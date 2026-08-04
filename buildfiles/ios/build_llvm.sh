#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/build_llvm.sh <device|simulator>

Required environment:
  LLVM_SOURCE      Path to llvm-project/llvm or a directory containing
                   llvm/CMakeLists.txt.

Optional environment:
  OUTPUT_DIR       Installation prefix. Defaults to out/llvm-<platform>.
  IOS_DEPLOYMENT_TARGET (default: 16.0)
  BUILD_TYPE       CMake build type (default: Release).
  JOBS             Parallel build count.
  GENERATOR        CMake generator (default: Ninja when available, otherwise
                   Unix Makefiles).
  LLVM_EXTRA_CMAKE_FLAGS
                   Additional whitespace-separated target CMake arguments.

The script first builds a native macOS llvm-tblgen, then cross-builds static
AArch64 LLVM libraries and installs LLVMConfig.cmake for RPCS3_IOS_LLVM_ROOT.
EOF
}

platform="${1:-}"
if [[ "${platform}" != "device" && "${platform}" != "simulator" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: LLVM for iOS must be cross-compiled on macOS" >&2
    exit 69
fi

llvm_source="${LLVM_SOURCE:-}"
if [[ -d "${llvm_source}/llvm" && -f "${llvm_source}/llvm/CMakeLists.txt" ]]; then
    llvm_source="${llvm_source}/llvm"
fi
if [[ -z "${llvm_source}" || ! -f "${llvm_source}/CMakeLists.txt" ]]; then
    echo "error: LLVM_SOURCE must point to llvm-project/llvm or llvm-project" >&2
    exit 66
fi

for command in xcrun cmake; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
deployment_target="${IOS_DEPLOYMENT_TARGET:-16.0}"
build_type="${BUILD_TYPE:-Release}"
jobs="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

if [[ -n "${GENERATOR:-}" ]]; then
    generator="${GENERATOR}"
elif command -v ninja >/dev/null 2>&1; then
    generator="Ninja"
else
    generator="Unix Makefiles"
fi

if [[ "${platform}" == "device" ]]; then
    sdk="iphoneos"
    target_triple="arm64-apple-ios${deployment_target}"
    output_dir="${OUTPUT_DIR:-${repo_root}/out/llvm-device}"
else
    sdk="iphonesimulator"
    target_triple="arm64-apple-ios${deployment_target}-simulator"
    output_dir="${OUTPUT_DIR:-${repo_root}/out/llvm-simulator}"
fi

sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
cc="$(xcrun --sdk "${sdk}" --find clang)"
cxx="$(xcrun --sdk "${sdk}" --find clang++)"
host_build="${repo_root}/build-ios-deps/llvm-host"
target_build="${repo_root}/build-ios-deps/llvm-${platform}"

mkdir -p "${host_build}" "${target_build}" "${output_dir}"

common_llvm_options=(
    -DLLVM_TARGETS_TO_BUILD=AArch64
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_ENABLE_BINDINGS=OFF
    -DLLVM_ENABLE_OCAMLDOC=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DLLVM_ENABLE_CURL=OFF
    -DLLVM_ENABLE_FFI=OFF
    -DLLVM_ENABLE_TERMINFO=OFF
    -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_LIBPFM=OFF
    -DLLVM_ENABLE_RTTI=ON
    -DLLVM_ENABLE_EH=ON
    -DLLVM_BUILD_LLVM_DYLIB=OFF
    -DLLVM_LINK_LLVM_DYLIB=OFF
)

cmake -S "${llvm_source}" -B "${host_build}" -G "${generator}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INCLUDE_TOOLS=ON \
    "${common_llvm_options[@]}"
cmake --build "${host_build}" --target llvm-tblgen --parallel "${jobs}"

llvm_tblgen="${host_build}/bin/llvm-tblgen"
if [[ ! -x "${llvm_tblgen}" ]]; then
    echo "error: native llvm-tblgen was not produced: ${llvm_tblgen}" >&2
    exit 1
fi

read -r -a extra_flags <<< "${LLVM_EXTRA_CMAKE_FLAGS:-}"

cmake -S "${llvm_source}" -B "${target_build}" -G "${generator}" \
    -DCMAKE_BUILD_TYPE="${build_type}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
    -DCMAKE_C_COMPILER="${cc}" \
    -DCMAKE_CXX_COMPILER="${cxx}" \
    -DCMAKE_C_FLAGS="-target ${target_triple} -isysroot ${sdk_path}" \
    -DCMAKE_CXX_FLAGS="-target ${target_triple} -isysroot ${sdk_path}" \
    -DCMAKE_EXE_LINKER_FLAGS="-target ${target_triple} -isysroot ${sdk_path}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_INSTALL_PREFIX="${output_dir}" \
    -DLLVM_TABLEGEN="${llvm_tblgen}" \
    -DLLVM_HOST_TRIPLE="${target_triple}" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="${target_triple}" \
    -DLLVM_TARGET_ARCH=AArch64 \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TOOLS=OFF \
    "${common_llvm_options[@]}" \
    "${extra_flags[@]}"

cmake --build "${target_build}" --target install --parallel "${jobs}"

llvm_config="${output_dir}/lib/cmake/llvm/LLVMConfig.cmake"
if [[ ! -f "${llvm_config}" ]]; then
    echo "error: LLVM installation did not produce ${llvm_config}" >&2
    exit 1
fi

cat <<EOF
LLVM iOS build installed to:
  ${output_dir}

Enable RPCS3 recompilers with:
  RPCS3_IOS_ENABLE_LLVM=ON
  RPCS3_IOS_LLVM_ROOT=${output_dir}
EOF
