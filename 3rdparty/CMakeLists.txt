find_package(PkgConfig)
include(ExternalProject)
include(CMakeDependentOption)

set(CMAKE_CXX_STANDARD 20)

# Defines the ARCHITECTURE variable
include("DetectArchitecture.cmake")

# Warnings are silenced for 3rdparty code
if(NOT MSVC)
	add_compile_options("$<$<COMPILE_LANGUAGE:CXX,C>:-w>")
endif()

# Dummy target to use when lib isn't available
add_library(3rdparty_dummy_lib INTERFACE)


# ZLib
add_subdirectory(zlib EXCLUDE_FROM_ALL)

# ZSTD
add_subdirectory(zstd EXCLUDE_FROM_ALL)

# 7zip sdk
add_subdirectory(7zip EXCLUDE_FROM_ALL)

# Protobuf
add_subdirectory(protobuf EXCLUDE_FROM_ALL)

# libPNG
add_subdirectory(libpng EXCLUDE_FROM_ALL)


# pugixml
if (USE_SYSTEM_PUGIXML)
	pkg_check_modules(PUGIXML REQUIRED IMPORTED_TARGET pugixml>=1.15)
	add_library(pugixml INTERFACE)
	target_link_libraries(pugixml INTERFACE PkgConfig::PUGIXML)
else()
	add_subdirectory(pugixml EXCLUDE_FROM_ALL)
endif()

if (USE_SYSTEM_VULKAN_MEMORY_ALLOCATOR)
	find_package(VulkanMemoryAllocator REQUIRED GLOBAL)
	add_library(3rdparty::vulkanmemoryallocator ALIAS GPUOpen::VulkanMemoryAllocator)
else()
	add_library(3rdparty_vulkanmemoryallocator INTERFACE)
	target_include_directories(3rdparty_vulkanmemoryallocator SYSTEM INTERFACE GPUOpen/VulkanMemoryAllocator/include)
	add_library(3rdparty::vulkanmemoryallocator ALIAS 3rdparty_vulkanmemoryallocator)
endif()

# libusb
if(RPCS3_IOS)
	# iOS uses the bundled library with its null backend. Host pkg-config
	# results are never valid for an iPhone target.
	set(USE_SYSTEM_LIBUSB OFF CACHE BOOL "Use bundled libusb on iOS" FORCE)
elseif(CMAKE_SYSTEM_NAME MATCHES "DragonFly|FreeBSD")
	pkg_check_modules(LIBUSB REQUIRED IMPORTED_TARGET libusb-1.0>=1.0 )
	cmake_dependent_option(USE_SYSTEM_LIBUSB "Use system libusb-1.0 as shared library" ON
			"LIBUSB_FOUND" OFF)
else()
	pkg_check_modules(LIBUSB IMPORTED_TARGET libusb-1.0>=1.0 )
	cmake_dependent_option(USE_SYSTEM_LIBUSB "Use system libusb-1.0 as shared library" OFF
			"LIBUSB_FOUND" OFF)
endif()
if(RPCS3_IOS)
	unset(LIBUSB_LIBRARIES CACHE)
	add_subdirectory(libusb EXCLUDE_FROM_ALL)
elseif(CMAKE_SYSTEM_NAME MATCHES "DragonFly|FreeBSD")
	# Always use system libusb as reference implementation isn't supported
	add_library(usb-1.0-shared INTERFACE)
	target_link_libraries(usb-1.0-shared INTERFACE PkgConfig::LIBUSB)
elseif(MSVC)
	# Windows time.h defines timespec but doesn't add any flag for it, which makes libusb attempt to define it again
	add_definitions(-DHAVE_STRUCT_TIMESPEC=1)
	add_subdirectory(libusb EXCLUDE_FROM_ALL)
else()
	if(USE_SYSTEM_LIBUSB)
		# we have the system libusb and have selected to use it
		add_library(usb-1.0-shared INTERFACE)
		target_link_libraries(usb-1.0-shared INTERFACE PkgConfig::LIBUSB)
	else()
		# we don't have the system libusb, so we compile from submodule
		unset(LIBUSB_LIBRARIES CACHE)
		add_subdirectory(libusb EXCLUDE_FROM_ALL)

		if (NOT TARGET usb-1.0 AND TARGET usb-1.0-static)
			add_library(usb-1.0 ALIAS usb-1.0-static)
		endif()
	endif()
endif()


# hidapi
add_subdirectory(hidapi)

# glslang
add_subdirectory(glslang EXCLUDE_FROM_ALL)

# yaml-cpp
add_subdirectory(yaml-cpp)


# OpenGL

if (NOT ANDROID AND NOT APPLE)
	find_package(OpenGL REQUIRED OPTIONAL_COMPONENTS EGL)

	add_library(3rdparty_opengl INTERFACE)
	target_include_directories(3rdparty_opengl SYSTEM INTERFACE GL)

	if (WIN32)
		if(NOT MSVC)
			target_link_libraries(3rdparty_opengl INTERFACE OpenGL::GL OpenGL::GLU)
		else()
			target_link_libraries(3rdparty_opengl INTERFACE dxgi.lib d2d1.lib dwrite.lib)
		endif()
	else()
		target_link_libraries(3rdparty_opengl INTERFACE OpenGL::GL OpenGL::GLU OpenGL::GLX)
	endif()
else()
	add_library(3rdparty_opengl INTERFACE)
	target_compile_definitions(3rdparty_opengl INTERFACE WITHOUT_OPENGL=1)
endif()

# stblib
add_subdirectory(stblib)

# DiscordRPC
add_subdirectory(discord-rpc)

# Cubeb
if(USE_SYSTEM_CUBEB)
	find_package(cubeb REQUIRED GLOBAL)
	message(STATUS "Using system cubeb version '${cubeb_VERSION}'")
	add_library(3rdparty::cubeb ALIAS cubeb::cubeb)
else()
	message(STATUS "Using static cubeb from 3rdparty")
	add_subdirectory(cubeb EXCLUDE_FROM_ALL)
endif()

# SoundTouch
add_subdirectory(SoundTouch EXCLUDE_FROM_ALL)

# libevdev
set(LIBEVDEV_TARGET 3rdparty_dummy_lib)
if(USE_LIBEVDEV)
	pkg_check_modules(LIBEVDEV libevdev libudev)
	if(LIBEVDEV_FOUND)
		add_library(3rdparty_libevdev INTERFACE)
		target_compile_definitions(3rdparty_libevdev INTERFACE -DHAVE_LIBEVDEV)
		target_include_directories(3rdparty_libevdev SYSTEM
			INTERFACE ${LIBEVDEV_INCLUDE_DIRS})
		target_link_libraries(3rdparty_libevdev INTERFACE ${LIBEVDEV_LDFLAGS})

		set(LIBEVDEV_TARGET 3rdparty_libevdev)
	endif()
endif()


# Vulkan
set(VULKAN_TARGET 3rdparty_dummy_lib)
if(USE_VULKAN)
	if(APPLE)
		if(RPCS3_IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
			if(NOT USE_SYSTEM_MVK)
				message(FATAL_ERROR
					"RPCS3: iOS Vulkan requires a caller-provided MoltenVK build. "
					"Set USE_SYSTEM_MVK=ON, Vulkan_INCLUDE_DIR to a MoltenVK include directory, "
					"and Vulkan_LIBRARY to the matching iPhoneOS or iPhoneSimulator library slice.")
			endif()

			if(NOT Vulkan_INCLUDE_DIR
				OR NOT EXISTS "${Vulkan_INCLUDE_DIR}/vulkan/vulkan.h"
				OR NOT EXISTS "${Vulkan_INCLUDE_DIR}/MoltenVK/mvk_vulkan.h")
				message(FATAL_ERROR
					"RPCS3: Vulkan_INCLUDE_DIR must contain both vulkan/vulkan.h and "
					"MoltenVK/mvk_vulkan.h for an iOS Vulkan build.")
			endif()

			if(NOT Vulkan_LIBRARY OR NOT EXISTS "${Vulkan_LIBRARY}" OR IS_DIRECTORY "${Vulkan_LIBRARY}")
				message(FATAL_ERROR
					"RPCS3: Vulkan_LIBRARY must name the MoltenVK library file for the "
					"selected iPhoneOS or iPhoneSimulator SDK (for example, libMoltenVK.a).")
			endif()

			message(STATUS "RPCS3: Using caller-provided MoltenVK for iOS")
		elseif(USE_SYSTEM_MVK)
			message(STATUS "RPCS3: Using system MoltenVK")
		else()
			message(STATUS "RPCS3: MoltenVK submodule")

			execute_process(COMMAND "${CMAKE_COMMAND}" -G "${CMAKE_GENERATOR}" .
				WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK"
			)
			execute_process(COMMAND "${CMAKE_COMMAND}" --build .
				WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK"
			)

			add_library(moltenvk_lib SHARED IMPORTED)
			add_dependencies(moltenvk_lib moltenvk)
			set_target_properties(moltenvk_lib
				PROPERTIES IMPORTED_LOCATION "{Vulkan_LIBRARY}"
			)

			set(VULKAN_SDK "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/MoltenVK/MoltenVK")
			set(VK_ICD_FILENAMES "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/MoltenVK/MoltenVK/icd/MoltenVK_icd.json")
			set(Vulkan_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/MoltenVK/MoltenVK/include")
			set(Vulkan_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/MoltenVK/Build/Products/Release/dynamic/libMoltenVK.dylib")
			set(Vulkan_TOOLS "${CMAKE_CURRENT_SOURCE_DIR}/MoltenVK/MoltenVK/Build/Products/Release")
		endif()
	endif()

	find_package(Vulkan)
	if(VULKAN_FOUND)
		add_library(3rdparty_vulkan INTERFACE)
		target_compile_definitions(3rdparty_vulkan INTERFACE -DHAVE_VULKAN)
		target_link_libraries(3rdparty_vulkan INTERFACE Vulkan::Vulkan)

		if(APPLE)
			find_library(RPCS3_MVK_METAL_FRAMEWORK Metal REQUIRED)
			find_library(RPCS3_MVK_FOUNDATION_FRAMEWORK Foundation REQUIRED)
			find_library(RPCS3_MVK_QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
			find_library(RPCS3_MVK_COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
			find_library(RPCS3_MVK_IOSURFACE_FRAMEWORK IOSurface REQUIRED)

			target_link_libraries(3rdparty_vulkan INTERFACE
				${RPCS3_MVK_METAL_FRAMEWORK}
				${RPCS3_MVK_FOUNDATION_FRAMEWORK}
				${RPCS3_MVK_QUARTZCORE_FRAMEWORK}
				${RPCS3_MVK_COREGRAPHICS_FRAMEWORK}
				${RPCS3_MVK_IOSURFACE_FRAMEWORK})

			if(RPCS3_IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
				find_library(RPCS3_MVK_UI_FRAMEWORK UIKit REQUIRED)
			else()
				find_library(RPCS3_MVK_UI_FRAMEWORK AppKit REQUIRED)
			endif()
			target_link_libraries(3rdparty_vulkan INTERFACE ${RPCS3_MVK_UI_FRAMEWORK})
		endif()

		if(UNIX AND NOT APPLE AND NOT ANDROID)
			find_package(Wayland)
			if (WAYLAND_FOUND)
				target_include_directories(3rdparty_vulkan
					SYSTEM INTERFACE ${WAYLAND_INCLUDE_DIR})
			endif()
		endif()

		set(VULKAN_TARGET 3rdparty_vulkan)
	else()
		message(WARNING "USE_VULKAN was enabled, but libvulkan was not found. RPCS3 will be compiled without Vulkan support.")
		if(APPLE)
			message(FATAL_ERROR "To build without Vulkan support on macOS, please disable USE_VULKAN.")
		endif()
	endif()
endif()

# AsmJit
add_subdirectory(asmjit EXCLUDE_FROM_ALL)

# SDL3
set(SDL3_TARGET 3rdparty_dummy_lib)
if(USE_SDL)
	if(USE_SYSTEM_SDL)
		find_package(SDL3)
		if(SDL3_FOUND AND SDL3_VERSION VERSION_GREATER_EQUAL 3.2.0)
			message(STATUS "Using system SDL3 version '${SDL3_VERSION}'")
			add_library(3rdparty_sdl3 INTERFACE)
			target_compile_definitions(3rdparty_sdl3 INTERFACE -DHAVE_SDL3=1)
			target_link_libraries(3rdparty_sdl3 INTERFACE SDL3::SDL3)
			set(SDL3_TARGET 3rdparty_sdl3)
		else()
			message(FATAL_ERROR "SDL3 is not available on this system")
		endif()
	else()
		message(STATUS "Using static SDL3 from 3rdparty")
		add_subdirectory(libsdl-org EXCLUDE_FROM_ALL)
		target_compile_definitions(SDL3-static INTERFACE -DHAVE_SDL3=1)
		set(SDL3_TARGET SDL3-static)
		set(SDL3_DIR "${CMAKE_CURRENT_BINARY_DIR}/libsdl-org/SDL" CACHE STRING "")
	endif()
endif()

# OpenAL
if (NOT ANDROID)
	add_subdirectory(OpenAL EXCLUDE_FROM_ALL)
else()
	add_library(3rdparty_openal INTERFACE)
	target_compile_definitions(3rdparty_openal INTERFACE WITHOUT_OPENAL=1)
endif()

# FAudio
set(FAUDIO_TARGET 3rdparty_dummy_lib)
if(USE_FAUDIO)
	# FAudio depends on SDL3
	find_package(SDL3)
	if (USE_SYSTEM_FAUDIO)
		if (SDL3_FOUND AND SDL3_VERSION VERSION_GREATER_EQUAL 3.2.0)
			message(STATUS "RPCS3: Using system FAudio")
			find_package(FAudio REQUIRED CONFIGS FAudioConfig.cmake FAudio-config.cmake)
			add_library(3rdparty_FAudio INTERFACE)
			target_link_libraries(3rdparty_FAudio INTERFACE FAudio)
			target_compile_definitions(3rdparty_FAudio INTERFACE -DHAVE_FAUDIO)
			set(FAUDIO_TARGET 3rdparty_FAudio)
		else()
			message(WARNING
				"RPCS3: System FAudio requires SDL 3.2.0 or newer. Since a valid SDL3"
				">=3.2.0 version cannot be found, building with FAudio will be skipped.")
			set(USE_FAUDIO OFF CACHE BOOL "Disabled using system FAudio with SDL < 3.2.0" FORCE)
		endif()
	else()
		if (SDL3_FOUND AND SDL3_VERSION VERSION_GREATER_EQUAL 3.2.0)
			message(STATUS "RPCS3: Using builtin FAudio")
			set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared library")
			add_subdirectory(FAudio EXCLUDE_FROM_ALL)
			target_compile_definitions(FAudio-static INTERFACE -DHAVE_FAUDIO)
			set(FAUDIO_TARGET FAudio-static)
		else()
			message(WARNING
				"-- RPCS3: 3rdparty FAudio requires SDL 3.2.0 or newer. Since a valid SDL3"
				">=3.2.0 version cannot be found, building with FAudio will be skipped.")
			set(USE_FAUDIO OFF CACHE BOOL "Disabled FAudio with SDL < 3.2.0" FORCE)
		endif()
	endif()
endif()

set_property(TARGET ${FAUDIO_TARGET} PROPERTY FOLDER "3rdparty/")


# FFMPEG
if(RPCS3_IOS)
	set(RPCS3_IOS_FFMPEG_ROOT "" CACHE PATH
		"Prefix containing target-built FFmpeg include/ and lib/ directories")
	if(NOT RPCS3_IOS_FFMPEG_ROOT)
		message(FATAL_ERROR
			"An iOS FFmpeg build is required. Set RPCS3_IOS_FFMPEG_ROOT to a ${RPCS3_IOS_PLATFORM}-compatible prefix containing include/ and lib/*.a. The macOS prebuilt is not compatible with iOS.")
	endif()

	set(RPCS3_IOS_FFMPEG_LIBRARIES)
	foreach(FFMPEG_COMPONENT avformat avcodec swscale swresample avutil)
		set(FFMPEG_COMPONENT_LIBRARY "${RPCS3_IOS_FFMPEG_ROOT}/lib/lib${FFMPEG_COMPONENT}.a")
		if(NOT EXISTS "${FFMPEG_COMPONENT_LIBRARY}")
			message(FATAL_ERROR "Missing iOS FFmpeg library: ${FFMPEG_COMPONENT_LIBRARY}")
		endif()
		list(APPEND RPCS3_IOS_FFMPEG_LIBRARIES "${FFMPEG_COMPONENT_LIBRARY}")
	endforeach()
	if(NOT EXISTS "${RPCS3_IOS_FFMPEG_ROOT}/include/libavcodec/avcodec.h")
		message(FATAL_ERROR "Missing iOS FFmpeg headers under ${RPCS3_IOS_FFMPEG_ROOT}/include")
	endif()

	# arm64 alone is ambiguous on Apple platforms. Inspect an archive member so
	# an iPhoneOS library cannot accidentally enter an iPhoneSimulator build (or
	# vice versa) and defer the failure until the final link.
	set(FFMPEG_PLATFORM_CHECK_DIR "${CMAKE_BINARY_DIR}/CMakeFiles/rpcs3-ffmpeg-platform-check")
	file(REMOVE_RECURSE "${FFMPEG_PLATFORM_CHECK_DIR}")
	file(MAKE_DIRECTORY "${FFMPEG_PLATFORM_CHECK_DIR}")
	execute_process(
		COMMAND "${CMAKE_AR}" -t "${RPCS3_IOS_FFMPEG_ROOT}/lib/libavcodec.a"
		OUTPUT_VARIABLE FFMPEG_ARCHIVE_MEMBERS
		RESULT_VARIABLE FFMPEG_AR_LIST_RESULT
		OUTPUT_STRIP_TRAILING_WHITESPACE)
	if(NOT FFMPEG_AR_LIST_RESULT EQUAL 0)
		message(FATAL_ERROR "Unable to inspect ${RPCS3_IOS_FFMPEG_ROOT}/lib/libavcodec.a")
	endif()
	string(REPLACE "\n" ";" FFMPEG_ARCHIVE_MEMBERS "${FFMPEG_ARCHIVE_MEMBERS}")
	list(FILTER FFMPEG_ARCHIVE_MEMBERS INCLUDE REGEX "\\.o$")
	list(LENGTH FFMPEG_ARCHIVE_MEMBERS FFMPEG_ARCHIVE_MEMBER_COUNT)
	if(FFMPEG_ARCHIVE_MEMBER_COUNT EQUAL 0)
		message(FATAL_ERROR "The FFmpeg avcodec archive contains no inspectable Mach-O object files")
	endif()
	list(GET FFMPEG_ARCHIVE_MEMBERS 0 FFMPEG_ARCHIVE_MEMBER)
	execute_process(
		COMMAND "${CMAKE_AR}" -x "${RPCS3_IOS_FFMPEG_ROOT}/lib/libavcodec.a" "${FFMPEG_ARCHIVE_MEMBER}"
		WORKING_DIRECTORY "${FFMPEG_PLATFORM_CHECK_DIR}"
		RESULT_VARIABLE FFMPEG_AR_EXTRACT_RESULT)
	if(NOT FFMPEG_AR_EXTRACT_RESULT EQUAL 0)
		message(FATAL_ERROR "Unable to extract an object from the FFmpeg avcodec archive")
	endif()
	find_program(RPCS3_VTOOL_EXECUTABLE vtool REQUIRED)
	execute_process(
		COMMAND "${RPCS3_VTOOL_EXECUTABLE}" -show-build "${FFMPEG_PLATFORM_CHECK_DIR}/${FFMPEG_ARCHIVE_MEMBER}"
		OUTPUT_VARIABLE FFMPEG_BUILD_VERSION
		RESULT_VARIABLE FFMPEG_VTOOL_RESULT)
	if(RPCS3_IOS_PLATFORM STREQUAL "simulator")
		set(FFMPEG_EXPECTED_PLATFORM "IOSSIMULATOR")
	else()
		set(FFMPEG_EXPECTED_PLATFORM "IOS")
	endif()
	if(NOT FFMPEG_VTOOL_RESULT EQUAL 0
		OR NOT FFMPEG_BUILD_VERSION MATCHES "platform[ \t]+${FFMPEG_EXPECTED_PLATFORM}([ \r\n]|$)")
		message(FATAL_ERROR
			"RPCS3_IOS_FFMPEG_ROOT does not contain ${RPCS3_IOS_PLATFORM} libraries (expected LC_BUILD_VERSION platform ${FFMPEG_EXPECTED_PLATFORM}).")
	endif()
	file(REMOVE_RECURSE "${FFMPEG_PLATFORM_CHECK_DIR}")

	add_library(3rdparty_ffmpeg INTERFACE)
	target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE
		"${RPCS3_IOS_FFMPEG_ROOT}/include")
	target_link_libraries(3rdparty_ffmpeg INTERFACE
		${RPCS3_IOS_FFMPEG_LIBRARIES}
		bz2
		iconv
		z
		"-framework AudioToolbox"
		"-framework CoreFoundation"
		"-framework CoreMedia"
		"-framework CoreVideo"
		"-framework Security"
		"-framework VideoToolbox")
elseif(NOT ANDROID)
	add_library(3rdparty_ffmpeg INTERFACE)

	# Select the version of ffmpeg to use, default is builtin
	if(USE_SYSTEM_FFMPEG)
		message(STATUS "RPCS3: using shared ffmpeg")
		find_package(FFMPEG REQUIRED)

		target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE ${FFMPEG_INCLUDE_DIR})
		target_link_libraries(3rdparty_ffmpeg INTERFACE ${FFMPEG_LIBRARIES})
	else()
		message(STATUS "RPCS3: using builtin ffmpeg")
		add_subdirectory(ffmpeg EXCLUDE_FROM_ALL)
		# ffmpeg-core libraries are extracted to CMAKE_BINARY_DIR
		set(FFMPEG_LIB_DIR "${CMAKE_BINARY_DIR}/3rdparty/ffmpeg/lib")

		if (WIN32)
			target_link_libraries(3rdparty_ffmpeg INTERFACE "Bcrypt.lib")
		endif()

		find_library(FFMPEG_LIB_AVFORMAT avformat PATHS ${FFMPEG_LIB_DIR} NO_DEFAULT_PATH)
		find_library(FFMPEG_LIB_AVCODEC avcodec PATHS ${FFMPEG_LIB_DIR} NO_DEFAULT_PATH)
		find_library(FFMPEG_LIB_AVUTIL avutil PATHS ${FFMPEG_LIB_DIR} NO_DEFAULT_PATH)
		find_library(FFMPEG_LIB_SWSCALE swscale PATHS ${FFMPEG_LIB_DIR} NO_DEFAULT_PATH)
		find_library(FFMPEG_LIB_SWRESAMPLE swresample PATHS ${FFMPEG_LIB_DIR} NO_DEFAULT_PATH)

		if (FFMPEG_LIB_AVFORMAT MATCHES "FFMPEG_LIB_AVFORMAT-NOTFOUND")
			message(FATAL_ERROR "@#$%! FFMPEG NOT FOUND! ${FFMPEG_LIB_DIR}")
		endif()

		target_link_libraries(3rdparty_ffmpeg
		INTERFACE
			${FFMPEG_LIB_AVFORMAT}
			${FFMPEG_LIB_AVCODEC}
			${FFMPEG_LIB_AVUTIL}
			${FFMPEG_LIB_SWSCALE}
			${FFMPEG_LIB_SWRESAMPLE}
		)
		target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE "ffmpeg/include")
	endif()
endif()


# GLEW
add_library(3rdparty_glew INTERFACE)
if(NOT MSVC AND NOT ANDROID AND NOT APPLE)
	find_package(GLEW REQUIRED)
	target_link_libraries(3rdparty_glew INTERFACE GLEW::GLEW)
endif()


# LLVM
add_subdirectory(llvm EXCLUDE_FROM_ALL)

# WOLFSSL
add_subdirectory(wolfssl EXCLUDE_FROM_ALL)

# CURL
add_subdirectory(curl EXCLUDE_FROM_ALL)

# MINIUPNP
add_subdirectory(miniupnp EXCLUDE_FROM_ALL)

# RTMIDI
add_subdirectory(rtmidi EXCLUDE_FROM_ALL)

# OPENCV
add_subdirectory(opencv EXCLUDE_FROM_ALL)

# FUSION
add_subdirectory(fusion EXCLUDE_FROM_ALL)

# FERAL INTERACTIVE
add_subdirectory(feralinteractive EXCLUDE_FROM_ALL)

# add nice ALIAS targets for ease of use
if(USE_SYSTEM_LIBUSB)
	add_library(3rdparty::libusb ALIAS usb-1.0-shared)
else()
	add_library(3rdparty::libusb ALIAS usb-1.0-static)
endif()
add_library(3rdparty::zlib ALIAS 3rdparty_zlib)
add_library(3rdparty::zstd ALIAS 3rdparty_zstd)
add_library(3rdparty::7zip ALIAS 3rdparty_7zip)
add_library(3rdparty::protobuf ALIAS 3rdparty_protobuf)
add_library(3rdparty::pugixml ALIAS pugixml)
add_library(3rdparty::glslang ALIAS 3rdparty_glslang)
add_library(3rdparty::yaml-cpp ALIAS yaml-cpp)
add_library(3rdparty::hidapi ALIAS 3rdparty_hidapi)
add_library(3rdparty::libpng ALIAS ${LIBPNG_TARGET})
add_library(3rdparty::opengl ALIAS 3rdparty_opengl)
add_library(3rdparty::stblib ALIAS 3rdparty_stblib)
add_library(3rdparty::discordRPC ALIAS 3rdparty_discordRPC)
add_library(3rdparty::faudio ALIAS ${FAUDIO_TARGET})
add_library(3rdparty::libevdev ALIAS ${LIBEVDEV_TARGET})
add_library(3rdparty::vulkan ALIAS ${VULKAN_TARGET})
add_library(3rdparty::openal ALIAS 3rdparty_openal)
add_library(3rdparty::ffmpeg ALIAS 3rdparty_ffmpeg)
add_library(3rdparty::glew ALIAS 3rdparty_glew)
add_library(3rdparty::wolfssl ALIAS wolfssl)
add_library(3rdparty::libcurl ALIAS 3rdparty_libcurl)
add_library(3rdparty::soundtouch ALIAS soundtouch)
add_library(3rdparty::sdl3 ALIAS ${SDL3_TARGET})
add_library(3rdparty::miniupnpc ALIAS 3rdparty_miniupnpc)
add_library(3rdparty::rtmidi ALIAS rtmidi)
add_library(3rdparty::opencv ALIAS ${OPENCV_TARGET})
add_library(3rdparty::fusion ALIAS Fusion)
add_library(3rdparty::feralinteractive ALIAS 3rdparty_feralinteractive)
