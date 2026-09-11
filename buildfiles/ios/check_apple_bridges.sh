#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Compile the Objective-C++ bridges against real SDK headers without building
# RPCS3's external dependencies. This is a syntax check, not a link/device test.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcrun >/dev/null 2>&1; then
    echo "This check requires macOS with Xcode and both iOS SDKs installed." >&2
    exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
minimum="${RPCS3_IOS_DEPLOYMENT_TARGET:-17.4}"
if [[ ! "$minimum" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "RPCS3_IOS_DEPLOYMENT_TARGET must be a numeric version, e.g. 17.4." >&2
    exit 2
fi
for sdk in iphoneos iphonesimulator; do
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    target="arm64-apple-ios${minimum}"
    if [[ "$sdk" == iphonesimulator ]]; then target+="-simulator"; fi
    for source in rpcs3/Input/ios_controller_bridge.mm rpcs3/Emu/RSX/VK/vkutils/metal_layer.mm; do
        echo "Syntax checking $source for $target"
        xcrun --sdk "$sdk" clang++ \
            -std=c++20 -target "$target" -isysroot "$sdk_path" \
            -fobjc-arc -fblocks -fsyntax-only -Wall -Wextra \
            -Werror=return-type -Werror=objc-method-access \
            -Wno-deprecated-declarations -I"$root/rpcs3" "$root/$source"
    done
done
