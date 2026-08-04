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

void perform_pause_if_needed()
{
    if (g_pause_reasons.load(std::memory_order_acquire) == 0 ||
        rpcs3_ios_core_emulator_state() != RPCS3_IOS_EMULATOR_RUNNING)
    {
        return;
    }

    if (rpcs3_ios_core_pause() == RPCS3_IOS_CORE_SUCCESS)
    {
        g_core_performed_pause.store(true, std::memory_order_release);
    }
}

void pause_for_reason(unsigned int reason)
{
    g_pause_reasons.fetch_or(reason, std::memory_order_acq_rel);
    perform_pause_if_needed();
}

void resume_after_reason(unsigned int reason)
{
    const unsigned int previous = g_pause_reasons.fetch_and(~reason, std::memory_order_acq_rel);
    if ((previous & reason) == 0 || (previous & ~reason) != 0)
    {
        return;
    }
    if (!g_core_performed_pause.exchange(false, std::memory_order_acq_rel))
    {
        return;
    }

    if (rpcs3_ios_core_emulator_state() == RPCS3_IOS_EMULATOR_PAUSED)
    {
        (void)rpcs3_ios_core_resume();
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
    return g_application_active.load(std::memory_order_acquire) &&
        g_pause_reasons.load(std::memory_order_acquire) == 0;
}

void enforce_core_lifecycle_pause_after_run()
{
    perform_pause_if_needed();
}
}
