#!/usr/bin/env python3
"""Static validation for the iOS port that does not require Xcode.

This deliberately checks source invariants only. It does not claim that an iOS
SDK build, application launch, JIT execution, or emulator workload succeeds.
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
    "3rdparty/ios.cmake",
    "buildfiles/cmake/ConfigureIOS.cmake",
    "buildfiles/ios/configure.sh",
    "buildfiles/ios/build_ffmpeg.sh",
    "buildfiles/ios/build_llvm.sh",
    "buildfiles/ios/create_core_xcframework.sh",
    "buildfiles/ios/validate_environment.sh",
    "buildfiles/ios/validate_sources.py",
    "buildfiles/ios/validate_core.py",
    "buildfiles/ios/archive.sh",
    "buildfiles/ios/deploy.sh",
    "buildfiles/ios/report_signing.sh",
    "rpcs3/ios/CMakeLists.txt",
    "rpcs3/ios/PatchCoreSources.cmake",
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

PLISTS = (
    "rpcs3/ios/Info.plist.in",
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

FORBIDDEN_PRIVATE_MOLTENVK_FLAGS = (
    "MVK_CONFIG_USE_METAL_PRIVATE_API",
    "MVK_CONFIG_METAL_COMPILE_TIMEOUT",
    "MTL_DEBUG_LAYER",
)

FORBIDDEN_PRIVATE_APIS = (
    "SpringBoardServices",
    "SBSLaunchApplicationWithIdentifier",
    "MobileGestalt",
    "com.apple.private",
)

ANCHORS = {
    "Utilities/File.cpp": (
        "// App bundle directory is three levels up from the binary.",
        "return get_parent_dir(bin_path, 3);",
    ),
    "rpcs3/util/vm_native.cpp": (
        '#include "util/asm.hpp"',
        "void memory_commit(void* pointer, usz size, protection prot)",
        "void memory_reset(void* pointer, usz size, protection prot",
        "void memory_protect(void* pointer, usz size, protection prot)",
        "ensure(::mprotect(",
    ),
    "rpcs3/rpcs3.cpp": (
        '#include "Emu/savestate_utils.hpp"',
        'app->setOrganizationName("RPCS3");',
    ),
    "rpcs3/rpcs3qt/gs_frame.cpp": (
        '#include "Input/pad_thread.h"',
        "load_gui_settings();",
        "gs_frame::~gs_frame()",
    ),
    "rpcs3/Input/pad_thread.cpp": (
        '#include "keyboard_pad_handler.h"',
        "case pad_handler::move:",
        "return std::make_shared<ps_move_handler>();",
    ),
    "rpcs3/Input/gui_pad_thread.cpp": (
        '#include "gui_pad_thread.h"',
        "case pad_handler::dualsense:",
        "return std::make_shared<dualsense_pad_handler>();",
    ),
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def validate_required_files(root: Path, errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        if not (root / relative).is_file():
            fail(errors, f"missing required iOS source: {relative}")


def validate_plists(root: Path, errors: list[str]) -> None:
    for relative in PLISTS:
        path = root / relative
        try:
            with path.open("rb") as stream:
                value = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException) as error:
            fail(errors, f"invalid plist {relative}: {error}")
            continue

        if not isinstance(value, dict):
            fail(errors, f"plist root is not a dictionary: {relative}")
            continue

        forbidden = FORBIDDEN_ENTITLEMENTS.intersection(value)
        if forbidden:
            fail(errors, f"forbidden private entitlement(s) in {relative}: {sorted(forbidden)}")

    info_path = root / "rpcs3/ios/Info.plist.in"
    if info_path.is_file():
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        for key in (
            "CFBundleIdentifier",
            "CFBundleExecutable",
            "UISupportedInterfaceOrientations",
            "GCSupportsControllerUserInteraction",
            "LSApplicationQueriesSchemes",
            "NSLocalNetworkUsageDescription",
        ):
            if key not in info:
                fail(errors, f"Info.plist is missing {key}")

        schemes = set(info.get("LSApplicationQueriesSchemes", []))
        for scheme in ("apple-magnifier", "stikjit"):
            if scheme not in schemes:
                fail(errors, f"Info.plist is missing the public JIT provider scheme {scheme!r}")


def validate_shell_scripts(root: Path, errors: list[str]) -> None:
    for relative in SHELL_SCRIPTS:
        text = (root / relative).read_text(encoding="utf-8")
        if not text.startswith("#!/usr/bin/env bash\n"):
            fail(errors, f"shell helper lacks the expected Bash shebang: {relative}")
        if "set -euo pipefail" not in text:
            fail(errors, f"shell helper lacks strict mode: {relative}")
        if "mapfile" in text or "readarray" in text:
            fail(errors, f"shell helper uses a Bash feature absent from macOS system Bash: {relative}")


def validate_patch_anchors(root: Path, errors: list[str]) -> None:
    for relative, anchors in ANCHORS.items():
        path = root / relative
        if not path.is_file():
            fail(errors, f"patch source is missing: {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        for anchor in anchors:
            if anchor not in text:
                fail(errors, f"generated-source anchor moved in {relative}: {anchor!r}")


def validate_cmake_contracts(root: Path, errors: list[str]) -> None:
    root_cmake = (root / "CMakeLists.txt").read_text(encoding="utf-8")
    for contract in (
        "RPCS3_IOS_BOOTSTRAP_ONLY",
        "3rdparty/ios.cmake",
        "PatchCoreSources.cmake",
    ):
        if contract not in root_cmake:
            fail(errors, f"root CMake contract missing: {contract}")

    configure = (root / "buildfiles/cmake/ConfigureIOS.cmake").read_text(encoding="utf-8")
    for option in (
        "RPCS3_IOS_BUILD_QT_FRONTEND",
        "RPCS3_IOS_ENABLE_LLVM",
        "RPCS3_IOS_LLVM_ROOT",
        "RPCS3_IOS_ENTITLEMENTS_FILE",
    ):
        if option not in configure:
            fail(errors, f"iOS CMake option missing: {option}")

    dependencies = (root / "3rdparty/ios.cmake").read_text(encoding="utf-8")
    for contract in (
        "Vulkan_LIBRARY",
        "RPCS3_IOS_FFMPEG_ROOT",
        "3rdparty::vulkan",
        "3rdparty::ffmpeg",
    ):
        if contract not in dependencies:
            fail(errors, f"iOS dependency contract missing: {contract}")

    platform_cmake = (root / "rpcs3/ios/platform/CMakeLists.txt").read_text(encoding="utf-8")
    for contract in (
        "IOSJITProvider.mm",
        "IOSControllerFeatures.mm",
        "IOSControllerLight.mm",
        "IOSExternalDisplay.mm",
        "IOSMoltenVK.mm",
        "IOSDiagnostics.mm",
        "CoreHaptics",
        "CoreMotion",
    ):
        if contract not in platform_cmake:
            fail(errors, f"iOS platform build contract missing: {contract}")

    bootstrap_cmake = (root / "rpcs3/ios/CMakeLists.txt").read_text(encoding="utf-8")
    for contract in ("IOSBootstrapViewController.mm", "IOSVulkanProbe.mm"):
        if contract not in bootstrap_cmake:
            fail(errors, f"bootstrap build contract missing: {contract}")

    llvm_builder = (root / "buildfiles/ios/build_llvm.sh").read_text(encoding="utf-8")
    for contract in ("llvm-tblgen", "LLVM_TABLEGEN", "LLVMConfig.cmake", "CMAKE_SYSTEM_NAME=iOS"):
        if contract not in llvm_builder:
            fail(errors, f"LLVM cross-build contract missing: {contract}")


def validate_platform_contracts(root: Path, errors: list[str]) -> None:
    platform = (root / "rpcs3/ios/platform/IOSPlatform.h").read_text(encoding="utf-8")
    required_apis = (
        "allocate_jit_memory",
        "publish_jit_memory",
        "query_extended_jit_capabilities",
        "request_jit",
        "wait_for_jit_enablement",
        "get_combined_controller_motion",
        "set_combined_controller_rumble",
        "set_combined_controller_light",
        "get_external_display_state",
        "configure_moltenvk",
        "write_diagnostics_report",
    )
    for api in required_apis:
        if api not in platform:
            fail(errors, f"expanded iOS platform API missing: {api}")

    jit = (root / "rpcs3/ios/platform/IOSJIT.mm").read_text(encoding="utf-8")
    for contract in ("mach_vm_remap", "sys_icache_invalidate", "pthread_jit_write_protect_np"):
        if contract not in jit:
            fail(errors, f"JIT memory contract missing: {contract}")

    provider = (root / "rpcs3/ios/platform/IOSJITProvider.mm").read_text(encoding="utf-8")
    for contract in (
        "apple-magnifier://",
        "stikjit://enable-jit",
        "[fd00::]:9172/attach",
        "wait_for_jit_enablement",
    ):
        if contract not in provider:
            fail(errors, f"external JIT provider contract missing: {contract}")

    controller = (root / "rpcs3/ios/platform/IOSControllerFeatures.mm").read_text(encoding="utf-8")
    for contract in (
        "CoreMotion",
        "CoreHaptics",
        "GCHapticsLocalityAll",
        "deviceMotion",
        "normalize_hardware_controller_slots",
    ):
        if contract not in controller:
            fail(errors, f"controller feature contract missing: {contract}")

    controller_light = (root / "rpcs3/ios/platform/IOSControllerLight.mm").read_text(encoding="utf-8")
    for contract in ("GCDeviceLight", "GCColor", "set_hardware_controller_light"):
        if contract not in controller_light:
            fail(errors, f"controller light contract missing: {contract}")

    moltenvk = (root / "rpcs3/ios/platform/IOSMoltenVK.mm").read_text(encoding="utf-8")
    for forbidden in FORBIDDEN_PRIVATE_MOLTENVK_FLAGS:
        if forbidden in moltenvk:
            fail(errors, f"private or debug-only MoltenVK/Metal flag added: {forbidden}")

    ios_sources = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in (root / "rpcs3/ios").rglob("*")
        if path.is_file()
    )
    for forbidden in FORBIDDEN_PRIVATE_APIS:
        if forbidden in ios_sources:
            fail(errors, f"private Apple API or entitlement marker added to iOS sources: {forbidden}")

    patch = (root / "rpcs3/ios/PatchCoreSources.cmake").read_text(encoding="utf-8")
    for contract in (
        "if(TARGET rpcs3_emu)",
        "if(TARGET rpcs3_ui)",
        "set_jit_write_protection",
        "__builtin___clear_cache",
    ):
        if contract not in patch:
            fail(errors, f"generated iOS core adaptation missing: {contract}")


def validate_controller_contract(root: Path, errors: list[str]) -> None:
    enum_header = (root / "rpcs3/Emu/Io/pad_config_types.h").read_text(encoding="utf-8")
    enum_source = (root / "rpcs3/Emu/Io/pad_config_types.cpp").read_text(encoding="utf-8")
    handler = (root / "rpcs3/Input/ios_gamecontroller_pad_handler.cpp").read_text(encoding="utf-8")
    platform = (root / "rpcs3/ios/platform/IOSPlatform.h").read_text(encoding="utf-8")

    checks = (
        ("ios_gamecontroller", enum_header, "handler enum"),
        ("iOS GameController", enum_source, "handler serialization"),
        ("get_combined_controller_state", handler, "handler state source"),
        ("get_combined_controller_motion", handler, "motion integration"),
        ("set_combined_controller_rumble", handler, "rumble integration"),
        ("set_combined_controller_light", handler, "controller light integration"),
        ("get_battery_level", handler, "battery integration"),
        ("colorR.get()", handler, "RGB configuration integration"),
        ("attach_touch_controller_overlay", platform, "touch overlay API"),
    )
    for needle, haystack, description in checks:
        if needle not in haystack:
            fail(errors, f"missing {description}: {needle}")


def validate_no_claims_of_completion(root: Path, errors: list[str]) -> None:
    text = (root / "PORTING_IOS.md").read_text(encoding="utf-8").lower()
    suspicious = re.compile(r"\b(fully working|port complete|all games work|production ready)\b")
    match = suspicious.search(text)
    if match:
        fail(errors, f"PORTING_IOS.md makes an unsupported completion claim: {match.group(0)!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()

    errors: list[str] = []
    validate_required_files(root, errors)
    validate_plists(root, errors)
    validate_shell_scripts(root, errors)
    validate_patch_anchors(root, errors)
    validate_cmake_contracts(root, errors)
    validate_platform_contracts(root, errors)
    validate_controller_contract(root, errors)
    validate_no_claims_of_completion(root, errors)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("iOS source validation passed (host-independent checks only).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
