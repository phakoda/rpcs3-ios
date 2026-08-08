#include "RPCS3Core.h"
#include "IOSCoreDefaults.h"
#include "IOSCoreEmulator.h"
#include "IOSCoreGSFrame.h"
#include "IOSCoreInstaller.h"
#include "IOSCoreLifecycle.h"
#include "IOSCoreSettings.h"
#include "platform/IOSPlatform.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace rpcs3::ios
{
int core_port_anchor();
}

namespace
{
std::atomic_bool g_initialized = false;
std::mutex g_core_mutex;
std::mutex g_import_mutex;
std::string g_pending_import_source;
std::string g_pending_import_path;

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

std::string read_public_string(size_t (*copy_function)(char*, size_t))
{
    const size_t required = copy_function(nullptr, 0);
    if (!required)
    {
        return {};
    }

    std::vector<char> buffer(required);
    copy_function(buffer.data(), buffer.size());
    return buffer.data();
}

std::string copy_registered_directory(size_t index)
{
    size_t required = 0;
    if (rpcs3_ios_core_copy_game_directory(index, nullptr, 0, &required) !=
        RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {};
    }

    std::vector<char> buffer(std::max<size_t>(required, 1));
    return rpcs3_ios_core_copy_game_directory(
        index, buffer.data(), buffer.size(), &required) == RPCS3_IOS_CORE_SUCCESS
        ? std::string(buffer.data())
        : std::string{};
}

std::string copy_midi_assignment_name(uint32_t slot, uint32_t* type)
{
    size_t required = 0;
    uint32_t assignment_type = RPCS3_IOS_MIDI_KEYBOARD;
    if (rpcs3_ios_core_copy_midi_assignment(
            slot, &assignment_type, nullptr, 0, &required) != RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        if (type)
        {
            *type = assignment_type;
        }
        return {};
    }

    std::vector<char> buffer(std::max<size_t>(required, 1));
    const rpcs3_ios_core_result result = rpcs3_ios_core_copy_midi_assignment(
        slot, &assignment_type, buffer.data(), buffer.size(), &required);
    if (type)
    {
        *type = assignment_type;
    }
    return result == RPCS3_IOS_CORE_SUCCESS ? std::string(buffer.data()) : std::string{};
}

const char* midi_type_name(uint32_t type)
{
    switch (type)
    {
    case RPCS3_IOS_MIDI_KEYBOARD: return "Keyboard";
    case RPCS3_IOS_MIDI_GUITAR_17_FRET: return "Guitar (17 frets)";
    case RPCS3_IOS_MIDI_GUITAR_22_FRET: return "Guitar (22 frets)";
    case RPCS3_IOS_MIDI_DRUMS: return "Drums";
    default: return "Unknown";
    }
}

std::string build_core_diagnostics_extension()
{
    const std::string previous_error = rpcs3::ios::get_core_last_error();
    std::ostringstream report;
    report << "\nRPCS3Core.framework\n";
    report << "Version: " << RPCS3CoreVersionString << "\n";
    report << "Initialized: " << (g_initialized.load() ? "yes" : "no") << "\n";
    report << "Render view: " << (rpcs3::ios::has_core_render_view() ? "attached" : "headless") << "\n";
    report << "Game mappings: " << rpcs3_ios_core_game_count() << "\n";

    const size_t directory_count = rpcs3_ios_core_game_directory_count();
    report << "Persistent game roots: " << directory_count << "\n";
    for (size_t index = 0; index < directory_count; ++index)
    {
        const std::string path = copy_registered_directory(index);
        report << "  Root " << (index + 1) << ": "
               << (path.empty() ? "<unavailable>" : path) << "\n";
    }

    report << "CoreMIDI sources: " << rpcs3_ios_core_midi_source_count() << "\n";
    if (g_initialized.load())
    {
        const size_t slot_count = rpcs3_ios_core_midi_slot_count();
        for (uint32_t slot = 0; slot < slot_count; ++slot)
        {
            uint32_t type = RPCS3_IOS_MIDI_KEYBOARD;
            const std::string source = copy_midi_assignment_name(slot, &type);
            report << "  MIDI slot " << (slot + 1) << ": " << midi_type_name(type)
                   << " / " << (source.empty() ? "None" : source) << "\n";
        }
    }

    const rpcs3_ios_installation_status installation = rpcs3_ios_core_query_installation_status();
    report << "Installer active: " << (installation.active ? "yes" : "no") << "\n";
    report << "Installer cancel requested: " << (installation.cancel_requested ? "yes" : "no") << "\n";
    report << "Installer kind: "
           << (installation.kind == RPCS3_IOS_INSTALLATION_PACKAGE ? "package" : "firmware") << "\n";
    report << "Installer stage: " << installation.stage << "\n";
    report << "Installer progress: " << installation.completed << "/" << installation.total << "\n";
    const std::string detail = read_public_string(rpcs3_ios_core_copy_installation_detail);
    report << "Installer detail: " << (detail.empty() ? "<none>" : detail) << "\n";

    rpcs3::ios::set_core_last_error(previous_error);
    return report.str();
}

const char* refresh_path(std::string& storage, const std::string& value)
{
    storage = value;
    return storage.c_str();
}

void clear_pending_import()
{
    std::lock_guard lock(g_import_mutex);
    g_pending_import_source.clear();
    g_pending_import_path.clear();
}

bool renderer_mutation_allowed()
{
    if (!g_initialized.load())
    {
        return true;
    }

    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    return state == RPCS3_IOS_EMULATOR_STOPPED || state == RPCS3_IOS_EMULATOR_UNAVAILABLE;
}

rpcs3_ios_core_result fail_initialization(std::string error)
{
    clear_pending_import();
    rpcs3::ios::shutdown_core_installer();
    rpcs3::ios::remove_core_lifecycle_callbacks();
    rpcs3::ios::shutdown_core_emulator();
    rpcs3::ios::clear_core_render_view();
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::set_external_display_callback({});
    rpcs3::ios::set_performance_callback({});
    rpcs3::ios::shutdown();
    rpcs3::ios::set_core_last_error(std::move(error));
    return RPCS3_IOS_CORE_PLATFORM_ERROR;
}
}

extern "C"
{
double RPCS3CoreVersionNumber = 0.4;
const unsigned char RPCS3CoreVersionString[] = "RPCS3Core 0.4";

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
    rpcs3::ios::load_core_configuration();

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

    rpcs3::ios::install_core_lifecycle_callbacks();
    clear_pending_import();
    rpcs3::ios::set_core_last_error({});
    g_initialized.store(true);
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_shutdown(void)
{
    std::lock_guard lock(g_core_mutex);
    if (!g_initialized.exchange(false))
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }

    // Close admission before cancelling and draining framework-owned file
    // operations. No new importer, installer, library, or boot operation can
    // begin while guest, renderer, controller, display, audio, and notification
    // services are being torn down.
    rpcs3::ios::shutdown_core_installer();
    rpcs3::ios::remove_core_lifecycle_callbacks();
    rpcs3::ios::shutdown_core_emulator();
    rpcs3::ios::clear_core_render_view();
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::set_external_display_callback({});
    rpcs3::ios::set_performance_callback({});
    rpcs3::ios::shutdown();
    clear_pending_import();
    return RPCS3_IOS_CORE_SUCCESS;
}

uint8_t rpcs3_ios_core_is_initialized(void)
{
    return g_initialized.load() ? 1 : 0;
}

rpcs3_ios_core_result rpcs3_ios_core_set_render_view(void* native_view)
{
    if (!native_view)
    {
        rpcs3::ios::set_core_last_error("A non-null CAMetalLayer-backed UIView is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!renderer_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("The render view can be changed only while emulation is stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::string error;
    if (!rpcs3::ios::set_core_render_view(native_view, &error))
    {
        rpcs3::ios::set_core_last_error(error.empty() ? "Could not attach the render view." : error);
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    // Keep both RPCS3 headless state holders and the configured renderer in
    // sync immediately rather than waiting until the next boot request.
    rpcs3::ios::apply_core_compatibility_defaults();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_clear_render_view(void)
{
    if (!renderer_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("The render view can be cleared only while emulation is stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    rpcs3::ios::clear_core_render_view();
    rpcs3::ios::apply_core_compatibility_defaults();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

uint8_t rpcs3_ios_core_has_render_view(void)
{
    return rpcs3::ios::has_core_render_view() ? 1 : 0;
}

void rpcs3_ios_core_refresh_render_view(void)
{
    rpcs3::ios::refresh_core_render_view();
}

rpcs3_ios_core_result rpcs3_ios_core_import_path(
    const char* source_path,
    char* imported_path,
    size_t imported_path_size,
    size_t* required_size)
{
    if (!g_initialized.load())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!source_path || !*source_path || !required_size)
    {
        rpcs3::ios::set_core_last_error("A source path and required-size output are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard import_lock(g_import_mutex);
    if (g_pending_import_source != source_path || g_pending_import_path.empty())
    {
        std::string stable_path;
        std::string error;
        if (!rpcs3::ios::import_item(source_path, &stable_path, &error))
        {
            g_pending_import_source.clear();
            g_pending_import_path.clear();
            rpcs3::ios::set_core_last_error(error.empty() ? "The selected item could not be imported." : error);
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        g_pending_import_source = source_path;
        g_pending_import_path = std::move(stable_path);
    }

    *required_size = g_pending_import_path.size() + 1;
    if (!imported_path || imported_path_size < *required_size)
    {
        // The item has already been copied. Keep the stable path cached so the
        // caller can retry with the reported size without importing it again.
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    std::memcpy(imported_path, g_pending_import_path.c_str(), *required_size);
    g_pending_import_source.clear();
    g_pending_import_path.clear();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
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
    g_diagnostics += build_core_diagnostics_extension();
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
