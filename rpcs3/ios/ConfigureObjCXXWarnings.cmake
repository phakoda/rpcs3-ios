# Xcode may route C++ and Objective-C++ warning settings through shared build
# settings. Apply the old-style-cast exception at source granularity so UIKit,
# Foundation, and CoreMIDI bridge translation units remain warning-clean without
# relaxing RPCS3's ordinary C++ sources.

foreach(_rpcs3_ios_objcxx_target
    rpcs3_ios_core_framework
    rpcs3_ios_core_link)
    if(NOT TARGET ${_rpcs3_ios_objcxx_target})
        continue()
    endif()

    get_target_property(_rpcs3_ios_objcxx_sources ${_rpcs3_ios_objcxx_target} SOURCES)
    if(NOT _rpcs3_ios_objcxx_sources)
        continue()
    endif()

    foreach(_rpcs3_ios_objcxx_source IN LISTS _rpcs3_ios_objcxx_sources)
        if(_rpcs3_ios_objcxx_source MATCHES "\\.mm$")
            set_source_files_properties("${_rpcs3_ios_objcxx_source}" PROPERTIES
                COMPILE_OPTIONS "-Wno-error=old-style-cast")
        endif()
    endforeach()
endforeach()
