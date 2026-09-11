#!/usr/bin/env python3
"""Validate the ARM64 Mach-O platform of a caller-provided MoltenVK library.

Runs on any host; no Apple command-line tools or third-party packages required.
Accepts thin/fat dylibs and BSD/GNU ar archives, including fat archives. Checks
all selected ARM64 object members, not just the first member or CPU name.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import struct
import sys
from typing import List, Optional, Tuple

ARM64 = 0x0100000C
PLATFORMS = {"device": 2, "simulator": 7}


class ValidationError(ValueError):
    """A library is malformed, unidentifiable, or incompatible with the target."""


@dataclass(frozen=True)
class ObjectInfo:
    name: str
    platform: int
    minimum_os: int


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def _thin(data: bytes, label: str) -> List[ObjectInfo]:
    endian = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}.get(data[:4])
    _require(endian is not None and len(data) >= 32, f"{label}: not a complete 64-bit Mach-O object")
    _, cpu, subtype, file_type, commands, command_bytes, _, _ = struct.unpack_from(endian + "8I", data)
    _require(cpu == ARM64, f"{label}: expected ARM64, found CPU type 0x{cpu:x}")
    _require((subtype & 0x00FFFFFF) != 2, f"{label}: arm64e is not the generic arm64 target")
    _require(file_type in (1, 6), f"{label}: expected an object file or dylib")
    _require(command_bytes <= len(data) - 32 and commands <= command_bytes // 8,
             f"{label}: truncated load-command table")
    end = 32 + command_bytes
    offset = 32
    versions: List[Tuple[int, int]] = []
    for _ in range(commands):
        _require(offset + 8 <= end, f"{label}: truncated load command")
        command, size = struct.unpack_from(endian + "2I", data, offset)
        _require(size >= 8 and size % 8 == 0 and size <= end - offset,
                 f"{label}: invalid load-command size")
        if command == 0x32:  # LC_BUILD_VERSION
            _require(size >= 24, f"{label}: truncated LC_BUILD_VERSION")
            platform, minimum, _, tools = struct.unpack_from(endian + "4I", data, offset + 8)
            _require(tools <= (size - 24) // 8, f"{label}: truncated build-tool list")
            versions.append((platform, minimum))
        elif command in (0x24, 0x25, 0x2F, 0x30):  # legacy minimum OS commands
            _require(size >= 16, f"{label}: truncated minimum-OS command")
            minimum = struct.unpack_from(endian + "I", data, offset + 8)[0]
            versions.append(({0x24: 1, 0x25: 2, 0x2F: 3, 0x30: 4}[command], minimum))
        offset += size
    _require(offset == end, f"{label}: inconsistent load-command count/size")
    _require(len(versions) == 1, f"{label}: missing or ambiguous Apple platform metadata")
    return [ObjectInfo(label, *versions[0])]


def _archive(data: bytes, label: str, depth: int) -> List[ObjectInfo]:
    offset = 8
    long_names = b""
    result: List[ObjectInfo] = []
    while offset < len(data):
        _require(len(data) - offset >= 60, f"{label}: truncated archive header")
        header = data[offset:offset + 60]
        _require(header[58:60] == b"`\n", f"{label}: bad archive member header")
        raw_size = header[48:58].strip()
        _require(raw_size.isdigit(), f"{label}: invalid archive member size")
        size = int(raw_size)
        offset += 60
        _require(size <= len(data) - offset, f"{label}: truncated archive member")
        member = data[offset:offset + size]
        name = header[:16].decode("ascii", errors="replace").strip()
        if name.startswith("#1/"):  # BSD extended filename
            length_text = name[3:]
            _require(length_text.isdigit(), f"{label}: bad extended archive filename")
            length = int(length_text)
            _require(length <= len(member), f"{label}: truncated extended filename")
            name = member[:length].rstrip(b"\0").decode("utf-8", errors="replace")
            member = member[length:]
        elif name.startswith("/") and name[1:].isdigit():
            index = int(name[1:])
            _require(index < len(long_names), f"{label}: invalid GNU filename offset")
            finish = long_names.find(b"\n", index)
            _require(finish >= index, f"{label}: unterminated GNU filename")
            name = long_names[index:finish].rstrip(b"/").decode("utf-8", errors="replace")
        if name == "//":
            long_names = member
        elif name not in ("/", "/SYM64/") and not name.rstrip("/").startswith("__.SYMDEF"):
            result.extend(_inspect(member, f"{label}({name.rstrip('/')})", depth + 1))
        offset += size
        if size & 1:
            _require(offset < len(data) and data[offset:offset + 1] == b"\n",
                     f"{label}: missing archive padding")
            offset += 1
    _require(bool(result), f"{label}: no ARM64 object members")
    return result


def _inspect(data: bytes, label: str, depth: int = 0) -> List[ObjectInfo]:
    _require(depth < 8, f"{label}: too many nested archive/fat containers")
    if data.startswith(b"!<arch>\n"):
        return _archive(data, label, depth)
    fat = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
           b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}.get(data[:4])
    if fat:
        _require(len(data) >= 8, f"{label}: truncated fat header")
        endian, is_64 = fat
        count = struct.unpack_from(endian + "I", data, 4)[0]
        entry_size = 32 if is_64 else 20
        _require(count <= (len(data) - 8) // entry_size, f"{label}: truncated fat architecture table")
        selected: List[ObjectInfo] = []
        for index in range(count):
            entry = 8 + index * entry_size
            cpu = struct.unpack_from(endian + "I", data, entry)[0]
            start, size = struct.unpack_from(endian + ("2Q" if is_64 else "2I"), data, entry + 8)
            _require(start >= 8 + count * entry_size and start <= len(data) and size <= len(data) - start,
                     f"{label}: invalid fat slice bounds")
            if cpu == ARM64:
                selected.extend(_inspect(data[start:start + size], label + "[arm64]", depth + 1))
        _require(bool(selected), f"{label}: no ARM64 slice")
        return selected
    return _thin(data, label)


def os_version(text: str) -> int:
    parts = text.split(".")
    if not 1 <= len(parts) <= 3 or not all(part.isdigit() for part in parts):
        raise ValidationError(f"Invalid deployment target: {text}")
    values = [int(part) for part in parts] + [0] * (3 - len(parts))
    if values[0] > 65535 or any(value > 255 for value in values[1:]):
        raise ValidationError(f"Invalid deployment target: {text}")
    return (values[0] << 16) | (values[1] << 8) | values[2]


def version_string(version: int) -> str:
    return f"{version >> 16}.{(version >> 8) & 255}.{version & 255}"


def validate_library(data: bytes, platform: str, deployment_target: Optional[str] = None,
                     label: str = "MoltenVK") -> List[ObjectInfo]:
    if platform not in PLATFORMS:
        raise ValidationError(f"Unknown target platform: {platform}")
    objects = _inspect(bytes(data), label)
    target = os_version(deployment_target) if deployment_target else None
    for item in objects:
        _require(item.platform == PLATFORMS[platform],
                 f"{item.name}: platform {item.platform}, expected {PLATFORMS[platform]} ({platform}); "
                 "ARM64 macOS, iPhoneOS and iPhoneSimulator are not interchangeable")
        if target is not None:
            _require(item.minimum_os <= target,
                     f"{item.name}: requires OS {version_string(item.minimum_os)}, "
                     f"above deployment target {deployment_target}")
    return objects


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--platform", required=True, choices=tuple(PLATFORMS))
    parser.add_argument("--deployment-target")
    args = parser.parse_args()
    try:
        objects = validate_library(args.library.read_bytes(), args.platform, args.deployment_target,
                                   str(args.library))
        newest = max(item.minimum_os for item in objects)
    except (OSError, ValidationError) as error:
        print(f"MoltenVK validation failed: {error}", file=sys.stderr)
        return 1
    print(f"MoltenVK: {len(objects)} ARM64 Mach-O object(s), {args.platform}, "
          f"highest minimum OS {version_string(newest)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
