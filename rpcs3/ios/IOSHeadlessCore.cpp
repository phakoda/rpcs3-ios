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

#include <atomic>
#include <memory>
#include <mutex>
#include <set>
#include <utility>
#include <vector>

namespace
{
std::mutex g_headless_mutex;
bool g_headless_prepared = false;

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
    callbacks.on_emulation_stop_no_response = [](std::shared_ptr<atomic_t<bool>> closed, int)
    {
        if (closed)
        {
            *closed = true;
            closed->notify_all();
        }
    };
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
    callbacks.get_photo_path = [](const std::string&) -> std::string { return {}; };
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
bool prepare_headless_emulator(std::string* error)
{
    std::lock_guard lock(g_headless_mutex);
    if (g_headless_prepared)
    {
        return true;
    }

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
    return true;
}

void shutdown_headless_emulator()
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        return;
    }

    if (!Emu.IsStopped())
    {
        Emu.Kill(false);
    }
    g_headless_prepared = false;
}

std::uint32_t boot_headless_path(const std::string& path)
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }
    if (path.empty())
    {
        return static_cast<std::uint32_t>(game_boot_result::invalid_file_or_folder);
    }

    Emu.SetForceBoot(true);
    Emu.SetContinuousMode(false);
    return static_cast<std::uint32_t>(Emu.BootGame(path));
}

std::uint32_t restart_headless_emulator(bool graceful)
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared)
    {
        return static_cast<std::uint32_t>(game_boot_result::currently_restricted);
    }
    return static_cast<std::uint32_t>(Emu.Restart(graceful, true));
}

bool pause_headless_emulator()
{
    std::lock_guard lock(g_headless_mutex);
    return g_headless_prepared && Emu.IsRunning() && Emu.Pause(false, false);
}

bool resume_headless_emulator()
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared || !Emu.IsPaused())
    {
        return false;
    }
    Emu.Resume();
    return true;
}

bool stop_headless_emulator(bool graceful)
{
    std::lock_guard lock(g_headless_mutex);
    if (!g_headless_prepared || Emu.IsStopped())
    {
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
    return true;
}

std::uint32_t get_headless_emulator_state()
{
    std::lock_guard lock(g_headless_mutex);
    return g_headless_prepared
        ? static_cast<std::uint32_t>(Emu.GetStatus())
        : static_cast<std::uint32_t>(system_state::stopped);
}
}
