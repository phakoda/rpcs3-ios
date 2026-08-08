#include "IOSCoreOperations.h"

#include <mutex>
#include <thread>
#include <utility>

namespace
{
std::mutex g_operation_mutex;
rpcs3::ios::core_operation g_active_operation = rpcs3::ios::core_operation::none;
std::thread::id g_operation_owner;
std::uint64_t g_operation_generation = 0;

bool begin_operation(rpcs3::ios::core_operation operation, std::string* error)
{
    std::lock_guard lock(g_operation_mutex);
    if (g_active_operation != rpcs3::ios::core_operation::none)
    {
        if (error)
        {
            *error = std::string("RPCS3Core cannot begin ") +
                rpcs3::ios::core_operation_name(operation) +
                " while " + rpcs3::ios::core_operation_name(g_active_operation) +
                " is active.";
            if (g_operation_owner == std::this_thread::get_id())
            {
                *error += " Reentrant state mutation is not permitted.";
            }
        }
        return false;
    }

    g_active_operation = operation;
    g_operation_owner = std::this_thread::get_id();
    ++g_operation_generation;
    return true;
}

void end_operation(rpcs3::ios::core_operation operation)
{
    std::lock_guard lock(g_operation_mutex);
    if (g_active_operation == operation && g_operation_owner == std::this_thread::get_id())
    {
        g_active_operation = rpcs3::ios::core_operation::none;
        g_operation_owner = {};
    }
}
}

namespace rpcs3::ios
{
core_operation_scope::core_operation_scope(core_operation operation, std::string* error)
    : m_operation(operation)
    , m_acquired(begin_operation(operation, error))
{
}

core_operation_scope::~core_operation_scope()
{
    if (m_acquired)
    {
        end_operation(m_operation);
    }
}

core_operation_scope::core_operation_scope(core_operation_scope&& other) noexcept
    : m_operation(std::exchange(other.m_operation, core_operation::none))
    , m_acquired(std::exchange(other.m_acquired, false))
{
}

core_operation_scope& core_operation_scope::operator=(core_operation_scope&& other) noexcept
{
    if (this == &other)
    {
        return *this;
    }
    if (m_acquired)
    {
        end_operation(m_operation);
    }
    m_operation = std::exchange(other.m_operation, core_operation::none);
    m_acquired = std::exchange(other.m_acquired, false);
    return *this;
}

core_operation_scope::operator bool() const noexcept
{
    return m_acquired;
}

bool core_operation_scope::acquired() const noexcept
{
    return m_acquired;
}

const char* core_operation_name(core_operation operation) noexcept
{
    switch (operation)
    {
    case core_operation::none: return "no operation";
    case core_operation::initialize: return "initialization";
    case core_operation::shutdown: return "shutdown";
    case core_operation::boot: return "boot";
    case core_operation::restart: return "restart";
    case core_operation::pause: return "pause";
    case core_operation::resume: return "resume";
    case core_operation::stop: return "stop";
    case core_operation::install_firmware: return "firmware installation";
    case core_operation::install_package: return "package installation";
    case core_operation::library: return "game-library mutation";
    case core_operation::settings: return "settings mutation";
    case core_operation::midi: return "MIDI mutation";
    case core_operation::render_host: return "render-host mutation";
    case core_operation::import_item: return "security-scoped import";
    }
    return "unknown operation";
}

core_operation active_core_operation() noexcept
{
    std::lock_guard lock(g_operation_mutex);
    return g_active_operation;
}

std::uint64_t active_core_operation_generation() noexcept
{
    std::lock_guard lock(g_operation_mutex);
    return g_operation_generation;
}

bool core_operation_owned_by_current_thread() noexcept
{
    std::lock_guard lock(g_operation_mutex);
    return g_active_operation != core_operation::none &&
        g_operation_owner == std::this_thread::get_id();
}
}
