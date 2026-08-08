# Building RPCS3 for iOS and iPadOS

The port has three stages:

- **bootstrap** — native UIKit/MoltenVK platform diagnostics;
- **core** — Qt-free `rpcs3_emu`, `RPCS3Core.framework` 0.4, a framework-only UIKit management app, and whole-archive final-link artifacts;
- **full** — the core plus the desktop-derived Qt iOS frontend, GameController backend, and touch controls.

The source and target graph exists for every stage. This document does not claim successful Xcode generation, compilation, installation, or workload execution.

See [PORTING_IOS.md](PORTING_IOS.md) for architecture and status, and [IOS_CORE_API.md](IOS_CORE_API.md) for the public framework API.

## Requirements

- Apple Silicon Mac with Xcode and an iOS SDK;
- CMake 3.28 or newer;
- matching device/simulator MoltenVK and static FFmpeg builds;
- optionally, matching static LLVM target packages;
- Qt iOS plus matching macOS host tools for the full stage;
- a signing environment for physical-device installation.

The repository does not include firmware, games, Apple SDKs, signing credentials, or vphone guest state.

Typical variables:

```bash
export MOLTENVK_ROOT=/absolute/path/to/MoltenVK
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/out/ffmpeg-device
export RPCS3_IOS_LLVM_ROOT=/absolute/path/to/out/llvm-device
export Qt6_DIR=/absolute/path/to/Qt/6.x/ios/lib/cmake/Qt6
export QT_HOST_PATH=/absolute/path/to/Qt/6.x/macos
```

Override MoltenVK discovery when needed:

```bash
export Vulkan_INCLUDE_DIR="$MOLTENVK_ROOT/include"
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
```

## Stage 1: bootstrap

Device:

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh device bootstrap
cmake --build build-ios-device-bootstrap --config Release --target rpcs3_ios_bootstrap
```

Simulator:

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh simulator bootstrap
cmake --build build-ios-simulator-bootstrap --config Release --target rpcs3_ios_bootstrap
```

Use SDK-matching MoltenVK archives. A device archive cannot be linked into a simulator target.

The bootstrap console covers Vulkan portability enumeration, `VK_EXT_metal_surface`, public MoltenVK configuration, sandbox imports, memory and thermal state, controllers, external displays, signing/JIT diagnostics, public JIT-provider requests, and diagnostics export.

## Build FFmpeg

```bash
export FFMPEG_SOURCE=/absolute/path/to/ffmpeg
bash buildfiles/ios/build_ffmpeg.sh device
bash buildfiles/ios/build_ffmpeg.sh simulator
```

Default outputs are `out/ffmpeg-device` and `out/ffmpeg-simulator`. Static FFmpeg ordering and Apple media-framework closure are handled by `3rdparty/ios.cmake`.

## Stage 2: core

Device:

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
  bash buildfiles/ios/configure.sh device core
cmake --build build-ios-device-core --config Release --target rpcs3_ios_core
```

Simulator:

```bash
bash buildfiles/ios/configure.sh simulator core
cmake --build build-ios-simulator-core --config Release --target rpcs3_ios_core
```

The aggregate requires:

1. a low-level Mach-O executable that force-loads every `rpcs3_emu` object;
2. `RPCS3Core.framework`, which whole-archives the core behind a public C module and exported-symbol list;
3. `RPCS3 iOS Core.app`, which imports only `RPCS3Core.h` and exercises the public management surface.

Build individual products while narrowing link failures:

```bash
cmake --build build-ios-device-core --config Release --target rpcs3_ios_core_framework
cmake --build build-ios-device-core --config Release --target rpcs3_ios_core_link
```

`rpcs3_ios_core_archive` is a dependency wrapper, not a supported standalone monolithic archive.

### RPCS3Core.framework 0.4

The API includes:

- ordered initialization and shutdown plus lifecycle controls;
- CAMetalLayer-backed Vulkan host attachment with Null-RSX fallback;
- generation-checked main-queue events;
- security-scoped import into `Documents/Imports`;
- persistent mobile-safe settings and reset;
- `games.yml` enumeration and mutation;
- persistent scan-root add, unregister, rescan, prune, clear, and enumeration;
- public CoreMIDI source enumeration and three persistent Rock Band adapter mappings;
- synchronous cancellable PUP and PKG installers;
- thread-safe installer active/kind/stage/progress/cancellation/detail queries;
- JIT, performance, sandbox, metadata, diagnostics, and error APIs.

The UIKit management app exposes the renderer, import, lifecycle, installer, persistent-root, library, settings, CoreMIDI, and diagnostics operations.

### Persistent game roots

`Emulator::GetGameDirs()` describes the currently booted title and is not a library-root registry. The framework stores stable imported scan roots in `NSUserDefaults`, scans with `Emu.AddGamesFromDir`, and optionally removes mappings with `Emu.RemoveGamesFromDir`.

### CoreMIDI

The zero-port RtMidi stub is removed. A public CoreMIDI backend implements the RtMidi C ABI used by RPCS3's emulated Rock Band 3 adapters, including packet-boundary state, running status, interleaved real-time bytes, bounded SysEx/message queues, filtering, endpoint connection, and Mach-clock delta timing.

Three persistent slots can map a CoreMIDI source display name to keyboard, 17-fret guitar, 22-fret guitar, or drums. Duplicate display names can be ambiguous because upstream RPCS3 also maps by name.

Physical CoreMIDI behavior remains unvalidated until an Apple target is compiled and exercised.

### Unsupported peripherals

Generic physical USB passthrough is unavailable through public iOS APIs. The concrete libusb compatibility library reports zero host devices while preserving emulated USB devices.

Host camera, microphone, and PS Move capture remain disabled.

## Optional LLVM

```bash
export LLVM_SOURCE=/absolute/path/to/llvm-project
bash buildfiles/ios/build_llvm.sh device
bash buildfiles/ios/build_llvm.sh simulator
```

Enable a matching package:

```bash
export RPCS3_IOS_ENABLE_LLVM=ON
export RPCS3_IOS_LLVM_ROOT="$PWD/out/llvm-device"
```

A target LLVM package does not grant executable memory. Effective signing and runtime capability remain separate requirements.

## Stage 3: full frontend

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
Qt6_DIR="$Qt6_DIR" \
QT_HOST_PATH="$QT_HOST_PATH" \
  bash buildfiles/ios/configure.sh device full
cmake --build build-ios-device-full --config Release --target rpcs3
```

Resolve core-stage portability failures before Qt-specific frontend behavior.

## Validation

Environment and architecture checks:

```bash
bash buildfiles/ios/validate_environment.sh device bootstrap
bash buildfiles/ios/validate_environment.sh device core
bash buildfiles/ios/validate_environment.sh device full
```

Host-independent contracts:

```bash
python3 buildfiles/ios/validate_sources.py
python3 buildfiles/ios/validate_core.py
python3 buildfiles/ios/validate_callbacks.py
for helper in buildfiles/ios/*.sh; do bash -n "$helper"; done
```

These checks validate source/plist/generated-anchor contracts, public declaration/export/implementation parity, whole-archive linking, dependency ordering, concrete libusb/CoreMIDI ABIs, persistent settings/roots/MIDI mappings, installer status composition, native callbacks, and packaging. They do not invoke Xcode.

## Packaging

Archive the core management app and extract its framework:

```bash
bash buildfiles/ios/archive.sh core
```

Create a device/simulator XCFramework after both build trees are configured:

```bash
bash buildfiles/ios/create_core_xcframework.sh
```

Default output:

```text
out/ios/RPCS3Core.xcframework
```

Archive bootstrap or full:

```bash
bash buildfiles/ios/archive.sh bootstrap
bash buildfiles/ios/archive.sh full
```

Inspect effective signing:

```bash
bash buildfiles/ios/report_signing.sh /path/to/RPCS3.app
```

Do not add private sandbox-bypass, SpringBoardServices, platform-security, or private Metal entitlements.

## Deploy

```bash
LAUNCH=1 bash buildfiles/ios/deploy.sh simulator bootstrap
DEVICE=<identifier> LAUNCH=1 bash buildfiles/ios/deploy.sh device core
```

A vphone guest is usable only when it appears through CoreDevice. The vphone MCP surface does not install application bundles, and the repository excludes guest state and firmware.

## Evidence still required

This source work does not establish:

- successful device/simulator generation, compilation, or final linking;
- framework loading or repeated API execution;
- firmware/PKG installation or legal workload boot;
- CoreMIDI endpoint discovery, packet delivery, timing, or emulated instrument behavior;
- PPU/SPU interpreter or LLVM/JIT execution;
- MoltenVK feature compatibility or actual RSX frame presentation;
- stable lifecycle, rotation, displays, audio, controllers, touch, MIDI, thermal, or memory behavior;
- full Qt frontend usability.

Those remain explicit Apple-build and runtime evidence gates.
