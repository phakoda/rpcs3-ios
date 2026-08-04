#include "IOSCoreLifecycle.h"

#import <Foundation/Foundation.h>

#include <atomic>

namespace
{
std::atomic_bool g_pause_retry_active = false;
std::atomic_bool g_resume_retry_active = false;

void schedule_pause_attempt(unsigned int remaining_attempts)
{
    if (!remaining_attempts)
    {
        g_pause_retry_active.store(false, std::memory_order_release);
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (rpcs3::ios::try_core_lifecycle_pause_after_run())
            {
                g_pause_retry_active.store(false, std::memory_order_release);
            }
            else
            {
                schedule_pause_attempt(remaining_attempts - 1);
            }
        });
}

void schedule_resume_attempt(unsigned int remaining_attempts)
{
    if (!remaining_attempts)
    {
        g_resume_retry_active.store(false, std::memory_order_release);
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (rpcs3::ios::try_core_lifecycle_resume_after_reasons())
            {
                g_resume_retry_active.store(false, std::memory_order_release);
            }
            else
            {
                schedule_resume_attempt(remaining_attempts - 1);
            }
        });
}
}

namespace rpcs3::ios
{
void schedule_core_lifecycle_pause_after_run()
{
    // A bounded five-second retry window covers BootGame teardown and temporary
    // operation-gate contention. Multiple lifecycle notifications share one
    // retry chain instead of producing unbounded main-queue work.
    if (!g_pause_retry_active.exchange(true, std::memory_order_acq_rel))
    {
        schedule_pause_attempt(100);
    }
}

void schedule_core_lifecycle_resume_after_reasons()
{
    // Resume uses the same bounded admission retry. Ownership of a lifecycle
    // pause is retained until resume succeeds or the title independently leaves
    // the paused state.
    if (!g_resume_retry_active.exchange(true, std::memory_order_acq_rel))
    {
        schedule_resume_attempt(100);
    }
}
}
