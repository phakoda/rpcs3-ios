if(RPCS3_IOS)
  # Upstream's generic APPLE branch adds the macOS-only CoreServices
  # framework. RtMidi itself has an iOS CoreMIDI implementation, so build
  # that source directly with only frameworks present in the iOS SDK.
  add_library(rtmidi STATIC
    rtmidi/RtMidi.cpp
    rtmidi/rtmidi_c.cpp)
  target_compile_definitions(rtmidi PRIVATE __MACOSX_CORE__ RTMIDI_EXPORT)
  target_include_directories(rtmidi PUBLIC rtmidi)
  target_link_libraries(rtmidi PRIVATE
    "-framework CoreAudio"
    "-framework CoreFoundation"
    "-framework CoreMIDI")
elseif(USE_SYSTEM_RTMIDI)
  message(STATUS "RPCS3: using shared RtMidi")
  pkg_check_modules(RtMidi REQUIRED IMPORTED_TARGET rtmidi>=6.0.0)
  add_library(rtmidi INTERFACE)
  target_link_libraries(rtmidi INTERFACE PkgConfig::RtMidi)
  target_include_directories(rtmidi SYSTEM INTERFACE PkgConfig::RtMidi)
else()
  option(RTMIDI_API_JACK "Compile with JACK support." OFF)
  option(RTMIDI_BUILD_TESTING "Build test programs" OFF)
  set(RTMIDI_TARGETNAME_UNINSTALL "uninstall-rpcs3-rtmidi")
  add_subdirectory(rtmidi EXCLUDE_FROM_ALL)
endif()
