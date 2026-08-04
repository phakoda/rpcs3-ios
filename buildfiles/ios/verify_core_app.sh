#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 /path/to/RPCS3\ iOS\ Core.app" >&2; exit 2; }
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

[[ -d "${APP}" ]] || { echo "error: app bundle not found: ${APP}" >&2; exit 1; }
[[ -f "${APP}/Info.plist" ]] || { echo "error: missing app Info.plist" >&2; exit 1; }
plutil -lint "${APP}/Info.plist" >/dev/null

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP}/Info.plist")"
BINARY="${APP}/${EXECUTABLE_NAME}"
FRAMEWORK="${APP}/Frameworks/RPCS3Core.framework"
[[ -f "${BINARY}" ]] || { echo "error: app executable is missing: ${BINARY}" >&2; exit 1; }
[[ -d "${FRAMEWORK}" ]] || { echo "error: embedded RPCS3Core.framework is missing" >&2; exit 1; }

"${ROOT}/buildfiles/ios/verify_core_framework.sh" "${FRAMEWORK}"

APP_ARCHS="$(lipo -archs "${BINARY}")"
FRAMEWORK_BINARY="${FRAMEWORK}/RPCS3Core"
FRAMEWORK_ARCHS="$(lipo -archs "${FRAMEWORK_BINARY}")"
for ARCH in ${APP_ARCHS}; do
    case " ${FRAMEWORK_ARCHS} " in
        *" ${ARCH} "*) ;;
        *) echo "error: embedded framework lacks app architecture ${ARCH}" >&2; exit 1 ;;
    esac
done

LOAD_COMMANDS="$(otool -L "${BINARY}")"
grep -Eq '@rpath/RPCS3Core\.framework/RPCS3Core' <<<"${LOAD_COMMANDS}" || {
    echo "error: app does not load RPCS3Core.framework through @rpath" >&2
    echo "${LOAD_COMMANDS}" >&2
    exit 1
}
if grep -Eq 'Qt[^/]*\.framework|AppKit\.framework|/usr/local/|/opt/homebrew/' <<<"${LOAD_COMMANDS}"; then
    echo "error: app contains a desktop or host-machine load dependency" >&2
    echo "${LOAD_COMMANDS}" >&2
    exit 1
fi

RPATHS="$(otool -l "${BINARY}" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" {in_rpath=1; next}
    in_rpath && $1 == "path" {print $2; in_rpath=0}
')"
grep -Fxq '@executable_path/Frameworks' <<<"${RPATHS}" || {
    echo "error: app lacks @executable_path/Frameworks LC_RPATH" >&2
    exit 1
}

codesign --verify --deep --strict "${APP}"
codesign -d --entitlements :- "${APP}" >"${TMPDIR:-/tmp}/rpcs3-ios-app-entitlements.plist" 2>/dev/null || true

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Info.plist")"
[[ "${APP_VERSION}" == "0.5" ]] || { echo "error: app short version is not 0.5" >&2; exit 1; }

echo "app architectures: ${APP_ARCHS}"
echo "RPCS3 iOS app verification passed: ${APP}"
