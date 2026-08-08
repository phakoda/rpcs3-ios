#!/bin/zsh

set -eu
set -o pipefail

usage() {
    cat <<'EOF'
Usage: inspect_simulator_target.sh <app-bundle-or-mach-o>

Read-only compatibility check for an iOS Simulator executable or .app.
It rejects macOS and iPhone-device binaries even when they contain arm64 code.
EOF
}

fail() {
    print -u2 -- "ERROR: $*"
    exit 1
}

[[ $# -eq 1 ]] || {
    usage >&2
    exit 64
}

TARGET=${1:A}
[[ -e "$TARGET" ]] || fail "target does not exist: $TARGET"

APP=""
PLIST=""
EXECUTABLE="$TARGET"

if [[ -d "$TARGET" && "$TARGET" == *.app ]]; then
    APP="$TARGET"
    if [[ -f "$APP/Info.plist" ]]; then
        PLIST="$APP/Info.plist"
        EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || true)
        [[ -n "$EXECUTABLE_NAME" ]] || fail "CFBundleExecutable is missing from $PLIST"
        EXECUTABLE="$APP/$EXECUTABLE_NAME"
    elif [[ -f "$APP/Contents/Info.plist" ]]; then
        PLIST="$APP/Contents/Info.plist"
        EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || true)
        [[ -n "$EXECUTABLE_NAME" ]] || fail "CFBundleExecutable is missing from $PLIST"
        EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
    else
        fail "no Info.plist found in app bundle: $APP"
    fi
fi

[[ -f "$EXECUTABLE" ]] || fail "bundle executable does not exist: $EXECUTABLE"

FILE_DESCRIPTION=$(file -b "$EXECUTABLE")
[[ "$FILE_DESCRIPTION" == *Mach-O* ]] || fail "not a Mach-O executable: $EXECUTABLE ($FILE_DESCRIPTION)"

BUILD_INFO=$(xcrun vtool -show-build "$EXECUTABLE" 2>/dev/null || true)
PLATFORM=$(print -r -- "$BUILD_INFO" | awk '/^[[:space:]]*platform / { print $2; exit }')

print -- "Target      : $TARGET"
print -- "Executable  : $EXECUTABLE"
print -- "File        : $FILE_DESCRIPTION"
print -- "Platform    : ${PLATFORM:-unknown}"

if [[ -n "$PLIST" ]]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)
    SUPPORTED=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms' "$PLIST" 2>/dev/null || true)
    print -- "Bundle ID   : ${BUNDLE_ID:-missing}"
    print -- "Platforms   : ${SUPPORTED:-missing}"
fi

case "$PLATFORM" in
    IOSSIMULATOR)
        ;;
    IOS)
        fail "this is an iPhone-device binary (platform IOS), not an iOS Simulator binary"
        ;;
    MACOS)
        fail "this is a macOS binary (platform MACOS), not an iOS Simulator binary"
        ;;
    *)
        fail "expected LC_BUILD_VERSION platform IOSSIMULATOR; found ${PLATFORM:-none}"
        ;;
esac

if [[ -n "$APP" ]]; then
    [[ "$PLIST" == "$APP/Info.plist" ]] || fail "macOS-style Contents/ bundle layout is not installable in CoreSimulator"
    [[ -n "${BUNDLE_ID:-}" ]] || fail "CFBundleIdentifier is required"
    if [[ -n "${SUPPORTED:-}" && "$SUPPORTED" != *iPhoneSimulator* ]]; then
        fail "CFBundleSupportedPlatforms does not contain iPhoneSimulator"
    fi

    INCOMPATIBLE=0
    while IFS= read -r -d '' CANDIDATE; do
        CANDIDATE_FILE=$(file -b "$CANDIDATE" 2>/dev/null || true)
        [[ "$CANDIDATE_FILE" == *Mach-O* ]] || continue
        CANDIDATE_PLATFORM=$(xcrun vtool -show-build "$CANDIDATE" 2>/dev/null | awk '/^[[:space:]]*platform / { print $2; exit }')
        if [[ "$CANDIDATE_PLATFORM" != IOSSIMULATOR ]]; then
            print -u2 -- "INCOMPATIBLE: $CANDIDATE ($CANDIDATE_PLATFORM)"
            INCOMPATIBLE=1
        fi
    done < <(find "$APP" -type f -print0)
    (( INCOMPATIBLE == 0 )) || fail "one or more embedded Mach-O files target a platform other than IOSSIMULATOR"
fi

print -- "Result      : compatible with CoreSimulator"
