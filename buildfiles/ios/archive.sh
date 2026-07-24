#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/archive.sh <bootstrap|core|full>

Optional environment:
  BUILD_DIR        Configured Xcode build directory.
  OUTPUT_DIR       Archive/IPA output directory (default: out/ios).
  CONFIGURATION    Xcode configuration (default: Release).
  DEVELOPMENT_TEAM Apple development team identifier.
  CODE_SIGN_IDENTITY
  PROVISIONING_PROFILE_SPECIFIER
  ARCHIVE_ONLY=1   Skip IPA packaging and retain only the xcarchive.

Without DEVELOPMENT_TEAM the script produces an unsigned archive and an
unsigned IPA-shaped ZIP for inspection or supported alternative signing tools.
The core mode packages the whole-archive final-link harness, not the Qt app.
EOF
}

mode="${1:-}"
if [[ "${mode}" != "bootstrap" && "${mode}" != "core" && "${mode}" != "full" ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: archiving iOS applications requires macOS and Xcode" >&2
    exit 69
fi

for command in xcodebuild ditto; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
configuration="${CONFIGURATION:-Release}"
output_dir="${OUTPUT_DIR:-${repo_root}/out/ios}"

case "${mode}" in
    bootstrap)
        scheme="rpcs3_ios_bootstrap"
        default_build_dir="${repo_root}/build-ios-device-bootstrap"
        product_label="RPCS3-iOS-Bootstrap"
        ;;
    core)
        scheme="rpcs3_ios_core_link"
        default_build_dir="${repo_root}/build-ios-device-core"
        product_label="RPCS3-iOS-Core-Link"
        ;;
    full)
        scheme="rpcs3"
        default_build_dir="${repo_root}/build-ios-device-full"
        product_label="RPCS3-iOS"
        ;;
esac

build_dir="${BUILD_DIR:-${default_build_dir}}"
project="${build_dir}/rpcs3.xcodeproj"
if [[ ! -d "${project}" ]]; then
    echo "error: Xcode project not found: ${project}" >&2
    echo "Configure it first with buildfiles/ios/configure.sh device ${mode}." >&2
    exit 66
fi

mkdir -p "${output_dir}"
archive_path="${output_dir}/${product_label}.xcarchive"
ipa_path="${output_dir}/${product_label}.ipa"
rm -rf "${archive_path}" "${ipa_path}" "${output_dir}/Payload"

xcode_args=(
    -project "${project}"
    -scheme "${scheme}"
    -sdk iphoneos
    -configuration "${configuration}"
    -archivePath "${archive_path}"
    SKIP_INSTALL=NO
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    xcode_args+=(
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"
        CODE_SIGN_STYLE=Automatic
    )
    if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
        xcode_args+=(CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}")
    fi
    if [[ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
        xcode_args+=(PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER}")
    fi
else
    xcode_args+=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
    )
fi

xcodebuild "${xcode_args[@]}" clean archive

app_path="$(find "${archive_path}/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
    echo "error: archive did not contain an application bundle" >&2
    exit 1
fi

if [[ "${ARCHIVE_ONLY:-0}" != "1" ]]; then
    mkdir -p "${output_dir}/Payload"
    ditto "${app_path}" "${output_dir}/Payload/$(basename "${app_path}")"
    pushd "${output_dir}" >/dev/null
    ditto -c -k --sequesterRsrc --keepParent Payload "$(basename "${ipa_path}")"
    popd >/dev/null
    rm -rf "${output_dir}/Payload"
fi

cat <<EOF
Archive created:
  ${archive_path}
EOF
if [[ "${ARCHIVE_ONLY:-0}" != "1" ]]; then
    cat <<EOF
IPA package created:
  ${ipa_path}
EOF
fi
