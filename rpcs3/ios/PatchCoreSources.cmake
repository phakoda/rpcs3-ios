# Apply narrowly scoped iOS source adaptations while leaving shared desktop
# sources unchanged. Generated files retain the upstream source as their base
# and fail configuration if an expected anchor moves.

set(_ios_generated_dir "${CMAKE_CURRENT_BINARY_DIR}/ios-generated")
file(MAKE_DIRECTORY "${_ios_generated_dir}")

# Utilities/File.cpp treats every Apple bundle as a macOS .app whose executable
# lives under Contents/MacOS. iOS executables live directly inside the .app, so
# resource discovery must stop after one parent directory.
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

# Qt creates UIApplication while constructing gui_application. Initialize the
# native platform layer immediately after that application object exists rather
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
    "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSRuntimeIntegration.h")

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
