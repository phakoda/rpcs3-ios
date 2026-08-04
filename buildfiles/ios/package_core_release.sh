#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 /path/to/RPCS3Core.xcframework output-directory" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
[[ -d "$1" ]] || { echo "error: XCFramework not found: $1" >&2; exit 1; }
XCFRAMEWORK="$(cd "$1" && pwd)"
OUTPUT_DIR="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${ROOT}/buildfiles/ios/verify_core_xcframework.sh" "${XCFRAMEWORK}"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/Documentation"

ARCHIVE="${OUTPUT_DIR}/RPCS3Core-0.5.xcframework.zip"
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent "${XCFRAMEWORK}" "${ARCHIVE}"

cp "${ROOT}/rpcs3/ios/RPCS3Core.h" "${OUTPUT_DIR}/RPCS3Core.h"
cp "${ROOT}/rpcs3/ios/RPCS3CoreStatus.h" "${OUTPUT_DIR}/RPCS3CoreStatus.h"
cp "${ROOT}/rpcs3/ios/RPCS3Core.modulemap" "${OUTPUT_DIR}/module.modulemap"
cp "${ROOT}/IOS_CORE_0_5.md" "${OUTPUT_DIR}/Documentation/"
cp "${ROOT}/IOS_FRAMEWORK_CONSUMER.md" "${OUTPUT_DIR}/Documentation/"
cp "${ROOT}/IOS_ARTIFACT_VERIFICATION.md" "${OUTPUT_DIR}/Documentation/"
cp "${ROOT}/IOS_BUILD_EVIDENCE.md" "${OUTPUT_DIR}/Documentation/"
cp "${ROOT}/LICENSE" "${OUTPUT_DIR}/LICENSE" 2>/dev/null || true

"${ROOT}/buildfiles/ios/write_build_manifest.sh" \
    "${OUTPUT_DIR}/build-manifest.txt" \
    "${XCFRAMEWORK}" \
    "${ARCHIVE}"

cat >"${OUTPUT_DIR}/SOURCE.txt" <<EOF
Repository: https://github.com/phakoda/rpcs3-ios
Commit: $(git -C "${ROOT}" rev-parse HEAD)
Framework ABI: RPCS3Core 0.5

This package is source/build evidence only until the separate runtime gates in
Documentation/IOS_CORE_0_5.md have passed for the exact binary and signing model.
EOF

(
    cd "${OUTPUT_DIR}"
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | \
        while IFS= read -r FILE_PATH; do
            shasum -a 256 "${FILE_PATH}"
        done >SHA256SUMS
)

shasum -a 256 -c "${OUTPUT_DIR}/SHA256SUMS"
echo "Packaged verified RPCS3Core 0.5 release: ${OUTPUT_DIR}"
