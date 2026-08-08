#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${TMPDIR:-/tmp}/rpcs3-ios-cmake-composition"
SOURCE_DIR="${WORK}/source"
BUILD_DIR="${WORK}/build"

rm -rf "${WORK}"
mkdir -p "${SOURCE_DIR}"
ln -s "${ROOT}/rpcs3" "${SOURCE_DIR}/rpcs3"
ln -s "${ROOT}/3rdparty" "${SOURCE_DIR}/3rdparty"

cat >"${SOURCE_DIR}/dummy.cpp" <<'EOF'
int rpcs3_ios_contract_dummy()
{
    return 0;
}
EOF

cat >"${SOURCE_DIR}/main.cpp" <<'EOF'
int main()
{
    return 0;
}
EOF

cat >"${SOURCE_DIR}/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.27)
project(rpcs3_ios_composition_contract LANGUAGES C CXX OBJCXX)

set(RPCS3_IOS ON)
add_library(rpcs3_ios_core_framework SHARED dummy.cpp)
add_executable(rpcs3_ios_core_link main.cpp)
add_library(3rdparty_rtmidi STATIC
    "${CMAKE_SOURCE_DIR}/3rdparty/ios/rtmidi/rtmidi_coremidi.cpp")

include("${CMAKE_SOURCE_DIR}/rpcs3/ios/CoreExtensions.cmake")

get_target_property(CORE_SOURCES rpcs3_ios_core_framework SOURCES)
get_target_property(HOST_SOURCES rpcs3_ios_core_link SOURCES)
get_target_property(RTMIDI_SOURCES 3rdparty_rtmidi SOURCES)
get_target_property(CORE_VERSION rpcs3_ios_core_framework VERSION)
get_target_property(CORE_SOVERSION rpcs3_ios_core_framework SOVERSION)
get_target_property(CORE_PUBLIC_HEADERS rpcs3_ios_core_framework PUBLIC_HEADER)

foreach(REQUIRED_SOURCE IN ITEMS
    IOSCoreOperations.cpp
    IOSCoreOperationAPI.cpp
    IOSCoreMutationAPI.cpp
    IOSCoreStatusAPI.cpp
    IOSCoreDiagnostics.cpp
    IOSCoreLifecycleDeferred.mm
    IOSCoreMIDIIdentity.mm
    IOSCoreMIDIComposition.mm
    IOSCoreInstallerSupport.cpp
    IOSCoreInstallerTransaction.cpp
    IOSCoreInstallerRecovery.cpp
    IOSCoreInstallationStatus.cpp)
    string(FIND "${CORE_SOURCES}" "${REQUIRED_SOURCE}" FOUND_INDEX)
    if(FOUND_INDEX EQUAL -1)
        message(FATAL_ERROR "Core composition omitted ${REQUIRED_SOURCE}: ${CORE_SOURCES}")
    endif()
endforeach()

string(FIND "${HOST_SOURCES}" "IOSCoreOpenURL.mm" OPEN_URL_INDEX)
if(OPEN_URL_INDEX EQUAL -1)
    message(FATAL_ERROR "Management host composition omitted IOSCoreOpenURL.mm")
endif()

string(FIND "${RTMIDI_SOURCES}" "rtmidi_coremidi_v2.cpp" RTMIDI_V2_INDEX)
if(RTMIDI_V2_INDEX EQUAL -1)
    message(FATAL_ERROR "RtMidi composition omitted rtmidi_coremidi_v2.cpp")
endif()
string(FIND "${RTMIDI_SOURCES}" "rtmidi_coremidi.cpp" RTMIDI_V1_INDEX)
if(NOT RTMIDI_V1_INDEX EQUAL -1)
    message(FATAL_ERROR "RtMidi composition retained the superseded CoreMIDI source")
endif()

if(NOT CORE_VERSION STREQUAL "0.5.0")
    message(FATAL_ERROR "Unexpected framework VERSION: ${CORE_VERSION}")
endif()
if(NOT CORE_SOVERSION STREQUAL "0.5")
    message(FATAL_ERROR "Unexpected framework SOVERSION: ${CORE_SOVERSION}")
endif()
foreach(PUBLIC_HEADER IN ITEMS RPCS3Core.h RPCS3CoreStatus.h)
    string(FIND "${CORE_PUBLIC_HEADERS}" "${PUBLIC_HEADER}" HEADER_INDEX)
    if(HEADER_INDEX EQUAL -1)
        message(FATAL_ERROR "PUBLIC_HEADER omitted ${PUBLIC_HEADER}")
    endif()
endforeach()

file(WRITE "${CMAKE_BINARY_DIR}/composition-manifest.txt"
    "version=${CORE_VERSION}\n"
    "soversion=${CORE_SOVERSION}\n"
    "core_sources=${CORE_SOURCES}\n"
    "host_sources=${HOST_SOURCES}\n"
    "rtmidi_sources=${RTMIDI_SOURCES}\n"
    "public_headers=${CORE_PUBLIC_HEADERS}\n")
EOF

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0

SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang++ \
    -std=c++23 \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    -target arm64-apple-ios16.0-simulator \
    -isysroot "${SDKROOT}" \
    -I"${ROOT}/rpcs3/ios" \
    -fsyntax-only \
    "${BUILD_DIR}/ios-generated/CoreLinkMainSafe.mm"

test -s "${BUILD_DIR}/composition-manifest.txt"
cat "${BUILD_DIR}/composition-manifest.txt"
echo "RPCS3 iOS CMake composition contract passed."
