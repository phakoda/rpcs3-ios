# RPCS3Core.framework 0.5

`RPCS3Core.framework` 0.5 is the Qt-free native framework surface for the staged
RPCS3 iOS/iPadOS port. It is intentionally separated from the optional
Qt-derived application frontend and from the small Vulkan bootstrap target.

This document describes source and ABI contracts. **No Apple-target final link,
simulator launch, physical-device execution, firmware installation, legal
workload boot, JIT execution, Vulkan frame presentation, controller interaction,
or CoreMIDI hardware delivery is established merely by these sources or the
host-independent validators.**

## Public headers

Framework consumers import:

```c
#include <RPCS3Core/RPCS3Core.h>
#include <RPCS3Core/RPCS3CoreStatus.h>
```

`RPCS3Core.h` retains the original 0.4-compatible lifecycle, renderer, import,
emulator, settings, library, CoreMIDI, installer, diagnostics, and path APIs.
`RPCS3CoreStatus.h` adds versioned 0.5 status and capability structures without
changing the layout of existing public structures.

Every structure containing `struct_size` must be initialized by the caller when
passed into the framework. Structures returned by value have their size filled
by the framework.

## Framework operation admission

RPCS3 and its VFS, renderer, configuration, library, and installer state cannot
be mutated safely by unrelated concurrent host calls. Version 0.5 therefore has
one framework-wide exclusive operation gate covering:

- initialization and shutdown;
- boot, restart, pause, resume, and stop;
- render-view replacement and clearing;
- security-scoped imports;
- firmware and package installation;
- library mutations and scans;
- persistent settings mutation;
- CoreMIDI assignment mutation.

Admission is nonblocking. A conflicting or reentrant request returns
`RPCS3_IOS_CORE_BUSY`, or `RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED` for boot-shaped
operations, and records a descriptive last error. Status queries, diagnostics,
event delivery, and installation cancellation remain available while a long
operation is active.

`rpcs3_ios_core_query_operation_status()` reports the active operation, a
monotonically increasing generation, and whether the current calling thread owns
the operation. Hosts should use this state—not a private UI boolean—to disable
conflicting controls.

A host callback must not synchronously request shutdown, boot, library mutation,
settings mutation, MIDI mutation, or another installation from inside an active
operation callback. Reentrant state mutation is rejected instead of tearing down
RPCS3 state underneath the caller's stack.

## Initialization and shutdown

A successful initialization performs the native platform and emulator setup and
then checks for an interrupted transactional firmware commit. If a previous
process ended after moving live firmware to backup but before activating the
staged tree, the framework restores the backup before returning success.

Shutdown obtains exclusive operation admission before it:

1. stops accepting native guest sound playback;
2. stops and releases retained `AVAudioPlayer` objects;
3. releases the CoreMIDI identity client;
4. cancels and drains installation work;
5. removes lifecycle callbacks;
6. shuts down the emulator, renderer host, controllers, displays, performance
   notifications, audio, and native platform state.

A shutdown request made reentrantly from an admitted callback returns busy; it
does not continue tearing down the framework.

## Lifecycle and thread rules

Event callbacks are delivered on the UIKit main queue. Replacing or clearing the
event callback from a non-main thread synchronizes with that queue so a host may
release its context after the clear returns.

UIKit presentation and render-view configuration occur on the main queue.
Renderer-thread queries do not synchronously enter UIKit. Width, height, refresh
rate, visibility, and drawable generation are cached from main-queue layout
updates and read by RSX without a main-thread round trip.

Boot and restart are rejected while the application is inactive, backgrounded,
or inside an unresolved audio interruption. If the application becomes inactive
while loading is already in progress, the RUN callback schedules a bounded,
deduplicated pause retry after boot operation admission is released. Resume is
attempted only for a pause successfully initiated by the lifecycle layer; manual
pauses remain manual.

Lifecycle pause and resume retries are bounded to five seconds and retain pause
ownership across temporary `BUSY` results. Stopped, unavailable, or independently
resumed emulator state terminates the matching retry without forcing a new
transition.

## Render host

`rpcs3_ios_core_set_render_view()` accepts a live `UIView` backed by
`CAMetalLayer`. The framework retains the view while attached and configures:

- `framebufferOnly = NO`;
- opaque presentation;
- native screen scale;
- a minimum one-pixel drawable size;
- touch-controller overlay attachment.

The render view can be replaced or cleared only while emulation is stopped and
while no conflicting framework operation owns admission. Hosts call
`rpcs3_ios_core_refresh_render_view()` after layout, orientation, window, scale,
or external-screen changes.

Cached metrics include a drawable generation that changes with size or refresh
rate. This is diagnostic and source-level resize state; real MoltenVK swapchain
recreation and actual frame presentation remain Apple-runtime evidence gates.

## Persistent mobile-safe settings

The persistent configuration contains:

- portable PPU static + SPU dynamic interpreter mode;
- optional PPU LLVM or full LLVM when compiled in;
- Cubeb or null audio;
- 0–200 percent volume;
- 25–800 percent resolution scale;
- automatic, 30, 60, 120, or display-rate frame limits;
- shader cache;
- performance overlay;
- 0–6 preferred SPU threads.

Version 0.5 validates and normalizes every field into temporary decoded state
before assigning any `g_cfg` value. Invalid input therefore cannot partially
change CPU mode or another earlier field. Settings persistence has a versioned
migration marker and falls back to the portable configuration when a stored
configuration is unsupported.

Mutations require stopped emulation and exclusive operation admission.

## Game library and persistent roots

The framework continues to use RPCS3's normal `games.yml` title-ID mappings. A
separate ordered set of normalized scan roots is stored in the host application's
`NSUserDefaults` domain.

Public operations can:

- scan and register a root;
- rescan all registered roots;
- prune missing roots;
- unregister a root while preserving or removing its mappings;
- clear all roots while preserving or removing mappings;
- add a specific game path;
- remove a title-ID mapping;
- enumerate roots and mappings.

All mutations require stopped emulation and framework operation admission.
Enumeration functions remain snapshots; a host must not assume an index remains
stable across a later mutation.

## CoreMIDI input

The public CoreMIDI backend implements the RtMidi C subset consumed by RPCS3's
emulated Rock Band adapters. It supports:

- packet-boundary partial messages;
- channel running status;
- interleaved system real-time bytes;
- bounded 65,536-byte SysEx state;
- a bounded 2,048-message queue;
- RtMidi SysEx, timing, and active-sense filtering;
- Mach host-clock delivery deltas;
- CoreMIDI topology notifications;
- endpoint reconnection after removal and reappearance.

Source names include a stable `kMIDIPropertyUniqueID` suffix when available, or
an index suffix as a fallback. Version 0.5 migrates a legacy plain display-name
assignment only when exactly one current endpoint has that display name. It does
not silently resolve an ambiguous duplicate.

`rpcs3_ios_core_midi_topology_generation()` changes when CoreMIDI reports setup,
object, or relevant property changes. Hosts can refresh their source chooser when
that generation changes.

The three persistent adapter slots still map to keyboard, 17-fret guitar,
22-fret guitar, or drums. Actual endpoint discovery, packet timing, reconnect,
and emulated instrument behavior require physical-device and MIDI-hardware
proof.

## Firmware and package installation

Installers are synchronous and intended for a host-owned background queue.
Callbacks run on the calling thread. Cancellation may be requested from another
thread.

### Installer status

The legacy `rpcs3_ios_installation_status` remains available. Version 0.5 adds
`rpcs3_ios_installation_status_v2`, which reports:

- active and cancellation state;
- firmware/package kind;
- current stage and completed/total work;
- terminal state: none, succeeded, failed, or cancelled;
- the exact `rpcs3_ios_core_result`;
- a monotonically increasing operation ID.

The public last-installed path is cleared at operation start and populated only
for the matching successful operation. Hosts should correlate completion using
the operation ID rather than retaining a path from an earlier install.

### Transactional firmware commit

Firmware is no longer intentionally extracted directly into the live
`dev_flash` tree. Version 0.5:

1. recovers an earlier interrupted commit if a marker exists;
2. parses numeric firmware version components for downgrade rejection;
3. conservatively checks free space for the live copy, expanded PUP, and margin;
4. copies live firmware into a sibling staging tree;
5. redirects the raw RPCS3 PUP extraction path to that staging tree;
6. leaves the live tree unchanged on validation, extraction, or cancellation
   failure;
7. writes a transaction marker, moves live firmware to backup, and atomically
   renames staging into the live path;
8. rolls back the backup when activation fails;
9. remounts the live `/dev_flash` and refreshes emulator VFS state;
10. completes interrupted backup/staging cleanup during the next initialization.

The current conservative free-space estimate is not proof of every PUP's exact
expanded size. Filesystem rename behavior, legal PUP content, cancellation,
crash-recovery, and final firmware usability still require Apple filesystem and
runtime validation.

Package installation continues through RPCS3's package reader, extraction
workers, abort path, app-version check, and bootable-path result. A successful
bootable result is added to the normal game library. Package extraction can
still leave partial content after cancellation, matching upstream behavior; a
future package transaction layer may be needed after target-runtime validation.

## Native guest interfaces

The Qt-free callback composition supplies:

- message dialogs;
- OSK input;
- bounded save-data selection;
- trophy notifications;
- ImageIO metadata and orientation-aware scaled straight-RGBA8888 output;
- source-text UTF-8 and UTF-32 localization fallbacks;
- retained `AVAudioPlayer` sound playback.

Sound playback is main-queue confined, capped at 16 retained players, and fully
stopped during framework shutdown. Network send/receive dialogs, host camera,
host microphone, PS Move capture, and physical USB passthrough remain explicitly
unsupported rather than being represented by guessed implementations.

## Files and Open In

The management application registers specific UTIs for PUP, PKG, executable,
disc-image, and license content. It no longer registers itself for all
`public.data` files or every folder.

Open In routing:

1. holds the security-scoped URL while importing it into `Documents/Imports`;
2. prompts for PUP or PKG installation;
3. routes other supported imported content to direct boot;
4. copies C++ paths before asynchronous Objective-C block capture.

The management host polls framework operation and installer v2 status every
half-second. Open In operations therefore disable conflicting controls and share
progress/cancellation state with operations launched from the main host UI.

## Capabilities and diagnostics

`rpcs3_ios_core_query_capabilities()` reports the ABI version and compile-time
availability of Vulkan, LLVM, CoreMIDI, installers, native dialogs, and physical
USB passthrough. LLVM availability does not imply runtime executable-memory
permission.

Diagnostics include:

- framework/API version;
- initialization and render-host state;
- operation kind and generation;
- cached render metrics and drawable generation;
- game mappings and persistent roots;
- CoreMIDI source assignments and topology generation;
- installer operation ID, stage, progress, terminal state, result, and detail;
- JIT, entitlement, performance, memory, thermal, and platform state.

Diagnostics preserve the caller's prior last-error value.

## Build and validation layers

The dedicated workflow has two distinct levels:

1. Linux structural validation checks shell syntax, source anchors, declaration /
   export / implementation parity, build composition, operation admission,
   transactional settings and firmware contracts, lifecycle, renderer, MIDI,
   plist, and packaging invariants.
2. The `macos-latest` Apple SDK contract job lints plists and syntax-compiles
   public C, C++, and Objective-C++ consumers plus standalone CoreMIDI, Open In,
   lifecycle, and MIDI identity sources for an arm64 iOS simulator target.

The Apple SDK contract job is materially stronger than text validation, but it
is not a CMake/Xcode generation, full dependency compile, final framework link,
codesign, application launch, or emulator execution test.

## Evidence still required

Before describing this port as a working emulator, obtain all of the following:

- generate device and simulator Xcode projects from clean dependency prefixes;
- compile every selected dependency for the intended SDK and architecture;
- compile and final-link the low-level artifact, framework, management app, and
  optional Qt application;
- verify exported symbols, load commands, architectures, module import,
  framework embedding, and codesigning;
- create and consume `RPCS3Core.xcframework` from an independent application;
- repeatedly initialize, attach/refresh/clear a render view, invoke every public
  API, and shut down on an Apple runtime;
- install legally supplied firmware and packages, including failure,
  cancellation, low-space, overwrite, downgrade, and interrupted-commit paths;
- boot a legal workload and prove PPU/SPU interpreter behavior;
- validate or reject LLVM PPU/SPU recompilers under each supported signing and
  JIT-provider model;
- validate MoltenVK features against real RSX workloads and prove frame
  presentation and resize/swapchain recreation;
- validate dialogs, images, localization, sound, audio routes, rotation,
  lifecycle, external displays, controllers, touch, haptics, motion, lights,
  memory pressure, and thermal behavior;
- validate CoreMIDI hardware delivery and reconnection;
- resolve remaining Qt frontend assumptions;
- establish repeatable simulator, physical-device, signing, vphone, archive,
  and regression workflows.

Until those gates pass, 0.5 is a source-integrated, structurally validated, and
partially Apple-SDK-syntax-validated port architecture—not proof of a functioning
RPCS3 emulator on iOS or iPadOS.

## AI disclosure

OpenAI ChatGPT generated and applied the source changes on this branch through
the connected GitHub integration. A human contributor must review, understand,
build, test, and maintain the code before upstream submission. No simulator,
physical-device, firmware, package, MIDI hardware, JIT, legal workload, or frame
presentation test was performed while writing this document.
