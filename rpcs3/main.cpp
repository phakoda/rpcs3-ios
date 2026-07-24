#include "stdafx.h"
#include "rpcs3.h"

#ifdef RPCS3_IOS
#include "Emu/System.h"
#include "ios/platform/IOSPlatform.h"

#include <atomic>
#endif

LOG_CHANNEL(sys_log, "SYS");

#ifdef RPCS3_IOS
namespace
{
enum ios_pause_reason : u32
{
    ios_pause_inactive = 1u << 0,
    ios_pause_audio_interruption = 1u << 1,
};

std::atomic<u32> g_ios_pause_reasons = 0;
std::atomic_bool g_ios_paused_emulation = false;

void pause_for_ios_reason(u32 reason)
{
    const u32 previous = g_ios_pause_reasons.fetch_or(reason);
    if (previous != 0 || !Emulator::IsAvailable() || !Emu.IsRunning())
    {
        return;
    }

    if (Emu.Pause(false, false))
    {
        g_ios_paused_emulation = true;
    }
}

void resume_after_ios_reason(u32 reason)
{
    const u32 previous = g_ios_pause_reasons.fetch_and(~reason);
    if ((previous & ~reason) != 0 || !g_ios_paused_emulation.exchange(false))
    {
        return;
    }

    if (Emulator::IsAvailable() && Emu.IsPaused())
    {
        Emu.Resume();
    }
}
}
#endif

int main(int argc, char** argv)
{
#ifdef RPCS3_IOS
    rpcs3::ios::initialize();
    rpcs3::ios::set_lifecycle_callbacks({
        .will_resign_active = [] { pause_for_ios_reason(ios_pause_inactive); },
        .did_become_active = [] { resume_after_ios_reason(ios_pause_inactive); },
        .audio_interruption_began = [] { pause_for_ios_reason(ios_pause_audio_interruption); },
        .audio_interruption_ended = [] { resume_after_ios_reason(ios_pause_audio_interruption); },
    });

    std::string audio_error;
    if (!rpcs3::ios::configure_audio_session(false, false, &audio_error))
    {
        sys_log.warning("iOS audio session setup failed: %s", audio_error);
    }

    const rpcs3::ios::runtime_paths paths = rpcs3::ios::get_runtime_paths();
    const rpcs3::ios::jit_capabilities jit = rpcs3::ios::query_jit_capabilities();
    sys_log.notice("iOS application support directory: %s", paths.application_support);
    sys_log.notice("iOS import directory: %s", paths.imports);
    sys_log.notice("iOS JIT capabilities: %s", jit.detail);
#endif

    const int exit_code = run_rpcs3(argc, argv);
    sys_log.notice("RPCS3 terminated with exit code %d", exit_code);

#ifdef RPCS3_IOS
    rpcs3::ios::shutdown();
#endif
    return exit_code;
}
