# RPCS3 on iOS and iPadOS

The iOS port is being brought up in stages. The first target in this branch is a native UIKit application that proves the iOS toolchain, MoltenVK linkage, Vulkan portability enumeration, and `CAMetalLayer` surface creation before the desktop RPCS3 frontend and emulator core are enabled.

This separation is intentional: a successful Xcode compile is not enough to claim that PS3 emulation works. The bootstrap app reports the detected Metal/Vulkan device on screen and fails with a specific message when an instance extension, surface, or physical device is unavailable.

## Current milestone

Implemented:

- explicit CMake detection for `CMAKE_SYSTEM_NAME=iOS`;
- device and simulator Xcode generation;
- Objective-C++/UIKit application lifecycle;
- MoltenVK static-library linkage;
- `VK_KHR_surface`, `VK_EXT_metal_surface`, and Vulkan portability enumeration;
- creation and destruction of a `VkSurfaceKHR` backed by `CAMetalLayer`;
- an iOS implementation of the renderer's existing `GetCAMetalLayerFromMetalView` bridge;
- optional development-only JIT entitlement wiring.

Not yet represented as complete:

- linking and booting the full RPCS3 emulator core;
- replacing or disabling every desktop-only dependency and Qt workflow;
- validating LLVM/PPU/SPU JIT memory allocation under the selected signing method;
- controller, keyboard, audio, microphone, camera, and sandboxed file-import integration;
- firmware installation and game boot on a physical device or research VM.

## Requirements

- Apple Silicon Mac;
- Xcode with the iOS SDK selected by `xcode-select`;
- CMake 3.28 or newer;
- an unpacked MoltenVK distribution containing Vulkan headers and a library for the selected iOS SDK;
- an Apple development signing identity for physical-device deployment.

The bootstrap does not download proprietary SDKs, firmware, signing material, guest VM state, or games.

## Configure for a physical device

Set `MOLTENVK_ROOT` to the root of the unpacked MoltenVK distribution, then run:

```bash
MOLTENVK_ROOT=/absolute/path/to/MoltenVK \
  bash buildfiles/ios/configure.sh device

cmake --build build-ios-device \
  --config Release \
  --target rpcs3_ios_bootstrap
```

Open `build-ios-device/rpcs3.xcodeproj`, select `rpcs3_ios_bootstrap`, choose a development team, and run on an iPhone or iPad.

## Configure for the iOS Simulator

```bash
MOLTENVK_ROOT=/absolute/path/to/MoltenVK \
  bash buildfiles/ios/configure.sh simulator

cmake --build build-ios-simulator \
  --config Release \
  --target rpcs3_ios_bootstrap
```

The helper recognizes common MoltenVK archive layouts. Override its detection when needed:

```bash
Vulkan_INCLUDE_DIR=/absolute/path/to/include \
Vulkan_LIBRARY=/absolute/path/to/libMoltenVK.a \
MOLTENVK_ROOT=/absolute/path/to/MoltenVK \
  bash buildfiles/ios/configure.sh device
```

## Expected result

A successful launch shows text similar to:

```text
MoltenVK bring-up passed.
GPU: Apple ...
Vulkan: 1.x.x
Surface: VK_EXT_metal_surface
```

This validates the graphics bootstrap only. It does not mean a game has booted.

## JIT signing

The `dynamic-codesigning` entitlement is opt-in because ordinary App Store signing will not grant the runtime code-generation capabilities required by RPCS3's LLVM paths.

Configure it only with a signing/deployment environment that supports it:

```bash
cmake -S . -B build-ios-device -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DRPCS3_IOS_BOOTSTRAP_ONLY=ON \
  -DRPCS3_IOS_ENABLE_JIT_ENTITLEMENTS=ON \
  -DVulkan_INCLUDE_DIR=/absolute/path/to/include \
  -DVulkan_LIBRARY=/absolute/path/to/libMoltenVK.a
```

The next core milestone must separately test executable-memory allocation and code execution; the presence of an entitlement in a plist is not proof that the signing platform granted it.

## vphone testing

The `phakoda/vphone-aio-mcp` project can host a research iPhone VM on a properly configured Apple Silicon Mac. Its repository intentionally excludes guest VM state and firmware inputs, and its host requires private virtualization entitlements and security changes. Prepare those assets locally according to that repository's documentation, then use the generated Xcode app as the artifact under test.

Do not commit VM disks, NVRAM, SEP storage, serial logs, firmware, personal data, or signing secrets to this repository.

## Full-port path

After this bootstrap passes on the target environment, set `RPCS3_IOS_BOOTSTRAP_ONLY=OFF` and address full-build failures in dependency order. Keep each stage testable:

1. build the non-UI emulator core for arm64 iOS;
2. establish sandbox-safe configuration, cache, firmware, and game paths;
3. validate interpreter execution before enabling LLVM JIT;
4. attach the RSX Vulkan renderer to the proven Metal surface bridge;
5. add iOS-native input/audio lifecycle handling;
6. boot firmware and a legal test workload;
7. add repeatable device and vphone smoke tests.
