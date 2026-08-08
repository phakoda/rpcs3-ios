#!/bin/zsh

set -eu
set -o pipefail

SCRIPT_DIR=${0:A:h}
DEVICE=""
OPEN_SIMULATOR=1

usage() {
    cat <<'EOF'
Usage: run_simulator.sh [--device <name-or-udid>] [--no-open] <app> [-- <app arguments...>]

Validates, boots, installs, and launches an iOS Simulator .app. If --device is
omitted, a booted iPhone is preferred, then the first available iPhone.

Examples:
  buildfiles/ios/run_simulator.sh build-ios-sim/bin/RPCS3.app
  buildfiles/ios/run_simulator.sh --device "iPhone 17 Pro" RPCS3.app -- --no-gui
EOF
}

fail() {
    print -u2 -- "ERROR: $*"
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --device)
            (( $# >= 2 )) || fail "--device requires a name or UDID"
            DEVICE=$2
            shift 2
            ;;
        --no-open)
            OPEN_SIMULATOR=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

(( $# >= 1 )) || {
    usage >&2
    exit 64
}

APP=${1:A}
shift
if [[ ${1:-} == -- ]]; then
    shift
fi
APP_ARGS=("$@")

[[ -d "$APP" && "$APP" == *.app ]] || fail "expected an .app bundle: $APP"
"$SCRIPT_DIR/inspect_simulator_target.sh" "$APP"

command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable; select a full Xcode installation"

DEVICES=$(xcrun simctl list devices available)
if [[ -z "$DEVICE" ]]; then
    DEVICE=$(print -r -- "$DEVICES" | awk -F '[()]' '/iPhone/ && /Booted/ { print $2; exit }')
    if [[ -z "$DEVICE" ]]; then
        DEVICE=$(print -r -- "$DEVICES" | awk -F '[()]' '/iPhone/ { print $2; exit }')
    fi
    [[ -n "$DEVICE" ]] || fail "no available iPhone simulator was found"
fi

MATCH=$(print -r -- "$DEVICES" | awk -v requested="$DEVICE" '
    index($0, "(" requested ")") || index($0, requested " (") { print; exit }
')
[[ -n "$MATCH" ]] || fail "no available simulator matches: $DEVICE"
UDID=$(print -r -- "$MATCH" | awk -F '[()]' '{ print $2 }')
NAME=$(print -r -- "$MATCH" | sed -E 's/^[[:space:]]*([^()]*) \(.*/\1/')

PLIST="$APP/Info.plist"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")

print -- "Simulator   : $NAME ($UDID)"
if [[ "$MATCH" != *Booted* ]]; then
    print -- "Booting simulator..."
    xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b

if (( OPEN_SIMULATOR )); then
    open -a Simulator --args -CurrentDeviceUDID "$UDID"
fi

print -- "Installing   : $APP"
xcrun simctl install "$UDID" "$APP"

print -- "Launching    : $BUNDLE_ID"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "${APP_ARGS[@]}"

print -- "Log command  : xcrun simctl spawn $UDID log stream --style compact --predicate 'process == \"$BUNDLE_ID\"'"
