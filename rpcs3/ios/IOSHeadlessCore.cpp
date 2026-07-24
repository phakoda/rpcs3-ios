#include "IOSHeadlessCore.h"
#include "IOSCoreDefaults.h"

#include "Emu/System.h"
#include "Emu/system_config.h"
#include "Emu/IdManager.h"
#include "Emu/RSX/Null/NullGSRender.h"
#include "Emu/Io/KeyboardHandler.h"
#include "Emu/Io/MouseHandler.h"
#include "Emu/Io/Null/NullKeyboardHandler.h"
#include "Emu/Io/Null/NullMouseHandler.h"
#include "Emu/Io/Null/null_camera_handler.h"
#include "Emu/Io/Null/null_music_handler.h"
#include "Emu/Audio/AudioBackend.h"
#include "Emu/Audio/Null/NullAudioBackend.h"
#include "Emu/Audio/Null/null_enumerator.h"
#include "Emu/Cell/Modules/cellMsgDialog.h"
#include "Emu/Cell/Modules/cellOskDialog.h"
#include "Emu/Cell/Modules/cellSaveData.h"
#include "Emu/Cell/Modules/sceNpTrophy.h"
#include "Utilities/Thread.h"
#include "util/video_source.h"

#include <pthread.h>

#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string_view>
#include <utility>
#include <vector>

namespace
{
std::mutex g_headless_mutex;
bool g_headless_prepared = false;

bool require_main_thread(std::string* error)
{
    if (pthread_main_np() != 0)
    {
        return true;
    }

    if (error)
    {
        *error = "RPCS3 emulator lifecycle operations must be called from the process main thread.";
    }
    return false;
}

void report_exception(std::string* error, const char* operation)
{
    if (!error)
    {
        return;
    }

    try
    {
        throw;
    }
    catch (const std::exception& exception)
    {
        *error = std::string(operation) + " failed: " + exception.what();
    }
    catch (...)
    {
        *error = std::string(operation) + " failed with an unknown C++ exception.";
    }
}

EmuCallbacks create_headless_callbacks()
{
    EmuCallbacks callbacks{};

    callbacks.call_from_main_thread = [](std::function<void()> function, atomic_t<u32>* wake_up)
    {
        if (function)
        {
            function();
        }
        if (wake_up)
        {
            *wake_up = true;
            wake_up->notify_one();
        }
    };

    callbacks.on_run = [](bool) {};
    callbacks.on_pause = [] {};
    callbacks.on_resume = [] {};
    callbacks.on_stop = [] {};
    callbacks.on_ready = [] {};
    callbacks.on_missing_fw = [] {};
    callbacks.on_emulation_stop_no_response = [](std::shared_ptr<atomic_t<bool>>, int) {};
    callbacks.on_save_state_progress = [](std::shared_ptr<atomic_t<bool>>, stx::shared_ptr<utils::serial>,
        stx::atomic_ptr<std::string>*, std::shared_ptr<void>) {};

    callbacks.enable_disc_eject = [](bool) {};
    callbacks.enable_disc_insert = [](bool) {};
    callbacks.try_to_quit = [](bool, std::function<void()> on_exit)
    {
        if (on_exit)
        {
            on_exit();
        }
        return true;
    };
    callbacks.handle_taskbar_progress = [](s32, s32) {};

    callbacks.init_kb_handler = []
    {
        ensure(g_fxo->init<KeyboardHandlerBase, NullKeyboardHandler>(Emu.DeserialManager()));
    };
    callbacks.init_mouse_handler = []
    {
        ensure(g_fxo->init<MouseHandlerBase, NullMouseHandler>(Emu.DeserialManager()));
    };
    // The portable core target intentionally excludes the Qt/Input pad thread.
    // A native frontend may provide a richer callback table in a later layer.
    callbacks.init_pad_handler = [](std::string_view) {};
    callbacks.update_emu_settings = [] {};
    callbacks.save_emu_settings = [] {};

    callbacks.close_gs_frame = [] {};
    callbacks.get_gs_frame = []() -> std::unique_ptr<GSFrameBase> { return {}; };
    callbacks.init_gs_render = [](utils::serial* archive)
    {
        g_fxo->init<rsx::thread, named_thread<NullGSRender>>(archive);
    };

    callbacks.get_camera_handler = []() -> std::shared_ptr<camera_handler_base>
    {
        return std::make_shared<null_camera_handler>();
    };
    callbacks.get_music_handler = []() -> std::shared_ptr<music_handler_base>
    {
        return std::make_shared<null_music_handler>();
    };
    callbacks.get_audio = []() -> std::shared_ptr<AudioBackend>
    {
        return std::make_shared<NullAudioBackend>();
    };
    callbacks.get_audio_enumerator = [](u64) -> std::shared_ptr<audio_device_enumerator>
    {
        return std::make_shared<null_enumerator>();
    };

    callbacks.get_msg_dialog = []() -> std::shared_ptr<MsgDialogBase> { return {}; };
    callbacks.get_osk_dialog = []() -> std::shared_ptr<OskDialogBase> { return {}; };
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase> { return {}; };
    callbacks.get_trophy_notification_dialog = []() -> std::unique_ptr<TrophyNotificationBase> { return {}; };

    callbacks.get_localized_string = [](localized_string_id, const char*) -> std::string { return {}; };
    callbacks.get_localized_u32string = [](localized_string_id, const char*) -> std::u32string { return {}; };
    callbacks.get_localized_setting = [](const cfg::_base*, u32) -> std::string { return {}; };
    callbacks.get_photo_path = [](std::string_view) -> std::string { return {}; };
    callbacks.play_sound = [](const std::string&, std::optional<f32>) {};
    callbacks.get_image_info = [](const std::string&, std::string&, s32&, s32&, s32&) { return false; };
    callbacks.get_scaled_image = [](const std::string&, s32, s32, s32&, s32&, u8*, bool) { return false; };
    callbacks.get_font_dirs = [] { return std::vector<std::string>{}; };
    callbacks.on_install_pkgs = [](const std::vector<std::string>&) { return false; };
    callbacks.add_breakpoint = [](u32) {};
    callbacks.display_sleep_control_supported = [] { return false; };
    callbacks.enable_display_sleep = [](bool) {};
    callbacks.check_microphone_permissions = [] {};
    callbacks.make_video_source = []() -> std::unique_ptr<video_source> { return {}; };
    callbacks.enable_gamemode = [](bool) {};
    callbacks.get_database_config = [](const std::string&) -> std::string { return {}; };

    return callbacks;
}
}

namespace rpcs3::ios
{
bool prepare_headless_emulator(std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return false;
    }

    std::lock_guard lock(g_headless_mutex);
    if (g_headless_prepared)
    {
        return true;
    }

    try
    {
        if (!Emulator::IsAvailable())
        {
            if (error)
            {
                *error = "The RPCS3 Emulator singleton is unavailable.";
            }
            return false;
        }

        apply_core_compatibility_defaults();
        g_cfg.video.renderer = video_renderer::null;
        g_cfg.audio.renderer = audio_renderer::null;
        g_cfg.audio.music = music_handler::null;
        g_cfg.io.keyboard = keyboard_handler::null;
        g_cfg.io.mouse = mouse_handler::null;

        Emu.SetHasGui(false);
        Emu.SetHeadless(true);
        Emu.SetUsr("00000001");
        Emu.SetSupportedRenderers({video_renderer::null});
        Emu.SetDefaultRenderer(video_renderer::null);
        Emu.Init();
        Emu.SetCallbacks(create_headless_callbacks());

        g_headless_prepared = true;
        if (error)
        {
            error->clear();
        }
        return true;
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless initialization");
        return false;
    }
}

void shutdown_headless_emulator() noexcept
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        return;
    }

    try
    {
        if (!Emu.IsStopped())
        {
            Emu.Kill(false);
        }
    }
    catch (...)
    {
        // Shutdown is best-effort and must never throw through the C ABI.
    }
    g_headless_prepared = false;
}

std::uint32_t boot_headless_path(const std::string& path, std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }

    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        if (error)
        {
            *error = "The headless emulator has not been prepared.";
        }
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }
    if (path.empty())
    {
        if (error)
        {
            *error = "A non-empty local boot path is required.";
        }
        return static_cast<std::uint32_t>(game_boot_result::invalid_file_or_folder);
    }

    try
    {
        Emu.SetForceBoot(true);
        Emu.SetContinuousMode(false);
        const game_boot_result result = Emu.BootGame(path);
        if (error)
        {
            error->clear();
        }
        return static_cast<std::uint32_t>(result);
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless boot");
        return static_cast<std::uint32_t>(game_boot_result::generic_error);
    }
}

std::uint32_t restart_headless_emulator(bool graceful, std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }

    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        if (error)
        {
            *error = "The headless emulator has not been prepared.";
        }
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }

    try
    {
        const game_boot_result result = Emu.Restart(graceful, true);
        if (error)
        {
            error->clear();
        }
        return static_cast<std::uint32_t>(result);
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless restart");
        return static_cast<std::uint32_t>(game_boot_result::generic_error);
    }
}

bool pause_headless_emulator(std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return false;
    }

    std::lock_guard lock(g_headless_mutex);
    try
    {
        if (!g_headless_prepared || !Emu.IsRunning())
        {
            if (error)
            {
                *error = "RPCS3 is not currently running.";
            }
            return false;
        }

        const bool paused = Emu.Pause(false, false);
        if (paused && error)
        {
            error->clear();
        }
        return paused;
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless pause");
        return false;
    }
}

bool resume_headless_emulator(std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return false;
    }

    std::lock_guard lock(g_headless_mutex);
    try
    {
        if (!g_headless_prepared || !Emu.IsPaused())
        {
            if (error)
            {
                *error = "RPCS3 is not currently paused.";
            }
            return false;
        }
        Emu.Resume();
        if (error)
        {
            error->clear();
        }
        return true;
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless resume");
        return false;
    }
}

bool stop_headless_emulator(bool graceful, std::string* error) noexcept
{
    if (!require_main_thread(error))
    {
        return false;
    }

    std::lock_guard lock(g_headless_mutex);
    try
    {
        if (!g_headless_prepared || Emu.IsStopped())
        {
            if (error)
            {
                *error = "RPCS3 is already stopped or has not been prepared.";
            }
            return false;
        }

        if (graceful)
        {
            Emu.GracefulShutdown(false, false, false, false);
        }
        else
        {
            Emu.Kill(false);
        }
        if (error)
        {
            error->clear();
        }
        return true;
    }
    catch (...)
    {
        report_exception(error, "RPCS3 headless stop");
        return false;
    }
}

std::uint32_t get_headless_emulator_state() noexcept
{
    std::lock_guard lock(g_headless_mutex);
    try
    {
        return g_headless_prepared
            ? static_cast<std::uint32_t>(Emu.GetStatus())
            : static_cast<std::uint32_t>(system_state::stopped);
    }
    catch (...)
    {
        return static_cast<std::uint32_t>(system_state::stopped);
    }
}
}
