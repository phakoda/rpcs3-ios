#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 /path/to/RPCS3Core.framework device|simulator" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
FRAMEWORK="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PLATFORM="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACTS="${ROOT}/buildfiles/ios/contracts"
BUILD_DIR="${TMPDIR:-/tmp}/rpcs3-ios-framework-consumers"

case "${PLATFORM}" in
    device)
        SDK=iphoneos
        TARGET=arm64-apple-ios16.0
        ;;
    simulator)
        SDK=iphonesimulator
        TARGET=arm64-apple-ios16.0-simulator
        ;;
    *) usage ;;
esac

[[ -d "${FRAMEWORK}" ]] || { echo "error: framework not found: ${FRAMEWORK}" >&2; exit 1; }
FRAMEWORK_PARENT="$(dirname "${FRAMEWORK}")"
SDKROOT="$(xcrun --sdk "${SDK}" --show-sdk-path)"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

COMMON=(
    -target "${TARGET}"
    -isysroot "${SDKROOT}"
    -F"${FRAMEWORK_PARENT}"
    -framework RPCS3Core
    -Wl,-rpath,@executable_path/Frameworks
)

xcrun --sdk "${SDK}" clang -std=c17 -Wall -Wextra -Werror \
    "${COMMON[@]}" "${CONTRACTS}/core_consumer.c" \
    -o "${BUILD_DIR}/core_consumer_c"

xcrun --sdk "${SDK}" clang++ -std=c++20 -Wall -Wextra -Werror \
    "${COMMON[@]}" "${CONTRACTS}/core_consumer.cpp" \
    -o "${BUILD_DIR}/core_consumer_cpp"

xcrun --sdk "${SDK}" clang++ -std=c++20 -fobjc-arc -fblocks -Wall -Wextra -Werror \
    "${COMMON[@]}" -framework UIKit -framework QuartzCore \
    "${CONTRACTS}/core_consumer.mm" \
    -o "${BUILD_DIR}/core_consumer_objcxx"

xcrun --sdk "${SDK}" swiftc \
    -target "${TARGET}" \
    -sdk "${SDKROOT}" \
    -F "${FRAMEWORK_PARENT}" \
    -typecheck \
    "${CONTRACTS}/CoreConsumer.swift"

for BINARY in \
    "${BUILD_DIR}/core_consumer_c" \
    "${BUILD_DIR}/core_consumer_cpp" \
    "${BUILD_DIR}/core_consumer_objcxx"; do
    otool -L "${BINARY}" | grep -Eq '@rpath/RPCS3Core\.framework/RPCS3Core' || {
        echo "error: consumer does not link RPCS3Core through @rpath: ${BINARY}" >&2
        otool -L "${BINARY}" >&2
        exit 1
    }
done

echo "Independent C, C++, Objective-C++, and Swift consumer contracts passed for ${PLATFORM}."
