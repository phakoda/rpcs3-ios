#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 /path/to/RPCS3Core.xcframework" >&2; exit 2; }
[[ -d "$1" ]] || { echo "error: XCFramework not found: $1" >&2; exit 1; }
XCFRAMEWORK="$(cd "$1" && pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_FRAMEWORK="${ROOT}/buildfiles/ios/verify_core_framework.sh"

[[ -f "${XCFRAMEWORK}/Info.plist" ]] || { echo "error: missing XCFramework Info.plist" >&2; exit 1; }
plutil -lint "${XCFRAMEWORK}/Info.plist" >/dev/null

mapfile_compat() {
    while IFS= read -r line; do
        [[ -n "${line}" ]] && printf '%s\0' "${line}"
    done
}

LIBRARY_IDS_RAW="$(/usr/libexec/PlistBuddy -c 'Print :AvailableLibraries' "${XCFRAMEWORK}/Info.plist" | \
    awk '/LibraryIdentifier = / {gsub(/[";]/, "", $3); print $3}')"
[[ -n "${LIBRARY_IDS_RAW}" ]] || { echo "error: XCFramework has no AvailableLibraries" >&2; exit 1; }

DEVICE_COUNT=0
SIMULATOR_COUNT=0
while IFS= read -r IDENTIFIER; do
    [[ -n "${IDENTIFIER}" ]] || continue
    ENTRY="${XCFRAMEWORK}/${IDENTIFIER}"
    FRAMEWORK="${ENTRY}/RPCS3Core.framework"
    [[ -d "${FRAMEWORK}" ]] || {
        echo "error: slice ${IDENTIFIER} does not contain RPCS3Core.framework" >&2
        exit 1
    }

    if [[ "${IDENTIFIER}" == *simulator* ]]; then
        ((SIMULATOR_COUNT += 1))
        "${VERIFY_FRAMEWORK}" "${FRAMEWORK}" simulator
    else
        ((DEVICE_COUNT += 1))
        "${VERIFY_FRAMEWORK}" "${FRAMEWORK}" device
    fi
done <<<"${LIBRARY_IDS_RAW}"

[[ ${DEVICE_COUNT} -ge 1 ]] || { echo "error: XCFramework has no iOS device slice" >&2; exit 1; }
[[ ${SIMULATOR_COUNT} -ge 1 ]] || { echo "error: XCFramework has no iOS simulator slice" >&2; exit 1; }

echo "RPCS3Core.xcframework verification passed: ${XCFRAMEWORK}"
