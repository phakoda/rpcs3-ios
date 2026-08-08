# iOS-only build adjustments that need to be applied after RPCS3's targets exist.
# This is loaded by the iOS presets through CMAKE_PROJECT_INCLUDE and deferred
# until the top-level directory has finished defining its subdirectories.

function(rpcs3_ios_apply_runtime_overrides)
    if(NOT RPCS3_IOS)
        return()
    endif()

    # vm_native.cpp still contains the macOS ARM64 decommit implementation,
    # which unmaps a JIT reservation and relies on a non-fixed mmap hint to get
    # the same virtual address back. On iOS that is unsafe for MAP_JIT regions.
    # Rename the platform implementation in this translation unit and install
    # a narrow iOS wrapper that preserves live JIT reservations.
    set_source_files_properties(
        "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native.cpp"
        TARGET_DIRECTORY rpcs3_emu
        PROPERTIES COMPILE_DEFINITIONS "memory_decommit=memory_decommit_platform")

    target_sources(rpcs3_emu PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native_ios.cpp")
endfunction()

cmake_language(DEFER CALL rpcs3_ios_apply_runtime_overrides)
