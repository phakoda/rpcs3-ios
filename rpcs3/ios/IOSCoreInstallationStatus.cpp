#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>

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
}

namespace
{
std::mutex g_status_mutex;
rpcs3_ios_installation_status g_status{
    sizeof(rpcs3_ios_installation_status),
    0,
    0,
    RPCS3_IOS_INSTALLATION_FIRMWARE,
    RPCS3_IOS_INSTALLATION_VALIDATING,
    0,
    0,
};
std::string g_detail;
thread_local std::string g_detail_copy;

struct callback_context
{
    rpcs3_ios_installation_progress_callback callback = nullptr;
    void* context = nullptr;
};

bool begin_operation(rpcs3_ios_installation_kind kind, std::string detail)
{
    std::lock_guard lock(g_status_mutex);
    if (g_status.active)
    {
        return false;
    }

    g_status = {
        sizeof(rpcs3_ios_installation_status),
        1,
        0,
        static_cast<uint32_t>(kind),
        RPCS3_IOS_INSTALLATION_VALIDATING,
        0,
        0,
    };
    g_detail = std::move(detail);
    return true;
}

void finish_operation(rpcs3_ios_core_result result)
{
    std::lock_guard lock(g_status_mutex);
    g_status.active = 0;

    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        g_status.stage = RPCS3_IOS_INSTALLATION_COMPLETE;
        if (g_status.total && g_status.completed < g_status.total)
        {
            g_status.completed = g_status.total;
        }
        if (g_detail.empty())
        {
            g_detail = "Installation completed.";
        }
        return;
    }

    if (result == RPCS3_IOS_CORE_CANCELLED)
    {
        g_status.cancel_requested = 1;
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

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_install_firmware(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    if (!begin_operation(
            RPCS3_IOS_INSTALLATION_FIRMWARE,
            "Preparing PlayStation 3 firmware installation."))
    {
        rpcs3::ios::set_core_last_error("Another RPCS3Core installation operation is already active.");
        return RPCS3_IOS_CORE_BUSY;
    }

    callback_context callback_state{callback, context};
    const rpcs3_ios_core_result result = rpcs3_ios_core_install_firmware_base(
        pup_path,
        allow_downgrade,
        overwrite_existing,
        progress_trampoline,
        &callback_state);
    finish_operation(result);
    return result;
}

rpcs3_ios_core_result rpcs3_ios_core_install_package(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    if (!begin_operation(
            RPCS3_IOS_INSTALLATION_PACKAGE,
            "Preparing PlayStation 3 package installation."))
    {
        rpcs3::ios::set_core_last_error("Another RPCS3Core installation operation is already active.");
        return RPCS3_IOS_CORE_BUSY;
    }

    callback_context callback_state{callback, context};
    const rpcs3_ios_core_result result = rpcs3_ios_core_install_package_base(
        package_path,
        progress_trampoline,
        &callback_state);
    finish_operation(result);
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
}
