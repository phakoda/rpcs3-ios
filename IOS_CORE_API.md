# RPCS3Core.framework host API

`RPCS3Core.framework` is the Qt-free iOS/iPadOS integration boundary for the RPCS3 emulator core. Version 0.3 exposes a C ABI and Clang module that can be consumed from Objective-C, Objective-C++, Swift bridging code, C, or C++.

This guide documents source contracts. It does not claim that the framework has compiled, linked, loaded, installed firmware, booted a workload, or presented a frame on an Apple target.

## Products

- `RPCS3Core.framework`: device- or simulator-specific dynamic framework.
- `RPCS3Core.xcframework`: combined device/simulator package created by `buildfiles/ios/create_core_xcframework.sh`.
- `RPCS3 iOS Core.app`: UIKit management host that imports only the public framework header.

Import the module from Objective-C or Objective-C++:

```objc
@import RPCS3Core;
```

Or include the public C header:

```c
#include <RPCS3Core/RPCS3Core.h>
```

## Lifecycle

Initialize once after UIKit has created the application process:

```objc
rpcs3_ios_core_result result = rpcs3_ios_core_initialize();
if (result != RPCS3_IOS_CORE_SUCCESS &&
    result != RPCS3_IOS_CORE_ALREADY_INITIALIZED)
{
    // Retrieve rpcs3_ios_core_copy_last_error().
}
```

Shutdown rejects new framework operations, cancels and drains active installers, removes lifecycle callbacks, stops guest/renderer threads, clears the retained render view, and then tears down platform services:

```objc
rpcs3_ios_core_set_event_callback(NULL, NULL);
rpcs3_ios_core_request_installation_cancel();
rpcs3_ios_core_shutdown();
```

Boot, pause, resume, restart, stop, render-view mutation, settings mutation and game-library mutation should be initiated from the UIKit main thread. Installation functions are synchronous and should run on a dedicated serial background queue.

## Emulator events

Install a callback before boot:

```objc
static void core_event(
    rpcs3_ios_core_event event,
    const char* detail,
    void* context)
{
    // Delivered on the UIKit main queue.
}

rpcs3_ios_core_set_event_callback(core_event, context);
```

Queued events are generation checked. Replacing or clearing the callback invalidates already queued deliveries, preventing a released context from being called later.

Events include ready, run, pause, resume, stop, missing firmware, pad connection changes and fatal errors.

## Render host

Supply a live `UIView` whose backing layer class is `CAMetalLayer` before boot:

```objc
@interface GameView : UIView
@end

@implementation GameView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

GameView* view = [[GameView alloc] initWithFrame:CGRectZero];
rpcs3_ios_core_set_render_view((__bridge void*)view);
```

The framework retains the view while attached, sets `framebufferOnly = NO`, updates `contentsScale` and `drawableSize`, and attaches the native touch overlay. Call this after host layout or orientation changes:

```objc
rpcs3_ios_core_refresh_render_view();
```

A valid attached view selects Vulkan/MoltenVK for the next boot. Without one, the framework selects `NullGSRender`. The render view may be replaced or cleared only while emulation is fully stopped.

## Security-scoped import

The core copies selected Files app content into a stable `Documents/Imports` location. The two-call buffer pattern does not copy the item twice; the completed destination path is cached until retrieved.

```objc
BOOL scoped = [url startAccessingSecurityScopedResource];
size_t required = 0;
rpcs3_ios_core_result result = rpcs3_ios_core_import_path(
    url.fileSystemRepresentation, NULL, 0, &required);

std::vector<char> path(required);
if (result == RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
{
    result = rpcs3_ios_core_import_path(
        url.fileSystemRepresentation,
        path.data(), path.size(), &required);
}
if (scoped)
{
    [url stopAccessingSecurityScopedResource];
}
```

Use the stable imported path for booting, firmware installation, package installation or game-directory registration.

## Boot and state

```c
rpcs3_ios_boot_result boot = rpcs3_ios_core_boot_path(path, 1);
rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
```

The public boot-result values mirror RPCS3's current `game_boot_result` values. Additional sentinel values represent an uninitialized core or invalid argument.

Lifecycle controls:

```c
rpcs3_ios_core_pause();
rpcs3_ios_core_resume();
rpcs3_ios_core_restart();
rpcs3_ios_core_stop();
```

Title, title ID and boot path use the same two-call string convention as diagnostics.

## Persistent mobile-safe settings

Settings are stored in the host application's `NSUserDefaults` domain and are applied before the RPCS3 callback table is installed.

```c
rpcs3_ios_configuration configuration = {0};
configuration.struct_size = sizeof(configuration);
rpcs3_ios_core_get_configuration(&configuration);

configuration.audio_volume = 80;
configuration.resolution_scale_percent = 100;
configuration.frame_limit = RPCS3_IOS_FRAME_LIMIT_DISPLAY;
rpcs3_ios_core_set_configuration(&configuration);
```

Available controls:

- portable PPU/static plus SPU dynamic interpreter mode;
- optional PPU LLVM or full LLVM modes when the framework was built with target LLVM;
- Cubeb or null audio;
- volume from 0–200%;
- resolution scale from 25–800%;
- automatic, 30, 60, 120 or display-rate frame limits;
- on-disk shader cache;
- RPCS3 performance overlay;
- preferred SPU threads from 0–6.

Unsupported LLVM selections return `RPCS3_IOS_CORE_UNSUPPORTED`. Settings can be changed or reset only while emulation is fully stopped.

## Game library

The framework manages RPCS3's normal `games.yml` and game-directory list without Qt:

```c
uint32_t added = 0;
rpcs3_ios_core_add_game_directory(directory, &added);
rpcs3_ios_core_add_game(game_path);
rpcs3_ios_core_remove_game(title_id);
```

Enumerate games using `rpcs3_ios_core_game_count()` and `rpcs3_ios_core_copy_game()`. Each entry contains the title ID and boot path. Registered directories use `rpcs3_ios_core_game_directory_count()` and `rpcs3_ios_core_copy_game_directory()`.

Scans and mutations require stopped emulation.

## Firmware installation

The framework uses RPCS3's existing PUP parser, hash validation, SCE decrypter, TAR reader and VFS destinations. It validates free storage, extracts `dev_flash_*` packages and refreshes emulator VFS state.

Run on a serial background queue:

```objc
dispatch_async(operationQueue, ^{
    rpcs3_ios_core_result result = rpcs3_ios_core_install_firmware(
        importedPupPath,
        0, // reject downgrade
        1, // replace existing firmware
        install_progress,
        context);
});
```

The host must provide legally obtained PlayStation 3 firmware. The repository does not include firmware.

Cancellation is cooperative between package boundaries:

```c
rpcs3_ios_core_request_installation_cancel();
```

A cancelled or failed installation may leave partially extracted files. The host should display this warning and allow the user to retry a known-good firmware package.

Read the currently detected firmware version with `rpcs3_ios_core_copy_firmware_version()`.

## PKG installation

The package installer uses RPCS3's `package_reader`, decryption/extraction logic, progress reporting and abort path:

```objc
dispatch_async(operationQueue, ^{
    rpcs3_ios_core_result result = rpcs3_ios_core_install_package(
        importedPkgPath,
        install_progress,
        context);
});
```

The first bootable path returned by a successful package extraction is added to the normal game library. Retrieve it with `rpcs3_ios_core_copy_last_installed_path()`.

Installers are serialized inside the framework. A second concurrent operation returns `RPCS3_IOS_CORE_BUSY`.

## Native guest interfaces

The Qt-free core callback extension supplies public iOS implementations for:

- message dialogs using `UIAlertController`;
- on-screen keyboard input using a UIKit text field;
- save-data selection using an action sheet, with a focused-entry fallback when invoked on the main thread;
- trophy notifications;
- image metadata through ImageIO;
- scaled straight-RGBA8888 image output through ImageIO/CoreGraphics.

Network send/receive-message dialogs, host camera capture, microphone capture, physical USB passthrough and host MIDI remain disabled until stable public iOS implementations are added.

## Diagnostics

Use these APIs for support reports:

- `rpcs3_ios_core_query_jit_status()`;
- `rpcs3_ios_core_query_performance_status()`;
- `rpcs3_ios_core_copy_jit_detail()`;
- `rpcs3_ios_core_copy_diagnostics()`;
- `rpcs3_ios_core_copy_last_error()`;
- sandbox path accessors.

The UIKit management host writes diagnostics to a temporary text file and presents `UIActivityViewController` for export.

## Threading and ownership summary

- Event callbacks run on the UIKit main queue.
- Installation progress callbacks run on the installation caller's thread.
- The host owns callback context memory and must clear callbacks before releasing it.
- Queued emulator events are invalidated when the callback generation changes.
- The framework retains the attached render view until it is cleared or shutdown completes.
- Installation calls are synchronous and internally serialized.
- Shutdown closes admission, requests cancellation and waits for the active installer to leave RPCS3 VFS/package state.

## Evidence still required

The source tree still requires Apple-side proof for:

- Xcode generation and compilation;
- final linking and module import;
- framework loading and repeated initialization/shutdown;
- firmware and PKG installation;
- interpreter and optional LLVM execution;
- Vulkan/MoltenVK device creation and actual RSX frame presentation;
- dialog, image, audio, controller, touch, lifecycle, memory and thermal behavior;
- legal game boot compatibility.
