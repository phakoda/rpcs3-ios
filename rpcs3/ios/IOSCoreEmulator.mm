#include "IOSCoreEmulator.h"
#include "IOSCoreDefaults.h"
#include "RPCS3Core.h"
#include "platform/IOSPlatform.h"

#import <Foundation/Foundation.h>

#include "Emu/System.h"
#include "Emu/IdManager.h"
#include "Emu/system_config.h"
#include "Emu/RSX/GSFrameBase.h"
#include "Emu/RSX/Null/NullGSRender.h"
#include "Emu/Audio/AudioBackend.h"
#include "Emu/Audio/Null/NullAudioBackend.h"
#include "Emu/Audio/Null/null_enumerator.h"
#include "Emu/Audio/Cubeb/CubebBackend.h"
#include "Emu/Audio/Cubeb/cubeb_enumerator.h"
#include "Emu/Io/Null/NullKeyboardHandler.h"
#include "Emu/Io/Null/NullMouseHandler.h"
#include "Emu/Io/Null/null_camera_handler.h"
#include "Emu/Io/Null/null_music_handler.h"
#include "Emu/Cell/Modules/cellMsgDialog.h"
#include "Emu/Cell/Modules/cellOskDialog.h"
#include "Emu/Cell/Modules/cellSaveData.h"
#include "Emu/Cell/Modules/sceNpTrophy.h"
#include "Input/pad_thread.h"
#include "Utilities/Thread.h"
#include "util/atomic.hpp"
#include "util/video_source.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace
{
std::atomic_bool g_core_emulator_initialized = false;
std::atomic_bool g_core_input_enabled = false;
std::mutex g_emulator_api_mutex;
std::mutex g_event_mutex;
std::mutex g_error_mutex;
rpcs3_ios_core_event_callback g_event_callback = nullptr;
void* g_event_context = nullptr;
std::string g_last_error;

thread_local std::string g_boot_path;
thread_local std::string g_title;
thread_local std::string g_title_id;

size_t copy_string(const std::string& value, char* buffer, size_t buffer_size)
{
    const size_t required = value.size() + 1;
    if (!buffer || buffer_size == 0)
    {
        return required;
    }

    const size_t copied = std::min(value.size(), buffer_size - 1);
    std::memcpy(buffer, value.data(), copied);
    buffer[copied] = '\0';
    return required;
}

std::string append_path_component(std::string base, std::string_view component)
{
    if (!base.empty() && base.back() != '/')
    {
        base.push_back('/');
    }
    base.append(component);
    return base;
}

void deliver_event(rpcs3_ios_core_event event, std::string detail = {})
{
    rpcs3_ios_core_event_callback callback = nullptr;
    void* context = nullptr;
    {
        std::lock_guard lock(g_event_mutex);
        callback = g_event_callback;
        context = g_event_context;
    }

    if (!callback)
    {
        return;
    }

    auto detail_storage = std::make_shared<std::string>(std::move(detail));
    const auto invoke = ^{
        callback(event, detail_storage->c_str(), context);
    };

    if (NSThread.isMainThread)
    {
        invoke();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), invoke);
    }
}

void call_on_main_thread(std::function<void()> function, atomic_t<u32>* wake_up)
{
    auto task = std::make_shared<std::function<void()>>(std::move(function));
    const auto invoke = ^{
        (*task)();
        if (wake_up)
        {
            *wake_up = 1;
            wake_up->notify_one();
        }
    };

    if (NSThread.isMainThread)
    {
        invoke();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), invoke);
    }
}

std::string boot_result_description(game_boot_result result)
{
    switch (result)
    {
    case game_boot_result::no_errors: return "Boot request accepted.";
    case game_boot_result::generic_error: return "Generic boot error.";
    case game_boot_result::nothing_to_boot: return "No bootable content was found.";
    case game_boot_result::wrong_disc_location: return "The disc content is in the wrong location.";
    case game_boot_result::invalid_file_or_folder: return "The selected file or folder is invalid.";
    case game_boot_result::invalid_bdvd_folder: return "The dev_bdvd folder is invalid.";
    case game_boot_result::install_failed: return "Content installation failed.";
    case game_boot_result::decryption_error: return "The selected content could not be decrypted.";
    case game_boot_result::file_creation_error: return "RPCS3 could not create a required file.";
    case game_boot_result::firmware_missing: return "PlayStation 3 firmware is missing.";
    case game_boot_result::firmware_version: return "The installed PlayStation 3 firmware is too old.";
    case game_boot_result::unsupported_disc_type: return "The selected disc type is unsupported.";
    case game_boot_result::savestate_corrupted: return "The savestate is corrupted.";
    case game_boot_result::savestate_version_unsupported: return "The savestate version is unsupported.";
    case game_boot_result::still_running: return "Emulation is already running.";
    case game_boot_result::already_added: return "The game has already been added.";
    case game_boot_result::currently_restricted: return "Booting is currently restricted.";
    case game_boot_result::database_config_missing: return "The requested database configuration is missing.";
    }
    return "Unknown boot error.";
}

EmuCallbacks make_core_callbacks()
{
    EmuCallbacks callbacks{};

    callbacks.call_from_main_thread = call_on_main_thread;
    callbacks.on_run = [](bool) { deliver_event(RPCS3_IOS_CORE_EVENT_RUN); };
    callbacks.on_pause = [] { deliver_event(RPCS3_IOS_CORE_EVENT_PAUSE); };
    callbacks.on_resume = [] { deliver_event(RPCS3_IOS_CORE_EVENT_RESUME); };
    callbacks.on_stop = [] { deliver_event(RPCS3_IOS_CORE_EVENT_STOP); };
    callbacks.on_ready = [] { deliver_event(RPCS3_IOS_CORE_EVENT_READY); };
    callbacks.on_missing_fw = []
    {
        rpcs3::ios::set_core_last_error("PlayStation 3 firmware is missing.");
        deliver_event(RPCS3_IOS_CORE_EVENT_MISSING_FIRMWARE, "PlayStation 3 firmware is missing.");
    };
    callbacks.on_emulation_stop_no_response = [](std::shared_ptr<atomic_t<bool>> closed, int seconds)
    {
        if (!closed || !*closed)
        {
            const std::string error = "Emulation did not stop after " + std::to_string(seconds) + " seconds.";
            rpcs3::ios::set_core_last_error(error);
            deliver_event(RPCS3_IOS_CORE_EVENT_FATAL_ERROR, error);
        }
    };
    callbacks.on_save_state_progress = [](std::shared_ptr<atomic_t<bool>>, stx::shared_ptr<utils::serial>, stx::atomic_ptr<std::string>*, std::shared_ptr<void>) {};
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
    callbacks.init_pad_handler = [](std::string_view title_id)
    {
        ensure(g_fxo->init<named_thread<pad_thread>>(nullptr, nullptr, title_id));
    };

    callbacks.update_emu_settings = []
    {
        rpcs3::ios::apply_core_compatibility_defaults();
        g_cfg.video.renderer = video_renderer::null;
    };
    callbacks.save_emu_settings = []
    {
        Emulator::SaveSettings(g_cfg.to_string(), Emu.GetTitleID());
    };
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
        std::shared_ptr<AudioBackend> result;
        if (g_cfg.audio.renderer.get() == audio_renderer::cubeb)
        {
            result = std::make_shared<CubebBackend>();
        }
        else
        {
            result = std::make_shared<NullAudioBackend>();
        }

        if (!result->Initialized())
        {
            result = std::make_shared<NullAudioBackend>();
        }
        return result;
    };
    callbacks.get_audio_enumerator = [](u64 renderer) -> std::shared_ptr<audio_device_enumerator>
    {
        if (static_cast<audio_renderer>(renderer) == audio_renderer::cubeb)
        {
            return std::make_shared<cubeb_enumerator>();
        }
        return std::make_shared<null_enumerator>();
    };

    callbacks.get_msg_dialog = []() -> std::shared_ptr<MsgDialogBase> { return {}; };
    callbacks.get_osk_dialog = []() -> std::shared_ptr<OskDialogBase> { return {}; };
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase> { return {}; };
    callbacks.get_sendmessage_dialog = []() -> std::shared_ptr<SendMessageDialogBase> { return {}; };
    callbacks.get_recvmessage_dialog = []() -> std::shared_ptr<RecvMessageDialogBase> { return {}; };
    callbacks.get_trophy_notification_dialog = []() -> std::unique_ptr<TrophyNotificationBase> { return {}; };

    callbacks.get_localized_string = [](localized_string_id, const char*) -> std::string { return {}; };
    callbacks.get_localized_u32string = [](localized_string_id, const char*) -> std::u32string { return {}; };
    callbacks.get_localized_setting = [](const cfg::_base*, u32) -> std::string { return {}; };
    callbacks.get_photo_path = [](std::string_view name)
    {
        return append_path_component(rpcs3::ios::get_runtime_paths().documents, name);
    };
    callbacks.play_sound = [](const std::string&, std::optional<f32>) {};
    callbacks.get_image_info = [](const std::string&, std::string& subtype, s32& width, s32& height, s32& orientation)
    {
        subtype.clear();
        width = 0;
        height = 0;
        orientation = 0;
        return false;
    };
    callbacks.get_scaled_image = [](const std::string&, s32, s32, s32& width, s32& height, u8*, bool)
    {
        width = 0;
        height = 0;
        return false;
    };
    callbacks.get_font_dirs = [] { return std::vector<std::string>{}; };
    callbacks.on_install_pkgs = [](const std::vector<std::string>&) { return false; };
    callbacks.add_breakpoint = [](u32) {};
    callbacks.display_sleep_control_supported = [] { return true; };
    callbacks.enable_display_sleep = [](bool enabled) { rpcs3::ios::set_idle_timer_disabled(!enabled); };
    callbacks.check_microphone_permissions = [] {};
    callbacks.make_video_source = []() -> std::unique_ptr<video_source> { return {}; };
    callbacks.enable_gamemode = [](bool) {};
    callbacks.get_database_config = [](const std::string&) { return std::string{}; };

    return callbacks;
}
}

atomic_t<bool> g_headless = true;
std::string g_input_config_override;

void pad_state_notify_state_change(usz index, u32 state)
{
    deliver_event(
        RPCS3_IOS_CORE_EVENT_PAD_CONNECTION_CHANGED,
        "Pad " + std::to_string(index + 1) + " state changed to " + std::to_string(state) + ".");
}

bool is_input_allowed()
{
    return g_core_input_enabled.load();
}

[[noreturn]] void report_fatal_error(std::string_view text, bool is_html, bool include_help_text)
{
    (void)is_html;
    (void)include_help_text;
    const std::string error{text};
    rpcs3::ios::set_core_last_error(error);
    deliver_event(RPCS3_IOS_CORE_EVENT_FATAL_ERROR, error);
    NSLog(@"RPCS3Core fatal error: %s", error.c_str());
    std::abort();
}

namespace rpcs3::ios
{
void set_core_last_error(std::string error)
{
    std::lock_guard lock(g_error_mutex);
    g_last_error = std::move(error);
}

std::string get_core_last_error()
{
    std::lock_guard lock(g_error_mutex);
    return g_last_error;
}

bool initialize_core_emulator(std::string* error)
{
    std::lock_guard lock(g_emulator_api_mutex);
    if (g_core_emulator_initialized.load())
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

    try
    {
        Emu.SetHasGui(false);
        Emu.SetHeadless(true);
        Emu.SetUsr("00000001");
        Emu.Init();

        apply_core_compatibility_defaults();
        g_cfg.video.renderer = video_renderer::null;
        Emu.SetSupportedRenderers({video_renderer::null});
        Emu.SetDefaultRenderer(video_renderer::null);
        Emu.SetCallbacks(make_core_callbacks());

        g_core_input_enabled = true;
        g_core_emulator_initialized = true;
        set_core_last_error({});
        return true;
    }
    catch (const std::exception& exception)
    {
        const std::string message = std::string("Could not initialize the RPCS3 emulator core: ") + exception.what();
        set_core_last_error(message);
        if (error)
        {
            *error = message;
        }
        return false;
    }
}

void shutdown_core_emulator()
{
    std::lock_guard lock(g_emulator_api_mutex);
    if (!g_core_emulator_initialized.exchange(false))
    {
        return;
    }

    g_core_input_enabled = false;
    try
    {
        if (Emulator::IsAvailable() && !Emu.IsStopped(true))
        {
            Emu.Kill(false);
        }
        Emulator::CleanUp();
    }
    catch (const std::exception& exception)
    {
        set_core_last_error(std::string("Core shutdown failed: ") + exception.what());
    }
}
}

extern "C"
{
void rpcs3_ios_core_set_event_callback(rpcs3_ios_core_event_callback callback, void* context)
{
    std::lock_guard lock(g_event_mutex);
    g_event_callback = callback;
    g_event_context = context;
}

rpcs3_ios_boot_result rpcs3_ios_core_boot_path(const char* path, uint8_t direct_boot)
{
    if (!g_core_emulator_initialized.load())
    {
        return RPCS3_IOS_BOOT_CORE_NOT_INITIALIZED;
    }
    if (!path || !*path)
    {
        rpcs3::ios::set_core_last_error("A non-empty local content path is required.");
        return RPCS3_IOS_BOOT_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_emulator_api_mutex);
    try
    {
        rpcs3::ios::apply_core_compatibility_defaults();
        g_cfg.video.renderer = video_renderer::null;
        Emu.SetForceBoot(true);
        const game_boot_result result = Emu.BootGame(path, {}, direct_boot != 0, cfg_mode::custom);
        if (is_error(result))
        {
            rpcs3::ios::set_core_last_error(boot_result_description(result));
        }
        else
        {
            rpcs3::ios::set_core_last_error({});
        }
        return static_cast<rpcs3_ios_boot_result>(result);
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Boot failed: ") + exception.what());
        return RPCS3_IOS_BOOT_GENERIC_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_pause(void)
{
    if (!g_core_emulator_initialized.load())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    std::lock_guard lock(g_emulator_api_mutex);
    return Emu.IsRunning() && Emu.Pause(false, false) ? RPCS3_IOS_CORE_SUCCESS : RPCS3_IOS_CORE_BUSY;
}

rpcs3_ios_core_result rpcs3_ios_core_resume(void)
{
    if (!g_core_emulator_initialized.load())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    std::lock_guard lock(g_emulator_api_mutex);
    if (!Emu.IsPaused())
    {
        return RPCS3_IOS_CORE_BUSY;
    }
    Emu.Resume();
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_stop(void)
{
    if (!g_core_emulator_initialized.load())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    std::lock_guard lock(g_emulator_api_mutex);
    if (!Emu.IsStopped(true))
    {
        Emu.Kill(false);
    }
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_boot_result rpcs3_ios_core_restart(void)
{
    if (!g_core_emulator_initialized.load())
    {
        return RPCS3_IOS_BOOT_CORE_NOT_INITIALIZED;
    }
    std::lock_guard lock(g_emulator_api_mutex);
    try
    {
        const game_boot_result result = Emu.Restart(true, true);
        if (is_error(result))
        {
            rpcs3::ios::set_core_last_error(boot_result_description(result));
        }
        else
        {
            rpcs3::ios::set_core_last_error({});
        }
        return static_cast<rpcs3_ios_boot_result>(result);
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Restart failed: ") + exception.what());
        return RPCS3_IOS_BOOT_GENERIC_ERROR;
    }
}

rpcs3_ios_emulator_state rpcs3_ios_core_emulator_state(void)
{
    if (!g_core_emulator_initialized.load() || !Emulator::IsAvailable())
    {
        return RPCS3_IOS_EMULATOR_UNAVAILABLE;
    }
    return static_cast<rpcs3_ios_emulator_state>(Emu.GetStatus(false));
}

size_t rpcs3_ios_core_copy_boot_path(char* buffer, size_t buffer_size)
{
    g_boot_path = Emulator::IsAvailable() ? Emu.GetBoot() : std::string{};
    return copy_string(g_boot_path, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_title(char* buffer, size_t buffer_size)
{
    g_title = Emulator::IsAvailable() ? Emu.GetTitle() : std::string{};
    return copy_string(g_title, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_title_id(char* buffer, size_t buffer_size)
{
    g_title_id = Emulator::IsAvailable() ? Emu.GetTitleID() : std::string{};
    return copy_string(g_title_id, buffer, buffer_size);
}
}
