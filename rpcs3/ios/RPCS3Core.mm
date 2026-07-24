#include "RPCS3Core.h"
#include "IOSCoreDefaults.h"
#include "IOSCoreEmulator.h"
#include "platform/IOSPlatform.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>

namespace rpcs3::ios
{
int core_port_anchor();
}

namespace
{
std::atomic_bool g_initialized = false;
std::mutex g_core_mutex;

thread_local std::string g_application_support_path;
thread_local std::string g_caches_path;
thread_local std::string g_documents_path;
thread_local std::string g_imports_path;
thread_local std::string g_temporary_path;
thread_local std::string g_jit_detail;
thread_local std::string g_diagnostics;
thread_local std::string g_error_copy;

size_t copy_string(const std::string& value, char* buffer, size_t buffer_size)
{
    const size_t required = value.size() + 1;
    if (!buffer || buffer_size == 0)
    {
        return required;
    }

    const size_t copied = std::min(value.size(), buffer_size - 1);
    std::memcpy(buffer, value.data(), copied);
    buffer[copied] = '\0';
    return required;
}

const char* refresh_path(std::string& storage, const std::string& value)
{
    storage = value;
    return storage.c_str();
}

rpcs3_ios_core_result fail_initialization(std::string error)
{
    rpcs3::ios::shutdown_core_emulator();
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::set_external_display_callback({});
    rpcs3::ios::set_performance_callback({});
    rpcs3::ios::set_lifecycle_callbacks({});
    rpcs3::ios::shutdown();
    rpcs3::ios::set_core_last_error(std::move(error));
    return RPCS3_IOS_CORE_PLATFORM_ERROR;
}
}

extern "C"
{
double RPCS3CoreVersionNumber = 0.2;
const unsigned char RPCS3CoreVersionString[] = "RPCS3Core 0.2";

rpcs3_ios_core_result rpcs3_ios_core_initialize(void)
{
    std::lock_guard lock(g_core_mutex);
    if (g_initialized.load())
    {
        return RPCS3_IOS_CORE_ALREADY_INITIALIZED;
    }

    rpcs3::ios::configure_moltenvk({});
    rpcs3::ios::initialize();
    rpcs3::ios::apply_core_compatibility_defaults();

    std::string error;
    if (!rpcs3::ios::prepare_runtime_directories(&error))
    {
        return fail_initialization(error.empty()
            ? "Could not prepare the RPCS3 iOS runtime directories."
            : std::move(error));
    }

    if (rpcs3::ios::core_port_anchor() != 0)
    {
        return fail_initialization("The RPCS3 iOS core anchor could not resolve its Application Support path.");
    }

    if (!rpcs3::ios::initialize_core_emulator(&error))
    {
        return fail_initialization(error.empty()
            ? "Could not initialize the RPCS3 emulator object."
            : std::move(error));
    }

    rpcs3::ios::set_core_last_error({});
    g_initialized.store(true);
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_shutdown(void)
{
    std::lock_guard lock(g_core_mutex);
    if (!g_initialized.load())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }

    // Stop guest threads and destroy emulator-owned fixed objects before native
    // controller, display, audio, and notification services disappear.
    rpcs3::ios::shutdown_core_emulator();
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::set_external_display_callback({});
    rpcs3::ios::set_performance_callback({});
    rpcs3::ios::set_lifecycle_callbacks({});
    rpcs3::ios::shutdown();
    g_initialized.store(false);
    return RPCS3_IOS_CORE_SUCCESS;
}

uint8_t rpcs3_ios_core_is_initialized(void)
{
    return g_initialized.load() ? 1 : 0;
}

const char* rpcs3_ios_core_application_support_path(void)
{
    return refresh_path(g_application_support_path, rpcs3::ios::get_runtime_paths().application_support);
}

const char* rpcs3_ios_core_caches_path(void)
{
    return refresh_path(g_caches_path, rpcs3::ios::get_runtime_paths().caches);
}

const char* rpcs3_ios_core_documents_path(void)
{
    return refresh_path(g_documents_path, rpcs3::ios::get_runtime_paths().documents);
}

const char* rpcs3_ios_core_imports_path(void)
{
    return refresh_path(g_imports_path, rpcs3::ios::get_runtime_paths().imports);
}

const char* rpcs3_ios_core_temporary_path(void)
{
    return refresh_path(g_temporary_path, rpcs3::ios::get_runtime_paths().temporary);
}

rpcs3_ios_jit_status rpcs3_ios_core_query_jit_status(void)
{
    const rpcs3::ios::jit_capabilities capabilities = rpcs3::ios::query_extended_jit_capabilities();
    return {
        static_cast<uint8_t>(capabilities.map_jit_available),
        static_cast<uint8_t>(capabilities.map_jit_allocation_succeeded),
        static_cast<uint8_t>(capabilities.jit_write_protect_available),
        static_cast<uint8_t>(capabilities.dynamic_codesigning_entitlement),
        static_cast<uint8_t>(capabilities.allow_jit_entitlement),
        static_cast<uint8_t>(capabilities.debugger_entitlement),
        static_cast<uint8_t>(capabilities.increased_memory_limit_entitlement),
        static_cast<uint8_t>(capabilities.extended_virtual_addressing_entitlement),
        static_cast<uint8_t>(capabilities.process_is_debugged),
    };
}

rpcs3_ios_performance_status rpcs3_ios_core_query_performance_status(void)
{
    const rpcs3::ios::performance_state state = rpcs3::ios::get_performance_state();
    return {
        static_cast<uint32_t>(state.thermal),
        static_cast<uint32_t>(state.memory_pressure),
        static_cast<uint8_t>(state.low_power_mode),
        state.physical_memory,
        state.available_memory,
    };
}

size_t rpcs3_ios_core_copy_jit_detail(char* buffer, size_t buffer_size)
{
    g_jit_detail = rpcs3::ios::query_extended_jit_capabilities().detail;
    return copy_string(g_jit_detail, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_diagnostics(char* buffer, size_t buffer_size)
{
    g_diagnostics = rpcs3::ios::build_diagnostics_report();
    return copy_string(g_diagnostics, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_last_error(char* buffer, size_t buffer_size)
{
    g_error_copy = rpcs3::ios::get_core_last_error();
    return copy_string(g_error_copy, buffer, buffer_size);
}

void rpcs3_ios_core_configure_moltenvk_defaults(void)
{
    rpcs3::ios::configure_moltenvk({});
}
}
