#include "IOSCoreEmulator.h"
#include "IOSCoreLifecycle.h"
#include "IOSCoreOperations.h"
#include "RPCS3Core.h"

#include <string>
#include <utility>

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_initialize_base(void);
rpcs3_ios_core_result rpcs3_ios_core_shutdown_base(void);
rpcs3_ios_core_result rpcs3_ios_core_set_render_view_base(void* native_view);
rpcs3_ios_core_result rpcs3_ios_core_clear_render_view_base(void);
rpcs3_ios_boot_result rpcs3_ios_core_boot_path_base(const char* path, uint8_t direct_boot);
rpcs3_ios_core_result rpcs3_ios_core_pause_base(void);
rpcs3_ios_core_result rpcs3_ios_core_resume_base(void);
rpcs3_ios_core_result rpcs3_ios_core_stop_base(void);
rpcs3_ios_boot_result rpcs3_ios_core_restart_base(void);
}

namespace
{
template <typename Result, typename Function>
Result run_core_operation(
    rpcs3::ios::core_operation operation,
    Result busy_result,
    Function&& function)
{
    std::string error;
    rpcs3::ios::core_operation_scope scope(operation, &error);
    if (!scope)
    {
        rpcs3::ios::set_core_last_error(std::move(error));
        return busy_result;
    }
    return function();
}

bool require_active_lifecycle()
{
    if (rpcs3::ios::core_lifecycle_allows_boot())
    {
        return true;
    }
    rpcs3::ios::set_core_last_error(
        "Booting is unavailable while the application is inactive, backgrounded, or handling an audio interruption.");
    return false;
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_initialize(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::initialize,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_initialize_base(); });
}

rpcs3_ios_core_result rpcs3_ios_core_shutdown(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::shutdown,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_shutdown_base(); });
}

rpcs3_ios_core_result rpcs3_ios_core_set_render_view(void* native_view)
{
    return run_core_operation(
        rpcs3::ios::core_operation::render_host,
        RPCS3_IOS_CORE_BUSY,
        [=] { return rpcs3_ios_core_set_render_view_base(native_view); });
}

rpcs3_ios_core_result rpcs3_ios_core_clear_render_view(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::render_host,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_clear_render_view_base(); });
}

rpcs3_ios_boot_result rpcs3_ios_core_boot_path(const char* path, uint8_t direct_boot)
{
    if (!require_active_lifecycle())
    {
        return RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED;
    }
    return run_core_operation(
        rpcs3::ios::core_operation::boot,
        RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED,
        [=] { return rpcs3_ios_core_boot_path_base(path, direct_boot); });
}

rpcs3_ios_core_result rpcs3_ios_core_pause(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::pause,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_pause_base(); });
}

rpcs3_ios_core_result rpcs3_ios_core_resume(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::resume,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_resume_base(); });
}

rpcs3_ios_core_result rpcs3_ios_core_stop(void)
{
    return run_core_operation(
        rpcs3::ios::core_operation::stop,
        RPCS3_IOS_CORE_BUSY,
        [] { return rpcs3_ios_core_stop_base(); });
}

rpcs3_ios_boot_result rpcs3_ios_core_restart(void)
{
    if (!require_active_lifecycle())
    {
        return RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED;
    }
    return run_core_operation(
        rpcs3::ios::core_operation::restart,
        RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED,
        [] { return rpcs3_ios_core_restart_base(); });
}
}
