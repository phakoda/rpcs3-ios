# Apply narrowly scoped iOS source adaptations while leaving shared desktop
# sources unchanged. Generated files retain the upstream source as their base
# and fail configuration if an expected anchor moves.

set(_ios_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/ios-generated")
file(MAKE_DIRECTORY "${_ios_generated_dir}")

# Utilities/File.cpp treats every Apple bundle as a macOS .app whose executable
# lives under Contents/MacOS. iOS executables live directly inside the .app, so
# resource discovery must stop after one parent directory.
if(TARGET rpcs3_emu)
    set(_file_source "${CMAKE_SOURCE_DIR}/Utilities/File.cpp")
    set(_file_generated "${_ios_generated_dir}/File_ios.cpp")
    file(READ "${_file_source}" _file_contents)

    set(_bundle_anchor "\t\t// App bundle directory is three levels up from the binary.\n\t\treturn get_parent_dir(bin_path, 3);")
    set(_bundle_replacement "#ifdef RPCS3_IOS\n\t\t// iOS places the executable directly in the application bundle.\n\t\treturn get_parent_dir(bin_path);\n#else\n\t\t// macOS places the executable under Contents/MacOS.\n\t\treturn get_parent_dir(bin_path, 3);\n#endif")
    string(REPLACE "${_bundle_anchor}" "${_bundle_replacement}" _file_contents "${_file_contents}")

    if(NOT _file_contents MATCHES "iOS places the executable directly")
        message(FATAL_ERROR "Could not apply the iOS application-bundle path adaptation to Utilities/File.cpp")
    endif()

    file(WRITE "${_file_generated}" "${_file_contents}")
    get_target_property(_rpcs3_emu_sources rpcs3_emu SOURCES)
    list(FILTER _rpcs3_emu_sources EXCLUDE REGEX "Utilities/File\\.cpp$")
    set_property(TARGET rpcs3_emu PROPERTY SOURCES "${_rpcs3_emu_sources}")
    target_sources(rpcs3_emu PRIVATE "${_file_generated}")

    # Apple arm64 uses thread-local write protection for MAP_JIT mappings. RPCS3
    # already marks code-generation regions as WX while publishing and RX before
    # execution. Preserve those semantics and pair the transitions with Apple's
    # pthread JIT API and an instruction-cache flush.
    set(_vm_source "${CMAKE_SOURCE_DIR}/rpcs3/util/vm_native.cpp")
    set(_vm_generated "${_ios_generated_dir}/vm_native_ios.cpp")
    file(READ "${_vm_source}" _vm_contents)

    set(_vm_include_anchor "#include \"util/asm.hpp\"")
    set(_vm_include_replacement "#include \"util/asm.hpp\"\n#include \"ios/platform/IOSPlatform.h\"")
    string(REPLACE "${_vm_include_anchor}" "${_vm_include_replacement}" _vm_contents "${_vm_contents}")

    set(_mprotect_anchor "\t\tconst u64 ptr64 = reinterpret_cast<u64>(pointer);\n\t\tensure(::mprotect(reinterpret_cast<void*>(ptr64 & -get_page_size()), size + (ptr64 & (get_page_size() - 1)), +prot) != -1);")
    set(_mprotect_replacement "\t\tconst u64 ptr64 = reinterpret_cast<u64>(pointer);\n#ifdef RPCS3_IOS\n\t\tif (prot == protection::wx)\n\t\t{\n\t\t\trpcs3::ios::set_jit_write_protection(false);\n\t\t}\n#endif\n\t\tensure(::mprotect(reinterpret_cast<void*>(ptr64 & -get_page_size()), size + (ptr64 & (get_page_size() - 1)), +prot) != -1);\n#ifdef RPCS3_IOS\n\t\tif (prot == protection::rx)\n\t\t{\n\t\t\t__builtin___clear_cache(static_cast<char*>(pointer), static_cast<char*>(pointer) + size);\n\t\t\trpcs3::ios::set_jit_write_protection(true);\n\t\t}\n#endif")
    string(REPLACE "${_mprotect_anchor}" "${_mprotect_replacement}" _vm_contents "${_vm_contents}")

    set(_reset_anchor "#if defined(__APPLE__) && defined(ARCH_ARM64)\n\t\tensure(::munmap(pointer, size) != -1);\n\t\tensure(::mmap(pointer, size, +prot,  MAP_ANON | MAP_PRIVATE | (can_be_jit ? MAP_JIT : 0), -1, 0) == pointer);")
    set(_reset_replacement "#if defined(__APPLE__) && defined(ARCH_ARM64)\n#ifdef RPCS3_IOS\n\t\tif (can_be_jit && prot == protection::wx)\n\t\t{\n\t\t\trpcs3::ios::set_jit_write_protection(false);\n\t\t}\n#endif\n\t\tensure(::munmap(pointer, size) != -1);\n\t\tensure(::mmap(pointer, size, +prot,  MAP_ANON | MAP_PRIVATE | (can_be_jit ? MAP_JIT : 0), -1, 0) == pointer);\n#ifdef RPCS3_IOS\n\t\tif (can_be_jit && prot == protection::rx)\n\t\t{\n\t\t\t__builtin___clear_cache(static_cast<char*>(pointer), static_cast<char*>(pointer) + size);\n\t\t\trpcs3::ios::set_jit_write_protection(true);\n\t\t}\n#endif")
    string(REPLACE "${_reset_anchor}" "${_reset_replacement}" _vm_contents "${_vm_contents}")

    if(NOT _vm_contents MATCHES "set_jit_write_protection\\(false\\)" OR
       NOT _vm_contents MATCHES "__builtin___clear_cache" OR
       NOT _vm_contents MATCHES "set_jit_write_protection\\(true\\)")
        message(FATAL_ERROR "Could not apply iOS JIT write-protection adaptations to vm_native.cpp")
    endif()

    file(WRITE "${_vm_generated}" "${_vm_contents}")
    get_target_property(_rpcs3_emu_sources rpcs3_emu SOURCES)
    list(FILTER _rpcs3_emu_sources EXCLUDE REGEX "(^|/)util/vm_native\\.cpp$")
    set_property(TARGET rpcs3_emu PROPERTY SOURCES "${_rpcs3_emu_sources}")
    target_sources(rpcs3_emu PRIVATE "${_vm_generated}")
endif()

# Generate a Qt-free gameplay pad thread for RPCS3Core.framework. The upstream
# pad thread's core state and USB/LDD behavior are retained, unsupported desktop
# HID factories resolve to NullPadHandler, keyboard-window code is compiled out,
# and the native GameController implementation is inserted explicitly.
set(_core_pad_source "${CMAKE_SOURCE_DIR}/rpcs3/Input/pad_thread.cpp")
set(_core_pad_generated "${_ios_generated_dir}/pad_thread_ios_core.cpp")
file(READ "${_core_pad_source}" _core_pad_contents)
foreach(_include IN ITEMS
    "#include \"ds3_pad_handler.h\"\n"
    "#include \"ds4_pad_handler.h\"\n"
    "#include \"dualsense_pad_handler.h\"\n"
    "#include \"skateboard_pad_handler.h\"\n"
    "#include \"ps_move_handler.h\"\n")
    string(REPLACE "${_include}" "" _core_pad_contents "${_core_pad_contents}")
endforeach()
string(REPLACE "#include \"Emu/Io/Null/NullPadHandler.h\""
    "#include \"Emu/Io/Null/NullPadHandler.h\"\n#include \"ios_gamecontroller_pad_handler.h\""
    _core_pad_contents "${_core_pad_contents}")
string(REPLACE "#ifndef ANDROID"
    "#if !defined(ANDROID) && !defined(RPCS3_IOS_CORE)"
    _core_pad_contents "${_core_pad_contents}")
foreach(_handler IN ITEMS ds3 ds4 dualsense skateboard move)
    if(_handler STREQUAL "ds3")
        set(_class ds3_pad_handler)
    elseif(_handler STREQUAL "ds4")
        set(_class ds4_pad_handler)
    elseif(_handler STREQUAL "dualsense")
        set(_class dualsense_pad_handler)
    elseif(_handler STREQUAL "skateboard")
        set(_class skateboard_pad_handler)
    else()
        set(_class ps_move_handler)
    endif()
    string(REPLACE
        "\tcase pad_handler::${_handler}:\n\t\treturn std::make_shared<${_class}>();"
        "\tcase pad_handler::${_handler}:\n\t\treturn std::make_shared<NullPadHandler>();"
        _core_pad_contents "${_core_pad_contents}")
endforeach()
string(REPLACE
    "\tcase pad_handler::move:\n\t\treturn std::make_shared<NullPadHandler>();"
    "\tcase pad_handler::move:\n\t\treturn std::make_shared<NullPadHandler>();\n\tcase pad_handler::ios_gamecontroller:\n\t\treturn std::make_shared<ios_gamecontroller_pad_handler>();"
    _core_pad_contents "${_core_pad_contents}")
if(NOT _core_pad_contents MATCHES "case pad_handler::ios_gamecontroller" OR
   _core_pad_contents MATCHES "std::make_shared<ds3_pad_handler>")
    message(FATAL_ERROR "Could not generate the Qt-free iOS core pad thread")
endif()
file(WRITE "${_core_pad_generated}" "${_core_pad_contents}")

# Build the adapted core in three forms:
#
# 1. rpcs3_ios_core_archive is a reusable static archive milestone.
# 2. RPCS3Core.framework force-loads every rpcs3_emu object and resolves the
#    complete dependency/framework closure behind a stable C ABI.
# 3. RPCS3 iOS Core.app imports only that public C ABI, proving a consumer can
#    link the framework without reaching into RPCS3 internals.
if(TARGET rpcs3_ios_core AND TARGET rpcs3_emu AND NOT TARGET rpcs3_ios_core_framework)
    set(_rpcs3_core_modulemap "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.modulemap")
    add_library(rpcs3_ios_core_framework SHARED
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.exports"
        "${_rpcs3_core_modulemap}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreDefaults.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreDefaults.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEmulator.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreEmulator.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreGSFrame.mm"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreGSFrame.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLifecycle.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreLifecycle.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreMouseGyro.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/CoreAnchor.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/rpcs3_version.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/rpcs3_version.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/Input/product_info.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/Input/ios_gamecontroller_pad_handler.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/Input/ios_gamecontroller_pad_handler.h"
        "${_core_pad_generated}")
    set_source_files_properties("${_rpcs3_core_modulemap}" PROPERTIES
        MACOSX_PACKAGE_LOCATION Modules)
    target_compile_features(rpcs3_ios_core_framework PRIVATE cxx_std_23)
    target_compile_definitions(rpcs3_ios_core_framework PRIVATE RPCS3_IOS_CORE=1)
    target_include_directories(rpcs3_ios_core_framework
        PUBLIC "${CMAKE_SOURCE_DIR}/rpcs3/ios"
        PRIVATE
            "${CMAKE_SOURCE_DIR}/rpcs3"
            "${CMAKE_SOURCE_DIR}/rpcs3/Input")
    target_link_options(rpcs3_ios_core_framework PRIVATE
        "-ObjC"
        "LINKER:-exported_symbols_list,${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.exports")
    target_link_libraries(rpcs3_ios_core_framework PRIVATE
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,rpcs3_emu>"
        rpcs3_ios_platform
        3rdparty::vulkan
        3rdparty::ios_system)
    set_target_properties(rpcs3_ios_core_framework PROPERTIES
        OUTPUT_NAME "RPCS3Core"
        FRAMEWORK TRUE
        FRAMEWORK_VERSION A
        VERSION 0.2.0
        SOVERSION 0.2
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
        PUBLIC_HEADER "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core.h"
        MACOSX_FRAMEWORK_IDENTIFIER "net.rpcs3.ios.core"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/rpcs3/ios/RPCS3Core-Info.plist.in"
        XCODE_ATTRIBUTE_CLANG_ENABLE_MODULES YES
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
        XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING NO
        XCODE_ATTRIBUTE_DEFINES_MODULE YES
        XCODE_ATTRIBUTE_ENABLE_BITCODE NO
        XCODE_ATTRIBUTE_LD_GENERATE_MAP_FILE YES
        XCODE_ATTRIBUTE_LD_MAP_FILE_PATH "$(TARGET_TEMP_DIR)/$(PRODUCT_NAME)-LinkMap-$(CURRENT_ARCH).txt"
        XCODE_ATTRIBUTE_MODULEMAP_FILE "${_rpcs3_core_modulemap}"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "net.rpcs3.ios.core"
        XCODE_ATTRIBUTE_SKIP_INSTALL NO)

    add_executable(rpcs3_ios_core_link MACOSX_BUNDLE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/CoreLinkMain.mm")
    target_compile_features(rpcs3_ios_core_link PRIVATE cxx_std_23)
    target_include_directories(rpcs3_ios_core_link PRIVATE
        "${CMAKE_SOURCE_DIR}/rpcs3/ios")
    target_link_options(rpcs3_ios_core_link PRIVATE "-ObjC")
    target_link_libraries(rpcs3_ios_core_link PRIVATE
        rpcs3_ios_core_framework
        3rdparty::ios_system)
    set_target_properties(rpcs3_ios_core_link PROPERTIES
        OUTPUT_NAME "RPCS3 iOS Core"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/rpcs3/ios/Info.plist.in"
        XCODE_EMBED_FRAMEWORKS "$<TARGET_BUNDLE_DIR:rpcs3_ios_core_framework>"
        XCODE_EMBED_FRAMEWORKS_CODE_SIGN_ON_COPY YES
        XCODE_EMBED_FRAMEWORKS_REMOVE_HEADERS_ON_COPY YES
        XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "net.rpcs3.ios.core.link"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
        XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
        XCODE_ATTRIBUTE_ENABLE_BITCODE NO
        XCODE_ATTRIBUTE_SKIP_INSTALL NO)

    if(RPCS3_IOS_ENTITLEMENTS_FILE)
        set_target_properties(rpcs3_ios_core_link PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
    elseif(RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS)
        set_target_properties(rpcs3_ios_core_link PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/rpcs3/ios/JIT.entitlements")
    endif()

    add_dependencies(rpcs3_ios_core
        rpcs3_ios_core_framework
        rpcs3_ios_core_link)
endif()

if(TARGET rpcs3_ui)
    # Qt creates UIApplication while constructing gui_application. Initialize
    # native services immediately after that application object exists rather
    # than from main(), where UIKit services are not ready yet.
    set(_frontend_source "${CMAKE_SOURCE_DIR}/rpcs3/rpcs3.cpp")
    set(_frontend_generated "${_ios_generated_dir}/rpcs3_ios.cpp")
    file(READ "${_frontend_source}" _frontend_contents)

    set(_frontend_include_anchor "#include \"Emu/savestate_utils.hpp\"")
    set(_frontend_include_replacement "#include \"Emu/savestate_utils.hpp\"\n#include \"ios/IOSRuntimeIntegration.h\"")
    string(REPLACE "${_frontend_include_anchor}" "${_frontend_include_replacement}" _frontend_contents "${_frontend_contents}")

    set(_frontend_init_anchor "\tapp->setOrganizationName(\"RPCS3\");")
    set(_frontend_init_replacement "\tapp->setOrganizationName(\"RPCS3\");\n\trpcs3::ios::initialize_rpcs3_runtime();")
    string(REPLACE "${_frontend_init_anchor}" "${_frontend_init_replacement}" _frontend_contents "${_frontend_contents}")

    if(NOT _frontend_contents MATCHES "initialize_rpcs3_runtime")
        message(FATAL_ERROR "Could not inject iOS runtime initialization into rpcs3.cpp")
    endif()

    file(WRITE "${_frontend_generated}" "${_frontend_contents}")
    get_target_property(_rpcs3_ui_sources rpcs3_ui SOURCES)
    list(FILTER _rpcs3_ui_sources EXCLUDE REGEX "(^|/)rpcs3\\.cpp$")
    set_property(TARGET rpcs3_ui PROPERTY SOURCES "${_rpcs3_ui_sources}")
    target_sources(rpcs3_ui PRIVATE
        "${_frontend_generated}"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSRuntimeIntegration.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSRuntimeIntegration.h"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreDefaults.cpp"
        "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreDefaults.h")

    # Add the native touch controller above the Metal-backed Qt game view. The
    # overlay feeds the same iOS pad handler as hardware GameController devices.
    set(_gs_frame_source "${CMAKE_SOURCE_DIR}/rpcs3/rpcs3qt/gs_frame.cpp")
    set(_gs_frame_generated "${_ios_generated_dir}/gs_frame_ios.cpp")
    file(READ "${_gs_frame_source}" _gs_frame_contents)

    set(_gs_include_anchor "#include \"Input/pad_thread.h\"")
    set(_gs_include_replacement "#include \"Input/pad_thread.h\"\n#include \"ios/platform/IOSPlatform.h\"")
    string(REPLACE "${_gs_include_anchor}" "${_gs_include_replacement}" _gs_frame_contents "${_gs_frame_contents}")

    set(_gs_attach_anchor "\tload_gui_settings();")
    set(_gs_attach_replacement "\tload_gui_settings();\n\trpcs3::ios::attach_touch_controller_overlay(handle());")
    string(REPLACE "${_gs_attach_anchor}" "${_gs_attach_replacement}" _gs_frame_contents "${_gs_frame_contents}")

    set(_gs_detach_anchor "gs_frame::~gs_frame()\n{")
    set(_gs_detach_replacement "gs_frame::~gs_frame()\n{\n\trpcs3::ios::detach_touch_controller_overlay(handle());")
    string(REPLACE "${_gs_detach_anchor}" "${_gs_detach_replacement}" _gs_frame_contents "${_gs_frame_contents}")

    if(NOT _gs_frame_contents MATCHES "attach_touch_controller_overlay" OR NOT _gs_frame_contents MATCHES "detach_touch_controller_overlay")
        message(FATAL_ERROR "Could not attach the iOS touch controller to gs_frame.cpp")
    endif()

    file(WRITE "${_gs_frame_generated}" "${_gs_frame_contents}")
    get_target_property(_rpcs3_ui_sources rpcs3_ui SOURCES)
    list(FILTER _rpcs3_ui_sources EXCLUDE REGEX "(^|/)gs_frame\\.cpp$")
    set_property(TARGET rpcs3_ui PROPERTY SOURCES "${_rpcs3_ui_sources}")
    target_sources(rpcs3_ui PRIVATE "${_gs_frame_generated}")
endif()
