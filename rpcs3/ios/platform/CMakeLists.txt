if(NOT RPCS3_IOS)
    message(FATAL_ERROR "rpcs3_ios_platform is only available for iOS targets")
endif()

find_library(IOS_PLATFORM_UIKIT UIKit REQUIRED)
find_library(IOS_PLATFORM_FOUNDATION Foundation REQUIRED)
find_library(IOS_PLATFORM_AVFOUNDATION AVFoundation REQUIRED)
find_library(IOS_PLATFORM_GAMECONTROLLER GameController REQUIRED)
find_library(IOS_PLATFORM_COREHAPTICS CoreHaptics REQUIRED)
find_library(IOS_PLATFORM_COREMOTION CoreMotion REQUIRED)
find_library(IOS_PLATFORM_METAL Metal REQUIRED)
find_library(IOS_PLATFORM_SECURITY Security REQUIRED)
find_library(IOS_PLATFORM_UNIFORMTYPES UniformTypeIdentifiers REQUIRED)

set(_rpcs3_ios_platform_objcxx_sources
    IOSPlatform.mm
    IOSJIT.mm
    IOSJITProvider.mm
    IOSPerformance.mm
    IOSControllerFeatures.mm
    IOSControllerLight.mm
    IOSExternalDisplay.mm
    IOSMoltenVK.mm
    IOSDiagnostics.mm
    IOSTouchController.mm)

add_library(rpcs3_ios_platform STATIC
    ${_rpcs3_ios_platform_objcxx_sources}
    IOSVirtualController.cpp
)

# Xcode maps C++ and Objective-C++ warning settings through the same build
# setting in places, so a COMPILE_LANGUAGE generator expression is not enough
# to keep -Werror=old-style-cast away from UIKit/Foundation bridge idioms.
# Relax only this style warning on concrete .mm sources; RPCS3's C++ core keeps
# the strict warning policy.
set_source_files_properties(${_rpcs3_ios_platform_objcxx_sources} PROPERTIES
    COMPILE_OPTIONS "-Wno-error=old-style-cast")

target_compile_features(rpcs3_ios_platform PUBLIC cxx_std_20)
target_include_directories(rpcs3_ios_platform PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(rpcs3_ios_platform PUBLIC
    "${IOS_PLATFORM_UIKIT}"
    "${IOS_PLATFORM_FOUNDATION}"
    "${IOS_PLATFORM_AVFOUNDATION}"
    "${IOS_PLATFORM_GAMECONTROLLER}"
    "${IOS_PLATFORM_COREHAPTICS}"
    "${IOS_PLATFORM_COREMOTION}"
    "${IOS_PLATFORM_METAL}"
    "${IOS_PLATFORM_SECURITY}"
    "${IOS_PLATFORM_UNIFORMTYPES}"
)

set_target_properties(rpcs3_ios_platform PROPERTIES
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
)
