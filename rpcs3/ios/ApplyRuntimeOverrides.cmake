# Apply the narrow runtime overrides that vPhone proved necessary after the
# bootstrap source generator has replaced vm_native.cpp with its iOS-adapted
# generated copy. These keep bootstrap's framework architecture while matching
# the proven iPhone JIT lifetime semantics.

if(NOT RPCS3_IOS OR NOT TARGET rpcs3_emu)
    return()
endif()

set(_rpcs3_ios_generated_vm "${CMAKE_CURRENT_BINARY_DIR}/ios-generated/vm_native_ios.cpp")
if(NOT EXISTS "${_rpcs3_ios_generated_vm}")
    message(FATAL_ERROR "The generated iOS vm_native source must exist before runtime overrides are applied")
endif()

# Preserve the generated platform implementation under a private name and let
# vm_native_ios.cpp own the public memory_decommit symbol. JIT regions remain
# mapped on iPhone instead of inheriting macOS's unsafe unmap/remap-by-hint path.
set_source_files_properties(
    "${_rpcs3_ios_generated_vm}"
    TARGET_DIRECTORY rpcs3_emu
    PROPERTIES COMPILE_DEFINITIONS "memory_decommit=memory_decommit_platform")

# Route only JITASM's callback invocation through a diagnostic wrapper. The
# callback functions themselves stay in JITASM.cpp, so Apple's callback
# allow-list remains attached to the same image functions.
set_source_files_properties(
    "${CMAKE_SOURCE_DIR}/Utilities/JITASM.cpp"
    TARGET_DIRECTORY rpcs3_emu
    PROPERTIES COMPILE_DEFINITIONS
        "pthread_jit_write_with_callback_np=rpcs3_ios_pthread_jit_write_with_callback_np")

target_sources(rpcs3_emu PRIVATE
    "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native_ios.cpp"
    "${CMAKE_SOURCE_DIR}/Utilities/JIT_iOS.cpp")
