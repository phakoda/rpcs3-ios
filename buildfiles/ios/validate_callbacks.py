#!/usr/bin/env python3
"""Host-independent contracts for RPCS3Core's native UIKit callback layer."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

REQUIRED_FILES = (
    "IOS_CORE_API.md",
    "rpcs3/ios/IOSCoreCallbacks.h",
    "rpcs3/ios/IOSCoreCallbacks.mm",
    "rpcs3/ios/IOSCoreCallbacksComposite.cpp",
    "rpcs3/ios/IOSCoreEventCallback.mm",
    "rpcs3/ios/IOSCoreFallbackCallbacks.h",
    "rpcs3/ios/IOSCoreFallbackCallbacks.mm",
    "rpcs3/ios/IOSCoreImageCallbacks.h",
    "rpcs3/ios/IOSCoreImageCallbacks.mm",
    "rpcs3/ios/IOSCoreOpenURL.mm",
    "rpcs3/ios/IOSCoreSaveDialog.h",
    "rpcs3/ios/IOSCoreSaveDialog.mm",
    "rpcs3/ios/PatchCoreHost.cmake",
)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    for relative in REQUIRED_FILES:
        require(errors, (ROOT / relative).is_file(), f"missing native callback source: {relative}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    cmake = read("rpcs3/ios/CoreExtensions.cmake")
    host_patch = read("rpcs3/ios/PatchCoreHost.cmake")
    callback = read("rpcs3/ios/IOSCoreCallbacks.mm")
    composite = read("rpcs3/ios/IOSCoreCallbacksComposite.cpp")
    event_wrapper = read("rpcs3/ios/IOSCoreEventCallback.mm")
    fallback = read("rpcs3/ios/IOSCoreFallbackCallbacks.mm")
    image = read("rpcs3/ios/IOSCoreImageCallbacks.mm")
    open_url = read("rpcs3/ios/IOSCoreOpenURL.mm")
    bounded_save = read("rpcs3/ios/IOSCoreSaveDialog.mm")
    defaults = read("rpcs3/ios/IOSCoreDefaults.cpp")
    emulator = read("rpcs3/ios/IOSCoreEmulator.mm")
    guide = read("IOS_CORE_API.md")

    for contract in (
        "IOSCoreCallbacks.mm",
        "IOSCoreCallbacksComposite.cpp",
        "IOSCoreEventCallback.mm",
        "IOSCoreFallbackCallbacks.mm",
        "IOSCoreImageCallbacks.mm",
        "IOSCoreSaveDialog.mm",
        "extend_core_callbacks=extend_core_callbacks_base",
        "rpcs3_ios_core_set_event_callback=rpcs3_ios_core_set_event_callback_base",
        "PatchCoreHost.cmake",
    ):
        require(errors, contract in cmake, f"callback or host composition build contract is missing: {contract}")

    for contract in (
        "CoreLinkMainSafe.mm",
        "IOSCoreOpenURL.mm",
        "@interface RPCS3CoreLinkViewController ()",
        "const std::string path_copy = path;",
        "INSTALLATION_FIRMWARE path:path_copy",
        "INSTALLATION_PACKAGE path:path_copy",
        "removeDirectory:path_copy removeEntries:NO",
        "removeDirectory:path_copy removeEntries:YES",
        "list(FILTER _core_host_sources EXCLUDE REGEX",
        "Could not apply the iOS core management-host lifetime adaptation",
    ):
        require(errors, contract in host_patch, f"generated management-host hardening is missing: {contract}")

    require(
        errors,
        host_patch.count("const std::string path_copy = path;") >= 4,
        "management-host patch does not define and validate all explicit path copies",
    )

    for contract in (
        "class ios_msg_dialog",
        "class ios_osk_dialog",
        "class ios_save_dialog",
        "class ios_trophy_notification",
        "extend_core_callbacks",
    ):
        require(errors, contract in callback, f"native callback contract is missing: {contract}")

    for contract in (
        "extend_core_callbacks_base",
        "extend_core_fallback_callbacks",
        "extend_core_image_callbacks",
        "extend_core_save_dialog_callback",
    ):
        require(errors, contract in composite, f"callback composition ordering is missing: {contract}")

    for contract in (
        "rpcs3_ios_core_set_event_callback_base",
        "NSThread.isMainThread",
        "dispatch_sync(dispatch_get_main_queue()",
        "waits for any in-flight callback",
    ):
        require(errors, contract in event_wrapper, f"main-queue event mutation contract is missing: {contract}")

    for contract in (
        "callbacks.get_localized_string",
        "callbacks.get_localized_u32string",
        "CFStringIsSurrogateHighCharacter",
        "CFStringGetLongCharacterForSurrogatePair",
        "callbacks.play_sound",
        "AVAudioPlayerDelegate",
        "NSMutableSet<AVAudioPlayer*>",
        "volume.value_or(1.0f)",
        "audioPlayerDidFinishPlaying",
        "audioPlayerDecodeErrorDidOccur",
    ):
        require(errors, contract in fallback, f"localization or native sound fallback is missing: {contract}")

    require(
        errors,
        fallback.find("@interface RPCS3CoreSoundPool") < fallback.find("namespace rpcs3::ios"),
        "Objective-C sound pool is incorrectly declared inside a C++ namespace",
    )

    for contract in (
        "preferredFilenameExtension",
        "case 6: return 2",
        "case 3: return 3",
        "case 8: return 4",
        "CGImageSourceCreateThumbnailAtIndex",
        "CGBitmapContextCreate",
        "straight RGBA8888",
    ):
        require(errors, contract in image, f"contract-compatible ImageIO behavior is missing: {contract}")

    for contract in (
        "NSArray<NSString*>* immutable_titles",
        "timeout_seconds = 120",
        "dispatch_semaphore_wait",
        "dismissViewControllerAnimated",
        "NSThread.isMainThread",
        "std::make_unique<ios_bounded_save_dialog>",
    ):
        require(errors, contract in bounded_save, f"bounded save-dialog contract is missing: {contract}")

    require(
        errors,
        "save_entries" not in bounded_save.split("dispatch_async(dispatch_get_main_queue()", 1)[-1],
        "bounded save dialog captures RPCS3's caller-owned save entry vector across UIKit dispatch",
    )

    for contract in (
        "startAccessingSecurityScopedResource",
        "rpcs3_ios_core_import_path",
        "rpcs3_ios_core_install_firmware",
        "rpcs3_ios_core_install_package",
        "rpcs3_ios_core_boot_path",
        "application:(UIApplication*)application",
        "openURL:(NSURL*)url",
        "const std::string path_copy",
    ):
        require(errors, contract in open_url, f"open-in-place routing contract is missing: {contract}")

    for contract in (
        "#ifdef RPCS3_IOS_CORE",
        "extern atomic_t<bool> g_headless",
        "const bool has_render_host = has_core_render_view()",
        "g_headless = !has_render_host",
        "Emu.SetHeadless(!has_render_host)",
        "has_render_host ? video_renderer::vulkan : video_renderer::null",
    ):
        require(errors, contract in defaults, f"hosted Vulkan/headless contract is missing: {contract}")

    require(errors, "extend_core_callbacks(callbacks)" in emulator, "emulator callback table is not extended")
    require(errors, "g_event_generation" in emulator, "queued event generation guard is missing")

    for contract in (
        "Persistent mobile-safe settings",
        "Game library and persistent roots",
        "CoreMIDI input",
        "Firmware and package installation",
        "Installer status polling",
        "Native guest interfaces",
        "Evidence still required",
    ):
        require(errors, contract in guide, f"public core API guide is missing section: {contract}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3 iOS native callback/fallback/open-in-place/host-lifetime contracts passed (no Apple execution performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
