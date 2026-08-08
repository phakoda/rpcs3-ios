cmake_minimum_required(VERSION 3.28)

find_program(CCACHE_PATH ccache HINTS ENV PATH)
if(CCACHE_PATH)
  message(STATUS "Using ccache: ${CCACHE_PATH}")
  set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PATH}")
  set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PATH}")
endif()

project(rpcs3 LANGUAGES C CXX)

set(RPCS3_IOS OFF)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RPCS3_IOS ON)

    if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
        message(FATAL_ERROR "The initial RPCS3 iOS port supports arm64 only. Set CMAKE_OSX_ARCHITECTURES=arm64.")
    endif()

    if(CMAKE_OSX_SYSROOT MATCHES "([Ii]Phone)?[Ss]imulator")
        set(RPCS3_IOS_PLATFORM "simulator")
        set(RPCS3_IOS_SUPPORTED_PLATFORM "iPhoneSimulator")
    elseif(CMAKE_OSX_SYSROOT MATCHES "([Ii]Phone)?[Oo][Ss]")
        set(RPCS3_IOS_PLATFORM "device")
        set(RPCS3_IOS_SUPPORTED_PLATFORM "iPhoneOS")
    else()
        message(FATAL_ERROR
            "RPCS3 iOS builds require CMAKE_OSX_SYSROOT=iphoneos or iphonesimulator; got '${CMAKE_OSX_SYSROOT}'.")
    endif()

    # Never use packages from the host user's CMake package registry while
    # cross-compiling. Target dependency prefixes may still be supplied
    # explicitly with CMAKE_PREFIX_PATH.
    set(CMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY ON)
    set(CMAKE_FIND_USE_PACKAGE_REGISTRY OFF)
    set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY OFF)

    list(FILTER CMAKE_PREFIX_PATH EXCLUDE REGEX "^(/opt/homebrew|/usr/local)(/|$)")
    list(FILTER CMAKE_SYSTEM_PREFIX_PATH EXCLUDE REGEX "^(/opt/homebrew|/usr/local)(/|$)")

    set(RPCS3_IOS_PKG_CONFIG_LIBDIR "" CACHE PATH
        "Target pkg-config directory for iOS dependencies (empty disables pkg-config package discovery)")
    if(RPCS3_IOS_PKG_CONFIG_LIBDIR)
        set(ENV{PKG_CONFIG_LIBDIR} "${RPCS3_IOS_PKG_CONFIG_LIBDIR}")
    else()
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/empty-pkgconfig")
        set(ENV{PKG_CONFIG_LIBDIR} "${CMAKE_BINARY_DIR}/empty-pkgconfig")
    endif()
    set(ENV{PKG_CONFIG_PATH} "")

    message(STATUS "RPCS3: configuring iOS ${RPCS3_IOS_PLATFORM} for arm64 (${CMAKE_OSX_SYSROOT})")
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 13)
        message(FATAL_ERROR "RPCS3 requires at least gcc-13.")
    endif()
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19.0)
        message(FATAL_ERROR "RPCS3 requires at least clang-19.0.")
    endif()
endif()

if(APPLE OR WIN32)
    set(USE_SYSTEM_OPENAL_DEFAULT OFF)
else()
    set(USE_SYSTEM_OPENAL_DEFAULT ON)
endif()

set(USE_NATIVE_INSTRUCTIONS_DEFAULT ON)
set(WITH_LLVM_DEFAULT ON)
set(USE_FAUDIO_DEFAULT ON)
set(USE_LIBEVDEV_DEFAULT ON)
set(USE_VULKAN_DEFAULT ON)
set(USE_SDL_DEFAULT ON)
set(USE_SYSTEM_CURL_DEFAULT ON)
set(USE_SYSTEM_OPENAL_PLATFORM_DEFAULT ${USE_SYSTEM_OPENAL_DEFAULT})
set(USE_SYSTEM_OPENCV_DEFAULT ON)
set(USE_LTO_DEFAULT ON)
set(USE_GAMEMODE_DEFAULT ON)

if(RPCS3_IOS)
    # These defaults form a conservative cross-build baseline. Features can
    # be opted back in once target libraries are supplied explicitly.
    set(USE_NATIVE_INSTRUCTIONS_DEFAULT OFF)
    set(WITH_LLVM_DEFAULT OFF)
    set(USE_FAUDIO_DEFAULT OFF)
    set(USE_LIBEVDEV_DEFAULT OFF)
    set(USE_VULKAN_DEFAULT OFF)
    set(USE_SDL_DEFAULT OFF)
    set(USE_SYSTEM_CURL_DEFAULT OFF)
    set(USE_SYSTEM_OPENAL_PLATFORM_DEFAULT OFF)
    set(USE_SYSTEM_OPENCV_DEFAULT OFF)
    set(USE_LTO_DEFAULT OFF)
    set(USE_GAMEMODE_DEFAULT OFF)
endif()

option(USE_NATIVE_INSTRUCTIONS "USE_NATIVE_INSTRUCTIONS makes rpcs3 compile with -march=native, which is useful for local builds, but not good for packages." ${USE_NATIVE_INSTRUCTIONS_DEFAULT})
option(WITH_LLVM "Enable usage of LLVM library" ${WITH_LLVM_DEFAULT})
option(BUILD_LLVM "Build LLVM from git submodule" OFF)
option(STATIC_LINK_LLVM "Link against LLVM statically. This will get set to ON if you build LLVM from the submodule." OFF)
option(USE_FAUDIO "FAudio audio backend" ${USE_FAUDIO_DEFAULT})
option(USE_LIBEVDEV "libevdev-based joystick support" ${USE_LIBEVDEV_DEFAULT})
option(USE_DISCORD_RPC "Discord rich presence integration" OFF)
option(USE_VULKAN "Vulkan render backend" ${USE_VULKAN_DEFAULT})
option(USE_PRECOMPILED_HEADERS "Use precompiled headers" OFF)
option(USE_SDL "Enables SDL input handler" ${USE_SDL_DEFAULT})
option(USE_SYSTEM_CUBEB "Prefer system cubeb instead of the builtin one" OFF)
option(USE_SYSTEM_CURL "Prefer system Curl instead of the prebuild one" ${USE_SYSTEM_CURL_DEFAULT})
option(USE_SYSTEM_FAUDIO "Prefer system FAudio instead of the builtin one" OFF)
option(USE_SYSTEM_FFMPEG "Prefer system ffmpeg instead of the prebuild one" OFF)
option(USE_SYSTEM_PROTOBUF "Prefer system protobuf instead of the builtin one" OFF)
option(USE_SYSTEM_GLSLANG "Prefer system glslang instead of the builtin one" OFF)
option(USE_SYSTEM_HIDAPI "Prefer system hidapi instead of the builtin one" OFF)
option(USE_SYSTEM_LIBPNG "Prefer system libpng instead of the builtin one" OFF)
option(USE_SYSTEM_LIBUSB "Prefer system libusb instead of the builtin one" OFF)
option(USE_SYSTEM_MINIUPNPC "Prefer system MiniUPnPc instead of the builtin one" OFF)
option(USE_SYSTEM_MVK "Prefer system MoltenVK instead of the builtin one" OFF)
option(USE_SYSTEM_OPENAL "Prefer system OpenAL instead of the prebuild one" ${USE_SYSTEM_OPENAL_PLATFORM_DEFAULT})
option(USE_SYSTEM_OPENCV "Prefer system OpenCV instead of the builtin one" ${USE_SYSTEM_OPENCV_DEFAULT})
option(USE_SYSTEM_PUGIXML "Prefer system pugixml instead of the builtin one" OFF)
option(USE_SYSTEM_RTMIDI "Prefer system RtMidi instead of the builtin one" OFF)
option(USE_SYSTEM_SDL "Prefer system SDL instead of the builtin one" ON)
option(USE_SYSTEM_VULKAN_MEMORY_ALLOCATOR "Prefer system Vulkan Memory Allocator instead of the builtin one" OFF)
option(USE_SYSTEM_WOLFSSL "Prefer system wolfSSL instead of the builtin one" OFF)
option(USE_SYSTEM_ZLIB "Prefer system ZLIB instead of the builtin one" ON)
option(USE_SYSTEM_ZSTD "Prefer system zstd instead of the builtin one" OFF)
option(HAS_MEMORY_BREAKPOINTS "Add support for memory breakpoints to the interpreter" OFF)
option(USE_LTO "Use LTO for building" ${USE_LTO_DEFAULT})
option(BUILD_RPCS3_TESTS "Build RPCS3 unit tests." OFF)
option(RUN_RPCS3_TESTS "Run RPCS3 unit tests. Requires BUILD_RPCS3_TESTS" OFF)
option(USE_GAMEMODE "Choose whether to enable GameMode features or not." ${USE_GAMEMODE_DEFAULT})

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/buildfiles/cmake")

include(CheckCXXCompilerFlag)

get_property(IS_MULTI_CONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTI_CONFIG)
    # TODO(cjj19970505@live.cn)
    # Currently DicordRPC is included as a binary compiled with /MT flag.
    # We need all 4 binaries(/MT /MTd /MD /MDd) or including the source instead of binary.
    set(USE_DISCORD_RPC OFF CACHE BOOL "Discord RPC is only avaliable with single-config generator" FORCE)
else()
    if(NOT CMAKE_BUILD_TYPE)
        message(STATUS "No build type selected, default to Release")
        set(CMAKE_BUILD_TYPE "Release")
    endif()
endif()

if(CMAKE_BUILD_TYPE MATCHES "Debug" AND NOT MSVC)
    add_compile_definitions(_DEBUG)
endif()

if(MSVC)
    add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:/MP>")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "RPCS3 can only be compiled on 64-bit platforms.")
endif()

if(APPLE AND NOT RPCS3_IOS AND CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    list(APPEND CMAKE_PREFIX_PATH "/opt/homebrew")
    list(APPEND CMAKE_SYSTEM_PREFIX_PATH "/opt/homebrew")
endif()

if(MSVC)
    add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:/wd4530;/utf-8>") # C++ exception handler used, but unwind semantics are not enabled
endif()

add_subdirectory(3rdparty)

if (DISABLE_LTO)
    if (CMAKE_C_FLAGS)
        string(REGEX REPLACE "-flto[^ ]*" "" CMAKE_C_FLAGS ${CMAKE_C_FLAGS})
    endif()
    if (CMAKE_CXX_FLAGS)
        string(REGEX REPLACE "-flto[^ ]*" "" CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS})
    endif()
endif()

string(FIND "${CMAKE_C_FLAGS} ${CMAKE_CXX_FLAGS}" "-flto" FOUND_LTO)
if (NOT FOUND_LTO EQUAL -1)
    message(FATAL_ERROR "RPCS3 doesn't support building with LTO, use -DDISABLE_LTO=TRUE to force-disable it")
endif()

## Look for Gamemode if its installed on Linux
if(LINUX)
    ## User chooses whether to Enable GameMode features or not
    if(USE_GAMEMODE)
         add_compile_definitions(GAMEMODE_AVAILABLE)
    endif()
endif()

# TODO: do real installation, including copying directory structure
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${PROJECT_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG "${PROJECT_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${PROJECT_BINARY_DIR}/bin")

if(BUILD_RPCS3_TESTS)
    enable_testing()
endif()
add_subdirectory(rpcs3)

set_directory_properties(PROPERTIES VS_STARTUP_PROJECT rpcs3)
