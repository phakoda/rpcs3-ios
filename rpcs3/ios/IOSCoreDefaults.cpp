#include "IOSCoreDefaults.h"

#include "Emu/system_config.h"

#ifdef RPCS3_IOS_CORE
#include "IOSCoreGSFrame.h"
#include "Emu/System.h"
#include "util/atomic.hpp"

extern atomic_t<bool> g_headless;
#endif

namespace rpcs3::ios
{
void apply_core_compatibility_defaults()
{
#ifdef RPCS3_IOS_CORE
    // Upstream treats headless mode as Null-RSX-only. A framework host with a
    // live CAMetalLayer is a real GUI/render target even though it does not use
    // Qt, so clear both RPCS3 headless state holders before settings fixup.
    const bool has_render_host = has_core_render_view();
    g_headless = !has_render_host;
    if (Emulator::IsAvailable())
    {
        Emu.SetHeadless(!has_render_host);
    }
    g_cfg.video.renderer = has_render_host ? video_renderer::vulkan : video_renderer::null;
#else
    // MoltenVK is the only renderer linked into the full iOS frontend.
    g_cfg.video.renderer = video_renderer::vulkan;
#endif

#ifndef RPCS3_IOS_HAS_LLVM
    if (g_cfg.core.ppu_decoder == ppu_decoder_type::llvm)
    {
        g_cfg.core.ppu_decoder = ppu_decoder_type::_static;
    }
    if (g_cfg.core.spu_decoder == spu_decoder_type::llvm)
    {
        g_cfg.core.spu_decoder = spu_decoder_type::dynamic;
    }
#endif

#if defined(ARCH_ARM64)
    // RPCS3's AsmJit SPU backend emits x86 machine code. The dynamic
    // interpreter is the portable fallback on Apple arm64.
    if (g_cfg.core.spu_decoder == spu_decoder_type::asmjit)
    {
        g_cfg.core.spu_decoder = spu_decoder_type::dynamic;
    }
#endif

    // The current iOS core exposes emulated USB and public CoreMIDI sources but
    // not host USB passthrough, camera, microphone, or PS Move capture backends.
    g_cfg.audio.microphone_type = microphone_handler::null;
    g_cfg.io.camera = camera_handler::null;
    g_cfg.io.move = move_handler::null;

    // Raw desktop mouse capture is not available through UIKit.
    if (g_cfg.io.mouse == mouse_handler::raw)
    {
        g_cfg.io.mouse = mouse_handler::basic;
    }
}
}
