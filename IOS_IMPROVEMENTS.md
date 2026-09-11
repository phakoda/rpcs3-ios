# RPCS3 iOS graphics, input and build hardening

Prepared September 10, 2026 (US Eastern). Based on the supplied `rpcs3-ios.zip`,
Git revision `30865a5c40a89153ac51d79d5ccd6318465c9ca6`.

## Delivery status

This is a **source-code improvement package, not a compiled or signed IPA**.
The changes address concrete presentation, resource-lifetime, input and build
problems found in the supplied fork. The portable algorithms have executable
regression coverage. The Objective-C++ and Vulkan integration changes have been
reviewed, but have **not** been compiled against an Apple SDK or run on a GPU in
this environment. There is no verified game-compatibility claim, artifact-free
claim, FPS increase, or battery-life measurement.

The supplied source describes itself as a first-stage iOS port. Its original
`ios-device` and `ios-simulator` presets disable Vulkan and LLVM. The two new
Vulkan presets enable the graphics backend, but intentionally retain
`WITH_LLVM=OFF`. Enabling rendering is not equivalent to a working, optimized
PPU/SPU recompiler. Do not interpret these changes as a complete mature PS3
emulator for iOS.

The original archive was not modified. The updated complete archive preserves
its Git history and submodule references; external dependency submodules remain
unpopulated, as in the input. No game data, firmware, Apple SDK, MoltenVK binaries,
signing material, or third-party source copied from the researched emulators is
included.

## Implemented changes

### Presentation and graphical correctness

**Acquisition and semaphore ownership.** Startup and resize previously recorded
clears and layout transitions for every swapchain image before those images had
been acquired. Those loops are removed. The acquired image is now initialized
within the presentation submission that waits for acquisition. Its first layout
transition uses a source-stage mask that chains with that acquire wait, rather
than relying on an earlier `TOP_OF_PIPE` transition. Present-wait semaphores are
allocated per swapchain image and selected using the acquired image index,
instead of being reused by CPU frame index. Acquire semaphores remain associated
with drained CPU frame contexts. Creation results are checked. This follows the
ownership rules discussed in Khronos references [1] and [2].

**Clear and border correctness.** When clearing before a blit, the tracked image
layout is updated before the following write-after-write barrier. Previously the
barrier could name the presentation layout after the image had already moved to
transfer-destination layout. The background is opaque black. Coverage checks now
include both far edges of the image, so an uncovered right/bottom pixel is not
missed simply because the left/top offsets are zero.

**Swapchain creation and recovery.** `vkCreateSwapchainKHR` is checked before its
output is used. Failed creation does not lead to image enumeration using a failed
output handle. The retired old handle is cleared and destroyed instead of being
passed again on a retry. Khronos specifies that supplying `oldSwapchain` retires
it even when replacement creation fails [3]. Device loss remains an explicit
fatal error rather than being disguised as a recoverable resize.

The Vulkan count/data enumeration helper retries bounded `VK_INCOMPLETE`
responses, sizes vectors to the actual returned count, and only publishes a
complete result. It is used for surface formats, present modes and swapchain
images. Format and color space are selected as an advertised pair. Surface extent,
image usage and composite alpha are validated against capabilities. Fixed
surface extents are authoritative; variable extents are clamped; zero-sized
surfaces defer creation. Requested window dimensions are tracked separately from
the negotiated extent so that clamping does not force endless recreation.

CPU frame storage is retained after a deferred replacement, and at least one CPU
context exists when an initially hidden window has no swapchain images. An
out-of-date acquire is handled at the next frame boundary rather than recreating
resources halfway through a flip.

**Framebuffer cache.** The old framebuffer key used a union with 16-bit width,
16-bit height and a one-bit flag, but read the whole 64-bit value, including
uninitialized upper bits. The replacement packs every bit deterministically.
Single-image cache lookup now also checks attachment count and format. On resize,
cached framebuffers/image views referring to old swapchain images are removed
after draining GPU work and before destroying the swapchain. Unrelated render-
target cache entries are retained. The upscaler is also released after the drain.

**Metal view sizing.** An iOS fallback surface now uses a child UIView whose backing
layer is CAMetalLayer, rather than a raw sublayer sized once. Layout, window and
scale changes update drawable pixel dimensions without implicit animation or
same-size reallocation. UIKit writes occur on the main queue. A host view already
backed by CAMetalLayer is left under its existing owner's sizing policy. ARC is
explicitly enabled for this iOS source file. No per-frame synchronous main-queue
round trip was added.

Primary files: `VKPresent.cpp`, `VKGSRender.cpp/.h`, `VKGSRenderTypes.hpp`,
`VKFramebuffer.cpp/.h`, `vkutils/swapchain.cpp`, `vkutils/swapchain_core.h`,
`vkutils/instance.cpp`, `vkutils/metal_layer.mm`, and the new
`Common/presentation_policy.h` and `Common/framebuffer_key.h`.

### Input, controller lifecycle and haptics

**Controller-manager ownership.** Configuration-only `ios_pad_handler` instances
no longer stop a manager they never started. The manager counts active clients
and shuts down only when the final client releases it. UIKit/lifecycle/haptic
operations are kept on the main queue, while state shared with the polling worker
is protected. Controller reads use an autorelease pool on the worker.

**Stable player ports.** Surviving physical controllers retain their existing
logical slots when the OS reorders discovery or another controller disconnects.
New controllers fill holes. This stability is for the active manager session,
not a persisted cross-launch identity database.

**Touch controls.** Stick knobs are correctly centered on initial layout and
repositioned from normalized input after resizing. Movement is radially clamped
to the visible travel range. Each stick tracks its owning touch and resets on
cancellation or detachment. Button drag-exit releases input and drag-enter presses
it. Transparent overlay space passes touches to the underlying UI.

**Suspension and window changes.** Backgrounding neutralizes virtual input, gates
physical reads and stops haptics. Resume refreshes controllers. Key-window changes
retry virtual-pad attachment when no suitable window existed at initial startup.
Shared availability is read without consulting UIKit visibility from the worker.

**Numeric validation.** Axis, trigger, battery and motion conversion share finite-
value and range checks. NaN/infinity and extreme finite values cannot reach the
new trigger/sensor integer conversions unchecked. Motion falls back to neutral
512; unknown battery state is represented as full rather than a negative value.

**Rumble.** A zero command actually stops the previous haptic player. Disconnect,
shutdown and suspension stop engines/players. Queued commands retain the target
controller identity and are discarded after replacement. A bounded 400 ms event
covers the existing 300 ms heartbeat instead of the original 80 ms pulse followed
by a long gap. Changing rumble is coalesced at 20 ms intervals; stop commands are
immediate and zero-output idle updates are not repeatedly queued. Virtual touch
feedback reuses its generator and is throttled. This is not separate low/high-
frequency motor emulation or hardware-tested haptic calibration.

Primary files: `Input/ios_controller_bridge.mm`, `Input/ios_pad_handler.cpp`,
and the new `Input/ios_input_policy.h`.

### Performance changes and their limits

The code removes unnecessary startup/resize image clears and their dedicated
resize-fence submission, avoids same-size Metal storage updates, stops
zero-timeout acquire spinning on double-buffered surfaces, and reduces avoidable
controller/haptic work. Swapchain image-count policy requests one spare image,
with a preference for at least three where permitted, instead of the old two-
spare policy. Deterministic framebuffer keys restore reliable cache lookup.

These are concrete reductions in work or correctness fixes. They are **not a
measured overall speedup**. Queue depth can trade latency against throughput;
shader compilation, PPU/SPU execution, thermal limits and game-specific RSX work
may dominate. Shader accuracy options, fast-math, frame skipping, resolution
reduction, CPU scheduling and JIT entitlement behavior were not blindly changed.

### Build validation and continuous integration

New presets `ios-device-vulkan` and `ios-simulator-vulkan` take explicit MoltenVK
include/library paths. `buildfiles/ios/check_moltenvk.py` reads actual Mach-O
platform metadata, not just the CPU architecture. It supports thin/fat libraries
and BSD/GNU archives, checks every selected ARM64 object, and rejects a macOS,
Catalyst, opposite-iOS-target, arm64e, too-new-minimum-OS, malformed or ambiguous
library. A library file is required; an XCFramework directory is not a library.
Python 3.8 or newer is required for this configuration check.

The parser is deliberately strict about platform metadata. Bitcode-only or
metadata-less objects are not accepted. Passing it does not prove all required
MoltenVK symbols, features, header/library version compatibility, transitive
frameworks or signing requirements are satisfied.

The standalone tests do not need RPCS3's submodules. The added GitHub workflow runs
host regression tests and includes a macOS job to syntax-check both Objective-C++
bridges against iPhoneOS and Simulator SDKs. The workflow has been authored and
its YAML parsed locally; it has **not** been executed on GitHub or on macOS here.

## Tests actually executed

Environment: x86-64 Linux, Clang 17.0.0, GCC 14.2.0, CMake 3.31.6, Ninja 1.12.1,
Python 3.13.5 and LLVM ar 17.0.0. Strict C++ warnings are enabled for the portable
test target (`-Wall -Wextra -Wpedantic -Werror`).

| Configuration | Executed results |
| --- | --- |
| Clang Debug | 32 C++ groups; 620,392 assertions; 39 Python tests; all passed |
| Clang Debug + ASan/UBSan/float-cast-overflow | Same suites passed; no sanitizer diagnostic in these tested paths |
| GCC Release | Same suites passed; checks remain enabled with optimization |
| CMake preset listing | Both Vulkan presets recognized |
| Shell validation | Apple bridge checker passes `bash -n` |
| CI configuration | YAML parsed; host matrix and Apple SDK job present |
| Patch/source integrity | See the separate packaging verification log and changed-file manifest |

The C++ tests execute **production-used** extent, format, count, enumeration,
alpha-selection, input-sanitization, stick-normalization, controller-slot and
framebuffer-key functions. They include randomized invariants and exhaustive
16-bit framebuffer dimension checks. The 39 Python tests comprise **28 executable
Mach-O parser tests and 11 static source-wiring guards**. The latter inspect code
structure and ordering; they are not GPU or UI tests.

One parser test asks Clang to produce real minimal ARM64 iPhoneOS, ARM64 Simulator
and ARM64 macOS object files, packs them with llvm-ar, and checks acceptance or
rejection for each target. This does not require an Apple SDK and must not be
mistaken for compiling the emulator or testing GameController/Metal.

The complete iOS configure attempt failed because the target Qt toolchain and
dependency roots are absent. The Apple bridge check exited with its explicit
macOS/Xcode requirement. Those failure logs are included, not represented as
successful builds. Apple frameworks, Metal/Vulkan execution, game rendering,
physical controllers and frame rates have not been tested.

### Reproduce the host tests

Run from the repository root:

```sh
cmake -S buildfiles/ios/tests -B build-ios-tests -G Ninja \
  -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_BUILD_TYPE=Debug \
  -DRPCS3_IOS_TEST_SANITIZERS=ON
cmake --build build-ios-tests --parallel 2
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  ctest --test-dir build-ios-tests --output-on-failure
```

For an independent optimized run, use a separate directory with
`-DCMAKE_CXX_COMPILER=g++ -DCMAKE_BUILD_TYPE=Release` and sanitizers off.

## Building the graphics-enabled iOS target

Use a Mac with Xcode, the intended Apple SDK, CMake, Ninja, Python and target-built
Qt, FFmpeg and MoltenVK. The original submodule commits remain recorded:

```sh
git submodule update --init --recursive
bash buildfiles/ios/check_apple_bridges.sh

export RPCS3_IOS_QT_ROOT=/absolute/path/to/Qt/ios
export RPCS3_IOS_QT_HOST_PATH=/absolute/path/to/Qt/macos
export RPCS3_IOS_FFMPEG_ROOT=/absolute/path/to/ffmpeg-iphoneos
export RPCS3_IOS_MOLTENVK_INCLUDE_DIR=/absolute/path/to/MoltenVK/include
export RPCS3_IOS_MOLTENVK_LIBRARY=/absolute/path/to/iphoneos/libMoltenVK.a

python3 buildfiles/ios/check_moltenvk.py \
  --library "$RPCS3_IOS_MOLTENVK_LIBRARY" \
  --platform device --deployment-target 17.4
cmake --preset ios-device-vulkan
cmake --build --preset ios-device-vulkan
```

Replace every example dependency path with a provisioned target build. The include
root must contain `vulkan/vulkan.h` and `MoltenVK/mvk_vulkan.h`. The inherited bundle
location is `build-ios-device-vulkan/bin/rpcs3.app`, **only after a successful full
build**. For ARM64 Simulator, supply its dependency slices and use
`ios-simulator-vulkan`; macOS ARM64 libraries are not interchangeable. Consult
`BUILDING.md` for the fork's existing signing/runtime requirements. This package
does not provision or authorize JIT, change signing capabilities, or certify the
existing runtime fallback mechanisms.

The new CI syntax check should be the first Apple-side gate, followed by the full
application build. Merely setting `WITH_LLVM=ON` does not provision a compatible
LLVM toolchain or establish safe executable-memory behavior. A CPU-recompiler
configuration needs separate target-library and runtime validation.

## Remaining validation and engineering risks

The shared Vulkan files also affect desktop builds, so macOS/Windows/Linux Vulkan
regression runs are needed before merging broadly. Game-specific texture cache,
depth/stencil, shader translation, blending, render-to-texture, SPU/PPU accuracy,
audio timing and JIT correctness were not demonstrated by these host tests.
There is no new compatibility database or benchmark corpus in this delivery.

The new per-image semaphores fix **steady-state reuse**. Swapchain teardown still
uses the fork's practical `vkDeviceWaitIdle` approach. Khronos documents that
unextended presentation has no explicit completion fence and that WaitIdle alone
is not a formal presentation-completion guarantee [1]. A verified
swapchain-maintenance/present-fence or deferred-retirement design remains work;
it was not silently assumed available in the caller's MoltenVK build. Full
`VK_ERROR_SURFACE_LOST_KHR` recovery and actual device-loss recovery are also not
implemented. Acquire waits are individually bounded and check stop requests, but
a persistently unavailable surface can keep retrying until it changes or emulation
stops.

Before treating this as a release, test a device and simulator build with the exact
MoltenVK version, then capture validation diagnostics and deterministic frames.
Exercise startup hidden/visible, repeated rotation, split-window resizing where
supported, app suspension/resume and repeated stop/relaunch. Verify letterboxing,
odd-sized borders, screenshots, overlays, render-to-texture effects, depth and
blending against a known-good capture from the same game/build/settings. Any
shared-core change also needs a desktop Vulkan smoke test.

For input, test two physical controllers through disconnect/reorder/reconnect,
hold-and-cancel touches, rotate during a stick drag, connect a pad while virtual
buttons are held, open/close configuration during play, and issue explicit rumble
stop before backgrounding. Confirm the overlay attaches after a delayed window
creation and does not intercept unrelated UI taps.

Measure matched original/modified runs on the same hardware and deterministic
scene: cold and warm shader-cache runs, frame-time median/p95/p99, CPU/GPU time,
resident memory, validation messages and thermal state over sustained play. Store
exact OS, device, build, game update and settings alongside results. No numeric
performance target is asserted without those runs.

## Research provenance and licensing

References were used to check API contracts and implementation approaches, not to
import another emulator wholesale. New implementation/tests are independently
written for this fork. Existing licenses are retained; no Melo-Controller or
Dolphin source files were copied or bundled.

1. Khronos, **Swapchain Semaphore Reuse** — per-image present-wait ownership,
   acquire synchronization, and the explicit teardown limitation:
   https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
2. Khronos, **Synchronization Examples** — ordering layout transitions after an
   acquire semaphore wait:
   https://docs.vulkan.org/guide/latest/synchronization_examples.html
3. Khronos, **VkSwapchainCreateInfoKHR** — advertised format/color-space pairs,
   extent/usage/alpha limits, and retirement of the old swapchain on failed create:
   https://docs.vulkan.org/refpages/latest/refpages/source/VkSwapchainCreateInfoKHR.html
4. **Melo-Controller** — the supplied repository and UIKit joystick implementation
   were inspected for touch cancellation, normalization/recentering and feedback
   lifetime. The repository identifies GPL-3.0 licensing; no source was copied.
   Pinned inspected revision: `efe0373ede6ca4dc7d6533d7fa47ad52b4230fe8`.
   https://github.com/stossy11/Melo-Controller/blob/efe0373ede6ca4dc7d6533d7fa47ad52b4230fe8/Sources/Melo-Controller/Joystick/Joystick.swift
5. **Dolphin** — `Source/Core/VideoBackends/Vulkan/VKSwapChain.cpp` was inspected
   for checked creation, extent clamping, supported usage and buffer-count policy.
   Retrieved file blob: `370e22d15cc6227a915eb48a40d967798d2a9347`; branch URLs can
   change. No source was copied.
   https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/VideoBackends/Vulkan/VKSwapChain.cpp
6. The supplied stossy11 repository-list page was opened as a discovery reference:
   https://github.com/stossy11?tab=repositories
7. The supplied **MeloNX** endpoint returned an access-denied/anti-bot page on
   repeated attempts. Its implementation could not be inspected; no claim is made
   that MeloNX code was compared or integrated:
   https://git.ryujinx.app/projects/MeloNX

The two accessible code references are different emulators/control projects, not
proof that their game-specific GPU or CPU implementations can be transplanted
into PS3 emulation. Platform contracts and the supplied fork's own architecture
were the basis for these changes.
