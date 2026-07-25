# Additional Qt-free RPCS3Core.framework modules kept separate from generated
# upstream source adaptations. This file is included after PatchCoreSources.cmake
# has created the framework and management-host targets.

if(NOT RPCS3_IOS)
    return()
endif()

if(TARGET rpcs3_ios_core_framework)
    set(_rpcs3_ios_core_callbacks "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.mm")
    set(_rpcs3_ios_core_emulator "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEmulator.mm")
    set(_rpcs3_ios_core_installer "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.cpp")

    # Compile broad implementations under private base names. Small composition
    # units then install contract-specific behavior without rewriting the larger
    # emulator, installer, and UIKit callback translation units.
    set_source_files_properties("${_rpcs3_ios_core_callbacks}" PROPERTIES
        COMPILE_DEFINITIONS "extend_core_callbacks=extend_core_callbacks_base")
    set_source_files_properties("${_rpcs3_ios_core_emulator}" PROPERTIES
        COMPILE_DEFINITIONS "rpcs3_ios_core_set_event_callback=rpcs3_ios_core_set_event_callback_base")
    set_source_files_properties("${_rpcs3_ios_core_installer}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_install_firmware=rpcs3_ios_core_install_firmware_base;rpcs3_ios_core_install_package=rpcs3_ios_core_install_package_base;rpcs3_ios_core_request_installation_cancel=rpcs3_ios_core_request_installation_cancel_base")

    target_sources(rpcs3_ios_core_framework PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.h"
        "${_rpcs3_ios_core_callbacks}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacksComposite.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEventCallback.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreFallbackCallbacks.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreFallbackCallbacks.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreImageCallbacks.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreImageCallbacks.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSaveDialog.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSaveDialog.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMIDI.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMIDI.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLibrary.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.h"
        "${_rpcs3_ios_core_installer}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstallationStatus.cpp")

    # PatchCoreSources creates the framework target. Keep the public ABI version
    # override next to the extension modules that define the 0.4 surface.
    set_target_properties(rpcs3_ios_core_framework PROPERTIES
        VERSION 0.4.0
        SOVERSION 0.4)
endif()

include("${CMAKE_SOURCE_DIR}/rpcs3/ios/PatchCoreHost.cmake")
