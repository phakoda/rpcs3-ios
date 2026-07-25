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
    "rpcs3/ios/IOSCoreSaveDialog.h",
    "rpcs3/ios/IOSCoreSaveDialog.mm",
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
    callback = read("rpcs3/ios/IOSCoreCallbacks.mm")
    composite = read("rpcs3/ios/IOSCoreCallbacksComposite.cpp")
    bounded_save = read("rpcs3/ios/IOSCoreSaveDialog.mm")
    emulator = read("rpcs3/ios/IOSCoreEmulator.mm")
    guide = read("IOS_CORE_API.md")

    for contract in (
        "IOSCoreCallbacks.mm",
        "IOSCoreCallbacksComposite.cpp",
        "IOSCoreSaveDialog.mm",
        "extend_core_callbacks=extend_core_callbacks_base",
    ):
        require(errors, contract in cmake, f"callback composition build contract is missing: {contract}")

    for contract in (
        "class ios_msg_dialog",
        "class ios_osk_dialog",
        "class ios_save_dialog",
        "class ios_trophy_notification",
        "CGImageSourceCopyPropertiesAtIndex",
        "CGImageSourceCreateThumbnailAtIndex",
        "CGBitmapContextCreate",
        "extend_core_callbacks",
    ):
        require(errors, contract in callback, f"native callback contract is missing: {contract}")

    for contract in (
        "extend_core_callbacks_base",
        "extend_core_save_dialog_callback",
    ):
        require(errors, contract in composite, f"callback composition ordering is missing: {contract}")

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
    require(errors, "extend_core_callbacks(callbacks)" in emulator, "emulator callback table is not extended")

    for contract in (
        "Firmware installation",
        "PKG installation",
        "Persistent mobile-safe settings",
        "Game library",
        "Native guest interfaces",
        "Evidence still required",
    ):
        require(errors, contract in guide, f"public core API guide is missing section: {contract}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("RPCS3 iOS native callback/management contracts passed (no Apple execution performed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
