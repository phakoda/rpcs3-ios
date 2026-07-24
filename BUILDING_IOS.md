# Building RPCS3 for iOS and iPadOS

The port has three build stages:

- **bootstrap**: a native UIKit developer console for the iOS toolchain, MoltenVK, Metal surfaces, sandbox services, controllers, memory pressure, external displays, signing, and JIT capability diagnostics;
- **core**: `rpcs3_emu` and portable dependencies without the desktop-derived Qt frontend;
- **full**: core plus the Qt iOS frontend, application bundle, Files integration, GameController pad handler, and touch controls.

Build them in that order on a new environment. A successful bootstrap or static core archive does not mean PS3 software boots.

See [PORTING_IOS.md](PORTING_IOS.md) for architecture, reference implementations, safety boundaries, and remaining evidence gates.

## Requirements

- Apple Silicon Mac;
- Xcode with iOS SDK and command-line tools;
- CMake 3.28 or newer;
- MoltenVK headers and an iOS/iOS Simulator static library;
- for core/full stages, a static FFmpeg build for the selected SDK;
- optionally, a static target LLVM build for the selected SDK;
- for the full stage, a Qt iOS kit and matching macOS Qt host tools;
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

`MOLTENVK_ROOT` is used for common archive-layout discovery. Override it with exact paths when necessary:

```bash
export Vulkan_INCLUDE_DIR=/absolute/path/to/MoltenVK/include
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
```

## Stage 1: bootstrap

### Physical device

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh device bootstrap

cmake --build build-ios-device-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

Open `build-ios-device-bootstrap/rpcs3.xcodeproj`, select `rpcs3_ios_bootstrap`, choose a development team, and run on an iPhone or iPad.

The scrollable bootstrap console reports:

- GPU, Vulkan version, and Metal surface creation;
- MoltenVK mobile configuration;
- sandbox and import paths;
- physical and available memory;
- thermal, Low Power Mode, and memory-pressure state;
- controller motion, haptics, battery, and external display capabilities;
- effective signing/JIT/debugger capabilities.

It also provides file/folder import, an explicit ARM64 executable-memory probe, public external-JIT provider requests, and exportable diagnostics.

### Simulator

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh simulator bootstrap

cmake --build build-ios-simulator-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

MoltenVK must contain an arm64 iOS Simulator slice. Device archives cannot be linked into simulator targets.

## Build FFmpeg

Point `FFMPEG_SOURCE` at an FFmpeg source checkout:

```bash
export FFMPEG_SOURCE=/absolute/path/to/ffmpeg
bash buildfiles/ios/build_ffmpeg.sh device
```

For the simulator:

```bash
bash buildfiles/ios/build_ffmpeg.sh simulator
```

Default prefixes are `out/ffmpeg-device` and `out/ffmpeg-simulator`.

Override output or configure flags as needed:

```bash
OUTPUT_DIR=/absolute/path/to/ffmpeg-ios \
FFMPEG_EXTRA_CONFIGURE_FLAGS="--enable-bzlib" \
  bash buildfiles/ios/build_ffmpeg.sh device
```

Static FFmpeg builds vary with enabled codecs and external libraries. Pass additional link dependencies as a semicolon-separated list:

```bash
export RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES="/path/to/libfoo.a;/path/to/libbar.a"
```

## Stage 2: emulator core

The core stage is the preferred target for resolving C/C++ and nested dependency failures because it does not instantiate Qt Widgets, desktop HID stacks, PS Move dialogs, or an app bundle.

### Device core

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
  bash buildfiles/ios/configure.sh device core

cmake --build build-ios-device-core \
  --config Release \
  --target rpcs3_ios_core
```

### Simulator core

Use simulator builds of MoltenVK and FFmpeg:

```bash
bash buildfiles/ios/configure.sh simulator core
cmake --build build-ios-simulator-core --config Release --target rpcs3_ios_core
```

`rpcs3_ios_core` is a static archive milestone. It pulls `rpcs3_emu` and generated iOS memory/filesystem adaptations but is not installable or runnable by itself.

## Optional LLVM target build

LLVM remains disabled by default. The helper performs a two-stage build: native macOS `llvm-tblgen`, then static AArch64 target libraries for the chosen iOS SDK.

```bash
export LLVM_SOURCE=/absolute/path/to/llvm-project
bash buildfiles/ios/build_llvm.sh device
```

For the simulator:

```bash
bash buildfiles/ios/build_llvm.sh simulator
```

Default prefixes are `out/llvm-device` and `out/llvm-simulator`. Enable the target package during core/full configuration:

```bash
export RPCS3_IOS_ENABLE_LLVM=ON
export RPCS3_IOS_LLVM_ROOT="$PWD/out/llvm-device"
```

Enabling LLVM does not grant executable memory. It only makes the recompilers available to the target build.

## Stage 3: full frontend

Interpreter-first device configuration:

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
RPCS3_IOS_FFMPEG_ROOT="$RPCS3_IOS_FFMPEG_ROOT" \
Qt6_DIR="$Qt6_DIR" \
QT_HOST_PATH="$QT_HOST_PATH" \
  bash buildfiles/ios/configure.sh device full
```

Then build:

```bash
cmake --build build-ios-device-full \
  --config Release \
  --target rpcs3
```

Simulator full mode uses matching simulator MoltenVK and FFmpeg builds:

```bash
bash buildfiles/ios/configure.sh simulator full
cmake --build build-ios-simulator-full --config Release --target rpcs3
```

Full configuration intentionally fails early when MoltenVK, FFmpeg, LLVM, or Qt target inputs are missing. Resolve portable dependency failures in the core stage first, then address Qt-specific failures without linking macOS host libraries.

## Validate dependencies

Bootstrap:

```bash
export Vulkan_INCLUDE_DIR=/absolute/path/to/include
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
bash buildfiles/ios/validate_environment.sh device bootstrap
```

Core:

```bash
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/ffmpeg-ios
bash buildfiles/ios/validate_environment.sh device core
```

LLVM-enabled core:

```bash
export RPCS3_IOS_ENABLE_LLVM=ON
export RPCS3_IOS_LLVM_ROOT=/absolute/path/to/llvm-ios
bash buildfiles/ios/validate_environment.sh device core
```

Full:

```bash
export Qt6_DIR=/absolute/path/to/Qt/ios/lib/cmake/Qt6
export QT_HOST_PATH=/absolute/path/to/Qt/macos
bash buildfiles/ios/validate_environment.sh device full
```

The validator checks files, arm64 slices, and Mach-O `LC_BUILD_VERSION` platform metadata to catch device/simulator mismatches before Xcode linking.

Host-independent source checks can run anywhere with Python 3 and Bash:

```bash
python3 buildfiles/ios/validate_sources.py
for helper in buildfiles/ios/*.sh; do bash -n "$helper"; done
```

These validate plists, generated-source anchors, controller/JIT/dependency contracts, and selected private-API safety boundaries. They are not iOS build tests.

## JIT capability workflow

The bootstrap and full platform layer report:

- `MAP_JIT` allocation;
- `pthread_jit_write_protect_np` availability;
- debugger attachment;
- dynamic-code-signing, allow-JIT, extended-addressing, and increased-memory entitlements;
- dual writable/executable aliases through `mach_vm_remap`;
- instruction-cache publication;
- an explicit ARM64 function returning `42`.

RPCS3's native WX/RX memory transitions also toggle Apple thread-local JIT write protection and invalidate the generated-code cache.

### External providers

The bootstrap can request JIT through public integration points inspired by MeloNX:

- TrollStore / Apple Magnifier deep link;
- StikJIT / StikDebug deep link;
- local JitStreamer attach endpoint.

The app then polls effective capability rather than treating a successful URL open as proof of attachment. Provider availability and behavior depend on the user's environment.

### Entitlement profiles

Minimal development example:

```bash
export RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS=ON
```

Custom profile:

```bash
export RPCS3_IOS_ENTITLEMENTS_FILE="$PWD/rpcs3/ios/Research.entitlements"
```

`Research.entitlements` requests dynamic code signing, extended virtual addressing, and increased memory limit. Provisioning may reject or strip them. Source plists are not evidence.

Inspect a built app:

```bash
bash buildfiles/ios/report_signing.sh /path/to/RPCS3.app
```

Signed archives run the same report automatically.

Do not add private sandbox-bypass, SpringBoardServices, platform-security, or private Metal API entitlements/configuration to distributable builds.

## Input

The full target registers `iOS GameController` as the default Player 1 handler.

Supported hardware data and output include:

- stable GameController player slots;
- D-pad and four face buttons mapped by PlayStation position;
- L1/R1, analog L2/R2, both sticks, L3/R3, menu, options, and home;
- controller motion with device CoreMotion fallback;
- battery and charging state;
- persistent low/high CoreHaptics vibration;
- configured RPCS3 RGB controller-light output where supported.

Without hardware, a native multitouch overlay is attached to the game view. Connecting hardware hides the overlay and gives hardware Player 1 priority.

The optional Qt stage replaces unsupported USB/HID DualShock, skateboard, and PS Move gameplay factories with null handlers instead of compiling those desktop backends accidentally.

## Files and diagnostics

The app exposes Documents in the Files app and registers common PS3-related extensions. Security-scoped selections are coordinated and copied to:

```text
Documents/Imports
```

The full Qt target installs a `QFileOpenEvent` filter so files sent to the app are copied into the same stable import directory.

Persistent configuration and installed emulator data remain under Application Support. Regenerable data and diagnostics belong in Caches.

Use **Export Diagnostics** in the bootstrap to share a text report containing device/OS/app versions, memory state, JIT capability, MoltenVK configuration, controller capabilities, paths, and external-screen state.

## Archive and package

Unsigned archive and IPA-shaped ZIP:

```bash
bash buildfiles/ios/archive.sh bootstrap
bash buildfiles/ios/archive.sh full
```

Signed archive:

```bash
DEVELOPMENT_TEAM=ABCDE12345 \
  bash buildfiles/ios/archive.sh full
```

Optional signing overrides:

```bash
DEVELOPMENT_TEAM=ABCDE12345 \
CODE_SIGN_IDENTITY="Apple Development" \
PROVISIONING_PROFILE_SPECIFIER="RPCS3 Development" \
  bash buildfiles/ios/archive.sh full
```

The script creates an `.xcarchive` and, unless `ARCHIVE_ONLY=1`, an IPA-shaped ZIP under `out/ios`. An unsigned ZIP is not automatically installable on stock iOS.

## Deploy

Install and launch on the booted simulator:

```bash
LAUNCH=1 bash buildfiles/ios/deploy.sh simulator bootstrap
```

Install on a CoreDevice-visible iPhone, iPad, or research guest:

```bash
DEVICE=<name-or-identifier> \
LAUNCH=1 \
  bash buildfiles/ios/deploy.sh device full
```

Set `APP_PATH=/absolute/path/to/RPCS3.app` to deploy an existing bundle without querying Xcode build settings.

## vphone

`phakoda/vphone-aio-mcp` can run a research iPhone guest on a correctly configured Apple Silicon host. Its repository intentionally excludes firmware and guest VM state.

Its documented MCP tools control VM lifecycle, screenshots, taps, and swipes. They do not install app bundles. Use `deploy.sh device ...` when the guest appears in CoreDevice, or another locally authorized installation mechanism provided by the research environment.

Never commit guest disks, NVRAM, SEP storage, serial logs, firmware, personal data, provisioning profiles, certificates, or signing secrets.

## What remains unproven

Without an Apple build host and prepared runtime, source integration cannot establish:

- successful configuration of every nested dependency;
- successful core/full compilation and static linking;
- Qt Widgets behavior on iPhone/iPad;
- MoltenVK compatibility with real RSX workloads;
- interpreter or LLVM execution of PS3 code;
- external-screen renderer migration;
- firmware installation and legal workload boot;
- audio rendering, controller latency, touch ergonomics, thermal behavior, or memory stability.

Treat each item as an explicit evidence gate, not an assumed success.
