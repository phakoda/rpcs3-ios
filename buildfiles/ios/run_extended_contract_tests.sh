#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/rpcs3-ios-extended-contracts"
CXX="${CXX:-c++}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

COMMON_FLAGS=(
    -std=c++20
    -Wall
    -Wextra
    -Wpedantic
    -Werror
)

"${CXX}" "${COMMON_FLAGS[@]}" \
    -I"${ROOT}/rpcs3/ios" \
    "${ROOT}/buildfiles/ios/tests/test_public_abi.cpp" \
    -o "${BUILD_DIR}/test_public_abi"
"${BUILD_DIR}/test_public_abi"

"${CXX}" "${COMMON_FLAGS[@]}" \
    -I"${ROOT}/rpcs3/ios" \
    "${ROOT}/rpcs3/ios/IOSCoreInstallerSupport.cpp" \
    "${ROOT}/buildfiles/ios/tests/test_installer_support.cpp" \
    -o "${BUILD_DIR}/test_installer_support"
"${BUILD_DIR}/test_installer_support"

echo "RPCS3 iOS extended ABI and installer-policy contracts passed."
