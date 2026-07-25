# Additional Qt-free RPCS3Core.framework modules kept separate from generated
# upstream source adaptations. This file is included after PatchCoreSources.cmake
# has created the framework target.

if(NOT RPCS3_IOS)
    return()
endif()

if(TARGET rpcs3_ios_core_framework)
    set(_rpcs3_ios_core_callbacks "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.mm")
    set(_rpcs3_ios_core_emulator "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEmulator.mm")

    # Compile broad implementations under private base names. Small composition
    # units then install contract-specific behavior without rewriting the larger
    # emulator and UIKit callback translation units.
    set_source_files_properties("${_rpcs3_ios_core_callbacks}" PROPERTIES
        COMPILE_DEFINITIONS "extend_core_callbacks=extend_core_callbacks_base")
    set_source_files_properties("${_rpcs3_ios_core_emulator}" PROPERTIES
        COMPILE_DEFINITIONS "rpcs3_ios_core_set_event_callback=rpcs3_ios_core_set_event_callback_base")

    target_sources(rpcs3_ios_core_framework PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.h"
        "${_rpcs3_ios_core_callbacks}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacksComposite.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEventCallback.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreImageCallbacks.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreImageCallbacks.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSaveDialog.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSaveDialog.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLibrary.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.cpp")
endif()
