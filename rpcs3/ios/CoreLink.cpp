#include "platform/IOSPlatform.h"

namespace rpcs3::ios
{
int core_port_anchor();
}

// This executable is a link-completeness artifact, not an installable app. The
// CMake target force-loads every object from rpcs3_emu so unresolved core,
// dependency, Objective-C++, and Apple-framework symbols cannot hide inside a
// static archive. It intentionally performs no emulator workload.
int main()
{
    rpcs3::ios::configure_moltenvk({});
    rpcs3::ios::initialize();
    const int result = rpcs3::ios::core_port_anchor();
    rpcs3::ios::shutdown();
    return result;
}
