#include "IOSCoreSettings.h"
#include "IOSCoreDefaults.h"
#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#import <Foundation/Foundation.h>

#include "Emu/System.h"
#include "Emu/system_config.h"

#include <algorithm>
#include <mutex>

namespace
{
std::mutex g_settings_mutex;

NSString* const settings_marker = @"RPCS3Core.Settings.Version";
NSString* const settings_cpu_mode = @"RPCS3Core.Settings.CPUMode";
NSString* const settings_audio_enabled = @"RPCS3Core.Settings.AudioEnabled";
NSString* const settings_audio_volume = @"RPCS3Core.Settings.AudioVolume";
NSString* const settings_resolution_scale = @"RPCS3Core.Settings.ResolutionScale";
NSString* const settings_frame_limit = @"RPCS3Core.Settings.FrameLimit";
NSString* const settings_shader_cache = @"RPCS3Core.Settings.ShaderCache";
NSString* const settings_performance_overlay = @"RPCS3Core.Settings.PerformanceOverlay";
NSString* const settings_preferred_spu_threads = @"RPCS3Core.Settings.PreferredSPUThreads";

constexpr rpcs3_ios_configuration default_configuration()
{
    return {
        sizeof(rpcs3_ios_configuration),
        RPCS3_IOS_CPU_PORTABLE,
        1,
        100,
        100,
        RPCS3_IOS_FRAME_LIMIT_AUTO,
        1,
        0,
        0,
    };
}

bool mutation_allowed()
{
    return !Emulator::IsAvailable() || Emu.IsStopped(true);
}

frame_limit_type decode_frame_limit(uint32_t value)
{
    switch (value)
    {
    case RPCS3_IOS_FRAME_LIMIT_30: return frame_limit_type::_30;
    case RPCS3_IOS_FRAME_LIMIT_60: return frame_limit_type::_60;
    case RPCS3_IOS_FRAME_LIMIT_120: return frame_limit_type::_120;
    case RPCS3_IOS_FRAME_LIMIT_DISPLAY: return frame_limit_type::display_rate;
    case RPCS3_IOS_FRAME_LIMIT_AUTO:
    default: return frame_limit_type::_auto;
    }
}

uint32_t encode_frame_limit(frame_limit_type value)
{
    switch (value)
    {
    case frame_limit_type::_30: return RPCS3_IOS_FRAME_LIMIT_30;
    case frame_limit_type::_60: return RPCS3_IOS_FRAME_LIMIT_60;
    case frame_limit_type::_120: return RPCS3_IOS_FRAME_LIMIT_120;
    case frame_limit_type::display_rate: return RPCS3_IOS_FRAME_LIMIT_DISPLAY;
    default: return RPCS3_IOS_FRAME_LIMIT_AUTO;
    }
}

rpcs3_ios_cpu_mode current_cpu_mode()
{
    if (g_cfg.core.ppu_decoder.get() == ppu_decoder_type::llvm)
    {
        return g_cfg.core.spu_decoder.get() == spu_decoder_type::llvm
            ? RPCS3_IOS_CPU_FULL_LLVM
            : RPCS3_IOS_CPU_PPU_LLVM;
    }
    return RPCS3_IOS_CPU_PORTABLE;
}

rpcs3_ios_configuration configuration_snapshot()
{
    return {
        sizeof(rpcs3_ios_configuration),
        current_cpu_mode(),
        g_cfg.audio.renderer.get() == audio_renderer::cubeb ? 1u : 0u,
        static_cast<uint32_t>(g_cfg.audio.volume.get()),
        static_cast<uint32_t>(g_cfg.video.resolution_scale_percent.get()),
        encode_frame_limit(g_cfg.video.frame_limit.get()),
        g_cfg.video.disable_on_disk_shader_cache.get() ? 0u : 1u,
        g_cfg.video.perf_overlay.enabled.get() ? 1u : 0u,
        static_cast<uint32_t>(g_cfg.core.preferred_spu_threads.get()),
    };
}

rpcs3_ios_core_result apply_configuration(const rpcs3_ios_configuration& configuration)
{
    if (configuration.struct_size < sizeof(rpcs3_ios_configuration))
    {
        rpcs3::ios::set_core_last_error("The configuration structure is smaller than this RPCS3Core version expects.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    switch (configuration.cpu_mode)
    {
    case RPCS3_IOS_CPU_PORTABLE:
        g_cfg.core.ppu_decoder = ppu_decoder_type::_static;
        g_cfg.core.spu_decoder = spu_decoder_type::dynamic;
        break;
    case RPCS3_IOS_CPU_PPU_LLVM:
#ifdef RPCS3_IOS_HAS_LLVM
        g_cfg.core.ppu_decoder = ppu_decoder_type::llvm;
        g_cfg.core.spu_decoder = spu_decoder_type::dynamic;
        break;
#else
        rpcs3::ios::set_core_last_error("This RPCS3Core build does not include the LLVM PPU recompiler.");
        return RPCS3_IOS_CORE_UNSUPPORTED;
#endif
    case RPCS3_IOS_CPU_FULL_LLVM:
#ifdef RPCS3_IOS_HAS_LLVM
        g_cfg.core.ppu_decoder = ppu_decoder_type::llvm;
        g_cfg.core.spu_decoder = spu_decoder_type::llvm;
        break;
#else
        rpcs3::ios::set_core_last_error("This RPCS3Core build does not include the LLVM PPU/SPU recompilers.");
        return RPCS3_IOS_CORE_UNSUPPORTED;
#endif
    default:
        rpcs3::ios::set_core_last_error("The requested CPU mode is invalid.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    if (configuration.frame_limit > RPCS3_IOS_FRAME_LIMIT_DISPLAY)
    {
        rpcs3::ios::set_core_last_error("The requested frame-limit mode is invalid.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    g_cfg.audio.renderer = configuration.audio_enabled ? audio_renderer::cubeb : audio_renderer::null;
    g_cfg.audio.volume = std::min<uint32_t>(configuration.audio_volume, 200);
    g_cfg.video.resolution_scale_percent = std::clamp<uint32_t>(configuration.resolution_scale_percent, 25, 800);
    g_cfg.video.frame_limit = decode_frame_limit(configuration.frame_limit);
    g_cfg.video.disable_on_disk_shader_cache = configuration.shader_cache_enabled == 0;
    g_cfg.video.perf_overlay.enabled = configuration.performance_overlay_enabled != 0;
    g_cfg.core.preferred_spu_threads = std::min<uint32_t>(configuration.preferred_spu_threads, 6);

    rpcs3::ios::apply_core_compatibility_defaults();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

void persist_configuration(const rpcs3_ios_configuration& configuration)
{
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:1 forKey:settings_marker];
    [defaults setInteger:configuration.cpu_mode forKey:settings_cpu_mode];
    [defaults setBool:configuration.audio_enabled != 0 forKey:settings_audio_enabled];
    [defaults setInteger:configuration.audio_volume forKey:settings_audio_volume];
    [defaults setInteger:configuration.resolution_scale_percent forKey:settings_resolution_scale];
    [defaults setInteger:configuration.frame_limit forKey:settings_frame_limit];
    [defaults setBool:configuration.shader_cache_enabled != 0 forKey:settings_shader_cache];
    [defaults setBool:configuration.performance_overlay_enabled != 0 forKey:settings_performance_overlay];
    [defaults setInteger:configuration.preferred_spu_threads forKey:settings_preferred_spu_threads];
}

rpcs3_ios_configuration read_persisted_configuration(bool* had_persisted_value)
{
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    rpcs3_ios_configuration configuration = default_configuration();
    const bool exists = [defaults objectForKey:settings_marker] != nil;
    if (had_persisted_value)
    {
        *had_persisted_value = exists;
    }
    if (!exists)
    {
        return configuration;
    }

    configuration.cpu_mode = static_cast<uint32_t>([defaults integerForKey:settings_cpu_mode]);
    configuration.audio_enabled = [defaults boolForKey:settings_audio_enabled] ? 1 : 0;
    configuration.audio_volume = static_cast<uint32_t>(std::max<NSInteger>([defaults integerForKey:settings_audio_volume], 0));
    configuration.resolution_scale_percent = static_cast<uint32_t>(std::max<NSInteger>([defaults integerForKey:settings_resolution_scale], 0));
    configuration.frame_limit = static_cast<uint32_t>(std::max<NSInteger>([defaults integerForKey:settings_frame_limit], 0));
    configuration.shader_cache_enabled = [defaults boolForKey:settings_shader_cache] ? 1 : 0;
    configuration.performance_overlay_enabled = [defaults boolForKey:settings_performance_overlay] ? 1 : 0;
    configuration.preferred_spu_threads = static_cast<uint32_t>(std::max<NSInteger>([defaults integerForKey:settings_preferred_spu_threads], 0));
    return configuration;
}
}

namespace rpcs3::ios
{
void load_core_configuration()
{
    std::lock_guard lock(g_settings_mutex);
    bool persisted = false;
    const rpcs3_ios_configuration configuration = read_persisted_configuration(&persisted);
    if (apply_configuration(configuration) != RPCS3_IOS_CORE_SUCCESS)
    {
        const rpcs3_ios_configuration fallback = default_configuration();
        apply_configuration(fallback);
        persist_configuration(fallback);
    }
    else if (!persisted)
    {
        persist_configuration(configuration_snapshot());
    }
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_get_configuration(rpcs3_ios_configuration* configuration)
{
    if (!configuration)
    {
        rpcs3::ios::set_core_last_error("A configuration output pointer is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_settings_mutex);
    *configuration = configuration_snapshot();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_set_configuration(const rpcs3_ios_configuration* configuration)
{
    if (!configuration)
    {
        rpcs3::ios::set_core_last_error("A configuration input pointer is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Core settings can be changed only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_settings_mutex);
    const rpcs3_ios_core_result result = apply_configuration(*configuration);
    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        persist_configuration(configuration_snapshot());
    }
    return result;
}

rpcs3_ios_core_result rpcs3_ios_core_reset_configuration(void)
{
    if (!mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Core settings can be reset only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_settings_mutex);
    const rpcs3_ios_configuration configuration = default_configuration();
    const rpcs3_ios_core_result result = apply_configuration(configuration);
    if (result == RPCS3_IOS_CORE_SUCCESS)
    {
        NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
        for (NSString* key in @[
            settings_marker,
            settings_cpu_mode,
            settings_audio_enabled,
            settings_audio_volume,
            settings_resolution_scale,
            settings_frame_limit,
            settings_shader_cache,
            settings_performance_overlay,
            settings_preferred_spu_threads,
        ])
        {
            [defaults removeObjectForKey:key];
        }
        persist_configuration(configuration_snapshot());
    }
    return result;
}
}
