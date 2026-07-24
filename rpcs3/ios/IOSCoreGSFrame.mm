#include "IOSCoreGSFrame.h"
#include "platform/IOSPlatform.h"

#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include "Emu/RSX/GSFrameBase.h"

#include <algorithm>
#include <mutex>
#include <utility>
#include <vector>

namespace
{
std::mutex g_render_view_mutex;
__strong UIView* g_render_view = nil;

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
        run_on_main_async(^{
            CAMetalLayer* layer = [m_view.layer isKindOfClass:CAMetalLayer.class]
                ? (CAMetalLayer*)m_view.layer : nil;
            if (layer)
            {
                const CGFloat scale = m_view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
                layer.contentsScale = scale;
                layer.drawableSize = CGSizeMake(
                    std::max<CGFloat>(m_view.bounds.size.width * scale, 1.0),
                    std::max<CGFloat>(m_view.bounds.size.height * scale, 1.0));
            }
        });
    }

    bool shown() override
    {
        __block bool visible = false;
        run_on_main_sync(^{
            visible = m_view && !m_view.hidden && m_view.window != nil;
        });
        return visible;
    }

    void hide() override
    {
        run_on_main_async(^{ m_view.hidden = YES; });
    }

    void show() override
    {
        run_on_main_async(^{ m_view.hidden = NO; });
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
        __block int width = 1;
        run_on_main_sync(^{
            const CGFloat scale = m_view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
            width = std::max(1, static_cast<int>(m_view.bounds.size.width * scale));
        });
        return width;
    }

    int client_height() override
    {
        __block int height = 1;
        run_on_main_sync(^{
            const CGFloat scale = m_view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
            height = std::max(1, static_cast<int>(m_view.bounds.size.height * scale));
        });
        return height;
    }

    f64 client_display_rate() override
    {
        __block f64 rate = 60.0;
        run_on_main_sync(^{
            UIScreen* screen = m_view.window.screen ?: UIScreen.mainScreen;
            rate = std::max<NSInteger>(screen.maximumFramesPerSecond, 20);
        });
        return rate;
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
            CAMetalLayer* layer = (CAMetalLayer*)view.layer;
            layer.framebufferOnly = NO;
            layer.opaque = YES;
            const CGFloat scale = view.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
            layer.contentsScale = scale;
            layer.drawableSize = CGSizeMake(
                std::max<CGFloat>(view.bounds.size.width * scale, 1.0),
                std::max<CGFloat>(view.bounds.size.height * scale, 1.0));
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

    {
        std::lock_guard lock(g_render_view_mutex);
        if (g_render_view && g_render_view != view)
        {
            detach_touch_controller_overlay((__bridge void*)g_render_view);
        }
        g_render_view = view;
    }
    attach_touch_controller_overlay((__bridge void*)view);
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
    if (view)
    {
        detach_touch_controller_overlay((__bridge void*)view);
    }
}

bool has_core_render_view()
{
    std::lock_guard lock(g_render_view_mutex);
    return g_render_view != nil;
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
