# RPCS3Core release packaging

After device and simulator framework builds have been combined and verified,
create an auditable package with:

```bash
buildfiles/ios/package_core_release.sh \
  out/ios/RPCS3Core.xcframework \
  out/release/RPCS3Core-0.5
```

The packaging command first runs the full XCFramework verification. It then
creates:

- `RPCS3Core-0.5.xcframework.zip` using `ditto`, preserving framework metadata;
- standalone copies of both public headers and the module map;
- the 0.5 API, consumer, artifact-verification, and evidence documentation;
- the repository license when present;
- source repository and exact commit attribution;
- a toolchain/source/product build manifest;
- `SHA256SUMS` for every packaged file.

The command verifies its own checksum file before returning success. A release
pipeline should archive the corresponding evidence directory from
`capture_build_evidence.sh` next to this package and sign the archive/checksum
through the project's chosen release process.

A verified and packaged XCFramework is distribution evidence, not runtime
compatibility evidence. Do not label it as a working iOS emulator until the
runtime gates in `IOS_CORE_0_5.md` pass for the exact package.
