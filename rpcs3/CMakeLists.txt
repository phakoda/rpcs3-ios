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

if (NOT ANDROID)
    if(RPCS3_IOS)
        set(RPCS3_IOS_QT_ROOT "" CACHE PATH
            "Prefix of a Qt build targeting the selected iOS SDK")
        set(RPCS3_IOS_QT_HOST_PATH "" CACHE PATH
            "Prefix of the matching host Qt tools used by the iOS Qt build")

        if(NOT RPCS3_IOS_QT_ROOT)
            message(FATAL_ERROR
                "Qt for iOS is required. Set RPCS3_IOS_QT_ROOT to a ${RPCS3_IOS_PLATFORM}-compatible Qt prefix; a Homebrew macOS Qt installation cannot be used.")
        endif()
        list(PREPEND CMAKE_PREFIX_PATH "${RPCS3_IOS_QT_ROOT}")
        list(PREPEND CMAKE_FIND_ROOT_PATH "${RPCS3_IOS_QT_ROOT}")
        if(RPCS3_IOS_QT_HOST_PATH)
            set(QT_HOST_PATH "${RPCS3_IOS_QT_HOST_PATH}" CACHE PATH
                "Host Qt tools for the iOS cross-build" FORCE)
        endif()
    endif()

    # Qt
    # finds Qt libraries and setups custom commands for MOC and UIC
    # Must be done here because generated MOC and UIC targets cant
    # be found otherwise
    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)

    if(RPCS3_IOS AND NOT QT_QMAKE_TARGET_MKSPEC MATCHES "ios")
        message(FATAL_ERROR
            "RPCS3_IOS_QT_ROOT resolved to Qt target mkspec '${QT_QMAKE_TARGET_MKSPEC}', not an iOS Qt build (expected a mkspec such as macx-ios-clang).")
    endif()
endif()

# subdirectories
add_subdirectory(Emu)

if (NOT ANDROID)
    add_subdirectory(rpcs3qt)
endif()

gen_git_version(${CMAKE_CURRENT_SOURCE_DIR})

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
    elseif(RPCS3_IOS)
        set(RPCS3_IOS_BUNDLE_IDENTIFIER "org.rpcs3.ios" CACHE STRING
            "Bundle identifier for the iOS application")
        set(RPCS3_IOS_BUNDLE_VERSION "1" CACHE STRING
            "Monotonically increasing iOS bundle build number")
        set(RPCS3_IOS_SHORT_VERSION "0.0.1" CACHE STRING
            "User-visible iOS bundle version")
        set(RPCS3_IOS_ENTITLEMENTS_FILE
            "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3_ios.entitlements" CACHE FILEPATH
            "Entitlements plist used when signing the iOS application")
        set(RPCS3_IOS_DEVELOPMENT_TEAM "" CACHE STRING
            "Optional Apple development team identifier for Xcode-generated builds")

        if(NOT EXISTS "${RPCS3_IOS_ENTITLEMENTS_FILE}")
            message(FATAL_ERROR
                "RPCS3_IOS_ENTITLEMENTS_FILE does not exist: ${RPCS3_IOS_ENTITLEMENTS_FILE}")
        endif()

        set_target_properties(rpcs3 PROPERTIES
            MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3_ios.plist.in"
            MACOSX_BUNDLE_GUI_IDENTIFIER "${RPCS3_IOS_BUNDLE_IDENTIFIER}"
            MACOSX_BUNDLE_BUNDLE_NAME "RPCS3"
            MACOSX_BUNDLE_BUNDLE_VERSION "${RPCS3_IOS_BUNDLE_VERSION}"
            MACOSX_BUNDLE_SHORT_VERSION_STRING "${RPCS3_IOS_SHORT_VERSION}"
            XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${RPCS3_IOS_ENTITLEMENTS_FILE}"
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${RPCS3_IOS_BUNDLE_IDENTIFIER}"
            XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
            XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
            XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
            BUILD_WITH_INSTALL_RPATH TRUE
            INSTALL_RPATH "@executable_path/Frameworks")
        if(RPCS3_IOS_DEVELOPMENT_TEAM)
            set_target_properties(rpcs3 PROPERTIES
                XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${RPCS3_IOS_DEVELOPMENT_TEAM}")
        endif()

        target_link_libraries(rpcs3 PRIVATE
            "-framework Foundation"
            "-framework UIKit")

        # Caller-provided iOS MoltenVK builds are commonly distributed as a
        # dylib (including MeloNX's runtime). Keep the loader path inside the
        # signed application and embed that runtime below after linking.
        if(USE_VULKAN AND Vulkan_LIBRARY MATCHES "\\.dylib$")
            target_link_options(rpcs3 PRIVATE
                "LINKER:-rpath,@executable_path/Frameworks")
        endif()
    elseif(APPLE)
        target_sources(rpcs3 PRIVATE rpcs3.icns update_helper.sh)
        set_source_files_properties(update_helper.sh PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        set_target_properties(rpcs3
            PROPERTIES
                MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.plist.in")
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
    if(RPCS3_IOS)
        qt_finalize_target(rpcs3)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_BUNDLE_DIR:rpcs3>/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_BUNDLE_DIR:rpcs3>/GuiConfigs
            VERBATIM)
        if(USE_VULKAN AND Vulkan_LIBRARY MATCHES "\\.dylib$")
            add_custom_command(TARGET rpcs3 POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    $<TARGET_BUNDLE_DIR:rpcs3>/Frameworks
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${Vulkan_LIBRARY}"
                    $<TARGET_BUNDLE_DIR:rpcs3>/Frameworks/libMoltenVK.dylib
                COMMAND /usr/bin/codesign --force --sign -
                    $<TARGET_BUNDLE_DIR:rpcs3>/Frameworks/libMoltenVK.dylib
                VERBATIM)
        endif()
    elseif(APPLE)
        qt_finalize_target(rpcs3)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.icns $<TARGET_FILE_DIR:rpcs3>/../Resources/rpcs3.icns
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/../Resources/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/../Resources/GuiConfigs
            COMMAND "${MACDEPLOYQT_EXECUTABLE}" "${PROJECT_BINARY_DIR}/bin/rpcs3.app" "$<$<CONFIG:Debug,RelWithDebInfo>:-no-strip>")
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
        # Install the application icon and menu item
        install(FILES rpcs3.svg
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps)
        install(FILES rpcs3.png
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/48x48/apps)
        install(FILES rpcs3.desktop
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
        install(FILES rpcs3.metainfo.xml
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/metainfo)
        # Install other files
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
