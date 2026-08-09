# iOS-only build adjustments that need to be applied after RPCS3's targets exist.
# This is loaded by the iOS presets through CMAKE_PROJECT_rpcs3_INCLUDE and
# deferred until the top-level directory has finished defining subdirectories.

function(rpcs3_ios_apply_runtime_overrides)
    if(NOT RPCS3_IOS)
        return()
    endif()

    # vm_native.cpp still contains the macOS ARM64 decommit implementation,
    # which unmaps a JIT reservation and relies on a non-fixed mmap hint to get
    # the same virtual address back. On iOS that is unsafe for MAP_JIT regions.
    # Rename the platform implementation in this translation unit and install
    # a narrow iOS wrapper that preserves live JIT reservations.
    set(rpcs3_ios_vm_compile_definitions
        "memory_decommit=memory_decommit_platform")
    if(RPCS3_IOS_STIKDEBUG)
        list(APPEND rpcs3_ios_vm_compile_definitions RPCS3_IOS_STIKDEBUG=1)
    endif()
    set_source_files_properties(
        "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native.cpp"
        TARGET_DIRECTORY rpcs3_emu
        PROPERTIES COMPILE_DEFINITIONS "${rpcs3_ios_vm_compile_definitions}")

    # Route only JITASM.cpp's Apple callback call through a diagnostic wrapper.
    # The allowed callback functions themselves remain in JITASM.cpp, so the
    # PTHREAD_JIT_WRITE_ALLOW_CALLBACKS_NP image allowlist is unchanged.
    set_source_files_properties(
        "${CMAKE_SOURCE_DIR}/Utilities/JITASM.cpp"
        TARGET_DIRECTORY rpcs3_emu
        PROPERTIES COMPILE_DEFINITIONS
            "pthread_jit_write_with_callback_np=rpcs3_ios_pthread_jit_write_with_callback_np")

    target_sources(rpcs3_emu PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native_ios.cpp"
        "${CMAKE_SOURCE_DIR}/Utilities/JIT_iOS.cpp")

    if(RPCS3_IOS_STIKDEBUG)
        set_source_files_properties(
            "${CMAKE_SOURCE_DIR}/Utilities/JIT_iOS.cpp"
            TARGET_DIRECTORY rpcs3_emu
            PROPERTIES COMPILE_DEFINITIONS "RPCS3_IOS_STIKDEBUG=1")
        set_source_files_properties(
            "${CMAKE_SOURCE_DIR}/rpcs3/main.cpp"
            TARGET_DIRECTORY rpcs3
            PROPERTIES COMPILE_DEFINITIONS "RPCS3_IOS_STIKDEBUG=1")
    endif()

    # JIT_iOS.cpp protects failure-path log flushing with catch-all handling.
    # rpcs3_emu disables exceptions by default, so opt this diagnostic wrapper
    # back in just as yaml.cpp does for its exception-aware implementation.
    set_source_files_properties(
        "${CMAKE_SOURCE_DIR}/Utilities/JIT_iOS.cpp"
        TARGET_DIRECTORY rpcs3_emu
        PROPERTIES COMPILE_FLAGS "-fexceptions")

    # The iOS process-wide terminate handler inspects and rethrows the active
    # exception to preserve its type and message in the fatal report.
    set_source_files_properties(
        "${CMAKE_SOURCE_DIR}/rpcs3/main.cpp"
        TARGET_DIRECTORY rpcs3
        PROPERTIES COMPILE_FLAGS "-fexceptions")
endfunction()

cmake_language(DEFER CALL rpcs3_ios_apply_runtime_overrides)
