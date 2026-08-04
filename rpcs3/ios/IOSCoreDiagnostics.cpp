#include "IOSCoreEmulator.h"
#include "IOSCoreGSFrame.h"
#include "RPCS3Core.h"
#include "RPCS3CoreStatus.h"

#include <algorithm>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

extern "C" size_t rpcs3_ios_core_copy_diagnostics_base(char* buffer, size_t buffer_size);

namespace
{
thread_local std::string g_extended_diagnostics;

std::string copy_base_diagnostics()
{
    const size_t required = rpcs3_ios_core_copy_diagnostics_base(nullptr, 0);
    if (!required)
    {
        return {};
    }
    std::vector<char> buffer(required);
    rpcs3_ios_core_copy_diagnostics_base(buffer.data(), buffer.size());
    return buffer.data();
}

size_t copy_string(const std::string& value, char* buffer, size_t buffer_size)
{
    const size_t required = value.size() + 1;
    if (!buffer || !buffer_size)
    {
        return required;
    }
    const size_t copied = std::min(value.size(), buffer_size - 1);
    std::memcpy(buffer, value.data(), copied);
    buffer[copied] = '\0';
    return required;
}
}

extern "C" size_t rpcs3_ios_core_copy_diagnostics(char* buffer, size_t buffer_size)
{
    const std::string previous_error = rpcs3::ios::get_core_last_error();
    g_extended_diagnostics = copy_base_diagnostics();

    const std::string old_version = "Version: RPCS3Core 0.4";
    if (const size_t position = g_extended_diagnostics.find(old_version); position != std::string::npos)
    {
        g_extended_diagnostics.replace(position, old_version.size(), "Version: RPCS3Core 0.5");
    }

    const rpcs3_ios_core_operation_status operation = rpcs3_ios_core_query_operation_status();
    const rpcs3_ios_installation_status_v2 installation = rpcs3_ios_core_query_installation_status_v2();
    const rpcs3_ios_core_capabilities capabilities = rpcs3_ios_core_query_capabilities();
    const rpcs3::ios::core_render_metrics render = rpcs3::ios::get_core_render_metrics();

    std::ostringstream report;
    report << "\nRPCS3Core 0.5 integration state\n";
    report << "API version: " << capabilities.api_major << "."
           << capabilities.api_minor << "." << capabilities.api_patch << "\n";
    report << "Capabilities: Vulkan=" << capabilities.has_vulkan
           << ", LLVM=" << capabilities.has_llvm
           << ", CoreMIDI=" << capabilities.has_coremidi
           << ", installers=" << capabilities.has_installers
           << ", native dialogs=" << capabilities.has_native_dialogs
           << ", physical USB passthrough=" << capabilities.has_physical_usb_passthrough << "\n";
    report << "Active operation: " << operation.active_operation
           << ", generation=" << operation.generation
           << ", owned by caller=" << operation.owned_by_calling_thread << "\n";
    report << "Render metrics: " << render.width << "x" << render.height
           << " @ " << render.refresh_rate << " Hz"
           << ", visible=" << (render.visible ? "yes" : "no")
           << ", drawable generation=" << render.generation << "\n";
    report << "CoreMIDI topology generation: "
           << rpcs3_ios_core_midi_topology_generation() << "\n";
    report << "Installer operation ID: " << installation.operation_id << "\n";
    report << "Installer terminal state: " << installation.terminal_state << "\n";
    report << "Installer result: " << installation.result << "\n";

    g_extended_diagnostics += report.str();
    rpcs3::ios::set_core_last_error(previous_error);
    return copy_string(g_extended_diagnostics, buffer, buffer_size);
}
