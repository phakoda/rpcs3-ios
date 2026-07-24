# iOS dependency selection for the RPCS3 core and full application targets.
#
# Desktop-only backends are represented by empty interface targets so their
# feature macros remain disabled. Required cross-built dependencies fail early
# with actionable paths instead of accidentally linking macOS host libraries.

include(CheckCXXCompilerFlag)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static dependencies for iOS" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "Disable dependency tests while cross-compiling" FORCE)

include("${CMAKE_CURRENT_LIST_DIR}/DetectArchitecture.cmake")

if(NOT TARGET 3rdparty_dummy_lib)
    add_library(3rdparty_dummy_lib INTERFACE)
endif()

function(rpcs3_ios_add_subdirectory name)
    add_subdirectory(
        "${CMAKE_CURRENT_LIST_DIR}/${name}"
        "${CMAKE_BINARY_DIR}/3rdparty/${name}"
        EXCLUDE_FROM_ALL)
endfunction()

# Prevent bundled dependencies from producing target executables, examples,
# tests, documentation, installers, or shared libraries during an iOS build.
set(protobuf_INSTALL OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_CONFORMANCE OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_PROTOC_BINARIES OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_LIBPROTOC OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_LIBUPB OFF CACHE BOOL "" FORCE)
set(protobuf_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
set(ENABLE_SPVREMAPPER OFF CACHE BOOL "" FORCE)
set(ENABLE_CTEST OFF CACHE BOOL "" FORCE)
set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)
set(CURL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUILD_RUST_LIBS OFF CACHE BOOL "" FORCE)
set(WOLFSSL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WOLFSSL_CRYPT_TESTS OFF CACHE BOOL "" FORCE)
set(UPNPC_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(UPNPC_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(UPNPC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(UPNPC_BUILD_SAMPLE OFF CACHE BOOL "" FORCE)

# Portable foundational libraries.
rpcs3_ios_add_subdirectory(zlib)
rpcs3_ios_add_subdirectory(zstd)
rpcs3_ios_add_subdirectory(7zip)
rpcs3_ios_add_subdirectory(protobuf)
rpcs3_ios_add_subdirectory(libpng)
rpcs3_ios_add_subdirectory(pugixml)
rpcs3_ios_add_subdirectory(glslang)
rpcs3_ios_add_subdirectory(yaml-cpp)
rpcs3_ios_add_subdirectory(stblib)
rpcs3_ios_add_subdirectory(cubeb)
rpcs3_ios_add_subdirectory(SoundTouch)
rpcs3_ios_add_subdirectory(asmjit)
rpcs3_ios_add_subdirectory(llvm)
rpcs3_ios_add_subdirectory(wolfssl)
rpcs3_ios_add_subdirectory(curl)
rpcs3_ios_add_subdirectory(miniupnpc)
rpcs3_ios_add_subdirectory(fusion)
rpcs3_ios_add_subdirectory(feralinteractive)

# Public Apple frameworks and system libraries required by the complete core
# graph. Keeping them on one interface target makes static final links stable
# and prevents individual dependencies from accidentally resolving macOS SDK
# variants on the host.
find_library(RPCS3_IOS_ACCELERATE Accelerate REQUIRED)
find_library(RPCS3_IOS_AUDIOTOOLBOX AudioToolbox REQUIRED)
find_library(RPCS3_IOS_AUDIOUNIT AudioUnit REQUIRED)
find_library(RPCS3_IOS_AVFOUNDATION AVFoundation REQUIRED)
find_library(RPCS3_IOS_CFNETWORK CFNetwork REQUIRED)
find_library(RPCS3_IOS_COREAUDIO CoreAudio REQUIRED)
find_library(RPCS3_IOS_COREFOUNDATION CoreFoundation REQUIRED)
find_library(RPCS3_IOS_COREGRAPHICS CoreGraphics REQUIRED)
find_library(RPCS3_IOS_COREHAPTICS CoreHaptics REQUIRED)
find_library(RPCS3_IOS_COREMEDIA CoreMedia REQUIRED)
find_library(RPCS3_IOS_COREMOTION CoreMotion REQUIRED)
find_library(RPCS3_IOS_COREVIDEO CoreVideo REQUIRED)
find_library(RPCS3_IOS_FOUNDATION Foundation REQUIRED)
find_library(RPCS3_IOS_GAMECONTROLLER GameController REQUIRED)
find_library(RPCS3_IOS_IOSURFACE IOSurface REQUIRED)
find_library(RPCS3_IOS_METAL Metal REQUIRED)
find_library(RPCS3_IOS_NETWORK Network REQUIRED)
find_library(RPCS3_IOS_QUARTZCORE QuartzCore REQUIRED)
find_library(RPCS3_IOS_SECURITY Security REQUIRED)
find_library(RPCS3_IOS_SYSTEMCONFIGURATION SystemConfiguration REQUIRED)
find_library(RPCS3_IOS_UIKIT UIKit REQUIRED)
find_library(RPCS3_IOS_UNIFORMTYPES UniformTypeIdentifiers REQUIRED)
find_library(RPCS3_IOS_VIDEOTOOLBOX VideoToolbox REQUIRED)
find_library(RPCS3_IOS_ICONV iconv REQUIRED)
find_library(RPCS3_IOS_RESOLV resolv REQUIRED)
find_library(RPCS3_IOS_BZ2 bz2)

add_library(3rdparty_ios_system INTERFACE)
target_link_libraries(3rdparty_ios_system INTERFACE
    "${RPCS3_IOS_ACCELERATE}"
    "${RPCS3_IOS_AUDIOTOOLBOX}"
    "${RPCS3_IOS_AUDIOUNIT}"
    "${RPCS3_IOS_AVFOUNDATION}"
    "${RPCS3_IOS_CFNETWORK}"
    "${RPCS3_IOS_COREAUDIO}"
    "${RPCS3_IOS_COREFOUNDATION}"
    "${RPCS3_IOS_COREGRAPHICS}"
    "${RPCS3_IOS_COREHAPTICS}"
    "${RPCS3_IOS_COREMEDIA}"
    "${RPCS3_IOS_COREMOTION}"
    "${RPCS3_IOS_COREVIDEO}"
    "${RPCS3_IOS_FOUNDATION}"
    "${RPCS3_IOS_GAMECONTROLLER}"
    "${RPCS3_IOS_IOSURFACE}"
    "${RPCS3_IOS_METAL}"
    "${RPCS3_IOS_NETWORK}"
    "${RPCS3_IOS_QUARTZCORE}"
    "${RPCS3_IOS_SECURITY}"
    "${RPCS3_IOS_SYSTEMCONFIGURATION}"
    "${RPCS3_IOS_UIKIT}"
    "${RPCS3_IOS_UNIFORMTYPES}"
    "${RPCS3_IOS_VIDEOTOOLBOX}"
    "${RPCS3_IOS_ICONV}"
    "${RPCS3_IOS_RESOLV}")
if(RPCS3_IOS_BZ2)
    target_link_libraries(3rdparty_ios_system INTERFACE "${RPCS3_IOS_BZ2}")
endif()
add_library(3rdparty::ios_system ALIAS 3rdparty_ios_system)

# Vulkan through a user-provided MoltenVK distribution.
if(NOT EXISTS "${Vulkan_INCLUDE_DIR}/vulkan/vulkan.h")
    message(FATAL_ERROR
        "Core/full iOS builds require Vulkan_INCLUDE_DIR to contain vulkan/vulkan.h")
endif()
if(NOT EXISTS "${Vulkan_LIBRARY}")
    message(FATAL_ERROR
        "Core/full iOS builds require Vulkan_LIBRARY to point to an iOS MoltenVK library")
endif()

if(NOT TARGET Vulkan::Vulkan)
    add_library(Vulkan::Vulkan UNKNOWN IMPORTED GLOBAL)
    set_target_properties(Vulkan::Vulkan PROPERTIES
        IMPORTED_LOCATION "${Vulkan_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${Vulkan_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "3rdparty_ios_system")
endif()

add_library(3rdparty_vulkan INTERFACE)
target_compile_definitions(3rdparty_vulkan INTERFACE HAVE_VULKAN VK_USE_PLATFORM_METAL_EXT=1)
target_link_libraries(3rdparty_vulkan INTERFACE Vulkan::Vulkan)

# OpenGL is unavailable on modern iOS. RPCS3 must use Vulkan/MoltenVK.
add_library(3rdparty_opengl INTERFACE)
target_compile_definitions(3rdparty_opengl INTERFACE WITHOUT_OPENGL=1)
add_library(3rdparty_glew INTERFACE)

# FFmpeg must be cross-built for the selected SDK. Expected layout:
#   <root>/include/libavcodec/avcodec.h
#   <root>/lib/libavcodec.a (and companion libraries)
if(NOT EXISTS "${RPCS3_IOS_FFMPEG_ROOT}/include/libavcodec/avcodec.h")
    message(FATAL_ERROR
        "Core/full iOS builds require RPCS3_IOS_FFMPEG_ROOT with FFmpeg headers and static libraries")
endif()

set(_rpcs3_ios_ffmpeg_libdir "${RPCS3_IOS_FFMPEG_ROOT}/lib")
find_library(RPCS3_IOS_AVFORMAT NAMES avformat PATHS "${_rpcs3_ios_ffmpeg_libdir}" NO_DEFAULT_PATH REQUIRED)
find_library(RPCS3_IOS_AVCODEC NAMES avcodec PATHS "${_rpcs3_ios_ffmpeg_libdir}" NO_DEFAULT_PATH REQUIRED)
find_library(RPCS3_IOS_AVUTIL NAMES avutil PATHS "${_rpcs3_ios_ffmpeg_libdir}" NO_DEFAULT_PATH REQUIRED)
find_library(RPCS3_IOS_SWSCALE NAMES swscale PATHS "${_rpcs3_ios_ffmpeg_libdir}" NO_DEFAULT_PATH REQUIRED)
find_library(RPCS3_IOS_SWRESAMPLE NAMES swresample PATHS "${_rpcs3_ios_ffmpeg_libdir}" NO_DEFAULT_PATH REQUIRED)

set(_rpcs3_ios_ffmpeg_platform_libraries
    3rdparty_ios_system
    3rdparty_zlib)
if(RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES)
    list(APPEND _rpcs3_ios_ffmpeg_platform_libraries ${RPCS3_IOS_FFMPEG_EXTRA_LIBRARIES})
endif()

add_library(3rdparty_ffmpeg INTERFACE)
target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE "${RPCS3_IOS_FFMPEG_ROOT}/include")
target_link_libraries(3rdparty_ffmpeg INTERFACE
    "${RPCS3_IOS_AVFORMAT}"
    "${RPCS3_IOS_AVCODEC}"
    "${RPCS3_IOS_SWSCALE}"
    "${RPCS3_IOS_SWRESAMPLE}"
    "${RPCS3_IOS_AVUTIL}"
    ${_rpcs3_ios_ffmpeg_platform_libraries})

# Unsupported desktop/peripheral integrations. Keeping these as interface
# targets lets the core compile its feature-disabled paths without pulling in
# macOS host packages or unsupported device APIs.
add_library(3rdparty_discordRPC INTERFACE)
add_library(3rdparty_libevdev INTERFACE)
add_library(3rdparty_hidapi INTERFACE)
add_library(3rdparty_libusb INTERFACE)
add_library(3rdparty_openal INTERFACE)
target_compile_definitions(3rdparty_openal INTERFACE WITHOUT_OPENAL=1)
add_library(3rdparty_faudio INTERFACE)
add_library(3rdparty_sdl3 INTERFACE)
add_library(3rdparty_opencv INTERFACE)
add_library(3rdparty_rtmidi INTERFACE)

# Vulkan Memory Allocator is header-only.
add_library(3rdparty_vulkanmemoryallocator INTERFACE)
target_include_directories(3rdparty_vulkanmemoryallocator SYSTEM INTERFACE
    "${CMAKE_CURRENT_LIST_DIR}/GPUOpen/VulkanMemoryAllocator/include")

# Stable aliases used throughout RPCS3.
add_library(3rdparty::zlib ALIAS 3rdparty_zlib)
add_library(3rdparty::zstd ALIAS 3rdparty_zstd)
add_library(3rdparty::7zip ALIAS 3rdparty_7zip)
add_library(3rdparty::protobuf ALIAS 3rdparty_protobuf)
add_library(3rdparty::pugixml ALIAS pugixml)
add_library(3rdparty::glslang ALIAS 3rdparty_glslang)
add_library(3rdparty::yaml-cpp ALIAS yaml-cpp)
add_library(3rdparty::libpng ALIAS ${LIBPNG_TARGET})
add_library(3rdparty::opengl ALIAS 3rdparty_opengl)
add_library(3rdparty::stblib ALIAS 3rdparty_stblib)
add_library(3rdparty::discordRPC ALIAS 3rdparty_discordRPC)
add_library(3rdparty::faudio ALIAS 3rdparty_faudio)
add_library(3rdparty::libevdev ALIAS 3rdparty_libevdev)
add_library(3rdparty::vulkan ALIAS 3rdparty_vulkan)
add_library(3rdparty::vulkanmemoryallocator ALIAS 3rdparty_vulkanmemoryallocator)
add_library(3rdparty::openal ALIAS 3rdparty_openal)
add_library(3rdparty::ffmpeg ALIAS 3rdparty_ffmpeg)
add_library(3rdparty::glew ALIAS 3rdparty_glew)
add_library(3rdparty::wolfssl ALIAS wolfssl)
add_library(3rdparty::libcurl ALIAS 3rdparty_libcurl)
add_library(3rdparty::soundtouch ALIAS soundtouch)
add_library(3rdparty::sdl3 ALIAS 3rdparty_sdl3)
add_library(3rdparty::miniupnpc ALIAS 3rdparty_miniupnpc)
add_library(3rdparty::rtmidi ALIAS 3rdparty_rtmidi)
add_library(3rdparty::opencv ALIAS 3rdparty_opencv)
add_library(3rdparty::fusion ALIAS Fusion)
add_library(3rdparty::feralinteractive ALIAS 3rdparty_feralinteractive)
add_library(3rdparty::hidapi ALIAS 3rdparty_hidapi)
add_library(3rdparty::libusb ALIAS 3rdparty_libusb)

message(STATUS "RPCS3: configured final-link-complete iOS third-party dependencies")
