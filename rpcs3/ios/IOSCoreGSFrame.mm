#include "IOSCoreGSFrame.h"
#include "platform/IOSPlatform.h"

#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include "Emu/RSX/GSFrameBase.h"

#include <algorithm>
#include <atomic>
#include <mutex>
#include <utility>
#include <vector>

namespace
{
std::mutex g_render_view_mutex;
__strong UIView* g_render_view = nil;
std::atomic<int> g_render_width = 1;
std::atomic<int> g_render_height = 1;
std::atomic<double> g_render_refresh_rate = 60.0;
std::atomic<std::uint64_t> g_render_generation = 0;
std::atomic_bool g_render_visible = false;

void run_on_main_sync(dispatch_block_t block)
{
    if (NSThread.isMainThread)
    {
        block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

void run_on_main_async(dispatch_block_t block)
{
    if (NSThread.isMainThread)
    {
        block();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

CGFloat scale_for_view(UIView* view)
{
    UIScreen* screen = view.window.screen ?: UIScreen.mainScreen;
    return std::max<CGFloat>(screen.nativeScale, 1.0);
}

void clear_render_metrics()
{
    g_render_width.store(1, std::memory_order_release);
    g_render_height.store(1, std::memory_order_release);
    g_render_refresh_rate.store(60.0, std::memory_order_release);
    g_render_visible.store(false, std::memory_order_release);
    g_render_generation.fetch_add(1, std::memory_order_acq_rel);
}

void update_metal_drawable(UIView* view)
{
    if (!view || ![view.layer isKindOfClass:CAMetalLayer.class])
    {
        clear_render_metrics();
        return;
    }

    CAMetalLayer* layer = (CAMetalLayer*)view.layer;
    const CGFloat scale = scale_for_view(view);
    const int width = std::max(1, static_cast<int>(view.bounds.size.width * scale));
    const int height = std::max(1, static_cast<int>(view.bounds.size.height * scale));
    UIScreen* screen = view.window.screen ?: UIScreen.mainScreen;
    const double refresh_rate = std::max<NSInteger>(screen.maximumFramesPerSecond, 20);
    const bool visible = !view.hidden && view.window != nil;

    layer.framebufferOnly = NO;
    layer.opaque = YES;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(width, height);

    const bool size_changed =
        g_render_width.exchange(width, std::memory_order_acq_rel) != width ||
        g_render_height.exchange(height, std::memory_order_acq_rel) != height;
    const bool rate_changed =
        g_render_refresh_rate.exchange(refresh_rate, std::memory_order_acq_rel) != refresh_rate;
    g_render_visible.store(visible, std::memory_order_release);
    if (size_changed || rate_changed)
    {
        // RSX-facing dimensions are now available without entering UIKit. The
        // generation lets diagnostics and future swapchain code distinguish a
        // new drawable contract from a repeated layout refresh.
        g_render_generation.fetch_add(1, std::memory_order_acq_rel);
    }
}

class ios_core_gs_frame final : public GSFrameBase
{
public:
    explicit ios_core_gs_frame(UIView* view)
        : m_view(view)
    {
    }

    void close() override
    {
        // The host application owns the view. Renderer teardown must not remove
        // or destroy it; the host can reuse it for the next boot.
    }

    void reset() override
    {
        __strong UIView* view = m_view;
        run_on_main_async(^{ update_metal_drawable(view); });
    }

    bool shown() override
    {
        return g_render_visible.load(std::memory_order_acquire);
    }

    void hide() override
    {
        __strong UIView* view = m_view;
        run_on_main_async(^{
            view.hidden = YES;
            g_render_visible.store(false, std::memory_order_release);
        });
    }

    void show() override
    {
        __strong UIView* view = m_view;
        run_on_main_async(^{
            view.hidden = NO;
            update_metal_drawable(view);
        });
    }

    void toggle_fullscreen() override
    {
        // iOS application windows own fullscreen policy. The renderer view
        // follows the layout supplied by the host controller.
    }

    void delete_context(draw_context_t context) override
    {
        (void)context;
    }

    draw_context_t make_context() override
    {
        return nullptr;
    }

    void set_current(draw_context_t context) override
    {
        (void)context;
    }

    void flip(draw_context_t context, bool skip_frame) override
    {
        (void)context;
        (void)skip_frame;
    }

    int client_width() override
    {
        return g_render_width.load(std::memory_order_acquire);
    }

    int client_height() override
    {
        return g_render_height.load(std::memory_order_acquire);
    }

    f64 client_display_rate() override
    {
        return g_render_refresh_rate.load(std::memory_order_acquire);
    }

    bool has_alpha() override
    {
        return false;
    }

    display_handle_t handle() const override
    {
        return (__bridge void*)m_view;
    }

    bool can_consume_frame() const override
    {
        return false;
    }

    void present_frame(std::vector<u8>&& data, u32 pitch, u32 width, u32 height, bool is_bgra) const override
    {
        (void)data;
        (void)pitch;
        (void)width;
        (void)height;
        (void)is_bgra;
    }

    void take_screenshot(std::vector<u8>&& data, u32 width, u32 height, bool is_bgra) override
    {
        (void)data;
        (void)width;
        (void)height;
        (void)is_bgra;
    }

    void update_title(double fps) override
    {
        (void)fps;
    }

private:
    __strong UIView* m_view = nil;
};
}

namespace rpcs3::ios
{
bool set_core_render_view(void* native_view, std::string* error)
{
    if (!native_view)
    {
        if (error)
        {
            *error = "A non-null UIView is required.";
        }
        return false;
    }

    __block UIView* view = nil;
    __block bool valid = false;
    run_on_main_sync(^{
        view = (__bridge UIView*)native_view;
        valid = [view isKindOfClass:UIView.class] && [view.layer isKindOfClass:CAMetalLayer.class];
        if (valid)
        {
            update_metal_drawable(view);
        }
    });

    if (!valid)
    {
        if (error)
        {
            *error = "The render UIView must use CAMetalLayer as its backing layer.";
        }
        return false;
    }

    __strong UIView* previous_view = nil;
    {
        std::lock_guard lock(g_render_view_mutex);
        previous_view = g_render_view;
        g_render_view = view;
    }

    run_on_main_async(^{
        if (previous_view && previous_view != view)
        {
            detach_touch_controller_overlay((__bridge void*)previous_view);
        }
        attach_touch_controller_overlay((__bridge void*)view);
        update_metal_drawable(view);
    });
    return true;
}

void clear_core_render_view()
{
    __strong UIView* view = nil;
    {
        std::lock_guard lock(g_render_view_mutex);
        view = g_render_view;
        g_render_view = nil;
    }
    clear_render_metrics();
    if (view)
    {
        run_on_main_async(^{ detach_touch_controller_overlay((__bridge void*)view); });
    }
}

bool has_core_render_view()
{
    std::lock_guard lock(g_render_view_mutex);
    return g_render_view != nil;
}

void refresh_core_render_view()
{
    __strong UIView* view = nil;
    {
        std::lock_guard lock(g_render_view_mutex);
        view = g_render_view;
    }
    if (view)
    {
        run_on_main_async(^{ update_metal_drawable(view); });
    }
}

core_render_metrics get_core_render_metrics()
{
    return {
        g_render_width.load(std::memory_order_acquire),
        g_render_height.load(std::memory_order_acquire),
        g_render_refresh_rate.load(std::memory_order_acquire),
        g_render_generation.load(std::memory_order_acquire),
        g_render_visible.load(std::memory_order_acquire),
    };
}

std::unique_ptr<GSFrameBase> make_core_gs_frame()
{
    __strong UIView* view = nil;
    {
        std::lock_guard lock(g_render_view_mutex);
        view = g_render_view;
    }
    if (!view)
    {
        return {};
    }
    return std::make_unique<ios_core_gs_frame>(view);
}
}
