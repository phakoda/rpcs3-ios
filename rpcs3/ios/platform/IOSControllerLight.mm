#include "IOSControllerFeatures.h"

#import <GameController/GameController.h>

#include <algorithm>

namespace
{
GCController* controller_for_slot(std::size_t index)
{
    rpcs3::ios::detail::normalize_hardware_controller_slots();
    for (GCController* controller in GCController.controllers)
    {
        if (controller.playerIndex != GCControllerPlayerIndexUnset &&
            static_cast<std::size_t>(controller.playerIndex) == index)
        {
            return controller;
        }
    }
    return nil;
}
}

namespace rpcs3::ios::detail
{
bool has_hardware_controller_light(std::size_t index)
{
    return controller_for_slot(index).light != nil;
}

bool set_hardware_controller_light(std::size_t index, float red, float green, float blue)
{
    GCDeviceLight* light = controller_for_slot(index).light;
    if (!light)
    {
        return false;
    }

    red = std::clamp(red, 0.0f, 1.0f);
    green = std::clamp(green, 0.0f, 1.0f);
    blue = std::clamp(blue, 0.0f, 1.0f);
    light.color = [[GCColor alloc] initWithRed:red green:green blue:blue];
    return true;
}
}
