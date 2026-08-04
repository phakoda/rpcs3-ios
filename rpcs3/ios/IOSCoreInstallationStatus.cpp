#include "IOSCoreEmulator.h"
#include "IOSCoreOperations.h"
#include "RPCS3Core.h"
#include "RPCS3CoreStatus.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_install_firmware_base(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
rpcs3_ios_core_result rpcs3_ios_core_install_package_base(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel_base(void);
size_t rpcs3_ios_core_copy_last_installed_path_base(char* buffer, size_t buffer_size);
}

namespace
{
std::mutex g_status_mutex;
rpcs3_ios_installation_status_v2 g_status{
    sizeof(rpcs3_ios_installation_status_v2),
    0,
    0,
    RPCS3_IOS_INSTALLATION_FIRMWARE,
    RPCS3_IOS_INSTALLATION_VALIDATING,
    0,
    0,
    RPCS3_IOS_INSTALLATION_TERMINAL_NONE,
    RPCS3_IOS_CORE_SUCCESS,
    0,
};
std::uint64_t g_next_operation_id = 0;
std::string g_detail;
std::string g_last_installed_path;
thread_local std::string g_detail_copy;
thread_local std::string g_installed_path_copy;

struct callback_context
{
    rpcs3_ios_installation_progress_callback callback = nullptr;
    void* context = nullptr;
};

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

std::string copy_base_string(size_t (*copy_function)(char*, size_t))
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

void begin_status(rpcs3_ios_installation_kind kind, std::string detail)
{
    std::lock_guard lock(g_status_mutex);
    g_status = {
        sizeof(rpcs3_ios_installation_status_v2),
        1,
        0,
        static_cast<uint32_t>(kind),
        RPCS3_IOS_INSTALLATION_VALIDATING,
        0,
        0,
        RPCS3_IOS_INSTALLATION_TERMINAL_NONE,
        RPCS3_IOS_CORE_SUCCESS,
        ++g_next_operation_id,
    };
    g_detail = std::move(detail);
    g_last_installed_path.clear();
}

void finish_status(rpcs3_ios_core_result result)
{
    std::string installed_path;
    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        installed_path = copy_base_string(rpcs3_ios_core_copy_last_installed_path_base);
    }

    std::lock_guard lock(g_status_mutex);
    g_status.active = 0;
    g_status.result = static_cast<uint32_t>(result);

    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        g_status.stage = RPCS3_IOS_INSTALLATION_COMPLETE;
        g_status.terminal_state = RPCS3_IOS_INSTALLATION_TERMINAL_SUCCEEDED;
        if (g_status.total && g_status.completed < g_status.total)
        {
            g_status.completed = g_status.total;
        }
        if (g_detail.empty())
        {
            g_detail = "Installation completed.";
        }
        g_last_installed_path = std::move(installed_path);
        return;
    }

    if (result == RPCS3_IOS_CORE_CANCELLED)
    {
        g_status.cancel_requested = 1;
        g_status.terminal_state = RPCS3_IOS_INSTALLATION_TERMINAL_CANCELLED;
    }
    else
    {
        g_status.terminal_state = RPCS3_IOS_INSTALLATION_TERMINAL_FAILED;
    }

    const std::string error = rpcs3::ios::get_core_last_error();
    if (!error.empty())
    {
        g_detail = error;
    }
}

void progress_trampoline(
    rpcs3_ios_installation_kind kind,
    rpcs3_ios_installation_stage stage,
    uint32_t completed,
    uint32_t total,
    const char* detail,
    void* opaque)
{
    auto* callback = static_cast<callback_context*>(opaque);
    {
        std::lock_guard lock(g_status_mutex);
        g_status.kind = static_cast<uint32_t>(kind);
        g_status.stage = static_cast<uint32_t>(stage);
        g_status.completed = completed;
        g_status.total = total;
        g_detail = detail ? detail : "";
    }

    if (callback && callback->callback)
    {
        callback->callback(kind, stage, completed, total, detail ? detail : "", callback->context);
    }
}

rpcs3::ios::core_operation operation_for(rpcs3_ios_installation_kind kind)
{
    return kind == RPCS3_IOS_INSTALLATION_PACKAGE
        ? rpcs3::ios::core_operation::install_package
        : rpcs3::ios::core_operation::install_firmware;
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_install_firmware(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    std::string admission_error;
    rpcs3::ios::core_operation_scope operation(
        operation_for(RPCS3_IOS_INSTALLATION_FIRMWARE), &admission_error);
    if (!operation)
    {
        rpcs3::ios::set_core_last_error(std::move(admission_error));
        return RPCS3_IOS_CORE_BUSY;
    }

    begin_status(RPCS3_IOS_INSTALLATION_FIRMWARE,
        "Preparing PlayStation 3 firmware installation.");
    callback_context callback_state{callback, context};
    const rpcs3_ios_core_result result = rpcs3_ios_core_install_firmware_base(
        pup_path,
        allow_downgrade,
        overwrite_existing,
        progress_trampoline,
        &callback_state);
    finish_status(result);
    return result;
}

rpcs3_ios_core_result rpcs3_ios_core_install_package(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    std::string admission_error;
    rpcs3::ios::core_operation_scope operation(
        operation_for(RPCS3_IOS_INSTALLATION_PACKAGE), &admission_error);
    if (!operation)
    {
        rpcs3::ios::set_core_last_error(std::move(admission_error));
        return RPCS3_IOS_CORE_BUSY;
    }

    begin_status(RPCS3_IOS_INSTALLATION_PACKAGE,
        "Preparing PlayStation 3 package installation.");
    callback_context callback_state{callback, context};
    const rpcs3_ios_core_result result = rpcs3_ios_core_install_package_base(
        package_path,
        progress_trampoline,
        &callback_state);
    finish_status(result);
    return result;
}

rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel(void)
{
    {
        std::lock_guard lock(g_status_mutex);
        if (g_status.active)
        {
            g_status.cancel_requested = 1;
            g_detail = "Cancellation requested.";
        }
    }
    return rpcs3_ios_core_request_installation_cancel_base();
}

rpcs3_ios_installation_status rpcs3_ios_core_query_installation_status(void)
{
    std::lock_guard lock(g_status_mutex);
    return {
        sizeof(rpcs3_ios_installation_status),
        g_status.active,
        g_status.cancel_requested,
        g_status.kind,
        g_status.stage,
        g_status.completed,
        g_status.total,
    };
}

rpcs3_ios_installation_status_v2 rpcs3_ios_core_query_installation_status_v2(void)
{
    std::lock_guard lock(g_status_mutex);
    return g_status;
}

size_t rpcs3_ios_core_copy_installation_detail(char* buffer, size_t buffer_size)
{
    {
        std::lock_guard lock(g_status_mutex);
        g_detail_copy = g_detail;
    }
    return copy_string(g_detail_copy, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_last_installed_path(char* buffer, size_t buffer_size)
{
    {
        std::lock_guard lock(g_status_mutex);
        g_installed_path_copy = g_last_installed_path;
    }
    return copy_string(g_installed_path_copy, buffer, buffer_size);
}
}
