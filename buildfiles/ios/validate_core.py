#!/usr/bin/env python3
"""Host-independent structural checks for RPCS3Core.framework.

These checks prove source and build-graph consistency only. They do not compile,
link, sign, launch, or execute the iOS target.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

REQUIRED_FILES = (
    "3rdparty/ios/libusb/include/libusb.h",
    "3rdparty/ios/libusb/libusb_stub.cpp",
    "3rdparty/ios/rtmidi/include/rtmidi_c.h",
    "3rdparty/ios/rtmidi/rtmidi_stub.cpp",
    "buildfiles/ios/create_core_xcframework.sh",
    "rpcs3/ios/CoreAnchor.cpp",
    "rpcs3/ios/CoreLink.cpp",
    "rpcs3/ios/CoreLinkMain.mm",
    "rpcs3/ios/IOSCoreDefaults.h",
    "rpcs3/ios/IOSCoreDefaults.cpp",
    "rpcs3/ios/IOSCoreEmulator.h",
    "rpcs3/ios/IOSCoreEmulator.mm",
    "rpcs3/ios/IOSCoreGSFrame.h",
    "rpcs3/ios/IOSCoreGSFrame.mm",
    "rpcs3/ios/IOSCoreLifecycle.h",
    "rpcs3/ios/IOSCoreLifecycle.cpp",
    "rpcs3/ios/IOSCoreMouseGyro.cpp",
    "rpcs3/ios/RPCS3Core.h",
    "rpcs3/ios/RPCS3Core.mm",
    "rpcs3/ios/RPCS3Core.exports",
    "rpcs3/ios/RPCS3Core.modulemap",
    "rpcs3/ios/RPCS3Core-Info.plist.in",
)

PUBLIC_BOOT_ENUMS = (
    "RPCS3_IOS_BOOT_SUCCESS",
    "RPCS3_IOS_BOOT_GENERIC_ERROR",
    "RPCS3_IOS_BOOT_NOTHING_TO_BOOT",
    "RPCS3_IOS_BOOT_WRONG_DISC_LOCATION",
    "RPCS3_IOS_BOOT_INVALID_FILE_OR_FOLDER",
    "RPCS3_IOS_BOOT_INVALID_BDVD_FOLDER",
    "RPCS3_IOS_BOOT_INSTALL_FAILED",
    "RPCS3_IOS_BOOT_DECRYPTION_ERROR",
    "RPCS3_IOS_BOOT_FILE_CREATION_ERROR",
    "RPCS3_IOS_BOOT_FIRMWARE_MISSING",
    "RPCS3_IOS_BOOT_FIRMWARE_TOO_OLD",
    "RPCS3_IOS_BOOT_UNSUPPORTED_DISC_TYPE",
    "RPCS3_IOS_BOOT_SAVESTATE_CORRUPTED",
    "RPCS3_IOS_BOOT_SAVESTATE_VERSION_UNSUPPORTED",
    "RPCS3_IOS_BOOT_STILL_RUNNING",
    "RPCS3_IOS_BOOT_ALREADY_ADDED",
    "RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED",
    "RPCS3_IOS_BOOT_DATABASE_CONFIG_MISSING",
)

CORE_IMPLEMENTATION_FILES = (
    "rpcs3/ios/RPCS3Core.mm",
    "rpcs3/ios/IOSCoreEmulator.mm",
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def validate_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        require(errors, (ROOT / relative).is_file(), f"missing core source: {relative}")

    for obsolete in ("rpcs3/ios/IOSHeadlessCore.h", "rpcs3/ios/IOSHeadlessCore.cpp"):
        require(errors, not (ROOT / obsolete).exists(), f"duplicate lifecycle bridge must remain removed: {obsolete}")


def public_functions(header: str) -> set[str]:
    return set(re.findall(
        r"RPCS3_IOS_CORE_EXPORT\s+[\w\s\*]+?\s+(rpcs3_ios_core_[a-z0-9_]+)\s*\(",
        header,
        flags=re.MULTILINE,
    ))


def validate_public_api(errors: list[str]) -> None:
    header = read("rpcs3/ios/RPCS3Core.h")
    exports = {
        line.strip().removeprefix("_")
        for line in read("rpcs3/ios/RPCS3Core.exports").splitlines()
        if line.strip().startswith("_rpcs3_ios_core_")
    }
    implementations = "\n".join(read(relative) for relative in CORE_IMPLEMENTATION_FILES)
    declarations = public_functions(header)

    require(errors, bool(declarations), "RPCS3Core.h exposes no public core functions")
    for function in sorted(declarations):
        require(errors, function in exports, f"public function is missing from RPCS3Core.exports: {function}")
        require(
            errors,
            re.search(rf"\b{re.escape(function)}\s*\(", implementations) is not None,
            f"public function has no implementation: {function}",
        )

    for function in sorted(exports - declarations):
        errors.append(f"exported core function is not declared in RPCS3Core.h: {function}")

    for required in (
        "rpcs3_ios_core_initialize",
        "rpcs3_ios_core_shutdown",
        "rpcs3_ios_core_set_render_view",
        "rpcs3_ios_core_clear_render_view",
        "rpcs3_ios_core_has_render_view",
        "rpcs3_ios_core_import_path",
        "rpcs3_ios_core_boot_path",
        "rpcs3_ios_core_pause",
        "rpcs3_ios_core_resume",
        "rpcs3_ios_core_stop",
        "rpcs3_ios_core_restart",
        "rpcs3_ios_core_set_event_callback",
    ):
        require(errors, required in declarations, f"required lifecycle API is missing: {required}")

    for value, name in enumerate(PUBLIC_BOOT_ENUMS):
        require(
            errors,
            re.search(rf"\b{re.escape(name)}\s*=\s*{value}\b", header) is not None,
            f"public boot enum no longer mirrors game_boot_result at value {value}: {name}",
        )

    require(errors, "g_pending_import_source" in implementations, "import-size probing is not side-effect cached")
    require(errors, "RPCS3_IOS_CORE_BUFFER_TOO_SMALL" in implementations, "import buffer contract is missing")
    require(errors, "render view can be changed only while emulation is stopped" in implementations, "render-view mutation guard is missing")


def validate_link_graph(errors: list[str]) -> None:
    patch = read("rpcs3/ios/PatchCoreSources.cmake")
    core_cmake = read("rpcs3/CMakeLists.txt")
    dependencies = read("3rdparty/ios.cmake")

    for contract in (
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,rpcs3_emu>",
        "rpcs3_ios_core_framework",
        "FRAMEWORK TRUE",
        "RPCS3Core.exports",
        "RPCS3Core.modulemap",
        "XCODE_EMBED_FRAMEWORKS",
        "IOSCoreEmulator.mm",
        "IOSCoreGSFrame.mm",
        "IOSCoreLifecycle.cpp",
        "IOSCoreMouseGyro.cpp",
        "pad_thread_ios_core.cpp",
        "ios_gamecontroller_pad_handler.cpp",
        "product_info.cpp",
        "RPCS3_IOS_CORE=1",
        "3rdparty::vulkan",
        "XCODE_ATTRIBUTE_LD_GENERATE_MAP_FILE",
    ):
        require(errors, contract in patch, f"core framework link contract is missing: {contract}")

    for contract in (
        "-Wl,-force_load,$<TARGET_FILE:rpcs3_emu>",
        "rpcs3-ios-core-link",
        "3rdparty::ios_system",
    ):
        require(errors, contract in core_cmake, f"low-level final-link contract is missing: {contract}")

    for contract in (
        "add_library(3rdparty_libusb STATIC",
        "add_library(3rdparty_rtmidi STATIC",
        "add_library(3rdparty::ios_system ALIAS",
        "RPCS3_IOS_NO_USB_PASSTHROUGH",
        "RPCS3_IOS_NO_MIDI_INPUT",
        "RPCS3_IOS_AVFORMAT",
        "RPCS3_IOS_AVCODEC",
        "RPCS3_IOS_AVUTIL",
    ):
        require(errors, contract in dependencies, f"concrete iOS dependency contract is missing: {contract}")

    require(
        errors,
        dependencies.count('"${RPCS3_IOS_AVCODEC}"') >= 2,
        "static FFmpeg link closure no longer repeats avcodec",
    )
    require(
        errors,
        dependencies.count('"${RPCS3_IOS_AVUTIL}"') >= 2,
        "static FFmpeg link closure no longer repeats avutil",
    )


def validate_compatibility_abis(errors: list[str]) -> None:
    libusb_header = read("3rdparty/ios/libusb/include/libusb.h")
    libusb_source = read("3rdparty/ios/libusb/libusb_stub.cpp")
    rtmidi_header = read("3rdparty/ios/rtmidi/include/rtmidi_c.h")
    rtmidi_source = read("3rdparty/ios/rtmidi/rtmidi_stub.cpp")

    for function in (
        "libusb_init",
        "libusb_get_device_list",
        "libusb_get_device_descriptor",
        "libusb_open",
        "libusb_alloc_transfer",
        "libusb_submit_transfer",
        "libusb_cancel_transfer",
        "libusb_handle_events_timeout_completed",
    ):
        require(errors, function in libusb_header, f"libusb compatibility declaration is missing: {function}")
        require(errors, function in libusb_source, f"libusb compatibility implementation is missing: {function}")

    for field in ("status", "actual_length", "callback", "user_data", "iso_packet_desc"):
        require(errors, re.search(rf"\b{field}\b", libusb_header) is not None, f"libusb transfer ABI field is missing: {field}")

    for function in (
        "rtmidi_in_create_default",
        "rtmidi_in_free",
        "rtmidi_in_get_current_api",
        "rtmidi_in_get_message",
        "rtmidi_get_port_count",
        "rtmidi_get_port_name",
        "rtmidi_open_port",
        "rtmidi_close_port",
    ):
        require(errors, function in rtmidi_header, f"RtMidi compatibility declaration is missing: {function}")
        require(errors, function in rtmidi_source, f"RtMidi compatibility implementation is missing: {function}")


def validate_core_policy(errors: list[str]) -> None:
    defaults = read("rpcs3/ios/IOSCoreDefaults.cpp")
    configure = read("buildfiles/cmake/ConfigureIOS.cmake")
    handler_header = read("rpcs3/Input/ios_gamecontroller_pad_handler.h")
    emulator = read("rpcs3/ios/IOSCoreEmulator.mm")
    gs_frame = read("rpcs3/ios/IOSCoreGSFrame.mm")
    lifecycle = read("rpcs3/ios/IOSCoreLifecycle.cpp")
    consumer = read("rpcs3/ios/CoreLinkMain.mm")

    for contract in (
        "RPCS3_IOS_HAS_LLVM",
        "spu_decoder_type::asmjit",
        "microphone_handler::null",
        "camera_handler::null",
        "move_handler::null",
    ):
        require(errors, contract in defaults or contract in configure, f"core compatibility policy is missing: {contract}")

    require(errors, "using keyboard_pad_handler = NullPadHandler" in handler_header, "core keyboard factory is not Qt-free")
    require(errors, "named_thread<pad_thread>" in emulator, "core emulator does not initialize the iOS-safe pad thread")
    require(errors, "selected_core_renderer" in emulator, "render-host renderer selection is missing")
    require(errors, "named_thread<VKGSRender>" in emulator, "Vulkan renderer initialization is missing")
    require(errors, "named_thread<NullGSRender>" in emulator, "Null renderer fallback is missing")
    require(errors, "make_core_gs_frame" in emulator, "host GSFrame callback is missing")
    require(errors, "CAMetalLayer" in gs_frame, "core GSFrame is not backed by CAMetalLayer")
    require(errors, "set_core_render_view" in gs_frame, "core render-view storage is missing")
    require(errors, "rpcs3_ios_core_set_render_view" in consumer, "framework consumer does not attach its render view")
    require(errors, "CubebBackend" in emulator, "native audio backend contract is missing")
    require(errors, "pause_reason_inactive" in lifecycle, "inactive lifecycle pause tracking is missing")
    require(errors, "pause_reason_audio" in lifecycle, "audio lifecycle pause tracking is missing")
    require(errors, "install_core_lifecycle_callbacks" in lifecycle, "core lifecycle callback installation is missing")
    require(errors, "remove_core_lifecycle_callbacks" in lifecycle, "core lifecycle callback removal is missing")


def validate_packaging(errors: list[str]) -> None:
    script = read("buildfiles/ios/create_core_xcframework.sh")
    archive = read("buildfiles/ios/archive.sh")
    require(errors, script.startswith("#!/usr/bin/env bash\n"), "XCFramework helper lacks the expected Bash shebang")
    require(errors, "set -euo pipefail" in script, "XCFramework helper lacks strict mode")
    for contract in (
        "rpcs3_ios_core_framework",
        "iphoneos",
        "iphonesimulator",
        "-create-xcframework",
        "RPCS3Core.h",
        "lipo -archs",
    ):
        require(errors, contract in script, f"XCFramework packaging contract is missing: {contract}")

    for contract in (
        "rpcs3_ios_core_link",
        "Frameworks/RPCS3Core.framework",
        "RPCS3Core-device.framework",
    ):
        require(errors, contract in archive, f"core archive extraction contract is missing: {contract}")


def main() -> int:
    errors: list[str] = []
    validate_files(errors)
    validate_public_api(errors)
    validate_link_graph(errors)
    validate_compatibility_abis(errors)
    validate_core_policy(errors)
    validate_packaging(errors)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3 iOS core source/link contracts passed (no Apple build performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
