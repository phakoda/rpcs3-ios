#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: capture_build_evidence.sh output-directory \
  --device-framework path \
  --simulator-framework path \
  --xcframework path \
  --app path \
  [--dependency-device archive]... \
  [--dependency-simulator archive]...
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
OUTPUT_DIR="$1"
shift
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEVICE_FRAMEWORK=""
SIMULATOR_FRAMEWORK=""
XCFRAMEWORK=""
APP=""
DEVICE_DEPENDENCIES=()
SIMULATOR_DEPENDENCIES=()
ALL_INPUTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-framework)
            [[ $# -ge 2 ]] || usage
            DEVICE_FRAMEWORK="$2"; ALL_INPUTS+=("$2"); shift 2 ;;
        --simulator-framework)
            [[ $# -ge 2 ]] || usage
            SIMULATOR_FRAMEWORK="$2"; ALL_INPUTS+=("$2"); shift 2 ;;
        --xcframework)
            [[ $# -ge 2 ]] || usage
            XCFRAMEWORK="$2"; ALL_INPUTS+=("$2"); shift 2 ;;
        --app)
            [[ $# -ge 2 ]] || usage
            APP="$2"; ALL_INPUTS+=("$2"); shift 2 ;;
        --dependency-device)
            [[ $# -ge 2 ]] || usage
            DEVICE_DEPENDENCIES+=("$2"); ALL_INPUTS+=("$2"); shift 2 ;;
        --dependency-simulator)
            [[ $# -ge 2 ]] || usage
            SIMULATOR_DEPENDENCIES+=("$2"); ALL_INPUTS+=("$2"); shift 2 ;;
        *) usage ;;
    esac
done

mkdir -p "${OUTPUT_DIR}"
LOG_DIR="${OUTPUT_DIR}/logs"
mkdir -p "${LOG_DIR}"

run_and_capture() {
    local name="$1"
    shift
    echo "+ $*" | tee "${LOG_DIR}/${name}.log"
    "$@" 2>&1 | tee -a "${LOG_DIR}/${name}.log"
}

if [[ -n "${DEVICE_FRAMEWORK}" ]]; then
    run_and_capture framework-device \
        "${ROOT}/buildfiles/ios/verify_core_framework.sh" "${DEVICE_FRAMEWORK}" device
    run_and_capture consumers-device \
        "${ROOT}/buildfiles/ios/verify_framework_consumers.sh" "${DEVICE_FRAMEWORK}" device
fi

if [[ -n "${SIMULATOR_FRAMEWORK}" ]]; then
    run_and_capture framework-simulator \
        "${ROOT}/buildfiles/ios/verify_core_framework.sh" "${SIMULATOR_FRAMEWORK}" simulator
    run_and_capture consumers-simulator \
        "${ROOT}/buildfiles/ios/verify_framework_consumers.sh" "${SIMULATOR_FRAMEWORK}" simulator
fi

if [[ -n "${XCFRAMEWORK}" ]]; then
    run_and_capture xcframework \
        "${ROOT}/buildfiles/ios/verify_core_xcframework.sh" "${XCFRAMEWORK}"
fi

if [[ -n "${APP}" ]]; then
    run_and_capture app \
        "${ROOT}/buildfiles/ios/verify_core_app.sh" "${APP}"
fi

if [[ ${#DEVICE_DEPENDENCIES[@]} -gt 0 ]]; then
    run_and_capture dependencies-device \
        "${ROOT}/buildfiles/ios/verify_dependency_archives.sh" device \
        "${DEVICE_DEPENDENCIES[@]}"
fi

if [[ ${#SIMULATOR_DEPENDENCIES[@]} -gt 0 ]]; then
    run_and_capture dependencies-simulator \
        "${ROOT}/buildfiles/ios/verify_dependency_archives.sh" simulator \
        "${SIMULATOR_DEPENDENCIES[@]}"
fi

"${ROOT}/buildfiles/ios/write_build_manifest.sh" \
    "${OUTPUT_DIR}/manifest.txt" "${ALL_INPUTS[@]}"

find "${ROOT}" -type f \( -name '*.map' -o -name '*linker-map*' \) -print0 2>/dev/null | \
    while IFS= read -r -d '' MAP; do
        cp "${MAP}" "${OUTPUT_DIR}/$(basename "${MAP}")"
    done

(
    cd "${OUTPUT_DIR}"
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | \
        while IFS= read -r FILE_PATH; do
            shasum -a 256 "${FILE_PATH}"
        done >SHA256SUMS
)

echo "Captured RPCS3 iOS build evidence: ${OUTPUT_DIR}"
