#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/validate_environment.sh <device|simulator> [bootstrap|core|full]

Required environment:
  Vulkan_INCLUDE_DIR
  Vulkan_LIBRARY

Core/full environment:
  RPCS3_IOS_FFMPEG_ROOT

LLVM-enabled core/full environment:
  RPCS3_IOS_ENABLE_LLVM=ON
  RPCS3_IOS_LLVM_ROOT

Full frontend environment:
  Qt6_DIR
  QT_HOST_PATH
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
    echo "error: validation requires macOS and Xcode command-line tools" >&2
    exit 69
fi

for command in xcrun cmake lipo file; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

ar_tool="$(xcrun --find ar)"
vtool="$(xcrun --find vtool)"

if [[ "${platform}" == "device" ]]; then
    sdk="iphoneos"
    expected_platform="IOS"
    display_platform="iOS"
else
    sdk="iphonesimulator"
    expected_platform="IOSSIMULATOR"
    display_platform="iOS Simulator"
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
echo "SDK: ${sdk_path}"
echo "Mode: ${mode}"

actions_failed=0
temporary="$(mktemp -d "${TMPDIR:-/tmp}/rpcs3-ios-validation.XXXXXX")"
trap 'rm -rf "${temporary}"' EXIT

require_file() {
    local description="$1"
    local path="$2"
    if [[ -z "${path}" || ! -f "${path}" ]]; then
        echo "error: ${description} not found: ${path:-<unset>}" >&2
        actions_failed=1
        return 1
    fi
    echo "ok: ${description}: ${path}"
}

require_dir() {
    local description="$1"
    local path="$2"
    if [[ -z "${path}" || ! -d "${path}" ]]; then
        echo "error: ${description} not found: ${path:-<unset>}" >&2
        actions_failed=1
        return 1
    fi
    echo "ok: ${description}: ${path}"
}

macho_platform_report() {
    local path="$1"
    local description_output
    description_output="$(file "${path}")"

    local inspect_path="${path}"
    if [[ "${description_output}" == *"current ar archive"* ]]; then
        local member
        member="$(${ar_tool} -t "${path}" | awk 'NF { print; exit }')"
        if [[ -z "${member}" ]]; then
            return 0
        fi

        local archive_dir="${temporary}/archive-$RANDOM-$$"
        mkdir -p "${archive_dir}"
        (
            cd "${archive_dir}"
            "${ar_tool}" -x "${path}" "${member}"
        )
        inspect_path="${archive_dir}/${member}"
        if [[ ! -f "${inspect_path}" ]]; then
            inspect_path="$(find "${archive_dir}" -type f -print -quit)"
        fi
    fi

    if [[ -z "${inspect_path}" || ! -f "${inspect_path}" ]]; then
        return 0
    fi
    "${vtool}" -show-build "${inspect_path}" 2>/dev/null || true
}

validate_archive() {
    local description="$1"
    local path="$2"
    if ! require_file "${description}" "${path}"; then
        return
    fi

    local architectures
    architectures="$(lipo -archs "${path}" 2>/dev/null || true)"
    if [[ " ${architectures} " != *" arm64 "* ]]; then
        echo "error: ${description} does not contain arm64: ${architectures:-unknown}" >&2
        actions_failed=1
    else
        echo "ok: ${description} architectures: ${architectures}"
    fi

    echo "    $(file "${path}")"
    local platform_report
    platform_report="$(macho_platform_report "${path}")"
    if [[ -z "${platform_report}" ]]; then
        echo "warning: ${description} did not expose LC_BUILD_VERSION platform metadata" >&2
        return
    fi

    echo "${platform_report}" | sed 's/^/    /'
    if echo "${platform_report}" | grep -Eq "platform[[:space:]]+${expected_platform}([[:space:]]|$)"; then
        echo "ok: ${description} targets ${display_platform}"
    elif echo "${platform_report}" | grep -Eq 'platform[[:space:]]+(IOS|IOSSIMULATOR)([[:space:]]|$)'; then
        echo "error: ${description} targets the wrong Apple platform for ${display_platform}" >&2
        actions_failed=1
    else
        echo "warning: ${description} platform could not be classified from LC_BUILD_VERSION" >&2
    fi
}

require_file "Vulkan header" "${Vulkan_INCLUDE_DIR:-}/vulkan/vulkan.h" || true
validate_archive "MoltenVK library" "${Vulkan_LIBRARY:-}"

if [[ "${mode}" == "core" || "${mode}" == "full" ]]; then
    ffmpeg_root="${RPCS3_IOS_FFMPEG_ROOT:-}"
    require_file "FFmpeg avcodec header" "${ffmpeg_root}/include/libavcodec/avcodec.h" || true
    for library in avformat avcodec avutil swscale swresample; do
        validate_archive "FFmpeg ${library}" "${ffmpeg_root}/lib/lib${library}.a"
    done

    case "${RPCS3_IOS_ENABLE_LLVM:-OFF}" in
        ON|on|TRUE|true|1|YES|yes)
            llvm_root="${RPCS3_IOS_LLVM_ROOT:-}"
            require_file "LLVMConfig.cmake" "${llvm_root}/lib/cmake/llvm/LLVMConfig.cmake" || true
            llvm_archive="$(find "${llvm_root}/lib" -maxdepth 1 -type f -name 'libLLVMCore.a' -print -quit 2>/dev/null || true)"
            if [[ -n "${llvm_archive}" ]]; then
                validate_archive "LLVM Core library" "${llvm_archive}"
            else
                echo "error: LLVM Core static library not found under ${llvm_root:-<unset>}/lib" >&2
                actions_failed=1
            fi
            ;;
    esac
fi

if [[ "${mode}" == "full" ]]; then
    require_file "Qt6Config.cmake" "${Qt6_DIR:-}/Qt6Config.cmake" || true
    require_dir "Qt host tools" "${QT_HOST_PATH:-}" || true
fi

if [[ "${actions_failed}" != "0" ]]; then
    echo "Environment validation failed for ${display_platform} ${mode}." >&2
    exit 1
fi

echo "Environment validation passed for ${display_platform} ${mode}."
