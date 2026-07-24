if(NOT RPCS3_IOS)
    message(FATAL_ERROR "rpcs3_ios_platform is only available for iOS targets")
endif()

find_library(IOS_PLATFORM_UIKIT UIKit REQUIRED)
find_library(IOS_PLATFORM_FOUNDATION Foundation REQUIRED)
find_library(IOS_PLATFORM_AVFOUNDATION AVFoundation REQUIRED)
find_library(IOS_PLATFORM_GAMECONTROLLER GameController REQUIRED)
find_library(IOS_PLATFORM_SECURITY Security REQUIRED)
find_library(IOS_PLATFORM_UNIFORMTYPES UniformTypeIdentifiers REQUIRED)

add_library(rpcs3_ios_platform STATIC
    IOSPlatform.mm
    IOSJIT.mm
    IOSPerformance.mm
    IOSTouchController.mm
    IOSVirtualController.cpp
)

target_compile_features(rpcs3_ios_platform PUBLIC cxx_std_20)
target_include_directories(rpcs3_ios_platform PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(rpcs3_ios_platform PUBLIC
    "${IOS_PLATFORM_UIKIT}"
    "${IOS_PLATFORM_FOUNDATION}"
    "${IOS_PLATFORM_AVFOUNDATION}"
    "${IOS_PLATFORM_GAMECONTROLLER}"
    "${IOS_PLATFORM_SECURITY}"
    "${IOS_PLATFORM_UNIFORMTYPES}"
)

set_target_properties(rpcs3_ios_platform PROPERTIES
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
)
