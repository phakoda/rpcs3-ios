# RPCS3 iOS port architecture

This document tracks engineering status. It deliberately distinguishes source integration from build validation and runtime proof.

## Reference implementations

The platform layer follows patterns used by established open-source console emulator ports rather than inventing an unrelated iOS architecture:

- **PPSSPP**: AVAudioSession setup and interruption recovery, GameController connection notifications, security-scoped document coordination, stable sandbox copies, and iOS-specific packaging.
- **Play!**: a small native application lifecycle boundary around a portable emulator core.
- **DolphiniOS and Provenance**: explicit separation between ordinary iOS builds and signing environments that can provide executable-memory capabilities.

The implementation is RPCS3-specific. No source was copied verbatim; the references informed lifecycle boundaries, service selection, and failure handling.

## Build modes

### Bootstrap

`RPCS3_IOS_BOOTSTRAP_ONLY=ON` builds a native UIKit application with minimal dependencies. It exercises:

- Objective-C++ compilation;
- MoltenVK static linkage;
- Vulkan portability enumeration;
- `VK_EXT_metal_surface` creation from `CAMetalLayer`;
- sandbox directory creation;
- AVAudioSession activation;
- JIT entitlement and `MAP_JIT` capability reporting;
- hardware controller enumeration;
- security-scoped file and directory import.

It does not link the emulator core.

### Full

`RPCS3_IOS_BOOTSTRAP_ONLY=OFF` selects the iOS third-party graph, Qt iOS frontend, mobile runtime services, GameController pad handler, touch overlay, and full RPCS3 targets.

The full mode is an integration target. It is expected to reveal additional compile and link failures until every portable dependency and desktop assumption has been resolved on an actual Xcode host.

## Platform services

The reusable service library under `rpcs3/ios/platform/` provides:

| Area | Source | Status |
| --- | --- | --- |
| Sandbox paths | `IOSPlatform.mm` | Application Support, Caches, Documents, Imports, and temporary paths are created and exposed. |
| Files app | `IOSPlatform.mm`, `IOSRuntimeIntegration.cpp` | Document picker and Qt file-open events copy security-scoped files or directories into `Documents/Imports`. |
| Audio lifecycle | `IOSPlatform.mm` | AVAudioSession category, 48 kHz preference, buffer preference, interruption recovery, and deactivation are implemented. |
| Application lifecycle | `IOSPlatform.mm`, `IOSRuntimeIntegration.cpp` | Inactive/background and audio interruptions pause emulation only when RPCS3 initiated the pause; activation resumes it. |
| Controllers | `IOSPlatform.mm` | Hardware `GCController` snapshots include face buttons, D-pad, sticks, triggers, shoulders, thumbstick clicks, menu, options, and home. |
| Touch input | `IOSTouchController.mm`, `IOSVirtualController.cpp` | Native multitouch DualShock-style overlay feeds the same pad backend; hardware controllers take priority and hide it. |
| Pad backend | `Input/ios_gamecontroller_pad_handler.*` | Registered RPCS3 handler with PS3 layout mapping, analog values, triggers, defaults, deadzones, and stable logical names. |
| Mobile performance | `IOSPerformance.mm` | Thermal state, Low Power Mode, physical memory, memory warnings, and idle-timer control are exposed. |
| JIT preflight | `IOSPlatform.mm`, `IOSJIT.mm` | Reports entitlements and `MAP_JIT`; provides thread-local write/executable transitions. LLVM remains opt-in. |
| Vulkan view bridge | `metal_layer.mm` | Accepts `UIView` on iOS and `NSView` on macOS. |

## Third-party dependency policy

`3rdparty/ios.cmake` prevents the cross-build from accidentally resolving macOS host libraries.

Portable bundled dependencies remain source-built where practical. MoltenVK and FFmpeg must be supplied as matching iOS or iOS Simulator builds. Qt must come from an iOS kit with matching macOS host tools.

Desktop-only integrations are replaced by feature-disabled interface targets during initial bring-up:

- libevdev;
- HIDAPI and libusb device backends;
- OpenAL and FAudio;
- SDL input;
- OpenCV camera tracking;
- RtMidi;
- Discord RPC.

This does not claim that every portable dependency already cross-compiles. Protobuf host-tool generation, curl/wolfSSL configuration, LLVM cross-linking, and other nested projects may still require targeted fixes once Xcode configuration reaches them.

## Input model

The iOS handler exposes logical devices named `iOS Controller 1`, `iOS Controller 2`, and so on.

When one or more hardware controllers are connected, they occupy the first logical slots. The touch overlay is appended after them and hidden. Without hardware, the touch overlay becomes Player 1.

Face buttons are mapped by physical position:

| Apple gamepad position | PS3 control |
| --- | --- |
| Bottom / A | Cross |
| Right / B | Circle |
| Left / X | Square |
| Top / Y | Triangle |

## Filesystem model

Persistent emulator state belongs in the application sandbox:

- RPCS3 configuration and installed system data: Application Support;
- regenerable caches: Caches;
- user-visible imports: Documents/Imports;
- transient work: temporary directory.

The existing Apple configuration path logic already resolves through the sandbox `HOME`. An iOS-generated adaptation changes application-bundle discovery because iOS executables live directly inside the `.app`, unlike macOS executables under `Contents/MacOS`.

Generated adaptations fail CMake configuration when their upstream anchor moves. This prevents a silent stale patch while avoiding broad forks of shared desktop source files.

## Executable memory

RPCS3 already requests `MAP_JIT` on Apple. The iOS platform layer additionally:

- reports whether `MAP_JIT` is available;
- attempts a small allocation without executing code;
- reports relevant signing entitlements;
- exposes `pthread_jit_write_protect_np` through `set_jit_write_protection` and `jit_write_scope`.

`RPCS3_IOS_ENABLE_LLVM` defaults to `OFF`. The initial full target should use interpreter paths until a supported signing environment demonstrates allocation, write protection transitions, instruction-cache publication, and generated-code execution.

Included entitlement files are examples, not grants:

- `JIT.entitlements`: dynamic code signing only;
- `Research.entitlements`: dynamic code signing plus extended virtual addressing and increased memory limit.

A provisioning/signing environment may reject or strip any entitlement. Runtime reporting is authoritative.

## Graphics

The supported renderer is Vulkan through MoltenVK. Desktop OpenGL is disabled.

Both the bootstrap and full renderer use `VK_EXT_metal_surface`. The older `VK_MVK_ios_surface` path is intentionally not used.

Remaining graphics work requires a device build and includes shader/compiler compatibility, MoltenVK feature gaps, swapchain lifecycle during rotation/backgrounding, memory pressure behavior, and real RSX workloads.

## Mobile lifecycle behavior

The full target initializes native services only after Qt has created its application bridge. Cleanup is connected to `QCoreApplication::aboutToQuit`, before the Qt application object is destroyed.

RPCS3 pauses for two independently tracked reasons:

- application inactive/background transition;
- AVAudioSession interruption.

It resumes only after every active reason clears and only if the iOS integration performed the pause.

## Build and deployment tools

- `buildfiles/ios/configure.sh`: bootstrap or full Xcode configuration for device/simulator.
- `buildfiles/ios/build_ffmpeg.sh`: static arm64 FFmpeg cross-build.
- `buildfiles/ios/validate_environment.sh`: SDK, architecture, MoltenVK, FFmpeg, and Qt validation.
- `buildfiles/ios/archive.sh`: signed or unsigned xcarchive and IPA-shaped package.
- `buildfiles/ios/deploy.sh`: simulator or CoreDevice installation and launch.

A vphone guest can use `deploy.sh device ...` when it appears in CoreDevice. The current vphone MCP surface provides VM lifecycle, screenshot, tap, and swipe operations, but not app installation.

## Remaining blockers

Source work can reduce, but not honestly eliminate, these blockers without an Apple build/runtime environment:

1. configure and compile every nested dependency with an iOS SDK;
2. resolve Qt Widgets behavior and unsupported desktop dialogs on iPhone-sized screens;
3. prove PPU/SPU interpreter operation;
4. prove or reject LLVM JIT under the selected signing model;
5. validate MoltenVK device features against RPCS3 requirements;
6. integrate microphone/camera permissions and backends where useful;
7. handle memory warnings with targeted cache eviction;
8. install legal firmware and boot a legal test workload;
9. exercise background/foreground, rotation, audio route changes, controllers, touch input, Files imports, and thermal throttling on device;
10. establish repeatable physical-device and vphone smoke tests.

Until those steps succeed, the repository should describe the work as an iOS port in progress, not a functioning PS3 emulator release.
