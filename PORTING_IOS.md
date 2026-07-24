# RPCS3 iOS port architecture and status

This document tracks engineering status. It deliberately distinguishes source integration from build validation and runtime proof.

## Reference implementations

The platform layer follows patterns used by established open-source console-emulator ports rather than inventing an unrelated iOS architecture:

- **PPSSPP**: AVAudioSession interruption recovery, GameController notifications, security-scoped document coordination, stable sandbox copies, and iOS packaging.
- **Play!**: a small native application-lifecycle boundary around a portable emulator core.
- **DolphiniOS and Provenance**: explicit separation between ordinary builds and signing environments that can provide executable-memory capabilities.
- **MeloNX**: dual-mapped JIT memory, entitlement/debugger capability checks, public external-JIT provider links, stable GameController player slots, controller motion with CoreMotion fallback, persistent CoreHaptics output, external-screen awareness, and mobile MoltenVK configuration.

The original MeloNX forge at `git.ryujinx.app/projects/MeloNX` may require an interactive anti-bot challenge. Source review for this work used the public `VertexSelection/MeloVertex` mirror and its `XC-ios-ht` branch.

No source was copied verbatim. The implementations here use RPCS3 types, build targets, renderer boundaries, and pad-processing callbacks.

MeloNX also contains research-only private API and private Metal configuration paths. RPCS3 intentionally does **not** adopt SpringBoardServices calls, private sandbox-bypass entitlements, private Metal API toggles, or TXM/private framework hooks.

## Build stages

### 1. Bootstrap

`RPCS3_IOS_BOOTSTRAP_ONLY=ON` builds a native UIKit developer console with minimal emulator dependencies. It exposes:

- Objective-C++ and UIKit application bring-up;
- adaptive MoltenVK environment configuration;
- Vulkan portability enumeration and `VK_EXT_metal_surface` creation;
- sandbox directory creation and security-scoped imports;
- AVAudioSession activation;
- signing, debugger, `MAP_JIT`, dual-mapping, and executable-code diagnostics;
- public TrollStore/Apple Magnifier, StikJIT, and JitStreamer request paths;
- controller input, motion, battery, haptics, and light capabilities;
- memory pressure, available-memory, thermal, and Low Power Mode status;
- external display/AirPlay screen status;
- an exportable diagnostics report.

It does not link the emulator core.

### 2. Core

`RPCS3_IOS_BOOTSTRAP_ONLY=OFF` and `RPCS3_IOS_BUILD_QT_FRONTEND=OFF` build `rpcs3_ios_core`.

This stage pulls `rpcs3_emu`, portable dependencies, generated iOS filesystem adaptations, and Apple JIT write-protection transitions without instantiating the desktop-derived Qt frontend, HID stacks, PS Move UI, or an application bundle.

The target is a static archive milestone, not a runnable emulator.

### 3. Full frontend

`RPCS3_IOS_BUILD_QT_FRONTEND=ON` adds the Qt iOS frontend, application bundle, Files integration, native runtime hooks, GameController pad backend, and touch overlay.

The frontend is deliberately the last stage because desktop dialogs and peripheral integrations are a separate compatibility surface from the emulator core.

## Platform services

The reusable library under `rpcs3/ios/platform/` provides:

| Area | Source | Status |
| --- | --- | --- |
| Sandbox paths | `IOSPlatform.mm` | Application Support, Caches, Documents, Imports, and temporary paths are created and exposed. |
| Files app | `IOSPlatform.mm`, `IOSRuntimeIntegration.cpp` | Document picker and Qt file-open events copy security-scoped files or directories into `Documents/Imports`. |
| Audio lifecycle | `IOSPlatform.mm` | AVAudioSession category, 48 kHz preference, buffer preference, interruption recovery, and deactivation are implemented. |
| Application lifecycle | `IOSPlatform.mm`, `IOSRuntimeIntegration.cpp` | Inactive/background and audio interruptions pause emulation only when RPCS3 initiated the pause; activation resumes it. |
| JIT capability | `IOSJIT.mm`, `IOSJITProvider.mm` | Entitlement/debugger reporting, MAP_JIT allocation, dual RW/RX mappings, cache publication, provider requests, and attachment polling are implemented. |
| Core JIT transitions | `PatchCoreSources.cmake` | RPCS3 WX/RX memory transitions call the Apple thread-local JIT write barrier and publish the instruction cache. |
| Controllers | `IOSPlatform.mm`, `IOSControllerFeatures.mm`, `IOSControllerLight.mm` | Stable player slots, buttons, sticks, triggers, motion, battery, persistent haptics, and controller light output are exposed. |
| Touch input | `IOSTouchController.mm`, `IOSVirtualController.cpp` | Native multitouch DualShock-style overlay feeds the same pad backend; hardware controllers take priority and hide it. |
| Pad backend | `Input/ios_gamecontroller_pad_handler.*` | PS3 layout mapping, analog values, battery, orientation, motion, rumble, and RGB light output use normal RPCS3 pad callbacks. |
| Mobile performance | `IOSPerformance.mm` | Thermal state, Low Power Mode, physical/available memory, dispatch memory pressure, memory warnings, and idle-timer control are exposed. |
| External displays | `IOSExternalDisplay.mm` | External screen connection, resolution, scale, mode changes, and maximum refresh rate are monitored. Rendering migration remains future work. |
| MoltenVK policy | `IOSMoltenVK.mm` | Public configuration enables Tier-2 argument buffers when supported, lost-device recovery, command pooling, command-buffer presentation, and bounded queue depth. |
| Diagnostics | `IOSDiagnostics.mm` | Device, OS, app, memory, JIT, controller, MoltenVK, path, and display information can be written and shared. |
| Vulkan view bridge | `metal_layer.mm` | Accepts `UIView` on iOS and `NSView` on macOS. |

## Third-party dependency policy

`3rdparty/ios.cmake` prevents cross-builds from accidentally resolving macOS host libraries.

Portable bundled dependencies remain source-built where practical. MoltenVK and FFmpeg must be supplied as matching iOS or iOS Simulator builds. Qt is only required for the full frontend stage and must come from an iOS kit with matching macOS host tools.

LLVM is optional and interpreter-first remains the default. `buildfiles/ios/build_llvm.sh` performs a two-stage build: a native macOS `llvm-tblgen`, followed by static AArch64 target libraries and an installed target `LLVMConfig.cmake`. The target package is passed through `RPCS3_IOS_LLVM_ROOT`.

Desktop-only integrations are represented by feature-disabled interface targets during bring-up:

- libevdev;
- HIDAPI and libusb device backends;
- OpenAL and FAudio;
- SDL input;
- OpenCV camera tracking when unavailable;
- RtMidi;
- Discord RPC.

The optional Qt stage removes unconditional DualShock/HID/PS Move gameplay factories and substitutes explicit null fallbacks. The native GameController handler is inserted into gameplay and GUI-navigation factories through generated iOS source adaptations.

This does not claim every nested project already cross-compiles. curl/wolfSSL configuration, Qt desktop assumptions, LLVM component selection, and other nested projects may still require targeted fixes once Xcode reaches them.

## Input model

The iOS handler exposes logical devices named `iOS Controller 1`, `iOS Controller 2`, and so on.

GameController player indices are normalized and preserved. Hardware controllers occupy the first logical slots in player-index order. Without hardware, the native touch overlay becomes Player 1. Connecting hardware hides the overlay and gives hardware Player 1 priority.

Face buttons map by physical position:

| Apple gamepad position | PS3 control |
| --- | --- |
| Bottom / A | Cross |
| Right / B | Circle |
| Left / X | Square |
| Top / Y | Triangle |

The touch overlay implements both sticks, D-pad, four face buttons, L1/R1, analog L2/R2, L3/R3, Select, Start, and PS.

Controller motion is preferred when available. Otherwise, device CoreMotion is remapped for the current orientation. RPCS3 sensor values and raw orientation are populated through `get_extended_info`.

RPCS3 large/small vibration motors drive persistent low/high CoreHaptics players. When controller haptics are unavailable, the device haptic engine is used as a fallback. Supported controller lights receive the configured RPCS3 RGB values.

## Filesystem model

Persistent emulator state belongs in the application sandbox:

- RPCS3 configuration and installed system data: Application Support;
- regenerable caches and diagnostics: Caches;
- user-visible imports: Documents/Imports;
- transient work: temporary directory.

The existing Apple configuration path logic resolves through the sandbox `HOME`. An iOS-generated adaptation changes application-bundle discovery because iOS executables live directly inside the `.app`, unlike macOS executables under `Contents/MacOS`.

Generated adaptations fail CMake configuration when upstream anchors move. This prevents silent stale patches while avoiding broad forks of shared desktop source files.

## Executable memory

RPCS3 already requests `MAP_JIT` on Apple. The iOS platform layer additionally:

- reports `MAP_JIT`, `pthread_jit_write_protect_np`, debugger state, and relevant entitlements;
- allocates separate writable and executable aliases through `mach_vm_remap` when possible;
- falls back to a shared MAP_JIT mapping with thread-local write protection;
- publishes generated code with an instruction-cache invalidation;
- provides an explicit ARM64 function-execution probe;
- exposes public external JIT provider requests and asynchronous attachment polling;
- integrates WX/RX transitions into RPCS3's native memory layer.

`RPCS3_IOS_ENABLE_LLVM` defaults to `OFF`. Core/full targets should remain interpreter-first until a supported signing environment demonstrates allocation, publication, and generated-code execution.

Included entitlement files are examples, not grants:

- `JIT.entitlements`: dynamic code signing only;
- `Research.entitlements`: dynamic code signing plus extended virtual addressing and increased memory limit.

Provisioning may reject or strip any entitlement. `report_signing.sh` and runtime diagnostics report effective capability rather than trusting source plists.

## Graphics

The supported renderer is Vulkan through MoltenVK. Desktop OpenGL is disabled.

Bootstrap and full renderer paths use `VK_EXT_metal_surface`. The older `VK_MVK_ios_surface` path is intentionally not used.

The default mobile MoltenVK profile uses only public configuration variables. Argument buffers are enabled only for Metal argument-buffer Tier 2. Lost-device recovery and command pooling are enabled, synchronous queue submission is disabled, presentation uses a command buffer, and active queue command buffers are bounded.

Remaining graphics work requires an Apple build and includes shader/compiler compatibility, feature gaps, swapchain lifecycle during rotation/backgrounding, external-screen render migration, memory-pressure behavior, and real RSX workloads.

## Mobile lifecycle behavior

The full target initializes native services only after Qt creates its iOS application bridge. Cleanup is connected to `QCoreApplication::aboutToQuit`, before the Qt application object is destroyed.

RPCS3 pauses for independently tracked reasons:

- application inactive/background transition;
- AVAudioSession interruption.

It resumes only after every active reason clears and only if the iOS integration performed the pause.

Thermal changes, Low Power Mode, dispatch memory pressure, memory warnings, controller changes, and external-screen changes are surfaced through callbacks. Haptic engines and device motion stop during shutdown.

## Build and deployment tools

- `buildfiles/ios/configure.sh`: bootstrap, core, or full Xcode configuration for device/simulator.
- `buildfiles/ios/build_ffmpeg.sh`: static arm64 FFmpeg cross-build.
- `buildfiles/ios/build_llvm.sh`: native tablegen plus static target LLVM cross-build.
- `buildfiles/ios/validate_environment.sh`: stage-specific architecture and Mach-O platform validation for MoltenVK, FFmpeg, LLVM, and Qt.
- `buildfiles/ios/validate_sources.py`: host-independent source/plist/patch-contract validation.
- `buildfiles/ios/report_signing.sh`: effective executable and provisioning-profile entitlement report.
- `buildfiles/ios/archive.sh`: signed or unsigned xcarchive and IPA-shaped package.
- `buildfiles/ios/deploy.sh`: simulator or CoreDevice installation and launch.

A vphone guest can use `deploy.sh device ...` when it appears in CoreDevice. The current vphone MCP surface provides VM lifecycle, screenshot, tap, and swipe operations, but not app installation.

## Evidence gates still open

Source work can reduce, but not honestly eliminate, these blockers without an Apple build/runtime environment:

1. configure and compile every nested dependency with an iOS SDK;
2. compile and link `rpcs3_ios_core` for device and simulator;
3. resolve Qt Widgets behavior and unsupported desktop dialogs on iPhone-sized screens;
4. prove PPU/SPU interpreter operation;
5. prove or reject LLVM recompilers under each selected signing/JIT provider model;
6. validate MoltenVK device features against RPCS3 requirements;
7. migrate a real renderer view to external displays safely;
8. integrate microphone/camera permissions and backends where useful;
9. connect critical memory pressure to targeted emulator cache eviction;
10. install legal firmware and boot a legal workload;
11. exercise lifecycle, rotation, audio routes, hardware controllers, touch input, Files imports, haptics, motion, external screens, and thermal throttling on device;
12. establish repeatable physical-device and vphone smoke workflows.

Until those steps succeed, this repository is an iOS port in progress, not a functioning PS3 emulator release.
