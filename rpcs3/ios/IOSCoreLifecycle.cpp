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

void pause_for_reason(unsigned int reason)
{
    const unsigned int previous = g_pause_reasons.fetch_or(reason);
    if (previous != 0 || rpcs3_ios_core_emulator_state() != RPCS3_IOS_EMULATOR_RUNNING)
    {
        return;
    }

    if (rpcs3_ios_core_pause() == RPCS3_IOS_CORE_SUCCESS)
    {
        g_core_performed_pause.store(true);
    }
}

void resume_after_reason(unsigned int reason)
{
    const unsigned int previous = g_pause_reasons.fetch_and(~reason);
    if ((previous & ~reason) != 0 || !g_core_performed_pause.exchange(false))
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
    g_pause_reasons.store(0);
    g_core_performed_pause.store(false);

    set_lifecycle_callbacks({
        .will_resign_active = [] { pause_for_reason(pause_reason_inactive); },
        .did_become_active = [] { resume_after_reason(pause_reason_inactive); },
        .did_enter_background = [] { pause_for_reason(pause_reason_inactive); },
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
    g_pause_reasons.store(0);
    g_core_performed_pause.store(false);
}
}
