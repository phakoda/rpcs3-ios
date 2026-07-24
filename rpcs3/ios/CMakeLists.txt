if(NOT RPCS3_IOS)
    message(FATAL_ERROR "The iOS bootstrap target requires -DCMAKE_SYSTEM_NAME=iOS")
endif()

add_subdirectory(platform)

set(Vulkan_INCLUDE_DIR "" CACHE PATH "Directory containing vulkan/vulkan.h from the MoltenVK distribution")
set(Vulkan_LIBRARY "" CACHE FILEPATH "Path to the iOS or iOS Simulator MoltenVK library")

if(NOT EXISTS "${Vulkan_INCLUDE_DIR}/vulkan/vulkan.h")
    message(FATAL_ERROR
        "Vulkan_INCLUDE_DIR must point to the MoltenVK include directory containing vulkan/vulkan.h")
endif()

if(NOT EXISTS "${Vulkan_LIBRARY}")
    message(FATAL_ERROR
        "Vulkan_LIBRARY must point to a MoltenVK library built for the selected iOS SDK and architecture")
endif()

find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(IOSURFACE_FRAMEWORK IOSurface REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(COREVIDEO_FRAMEWORK CoreVideo REQUIRED)

add_executable(rpcs3_ios_bootstrap MACOSX_BUNDLE
    main.mm
)

target_compile_features(rpcs3_ios_bootstrap PRIVATE cxx_std_20)
target_compile_definitions(rpcs3_ios_bootstrap PRIVATE VK_USE_PLATFORM_METAL_EXT=1)
target_include_directories(rpcs3_ios_bootstrap PRIVATE "${Vulkan_INCLUDE_DIR}")
target_link_options(rpcs3_ios_bootstrap PRIVATE "-ObjC")
target_link_libraries(rpcs3_ios_bootstrap PRIVATE
    rpcs3_ios_platform
    "${Vulkan_LIBRARY}"
    "${QUARTZCORE_FRAMEWORK}"
    "${METAL_FRAMEWORK}"
    "${IOSURFACE_FRAMEWORK}"
    "${COREGRAPHICS_FRAMEWORK}"
    "${COREVIDEO_FRAMEWORK}"
)

set_target_properties(rpcs3_ios_bootstrap PROPERTIES
    OUTPUT_NAME "RPCS3 iOS"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "net.rpcs3.ios.bootstrap"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
    XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
    XCODE_ATTRIBUTE_SKIP_INSTALL "NO"
)

if(RPCS3_IOS_ENTITLEMENTS_FILE)
    set_target_properties(rpcs3_ios_bootstrap PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
elseif(RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS)
    set_target_properties(rpcs3_ios_bootstrap PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/JIT.entitlements")
endif()
