# hidapi
if(RPCS3_IOS)
	# iOS has no public IOKit USB transport. Build HIDAPI over libusb's null
	# backend so callers retain the API and simply enumerate no USB devices.
	find_package(Threads REQUIRED)
	add_library(hidapi_libusb STATIC
		hidapi/libusb/hid.c
	)
	target_compile_definitions(hidapi_libusb PRIVATE
		NO_ICONV
		HIDAPI_THREAD_MODEL_INCLUDE="hidapi_thread_ios.h")
	target_include_directories(hidapi_libusb
		PUBLIC hidapi/hidapi
		PRIVATE hidapi/libusb ${CMAKE_CURRENT_SOURCE_DIR})
	target_link_libraries(hidapi_libusb PRIVATE usb-1.0-static Threads::Threads)

	add_library(3rdparty_hidapi INTERFACE)
	target_link_libraries(3rdparty_hidapi INTERFACE hidapi_libusb)
elseif(USE_SYSTEM_HIDAPI)
	message(STATUS "RPCS3: using shared hidapi")
	pkg_check_modules(hidapi-hidraw REQUIRED IMPORTED_TARGET hidapi-hidraw)
	add_library(3rdparty_hidapi INTERFACE)
	target_link_libraries(3rdparty_hidapi INTERFACE PkgConfig::hidapi-hidraw)
	target_include_directories(3rdparty_hidapi SYSTEM INTERFACE PkgConfig::hidapi-hidraw)
else()
	set(BUILD_SHARED_LIBS FALSE CACHE BOOL "Don't build shared libs")
	set(HIDAPI_INSTALL_TARGETS FALSE CACHE BOOL "Don't install anything")

	if(CMAKE_SYSTEM MATCHES "Linux")
		set(HIDAPI_WITH_LIBUSB FALSE CACHE BOOL "Don't build with libusb for linux")
	endif()

	add_library(3rdparty_hidapi INTERFACE)
	add_subdirectory(hidapi EXCLUDE_FROM_ALL)

	if(APPLE)
		target_link_libraries(3rdparty_hidapi INTERFACE hidapi_darwin "-framework CoreFoundation" "-framework IOKit")
	elseif(CMAKE_SYSTEM MATCHES "Linux")
		target_link_libraries(3rdparty_hidapi INTERFACE hidapi-hidraw udev)
	elseif(WIN32)
		target_link_libraries(3rdparty_hidapi INTERFACE hidapi::hidapi hidapi::include Shlwapi.lib)
	elseif(ANDROID)
		target_link_libraries(3rdparty_hidapi INTERFACE hidapi::libusb)
	else()
		target_link_libraries(3rdparty_hidapi INTERFACE hidapi-libusb usb)
	endif()
endif()
