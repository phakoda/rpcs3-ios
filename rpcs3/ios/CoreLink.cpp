#include "platform/IOSPlatform.h"

#include "Emu/System.h"
#include "Emu/system_config.h"

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

    const rpcs3::ios::runtime_paths paths = rpcs3::ios::get_runtime_paths();
    const bool configuration_available = &g_cfg != nullptr;
    const bool emulator_available = &Emu != nullptr;
    const int anchor_result = rpcs3::ios::core_port_anchor();

    rpcs3::ios::shutdown();
    return paths.application_support.empty() || !configuration_available ||
        !emulator_available || anchor_result != 0;
}
