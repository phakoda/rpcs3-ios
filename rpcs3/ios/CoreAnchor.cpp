#include "platform/IOSPlatform.h"

namespace rpcs3::ios
{
// A concrete archive target gives Xcode and command-line builds a stable core
// milestone while pulling the complete rpcs3_emu dependency graph. The native
// frontend will eventually call into explicit emulator bootstrap APIs instead
// of relying on this anchor.
int core_port_anchor()
{
    const runtime_paths paths = get_runtime_paths();
    return paths.application_support.empty() ? 1 : 0;
}
}
