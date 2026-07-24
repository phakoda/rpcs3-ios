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
option(RPCS3_IOS_ENABLE_LLVM "Enable LLVM PPU/SPU recompilers for iOS after JIT signing is validated" OFF)
set(RPCS3_IOS_ENTITLEMENTS_FILE "" CACHE FILEPATH "Custom entitlements for a supported iOS signing environment")
set(RPCS3_IOS_FFMPEG_ROOT "" CACHE PATH "Root of a static FFmpeg build for the selected iOS SDK")
set(RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES "" CACHE STRING "Additional libraries required by the selected static FFmpeg build")

if(RPCS3_IOS_ENTITLEMENTS_FILE AND NOT EXISTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
    message(FATAL_ERROR "RPCS3_IOS_ENTITLEMENTS_FILE does not exist: ${RPCS3_IOS_ENTITLEMENTS_FILE}")
endif()
if(RPCS3_IOS_ENABLE_LLVM AND NOT RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS AND NOT RPCS3_IOS_ENTITLEMENTS_FILE)
    message(WARNING "LLVM was enabled without an entitlement profile. Interpreter fallback may still be required at runtime.")
endif()

set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)
set(CMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING YES)

add_compile_definitions(RPCS3_IOS=1)

# Desktop defaults such as -march=native and host package discovery are not
# valid while cross-compiling for an iPhone or iPad.
set(USE_NATIVE_INSTRUCTIONS OFF CACHE BOOL "Disabled for iOS cross-compilation" FORCE)
set(USE_LIBEVDEV OFF CACHE BOOL "libevdev is unavailable on iOS" FORCE)
set(USE_DISCORD_RPC OFF CACHE BOOL "Discord RPC is unavailable on iOS" FORCE)
set(USE_GAMEMODE OFF CACHE BOOL "GameMode is unavailable on iOS" FORCE)
set(USE_FAUDIO OFF CACHE BOOL "FAudio is disabled for the initial iOS port" FORCE)
set(USE_SDL OFF CACHE BOOL "SDL input is replaced by GameController on iOS" FORCE)
set(USE_VULKAN ON CACHE BOOL "MoltenVK is the supported iOS renderer" FORCE)
set(USE_SYSTEM_MVK ON CACHE BOOL "Use an explicitly supplied iOS MoltenVK build" FORCE)
set(USE_SYSTEM_FFMPEG ON CACHE BOOL "Use an explicitly supplied iOS FFmpeg build" FORCE)
set(USE_SYSTEM_CURL OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)
set(USE_SYSTEM_OPENCV OFF CACHE BOOL "OpenCV is disabled for the initial iOS port" FORCE)
set(USE_SYSTEM_SDL OFF CACHE BOOL "Do not search the macOS host while cross-compiling" FORCE)
set(USE_SYSTEM_ZLIB OFF CACHE BOOL "Use the bundled cross-compiled zlib" FORCE)
set(USE_LTO OFF CACHE BOOL "Disable LTO while bringing up the iOS target" FORCE)
set(BUILD_LLVM OFF CACHE BOOL "Do not attempt a native LLVM submodule build while cross-compiling" FORCE)
set(STATIC_LINK_LLVM ON CACHE BOOL "iOS does not permit a separately loaded LLVM dylib" FORCE)
set(WITH_LLVM ${RPCS3_IOS_ENABLE_LLVM} CACHE BOOL "LLVM recompilers require validated iOS JIT signing" FORCE)

message(STATUS "RPCS3 iOS target enabled")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  Architectures: ${CMAKE_OSX_ARCHITECTURES}")
message(STATUS "  Deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
message(STATUS "  Bootstrap only: ${RPCS3_IOS_BOOTSTRAP_ONLY}")
message(STATUS "  LLVM/JIT enabled: ${RPCS3_IOS_ENABLE_LLVM}")
message(STATUS "  Entitlements: ${RPCS3_IOS_ENTITLEMENTS_FILE}")
