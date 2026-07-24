# Building RPCS3 for iOS and iPadOS

The port has three build stages:

- **bootstrap**: a native UIKit developer console for MoltenVK, Metal surfaces, sandbox services, controllers, signing, memory pressure, displays, and JIT capability diagnostics;
- **core**: the Qt-free emulator core, complete static dependency closure, `RPCS3Core.framework`, a public-C-API consumer app, and low-level whole-archive link artifact;
- **full**: the core plus the desktop-derived Qt iOS frontend, application bundle, native runtime integration, GameController backend, and touch controls.

Build them in that order on a new Apple environment. The repository contains the source and target graph for every stage, but no device or simulator build is claimed by this document.

See [PORTING_IOS.md](PORTING_IOS.md) for architecture, status, reference implementations, safety boundaries, and remaining evidence gates.

## Requirements

- Apple Silicon Mac;
- Xcode with an iOS SDK and command-line tools;
- CMake 3.28 or newer;
- MoltenVK headers and a matching static library for iOS or iOS Simulator;
- a matching static FFmpeg build for core/full targets;
- optionally, a matching static LLVM target package;
- for the full target, a Qt iOS kit and matching macOS Qt host tools;
- a signing identity or supported alternative signing environment for device installation.

The repository does not provide firmware, games, Apple SDKs, signing credentials, or vphone guest state.

## Environment layout

Typical variables:

```bash
export MOLTENVK_ROOT=/absolute/path/to/MoltenVK
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/rpcs3-ios/out/ffmpeg-device
export RPCS3_IOS_LLVM_ROOT=/absolute/path/to/rpcs3-ios/out/llvm-device
export Qt6_DIR=/absolute/path/to/Qt/6.x/ios/lib/cmake/Qt6
export QT_HOST_PATH=/absolute/path/to/Qt/6.x/macos
```

Override MoltenVK discovery when necessary:

```bash
export Vulkan_INCLUDE_DIR=/absolute/path/to/MoltenVK/include
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
```

## Stage 1: bootstrap

### Device

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh device bootstrap

cmake --build build-ios-device-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

Open `build-ios-device-bootstrap/rpcs3.xcodeproj`, select `rpcs3_ios_bootstrap`, choose a development team, and run on an iPhone or iPad.

The bootstrap console contains:

- Vulkan portability enumeration and `VK_EXT_metal_surface` creation;
- adaptive public MoltenVK configuration;
- sandbox paths and file/folder import;
- physical and available memory, thermal state, Low Power Mode, and memory pressure;
- controller motion, battery, haptics, and light capability reporting;
- external-display reporting;
- signing, debugger, MAP_JIT, dual-mapping, and executable-code diagnostics;
- public Apple Magnifier, StikJIT, and JitStreamer requests;
- a shareable diagnostics report.

### Simulator

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh simulator bootstrap

cmake --build build-ios-simulator-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

A device MoltenVK archive cannot be linked into a simulator target.

## Build FFmpeg

```bash
export FFMPEG_SOURCE=/absolute/path/to/ffmpeg
bash buildfiles/ios/build_ffmpeg.sh device
bash buildfiles/ios/build_ffmpeg.sh simulator
```

Default prefixes are `out/ffmpeg-device` and `out/ffmpeg-simulator`.

Optional overrides:

```bash
OUTPUT_DIR=/absolute/path/to/ffmpeg-ios \
FFMPEG_EXTRA_CONFIGURE_FLAGS="--enable-bzlib" \
  bash buildfiles/ios/build_ffmpeg.sh device

export RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES="/path/to/libfoo.a;/path/to/libbar.a"
```

The iOS CMake graph keeps static FFmpeg users before their dependencies, repeats `avcodec` and `avutil` to close optional archive cycles, and links the required public Apple media frameworks through `3rdparty::ios_system`.

## Stage 2: core and complete linking

Configure device core:

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
  bash buildfiles/ios/configure.sh device core
```

Configure simulator core with simulator MoltenVK and FFmpeg inputs:

```bash
bash buildfiles/ios/configure.sh simulator core
```

### Core aggregate

```bash
cmake --build build-ios-device-core \
  --config Release \
  --target rpcs3_ios_core
```

`rpcs3_ios_core` is an aggregate milestone. It requires all of these products:

1. **Low-level final-link artifact** — force-loads every object from `rpcs3_emu`, so unresolved core, Objective-C++, dependency, and Apple-framework symbols cannot remain hidden in a static archive.
2. **`RPCS3Core.framework`** — whole-archives the adapted emulator core behind a stable C ABI, explicit module map, hidden internal C++ visibility, exported-symbol list, and linker map.
3. **`RPCS3 iOS Core.app`** — imports only `RPCS3Core.h`, embeds the framework, imports security-scoped content, issues headless boot requests, and exposes pause, resume, stop, state, metadata, event, JIT, and diagnostics controls.

The small `rpcs3_ios_core_archive` CMake target is a dependency wrapper, not a standalone monolithic `.a`. Use `RPCS3Core.framework` for embedding.

Build individual products when narrowing a link failure:

```bash
cmake --build build-ios-device-core --config Release --target rpcs3_ios_core_framework
cmake --build build-ios-device-core --config Release --target rpcs3_ios_core_link
```

The core framework currently uses a **Null RSX output**. Its lifecycle API reaches the real RPCS3 `Emulator` object and includes native GameController pad initialization and Cubeb/null audio selection, but a UIKit/Metal renderer host remains separate work.

### Public framework API

`RPCS3Core/RPCS3Core.h` exposes C-compatible functions for:

- initialization and ordered shutdown;
- event callbacks;
- security-scoped import into `Documents/Imports`;
- headless boot, restart, pause, resume, and stop;
- emulator state, title, title ID, and boot path;
- sandbox paths;
- JIT and memory status;
- diagnostics and error strings;
- MoltenVK default configuration.

The import API supports a normal two-call buffer-size pattern without copying the selected item twice.

### Unsupported host peripherals

Public iOS APIs do not provide generic desktop USB passthrough. The core therefore links a concrete libusb compatibility library that reports zero host devices while retaining RPCS3's emulated USB devices.

MIDI adapter emulation links a concrete RtMidi compatibility library that reports no host ports until a native CoreMIDI bridge is implemented. Empty interface targets are used only for feature-guarded desktop integrations that the core does not compile.

## Optional LLVM target build

LLVM remains disabled by default. The helper builds native macOS `llvm-tblgen`, then static AArch64 libraries for the selected iOS SDK:

```bash
export LLVM_SOURCE=/absolute/path/to/llvm-project
bash buildfiles/ios/build_llvm.sh device
bash buildfiles/ios/build_llvm.sh simulator
```

Enable the matching target package during core/full configuration:

```bash
export RPCS3_IOS_ENABLE_LLVM=ON
export RPCS3_IOS_LLVM_ROOT="$PWD/out/llvm-device"
```

Enabling LLVM does not grant executable memory. Provisioning and runtime capability still determine whether recompilers can execute.

## Stage 3: full frontend

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
Qt6_DIR="$Qt6_DIR" \
QT_HOST_PATH="$QT_HOST_PATH" \
  bash buildfiles/ios/configure.sh device full

cmake --build build-ios-device-full \
  --config Release \
  --target rpcs3
```

Simulator full mode requires matching simulator dependencies:

```bash
bash buildfiles/ios/configure.sh simulator full
cmake --build build-ios-simulator-full --config Release --target rpcs3
```

Resolve portable failures in the core stage first, then address Qt-specific behavior without linking macOS host libraries.

## Validate inputs and source contracts

Dependency/platform validation:

```bash
bash buildfiles/ios/validate_environment.sh device bootstrap
bash buildfiles/ios/validate_environment.sh device core
bash buildfiles/ios/validate_environment.sh device full
```

Set the dependency variables required by each stage before running the command. The validator checks files, arm64 slices, and Mach-O `LC_BUILD_VERSION` metadata.

Host-independent checks:

```bash
python3 buildfiles/ios/validate_sources.py
python3 buildfiles/ios/validate_core.py
for helper in buildfiles/ios/*.sh; do bash -n "$helper"; done
```

`validate_core.py` checks public-header/implementation/export parity, boot-enum parity, framework whole-archive and embedding contracts, generated Qt-free pad sources, concrete libusb/RtMidi ABIs, FFmpeg ordering, core defaults, and XCFramework packaging. These are structural checks, not Apple target builds.

## Package the core

Archive the device consumer app and extract its embedded device framework:

```bash
bash buildfiles/ios/archive.sh core
```

Outputs under `out/ios` include:

- `RPCS3-iOS-Core-Link.xcarchive`;
- `RPCS3-iOS-Core-Link.ipa` unless `ARCHIVE_ONLY=1`;
- `RPCS3Core-device.framework`.

Create a device/simulator XCFramework after configuring both core build trees:

```bash
bash buildfiles/ios/create_core_xcframework.sh
```

Default output:

```text
out/ios/RPCS3Core.xcframework
```

The helper verifies arm64 slices and the public header before calling `xcodebuild -create-xcframework`.

## Archive bootstrap or full app

```bash
bash buildfiles/ios/archive.sh bootstrap
bash buildfiles/ios/archive.sh full
```

Signed example:

```bash
DEVELOPMENT_TEAM=ABCDE12345 \
CODE_SIGN_IDENTITY="Apple Development" \
PROVISIONING_PROFILE_SPECIFIER="RPCS3 Development" \
  bash buildfiles/ios/archive.sh full
```

An unsigned IPA-shaped ZIP is not automatically installable on stock iOS.

## JIT capability workflow

The platform reports:

- MAP_JIT allocation;
- `pthread_jit_write_protect_np` availability;
- debugger attachment and effective entitlements;
- separate writable/executable aliases through `mach_vm_remap`;
- instruction-cache publication;
- an explicit ARM64 function-execution probe.

RPCS3's native WX/RX transitions also use Apple's thread-local JIT write protection and invalidate generated code.

Optional entitlement selection:

```bash
export RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS=ON
# or
export RPCS3_IOS_ENTITLEMENTS_FILE="$PWD/rpcs3/ios/Research.entitlements"
```

Provisioning may reject or strip requested entitlements. Inspect the effective app:

```bash
bash buildfiles/ios/report_signing.sh /path/to/RPCS3.app
```

Do not add private sandbox-bypass, SpringBoardServices, platform-security, or private Metal API entitlements to distributable builds.

## Input and files

The core framework's generated pad thread removes Qt keyboard/window code, substitutes null handlers for unsupported desktop HID devices, and inserts the native iOS GameController handler. The full target additionally attaches the multitouch overlay to the game view.

Hardware support includes stable player slots, analog input, controller/device motion, battery state, persistent CoreHaptics output, and supported RGB lights.

Security-scoped items are coordinated and copied into:

```text
Documents/Imports
```

Persistent configuration and installed emulator data remain under Application Support. Regenerable data and diagnostics belong in Caches.

## Deploy

```bash
LAUNCH=1 bash buildfiles/ios/deploy.sh simulator bootstrap

DEVICE=<name-or-identifier> \
LAUNCH=1 \
  bash buildfiles/ios/deploy.sh device core
```

Set `APP_PATH=/absolute/path/to/RPCS3.app` to deploy an existing bundle.

A vphone guest can use the device path when it appears in CoreDevice. The vphone MCP surface does not install application bundles and the repository intentionally excludes guest state and firmware.

## Evidence still required

Without an Apple build host and prepared runtime, this source work does not establish:

- successful device or simulator CMake generation;
- successful compilation of every nested dependency;
- successful final linking of the low-level artifact, framework, or consumer app;
- successful framework loading or API execution;
- successful firmware installation or legal workload boot;
- PPU/SPU interpreter behavior;
- LLVM/JIT execution under any signing model;
- MoltenVK compatibility with real RSX workloads;
- renderer presentation, rotation, backgrounding, or external-display migration;
- stable audio, input, thermal, or memory behavior on hardware;
- full Qt frontend usability.

Those are explicit Apple-build and runtime evidence gates, not assumed results.
