#include "IOSControllerFeatures.h"

#import <CoreHaptics/CoreHaptics.h>
#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>
#include <mutex>

namespace
{
using namespace rpcs3::ios;
constexpr float radians_to_degrees = 57.29577951308232f;
constexpr std::size_t gamecontroller_player_slots = 4;

controller_battery_state convert_battery_state(GCDeviceBatteryState state)
{
    switch (state)
    {
    case GCDeviceBatteryStateDischarging: return controller_battery_state::discharging;
    case GCDeviceBatteryStateCharging: return controller_battery_state::charging;
    case GCDeviceBatteryStateFull: return controller_battery_state::full;
    case GCDeviceBatteryStateUnknown: break;
    }
    return controller_battery_state::unknown;
}

NSArray<GCController*>* hardware_controllers()
{
    return GCController.controllers;
}

NSArray<GCController*>* normalized_controllers()
{
    NSArray<GCController*>* sorted = [hardware_controllers() sortedArrayUsingComparator:^NSComparisonResult(GCController* lhs, GCController* rhs)
    {
        const NSInteger lhs_index = lhs.playerIndex == GCControllerPlayerIndexUnset ? NSIntegerMax : lhs.playerIndex;
        const NSInteger rhs_index = rhs.playerIndex == GCControllerPlayerIndexUnset ? NSIntegerMax : rhs.playerIndex;
        if (lhs_index < rhs_index) return NSOrderedAscending;
        if (lhs_index > rhs_index) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    const NSUInteger count = std::min<NSUInteger>(sorted.count, gamecontroller_player_slots);
    for (NSUInteger index = 0; index < count; ++index)
    {
        sorted[index].playerIndex = static_cast<GCControllerPlayerIndex>(index);
    }
    for (NSUInteger index = count; index < sorted.count; ++index)
    {
        sorted[index].playerIndex = GCControllerPlayerIndexUnset;
    }
    return sorted;
}

GCController* controller_at_index(std::size_t index)
{
    NSArray<GCController*>* controllers = normalized_controllers();
    return index < controllers.count ? controllers[index] : nil;
}

@interface RPCS3HapticDriver : NSObject
- (instancetype)initWithEngine:(CHHapticEngine*)engine;
- (BOOL)setLowFrequency:(float)low highFrequency:(float)high;
- (void)stop;
@end

@implementation RPCS3HapticDriver
{
    CHHapticEngine* _engine;
    id<CHHapticAdvancedPatternPlayer> _low_player;
    id<CHHapticAdvancedPatternPlayer> _high_player;
    BOOL _started;
}

- (instancetype)initWithEngine:(CHHapticEngine*)engine
{
    self = [super init];
    if (!self || !engine)
    {
        return nil;
    }

    _engine = engine;
    __weak RPCS3HapticDriver* weak_self = self;
    _engine.resetHandler = ^{
        RPCS3HapticDriver* strong_self = weak_self;
        if (strong_self)
        {
            strong_self->_started = NO;
        }
    };
    _engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason)
    {
        (void)reason;
        RPCS3HapticDriver* strong_self = weak_self;
        if (strong_self)
        {
            strong_self->_started = NO;
        }
    };

    NSError* error = nil;
    CHHapticEventParameter* intensity = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.0f];
    CHHapticEventParameter* low_sharpness = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.0f];
    CHHapticEventParameter* high_sharpness = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness value:1.0f];

    CHHapticEvent* low_event = [[CHHapticEvent alloc]
        initWithEventType:CHHapticEventTypeHapticContinuous
        parameters:@[intensity, low_sharpness]
        relativeTime:0.0
        duration:10.0];
    CHHapticEvent* high_event = [[CHHapticEvent alloc]
        initWithEventType:CHHapticEventTypeHapticContinuous
        parameters:@[intensity, high_sharpness]
        relativeTime:0.0
        duration:10.0];

    CHHapticPattern* low_pattern = [[CHHapticPattern alloc] initWithEvents:@[low_event] parameters:@[] error:&error];
    if (!low_pattern)
    {
        return nil;
    }
    CHHapticPattern* high_pattern = [[CHHapticPattern alloc] initWithEvents:@[high_event] parameters:@[] error:&error];
    if (!high_pattern)
    {
        return nil;
    }

    _low_player = [_engine createAdvancedPlayerWithPattern:low_pattern error:&error];
    _high_player = [_engine createAdvancedPlayerWithPattern:high_pattern error:&error];
    if (!_low_player || !_high_player)
    {
        return nil;
    }

    _low_player.loopEnabled = YES;
    _low_player.loopEnd = 10.0;
    _high_player.loopEnabled = YES;
    _high_player.loopEnd = 10.0;
    return self;
}

- (BOOL)startIfNeeded
{
    if (_started)
    {
        return YES;
    }

    NSError* error = nil;
    if (![_engine startAndReturnError:&error])
    {
        return NO;
    }
    if (![_low_player startAtTime:CHHapticTimeImmediate error:&error] ||
        ![_high_player startAtTime:CHHapticTimeImmediate error:&error])
    {
        return NO;
    }

    _started = YES;
    return YES;
}

- (BOOL)setLowFrequency:(float)low highFrequency:(float)high
{
    low = std::clamp(low, 0.0f, 1.0f);
    high = std::clamp(high, 0.0f, 1.0f);
    if (low <= 0.0f && high <= 0.0f && !_started)
    {
        return YES;
    }
    if (![self startIfNeeded])
    {
        return NO;
    }

    CHHapticDynamicParameter* low_parameter = [[CHHapticDynamicParameter alloc]
        initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:low relativeTime:0.0];
    CHHapticDynamicParameter* high_parameter = [[CHHapticDynamicParameter alloc]
        initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:high relativeTime:0.0];

    NSError* error = nil;
    return [_low_player sendParameters:@[low_parameter] atTime:CHHapticTimeImmediate error:&error] &&
        [_high_player sendParameters:@[high_parameter] atTime:CHHapticTimeImmediate error:&error];
}

- (void)stop
{
    if (!_started)
    {
        return;
    }
    NSError* error = nil;
    [_low_player stopAtTime:CHHapticTimeImmediate error:&error];
    [_high_player stopAtTime:CHHapticTimeImmediate error:&error];
    [_engine stopWithCompletionHandler:nil];
    _started = NO;
}
@end

std::mutex g_haptics_mutex;
NSMapTable<GCController*, RPCS3HapticDriver*>* g_controller_haptics = nil;
RPCS3HapticDriver* g_device_haptics = nil;
CMMotionManager* g_device_motion_manager = nil;

RPCS3HapticDriver* hardware_haptic_driver(GCController* controller)
{
    if (!controller || !controller.haptics)
    {
        return nil;
    }

    std::lock_guard lock(g_haptics_mutex);
    if (!g_controller_haptics)
    {
        g_controller_haptics = [NSMapTable weakToStrongObjectsMapTable];
    }

    RPCS3HapticDriver* driver = [g_controller_haptics objectForKey:controller];
    if (!driver)
    {
        CHHapticEngine* engine = [controller.haptics createEngineWithLocality:GCHapticsLocalityAll];
        driver = [[RPCS3HapticDriver alloc] initWithEngine:engine];
        if (driver)
        {
            [g_controller_haptics setObject:driver forKey:controller];
        }
    }
    return driver;
}

RPCS3HapticDriver* device_haptic_driver()
{
    std::lock_guard lock(g_haptics_mutex);
    if (!g_device_haptics && CHHapticEngine.capabilitiesForHardware.supportsHaptics)
    {
        NSError* error = nil;
        CHHapticEngine* engine = [[CHHapticEngine alloc] initAndReturnError:&error];
        if (engine)
        {
            g_device_haptics = [[RPCS3HapticDriver alloc] initWithEngine:engine];
        }
    }
    return g_device_haptics;
}

CMMotionManager* device_motion_manager()
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_device_motion_manager = [[CMMotionManager alloc] init];
        g_device_motion_manager.deviceMotionUpdateInterval = 1.0 / 60.0;
    });
    return g_device_motion_manager;
}

controller_motion_state remap_device_motion(CMDeviceMotion* motion)
{
    controller_motion_state result;
    if (!motion)
    {
        return result;
    }

    const float raw_accel_x = -static_cast<float>(motion.gravity.x + motion.userAcceleration.x);
    const float raw_accel_y = -static_cast<float>(motion.gravity.y + motion.userAcceleration.y);
    const float raw_accel_z = -static_cast<float>(motion.gravity.z + motion.userAcceleration.z);
    const float raw_gyro_x = static_cast<float>(motion.rotationRate.x) * radians_to_degrees;
    const float raw_gyro_y = -static_cast<float>(motion.rotationRate.y) * radians_to_degrees;
    const float raw_gyro_z = -static_cast<float>(motion.rotationRate.z) * radians_to_degrees;

    result.available = true;
    switch (UIDevice.currentDevice.orientation)
    {
    case UIDeviceOrientationLandscapeLeft:
        result.acceleration_x = raw_accel_y;
        result.acceleration_y = -raw_accel_x;
        result.acceleration_z = raw_accel_z;
        result.gyro_x = raw_gyro_y;
        result.gyro_y = -raw_gyro_x;
        result.gyro_z = raw_gyro_z;
        break;
    case UIDeviceOrientationLandscapeRight:
        result.acceleration_x = -raw_accel_y;
        result.acceleration_y = raw_accel_x;
        result.acceleration_z = raw_accel_z;
        result.gyro_x = -raw_gyro_y;
        result.gyro_y = raw_gyro_x;
        result.gyro_z = raw_gyro_z;
        break;
    default:
        result.acceleration_x = raw_accel_x;
        result.acceleration_y = raw_accel_z;
        result.acceleration_z = -raw_accel_y;
        result.gyro_x = raw_gyro_x;
        result.gyro_y = raw_gyro_z;
        result.gyro_z = -raw_gyro_y;
        break;
    }
    return result;
}
}

namespace rpcs3::ios::detail
{
void normalize_hardware_controller_slots()
{
    (void)normalized_controllers();
}

controller_capabilities get_hardware_controller_capabilities(std::size_t index)
{
    controller_capabilities result;
    GCController* controller = controller_at_index(index);
    if (!controller)
    {
        return result;
    }

    result.has_motion = controller.motion != nil;
    result.has_haptics = controller.haptics != nil;
    GCDeviceBattery* battery = controller.battery;
    if (battery)
    {
        result.has_battery = true;
        result.battery_level = battery.batteryLevel;
        result.battery_state = convert_battery_state(battery.batteryState);
    }
    return result;
}

controller_motion_state get_hardware_controller_motion(std::size_t index)
{
    controller_motion_state result;
    GCController* controller = controller_at_index(index);
    GCMotion* motion = controller.motion;
    if (!motion)
    {
        return result;
    }

    motion.sensorsActive = YES;
    result.available = true;
    result.acceleration_x = -static_cast<float>(motion.acceleration.x);
    result.acceleration_y = -static_cast<float>(motion.acceleration.z);
    result.acceleration_z = static_cast<float>(motion.acceleration.y);
    result.gyro_x = static_cast<float>(motion.rotationRate.x) * radians_to_degrees;
    result.gyro_y = static_cast<float>(motion.rotationRate.z) * radians_to_degrees;
    result.gyro_z = -static_cast<float>(motion.rotationRate.y) * radians_to_degrees;
    return result;
}

controller_motion_state get_device_motion()
{
    CMMotionManager* manager = device_motion_manager();
    if (!manager.deviceMotionAvailable)
    {
        return {};
    }

    if (!manager.deviceMotionActive)
    {
        [manager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
    }
    return remap_device_motion(manager.deviceMotion);
}

bool set_hardware_controller_rumble(std::size_t index, float low_frequency, float high_frequency)
{
    RPCS3HapticDriver* driver = hardware_haptic_driver(controller_at_index(index));
    return driver && [driver setLowFrequency:low_frequency highFrequency:high_frequency];
}

bool set_device_rumble(float low_frequency, float high_frequency)
{
    RPCS3HapticDriver* driver = device_haptic_driver();
    return driver && [driver setLowFrequency:low_frequency highFrequency:high_frequency];
}

void stop_controller_feature_services()
{
    std::lock_guard lock(g_haptics_mutex);
    for (RPCS3HapticDriver* driver in g_controller_haptics.objectEnumerator)
    {
        [driver stop];
    }
    [g_controller_haptics removeAllObjects];
    [g_device_haptics stop];
    g_device_haptics = nil;
    [g_device_motion_manager stopDeviceMotionUpdates];
}
}
