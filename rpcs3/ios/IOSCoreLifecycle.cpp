#include "IOSCoreLifecycle.h"
#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"
#include "platform/IOSPlatform.h"

#include <atomic>
#include <string>

namespace
{
enum core_pause_reason : unsigned int
{
    pause_reason_inactive = 1u << 0,
    pause_reason_audio = 1u << 1,
};

std::atomic_uint g_pause_reasons = 0;
std::atomic_bool g_core_performed_pause = false;
std::atomic_bool g_application_active = true;

bool pause_required()
{
    return g_pause_reasons.load(std::memory_order_acquire) != 0;
}

void pause_for_reason(unsigned int reason)
{
    g_pause_reasons.fetch_or(reason, std::memory_order_acq_rel);
    if (!rpcs3::ios::try_core_lifecycle_pause_after_run())
    {
        rpcs3::ios::schedule_core_lifecycle_pause_after_run();
    }
}

void resume_after_reason(unsigned int reason)
{
    const unsigned int previous = g_pause_reasons.fetch_and(~reason, std::memory_order_acq_rel);
    if ((previous & reason) == 0 || (previous & ~reason) != 0)
    {
        return;
    }

    if (!rpcs3::ios::try_core_lifecycle_resume_after_reasons())
    {
        rpcs3::ios::schedule_core_lifecycle_resume_after_reasons();
    }
}
}

namespace rpcs3::ios
{
void install_core_lifecycle_callbacks()
{
    g_pause_reasons.store(0, std::memory_order_release);
    g_core_performed_pause.store(false, std::memory_order_release);
    g_application_active.store(true, std::memory_order_release);

    set_lifecycle_callbacks({
        .will_resign_active = []
        {
            g_application_active.store(false, std::memory_order_release);
            pause_for_reason(pause_reason_inactive);
        },
        .did_become_active = []
        {
            g_application_active.store(true, std::memory_order_release);
            resume_after_reason(pause_reason_inactive);
        },
        .did_enter_background = []
        {
            g_application_active.store(false, std::memory_order_release);
            pause_for_reason(pause_reason_inactive);
        },
        .will_enter_foreground = [] {},
        .audio_interruption_began = [] { pause_for_reason(pause_reason_audio); },
        .audio_interruption_ended = []
        {
            std::string error;
            if (!configure_audio_session(false, false, &error) && !error.empty())
            {
                set_core_last_error("Audio session recovery failed: " + error);
            }
            resume_after_reason(pause_reason_audio);
        },
        .controller_configuration_changed = [] {},
    });
}

void remove_core_lifecycle_callbacks()
{
    set_lifecycle_callbacks({});
    g_pause_reasons.store(0, std::memory_order_release);
    g_core_performed_pause.store(false, std::memory_order_release);
    g_application_active.store(false, std::memory_order_release);
}

bool core_lifecycle_allows_boot()
{
    return g_application_active.load(std::memory_order_acquire) && !pause_required();
}

void enforce_core_lifecycle_pause_after_run()
{
    // BootGame may invoke on_run while holding the emulator API mutex. Defer the
    // pause request so it can acquire public operation admission after boot
    // leaves that critical section instead of recursively locking the mutex.
    if (pause_required())
    {
        schedule_core_lifecycle_pause_after_run();
    }
}

bool try_core_lifecycle_pause_after_run()
{
    if (!pause_required())
    {
        return true;
    }

    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    if (state == RPCS3_IOS_EMULATOR_PAUSED)
    {
        // A manual pause already satisfies the lifecycle requirement. Do not
        // claim ownership because the lifecycle layer must not resume it later.
        return true;
    }
    if (state == RPCS3_IOS_EMULATOR_STOPPED || state == RPCS3_IOS_EMULATOR_UNAVAILABLE)
    {
        return true;
    }
    if (state != RPCS3_IOS_EMULATOR_RUNNING)
    {
        return false;
    }

    const rpcs3_ios_core_result result = rpcs3_ios_core_pause();
    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        g_core_performed_pause.store(true, std::memory_order_release);
        return true;
    }

    // BUSY means another admitted operation briefly won the gate. Retry after
    // it leaves instead of losing the inactive/audio pause request.
    return result != RPCS3_IOS_CORE_BUSY;
}

bool try_core_lifecycle_resume_after_reasons()
{
    if (pause_required())
    {
        return true;
    }
    if (!g_core_performed_pause.load(std::memory_order_acquire))
    {
        return true;
    }

    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    if (state == RPCS3_IOS_EMULATOR_RUNNING ||
        state == RPCS3_IOS_EMULATOR_STOPPED ||
        state == RPCS3_IOS_EMULATOR_UNAVAILABLE)
    {
        // The title was resumed or stopped independently. Release only the
        // lifecycle layer's ownership marker; never force another transition.
        g_core_performed_pause.store(false, std::memory_order_release);
        return true;
    }
    if (state != RPCS3_IOS_EMULATOR_PAUSED)
    {
        return false;
    }

    const rpcs3_ios_core_result result = rpcs3_ios_core_resume();
    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        g_core_performed_pause.store(false, std::memory_order_release);
        return true;
    }

    // Keep ownership while admission is BUSY so the next retry can complete the
    // matching resume. A permanent error stops the bounded retry chain without
    // falsely claiming that a future lifecycle event still owns the pause.
    if (result != RPCS3_IOS_CORE_BUSY)
    {
        g_core_performed_pause.store(false, std::memory_order_release);
        return true;
    }
    return false;
}
}
