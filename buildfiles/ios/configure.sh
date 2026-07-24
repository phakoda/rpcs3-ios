#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/configure.sh <device|simulator>

Required environment:
  MOLTENVK_ROOT       Root of an unpacked MoltenVK distribution.

Optional overrides:
  Vulkan_INCLUDE_DIR Directory containing vulkan/vulkan.h.
  Vulkan_LIBRARY     Exact path to the MoltenVK library for the selected SDK.
  IOS_DEPLOYMENT_TARGET (default: 16.0)
  BUILD_DIR          CMake build directory.

The helper configures the native bring-up target. It does not download SDKs,
firmware, signing identities, or VM state.
EOF
}

platform="${1:-}"
if [[ "${platform}" != "device" && "${platform}" != "simulator" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: iOS targets must be configured on macOS with Xcode installed" >&2
    exit 69
fi

command -v xcrun >/dev/null 2>&1 || {
    echo "error: xcrun was not found; install Xcode and select it with xcode-select" >&2
    exit 69
}
command -v cmake >/dev/null 2>&1 || {
    echo "error: cmake 3.28 or newer is required" >&2
    exit 69
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
moltenvk_root="${MOLTENVK_ROOT:-}"
if [[ -z "${moltenvk_root}" || ! -d "${moltenvk_root}" ]]; then
    echo "error: set MOLTENVK_ROOT to an unpacked MoltenVK distribution" >&2
    exit 66
fi

if [[ "${platform}" == "device" ]]; then
    sdk="iphoneos"
    build_dir="${BUILD_DIR:-${repo_root}/build-ios-device}"
    candidate_slices=(
        "${moltenvk_root}/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
        "${moltenvk_root}/MoltenVK/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
        "${moltenvk_root}/lib/ios/libMoltenVK.a"
    )
else
    sdk="iphonesimulator"
    build_dir="${BUILD_DIR:-${repo_root}/build-ios-simulator}"
    candidate_slices=(
        "${moltenvk_root}/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a"
        "${moltenvk_root}/MoltenVK/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a"
        "${moltenvk_root}/lib/ios-simulator/libMoltenVK.a"
    )
fi

vulkan_include_dir="${Vulkan_INCLUDE_DIR:-}"
if [[ -z "${vulkan_include_dir}" ]]; then
    for candidate in \
        "${moltenvk_root}/include" \
        "${moltenvk_root}/MoltenVK/include" \
        "${moltenvk_root}/MoltenVK.xcframework/Headers"; do
        if [[ -f "${candidate}/vulkan/vulkan.h" ]]; then
            vulkan_include_dir="${candidate}"
            break
        fi
    done
fi

vulkan_library="${Vulkan_LIBRARY:-}"
if [[ -z "${vulkan_library}" ]]; then
    for candidate in "${candidate_slices[@]}"; do
        if [[ -f "${candidate}" ]]; then
            vulkan_library="${candidate}"
            break
        fi
    done
fi

if [[ ! -f "${vulkan_include_dir}/vulkan/vulkan.h" ]]; then
    echo "error: Vulkan headers were not found; set Vulkan_INCLUDE_DIR explicitly" >&2
    exit 66
fi
if [[ ! -f "${vulkan_library}" ]]; then
    echo "error: a MoltenVK library for ${sdk} was not found; set Vulkan_LIBRARY explicitly" >&2
    exit 66
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
deployment_target="${IOS_DEPLOYMENT_TARGET:-16.0}"

echo "Configuring RPCS3 iOS bring-up"
echo "  SDK: ${sdk_path}"
echo "  MoltenVK headers: ${vulkan_include_dir}"
echo "  MoltenVK library: ${vulkan_library}"
echo "  Build directory: ${build_dir}"

cmake -S "${repo_root}" -B "${build_dir}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
    -DRPCS3_IOS_BOOTSTRAP_ONLY=ON \
    -DVulkan_INCLUDE_DIR="${vulkan_include_dir}" \
    -DVulkan_LIBRARY="${vulkan_library}"

cat <<EOF

Configuration completed.
Build with:
  cmake --build "${build_dir}" --config Release --target rpcs3_ios_bootstrap

For device deployment, open:
  ${build_dir}/rpcs3.xcodeproj
and select your signing team and connected iPhone/iPad.
EOF
