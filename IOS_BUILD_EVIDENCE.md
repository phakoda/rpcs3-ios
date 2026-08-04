# Reproducible iOS build evidence

A build result is only useful when it can be tied to exact source, toolchain,
dependency, binary, and signing state. `capture_build_evidence.sh` runs the
available product verifiers and writes a self-contained evidence directory.

Example:

```bash
buildfiles/ios/capture_build_evidence.sh out/evidence/$(git rev-parse --short HEAD) \
  --device-framework out/ios/RPCS3Core-device.framework \
  --simulator-framework out/ios/RPCS3Core-simulator.framework \
  --xcframework out/ios/RPCS3Core.xcframework \
  --app out/ios/RPCS3\ iOS\ Core.app \
  --dependency-device /path/to/device/libMoltenVK.a \
  --dependency-device /path/to/device/libavcodec.a \
  --dependency-simulator /path/to/simulator/libMoltenVK.a
```

The evidence directory contains:

- verifier logs for every supplied framework, app, XCFramework, and dependency;
- independent C, C++, Objective-C++, and Swift consumer results;
- a manifest with UTC time, source commit, worktree state, submodule revisions,
  Xcode, SDK, Clang, Swift, CMake, and Ninja versions;
- SHA-256 hashes and file metadata for every supplied input and product;
- discovered linker maps;
- a final `SHA256SUMS` covering the evidence directory itself.

The script stops at the first failed verifier. Do not retain a partial directory
as passing evidence. Archive the successful directory together with the exact
GitHub Actions run, signing profile description, device model/OS version, and
runtime test record.

Evidence capture still does not turn an unexecuted framework into a working
emulator. Runtime gates remain those listed in `IOS_CORE_0_5.md`: legal firmware
and workload boot, interpreter behavior, optional JIT, MoltenVK frame
presentation, lifecycle, input, audio, MIDI, memory pressure, and thermal state.
