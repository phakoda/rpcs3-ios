#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 /path/to/RPCS3Core.framework [device|simulator]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
FRAMEWORK="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
EXPECTED_PLATFORM="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPECTED_EXPORTS="${ROOT}/rpcs3/ios/RPCS3Core.exports"

[[ -d "${FRAMEWORK}" ]] || { echo "error: framework not found: ${FRAMEWORK}" >&2; exit 1; }
[[ -f "${FRAMEWORK}/Info.plist" ]] || { echo "error: missing framework Info.plist" >&2; exit 1; }
[[ -f "${FRAMEWORK}/Headers/RPCS3Core.h" ]] || { echo "error: missing RPCS3Core.h" >&2; exit 1; }
[[ -f "${FRAMEWORK}/Headers/RPCS3CoreStatus.h" ]] || { echo "error: missing RPCS3CoreStatus.h" >&2; exit 1; }
[[ -f "${FRAMEWORK}/Modules/module.modulemap" ]] || { echo "error: missing module.modulemap" >&2; exit 1; }

BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${FRAMEWORK}/Info.plist")"
BINARY="${FRAMEWORK}/${BINARY_NAME}"
[[ -f "${BINARY}" ]] || { echo "error: missing framework binary: ${BINARY}" >&2; exit 1; }

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "${FRAMEWORK}/Info.plist")" == "FMWK" ]] || {
    echo "error: framework bundle type is not FMWK" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${FRAMEWORK}/Info.plist")" == "0.5" ]] || {
    echo "error: framework short version is not 0.5" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${FRAMEWORK}/Info.plist")" == "5" ]] || {
    echo "error: framework bundle version is not 5" >&2
    exit 1
}

plutil -lint "${FRAMEWORK}/Info.plist" >/dev/null
grep -Fq 'header "RPCS3Core.h"' "${FRAMEWORK}/Modules/module.modulemap"
grep -Fq 'header "RPCS3CoreStatus.h"' "${FRAMEWORK}/Modules/module.modulemap"

ARCHS="$(lipo -archs "${BINARY}")"
case " ${ARCHS} " in
    *" arm64 "*) ;;
    *) echo "error: framework does not contain arm64: ${ARCHS}" >&2; exit 1 ;;
esac

BUILD_INFO="$(xcrun vtool -show-build "${BINARY}" 2>/dev/null || true)"
if [[ -n "${EXPECTED_PLATFORM}" ]]; then
    case "${EXPECTED_PLATFORM}" in
        device)
            grep -Eq 'platform IOS($|[[:space:]])' <<<"${BUILD_INFO}" || {
                echo "error: framework binary is not marked for iOS device" >&2
                echo "${BUILD_INFO}" >&2
                exit 1
            }
            ;;
        simulator)
            grep -Eq 'platform IOSSIMULATOR($|[[:space:]])' <<<"${BUILD_INFO}" || {
                echo "error: framework binary is not marked for iOS simulator" >&2
                echo "${BUILD_INFO}" >&2
                exit 1
            }
            ;;
        *) usage ;;
    esac
fi

ACTUAL_EXPORTS="$(mktemp)"
EXPECTED_SORTED="$(mktemp)"
trap 'rm -f "${ACTUAL_EXPORTS}" "${EXPECTED_SORTED}"' EXIT
nm -gjU "${BINARY}" | grep -E '^_(RPCS3Core|rpcs3_ios_core_)' | sort -u >"${ACTUAL_EXPORTS}"
sort -u "${EXPECTED_EXPORTS}" >"${EXPECTED_SORTED}"
if ! diff -u "${EXPECTED_SORTED}" "${ACTUAL_EXPORTS}"; then
    echo "error: framework exports do not match RPCS3Core.exports" >&2
    exit 1
fi

LOAD_COMMANDS="$(otool -L "${BINARY}")"
if grep -Eq 'Qt[^/]*\.framework|AppKit\.framework|/usr/local/|/opt/homebrew/' <<<"${LOAD_COMMANDS}"; then
    echo "error: framework contains a desktop or host-machine load dependency" >&2
    echo "${LOAD_COMMANDS}" >&2
    exit 1
fi

if codesign -dvv "${FRAMEWORK}" >/dev/null 2>&1; then
    codesign --verify --deep --strict "${FRAMEWORK}"
else
    echo "notice: framework is unsigned; signature verification skipped" >&2
fi

file "${BINARY}"
echo "architectures: ${ARCHS}"
echo "RPCS3Core.framework verification passed: ${FRAMEWORK}"
