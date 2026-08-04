#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 device|simulator archive-or-library [...]" >&2
    exit 2
}

[[ $# -ge 2 ]] || usage
EXPECTED_PLATFORM="$1"
shift

case "${EXPECTED_PLATFORM}" in
    device) EXPECTED_BUILD_PLATFORM="IOS" ;;
    simulator) EXPECTED_BUILD_PLATFORM="IOSSIMULATOR" ;;
    *) usage ;;
esac

TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

verify_object() {
    local object="$1"
    local description="$2"
    local archs build

    archs="$(lipo -archs "${object}" 2>/dev/null || true)"
    if [[ -n "${archs}" ]]; then
        case " ${archs} " in
            *" arm64 "*) ;;
            *) echo "error: ${description} lacks arm64: ${archs}" >&2; return 1 ;;
        esac
    else
        file "${object}" | grep -Eq 'arm64|Mach-O 64-bit' || {
            echo "error: ${description} is not an arm64 Mach-O object" >&2
            file "${object}" >&2
            return 1
        }
    fi

    build="$(xcrun vtool -show-build "${object}" 2>/dev/null || true)"
    grep -Eq "platform ${EXPECTED_BUILD_PLATFORM}($|[[:space:]])" <<<"${build}" || {
        echo "error: ${description} is not marked for ${EXPECTED_BUILD_PLATFORM}" >&2
        echo "${build}" >&2
        return 1
    }
}

for INPUT in "$@"; do
    [[ -f "${INPUT}" ]] || { echo "error: dependency file not found: ${INPUT}" >&2; exit 1; }
    case "${INPUT}" in
        *.a)
            ARCHIVE_DIR="${TEMP_ROOT}/$(basename "${INPUT}").d"
            mkdir -p "${ARCHIVE_DIR}"
            MEMBER="$(ar -t "${INPUT}" | awk 'NF {print; exit}')"
            [[ -n "${MEMBER}" ]] || { echo "error: archive is empty: ${INPUT}" >&2; exit 1; }
            (
                cd "${ARCHIVE_DIR}"
                ar -x "${INPUT}" "${MEMBER}"
            )
            verify_object "${ARCHIVE_DIR}/${MEMBER}" "${INPUT}(${MEMBER})"
            ;;
        *.dylib|*.framework/*)
            verify_object "${INPUT}" "${INPUT}"
            ;;
        *)
            echo "error: unsupported dependency input: ${INPUT}" >&2
            exit 1
            ;;
    esac

done

echo "Dependency archive platform verification passed for ${EXPECTED_PLATFORM}."
