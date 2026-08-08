# RPCS3Core.framework host API

`RPCS3Core.framework` is the Qt-free iOS/iPadOS integration boundary for the RPCS3 emulator core. Version 0.4 exposes a C ABI and Clang module that can be consumed from Objective-C, Objective-C++, Swift bridging code, C, or C++.

This guide documents source contracts. It does not claim that the framework has compiled, linked, loaded, installed firmware, received MIDI, booted a workload, or presented a frame on an Apple target.

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

Boot, pause, resume, restart, stop, render-view mutation, settings mutation, game-library mutation, and MIDI assignment mutation should be initiated from the UIKit main thread. Installation functions are synchronous and should run on a dedicated serial background queue.

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

Queued events are generation checked. Callback registration and clearing are serialized on the UIKit main queue. Clearing therefore waits for an in-flight delivery to return before the host releases its context.

Events include ready, run, pause, resume, stop, missing firmware, pad connection changes, and fatal errors.

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

A valid attached view immediately marks both RPCS3 headless-state holders false and selects Vulkan/MoltenVK. Without one, the framework selects `NullGSRender` and headless mode. The view may be replaced or cleared only while emulation is fully stopped.

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

Use the stable imported path for booting, firmware installation, package installation, or persistent game-root registration.

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

Title, title ID, and boot path use the same two-call string convention as diagnostics.

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
- automatic, 30, 60, 120, or display-rate frame limits;
- on-disk shader cache;
- RPCS3 performance overlay;
- preferred SPU threads from 0–6.

Unsupported LLVM selections return `RPCS3_IOS_CORE_UNSUPPORTED`. Settings can be changed or reset only while emulation is fully stopped.

```c
rpcs3_ios_core_reset_configuration();
```

## Game library and persistent roots

Title-ID/path mappings use RPCS3's normal `games.yml`. Version 0.4 separately persists scan roots in the host application's `NSUserDefaults` domain; it does not misuse `Emulator::GetGameDirs()`, which describes the currently booted title rather than library roots.

Register and scan a stable imported directory:

```c
uint32_t added = 0;
rpcs3_ios_core_add_game_directory(directory, &added);
```

Maintain roots:

```c
uint32_t changed = 0;
rpcs3_ios_core_rescan_game_directories(&changed);
rpcs3_ios_core_prune_missing_game_directories(&changed);
rpcs3_ios_core_remove_game_directory(directory, 1, &changed);
rpcs3_ios_core_clear_game_directories(0, &changed);
```

For removal APIs, the flag controls whether `games.yml` entries beneath the root are also removed. Clearing roots without removing entries preserves the current game mappings.

Manage individual game mappings:

```c
rpcs3_ios_core_add_game(game_path);
rpcs3_ios_core_remove_game(title_id);
```

Enumerate games with `rpcs3_ios_core_game_count()` and `rpcs3_ios_core_copy_game()`. Each entry contains the title ID and boot path. Enumerate persistent roots with `rpcs3_ios_core_game_directory_count()` and `rpcs3_ios_core_copy_game_directory()`.

Scans and mutations require stopped emulation.

## CoreMIDI input

Version 0.4 replaces the no-port RtMidi compatibility stub with a public CoreMIDI implementation of the exact C ABI consumed by RPCS3's emulated Rock Band 3 MIDI adapters.

The bridge:

- enumerates current CoreMIDI sources by display name;
- connects and disconnects selected endpoints;
- preserves incomplete short messages across CoreMIDI packet boundaries;
- supports MIDI running status;
- preserves interleaved system real-time messages;
- accumulates bounded SysEx messages;
- applies RtMidi-style SysEx, timing, and active-sense filtering;
- queues at most 2,048 messages;
- reports message deltas using the Mach host clock.

Enumerate current sources:

```c
size_t count = rpcs3_ios_core_midi_source_count();
for (size_t index = 0; index < count; ++index)
{
    // Use rpcs3_ios_core_copy_midi_source() with the two-call buffer pattern.
}
```

RPCS3 supports three persistent adapter slots. Assign a source display name and emulated adapter type:

```c
rpcs3_ios_core_set_midi_assignment(
    0,
    RPCS3_IOS_MIDI_KEYBOARD,
    source_name);
```

Available adapter types are keyboard, 17-fret guitar, 22-fret guitar, and drums. Retrieve or clear assignments with:

```c
rpcs3_ios_core_copy_midi_assignment(...);
rpcs3_ios_core_clear_midi_assignment(slot);
rpcs3_ios_core_clear_all_midi_assignments();
```

Mappings are serialized using RPCS3's existing three-slot MIDI configuration format and reapplied before every boot so a per-game configuration cannot silently erase them. Source names are name-based, matching upstream RPCS3 behavior; duplicate CoreMIDI display names can therefore be ambiguous. Assignment mutation requires stopped emulation.

This is source-integrated but not device-validated. CoreMIDI source discovery, connection, message timing, and actual emulated instrument input still require Apple-side evidence.

## Firmware and package installation

The firmware installer uses RPCS3's existing PUP parser, hash validation, SCE decrypter, TAR reader, free-storage checks, and VFS destinations. The package installer uses RPCS3's `package_reader`, decryption/extraction logic, progress reporting, and abort path.

Run either synchronous operation on a serial background queue:

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

```objc
dispatch_async(operationQueue, ^{
    rpcs3_ios_core_result result = rpcs3_ios_core_install_package(
        importedPkgPath,
        install_progress,
        context);
});
```

The host must provide legally obtained content. The repository does not include firmware or packages.

Cancellation is cooperative:

```c
rpcs3_ios_core_request_installation_cancel();
```

A cancelled or failed installation may leave partially extracted files. The first bootable path returned by successful PKG extraction is added to the normal game library and can be retrieved with `rpcs3_ios_core_copy_last_installed_path()`.

### Installer status polling

Progress callbacks are optional. Version 0.4 also records status independently so another thread or a callback-free host can poll the active operation:

```c
rpcs3_ios_installation_status status =
    rpcs3_ios_core_query_installation_status();

if (status.active)
{
    // status.kind, status.stage, status.completed, status.total
}
```

`rpcs3_ios_installation_status` contains:

- `struct_size` for ABI inspection;
- `active`;
- `cancel_requested`;
- `kind` (`FIRMWARE` or `PACKAGE`);
- `stage` (`VALIDATING`, `EXTRACTING`, `FINALIZING`, or `COMPLETE`);
- `completed` and `total` work units.

Retrieve the latest progress, cancellation, completion, or failure text with the standard two-call string convention:

```c
size_t required = rpcs3_ios_core_copy_installation_detail(NULL, 0);
char* detail = malloc(required);
rpcs3_ios_core_copy_installation_detail(detail, required);
```

Status is protected by a dedicated mutex. The original installers remain the owners of operation serialization, package-reader abort behavior, RPCS3 VFS mutation, and shutdown draining.

## Native guest interfaces

The Qt-free core callback extension supplies public iOS implementations for:

- message dialogs using `UIAlertController`;
- on-screen keyboard input using a UIKit text field;
- bounded save-data selection using an action sheet;
- trophy notifications;
- image metadata through ImageIO;
- scaled straight-RGBA8888 image output through ImageIO/CoreGraphics.

Network send/receive-message dialogs, host camera capture, microphone capture, and physical USB passthrough remain disabled until stable public iOS implementations are added. CoreMIDI is implemented separately as described above.

## Diagnostics

Use these APIs for support reports:

- `rpcs3_ios_core_query_jit_status()`;
- `rpcs3_ios_core_query_performance_status()`;
- `rpcs3_ios_core_query_installation_status()`;
- `rpcs3_ios_core_copy_jit_detail()`;
- `rpcs3_ios_core_copy_installation_detail()`;
- `rpcs3_ios_core_copy_diagnostics()`;
- `rpcs3_ios_core_copy_last_error()`;
- sandbox path accessors.

The UIKit management host writes diagnostics to a temporary text file and presents `UIActivityViewController` for export. It also displays persistent-root counts and all three MIDI assignments.

## Threading and ownership summary

- Event callbacks run on the UIKit main queue.
- Installation progress callbacks run on the installation caller's thread.
- The host owns callback context memory and must clear callbacks before releasing it.
- Queued emulator events are invalidated when the callback generation changes.
- Callback clearing is serialized with delivery on the main queue.
- The framework retains the attached render view until it is cleared or shutdown completes.
- Installation calls are synchronous and internally serialized.
- Installer-status reads and cancellation requests may come from another thread.
- Library-root, settings, and MIDI mutations require fully stopped emulation.
- Shutdown closes admission, requests cancellation, and waits for the active installer to leave RPCS3 VFS/package state.

## Evidence still required

The source tree still requires Apple-side proof for:

- Xcode generation and compilation;
- final linking and module import;
- framework loading and repeated initialization/shutdown;
- firmware and PKG installation plus status polling under real I/O;
- CoreMIDI discovery, connection, packet delivery, and emulated instrument behavior;
- interpreter and optional LLVM execution;
- Vulkan/MoltenVK device creation and actual RSX frame presentation;
- dialogs, images, audio, controllers, touch, lifecycle, memory, and thermal behavior;
- legal game boot compatibility.
