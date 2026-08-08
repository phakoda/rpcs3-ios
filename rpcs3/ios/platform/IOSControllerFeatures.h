#pragma once

#include "IOSPlatform.h"

namespace rpcs3::ios::detail
{
void normalize_hardware_controller_slots();
controller_capabilities get_hardware_controller_capabilities(std::size_t index);
controller_motion_state get_hardware_controller_motion(std::size_t index);
controller_motion_state get_device_motion();
bool set_hardware_controller_rumble(std::size_t index, float low_frequency, float high_frequency);
bool set_device_rumble(float low_frequency, float high_frequency);
bool has_hardware_controller_light(std::size_t index);
bool set_hardware_controller_light(std::size_t index, float red, float green, float blue);
void stop_controller_feature_services();
}
