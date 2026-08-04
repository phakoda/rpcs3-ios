#!/usr/bin/env python3
"""Host-independent structural checks for RPCS3Core.framework 0.5.

These checks prove source, ABI, and build-graph consistency only. They do not
compile, link, sign, launch, install firmware, or execute an Apple target or a
PlayStation 3 workload.
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
    "3rdparty/ios/rtmidi/rtmidi_coremidi_v2.cpp",
    "buildfiles/ios/create_core_xcframework.sh",
    "rpcs3/ios/CoreAnchor.cpp",
    "rpcs3/ios/CoreExtensions.cmake",
    "rpcs3/ios/CoreLink.cpp",
    "rpcs3/ios/CoreLinkMain.mm",
    "rpcs3/ios/IOSCoreDefaults.cpp",
    "rpcs3/ios/IOSCoreDiagnostics.cpp",
    "rpcs3/ios/IOSCoreEmulator.mm",
    "rpcs3/ios/IOSCoreGSFrame.h",
    "rpcs3/ios/IOSCoreGSFrame.mm",
    "rpcs3/ios/IOSCoreInstallationStatus.cpp",
    "rpcs3/ios/IOSCoreInstaller.cpp",
    "rpcs3/ios/IOSCoreInstallerTransaction.cpp",
    "rpcs3/ios/IOSCoreLibrary.mm",
    "rpcs3/ios/IOSCoreLifecycle.cpp",
    "rpcs3/ios/IOSCoreLifecycleDeferred.mm",
    "rpcs3/ios/IOSCoreMIDI.mm",
    "rpcs3/ios/IOSCoreMIDIComposition.mm",
    "rpcs3/ios/IOSCoreMIDIIdentity.mm",
    "rpcs3/ios/IOSCoreMutationAPI.cpp",
    "rpcs3/ios/IOSCoreOperationAPI.cpp",
    "rpcs3/ios/IOSCoreOperations.cpp",
    "rpcs3/ios/IOSCoreOperations.h",
    "rpcs3/ios/IOSCoreSettings.mm",
    "rpcs3/ios/IOSCoreStatusAPI.cpp",
    "rpcs3/ios/IOSCoreVersion.cpp",
    "rpcs3/ios/PatchCoreHost.cmake",
    "rpcs3/ios/RPCS3Core.h",
    "rpcs3/ios/RPCS3Core.mm",
    "rpcs3/ios/RPCS3Core.exports",
    "rpcs3/ios/RPCS3Core.modulemap",
    "rpcs3/ios/RPCS3Core-Info.plist.in",
    "rpcs3/ios/RPCS3CoreStatus.h",
)

OBSOLETE_FILES = (
    "3rdparty/ios/rtmidi/rtmidi_stub.cpp",
    "rpcs3/ios/IOSCoreLibrary.cpp",
    "rpcs3/ios/IOSHeadlessCore.cpp",
    "rpcs3/ios/IOSHeadlessCore.h",
)

IMPLEMENTATION_FILES = (
    "rpcs3/ios/RPCS3Core.mm",
    "rpcs3/ios/IOSCoreDiagnostics.cpp",
    "rpcs3/ios/IOSCoreEmulator.mm",
    "rpcs3/ios/IOSCoreEventCallback.mm",
    "rpcs3/ios/IOSCoreInstallationStatus.cpp",
    "rpcs3/ios/IOSCoreInstaller.cpp",
    "rpcs3/ios/IOSCoreInstallerTransaction.cpp",
    "rpcs3/ios/IOSCoreLibrary.mm",
    "rpcs3/ios/IOSCoreMIDI.mm",
    "rpcs3/ios/IOSCoreMIDIIdentity.mm",
    "rpcs3/ios/IOSCoreMutationAPI.cpp",
    "rpcs3/ios/IOSCoreOperationAPI.cpp",
    "rpcs3/ios/IOSCoreSettings.mm",
    "rpcs3/ios/IOSCoreStatusAPI.cpp",
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

OPERATION_ENUMS = (
    "RPCS3_IOS_CORE_OPERATION_NONE",
    "RPCS3_IOS_CORE_OPERATION_INITIALIZE",
    "RPCS3_IOS_CORE_OPERATION_SHUTDOWN",
    "RPCS3_IOS_CORE_OPERATION_BOOT",
    "RPCS3_IOS_CORE_OPERATION_RESTART",
    "RPCS3_IOS_CORE_OPERATION_PAUSE",
    "RPCS3_IOS_CORE_OPERATION_RESUME",
    "RPCS3_IOS_CORE_OPERATION_STOP",
    "RPCS3_IOS_CORE_OPERATION_INSTALL_FIRMWARE",
    "RPCS3_IOS_CORE_OPERATION_INSTALL_PACKAGE",
    "RPCS3_IOS_CORE_OPERATION_LIBRARY",
    "RPCS3_IOS_CORE_OPERATION_SETTINGS",
    "RPCS3_IOS_CORE_OPERATION_MIDI",
    "RPCS3_IOS_CORE_OPERATION_RENDER_HOST",
    "RPCS3_IOS_CORE_OPERATION_IMPORT",
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def exported_functions() -> set[str]:
    return {
        line.strip().removeprefix("_")
        for line in read("rpcs3/ios/RPCS3Core.exports").splitlines()
        if line.strip().startswith("_rpcs3_ios_core_")
    }


def public_functions() -> set[str]:
    headers = read("rpcs3/ios/RPCS3Core.h") + "\n" + read("rpcs3/ios/RPCS3CoreStatus.h")
    return set(re.findall(
        r"RPCS3_IOS_CORE_EXPORT\s+[\w\s\*]+?\s+(rpcs3_ios_core_[a-z0-9_]+)\s*\(",
        headers,
        flags=re.MULTILINE,
    ))


def validate_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        require(errors, (ROOT / relative).is_file(), f"missing core source: {relative}")
    for relative in OBSOLETE_FILES:
        require(errors, not (ROOT / relative).exists(), f"obsolete iOS source must remain removed: {relative}")


def validate_public_api(errors: list[str]) -> None:
    main_header = read("rpcs3/ios/RPCS3Core.h")
    status_header = read("rpcs3/ios/RPCS3CoreStatus.h")
    implementations = "\n".join(read(relative) for relative in IMPLEMENTATION_FILES)
    declarations = public_functions()
    exports = exported_functions()

    require(errors, declarations == exports,
            f"public/exported function mismatch: declarations-only={sorted(declarations - exports)}, exports-only={sorted(exports - declarations)}")
    for function in sorted(declarations):
        require(errors, re.search(rf"\b{re.escape(function)}\s*\(", implementations) is not None,
                f"public function has no source implementation: {function}")

    for value, name in enumerate(PUBLIC_BOOT_ENUMS):
        require(errors, re.search(rf"\b{name}\s*=\s*{value}\b", main_header) is not None,
                f"boot result ABI changed at value {value}: {name}")
    for value, name in enumerate(OPERATION_ENUMS):
        require(errors, re.search(rf"\b{name}\s*=\s*{value}\b", status_header) is not None,
                f"operation ABI changed at value {value}: {name}")

    for field in (
        "struct_size", "active", "cancel_requested", "kind", "stage",
        "completed", "total", "terminal_state", "result", "operation_id",
    ):
        require(errors, re.search(rf"typedef struct rpcs3_ios_installation_status_v2[\s\S]*?\b{field}\b", status_header) is not None,
                f"installation status v2 field is missing: {field}")
    for field in ("active_operation", "generation", "owned_by_calling_thread"):
        require(errors, re.search(rf"typedef struct rpcs3_ios_core_operation_status[\s\S]*?\b{field}\b", status_header) is not None,
                f"operation status field is missing: {field}")

    status_api = read("rpcs3/ios/IOSCoreStatusAPI.cpp")
    for name in OPERATION_ENUMS:
        require(errors, name in status_api, f"operation enum lacks a compile-time parity assertion: {name}")
    require(errors, "RPCS3_IOS_CORE_CANCELLED = 8" in main_header, "cancelled result ABI value changed")
    require(errors, "RPCS3Core 0.5" in read("rpcs3/ios/IOSCoreVersion.cpp"), "public version string is not 0.5")


def validate_composition(errors: list[str]) -> None:
    root_cmake = read("CMakeLists.txt")
    extensions = read("rpcs3/ios/CoreExtensions.cmake")
    patch = read("rpcs3/ios/PatchCoreSources.cmake")
    dependencies = read("3rdparty/ios.cmake")

    require(errors, "CoreExtensions.cmake" in root_cmake, "root CMake does not load core extensions")
    for source in (
        "IOSCoreOperations.cpp", "IOSCoreOperationAPI.cpp", "IOSCoreMutationAPI.cpp",
        "IOSCoreStatusAPI.cpp", "IOSCoreDiagnostics.cpp", "IOSCoreLifecycleDeferred.mm",
        "IOSCoreInstallerTransaction.cpp", "IOSCoreInstallationStatus.cpp",
        "IOSCoreMIDIIdentity.mm", "IOSCoreMIDIComposition.mm",
    ):
        require(errors, source in extensions, f"composition source is not linked: {source}")

    for symbol in (
        "rpcs3_ios_core_initialize_base",
        "rpcs3_ios_core_shutdown_base",
        "rpcs3_ios_core_import_path_base",
        "rpcs3_ios_core_copy_diagnostics_base",
        "rpcs3_ios_core_install_firmware_raw",
        "rpcs3_ios_core_install_package_raw",
        "apply_core_midi_configuration_base",
    ):
        require(errors, symbol in extensions, f"source-local composition rename is missing: {symbol}")

    for contract in (
        "VERSION 0.5.0",
        "SOVERSION 0.5",
        "RPCS3CoreStatus.h",
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,rpcs3_emu>",
        "FRAMEWORK TRUE",
        "RPCS3Core.exports",
        "RPCS3Core.modulemap",
        "XCODE_EMBED_FRAMEWORKS",
        "RPCS3_IOS_CORE=1",
        "3rdparty::vulkan",
        "XCODE_ATTRIBUTE_LD_GENERATE_MAP_FILE",
    ):
        require(errors, contract in extensions or contract in patch, f"framework link contract is missing: {contract}")

    require(errors, "rtmidi_coremidi_v2.cpp" in extensions, "topology-aware CoreMIDI source is not selected")
    require(errors, "list(FILTER _rpcs3_ios_rtmidi_sources EXCLUDE REGEX" in extensions and
            "rtmidi_coremidi" in extensions,
            "initial name-only CoreMIDI source is not excluded from the target")
    for contract in (
        "add_library(3rdparty_libusb STATIC",
        "add_library(3rdparty_rtmidi STATIC",
        "RPCS3_IOS_COREMIDI",
        "add_library(3rdparty::ios_system ALIAS",
        "RPCS3_IOS_NO_USB_PASSTHROUGH",
        "RPCS3_IOS_AVFORMAT",
        "RPCS3_IOS_AVCODEC",
        "RPCS3_IOS_AVUTIL",
    ):
        require(errors, contract in dependencies, f"concrete dependency contract is missing: {contract}")


def validate_operation_gate(errors: list[str]) -> None:
    operations = read("rpcs3/ios/IOSCoreOperations.cpp")
    operation_api = read("rpcs3/ios/IOSCoreOperationAPI.cpp")
    mutations = read("rpcs3/ios/IOSCoreMutationAPI.cpp")
    status = read("rpcs3/ios/IOSCoreInstallationStatus.cpp")

    for contract in (
        "g_active_operation", "g_operation_owner", "g_operation_generation",
        "Reentrant state mutation is not permitted", "core_operation_scope",
    ):
        require(errors, contract in operations, f"exclusive operation gate contract is missing: {contract}")
    for operation in (
        "core_operation::initialize", "core_operation::shutdown", "core_operation::boot",
        "core_operation::restart", "core_operation::pause", "core_operation::resume",
        "core_operation::stop", "core_operation::render_host", "core_operation::import_item",
    ):
        require(errors, operation in operation_api, f"public operation is not admitted centrally: {operation}")
    for operation in ("core_operation::library", "core_operation::settings", "core_operation::midi"):
        require(errors, operation in mutations, f"public mutation is not admitted centrally: {operation}")
    for operation in ("core_operation::install_firmware", "core_operation::install_package"):
        require(errors, operation in status, f"installer is not admitted centrally: {operation}")
    require(errors, "shutdown_core_fallback_services" in operation_api, "native sound teardown is not composed into shutdown")
    require(errors, "shutdown_core_midi_identity" in operation_api, "CoreMIDI identity teardown is not composed into shutdown")
    require(errors, "core_lifecycle_allows_boot" in operation_api, "inactive/background boot admission is missing")


def validate_settings(errors: list[str]) -> None:
    settings = read("rpcs3/ios/IOSCoreSettings.mm")
    decode_position = settings.find("decode_configuration(")
    commit_position = settings.find("g_cfg.core.ppu_decoder = decoded.ppu_decoder")
    require(errors, decode_position >= 0 and commit_position > decode_position,
            "settings are not decoded before committing g_cfg")
    for contract in (
        "decoded_configuration", "Commit only after every field has been validated",
        "settings_version = 2", "persist_configuration(configuration_snapshot())",
    ):
        require(errors, contract in settings, f"transactional settings contract is missing: {contract}")


def validate_installer(errors: list[str]) -> None:
    transaction = read("rpcs3/ios/IOSCoreInstallerTransaction.cpp")
    status = read("rpcs3/ios/IOSCoreInstallationStatus.cpp")
    for contract in (
        ".ios-installing", ".ios-backup", ".ios-install-transaction",
        "recover_transaction", "write_marker", "copy_tree", "commit_staging",
        "has_transaction_space", "saturating_multiply", "version_components",
        "version_less", "dev_flash_redirect", "remount_live_dev_flash",
        "rpcs3_ios_core_install_firmware_raw", "rpcs3_ios_core_install_package_raw",
    ):
        require(errors, contract in transaction, f"transactional installer contract is missing: {contract}")
    for contract in (
        "terminal_state", "operation_id", "RPCS3_IOS_INSTALLATION_TERMINAL_SUCCEEDED",
        "RPCS3_IOS_INSTALLATION_TERMINAL_FAILED", "RPCS3_IOS_INSTALLATION_TERMINAL_CANCELLED",
        "g_last_installed_path.clear()",
    ):
        require(errors, contract in status, f"installer status v2 contract is missing: {contract}")
    require(errors, "pup_path, 1, overwrite_existing" in transaction,
            "numeric downgrade validation does not bypass the raw lexical comparison")


def method_body(source: str, signature: str, next_signature: str) -> str:
    start = source.find(signature)
    end = source.find(next_signature, start + len(signature))
    if start < 0:
        return ""
    return source[start:] if end < 0 else source[start:end]


def validate_renderer_and_lifecycle(errors: list[str]) -> None:
    renderer = read("rpcs3/ios/IOSCoreGSFrame.mm")
    for signature, next_signature in (
        ("bool shown() override", "void hide() override"),
        ("int client_width() override", "int client_height() override"),
        ("int client_height() override", "f64 client_display_rate() override"),
        ("f64 client_display_rate() override", "bool has_alpha() override"),
    ):
        body = method_body(renderer, signature, next_signature)
        require(errors, body and "run_on_main_sync" not in body,
                f"RSX-facing renderer query still enters UIKit synchronously: {signature}")
    for contract in (
        "g_render_width", "g_render_height", "g_render_refresh_rate",
        "g_render_generation", "g_render_visible", "get_core_render_metrics",
    ):
        require(errors, contract in renderer, f"cached renderer metric is missing: {contract}")

    lifecycle = read("rpcs3/ios/IOSCoreLifecycle.cpp")
    deferred = read("rpcs3/ios/IOSCoreLifecycleDeferred.mm")
    composite = read("rpcs3/ios/IOSCoreCallbacksComposite.cpp")
    for contract in (
        "core_lifecycle_allows_boot", "try_core_lifecycle_pause_after_run",
        "schedule_core_lifecycle_pause_after_run", "pause_required()",
    ):
        require(errors, contract in lifecycle or contract in deferred, f"lifecycle contract is missing: {contract}")
    require(errors, "dispatch_after" in deferred and "remaining_attempts" in deferred,
            "post-boot lifecycle pause is not bounded and deferred")
    require(errors, "enforce_core_lifecycle_pause_after_run" in composite,
            "RUN callback does not enforce pending lifecycle pause reasons")
    require(errors, "rpcs3_ios_core_pause_base" not in lifecycle,
            "RUN callback can still recursively enter the emulator API mutex")


def validate_midi(errors: list[str]) -> None:
    backend = read("3rdparty/ios/rtmidi/rtmidi_coremidi_v2.cpp")
    identity = read("rpcs3/ios/IOSCoreMIDIIdentity.mm")
    migration = read("rpcs3/ios/IOSCoreMIDIComposition.mm")
    for contract in (
        "MIDIClientCreate", "midi_notify_proc", "kMIDIPropertyUniqueID",
        "desired_unique_id", "topology_changed", "refresh_connection",
        "maximum_queued_messages", "running_status", "pending_size",
        "mach_timebase_info", "65536",
    ):
        require(errors, contract in backend, f"CoreMIDI v2 contract is missing: {contract}")
    for contract in (
        "stable_endpoint_name", "resolve_core_midi_source_identity",
        "CoreMIDI ID", "g_topology_generation",
    ):
        require(errors, contract in identity, f"stable MIDI identity contract is missing: {contract}")
    require(errors, "migrate_assignments" in migration and "changed" in migration,
            "persisted MIDI assignment migration is missing")


def validate_plists_and_module(errors: list[str]) -> None:
    with (ROOT / "rpcs3/ios/Info.plist.in").open("rb") as stream:
        app_plist = plistlib.load(stream)
    with (ROOT / "rpcs3/ios/RPCS3Core-Info.plist.in").open("rb") as stream:
        framework_plist = plistlib.load(stream)

    require(errors, app_plist.get("CFBundleShortVersionString") == "0.5", "app bundle version is not 0.5")
    require(errors, app_plist.get("CFBundleVersion") == "5", "app bundle build number is not 5")
    require(errors, framework_plist.get("CFBundleShortVersionString") == "0.5", "framework bundle version is not 0.5")
    require(errors, framework_plist.get("CFBundleVersion") == "5", "framework bundle build number is not 5")

    claimed_types = {
        item
        for document in app_plist.get("CFBundleDocumentTypes", [])
        for item in document.get("LSItemContentTypes", [])
    }
    require(errors, "public.data" not in claimed_types, "app still claims every public.data document")
    require(errors, "public.folder" not in claimed_types, "app still claims every public.folder document")
    for identifier in (
        "net.rpcs3.ps3-firmware", "net.rpcs3.ps3-package",
        "net.rpcs3.ps3-executable", "net.rpcs3.ps3-disc-image", "net.rpcs3.ps3-license",
    ):
        require(errors, identifier in claimed_types, f"specific document type is not registered: {identifier}")

    modulemap = read("rpcs3/ios/RPCS3Core.modulemap")
    require(errors, 'header "RPCS3Core.h"' in modulemap, "main public header is missing from module map")
    require(errors, 'header "RPCS3CoreStatus.h"' in modulemap, "status public header is missing from module map")


def validate_no_patch_artifacts(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        path = ROOT / relative
        if not path.is_file() or path.suffix not in {".cpp", ".h", ".mm", ".cmake", ".py"}:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            require(errors, re.match(r"^\+\s{2,}", line) is None,
                    f"literal diff marker in {path.relative_to(ROOT)}:{number}")


def main() -> int:
    errors: list[str] = []
    validate_files(errors)
    if not errors:
        validate_public_api(errors)
        validate_composition(errors)
        validate_operation_gate(errors)
        validate_settings(errors)
        validate_installer(errors)
        validate_renderer_and_lifecycle(errors)
        validate_midi(errors)
        validate_plists_and_module(errors)
        validate_no_patch_artifacts(errors)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3Core 0.5 source/ABI/operation/transaction/lifecycle/MIDI contracts passed (no Apple execution performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
