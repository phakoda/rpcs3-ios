# Cubeb

set(BUILD_SHARED_LIBS FALSE CACHE BOOL "Don't build shared libs")
set(BUILD_TESTS FALSE CACHE BOOL "Don't build tests")
set(BUILD_RUST_LIBS FALSE CACHE BOOL "Don't build rust libs")
set(BUILD_TOOLS FALSE CACHE BOOL "Don't build tools")
set(BUNDLE_SPEEX TRUE CACHE BOOL "Bundle the speex library")
set(LAZY_LOAD_LIBS TRUE CACHE BOOL "Lazily load shared libraries")
set(USE_SANITIZERS FALSE CACHE BOOL "Dont't use sanitizers")

if(RPCS3_IOS)
	# Cubeb's CoreAudio backend still depends on macOS-only AudioHardware
	# device APIs. Keep the API library available so RPCS3 can fall back to
	# its NullAudioBackend until Cubeb has a complete AVAudioSession path.
	set(USE_AUDIOUNIT OFF CACHE BOOL "Disable Cubeb's macOS AudioUnit backend on iOS" FORCE)
endif()

add_subdirectory(cubeb EXCLUDE_FROM_ALL)
add_library(3rdparty::cubeb ALIAS cubeb)

if (CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm|ARM|aarch64|AArch64|Aarch64)")
	target_compile_definitions(speex PUBLIC
		#_USE_NEON
	)
elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86|X86|amd64|AMD64|em64t|EM64T)")
	target_compile_definitions(speex PUBLIC
		_USE_SSE
		_USE_SSE2
	)
endif ()
