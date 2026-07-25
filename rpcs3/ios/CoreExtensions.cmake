# Additional Qt-free RPCS3Core.framework modules kept separate from generated
# upstream source adaptations. This file is included after PatchCoreSources.cmake
# has created the framework target.

if(NOT RPCS3_IOS)
    return()
endif()

if(TARGET rpcs3_ios_core_framework)
    target_sources(rpcs3_ios_core_framework PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLibrary.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.cpp")
endif()
