#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/validate_environment.sh <device|simulator>

Required environment:
  Vulkan_INCLUDE_DIR
  Vulkan_LIBRARY

For full builds also set:
  RPCS3_IOS_FFMPEG_ROOT
  Qt6_DIR
  QT_HOST_PATH

Set VALIDATE_FULL_BUILD=1 to require the full-build variables and libraries.
EOF
}

platform="${1:-}"
if [[ "${platform}" != "device" && "${platform}" != "simulator" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: validation requires macOS and Xcode command-line tools" >&2
    exit 69
fi

for command in xcrun cmake lipo file; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

if [[ "${platform}" == "device" ]]; then
    sdk="iphoneos"
    expected_platform="iOS"
else
    sdk="iphonesimulator"
    expected_platform="iOS Simulator"
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
echo "SDK: ${sdk_path}"

actions_failed=0

require_file() {
    local description="$1"
    local path="$2"
    if [[ -z "${path}" || ! -f "${path}" ]]; then
        echo "error: ${description} not found: ${path:-<unset>}" >&2
        actions_failed=1
        return
    fi
    echo "ok: ${description}: ${path}"
}

require_dir() {
    local description="$1"
    local path="$2"
    if [[ -z "${path}" || ! -d "${path}" ]]; then
        echo "error: ${description} not found: ${path:-<unset>}" >&2
        actions_failed=1
        return
    fi
    echo "ok: ${description}: ${path}"
}

validate_archive() {
    local description="$1"
    local path="$2"
    require_file "${description}" "${path}"
    [[ -f "${path}" ]] || return

    local architectures
    architectures="$(lipo -archs "${path}" 2>/dev/null || true)"
    if [[ " ${architectures} " != *" arm64 "* ]]; then
        echo "error: ${description} does not contain arm64: ${architectures:-unknown}" >&2
        actions_failed=1
    else
        echo "ok: ${description} architectures: ${architectures}"
    fi

    local description_output
    description_output="$(file "${path}")"
    echo "    ${description_output}"
}

require_file "Vulkan header" "${Vulkan_INCLUDE_DIR:-}/vulkan/vulkan.h"
validate_archive "MoltenVK library" "${Vulkan_LIBRARY:-}"

if [[ "${VALIDATE_FULL_BUILD:-0}" == "1" ]]; then
    ffmpeg_root="${RPCS3_IOS_FFMPEG_ROOT:-}"
    require_file "FFmpeg avcodec header" "${ffmpeg_root}/include/libavcodec/avcodec.h"
    for library in avformat avcodec avutil swscale swresample; do
        validate_archive "FFmpeg ${library}" "${ffmpeg_root}/lib/lib${library}.a"
    done

    require_file "Qt6Config.cmake" "${Qt6_DIR:-}/Qt6Config.cmake"
    require_dir "Qt host tools" "${QT_HOST_PATH:-}"
fi

if [[ "${actions_failed}" != "0" ]]; then
    echo "Environment validation failed for ${expected_platform}." >&2
    exit 1
fi

echo "Environment validation passed for ${expected_platform}."
