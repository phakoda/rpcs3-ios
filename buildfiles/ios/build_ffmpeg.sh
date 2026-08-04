#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/build_ffmpeg.sh <device|simulator>

Required environment:
  FFMPEG_SOURCE   Path to an FFmpeg source checkout.

Optional environment:
  OUTPUT_DIR      Installation prefix. Defaults to out/ffmpeg-<platform>.
  IOS_DEPLOYMENT_TARGET (default: 16.0)
  JOBS            Parallel build count.
  FFMPEG_EXTRA_CONFIGURE_FLAGS
                  Additional whitespace-separated FFmpeg configure flags.

The output layout is directly accepted by RPCS3_IOS_FFMPEG_ROOT.
EOF
}

platform="${1:-}"
if [[ "${platform}" != "device" && "${platform}" != "simulator" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: FFmpeg for iOS must be cross-compiled on macOS" >&2
    exit 69
fi

ffmpeg_source="${FFMPEG_SOURCE:-}"
if [[ -z "${ffmpeg_source}" || ! -x "${ffmpeg_source}/configure" ]]; then
    echo "error: FFMPEG_SOURCE must point to an FFmpeg source tree" >&2
    exit 66
fi

for command in xcrun make perl; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
deployment_target="${IOS_DEPLOYMENT_TARGET:-16.0}"
jobs="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

if [[ "${platform}" == "device" ]]; then
    sdk="iphoneos"
    target_triple="arm64-apple-ios${deployment_target}"
    output_dir="${OUTPUT_DIR:-${repo_root}/out/ffmpeg-device}"
else
    sdk="iphonesimulator"
    target_triple="arm64-apple-ios${deployment_target}-simulator"
    output_dir="${OUTPUT_DIR:-${repo_root}/out/ffmpeg-simulator}"
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
cc="$(xcrun --sdk "${sdk}" --find clang)"
cxx="$(xcrun --sdk "${sdk}" --find clang++)"
ar="$(xcrun --sdk "${sdk}" --find ar)"
ranlib="$(xcrun --sdk "${sdk}" --find ranlib)"
strip="$(xcrun --sdk "${sdk}" --find strip)"
nm="$(xcrun --sdk "${sdk}" --find nm)"

build_dir="${repo_root}/build-ios-deps/ffmpeg-${platform}"
rm -rf "${build_dir}"
mkdir -p "${build_dir}" "${output_dir}"

read -r -a extra_flags <<< "${FFMPEG_EXTRA_CONFIGURE_FLAGS:-}"

pushd "${build_dir}" >/dev/null
"${ffmpeg_source}/configure" \
    --prefix="${output_dir}" \
    --target-os=darwin \
    --arch=arm64 \
    --enable-cross-compile \
    --sysroot="${sdk_path}" \
    --cc="${cc} -target ${target_triple}" \
    --cxx="${cxx} -target ${target_triple}" \
    --ar="${ar}" \
    --ranlib="${ranlib}" \
    --strip="${strip}" \
    --nm="${nm}" \
    --extra-cflags="-target ${target_triple} -isysroot ${sdk_path} -fembed-bitcode-marker -fvisibility=hidden" \
    --extra-cxxflags="-target ${target_triple} -isysroot ${sdk_path} -fembed-bitcode-marker -fvisibility=hidden" \
    --extra-ldflags="-target ${target_triple} -isysroot ${sdk_path}" \
    --disable-shared \
    --enable-static \
    --enable-pic \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --disable-sdl2 \
    --disable-iconv \
    --disable-vulkan \
    --enable-audiotoolbox \
    --enable-videotoolbox \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-swresample \
    --enable-swscale \
    "${extra_flags[@]}"

make -j"${jobs}"
make install
popd >/dev/null

cat <<EOF
FFmpeg iOS build installed to:
  ${output_dir}

Configure the RPCS3 full target with:
  -DRPCS3_IOS_FFMPEG_ROOT=${output_dir}
EOF
