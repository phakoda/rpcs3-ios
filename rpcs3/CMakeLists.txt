# Define GNU standard installation directories
include(GNUInstallDirs)

# Generate git-version.h at build time.
include(${CMAKE_CURRENT_SOURCE_DIR}/git-version.cmake)

# Check for a sufficient compiler and set build options
include(ConfigureCompiler)
include(CheckFunctionExists)

set(CMAKE_CXX_STANDARD 23)

if(UNIX AND NOT APPLE AND NOT ANDROID)
    add_compile_definitions(DATADIR="${CMAKE_INSTALL_FULL_DATADIR}/rpcs3")
    # Optionally enable X11 for window management
    find_package(X11)
    if(X11_FOUND)
        add_compile_definitions(HAVE_X11)
    endif()
    find_package(Wayland)
    if(WAYLAND_FOUND)
        add_compile_definitions(HAVE_WAYLAND)
    endif()
endif()

if(NOT ANDROID AND (NOT RPCS3_IOS OR RPCS3_IOS_BUILD_QT_FRONTEND))
    # Qt
    # finds Qt libraries and setups custom commands for MOC and UIC
    # Must be done here because generated MOC and UIC targets cant
    # be found otherwise
    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)
endif()

if(RPCS3_IOS)
    add_subdirectory(ios/platform)
endif()

# Emulator core
add_subdirectory(Emu)

if(RPCS3_IOS)
    target_link_libraries(rpcs3_emu PUBLIC
        rpcs3_ios_platform
        3rdparty::ios_system)
endif()

gen_git_version(${CMAKE_CURRENT_SOURCE_DIR})

if(RPCS3_IOS AND NOT RPCS3_IOS_BUILD_QT_FRONTEND)
    # Keep an archive product for downstream embedding, but make the public core
    # milestone an actual iOS Mach-O link. Static archives can contain unresolved
    # references indefinitely; the force-loaded executable cannot.
    add_library(rpcs3_ios_core_archive STATIC ios/CoreAnchor.cpp)
    target_compile_features(rpcs3_ios_core_archive PRIVATE cxx_std_20)
    target_link_libraries(rpcs3_ios_core_archive PUBLIC
        rpcs3_emu
        rpcs3_ios_platform
        3rdparty::ios_system)
    set_target_properties(rpcs3_ios_core_archive PROPERTIES
        OUTPUT_NAME "rpcs3-ios-core"
        XCODE_ATTRIBUTE_SKIP_INSTALL YES)

    add_executable(rpcs3_ios_core ios/CoreLink.cpp)
    target_compile_features(rpcs3_ios_core PRIVATE cxx_std_20)
    target_link_libraries(rpcs3_ios_core PRIVATE
        rpcs3_ios_core_archive
        rpcs3_emu
        rpcs3_ios_platform
        3rdparty::ios_system)
    add_dependencies(rpcs3_ios_core rpcs3_emu)

    # Pull every rpcs3_emu object into the final link instead of only the members
    # referenced by CoreLink.cpp. This is the core link-completeness contract.
    target_link_options(rpcs3_ios_core PRIVATE
        "-ObjC"
        "-Wl,-force_load,$<TARGET_FILE:rpcs3_emu>")
    set_target_properties(rpcs3_ios_core PROPERTIES
        OUTPUT_NAME "rpcs3-ios-core-link"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
        XCODE_ATTRIBUTE_ENABLE_BITCODE NO
        XCODE_ATTRIBUTE_SKIP_INSTALL YES)
    return()
endif()

if (NOT ANDROID)
    add_subdirectory(rpcs3qt)
endif()

if (NOT ANDROID)
    # Build rpcs3_lib
    add_library(rpcs3_lib STATIC)

    if(WIN32)
        target_compile_definitions(rpcs3_lib PRIVATE UNICODE _UNICODE)
    endif()

    set_target_properties(rpcs3_lib
        PROPERTIES
            AUTOMOC ON
            AUTOUIC ON)

    target_link_libraries(rpcs3_lib
        PUBLIC
            3rdparty::stblib
            3rdparty::libevdev
            rpcs3_emu
        PRIVATE
            rpcs3_ui
            3rdparty::discordRPC
            3rdparty::qt6
            3rdparty::hidapi
            3rdparty::libusb
            3rdparty::wolfssl
            3rdparty::libcurl
            3rdparty::zlib
            3rdparty::opencv
            3rdparty::fusion)

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        #on some Linux distros shm_unlink and similar functions are in librt only
        target_link_libraries(rpcs3_lib PRIVATE rt)
    elseif(NOT WIN32 AND NOT CMAKE_CXX_FLAGS MATCHES "LIBICONV_PLUG")
        #it seems like glibc includes the iconv functions we use but other libc
        #implementations like the one on OSX don't seem implement them
        target_link_libraries(rpcs3_lib PRIVATE iconv)
    endif()

    # Unix display manager
    if(X11_FOUND)
        target_link_libraries(rpcs3_lib PRIVATE X11::X11 xkbcommon-x11)
    elseif(USE_VULKAN AND UNIX AND NOT WAYLAND_FOUND AND NOT APPLE AND NOT ANDROID)
        # Wayland has been checked in 3rdparty/CMakeLists.txt already.
        message(FATAL_ERROR "RPCS3 requires either X11 or Wayland (or both) for Vulkan.")
    endif()

    if(WIN32)
        target_link_libraries(rpcs3_lib PRIVATE ws2_32 Iphlpapi Winmm Psapi gdi32 setupapi)
    else()
        target_link_libraries(rpcs3_lib PRIVATE ${CMAKE_DL_LIBS})
    endif()

    if(USE_PRECOMPILED_HEADERS)
        target_precompile_headers(rpcs3_lib PRIVATE stdafx.h)
    endif()

    # Build rpcs3 executable
    add_executable(rpcs3 WIN32 MACOSX_BUNDLE)
    if(WIN32)
        target_sources(rpcs3 PRIVATE rpcs3.rc)
        target_compile_definitions(rpcs3 PRIVATE UNICODE _UNICODE)
    elseif(APPLE)
        if(RPCS3_IOS)
            set_target_properties(rpcs3
                PROPERTIES
                    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist.in"
                    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "net.rpcs3.ios"
                    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
                    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
                    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
                    XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
                    XCODE_ATTRIBUTE_SKIP_INSTALL "NO")
            target_link_options(rpcs3 PRIVATE "-ObjC")
            target_link_libraries(rpcs3 PRIVATE
                rpcs3_ios_platform
                3rdparty::ios_system
                "-framework QuartzCore"
                "-framework Metal"
                "-framework IOSurface"
                "-framework CoreGraphics"
                "-framework CoreVideo")
            if(RPCS3_IOS_ENTITLEMENTS_FILE)
                set_target_properties(rpcs3
                    PROPERTIES
                        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
            elseif(RPCS3_IOS_ENABLE_JIT_ENTITLEMENTS)
                set_target_properties(rpcs3
                    PROPERTIES
                        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/ios/JIT.entitlements")
            endif()
        else()
            target_sources(rpcs3 PRIVATE rpcs3.icns update_helper.sh)
            set_source_files_properties(update_helper.sh PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
            set_target_properties(rpcs3
                PROPERTIES
                    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.plist.in")
        endif()
    endif()

    target_sources(rpcs3
        PRIVATE
            main.cpp
    )

    target_link_libraries(rpcs3
        PRIVATE
            rpcs3_lib
    )

    if(USE_PRECOMPILED_HEADERS)
        target_precompile_headers(rpcs3 PRIVATE stdafx.h)
    endif()

    # Copy icons to executable directory
    if(APPLE)
        qt_finalize_target(rpcs3)
        if(NOT RPCS3_IOS)
            add_custom_command(TARGET rpcs3 POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.icns $<TARGET_FILE_DIR:rpcs3>/../Resources/rpcs3.icns
                COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/../Resources/Icons
                COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/../Resources/GuiConfigs
                COMMAND "${MACDEPLOYQT_EXECUTABLE}" "${PROJECT_BINARY_DIR}/bin/rpcs3.app" "$<$<CONFIG:Debug,RelWithDebInfo>:-no-strip>")
        endif()
    elseif(UNIX)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/GuiConfigs)
    elseif(WIN32)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/GuiConfigs
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/test $<TARGET_FILE_DIR:rpcs3>/test
            COMMAND "${WINDEPLOYQT_EXECUTABLE}" --no-compiler-runtime --no-opengl-sw --no-patchqt
                --no-system-d3d-compiler --no-system-dxc-compiler --no-quick-import
                --plugindir "$<IF:$<CXX_COMPILER_ID:MSVC>,$<TARGET_FILE_DIR:rpcs3>/plugins,$<TARGET_FILE_DIR:rpcs3>/share/qt6/plugins>"
                --translationdir "$<IF:$<CXX_COMPILER_ID:MSVC>,$<TARGET_FILE_DIR:rpcs3>/translations,$<TARGET_FILE_DIR:rpcs3>/share/qt6/translations>"
                --verbose 0 "$<TARGET_FILE:rpcs3>")
    endif()

    # Unix installation
    if(UNIX AND NOT APPLE)
        # Install the binary
        install(TARGETS rpcs3 RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
        install(FILES rpcs3.svg
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps)
        install(FILES rpcs3.png
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/48x48/apps)
        install(FILES rpcs3.desktop
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
        install(FILES rpcs3.metainfo.xml
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/metainfo)
        install(DIRECTORY ../bin/Icons
            DESTINATION ${CMAKE_INSTALL_DATADIR}/rpcs3)
        install(DIRECTORY ../bin/GuiConfigs
            DESTINATION ${CMAKE_INSTALL_DATADIR}/rpcs3)
        install(DIRECTORY ../bin/test
            DESTINATION ${CMAKE_INSTALL_DATADIR}/rpcs3)
    endif()
endif()

# Unit tests
if(BUILD_RPCS3_TESTS)
    find_package(GTest REQUIRED)

    message(STATUS "Building unit tests...")

    add_executable(rpcs3_test)

    target_sources(rpcs3_test
        PRIVATE
            tests/test.cpp
            tests/test_bit_set.cpp
            tests/test_fmt.cpp
            tests/test_pair.cpp
            tests/test_tuple.cpp
            tests/test_simple_array.cpp
            tests/test_address_range.cpp
            tests/test_sys_fs.cpp
            tests/test_rsx_cfg.cpp
            tests/test_rsx_fp_asm.cpp
            tests/test_dmux_pamf.cpp
            tests/test_spu_analyser.cpp
            tests/test_types_util.cpp
    )

    target_link_libraries(rpcs3_test
        PRIVATE
            rpcs3_lib
            rpcs3_emu
            GTest::gtest
            GTest::gmock
    )

    target_include_directories(rpcs3_test
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/..
    )

    include(GoogleTest)
    gtest_discover_tests(rpcs3_test)

    if(RUN_RPCS3_TESTS)
        add_custom_target(run_tests
            ALL
            COMMAND ${CMAKE_CTEST_COMMAND} -j -VV --output-on-failure
            DEPENDS rpcs3_test
     )
    endif()
endif()
