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

# PatchCoreSources relocates Utilities/File.cpp into ios-generated so its
# sibling includes (File.h, mutex.h, StrFmt.h, and future local headers) no
# longer resolve from the source file's original directory. Restore that one
# upstream include root for the iOS core target instead of rewriting each
# generated include independently.
target_include_directories(rpcs3_emu PRIVATE
    "${CMAKE_SOURCE_DIR}/Utilities")

# PatchCoreSources also generates a Qt-free pad_thread.cpp. Upstream now wraps
# keyboard_pad_handler in Android guards and moved NullPadHandler under Emu/Io,
# so the original narrow replacements leave keyboard/QThread/QWindow references
# behind and miss the native iOS handler include. Normalize those remnants in
# the already-generated translation unit without changing shared desktop code.
set(_rpcs3_ios_pad_thread
    "${CMAKE_CURRENT_BINARY_DIR}/ios-generated/pad_thread_ios_core.cpp")
if(NOT EXISTS "${_rpcs3_ios_pad_thread}")
    message(FATAL_ERROR "The generated Qt-free iOS pad thread must exist before runtime overrides are applied")
endif()
file(READ "${_rpcs3_ios_pad_thread}" _rpcs3_ios_pad_thread_contents)
string(REPLACE
    "#include \"Emu/Io/Null/NullPadHandler.h\""
    "#include \"Emu/Io/Null/NullPadHandler.h\"\n#include \"ios_gamecontroller_pad_handler.h\""
    _rpcs3_ios_pad_thread_contents "${_rpcs3_ios_pad_thread_contents}")
string(REPLACE
    "keyboard_pad_handler"
    "NullPadHandler"
    _rpcs3_ios_pad_thread_contents "${_rpcs3_ios_pad_thread_contents}")
string(REPLACE
    "\t\t\t\tkeyptr->moveToThread(static_cast<QThread*>(m_curthread));\n"
    ""
    _rpcs3_ios_pad_thread_contents "${_rpcs3_ios_pad_thread_contents}")
string(REPLACE
    "\t\t\t\tkeyptr->SetTargetWindow(static_cast<QWindow*>(m_curwindow));\n"
    ""
    _rpcs3_ios_pad_thread_contents "${_rpcs3_ios_pad_thread_contents}")

if(_rpcs3_ios_pad_thread_contents MATCHES "keyboard_pad_handler" OR
   _rpcs3_ios_pad_thread_contents MATCHES "QThread" OR
   _rpcs3_ios_pad_thread_contents MATCHES "QWindow" OR
   NOT _rpcs3_ios_pad_thread_contents MATCHES "#include \"ios_gamecontroller_pad_handler.h\"" OR
   NOT _rpcs3_ios_pad_thread_contents MATCHES "case pad_handler::ios_gamecontroller")
    message(FATAL_ERROR "Could not finish the Qt-free iOS pad-thread adaptation")
endif()
file(WRITE "${_rpcs3_ios_pad_thread}" "${_rpcs3_ios_pad_thread_contents}")

# The native GameController source has a private axis_direction(value, sign)
# helper. Current RPCS3 pad headers also expose an axis_direction type, making
# the unqualified helper calls ambiguous under Apple Clang. Keep the shared
# source untouched and generate the iOS framework translation unit with only
# that private helper renamed; controller scaling and mappings are unchanged.
if(TARGET rpcs3_ios_core_framework)
    set(_rpcs3_ios_controller_source
        "${CMAKE_SOURCE_DIR}/rpcs3/Input/ios_gamecontroller_pad_handler.cpp")
    set(_rpcs3_ios_controller_generated
        "${CMAKE_CURRENT_BINARY_DIR}/ios-generated/ios_gamecontroller_pad_handler.cpp")
    file(READ "${_rpcs3_ios_controller_source}" _rpcs3_ios_controller_contents)
    string(REPLACE
        "u16 axis_direction(float value, bool positive)"
        "u16 ios_axis_button_value(float value, bool positive)"
        _rpcs3_ios_controller_contents "${_rpcs3_ios_controller_contents}")
    string(REPLACE
        "axis_direction(state."
        "ios_axis_button_value(state."
        _rpcs3_ios_controller_contents "${_rpcs3_ios_controller_contents}")

    if(NOT _rpcs3_ios_controller_contents MATCHES "u16 ios_axis_button_value\\(float value, bool positive\\)" OR
       _rpcs3_ios_controller_contents MATCHES "axis_direction\\(state\\.")
        message(FATAL_ERROR "Could not apply the iOS GameController axis helper rename")
    endif()

    file(WRITE "${_rpcs3_ios_controller_generated}" "${_rpcs3_ios_controller_contents}")
    get_target_property(_rpcs3_ios_framework_sources rpcs3_ios_core_framework SOURCES)
    list(FILTER _rpcs3_ios_framework_sources EXCLUDE REGEX
        "rpcs3/Input/ios_gamecontroller_pad_handler\\.cpp$")
    set_property(TARGET rpcs3_ios_core_framework PROPERTY SOURCES
        "${_rpcs3_ios_framework_sources}")
    target_sources(rpcs3_ios_core_framework PRIVATE
        "${_rpcs3_ios_controller_generated}")
endif()

# OpenAL capture is intentionally disabled for the native iOS core, but
# cellMic keeps a few ALC types and its error formatter in always-compiled
# code. Export only the iOS null-backend compatibility header to this target;
# desktop OpenAL include resolution remains untouched.
target_include_directories(rpcs3_emu SYSTEM PRIVATE
    "${CMAKE_SOURCE_DIR}/3rdparty/ios/openal")

# configure.sh exposes one entitlement switch for every iOS mode. Apply it to
# the real Qt-free RPCS3Core management host as well as the small bootstrap
# target so core-mode device builds can be signed for the callback-JIT runtime.
if(TARGET rpcs3_ios_core_link)
    if(RPCS3_IOS_ENTITLEMENTS_FILE)
        set_target_properties(rpcs3_ios_core_link PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
    elseif(RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS)
        set_target_properties(rpcs3_ios_core_link PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/rpcs3/ios/JIT.entitlements")
    endif()
endif()
