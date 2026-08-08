#!/bin/zsh

set -eu
set -o pipefail

SCRIPT_DIR=${0:A:h}
SOURCE="$SCRIPT_DIR/jit_callback_probe.cpp"
OUTPUT_DIR=${TMPDIR:-/tmp}/rpcs3-ios-jit-probe
RUN_SIMULATOR=0
SIMULATOR_DEVICE=booted

usage() {
	cat <<'EOF'
Usage: probe_jit_callback.sh [--output <directory>] [--run-simulator [device]]

Compiles and links the arm64 JIT callback probe for iPhone and Simulator.
With --run-simulator, it also packages, allowlist-signs, installs, and runs the
probe on an already-booted Simulator (or the supplied device name/UDID).
EOF
}

while (( $# > 0 )); do
	case "$1" in
		--output)
			(( $# >= 2 )) || {
				usage >&2
				exit 64
			}
			OUTPUT_DIR=${2:A}
			shift 2
			;;
		--run-simulator)
			RUN_SIMULATOR=1
			if (( $# >= 2 )) && [[ "$2" != --* ]]; then
				SIMULATOR_DEVICE=$2
				shift 2
			else
				shift
			fi
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			print -u2 -- "ERROR: unknown argument: $1"
			usage >&2
			exit 64
			;;
	esac
done

command -v xcrun >/dev/null 2>&1 || {
	print -u2 -- "ERROR: xcrun is unavailable; select a full Xcode installation"
	exit 1
}

mkdir -p "$OUTPUT_DIR"

DEVICE_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
DEVICE_OUTPUT="$OUTPUT_DIR/jit-callback-iphoneos"
SIMULATOR_OUTPUT="$OUTPUT_DIR/jit-callback-iphonesimulator"

print -- "Compiling and linking the iphoneos probe..."
xcrun --sdk iphoneos clang++ \
	-std=c++20 -arch arm64 -miphoneos-version-min=17.4 \
	-isysroot "$DEVICE_SDK" "$SOURCE" -o "$DEVICE_OUTPUT"

print -- "Compiling and linking the iphonesimulator probe..."
xcrun --sdk iphonesimulator clang++ \
	-std=c++20 -arch arm64 -mios-simulator-version-min=17.4 \
	-isysroot "$SIMULATOR_SDK" "$SOURCE" -o "$SIMULATOR_OUTPUT"

DEVICE_PLATFORM=$(xcrun vtool -show-build "$DEVICE_OUTPUT" | awk '/^[[:space:]]*platform / { print $2; exit }')
SIMULATOR_PLATFORM=$(xcrun vtool -show-build "$SIMULATOR_OUTPUT" | awk '/^[[:space:]]*platform / { print $2; exit }')

[[ "$DEVICE_PLATFORM" == IOS ]] || {
	print -u2 -- "ERROR: expected IOS output, found ${DEVICE_PLATFORM:-unknown}"
	exit 1
}

[[ "$SIMULATOR_PLATFORM" == IOSSIMULATOR ]] || {
	print -u2 -- "ERROR: expected IOSSIMULATOR output, found ${SIMULATOR_PLATFORM:-unknown}"
	exit 1
}

print -- "iphoneos       : $DEVICE_OUTPUT"
print -- "iphonesimulator: $SIMULATOR_OUTPUT"
print -- "Result         : both callback probes compiled and linked for arm64 iOS 17.4+"

if (( RUN_SIMULATOR )); then
	APP="$OUTPUT_DIR/RPCS3JITProbe.app"
	PLIST="$APP/Info.plist"
	ENTITLEMENTS="$OUTPUT_DIR/jit-callback-probe.entitlements"
	mkdir -p "$APP"
	cp "$SIMULATOR_OUTPUT" "$APP/RPCS3JITProbe"

	plutil -create xml1 "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string en' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string RPCS3JITProbe' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.rpcs3.ios.jit-probe' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleName string RPCS3 JIT Probe' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleSupportedPlatforms array' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleSupportedPlatforms:0 string iPhoneSimulator' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$PLIST"
	/usr/libexec/PlistBuddy -c 'Add :MinimumOSVersion string 17.4' "$PLIST"

	plutil -create xml1 "$ENTITLEMENTS"
	/usr/libexec/PlistBuddy -c 'Add :com.apple.developer.cs.allow-jit bool true' "$ENTITLEMENTS"
	/usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.jit-write-allowlist bool true' "$ENTITLEMENTS"
	codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"

	print -- "Installing       : $APP"
	xcrun simctl install "$SIMULATOR_DEVICE" "$APP"
	print -- "Running on       : $SIMULATOR_DEVICE"
	RUNTIME_OUTPUT=$(xcrun simctl launch --terminate-running-process --console \
		"$SIMULATOR_DEVICE" org.rpcs3.ios.jit-probe)
	print -r -- "$RUNTIME_OUTPUT"
	[[ "$RUNTIME_OUTPUT" == *"JIT callback probe passed"* ]] || {
		print -u2 -- "ERROR: the Simulator probe did not report success"
		exit 1
	}
	print -- "Runtime result   : callback copy, cache invalidation, atomic patch, and RW JIT data passed"
else
	print -- "Runtime          : rerun with --run-simulator after booting an iOS Simulator"
fi
