#include "stdafx.h"
#include "IOSRuntimeIntegration.h"
#include "platform/IOSPlatform.h"

#include "Emu/System.h"

#include <QCoreApplication>
#include <QEvent>
#include <QFileOpenEvent>
#include <QUrl>

#include <atomic>
#include <memory>

LOG_CHANNEL(ios_log, "IOS");

namespace
{
enum ios_pause_reason : u32
{
    ios_pause_inactive = 1u << 0,
    ios_pause_audio_interruption = 1u << 1,
};

std::atomic_bool g_ios_runtime_initialized = false;
std::atomic<u32> g_ios_pause_reasons = 0;
std::atomic_bool g_ios_paused_emulation = false;

class ios_file_open_filter final : public QObject
{
public:
    using QObject::QObject;

protected:
    bool eventFilter(QObject* watched, QEvent* event) override
    {
        (void)watched;
        if (!event || event->type() != QEvent::FileOpen)
        {
            return false;
        }

        auto* file_event = static_cast<QFileOpenEvent*>(event);
        QString path = file_event->file();
        if (path.isEmpty() && file_event->url().isLocalFile())
        {
            path = file_event->url().toLocalFile();
        }
        if (path.isEmpty())
        {
            ios_log.error("Received an iOS file-open event without a local path.");
            return true;
        }

        std::string imported_path;
        std::string error;
        if (!rpcs3::ios::import_item(path.toStdString(), &imported_path, &error))
        {
            ios_log.error("Could not import Files app item '%s': %s", path.toStdString(), error);
            return true;
        }

        ios_log.success("Imported Files app item to '%s'.", imported_path);
        return true;
    }
};

std::unique_ptr<ios_file_open_filter> g_file_open_filter;

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

const char* thermal_state_name(rpcs3::ios::thermal_state state)
{
    using rpcs3::ios::thermal_state;
    switch (state)
    {
    case thermal_state::nominal: return "nominal";
    case thermal_state::fair: return "fair";
    case thermal_state::serious: return "serious";
    case thermal_state::critical: return "critical";
    case thermal_state::unknown: return "unknown";
    }
    return "unknown";
}

void log_performance_event(rpcs3::ios::performance_event event, rpcs3::ios::performance_state state)
{
    using rpcs3::ios::performance_event;
    switch (event)
    {
    case performance_event::thermal_state_changed:
        if (state.thermal == rpcs3::ios::thermal_state::serious || state.thermal == rpcs3::ios::thermal_state::critical)
        {
            ios_log.warning("Thermal state changed to %s; sustained emulation performance may be reduced.", thermal_state_name(state.thermal));
        }
        else
        {
            ios_log.notice("Thermal state changed to %s.", thermal_state_name(state.thermal));
        }
        break;
    case performance_event::low_power_mode_changed:
        ios_log.notice("Low Power Mode is now %s.", state.low_power_mode ? "enabled" : "disabled");
        break;
    case performance_event::memory_warning:
        ios_log.error("iOS issued a memory warning. Current caches and savestate operations should minimize peak memory use.");
        break;
    }
}

void refresh_touch_controller_visibility()
{
    const u32 hardware_count = static_cast<u32>(rpcs3::ios::get_controller_states().size());
    rpcs3::ios::set_touch_controller_overlay_visible(hardware_count == 0);
    ios_log.notice("GameController configuration changed; %u hardware controller(s) are connected. Touch controls are %s.",
        hardware_count,
        hardware_count == 0 ? "enabled" : "hidden");
}
}

namespace rpcs3::ios
{
void initialize_rpcs3_runtime()
{
    if (g_ios_runtime_initialized.exchange(true))
    {
        return;
    }

    initialize();
    set_lifecycle_callbacks({
        .will_resign_active = [] { pause_for_ios_reason(ios_pause_inactive); },
        .did_become_active = [] { resume_after_ios_reason(ios_pause_inactive); },
        .audio_interruption_began = [] { pause_for_ios_reason(ios_pause_audio_interruption); },
        .audio_interruption_ended = []
        {
            std::string error;
            if (!configure_audio_session(false, false, &error))
            {
                ios_log.warning("Audio session recovery failed: %s", error);
            }
            resume_after_ios_reason(ios_pause_audio_interruption);
        },
        .controller_configuration_changed = refresh_touch_controller_visibility,
    });

    set_performance_callback(log_performance_event);
    set_idle_timer_disabled(true);
    refresh_touch_controller_visibility();

    if (QCoreApplication* application = QCoreApplication::instance())
    {
        g_file_open_filter = std::make_unique<ios_file_open_filter>();
        application->installEventFilter(g_file_open_filter.get());
    }

    std::string audio_error;
    if (!configure_audio_session(false, false, &audio_error))
    {
        ios_log.warning("Audio session setup failed: %s", audio_error);
    }

    const runtime_paths paths = get_runtime_paths();
    const jit_capabilities jit = query_jit_capabilities();
    const performance_state performance = get_performance_state();
    ios_log.notice("Application support directory: %s", paths.application_support);
    ios_log.notice("Content import directory: %s", paths.imports);
    ios_log.notice("JIT capabilities: %s", jit.detail);
    ios_log.notice("Physical memory: %llu bytes; thermal state: %s; Low Power Mode: %s",
        performance.physical_memory,
        thermal_state_name(performance.thermal),
        performance.low_power_mode ? "enabled" : "disabled");
}

void shutdown_rpcs3_runtime()
{
    if (!g_ios_runtime_initialized.exchange(false))
    {
        return;
    }

    if (QCoreApplication* application = QCoreApplication::instance(); application && g_file_open_filter)
    {
        application->removeEventFilter(g_file_open_filter.get());
    }
    g_file_open_filter.reset();

    set_touch_controller_overlay_visible(false);
    clear_virtual_controller_state();
    set_idle_timer_disabled(false);
    set_performance_callback({});
    set_lifecycle_callbacks({});
    shutdown();
    g_ios_pause_reasons = 0;
    g_ios_paused_emulation = false;
}
}
