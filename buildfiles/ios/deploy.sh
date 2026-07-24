#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/deploy.sh <simulator|device> <bootstrap|full>

Optional environment:
  BUILD_DIR       Configured Xcode build directory.
  CONFIGURATION   Xcode configuration (default: Release).
  APP_PATH        Explicit .app bundle path, bypassing Xcode build settings.
  DEVICE          Device name, UDID, or devicectl identifier. Required for
                  physical devices unless exactly one eligible device exists.
  LAUNCH=1        Launch after installation when a bundle identifier is found.

The device path uses `xcrun devicectl`. A vphone guest can use the same path
when it is exposed to CoreDevice on the host; the vphone MCP server itself does
not currently expose an app-install action.
EOF
}

platform="${1:-}"
mode="${2:-}"
if [[ "${platform}" != "simulator" && "${platform}" != "device" ]]; then
    usage >&2
    exit 64
fi
if [[ "${mode}" != "bootstrap" && "${mode}" != "full" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: deployment requires macOS and Xcode command-line tools" >&2
    exit 69
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
configuration="${CONFIGURATION:-Release}"

if [[ "${mode}" == "bootstrap" ]]; then
    scheme="rpcs3_ios_bootstrap"
else
    scheme="rpcs3"
fi

if [[ "${platform}" == "simulator" ]]; then
    sdk="iphonesimulator"
    default_build_dir="${repo_root}/build-ios-simulator-${mode}"
else
    sdk="iphoneos"
    default_build_dir="${repo_root}/build-ios-device-${mode}"
fi

build_dir="${BUILD_DIR:-${default_build_dir}}"
project="${build_dir}/rpcs3.xcodeproj"
app_path="${APP_PATH:-}"

if [[ -z "${app_path}" ]]; then
    if [[ ! -d "${project}" ]]; then
        echo "error: Xcode project not found: ${project}" >&2
        exit 66
    fi

    settings="$(xcodebuild -project "${project}" -scheme "${scheme}" -sdk "${sdk}" -configuration "${configuration}" -showBuildSettings)"
    target_build_dir="$(awk -F ' = ' '/ TARGET_BUILD_DIR = / {print $2; exit}' <<< "${settings}")"
    wrapper_name="$(awk -F ' = ' '/ WRAPPER_NAME = / {print $2; exit}' <<< "${settings}")"
    app_path="${target_build_dir}/${wrapper_name}"
fi

if [[ ! -d "${app_path}" || "${app_path}" != *.app ]]; then
    echo "error: application bundle not found: ${app_path}" >&2
    echo "Build it first or set APP_PATH explicitly." >&2
    exit 66
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Info.plist" 2>/dev/null || true)"

if [[ "${platform}" == "simulator" ]]; then
    xcrun simctl install booted "${app_path}"
    if [[ "${LAUNCH:-0}" == "1" && -n "${bundle_id}" ]]; then
        xcrun simctl launch booted "${bundle_id}"
    fi
else
    device="${DEVICE:-}"
    if [[ -z "${device}" ]]; then
        mapfile -t devices < <(xcrun devicectl list devices 2>/dev/null | awk '/connected/ {print $1}')
        if [[ "${#devices[@]}" != "1" ]]; then
            echo "error: set DEVICE to a CoreDevice identifier, name, or UDID" >&2
            xcrun devicectl list devices || true
            exit 64
        fi
        device="${devices[0]}"
    fi

    xcrun devicectl device install app --device "${device}" "${app_path}"
    if [[ "${LAUNCH:-0}" == "1" && -n "${bundle_id}" ]]; then
        xcrun devicectl device process launch --device "${device}" "${bundle_id}"
    fi
fi

echo "Installed ${app_path}"
