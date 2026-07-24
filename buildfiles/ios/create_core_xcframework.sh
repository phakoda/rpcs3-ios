#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/create_core_xcframework.sh

Optional environment:
  DEVICE_BUILD_DIR     Configured device core build directory.
                       Default: build-ios-device-core
  SIMULATOR_BUILD_DIR  Configured simulator core build directory.
                       Default: build-ios-simulator-core
  CONFIGURATION        Xcode configuration. Default: Release
  OUTPUT_DIR           Output directory. Default: out/ios
  OUTPUT_NAME          XCFramework name. Default: RPCS3Core.xcframework
  SKIP_BUILD=1         Package existing framework products without building.

Both build trees must have been configured with:
  bash buildfiles/ios/configure.sh device core
  bash buildfiles/ios/configure.sh simulator core
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ $# -ne 0 ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: XCFramework creation requires macOS and Xcode" >&2
    exit 69
fi

for command in xcodebuild cmake lipo file; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device_build_dir="${DEVICE_BUILD_DIR:-${repo_root}/build-ios-device-core}"
simulator_build_dir="${SIMULATOR_BUILD_DIR:-${repo_root}/build-ios-simulator-core}"
configuration="${CONFIGURATION:-Release}"
output_dir="${OUTPUT_DIR:-${repo_root}/out/ios}"
output_name="${OUTPUT_NAME:-RPCS3Core.xcframework}"
output_path="${output_dir}/${output_name}"

for build_dir in "${device_build_dir}" "${simulator_build_dir}"; do
    if [[ ! -d "${build_dir}/rpcs3.xcodeproj" ]]; then
        echo "error: configured Xcode project not found: ${build_dir}/rpcs3.xcodeproj" >&2
        exit 66
    fi
done

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    cmake --build "${device_build_dir}" --config "${configuration}" --target rpcs3_ios_core_framework
    cmake --build "${simulator_build_dir}" --config "${configuration}" --target rpcs3_ios_core_framework
fi

find_framework() {
    local build_dir="$1"
    local expected_sdk="$2"
    local settings
    settings="$(xcodebuild \
        -project "${build_dir}/rpcs3.xcodeproj" \
        -target rpcs3_ios_core_framework \
        -configuration "${configuration}" \
        -sdk "${expected_sdk}" \
        -showBuildSettings)"

    local target_build_dir
    local full_product_name
    target_build_dir="$(awk -F ' = ' '$1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ { print $2; exit }' <<<"${settings}")"
    full_product_name="$(awk -F ' = ' '$1 ~ /^[[:space:]]*FULL_PRODUCT_NAME$/ { print $2; exit }' <<<"${settings}")"

    if [[ -z "${target_build_dir}" || -z "${full_product_name}" ]]; then
        echo "error: could not resolve framework build settings for ${expected_sdk}" >&2
        exit 1
    fi

    local framework="${target_build_dir}/${full_product_name}"
    if [[ ! -d "${framework}" ]]; then
        echo "error: framework product not found: ${framework}" >&2
        exit 1
    fi
    printf '%s\n' "${framework}"
}

device_framework="$(find_framework "${device_build_dir}" iphoneos)"
simulator_framework="$(find_framework "${simulator_build_dir}" iphonesimulator)"

validate_framework() {
    local framework="$1"
    local label="$2"
    local binary="${framework}/RPCS3Core"
    if [[ ! -f "${binary}" ]]; then
        echo "error: ${label} framework binary not found: ${binary}" >&2
        exit 1
    fi

    local architectures
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* ]]; then
        echo "error: ${label} framework does not contain arm64: ${architectures}" >&2
        exit 1
    fi

    if [[ ! -f "${framework}/Headers/RPCS3Core.h" ]]; then
        echo "error: ${label} framework is missing its public header" >&2
        exit 1
    fi

    echo "${label}: ${framework}"
    echo "  architectures: ${architectures}"
    echo "  binary: $(file "${binary}")"
}

validate_framework "${device_framework}" "Device"
validate_framework "${simulator_framework}" "Simulator"

rm -rf "${output_path}"
mkdir -p "${output_dir}"
xcodebuild -create-xcframework \
    -framework "${device_framework}" \
    -framework "${simulator_framework}" \
    -output "${output_path}"

cat <<EOF
RPCS3 core XCFramework created:
  ${output_path}

Public header:
  RPCS3Core/RPCS3Core.h
EOF
