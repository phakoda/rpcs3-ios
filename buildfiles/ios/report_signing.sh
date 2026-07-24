#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash buildfiles/ios/report_signing.sh /path/to/Application.app

Prints the entitlements embedded in the signed executable and, when present,
the provisioning-profile entitlements. Requested source plists are not proof
that these capabilities survived provisioning and codesigning.
EOF
}

app_path="${1:-}"
if [[ -z "${app_path}" || ! -d "${app_path}" || "${app_path}" != *.app ]]; then
    usage >&2
    exit 64
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: codesign and provisioning-profile inspection require macOS" >&2
    exit 69
fi

for command in codesign security plutil; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "error: required command not found: ${command}" >&2
        exit 69
    }
done

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${app_path}/Info.plist")"
executable="${app_path}/${executable_name}"
if [[ ! -f "${executable}" ]]; then
    echo "error: bundle executable not found: ${executable}" >&2
    exit 66
fi

temporary="$(mktemp -d "${TMPDIR:-/tmp}/rpcs3-ios-signing.XXXXXX")"
trap 'rm -rf "${temporary}"' EXIT

signed_entitlements="${temporary}/signed-entitlements.plist"
profile_plist="${temporary}/profile.plist"

if codesign -d --entitlements "${signed_entitlements}" "${executable}" >/dev/null 2>&1; then
    echo "Effective executable entitlements:"
    plutil -p "${signed_entitlements}"
else
    echo "Effective executable entitlements: unavailable (bundle may be unsigned)."
fi

profile="${app_path}/embedded.mobileprovision"
if [[ -f "${profile}" ]] && security cms -D -i "${profile}" > "${profile_plist}" 2>/dev/null; then
    echo
    echo "Provisioning profile:"
    /usr/libexec/PlistBuddy -c 'Print :Name' "${profile_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Print :UUID' "${profile_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "${profile_plist}" 2>/dev/null || true
    echo "Provisioning-profile entitlements:"
    /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "${profile_plist}" > "${temporary}/profile-entitlements.plist"
    plutil -p "${temporary}/profile-entitlements.plist"
else
    echo
    echo "Provisioning profile: not embedded or could not be decoded."
fi

echo
for entitlement in \
    dynamic-codesigning \
    com.apple.security.cs.allow-jit \
    get-task-allow \
    com.apple.developer.kernel.extended-virtual-addressing \
    com.apple.developer.kernel.increased-memory-limit; do
    value="missing"
    if [[ -f "${signed_entitlements}" ]]; then
        value="$(/usr/libexec/PlistBuddy -c "Print :${entitlement}" "${signed_entitlements}" 2>/dev/null || echo missing)"
    fi
    printf '%-64s %s\n' "${entitlement}" "${value}"
done
