#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/configure.sh <device|simulator> [bootstrap|core|full]

Required environment:
  MOLTENVK_ROOT       Root of an unpacked MoltenVK distribution.

Core/full environment:
  RPCS3_IOS_FFMPEG_ROOT
                      Static FFmpeg prefix from build_ffmpeg.sh.

Full frontend environment:
  Qt6_DIR             Qt iOS kit lib/cmake/Qt6 directory.
  QT_HOST_PATH        Matching macOS Qt host installation.

Optional overrides:
  Vulkan_INCLUDE_DIR Directory containing vulkan/vulkan.h.
  Vulkan_LIBRARY     Exact path to the MoltenVK library for the selected SDK.
  IOS_DEPLOYMENT_TARGET (default: 16.0)
  BUILD_DIR          CMake build directory.
  RPCS3_IOS_ENABLE_LLVM (default: OFF)
  RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS (default: OFF)
  RPCS3_IOS_ENTITLEMENTS_FILE
                      Custom entitlement plist for a supported research or
                      development signing environment.
  RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES
                      Semicolon-separated extra static FFmpeg dependencies.

Stages:
  bootstrap  Native UIKit/MoltenVK/platform-services application.
  core       rpcs3_emu and portable dependencies, without Qt desktop frontend.
  full       Core plus the Qt frontend and iOS application bundle.

The helper does not download SDKs, firmware, signing identities, VM state, or
copyrighted console software.
EOF
}

platform="${1:-}"
mode="${2:-bootstrap}"
if [[ "${platform}" != "device" && "${platform}" != "simulator" ]]; then
    usage >&2
    exit 64
fi
if [[ "${mode}" != "bootstrap" && "${mode}" != "core" && "${mode}" != "full" ]]; then
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
    default_build_dir="${repo_root}/build-ios-device-${mode}"
    candidate_slices=(
        "${moltenvk_root}/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
        "${moltenvk_root}/MoltenVK/MoltenVK.xcframework/ios-arm64/libMoltenVK.a"
        "${moltenvk_root}/lib/ios/libMoltenVK.a"
    )
else
    sdk="iphonesimulator"
    default_build_dir="${repo_root}/build-ios-simulator-${mode}"
    candidate_slices=(
        "${moltenvk_root}/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a"
        "${moltenvk_root}/MoltenVK/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a"
        "${moltenvk_root}/lib/ios-simulator/libMoltenVK.a"
    )
fi
build_dir="${BUILD_DIR:-${default_build_dir}}"

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

if [[ "${mode}" == "core" || "${mode}" == "full" ]]; then
    if [[ ! -f "${RPCS3_IOS_FFMPEG_ROOT:-}/include/libavcodec/avcodec.h" ]]; then
        echo "error: ${mode} mode requires RPCS3_IOS_FFMPEG_ROOT" >&2
        exit 66
    fi
fi

if [[ "${mode}" == "full" ]]; then
    if [[ ! -f "${Qt6_DIR:-}/Qt6Config.cmake" ]]; then
        echo "error: full mode requires Qt6_DIR from a Qt iOS kit" >&2
        exit 66
    fi
    if [[ ! -d "${QT_HOST_PATH:-}" ]]; then
        echo "error: full mode requires QT_HOST_PATH for matching macOS Qt tools" >&2
        exit 66
    fi
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
deployment_target="${IOS_DEPLOYMENT_TARGET:-16.0}"
bootstrap_only="ON"
qt_frontend="OFF"
target="rpcs3_ios_bootstrap"
if [[ "${mode}" == "core" ]]; then
    bootstrap_only="OFF"
    target="rpcs3_ios_core"
elif [[ "${mode}" == "full" ]]; then
    bootstrap_only="OFF"
    qt_frontend="ON"
    target="rpcs3"
fi

export Vulkan_INCLUDE_DIR="${vulkan_include_dir}"
export Vulkan_LIBRARY="${vulkan_library}"
bash "${repo_root}/buildfiles/ios/validate_environment.sh" "${platform}" "${mode}"

cmake_args=(
    -S "${repo_root}"
    -B "${build_dir}"
    -G Xcode
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT="${sdk_path}"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}"
    -DRPCS3_IOS_BOOTSTRAP_ONLY="${bootstrap_only}"
    -DRPCS3_IOS_BUILD_QT_FRONTEND="${qt_frontend}"
    -DRPCS3_IOS_ENABLE_LLVM="${RPCS3_IOS_ENABLE_LLVM:-OFF}"
    -DRPCS3_IOS_ENABLE_JIT_ENTITLEMENTS="${RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS:-OFF}"
    -DVulkan_INCLUDE_DIR="${vulkan_include_dir}"
    -DVulkan_LIBRARY="${vulkan_library}"
)

if [[ "${mode}" == "core" || "${mode}" == "full" ]]; then
    cmake_args+=(
        -DRPCS3_IOS_FFMPEG_ROOT="${RPCS3_IOS_FFMPEG_ROOT}"
    )
    if [[ -n "${RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES:-}" ]]; then
        cmake_args+=(
            -DRPCS3_IOS_FFMPEG_EXTRA_LIBRARIES="${RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES}"
        )
    fi
fi

if [[ "${mode}" == "full" ]]; then
    cmake_args+=(
        -DQt6_DIR="${Qt6_DIR}"
        -DQT_HOST_PATH="${QT_HOST_PATH}"
    )
fi

if [[ -n "${RPCS3_IOS_ENTITLEMENTS_FILE:-}" ]]; then
    cmake_args+=(
        -DRPCS3_IOS_ENTITLEMENTS_FILE="${RPCS3_IOS_ENTITLEMENTS_FILE}"
    )
fi

echo "Configuring RPCS3 iOS ${mode} target"
echo "  SDK: ${sdk_path}"
echo "  MoltenVK headers: ${vulkan_include_dir}"
echo "  MoltenVK library: ${vulkan_library}"
echo "  Build directory: ${build_dir}"
cmake "${cmake_args[@]}"

cat <<EOF

Configuration completed.
Build with:
  cmake --build "${build_dir}" --config Release --target ${target}
EOF

if [[ "${mode}" != "core" ]]; then
    cat <<EOF

For device deployment, open:
  ${build_dir}/rpcs3.xcodeproj
and select your signing team and connected iPhone/iPad.
EOF
fi
