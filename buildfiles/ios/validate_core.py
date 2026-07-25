#!/usr/bin/env python3
"""Host-independent structural checks for RPCS3Core.framework.

These checks prove source and build-graph consistency only. They do not compile,
link, sign, launch, install firmware, or execute an iOS target or PS3 workload.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

REQUIRED_FILES = (
    "3rdparty/ios/libusb/include/libusb.h",
    "3rdparty/ios/libusb/libusb_stub.cpp",
    "3rdparty/ios/rtmidi/include/rtmidi_c.h",
    "3rdparty/ios/rtmidi/rtmidi_coremidi.cpp",
    "buildfiles/ios/create_core_xcframework.sh",
    "rpcs3/ios/CoreAnchor.cpp",
    "rpcs3/ios/CoreExtensions.cmake",
    "rpcs3/ios/CoreLink.cpp",
    "rpcs3/ios/CoreLinkMain.mm",
    "rpcs3/ios/IOSCoreDefaults.h",
    "rpcs3/ios/IOSCoreDefaults.cpp",
    "rpcs3/ios/IOSCoreEmulator.h",
    "rpcs3/ios/IOSCoreEmulator.mm",
    "rpcs3/ios/IOSCoreGSFrame.h",
    "rpcs3/ios/IOSCoreGSFrame.mm",
    "rpcs3/ios/IOSCoreInstaller.h",
    "rpcs3/ios/IOSCoreInstaller.cpp",
    "rpcs3/ios/IOSCoreInstallationStatus.cpp",
    "rpcs3/ios/IOSCoreLibrary.mm",
    "rpcs3/ios/IOSCoreLifecycle.h",
    "rpcs3/ios/IOSCoreLifecycle.cpp",
    "rpcs3/ios/IOSCoreMIDI.h",
    "rpcs3/ios/IOSCoreMIDI.mm",
    "rpcs3/ios/IOSCoreMouseGyro.cpp",
    "rpcs3/ios/IOSCoreSettings.h",
    "rpcs3/ios/IOSCoreSettings.mm",
    "rpcs3/ios/RPCS3Core.h",
    "rpcs3/ios/RPCS3Core.mm",
    "rpcs3/ios/RPCS3Core.exports",
    "rpcs3/ios/RPCS3Core.modulemap",
    "rpcs3/ios/RPCS3Core-Info.plist.in",
)

OBSOLETE_FILES = (
    "3rdparty/ios/rtmidi/rtmidi_stub.cpp",
    "rpcs3/ios/IOSCoreLibrary.cpp",
    "rpcs3/ios/IOSHeadlessCore.h",
    "rpcs3/ios/IOSHeadlessCore.cpp",
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
    "rpcs3/ios/IOSCoreEventCallback.mm",
    "rpcs3/ios/IOSCoreEmulator.mm",
    "rpcs3/ios/IOSCoreInstaller.cpp",
    "rpcs3/ios/IOSCoreInstallationStatus.cpp",
    "rpcs3/ios/IOSCoreLibrary.mm",
    "rpcs3/ios/IOSCoreMIDI.mm",
    "rpcs3/ios/IOSCoreSettings.mm",
)

REQUIRED_PUBLIC_APIS = (
    "rpcs3_ios_core_initialize",
    "rpcs3_ios_core_shutdown",
    "rpcs3_ios_core_set_render_view",
    "rpcs3_ios_core_clear_render_view",
    "rpcs3_ios_core_has_render_view",
    "rpcs3_ios_core_refresh_render_view",
    "rpcs3_ios_core_set_event_callback",
    "rpcs3_ios_core_import_path",
    "rpcs3_ios_core_boot_path",
    "rpcs3_ios_core_pause",
    "rpcs3_ios_core_resume",
    "rpcs3_ios_core_stop",
    "rpcs3_ios_core_restart",
    "rpcs3_ios_core_get_configuration",
    "rpcs3_ios_core_set_configuration",
    "rpcs3_ios_core_reset_configuration",
    "rpcs3_ios_core_add_game_directory",
    "rpcs3_ios_core_remove_game_directory",
    "rpcs3_ios_core_rescan_game_directories",
    "rpcs3_ios_core_prune_missing_game_directories",
    "rpcs3_ios_core_clear_game_directories",
    "rpcs3_ios_core_add_game",
    "rpcs3_ios_core_remove_game",
    "rpcs3_ios_core_game_count",
    "rpcs3_ios_core_copy_game",
    "rpcs3_ios_core_game_directory_count",
    "rpcs3_ios_core_copy_game_directory",
    "rpcs3_ios_core_midi_source_count",
    "rpcs3_ios_core_copy_midi_source",
    "rpcs3_ios_core_midi_slot_count",
    "rpcs3_ios_core_set_midi_assignment",
    "rpcs3_ios_core_clear_midi_assignment",
    "rpcs3_ios_core_copy_midi_assignment",
    "rpcs3_ios_core_clear_all_midi_assignments",
    "rpcs3_ios_core_install_firmware",
    "rpcs3_ios_core_install_package",
    "rpcs3_ios_core_request_installation_cancel",
    "rpcs3_ios_core_query_installation_status",
    "rpcs3_ios_core_copy_installation_detail",
    "rpcs3_ios_core_copy_firmware_version",
    "rpcs3_ios_core_copy_last_installed_path",
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def validate_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        require(errors, (ROOT / relative).is_file(), f"missing core source: {relative}")
    for obsolete in OBSOLETE_FILES:
        require(errors, not (ROOT / obsolete).exists(), f"obsolete iOS source must remain removed: {obsolete}")


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
    for required in REQUIRED_PUBLIC_APIS:
        require(errors, required in declarations, f"required public API is missing: {required}")

    for value, name in enumerate(PUBLIC_BOOT_ENUMS):
        require(
            errors,
            re.search(rf"\b{re.escape(name)}\s*=\s*{value}\b", header) is not None,
            f"public boot enum no longer mirrors game_boot_result at value {value}: {name}",
        )

    for value, name in enumerate((
        "RPCS3_IOS_MIDI_KEYBOARD",
        "RPCS3_IOS_MIDI_GUITAR_17_FRET",
        "RPCS3_IOS_MIDI_GUITAR_22_FRET",
        "RPCS3_IOS_MIDI_DRUMS",
    )):
        require(errors, re.search(rf"\b{name}\s*=\s*{value}\b", header) is not None,
                f"public MIDI enum is not stable at value {value}: {name}")

    for field in (
        "struct_size",
        "active",
        "cancel_requested",
        "kind",
        "stage",
        "completed",
        "total",
    ):
        require(errors, re.search(rf"typedef struct rpcs3_ios_installation_status[\s\S]*?\b{field}\b", header) is not None,
                f"installation status ABI field is missing: {field}")

    require(errors, "RPCS3_IOS_CORE_CANCELLED = 8" in header, "cancelled result value is missing")
    require(errors, "g_pending_import_source" in implementations, "import-size probing is not side-effect cached")
    require(errors, "RPCS3_IOS_CORE_BUFFER_TOO_SMALL" in implementations, "buffer-size contracts are missing")
    require(errors, "render view can be changed only while emulation is stopped" in implementations, "render-view mutation guard is missing")

    emulator = read("rpcs3/ios/IOSCoreEmulator.mm")
    require(errors, "g_event_generation" in emulator, "queued event callback generation guard is missing")
    require(errors, "generation != g_event_generation" in emulator, "stale queued events are not rejected")
    for operation in ("Pause failed", "Resume failed", "Stop failed", "Restart failed", "Boot failed"):
        require(errors, operation in emulator, f"public lifecycle exception boundary is missing: {operation}")


def validate_link_graph(errors: list[str]) -> None:
    root_cmake = read("CMakeLists.txt")
    patch = read("rpcs3/ios/PatchCoreSources.cmake")
    extensions = read("rpcs3/ios/CoreExtensions.cmake")
    core_cmake = read("rpcs3/CMakeLists.txt")
    dependencies = read("3rdparty/ios.cmake")

    require(errors, "CoreExtensions.cmake" in root_cmake, "root CMake does not include core extensions")
    for source in (
        "IOSCoreSettings.mm",
        "IOSCoreMIDI.mm",
        "IOSCoreLibrary.mm",
        "IOSCoreInstaller.cpp",
        "IOSCoreInstallationStatus.cpp",
    ):
        require(errors, source in extensions, f"core extension source is not linked: {source}")

    for contract in (
        "rpcs3_ios_core_install_firmware_base",
        "rpcs3_ios_core_install_package_base",
        "rpcs3_ios_core_request_installation_cancel_base",
        "VERSION 0.4.0",
        "SOVERSION 0.4",
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
        require(errors, contract in extensions or contract in patch, f"core framework link contract is missing: {contract}")

    for contract in (
        "-Wl,-force_load,$<TARGET_FILE:rpcs3_emu>",
        "rpcs3-ios-core-link",
        "3rdparty::ios_system",
    ):
        require(errors, contract in core_cmake, f"low-level final-link contract is missing: {contract}")

    for contract in (
        "add_library(3rdparty_libusb STATIC",
        "add_library(3rdparty_rtmidi STATIC",
        "rtmidi_coremidi.cpp",
        "RPCS3_IOS_COREMIDI",
        "add_library(3rdparty::ios_system ALIAS",
        "RPCS3_IOS_NO_USB_PASSTHROUGH",
        "RPCS3_IOS_AVFORMAT",
        "RPCS3_IOS_AVCODEC",
        "RPCS3_IOS_AVUTIL",
    ):
        require(errors, contract in dependencies, f"concrete iOS dependency contract is missing: {contract}")
    require(errors, "RPCS3_IOS_NO_MIDI_INPUT" not in dependencies, "CoreMIDI build still declares MIDI unavailable")
    require(errors, dependencies.count('"${RPCS3_IOS_AVCODEC}"') >= 2, "static FFmpeg closure no longer repeats avcodec")
    require(errors, dependencies.count('"${RPCS3_IOS_AVUTIL}"') >= 2, "static FFmpeg closure no longer repeats avutil")


def validate_compatibility_abis(errors: list[str]) -> None:
    libusb_header = read("3rdparty/ios/libusb/include/libusb.h")
    libusb_source = read("3rdparty/ios/libusb/libusb_stub.cpp")
    rtmidi_header = read("3rdparty/ios/rtmidi/include/rtmidi_c.h")
    rtmidi_source = read("3rdparty/ios/rtmidi/rtmidi_coremidi.cpp")

    for function in (
        "libusb_init", "libusb_get_device_list", "libusb_get_device_descriptor",
        "libusb_open", "libusb_alloc_transfer", "libusb_submit_transfer",
        "libusb_cancel_transfer", "libusb_handle_events_timeout_completed",
    ):
        require(errors, function in libusb_header, f"libusb compatibility declaration is missing: {function}")
        require(errors, function in libusb_source, f"libusb compatibility implementation is missing: {function}")

    for field in ("status", "actual_length", "callback", "user_data", "iso_packet_desc"):
        require(errors, re.search(rf"\b{field}\b", libusb_header) is not None, f"libusb transfer ABI field is missing: {field}")

    for function in (
        "rtmidi_in_create_default", "rtmidi_in_free", "rtmidi_in_get_current_api",
        "rtmidi_in_ignore_types", "rtmidi_in_get_message", "rtmidi_get_port_count",
        "rtmidi_get_port_name", "rtmidi_open_port", "rtmidi_close_port",
    ):
        require(errors, function in rtmidi_header, f"RtMidi declaration is missing: {function}")
        require(errors, function in rtmidi_source, f"CoreMIDI RtMidi implementation is missing: {function}")

    for contract in (
        "MIDIClientCreate",
        "MIDIInputPortCreate",
        "MIDIPortConnectSource",
        "MIDIPortDisconnectSource",
        "MIDIPacketNext",
        "running_status",
        "pending_size",
        "maximum_queued_messages",
        "mach_timebase_info",
    ):
        require(errors, contract in rtmidi_source, f"CoreMIDI input contract is missing: {contract}")


def validate_mobile_features(errors: list[str]) -> None:
    defaults = read("rpcs3/ios/IOSCoreDefaults.cpp")
    configure = read("buildfiles/cmake/ConfigureIOS.cmake")
    handler_header = read("rpcs3/Input/ios_gamecontroller_pad_handler.h")
    emulator = read("rpcs3/ios/IOSCoreEmulator.mm")
    gs_frame = read("rpcs3/ios/IOSCoreGSFrame.mm")
    lifecycle = read("rpcs3/ios/IOSCoreLifecycle.cpp")
    settings = read("rpcs3/ios/IOSCoreSettings.mm")
    midi = read("rpcs3/ios/IOSCoreMIDI.mm")
    library = read("rpcs3/ios/IOSCoreLibrary.mm")
    installer = read("rpcs3/ios/IOSCoreInstaller.cpp")
    installer_status = read("rpcs3/ios/IOSCoreInstallationStatus.cpp")
    core = read("rpcs3/ios/RPCS3Core.mm")
    consumer = read("rpcs3/ios/CoreLinkMain.mm")

    for contract in (
        "RPCS3_IOS_HAS_LLVM", "spu_decoder_type::asmjit", "microphone_handler::null",
        "camera_handler::null", "move_handler::null",
    ):
        require(errors, contract in defaults or contract in configure, f"core compatibility policy is missing: {contract}")

    require(errors, "using keyboard_pad_handler = NullPadHandler" in handler_header, "core keyboard factory is not Qt-free")
    require(errors, "named_thread<pad_thread>" in emulator, "core emulator does not initialize the iOS-safe pad thread")
    require(errors, "named_thread<VKGSRender>" in emulator, "Vulkan renderer initialization is missing")
    require(errors, "named_thread<NullGSRender>" in emulator, "Null renderer fallback is missing")
    require(errors, "CAMetalLayer" in gs_frame, "core GSFrame is not backed by CAMetalLayer")
    require(errors, "refresh_core_render_view" in gs_frame, "core drawable refresh is missing")
    require(errors, "CubebBackend" in emulator, "native audio backend contract is missing")
    require(errors, "pause_reason_inactive" in lifecycle, "inactive lifecycle pause tracking is missing")
    require(errors, "pause_reason_audio" in lifecycle, "audio lifecycle pause tracking is missing")

    for contract in (
        "NSUserDefaults", "RPCS3_IOS_CPU_PORTABLE", "resolution_scale_percent",
        "preferred_spu_threads", "mutation_allowed", "persist_configuration",
    ):
        require(errors, contract in settings, f"persistent settings contract is missing: {contract}")

    for contract in (
        "RPCS3Core.Library.GameDirectories",
        "stringByStandardizingPath",
        "Emu.AddGamesFromDir",
        "Emu.RemoveGamesFromDir",
        "Emu.AddGame",
        "Emu.RemoveGameFromYml",
        "GetGamesConfig().get_games",
        "rpcs3_ios_core_rescan_game_directories",
        "rpcs3_ios_core_prune_missing_game_directories",
        "rpcs3_ios_core_clear_game_directories",
    ):
        require(errors, contract in library, f"persistent game-library contract is missing: {contract}")
    require(errors, "GetGameDirs" not in library, "library roots incorrectly use current-title GetGameDirs semantics")

    for contract in (
        "RPCS3Core.MIDI.Assignments",
        "max_midi_devices == 3",
        'result += "ßßß"',
        'result += "@@@"',
        "MIDIGetNumberOfSources",
        "apply_core_midi_configuration",
        "rpcs3_ios_core_set_midi_assignment",
        "rpcs3_ios_core_clear_all_midi_assignments",
    ):
        require(errors, contract in midi, f"CoreMIDI assignment contract is missing: {contract}")
    require(errors, 'g_cfg.io.midi_devices = ""' not in defaults, "compatibility policy still clears CoreMIDI mappings")
    require(errors, "apply_core_midi_configuration" in defaults, "MIDI assignments are not reapplied before boot")

    for contract in (
        "pup_object", "SCEDecrypter", "package_reader::extract_data", 'vfs::mount("/dev_flash"',
        "abort_extract", "std::jthread", "std::exception_ptr", "shutdown_core_installer",
        "RPCS3_IOS_CORE_CANCELLED",
    ):
        require(errors, contract in installer, f"installer contract is missing: {contract}")

    for contract in (
        "begin_operation",
        "progress_trampoline",
        "finish_operation",
        "rpcs3_ios_core_install_firmware_base",
        "rpcs3_ios_core_install_package_base",
        "rpcs3_ios_core_request_installation_cancel_base",
        "rpcs3_ios_core_query_installation_status",
        "rpcs3_ios_core_copy_installation_detail",
        "g_status.cancel_requested = 1",
    ):
        require(errors, contract in installer_status, f"installer status contract is missing: {contract}")

    require(errors, "g_initialized.exchange(false)" in core, "shutdown does not close operation admission before drain")
    require(errors, "load_core_configuration" in core, "persistent settings are not loaded during core initialization")
    require(errors, "shutdown_core_installer" in core, "installer is not drained during core teardown")
    require(errors, "RPCS3CoreVersionNumber = 0.4" in core, "public framework runtime version is not 0.4")
    require(errors, core.count("apply_core_compatibility_defaults();") >= 3,
            "render attachment or initialization does not synchronize compatibility state")

    for contract in (
        "rpcs3_ios_core_set_render_view", "rpcs3_ios_core_install_firmware",
        "rpcs3_ios_core_install_package", "rpcs3_ios_core_add_game_directory",
        "rpcs3_ios_core_copy_game", "rpcs3_ios_core_set_configuration",
        "rpcs3_ios_core_request_installation_cancel", "UIActivityViewController",
    ):
        require(errors, contract in consumer, f"native management host contract is missing: {contract}")


def validate_packaging(errors: list[str]) -> None:
    script = read("buildfiles/ios/create_core_xcframework.sh")
    archive = read("buildfiles/ios/archive.sh")
    plist_path = ROOT / "rpcs3/ios/RPCS3Core-Info.plist.in"
    with plist_path.open("rb") as stream:
        framework_info = plistlib.load(stream)

    require(errors, framework_info.get("CFBundleShortVersionString") == "0.4", "framework short version is not 0.4")
    require(errors, framework_info.get("CFBundleVersion") == "4", "framework bundle version is not 4")
    require(errors, script.startswith("#!/usr/bin/env bash\n"), "XCFramework helper lacks the expected Bash shebang")
    require(errors, "set -euo pipefail" in script, "XCFramework helper lacks strict mode")
    for contract in (
        "rpcs3_ios_core_framework", "iphoneos", "iphonesimulator",
        "-create-xcframework", "RPCS3Core.h", "lipo -archs",
    ):
        require(errors, contract in script, f"XCFramework packaging contract is missing: {contract}")

    for contract in (
        "rpcs3_ios_core_link", "Frameworks/RPCS3Core.framework", "RPCS3Core-device.framework",
    ):
        require(errors, contract in archive, f"core archive extraction contract is missing: {contract}")


def main() -> int:
    errors: list[str] = []
    validate_files(errors)
    validate_public_api(errors)
    validate_link_graph(errors)
    validate_compatibility_abis(errors)
    validate_mobile_features(errors)
    validate_packaging(errors)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3 iOS core 0.4 source/link/library/CoreMIDI/installer-status contracts passed (no Apple build or execution performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
