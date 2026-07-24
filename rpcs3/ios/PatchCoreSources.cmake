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
