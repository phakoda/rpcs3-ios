# RPCS3 iOS runtime hardening report

This branch contains the iOS runtime hardening work developed from base commit `19be56402314cf5a3fef7ad93027b00c7077ad29`.

## Runtime changes

- Native RemoteIO output for iOS with Float32/S16 PCM, stereo downmix negotiation, render-path underrun silencing, interruption/route/media-service recovery, and shutdown diagnostics.
- Capability-aware PPU/SPU decoder defaults and boot-time fallback so non-LLVM iOS builds do not select unavailable recompilers.
- Foreground/background pause ownership that preserves a user pause across repeated inactive/hidden/suspended transitions and rechecks activity after boot completes.
- Stable physical-controller slot enumeration, occupied-slot masks, and a virtual touch controller hosted only inside the native game view.
- NaN-safe PCM handling, exact in-range normalization, signed-16 conversion boundaries, in-place shrinking, and an ARM64 NEON path.
- ARC/precompiled-header isolation for Objective-C++ native bridges and exception support confined to the native audio translation unit.
- Portable PCM microbenchmarks and expanded source/runtime policy tests.

## Portable validation completed

The hardened source was exercised outside Apple hardware with both GCC Release and Clang sanitizer builds. Eight CTest targets passed in each configuration; the non-Python policy binaries accounted for 8,872,322 assertions per configuration and the Python source/prebuilt validation suite reported 47 tests passed. Production PCM helpers also compiled as AArch64 code and emitted vector instructions, and the portable finite S16 loop was checked for autovectorization.

These counts include assertions inside deterministic loops and buffer-guard checks. They are not a claim of millions of independently authored test cases.

## Apple/device acceptance still required

This development environment does not provide Xcode, Apple SDKs, or physical iOS hardware. Before calling the port device-validated, build the graphics-enabled `ios-device-vulkan` and/or `ios-simulator-vulkan` preset with matching Qt/FFmpeg/MoltenVK dependencies, run `buildfiles/ios/check_apple_bridges.sh`, and exercise speaker/wired/Bluetooth audio, interruptions, route changes, background/foreground transitions, physical controller reconnects, touch controls, sustained frame pacing, memory pressure, and thermal behavior on target devices.

## Reference code reviewed

PPSSPP's iOS RemoteIO/AVAudioSession patterns, Melo-Controller's touch joystick behavior, and upstream RPCS3 audio helpers were reviewed as references. Melo-Controller is GPL-3.0; no Melo-Controller source was copied into this GPL-2.0-only tree. The supplied MeloNX endpoint was access-denied during the original hardening pass and was not represented as reviewed source.
