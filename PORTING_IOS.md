# RPCS3 iOS port architecture and status

This document tracks engineering status and deliberately separates source integration from Apple build validation and runtime proof.

## Reference implementations

The native layer follows patterns from established open-source emulator ports:

- **PPSSPP**: AVAudioSession recovery, GameController notifications, coordinated security-scoped imports, sandbox copies, and iOS packaging.
- **Play!**: a narrow native lifecycle boundary around a portable emulator core.
- **DolphiniOS and Provenance**: explicit separation between ordinary signing and environments capable of executable memory.
- **MeloNX**: dual-mapped JIT memory, entitlement/debugger capability checks, public external-JIT provider links, stable GameController slots, controller motion with device fallback, persistent haptics, external-display awareness, and mobile MoltenVK policy.

The original MeloNX forge may require an interactive anti-bot challenge. Source review used the public `VertexSelection/MeloVertex` mirror and its `XC-ios-ht` branch.

No source was copied verbatim. RPCS3's implementations use RPCS3 configuration, emulator, renderer, pad, and build interfaces.

Research-only private API paths were deliberately excluded. The branch does not adopt SpringBoardServices, MobileGestalt, private sandbox-bypass entitlements, private Metal configuration, TXM hooks, or other private frameworks.

## Build stages

### 1. Bootstrap

`RPCS3_IOS_BOOTSTRAP_ONLY=ON` builds a native UIKit developer console without `rpcs3_emu`. It exercises source paths for:

- Objective-C++ and UIKit bring-up;
- public MoltenVK configuration;
- Vulkan portability enumeration and `VK_EXT_metal_surface` creation;
- sandbox paths and security-scoped imports;
- AVAudioSession activation;
- signing, debugger, MAP_JIT, dual-mapping, and executable-code diagnostics;
- public Apple Magnifier, StikJIT, and JitStreamer request paths;
- controller motion, battery, haptics, and lights;
- memory pressure, available memory, thermal state, and Low Power Mode;
- external-screen status;
- exportable diagnostics.

### 2. Core

`RPCS3_IOS_BOOTSTRAP_ONLY=OFF` and `RPCS3_IOS_BUILD_QT_FRONTEND=OFF` build a Qt-free core graph.

The `rpcs3_ios_core` aggregate requires:

1. a low-level force-loaded Mach-O link artifact;
2. `RPCS3Core.framework`, which whole-archives the adapted `rpcs3_emu` target behind a stable C module;
3. a UIKit consumer app that imports only `RPCS3Core.h` and embeds the framework.

The framework source graph includes:

- generated iOS filesystem and JIT memory adaptations;
- the real RPCS3 `Emulator` lifecycle object;
- headless boot, restart, pause, resume, stop, state, event, title, title-ID, and boot-path APIs;
- security-scoped import APIs;
- a generated Qt-free `pad_thread` with native GameController and null unsupported handlers;
- Cubeb audio with a null fallback;
- Null RSX output until a native renderer host is attached;
- sandbox, JIT, performance, controller, and diagnostics services;
- an explicit Clang module map, exported-symbol list, hidden internal visibility, and linker map.

The small `rpcs3_ios_core_archive` target is a dependency wrapper. It is not advertised as a standalone monolithic archive. `RPCS3Core.framework` and `RPCS3Core.xcframework` are the supported embedding products.

This is source-level completion of the core and final-link graph. It is not proof that Xcode successfully compiles or links those products.

### 3. Full frontend

`RPCS3_IOS_BUILD_QT_FRONTEND=ON` adds the Qt iOS frontend, application bundle, Files integration, native runtime hooks, GameController backend, and touch overlay.

The frontend remains the last stage because Qt Widgets, desktop dialogs, and peripheral UI are a separate compatibility surface from the emulator core.

## Core framework API

`RPCS3Core.h` is a C-compatible, module-importable public boundary. It exposes:

- initialization and ordered shutdown;
- main-queue event delivery;
- import into `Documents/Imports`;
- headless boot and restart results matching RPCS3's current `game_boot_result` values;
- pause, resume, stop, and state queries;
- title, title ID, and boot path;
- sandbox paths;
- effective JIT and performance status;
- diagnostics and last-error strings;
- public MoltenVK default configuration.

The two-call import buffer contract caches the completed copy so requesting the required output size does not import the same item twice.

The framework consumer application can select a file or folder, import it through the public API, request a headless boot, and drive lifecycle controls. Its current renderer callback creates `NullGSRender`; it is not a game-display frontend.

## Link architecture

A normal static archive may retain unresolved references indefinitely. The branch uses two independent source-level final-link checks:

- a low-level executable passes `-force_load` for `rpcs3_emu`;
- `RPCS3Core.framework` links `rpcs3_emu` with CMake `WHOLE_ARCHIVE` semantics.

The final framework closure contains the native platform library and `3rdparty::ios_system`, which centralizes public Apple frameworks and system libraries required by RPCS3, Cubeb, FFmpeg, curl/wolfSSL, MoltenVK, and the Objective-C++ bridge.

Static FFmpeg libraries are ordered after their users and `avcodec`/`avutil` are repeated to close optional archive cycles.

The framework's exported-symbol list permits only the public C API and version symbols. Internal RPCS3 C++ symbols use hidden visibility.

## Dependency policy

`3rdparty/ios.cmake` prevents target builds from accidentally resolving macOS host libraries.

Portable dependencies remain source-built where practical. MoltenVK, FFmpeg, and optional LLVM must match the selected device or simulator SDK. Qt is required only for the full stage and must be paired with matching macOS host tools.

Dependency examples, tests, executables, installers, shared libraries, and target-side host tools are disabled where their projects permit it.

### Physical USB

Public iOS does not expose generic desktop USB passthrough. Instead of an empty target, the branch contains a concrete libusb compatibility header and library implementing the ABI subset RPCS3 uses. It reports zero physical devices and returns explicit unsupported/no-device results.

RPCS3's emulated USB devices remain compiled. This distinction prevents missing headers and symbols without claiming physical USB support.

### MIDI

Rock Band MIDI adapters remain source-compatible through a concrete RtMidi compatibility library. It exposes the expected C API but no host ports until a native CoreMIDI bridge is implemented.

### Other desktop integrations

Feature-disabled interface targets remain only for code paths guarded out of the core, including libevdev, HIDAPI, OpenAL, FAudio, SDL, OpenCV, and Discord RPC.

## Core compatibility policy

The shared iOS compatibility policy constrains persisted settings to linked backends:

- Vulkan is the normal mobile renderer configuration;
- the core framework uses Null RSX output until a native renderer host exists;
- LLVM selections fall back when a target LLVM package is not enabled;
- x86 AsmJit SPU recompilation falls back on Apple arm64;
- camera, microphone, PS Move, host MIDI, and raw desktop mouse capture are disabled or replaced with null/basic handlers.

The policy is applied by both `RPCS3Core.framework` and the full frontend runtime.

## Platform services

| Area | Source | Source status |
| --- | --- | --- |
| Sandbox paths | `IOSPlatform.mm` | Application Support, Caches, Documents, Imports, and temporary paths are exposed. |
| Files | `IOSPlatform.mm`, `RPCS3Core.mm`, `IOSRuntimeIntegration.cpp` | Coordinated security-scoped imports are copied into `Documents/Imports`. |
| Audio | `IOSPlatform.mm`, `IOSCoreEmulator.mm` | AVAudioSession policy and Cubeb/null backend selection are present. |
| Lifecycle | `IOSCoreEmulator.mm`, `IOSRuntimeIntegration.cpp` | Core C lifecycle and full-app inactive/interruption pause reasons are implemented. |
| JIT | `IOSJIT.mm`, `IOSJITProvider.mm` | Entitlement/debugger reporting, dual mappings, cache publication, public provider requests, and polling are present. |
| Core JIT transitions | `PatchCoreSources.cmake` | RPCS3 WX/RX changes call Apple's thread-local write barrier and clear the instruction cache. |
| Controllers | `IOSControllerFeatures.mm`, `IOSControllerLight.mm` | Stable slots, motion, battery, persistent haptics, and light output are exposed. |
| Pad backend | `ios_gamecontroller_pad_handler.*`, generated `pad_thread` | Native PS3 mapping, sensors, rumble, lights, and core/full factories are present. |
| Touch input | `IOSTouchController.mm`, `IOSVirtualController.cpp` | The full renderer view can host a native touch overlay. |
| Performance | `IOSPerformance.mm` | Thermal, Low Power Mode, physical/available memory, and memory pressure are exposed. |
| Displays | `IOSExternalDisplay.mm` | Screen connection and mode information are monitored. Render migration remains open. |
| MoltenVK | `IOSMoltenVK.mm` | Only public mobile configuration is used. |
| Diagnostics | `IOSDiagnostics.mm` | Device, app, memory, JIT, controller, path, MoltenVK, and display information are reportable. |
| Metal layer | `metal_layer.mm` | `UIView` is accepted on iOS while macOS retains `NSView`. |

## Input model

The native handler exposes `iOS Controller 1`, `iOS Controller 2`, and so on.

Connected controllers are compacted into stable logical order after connection changes. Hardware devices occupy the first logical slots; the full frontend's touch controller becomes Player 1 only when no hardware controller is connected.

Face buttons map by physical position:

| Apple position | PS3 control |
| --- | --- |
| Bottom / A | Cross |
| Right / B | Circle |
| Left / X | Square |
| Top / Y | Triangle |

Controller motion is preferred. Device CoreMotion is the orientation-aware fallback. RPCS3 sensors and raw orientation are populated through normal pad callbacks.

Large and small motors drive persistent low- and high-sharpness CoreHaptics players. Device haptics are a fallback. Supported controller lights receive configured or overridden RPCS3 RGB values.

## Filesystem model

- Application Support: configuration and installed emulator/system data;
- Caches: regenerable data and diagnostics;
- Documents/Imports: stable user-visible imports;
- temporary directory: transient work.

The generated Apple bundle-path adaptation accounts for iOS executables living directly inside `.app`, unlike macOS executables under `Contents/MacOS`.

Generated adaptations fail CMake configuration when upstream anchors move.

## Executable memory

The iOS layer:

- reports MAP_JIT, debugger state, thread write-protection support, and relevant entitlements;
- creates MAP_JIT memory with protections sufficient for both generation and execution;
- creates separate RW and RX aliases with `mach_vm_remap` when possible;
- falls back to thread write protection for a shared mapping;
- invalidates the instruction cache before execution;
- includes an explicit ARM64 function probe;
- exposes public external JIT provider requests and attachment polling;
- integrates Apple's write barrier into RPCS3's native WX/RX transitions.

LLVM remains optional and disabled by default. A target LLVM package does not grant JIT capability.

## Graphics

Vulkan through MoltenVK is the supported mobile renderer path. Desktop OpenGL is disabled.

Bootstrap and full renderer paths use `VK_EXT_metal_surface`. The old `VK_MVK_ios_surface` path is not used.

The core framework currently initializes the real emulator with Null RSX output. Connecting RPCS3's renderer lifecycle to a host-owned UIKit/Metal view remains a separate evidence and implementation gate.

## Packaging and validation tools

- `configure.sh`: device/simulator bootstrap, core, or full Xcode configuration;
- `build_ffmpeg.sh`: static FFmpeg target build;
- `build_llvm.sh`: native tablegen plus static target LLVM build;
- `validate_environment.sh`: architecture and Mach-O platform checks;
- `validate_sources.py`: general host-independent source/plist/patch contracts;
- `validate_core.py`: public API/export parity, whole-archive graph, generated input, compatibility ABI, and package contracts;
- `archive.sh`: app archive/IPA-shaped package and core framework extraction;
- `create_core_xcframework.sh`: device/simulator `RPCS3Core.xcframework` creation;
- `report_signing.sh`: effective entitlement reporting;
- `deploy.sh`: simulator or CoreDevice install and launch.

The GitHub iOS source workflow runs Bash syntax, general contracts, and core contracts. These checks do not invoke Xcode.

## Evidence gates still open

Source work cannot honestly eliminate these without an Apple build/runtime environment:

1. generate device and simulator Xcode projects;
2. compile every selected dependency;
3. compile and final-link the low-level artifact, framework, and framework-consumer app;
4. load the framework and invoke every public API;
5. install legal firmware and prove a legal headless boot;
6. prove PPU/SPU interpreter behavior;
7. prove or reject LLVM recompilers under each supported signing/JIT provider model;
8. validate MoltenVK features against real RSX workloads;
9. connect a native renderer host and present frames;
10. validate rotation, backgrounding, external displays, audio routes, controllers, touch, haptics, motion, lights, memory pressure, and thermal behavior;
11. resolve remaining Qt frontend and desktop-dialog assumptions;
12. establish repeatable physical-device and vphone workflows.

Until those gates succeed, this repository is a source-complete iOS core/linking effort and an unfinished emulator port, not a functioning PS3 emulator release.
