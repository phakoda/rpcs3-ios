#include "IOSCoreLifecycle.h"
#include "IOSRetryGeneration.h"

#import <Foundation/Foundation.h>

namespace
{
rpcs3::ios::retry_generation_latch g_pause_retry;
rpcs3::ios::retry_generation_latch g_resume_retry;

void schedule_pause_attempt(unsigned int remaining_attempts, std::uint64_t generation);
void schedule_resume_attempt(unsigned int remaining_attempts, std::uint64_t generation);

void finish_pause_attempt(std::uint64_t generation)
{
    const rpcs3::ios::retry_generation_completion completion =
        g_pause_retry.complete(generation);
    if (completion.should_restart)
    {
        schedule_pause_attempt(100, completion.generation);
    }
}

void finish_resume_attempt(std::uint64_t generation)
{
    const rpcs3::ios::retry_generation_completion completion =
        g_resume_retry.complete(generation);
    if (completion.should_restart)
    {
        schedule_resume_attempt(100, completion.generation);
    }
}

void schedule_pause_attempt(unsigned int remaining_attempts, std::uint64_t generation)
{
    if (!remaining_attempts)
    {
        finish_pause_attempt(generation);
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (rpcs3::ios::try_core_lifecycle_pause_after_run())
            {
                finish_pause_attempt(generation);
            }
            else
            {
                schedule_pause_attempt(remaining_attempts - 1, generation);
            }
        });
}

void schedule_resume_attempt(unsigned int remaining_attempts, std::uint64_t generation)
{
    if (!remaining_attempts)
    {
        finish_resume_attempt(generation);
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (rpcs3::ios::try_core_lifecycle_resume_after_reasons())
            {
                finish_resume_attempt(generation);
            }
            else
            {
                schedule_resume_attempt(remaining_attempts - 1, generation);
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
    // retry chain. A generation handoff preserves notifications that race with
    // the active chain's completion.
    const retry_generation_request request = g_pause_retry.request();
    if (request.should_start)
    {
        schedule_pause_attempt(100, request.generation);
    }
}

void schedule_core_lifecycle_resume_after_reasons()
{
    // Resume uses the same bounded admission retry. Ownership of a lifecycle
    // pause is retained until resume succeeds or the title independently leaves
    // the paused state. A concurrent request extends the retry work safely.
    const retry_generation_request request = g_resume_retry.request();
    if (request.should_start)
    {
        schedule_resume_attempt(100, request.generation);
    }
}
}
