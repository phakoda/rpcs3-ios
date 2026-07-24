#include "IOSPlatform.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <dispatch/dispatch.h>
#include <os/proc.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <utility>

namespace
{
std::mutex g_performance_callback_mutex;
rpcs3::ios::performance_callback g_performance_callback;
std::atomic<rpcs3::ios::memory_pressure_level> g_memory_pressure = rpcs3::ios::memory_pressure_level::normal;
dispatch_source_t g_memory_pressure_source = nil;

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

rpcs3::ios::memory_pressure_level pressure_from_flags(unsigned long flags)
{
    using rpcs3::ios::memory_pressure_level;
    if (flags & DISPATCH_MEMORYPRESSURE_CRITICAL)
    {
        return memory_pressure_level::critical;
    }
    if (flags & DISPATCH_MEMORYPRESSURE_WARN)
    {
        return memory_pressure_level::warning;
    }
    if (flags & DISPATCH_MEMORYPRESSURE_NORMAL)
    {
        return memory_pressure_level::normal;
    }
    return memory_pressure_level::unknown;
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

void start_memory_pressure_source()
{
    if (g_memory_pressure_source)
    {
        return;
    }

    g_memory_pressure_source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,
        0,
        DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (!g_memory_pressure_source)
    {
        return;
    }

    dispatch_source_set_event_handler(g_memory_pressure_source, ^{
        const auto pressure = pressure_from_flags(dispatch_source_get_data(g_memory_pressure_source));
        g_memory_pressure.store(pressure);
        deliver_performance_event(rpcs3::ios::performance_event::memory_pressure_changed);
    });
    dispatch_resume(g_memory_pressure_source);
}

void stop_memory_pressure_source()
{
    if (!g_memory_pressure_source)
    {
        return;
    }
    dispatch_source_cancel(g_memory_pressure_source);
    g_memory_pressure_source = nil;
    g_memory_pressure.store(rpcs3::ios::memory_pressure_level::normal);
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
    [center addObserver:self selector:@selector(thermalStateChanged:)
                   name:NSProcessInfoThermalStateDidChangeNotification object:NSProcessInfo.processInfo];
    [center addObserver:self selector:@selector(powerStateChanged:)
                   name:NSProcessInfoPowerStateDidChangeNotification object:NSProcessInfo.processInfo];
    [center addObserver:self selector:@selector(memoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
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
    g_memory_pressure.store(rpcs3::ios::memory_pressure_level::warning);
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
    state.memory_pressure = g_memory_pressure.load();
    state.low_power_mode = process_info.lowPowerModeEnabled;
    state.physical_memory = process_info.physicalMemory;
    state.available_memory = os_proc_available_memory();
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
            start_memory_pressure_source();
        }
        else if (!has_callback)
        {
            g_performance_observer = nil;
            stop_memory_pressure_source();
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
