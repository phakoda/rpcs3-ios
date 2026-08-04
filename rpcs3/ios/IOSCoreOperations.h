#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios
{
enum class core_operation : std::uint32_t
{
    none = 0,
    initialize,
    shutdown,
    boot,
    restart,
    pause,
    resume,
    stop,
    install_firmware,
    install_package,
    library,
    settings,
    midi,
    render_host,
};

class core_operation_scope final
{
public:
    core_operation_scope(core_operation operation, std::string* error = nullptr);
    ~core_operation_scope();

    core_operation_scope(const core_operation_scope&) = delete;
    core_operation_scope& operator=(const core_operation_scope&) = delete;

    core_operation_scope(core_operation_scope&& other) noexcept;
    core_operation_scope& operator=(core_operation_scope&& other) noexcept;

    explicit operator bool() const noexcept;
    bool acquired() const noexcept;

private:
    core_operation m_operation = core_operation::none;
    bool m_acquired = false;
};

const char* core_operation_name(core_operation operation) noexcept;
core_operation active_core_operation() noexcept;
std::uint64_t active_core_operation_generation() noexcept;
bool core_operation_owned_by_current_thread() noexcept;
}
