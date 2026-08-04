# iOS artifact verification

The source validators and Apple SDK syntax jobs do not prove that the complete
RPCS3 iOS target generated, linked, embedded, signed, or launched. After an
actual Apple build, use these scripts to record objective product evidence.

## RPCS3Core.framework

```bash
buildfiles/ios/verify_artifacts.sh framework \
  out/ios/RPCS3Core-device.framework device

buildfiles/ios/verify_artifacts.sh framework \
  out/ios/RPCS3Core-simulator.framework simulator
```

The framework verifier checks:

- bundle plist type and 0.5 version metadata;
- both public headers and the module map;
- arm64 architecture;
- Mach-O device or simulator platform metadata when requested;
- exact public export parity with `RPCS3Core.exports`;
- absence of Qt, AppKit, Homebrew, and `/usr/local` load dependencies;
- code-signing validity when the framework is signed.

A passing framework verification is final-link evidence for that framework
slice. It is not launch, API-execution, firmware, game, JIT, or frame-presentation
evidence.

## RPCS3Core.xcframework

```bash
buildfiles/ios/verify_artifacts.sh xcframework \
  out/ios/RPCS3Core.xcframework
```

The XCFramework verifier requires at least one iOS device slice and one iOS
simulator slice, then applies the complete framework verification to each.

## Management application

```bash
buildfiles/ios/verify_artifacts.sh app \
  out/ios/RPCS3\ iOS\ Core.app
```

The app verifier checks:

- an embedded `RPCS3Core.framework`;
- matching app/framework architectures;
- `@rpath/RPCS3Core.framework/RPCS3Core` loading;
- `@executable_path/Frameworks` in `LC_RPATH`;
- absence of desktop and host-machine dependencies;
- recursive strict code-signing validity;
- 0.5 app version metadata.

This establishes bundle and embedding evidence, not successful installation or
launch.

## Dependency archives

```bash
buildfiles/ios/verify_artifacts.sh dependencies device \
  /path/to/libMoltenVK.a \
  /path/to/libavcodec.a \
  /path/to/libavformat.a

buildfiles/ios/verify_artifacts.sh dependencies simulator \
  /path/to/simulator/libMoltenVK.a \
  /path/to/simulator/libavcodec.a
```

For each static archive, the verifier extracts its first object and checks arm64
Mach-O and the expected iOS device or simulator build-platform marker. Use it on
all externally supplied MoltenVK, FFmpeg, LLVM, and other cross-built archives
before CMake configuration.

Because one archive can theoretically contain inconsistent members, a release
pipeline should additionally inspect every member or build dependencies from a
reproducible recipe. The first-member check is an early host-library and wrong-SDK
guard, not a complete binary provenance audit.

## Evidence retention

For every candidate build, retain:

- CMake configure output;
- complete Xcode build logs;
- dependency archive verification output;
- framework, XCFramework, and app verification output;
- linker maps;
- exported-symbol listings;
- `vtool -show-build`, `otool -L`, and architecture output;
- signing identity, entitlements, and `codesign --verify` output;
- the exact source commit and dependency revisions.

Do not describe the port as working until the separate runtime gates in
`IOS_CORE_0_5.md` have also passed on an Apple runtime with legally supplied
firmware and content.
