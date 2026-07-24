if(NOT APPLE OR NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "ConfigureIOS.cmake may only be used with -DCMAKE_SYSTEM_NAME=iOS")
endif()

# The Objective-C++ bridge is intentionally enabled only for iOS builds so the
# desktop toolchains remain unchanged.
enable_language(OBJCXX)

if(NOT CMAKE_GENERATOR STREQUAL "Xcode")
    message(WARNING "The RPCS3 iOS port is developed and tested with the Xcode generator")
endif()

if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS architectures" FORCE)
endif()

if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 16.0 CACHE STRING "Minimum supported iOS version" FORCE)
endif()

option(RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS "Apply development-only JIT entitlements to iOS application targets" OFF)

set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)

add_compile_definitions(RPCS3_IOS=1)

# Desktop defaults such as -march=native and host package discovery are not
# valid while cross-compiling for an iPhone or iPad.
set(USE_NATIVE_INSTRUCTIONS OFF CACHE BOOL "Disabled for iOS cross-compilation" FORCE)
set(USE_LIBEVDEV OFF CACHE BOOL "libevdev is unavailable on iOS" FORCE)
set(USE_DISCORD_RPC OFF CACHE BOOL "Discord RPC is unavailable on iOS" FORCE)
set(USE_GAMEMODE OFF CACHE BOOL "GameMode is unavailable on iOS" FORCE)
set(USE_SYSTEM_CURL OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)
set(USE_SYSTEM_OPENCV OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)
set(USE_SYSTEM_SDL OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)
set(USE_SYSTEM_ZLIB OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)

message(STATUS "RPCS3 iOS target enabled")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  Architectures: ${CMAKE_OSX_ARCHITECTURES}")
message(STATUS "  Deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
message(STATUS "  Bootstrap only: ${RPCS3_IOS_BOOTSTRAP_ONLY}")
