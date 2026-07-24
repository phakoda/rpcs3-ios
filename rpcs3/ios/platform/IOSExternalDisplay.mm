#include "IOSPlatform.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <mutex>
#include <utility>

namespace
{
std::mutex g_display_callback_mutex;
rpcs3::ios::external_display_callback g_display_callback;

UIScreen* external_screen()
{
    for (UIScreen* screen in UIScreen.screens)
    {
        if (screen != UIScreen.mainScreen)
        {
            return screen;
        }
    }
    return nil;
}

void deliver_display_state()
{
    rpcs3::ios::external_display_callback callback;
    {
        std::lock_guard lock(g_display_callback_mutex);
        callback = g_display_callback;
    }
    if (callback)
    {
        callback(rpcs3::ios::get_external_display_state());
    }
}
}

@interface RPCS3ExternalDisplayObserver : NSObject
@end

@implementation RPCS3ExternalDisplayObserver
- (instancetype)init
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(screenChanged:)
                   name:UIScreenDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(screenChanged:)
                   name:UIScreenDidDisconnectNotification object:nil];
    [center addObserver:self selector:@selector(screenChanged:)
                   name:UIScreenModeDidChangeNotification object:nil];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)screenChanged:(NSNotification*)notification
{
    (void)notification;
    deliver_display_state();
}
@end

static RPCS3ExternalDisplayObserver* g_display_observer = nil;

namespace rpcs3::ios
{
external_display_state get_external_display_state()
{
    __block external_display_state state;
    const auto collect = ^{
        UIScreen* screen = external_screen();
        if (!screen)
        {
            return;
        }

        state.connected = true;
        const CGRect native_bounds = screen.nativeBounds;
        state.width = static_cast<unsigned int>(native_bounds.size.width);
        state.height = static_cast<unsigned int>(native_bounds.size.height);
        state.scale = static_cast<float>(screen.nativeScale);
        state.maximum_frames_per_second = static_cast<float>(screen.maximumFramesPerSecond);
    };

    if (NSThread.isMainThread)
    {
        collect();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), collect);
    }
    return state;
}

void set_external_display_callback(external_display_callback callback)
{
    {
        std::lock_guard lock(g_display_callback_mutex);
        g_display_callback = std::move(callback);
    }

    const auto update_observer = ^{
        bool has_callback = false;
        {
            std::lock_guard lock(g_display_callback_mutex);
            has_callback = static_cast<bool>(g_display_callback);
        }

        if (has_callback && !g_display_observer)
        {
            g_display_observer = [[RPCS3ExternalDisplayObserver alloc] init];
        }
        else if (!has_callback)
        {
            g_display_observer = nil;
        }
    };

    if (NSThread.isMainThread)
    {
        update_observer();
        deliver_display_state();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            update_observer();
            deliver_display_state();
        });
    }
}
}
