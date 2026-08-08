# Independent RPCS3Core consumer verification

`RPCS3 iOS Core.app` is built in the same CMake graph as the framework. An
independent consumer check provides stronger packaging evidence by importing
only the installed framework headers and module map from outside that graph.

After building a device or simulator framework, run:

```bash
buildfiles/ios/verify_framework_consumers.sh \
  out/ios/RPCS3Core-simulator.framework simulator

buildfiles/ios/verify_framework_consumers.sh \
  out/ios/RPCS3Core-device.framework device
```

The verifier builds and links separate C, C++, and Objective-C++ executables
against `RPCS3Core.framework`, then type-checks a Swift consumer through the
framework module. The linked Mach-O consumers must reference:

```text
@rpath/RPCS3Core.framework/RPCS3Core
```

The contract sources use only:

- `<RPCS3Core/RPCS3Core.h>`;
- `<RPCS3Core/RPCS3CoreStatus.h>`;
- the public `RPCS3Core` Swift module.

A passing run proves that the selected framework slice exposes consumable public
headers, module metadata, symbols, and link information for that Apple SDK. It
does not prove that the consumer launches, that the framework initializes, or
that firmware, workloads, JIT, input, audio, or frame presentation work.

Retain the compiler commands, linked consumer binaries, `otool -L` output, exact
framework hash, and source commit with other evidence described in
`IOS_ARTIFACT_VERIFICATION.md`.
