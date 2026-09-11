"""Synthetic malformed-input tests plus real compiler-produced Mach-O fixtures."""
import importlib.util
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check_moltenvk.py"
spec = importlib.util.spec_from_file_location("check_moltenvk", SCRIPT)
mvk = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mvk
spec.loader.exec_module(mvk)


def macho(platform=2, minimum=0x110400, cpu=mvk.ARM64, command=None):
    command = command or struct.pack("<6I", 0x32, 24, platform, minimum, 0x120000, 0)
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 1, 1, len(command), 0, 0) + command


def ar_member(name, data):
    header = (f"{name:<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n").encode()
    assert len(header) == 60
    return header + data + (b"\n" if len(data) % 2 else b"")


def archive(*members):
    return b"!<arch>\n" + b"".join(ar_member(name, data) for name, data in members)


def fat(data, cpu=mvk.ARM64, is_64=False):
    entry_size = 32 if is_64 else 20
    header = struct.pack(">2I", 0xCAFEBABF if is_64 else 0xCAFEBABE, 1)
    fmt = ">2I2Q2I" if is_64 else ">5I"
    args = (cpu, 0, 8 + entry_size, len(data), 0, 0) if is_64 else (cpu, 0, 8 + entry_size, len(data), 0)
    return header + struct.pack(fmt, *args) + data


class MoltenVKValidationTests(unittest.TestCase):
    def test_device(self):
        self.assertEqual(len(mvk.validate_library(macho(), "device", "17.4")), 1)

    def test_simulator(self):
        self.assertEqual(len(mvk.validate_library(macho(7), "simulator", "17.4")), 1)

    def test_wrong_platform(self):
        for platform, target in ((1, "device"), (7, "device"), (2, "simulator"), (6, "device")):
            with self.subTest(platform=platform, target=target), self.assertRaises(mvk.ValidationError):
                mvk.validate_library(macho(platform), target)

    def test_wrong_architecture(self):
        with self.assertRaisesRegex(mvk.ValidationError, "expected ARM64"):
            mvk.validate_library(macho(cpu=0x01000007), "device")

    def test_arm64e_rejected(self):
        data = bytearray(macho())
        struct.pack_into("<I", data, 8, 2)
        with self.assertRaisesRegex(mvk.ValidationError, "arm64e"):
            mvk.validate_library(data, "device")

    def test_high_minimum_os(self):
        with self.assertRaisesRegex(mvk.ValidationError, "above deployment"):
            mvk.validate_library(macho(minimum=0x120000), "device", "17.4")

    def test_old_minimum_os(self):
        self.assertEqual(len(mvk.validate_library(macho(minimum=0x0E0000), "device", "17.4")), 1)

    def test_legacy_iphoneos(self):
        command = struct.pack("<4I", 0x25, 16, 0x0C0000, 0x0D0000)
        self.assertEqual(len(mvk.validate_library(macho(command=command), "device", "17.4")), 1)
        with self.assertRaises(mvk.ValidationError):
            mvk.validate_library(macho(command=command), "simulator")

    def test_missing_platform_metadata(self):
        command = struct.pack("<2I", 0x99, 8)
        with self.assertRaisesRegex(mvk.ValidationError, "missing or ambiguous"):
            mvk.validate_library(macho(command=command), "device")

    def test_truncated_load_commands(self):
        for count in range(56):
            with self.subTest(bytes=count), self.assertRaises(mvk.ValidationError):
                mvk.validate_library(macho()[:count], "device")

    def test_invalid_command_length(self):
        for size in (0, 4, 12, 0xFFFFFFFF):
            command = struct.pack("<6I", 0x32, size, 2, 0x110400, 0, 0)
            with self.subTest(size=size), self.assertRaises(mvk.ValidationError):
                mvk.validate_library(macho(command=command), "device")

    def test_truncated_build_tools(self):
        command = struct.pack("<6I", 0x32, 24, 2, 0x110400, 0, 9)
        with self.assertRaisesRegex(mvk.ValidationError, "build-tool"):
            mvk.validate_library(macho(command=command), "device")

    def test_archive_multiple_objects(self):
        data = archive(("one.o/", macho()), ("two.o/", macho()))
        self.assertEqual(len(mvk.validate_library(data, "device")), 2)

    def test_mixed_archive_rejects_wrong_second_object(self):
        data = archive(("one.o/", macho()), ("two.o/", macho(7)))
        with self.assertRaisesRegex(mvk.ValidationError, "two.o"):
            mvk.validate_library(data, "device")

    def test_bsd_extended_filename_and_symbols(self):
        name = b"very_long_filename.o\0"
        data = archive((f"#1/{len(name)}", name + macho()), ("__.SYMDEF/", b"symbol table"))
        self.assertEqual(len(mvk.validate_library(data, "device")), 1)

    def test_gnu_extended_filename_and_symbols(self):
        data = archive(("/", b"symbol table"), ("//", b"very_long_filename.o/\n"), ("/0", macho()))
        self.assertEqual(len(mvk.validate_library(data, "device")), 1)

    def test_gnu_bad_filename_offset(self):
        with self.assertRaisesRegex(mvk.ValidationError, "filename offset"):
            mvk.validate_library(archive(("/9999", macho())), "device")

    def test_archive_missing_padding(self):
        data = archive(("__.SYMDEF/", b"x"))[:-1]
        with self.assertRaisesRegex(mvk.ValidationError, "padding"):
            mvk.validate_library(data, "device")

    def test_archive_invalid_size(self):
        data = bytearray(archive(("one.o/", macho())))
        data[8 + 48:8 + 58] = b"-1        "
        with self.assertRaisesRegex(mvk.ValidationError, "member size"):
            mvk.validate_library(data, "device")

    def test_archive_empty(self):
        with self.assertRaisesRegex(mvk.ValidationError, "no ARM64"):
            mvk.validate_library(archive(), "device")

    def test_fat_library_and_fat_archive(self):
        for is_64 in (False, True):
            for data in (macho(), archive(("one.o/", macho()))):
                with self.subTest(is_64=is_64, archive=data[:8] == b"!<arch>\n"):
                    self.assertEqual(len(mvk.validate_library(fat(data, is_64=is_64), "device")), 1)

    def test_fat_wrong_platform(self):
        with self.assertRaises(mvk.ValidationError):
            mvk.validate_library(fat(macho(7)), "device")

    def test_fat_missing_arm64(self):
        with self.assertRaisesRegex(mvk.ValidationError, "no ARM64 slice"):
            mvk.validate_library(fat(macho(), cpu=0x01000007), "device")

    def test_fat_truncated_and_overflowing_offsets(self):
        for count in range(28):
            with self.subTest(count=count), self.assertRaises(mvk.ValidationError):
                mvk.validate_library(fat(macho())[:count], "device")
        data = bytearray(fat(macho()))
        struct.pack_into(">I", data, 16, 0xFFFFFFFF)
        with self.assertRaisesRegex(mvk.ValidationError, "slice bounds"):
            mvk.validate_library(data, "device")

    def test_deep_nesting_rejected(self):
        data = macho()
        for _ in range(9):
            data = fat(data)
        with self.assertRaisesRegex(mvk.ValidationError, "nested"):
            mvk.validate_library(data, "device")

    def test_invalid_version_strings(self):
        for value in ("", "17.x", "-1", "1.2.3.4", "17.999", "999999.0"):
            with self.subTest(value=value), self.assertRaises(mvk.ValidationError):
                mvk.os_version(value)

    def test_cli_missing_file_fails_clearly(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--library", "/nonexistent/MoltenVK.a",
                                 "--platform", "device"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("MoltenVK validation failed", result.stderr)

    @unittest.skipUnless(shutil.which("clang") and shutil.which("llvm-ar"), "clang and llvm-ar are needed for real Mach-O fixtures")
    def test_real_clang_target_objects_and_archives(self):
        # These are actual target object files, but do not link or run an iOS app.
        with tempfile.TemporaryDirectory(prefix="rpcs3-macho-") as directory:
            root = Path(directory)
            source = root / "probe.c"
            source.write_text("int rpcs3_mvk_target_probe(void) { return 3; }\n")
            for target, expected in (("arm64-apple-ios17.4", "device"),
                                     ("arm64-apple-ios17.4-simulator", "simulator"),
                                     ("arm64-apple-macos14.0", None)):
                obj = root / (target + ".o")
                lib = root / (target + ".a")
                subprocess.run([shutil.which("clang"), "-target", target, "-c", str(source), "-o", str(obj)],
                               check=True, capture_output=True, text=True)
                subprocess.run([shutil.which("llvm-ar"), "rcs", str(lib), str(obj)], check=True,
                               capture_output=True, text=True)
                for data in (obj.read_bytes(), lib.read_bytes()):
                    for platform in ("device", "simulator"):
                        with self.subTest(target=target, platform=platform, archive=data[:8] == b"!<arch>\n"):
                            if platform == expected:
                                self.assertEqual(len(mvk.validate_library(data, platform, "17.4")), 1)
                            else:
                                with self.assertRaises(mvk.ValidationError):
                                    mvk.validate_library(data, platform, "17.4")


if __name__ == "__main__":
    unittest.main()
