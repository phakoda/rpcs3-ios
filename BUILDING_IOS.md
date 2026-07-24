# Building RPCS3 for iOS and iPadOS

The port has two build modes:

- **bootstrap**: a small native UIKit target that validates the iOS toolchain, MoltenVK, Metal surface creation, sandbox services, controllers, imports, audio-session setup, and JIT capability reporting;
- **full**: the RPCS3 emulator and Qt frontend with the iOS-specific dependency graph and runtime integration enabled.

The bootstrap is the first target to build on a new environment. A successful bootstrap does not mean PS3 software boots. The full target remains an integration workstream until it compiles, links, installs, and runs on an Apple device or research VM.

See [PORTING_IOS.md](PORTING_IOS.md) for architecture, reference implementations, and the feature-status matrix.

## Requirements

- Apple Silicon Mac;
- Xcode with iOS SDK and command-line tools;
- CMake 3.28 or newer;
- MoltenVK headers and an iOS/iOS Simulator static library;
- for full mode, a static FFmpeg build for the selected SDK;
- for full mode, a Qt iOS kit and matching macOS Qt host tools;
- a signing identity or supported alternative signing environment for device installation.

The repository does not provide firmware, games, Apple SDKs, signing credentials, or vphone guest state.

## Environment layout

The helper scripts accept explicit paths and do not install packages globally.

Typical variables:

```bash
export MOLTENVK_ROOT=/absolute/path/to/MoltenVK
export Qt6_DIR=/absolute/path/to/Qt/6.x/ios/lib/cmake/Qt6
export QT_HOST_PATH=/absolute/path/to/Qt/6.x/macos
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/rpcs3-ios/out/ffmpeg-device
```

`MOLTENVK_ROOT` is used for common archive-layout discovery. Override it with exact paths when necessary:

```bash
export Vulkan_INCLUDE_DIR=/absolute/path/to/MoltenVK/include
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
```

## Bootstrap: physical device

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh device bootstrap

cmake --build build-ios-device-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

Open `build-ios-device-bootstrap/rpcs3.xcodeproj`, select `rpcs3_ios_bootstrap`, choose a development team, and run on an iPhone or iPad.

Expected on-screen output includes the detected GPU, Vulkan version, Metal surface result, sandbox import path, JIT capability report, and hardware-controller summary. The bootstrap also exposes file/folder import buttons.

## Bootstrap: simulator

```bash
MOLTENVK_ROOT="$MOLTENVK_ROOT" \
  bash buildfiles/ios/configure.sh simulator bootstrap

cmake --build build-ios-simulator-bootstrap \
  --config Release \
  --target rpcs3_ios_bootstrap
```

MoltenVK must contain an arm64 iOS Simulator slice. A device archive cannot be linked into a simulator target.

## Build FFmpeg for iOS

Point `FFMPEG_SOURCE` at a legal FFmpeg source checkout:

```bash
export FFMPEG_SOURCE=/absolute/path/to/ffmpeg
bash buildfiles/ios/build_ffmpeg.sh device
```

The default device prefix is `out/ffmpeg-device`. For the simulator:

```bash
bash buildfiles/ios/build_ffmpeg.sh simulator
```

The default simulator prefix is `out/ffmpeg-simulator`.

Override the output or configure flags as needed:

```bash
OUTPUT_DIR=/absolute/path/to/ffmpeg-ios \
FFMPEG_EXTRA_CONFIGURE_FLAGS="--enable-bzlib" \
  bash buildfiles/ios/build_ffmpeg.sh device
```

Static FFmpeg builds vary with enabled codecs and external libraries. Pass additional link dependencies to CMake as a semicolon-separated list:

```bash
export RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES="/path/to/libfoo.a;/path/to/libbar.a"
```

## Validate dependencies

Bootstrap validation:

```bash
export Vulkan_INCLUDE_DIR=/absolute/path/to/include
export Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
bash buildfiles/ios/validate_environment.sh device
```

Full validation:

```bash
export VALIDATE_FULL_BUILD=1
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/ffmpeg-ios
export Qt6_DIR=/absolute/path/to/Qt/ios/lib/cmake/Qt6
export QT_HOST_PATH=/absolute/path/to/Qt/macos
bash buildfiles/ios/validate_environment.sh device
```

The validator checks required files and arm64 archive slices. It cannot prove that nested static libraries use the correct platform or that all transitive symbols are present; Xcode linking remains authoritative.

## Configure the full emulator target

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

Full configuration intentionally fails early when MoltenVK, FFmpeg, or Qt paths are missing. Nested source dependencies may reveal further iOS compile failures; fix those in dependency order rather than linking macOS host binaries.

## LLVM and JIT

The full target defaults to interpreter-first operation:

```text
RPCS3_IOS_ENABLE_LLVM=OFF
```

Enabling LLVM does not create a working JIT by itself. It only permits LLVM sources and link configuration to enter the build:

```bash
export RPCS3_IOS_ENABLE_LLVM=ON
```

The platform layer reports:

- `MAP_JIT` availability;
- whether a small `MAP_JIT` allocation succeeds;
- `pthread_jit_write_protect_np` availability;
- dynamic-code-signing and debugger entitlement visibility.

It also exposes a thread-local `jit_write_scope`, but generated-code execution still needs real device proof, instruction-cache publication, and a signing environment that grants the required capabilities.

### Entitlement profiles

Minimal development example:

```bash
export RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS=ON
```

Custom profile:

```bash
export RPCS3_IOS_ENTITLEMENTS_FILE="$PWD/rpcs3/ios/Research.entitlements"
```

`Research.entitlements` requests dynamic code signing, extended virtual addressing, and increased memory limit. Apple provisioning may reject or strip these values. Do not infer capability from the source plist; use the runtime report.

Do not add private sandbox-bypass or platform-security entitlements to distributable builds.

## Input

The full target registers `iOS GameController` as the default Player 1 handler.

Supported hardware values include:

- D-pad;
- four face buttons mapped by physical PlayStation position;
- L1/R1 and analog L2/R2;
- both analog sticks and L3/R3;
- menu, options, and home.

Without a hardware controller, a native multitouch overlay is attached to the game view. Connecting a hardware controller hides the overlay and gives hardware Player 1 priority.

## Files and imports

The app exposes its Documents directory in the Files app and registers common PS3-related extensions. Security-scoped selections are coordinated and copied to:

```text
Documents/Imports
```

The full Qt target installs a `QFileOpenEvent` filter so files sent to the app are copied into the same stable import directory.

Persistent configuration and installed emulator data remain under Application Support; regenerable data belongs in Caches.

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

The script creates an `.xcarchive` and, unless `ARCHIVE_ONLY=1`, an IPA-shaped ZIP under `out/ios`. A ZIP containing an unsigned app is not automatically installable on stock iOS.

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

The currently documented MCP tools control VM lifecycle, screenshots, taps, and swipes. They do not install application bundles. Use `deploy.sh device ...` when the guest appears in CoreDevice, or another locally authorized installation mechanism provided by the research environment.

Never commit guest disks, NVRAM, SEP storage, serial logs, firmware, personal data, provisioning profiles, certificates, or signing secrets.

## What remains unproven

Without an Apple build host and prepared runtime, source integration cannot establish:

- successful configuration of every nested dependency;
- successful full compilation and static linking;
- Qt Widgets behavior on iPhone/iPad;
- MoltenVK feature compatibility with real RSX workloads;
- interpreter or LLVM execution of PS3 code;
- firmware installation and legal workload boot;
- audio rendering, controller latency, touch ergonomics, thermal behavior, or memory stability.

Treat every one of those as an explicit evidence gate, not an assumed success.
