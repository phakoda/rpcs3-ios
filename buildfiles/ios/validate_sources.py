#!/usr/bin/env python3
"""Static validation for the iOS port that does not require Xcode.

This deliberately checks source invariants only. It does not claim an iOS SDK
build, application launch, installation, JIT execution, or workload succeeds.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path


REQUIRED_FILES = (
    "BUILDING_IOS.md",
    "PORTING_IOS.md",
    "IOS_CORE_API.md",
    ".github/workflows/ios-source-validation.yml",
    "3rdparty/ios.cmake",
    "3rdparty/ios/rtmidi/include/rtmidi_c.h",
    "3rdparty/ios/rtmidi/rtmidi_coremidi_v2.cpp",
    "buildfiles/cmake/ConfigureIOS.cmake",
    "buildfiles/ios/configure.sh",
    "buildfiles/ios/build_ffmpeg.sh",
    "buildfiles/ios/build_llvm.sh",
    "buildfiles/ios/create_core_xcframework.sh",
    "buildfiles/ios/validate_environment.sh",
    "buildfiles/ios/validate_sources.py",
    "buildfiles/ios/validate_core.py",
    "buildfiles/ios/validate_callbacks.py",
    "buildfiles/ios/archive.sh",
    "buildfiles/ios/deploy.sh",
    "buildfiles/ios/report_signing.sh",
    "rpcs3/ios/CMakeLists.txt",
    "rpcs3/ios/PatchCoreSources.cmake",
    "rpcs3/ios/PatchCoreHost.cmake",
    "rpcs3/ios/CoreExtensions.cmake",
    "rpcs3/ios/IOSCoreInstallerTransaction.cpp",
    "rpcs3/ios/IOSCoreLifecycleDeferred.mm",
    "rpcs3/ios/IOSCoreMIDIIdentity.mm",
    "rpcs3/ios/IOSCoreOperations.cpp",
    "rpcs3/ios/RPCS3CoreStatus.h",
    "rpcs3/ios/IOSBootstrapViewController.h",
    "rpcs3/ios/IOSBootstrapViewController.mm",
    "rpcs3/ios/IOSVulkanProbe.h",
    "rpcs3/ios/IOSVulkanProbe.mm",
    "rpcs3/ios/platform/IOSPlatform.h",
    "rpcs3/ios/platform/IOSPlatform.mm",
    "rpcs3/ios/platform/IOSJIT.mm",
    "rpcs3/ios/platform/IOSJITProvider.mm",
    "rpcs3/ios/platform/IOSPerformance.mm",
    "rpcs3/ios/platform/IOSControllerFeatures.h",
    "rpcs3/ios/platform/IOSControllerFeatures.mm",
    "rpcs3/ios/platform/IOSControllerLight.mm",
    "rpcs3/ios/platform/IOSExternalDisplay.mm",
    "rpcs3/ios/platform/IOSMoltenVK.mm",
    "rpcs3/ios/platform/IOSDiagnostics.mm",
    "rpcs3/ios/platform/IOSTouchController.mm",
    "rpcs3/ios/platform/IOSVirtualController.cpp",
    "rpcs3/Input/ios_gamecontroller_pad_handler.h",
    "rpcs3/Input/ios_gamecontroller_pad_handler.cpp",
)

OBSOLETE_FILES = (
    "3rdparty/ios/rtmidi/rtmidi_stub.cpp",
    "rpcs3/ios/IOSCoreLibrary.cpp",
    "rpcs3/ios/IOSHeadlessCore.h",
    "rpcs3/ios/IOSHeadlessCore.cpp",
)

PLISTS = (
    "rpcs3/ios/Info.plist.in",
    "rpcs3/ios/RPCS3Core-Info.plist.in",
    "rpcs3/ios/JIT.entitlements",
    "rpcs3/ios/Research.entitlements",
)

SHELL_SCRIPTS = (
    "buildfiles/ios/configure.sh",
    "buildfiles/ios/build_ffmpeg.sh",
    "buildfiles/ios/build_llvm.sh",
    "buildfiles/ios/create_core_xcframework.sh",
    "buildfiles/ios/validate_environment.sh",
    "buildfiles/ios/archive.sh",
    "buildfiles/ios/deploy.sh",
    "buildfiles/ios/report_signing.sh",
)

FORBIDDEN_ENTITLEMENTS = {
    "com.apple.private.security.no-sandbox",
    "com.apple.private.security.storage.AppBundles",
    "com.apple.private.security.storage.MobileDocuments",
    "com.apple.private.security.container-required",
}

FORBIDDEN_SOURCE_MARKERS = (
    "MVK_CONFIG_USE_METAL_PRIVATE_API",
    "MVK_CONFIG_METAL_COMPILE_TIMEOUT",
    "MTL_DEBUG_LAYER",
    "SpringBoardServices",
    "SBSLaunchApplicationWithIdentifier",
    "MobileGestalt",
    "com.apple.private.",
)

ANCHORS = {
    "Utilities/File.cpp": (
        "// App bundle directory is three levels up from the binary.",
        "return get_parent_dir(bin_path, 3);",
    ),
    "rpcs3/util/vm_native.cpp": (
        '#include "util/asm.hpp"',
        "void memory_commit(void* pointer, usz size, protection prot)",
        "void memory_protect(void* pointer, usz size, protection prot)",
    ),
    "rpcs3/Input/pad_thread.cpp": (
        '#include "keyboard_pad_handler.h"',
        "case pad_handler::move:",
    ),
}


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def validate_required_files(root: Path, errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        require(errors, (root / relative).is_file(), f"missing required iOS source: {relative}")
    for relative in OBSOLETE_FILES:
        require(errors, not (root / relative).exists(), f"obsolete iOS source must remain removed: {relative}")


def validate_plists(root: Path, errors: list[str]) -> None:
    parsed: dict[str, dict] = {}
    for relative in PLISTS:
        path = root / relative
        try:
            with path.open("rb") as stream:
                value = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException) as error:
            errors.append(f"invalid plist {relative}: {error}")
            continue
        require(errors, isinstance(value, dict), f"plist root is not a dictionary: {relative}")
        if not isinstance(value, dict):
            continue
        parsed[relative] = value
        forbidden = FORBIDDEN_ENTITLEMENTS.intersection(value)
        require(errors, not forbidden, f"forbidden private entitlement(s) in {relative}: {sorted(forbidden)}")

    info = parsed.get("rpcs3/ios/Info.plist.in", {})
    for key in (
        "CFBundleIdentifier", "CFBundleExecutable", "CFBundleDocumentTypes",
        "UTImportedTypeDeclarations", "UISupportedInterfaceOrientations",
        "GCSupportsControllerUserInteraction", "LSApplicationQueriesSchemes",
        "NSLocalNetworkUsageDescription",
    ):
        require(errors, key in info, f"Info.plist is missing {key}")
    require(errors, info.get("CFBundleShortVersionString") == "0.5", "app plist short version is not 0.5")
    require(errors, info.get("CFBundleVersion") == "5", "app plist bundle version is not 5")

    schemes = set(info.get("LSApplicationQueriesSchemes", []))
    for scheme in ("apple-magnifier", "stikjit"):
        require(errors, scheme in schemes, f"Info.plist is missing public JIT provider scheme {scheme!r}")

    claimed_types = {
        item
        for document in info.get("CFBundleDocumentTypes", [])
        for item in document.get("LSItemContentTypes", [])
    }
    require(errors, "public.data" not in claimed_types, "app must not register as a handler for every public.data file")
    require(errors, "public.folder" not in claimed_types, "app must not register as a handler for every folder")

    framework = parsed.get("rpcs3/ios/RPCS3Core-Info.plist.in", {})
    require(errors, framework.get("CFBundleShortVersionString") == "0.5", "RPCS3Core plist short version is not 0.5")
    require(errors, framework.get("CFBundleVersion") == "5", "RPCS3Core plist bundle version is not 5")


def validate_shell_scripts(root: Path, errors: list[str]) -> None:
    for relative in SHELL_SCRIPTS:
        text = (root / relative).read_text(encoding="utf-8")
        require(errors, text.startswith("#!/usr/bin/env bash\n"), f"shell helper lacks expected Bash shebang: {relative}")
        require(errors, "set -euo pipefail" in text, f"shell helper lacks strict mode: {relative}")
        require(errors, "mapfile" not in text and "readarray" not in text,
                f"shell helper uses a Bash feature absent from macOS system Bash: {relative}")


def validate_patch_anchors(root: Path, errors: list[str]) -> None:
    for relative, anchors in ANCHORS.items():
        path = root / relative
        require(errors, path.is_file(), f"patch source is missing: {relative}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for anchor in anchors:
            require(errors, anchor in text, f"generated-source anchor moved in {relative}: {anchor!r}")


def validate_cmake_contracts(root: Path, errors: list[str]) -> None:
    root_cmake = (root / "CMakeLists.txt").read_text(encoding="utf-8")
    for contract in (
        "RPCS3_IOS_BOOTSTRAP_ONLY", "3rdparty/ios.cmake",
        "PatchCoreSources.cmake", "CoreExtensions.cmake",
    ):
        require(errors, contract in root_cmake, f"root CMake contract missing: {contract}")

    extensions = (root / "rpcs3/ios/CoreExtensions.cmake").read_text(encoding="utf-8")
    for contract in (
        "IOSCoreOperations.cpp", "IOSCoreInstallerTransaction.cpp",
        "IOSCoreMIDIIdentity.mm", "IOSCoreMIDIComposition.mm",
        "rpcs3_ios_core_install_firmware_raw", "VERSION 0.5.0", "SOVERSION 0.5",
    ):
        require(errors, contract in extensions, f"core extension build contract missing: {contract}")

    configure = (root / "buildfiles/cmake/ConfigureIOS.cmake").read_text(encoding="utf-8")
    for option in (
        "RPCS3_IOS_BUILD_QT_FRONTEND", "RPCS3_IOS_ENABLE_LLVM",
        "RPCS3_IOS_LLVM_ROOT", "RPCS3_IOS_ENTITLEMENTS_FILE",
    ):
        require(errors, option in configure, f"iOS CMake option missing: {option}")

    dependencies = (root / "3rdparty/ios.cmake").read_text(encoding="utf-8")
    for contract in (
        "Vulkan_LIBRARY", "RPCS3_IOS_FFMPEG_ROOT", "3rdparty::vulkan",
        "3rdparty::ffmpeg", "RPCS3_IOS_COREMIDI", "rtmidi_coremidi.cpp",
    ):
        require(errors, contract in dependencies, f"iOS dependency contract missing: {contract}")
    require(errors, "RPCS3_IOS_NO_MIDI_INPUT" not in dependencies, "CoreMIDI build still declares MIDI unavailable")

    workflow = (root / ".github/workflows/ios-source-validation.yml").read_text(encoding="utf-8")
    for contract in (
        "apple-sdk-contracts", "iphonesimulator", "public-c.c",
        "rtmidi_coremidi_v2.cpp", "plutil -lint",
    ):
        require(errors, contract in workflow, f"Apple SDK contract workflow is missing: {contract}")


def validate_platform_contracts(root: Path, errors: list[str]) -> None:
    platform = (root / "rpcs3/ios/platform/IOSPlatform.h").read_text(encoding="utf-8")
    for api in (
        "allocate_jit_memory", "publish_jit_memory", "query_extended_jit_capabilities",
        "request_jit", "wait_for_jit_enablement", "get_combined_controller_motion",
        "set_combined_controller_rumble", "set_combined_controller_light",
        "get_external_display_state", "configure_moltenvk", "write_diagnostics_report",
    ):
        require(errors, api in platform, f"expanded iOS platform API missing: {api}")

    jit = (root / "rpcs3/ios/platform/IOSJIT.mm").read_text(encoding="utf-8")
    for contract in ("mach_vm_remap", "sys_icache_invalidate", "pthread_jit_write_protect_np"):
        require(errors, contract in jit, f"JIT memory contract missing: {contract}")

    provider = (root / "rpcs3/ios/platform/IOSJITProvider.mm").read_text(encoding="utf-8")
    for contract in ("apple-magnifier://", "stikjit://enable-jit", "[fd00::]:9172/attach", "wait_for_jit_enablement"):
        require(errors, contract in provider, f"external JIT provider contract missing: {contract}")

    controller = (root / "rpcs3/ios/platform/IOSControllerFeatures.mm").read_text(encoding="utf-8")
    for contract in ("CoreMotion", "CoreHaptics", "GCHapticsLocalityAll", "deviceMotion"):
        require(errors, contract in controller, f"controller feature contract missing: {contract}")

    moltenvk = (root / "rpcs3/ios/platform/IOSMoltenVK.mm").read_text(encoding="utf-8")
    for forbidden in FORBIDDEN_SOURCE_MARKERS[:3]:
        require(errors, forbidden not in moltenvk, f"private/debug-only MoltenVK flag added: {forbidden}")

    ios_sources = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in (root / "rpcs3/ios").rglob("*")
        if path.is_file()
    )
    for forbidden in FORBIDDEN_SOURCE_MARKERS[3:]:
        require(errors, forbidden not in ios_sources, f"private Apple API/entitlement marker added: {forbidden}")


def validate_docs(root: Path, errors: list[str]) -> None:
    combined = "\n".join((root / name).read_text(encoding="utf-8") for name in (
        "BUILDING_IOS.md", "PORTING_IOS.md", "IOS_CORE_API.md",
    ))
    for phrase in (
        "no Apple", "Xcode", "device", "simulator", "firmware", "frame presentation",
    ):
        require(errors, phrase.lower() in combined.lower(), f"documentation evidence boundary is missing: {phrase}")


def validate_no_diff_artifacts(root: Path, errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        path = root / relative
        if not path.is_file() or path.suffix not in {".cpp", ".h", ".mm", ".cmake", ".py", ".yml"}:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            require(errors, re.match(r"^\+\s{2,}", line) is None,
                    f"literal diff marker in {relative}:{number}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    arguments = parser.parse_args()
    root = arguments.root.resolve()

    errors: list[str] = []
    validate_required_files(root, errors)
    if not errors:
        validate_plists(root, errors)
        validate_shell_scripts(root, errors)
        validate_patch_anchors(root, errors)
        validate_cmake_contracts(root, errors)
        validate_platform_contracts(root, errors)
        validate_docs(root, errors)
        validate_no_diff_artifacts(root, errors)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3 iOS 0.5 source/plist/CMake/platform safety contracts passed (no Apple execution performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
