# Additional Qt-free RPCS3Core.framework modules kept separate from generated
# upstream source adaptations. This file is included after PatchCoreSources.cmake
# has created the framework and management-host targets.

if(NOT RPCS3_IOS)
    return()
endif()

if(TARGET rpcs3_ios_core_framework)
    set(_rpcs3_ios_core_api "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.mm")
    set(_rpcs3_ios_core_callbacks "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreCallbacks.mm")
    set(_rpcs3_ios_core_emulator "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEmulator.mm")
    set(_rpcs3_ios_core_installer "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.cpp")
    set(_rpcs3_ios_core_library "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLibrary.mm")
    set(_rpcs3_ios_core_settings "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreSettings.mm")
    set(_rpcs3_ios_core_midi "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMIDI.mm")

    # Compile broad implementations under private base names. Small composition
    # units then install contract-specific behavior without rewriting the larger
    # emulator, installer, and UIKit callback translation units.
    set_source_files_properties("${_rpcs3_ios_core_api}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_initialize=rpcs3_ios_core_initialize_base;rpcs3_ios_core_shutdown=rpcs3_ios_core_shutdown_base;rpcs3_ios_core_set_render_view=rpcs3_ios_core_set_render_view_base;rpcs3_ios_core_clear_render_view=rpcs3_ios_core_clear_render_view_base")
    set_source_files_properties("${_rpcs3_ios_core_callbacks}" PROPERTIES
        COMPILE_DEFINITIONS "extend_core_callbacks=extend_core_callbacks_base")
    set_source_files_properties("${_rpcs3_ios_core_emulator}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_set_event_callback=rpcs3_ios_core_set_event_callback_base;rpcs3_ios_core_boot_path=rpcs3_ios_core_boot_path_base;rpcs3_ios_core_pause=rpcs3_ios_core_pause_base;rpcs3_ios_core_resume=rpcs3_ios_core_resume_base;rpcs3_ios_core_stop=rpcs3_ios_core_stop_base;rpcs3_ios_core_restart=rpcs3_ios_core_restart_base")
    set_source_files_properties("${_rpcs3_ios_core_installer}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_install_firmware=rpcs3_ios_core_install_firmware_base;rpcs3_ios_core_install_package=rpcs3_ios_core_install_package_base;rpcs3_ios_core_request_installation_cancel=rpcs3_ios_core_request_installation_cancel_base;rpcs3_ios_core_copy_last_installed_path=rpcs3_ios_core_copy_last_installed_path_base")
    set_source_files_properties("${_rpcs3_ios_core_library}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_add_game_directory=rpcs3_ios_core_add_game_directory_base;rpcs3_ios_core_remove_game_directory=rpcs3_ios_core_remove_game_directory_base;rpcs3_ios_core_rescan_game_directories=rpcs3_ios_core_rescan_game_directories_base;rpcs3_ios_core_prune_missing_game_directories=rpcs3_ios_core_prune_missing_game_directories_base;rpcs3_ios_core_clear_game_directories=rpcs3_ios_core_clear_game_directories_base;rpcs3_ios_core_add_game=rpcs3_ios_core_add_game_base;rpcs3_ios_core_remove_game=rpcs3_ios_core_remove_game_base")
    set_source_files_properties("${_rpcs3_ios_core_settings}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_set_configuration=rpcs3_ios_core_set_configuration_base;rpcs3_ios_core_reset_configuration=rpcs3_ios_core_reset_configuration_base")
    set_source_files_properties("${_rpcs3_ios_core_midi}" PROPERTIES
        COMPILE_DEFINITIONS
            "rpcs3_ios_core_set_midi_assignment=rpcs3_ios_core_set_midi_assignment_base;rpcs3_ios_core_clear_midi_assignment=rpcs3_ios_core_clear_midi_assignment_base;rpcs3_ios_core_clear_all_midi_assignments=rpcs3_ios_core_clear_all_midi_assignments_base")

    target_sources(rpcs3_ios_core_framework PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3CoreStatus.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreOperations.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreOperations.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreOperationAPI.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMutationAPI.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreStatusAPI.cpp"
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
        "${_rpcs3_ios_core_settings}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMIDI.h"
        "${_rpcs3_ios_core_midi}"
        "${_rpcs3_ios_core_library}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstaller.h"
        "${_rpcs3_ios_core_installer}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreInstallationStatus.cpp")

    # PatchCoreSources creates the framework target. Keep the public ABI version
    # override next to the extension modules that define the 0.5 surface.
    set_target_properties(rpcs3_ios_core_framework PROPERTIES
        VERSION 0.5.0
        SOVERSION 0.5
        PUBLIC_HEADER "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.h;${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3CoreStatus.h")
endif()

include("${CMAKE_SOURCE_DIR}/rpcs3/ios/PatchCoreHost.cmake")
