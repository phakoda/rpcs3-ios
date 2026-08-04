#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 output-file artifact-or-dependency [...]" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
OUTPUT="$1"
shift
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$(dirname "${OUTPUT}")"

absolute_path() {
    local input="$1"
    if [[ -d "${input}" ]]; then
        (cd "${input}" && pwd)
    else
        (cd "$(dirname "${input}")" && printf '%s/%s\n' "$(pwd)" "$(basename "${input}")")
    fi
}

{
    echo "RPCS3 iOS build evidence manifest"
    echo "generated_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "repository=${ROOT}"
    echo "commit=$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unavailable)"
    if git -C "${ROOT}" diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
        echo "worktree=clean"
    else
        echo "worktree=dirty"
    fi
    echo "uname=$(uname -a)"
    echo

    echo "[toolchain]"
    if command -v xcodebuild >/dev/null 2>&1; then
        xcodebuild -version | sed 's/^/xcodebuild=/'
    else
        echo "xcodebuild=unavailable"
    fi
    if command -v xcrun >/dev/null 2>&1; then
        for sdk in iphoneos iphonesimulator; do
            echo "${sdk}.path=$(xcrun --sdk "${sdk}" --show-sdk-path 2>/dev/null || echo unavailable)"
            echo "${sdk}.version=$(xcrun --sdk "${sdk}" --show-sdk-version 2>/dev/null || echo unavailable)"
        done
        echo "clang=$(xcrun clang --version 2>/dev/null | head -n 1 || echo unavailable)"
        echo "swift=$(xcrun swiftc --version 2>/dev/null | head -n 1 || echo unavailable)"
    fi
    echo "cmake=$(cmake --version 2>/dev/null | head -n 1 || echo unavailable)"
    echo "ninja=$(ninja --version 2>/dev/null || echo unavailable)"
    echo

    echo "[submodules]"
    git -C "${ROOT}" submodule status --recursive 2>/dev/null || true
    echo

    echo "[inputs-and-products]"
    for INPUT in "$@"; do
        if [[ ! -e "${INPUT}" ]]; then
            echo "missing=${INPUT}"
            continue
        fi
        ABSOLUTE="$(absolute_path "${INPUT}")"
        if [[ -f "${INPUT}" ]]; then
            echo "file=${ABSOLUTE}"
            echo "sha256=$(shasum -a 256 "${INPUT}" | awk '{print $1}')"
            echo "bytes=$(stat -f '%z' "${INPUT}" 2>/dev/null || stat -c '%s' "${INPUT}")"
            file "${INPUT}" | sed 's/^/file_type=/'
        else
            echo "directory=${ABSOLUTE}"
            while IFS= read -r FILE_PATH; do
                RELATIVE="${FILE_PATH#${INPUT}/}"
                HASH="$(shasum -a 256 "${FILE_PATH}" | awk '{print $1}')"
                echo "member=${RELATIVE} sha256=${HASH}"
            done < <(find "${INPUT}" -type f -print | LC_ALL=C sort)
        fi
        echo "--"
    done
} >"${OUTPUT}"

echo "Wrote RPCS3 iOS build manifest: ${OUTPUT}"
