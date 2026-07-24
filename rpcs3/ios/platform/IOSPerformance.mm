#include "IOSPlatform.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <memory>
#include <mutex>
#include <utility>

namespace
{
std::mutex g_performance_callback_mutex;
rpcs3::ios::performance_callback g_performance_callback;

rpcs3::ios::thermal_state convert_thermal_state(NSProcessInfoThermalState state)
{
    using rpcs3::ios::thermal_state;
    switch (state)
    {
    case NSProcessInfoThermalStateNominal: return thermal_state::nominal;
    case NSProcessInfoThermalStateFair: return thermal_state::fair;
    case NSProcessInfoThermalStateSerious: return thermal_state::serious;
    case NSProcessInfoThermalStateCritical: return thermal_state::critical;
    }
    return thermal_state::unknown;
}

void deliver_performance_event(rpcs3::ios::performance_event event)
{
    rpcs3::ios::performance_callback callback;
    {
        std::lock_guard lock(g_performance_callback_mutex);
        callback = g_performance_callback;
    }

    if (callback)
    {
        callback(event, rpcs3::ios::get_performance_state());
    }
}
}

@interface RPCS3PerformanceObserver : NSObject
@end

@implementation RPCS3PerformanceObserver
- (instancetype)init
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(thermalStateChanged:)
                   name:NSProcessInfoThermalStateDidChangeNotification
                 object:NSProcessInfo.processInfo];
    [center addObserver:self
               selector:@selector(powerStateChanged:)
                   name:NSProcessInfoPowerStateDidChangeNotification
                 object:NSProcessInfo.processInfo];
    [center addObserver:self
               selector:@selector(memoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)thermalStateChanged:(NSNotification*)notification
{
    (void)notification;
    deliver_performance_event(rpcs3::ios::performance_event::thermal_state_changed);
}

- (void)powerStateChanged:(NSNotification*)notification
{
    (void)notification;
    deliver_performance_event(rpcs3::ios::performance_event::low_power_mode_changed);
}

- (void)memoryWarning:(NSNotification*)notification
{
    (void)notification;
    deliver_performance_event(rpcs3::ios::performance_event::memory_warning);
}
@end

static RPCS3PerformanceObserver* g_performance_observer = nil;

namespace rpcs3::ios
{
performance_state get_performance_state()
{
    NSProcessInfo* process_info = NSProcessInfo.processInfo;
    performance_state state;
    state.thermal = convert_thermal_state(process_info.thermalState);
    state.low_power_mode = process_info.lowPowerModeEnabled;
    state.physical_memory = process_info.physicalMemory;
    return state;
}

void set_performance_callback(performance_callback callback)
{
    {
        std::lock_guard lock(g_performance_callback_mutex);
        g_performance_callback = std::move(callback);
    }

    const auto update_observer = ^{
        bool has_callback = false;
        {
            std::lock_guard lock(g_performance_callback_mutex);
            has_callback = static_cast<bool>(g_performance_callback);
        }

        if (has_callback && !g_performance_observer)
        {
            g_performance_observer = [[RPCS3PerformanceObserver alloc] init];
        }
        else if (!has_callback)
        {
            g_performance_observer = nil;
        }
    };

    if (NSThread.isMainThread)
    {
        update_observer();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), update_observer);
    }
}

void set_idle_timer_disabled(bool disabled)
{
    const auto update_idle_timer = ^{
        UIApplication.sharedApplication.idleTimerDisabled = disabled;
    };

    if (NSThread.isMainThread)
    {
        update_idle_timer();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), update_idle_timer);
    }
}
}
