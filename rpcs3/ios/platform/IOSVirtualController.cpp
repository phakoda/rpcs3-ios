#include "IOSPlatform.h"
#include "IOSControllerFeatures.h"

#include <algorithm>
#include <cstddef>
#include <mutex>
#include <utility>

namespace
{
std::mutex g_virtual_controller_mutex;
rpcs3::ios::controller_state g_virtual_controller;

std::vector<rpcs3::ios::controller_state> sorted_hardware_controllers()
{
    rpcs3::ios::detail::normalize_hardware_controller_slots();
    std::vector<rpcs3::ios::controller_state> controllers = rpcs3::ios::get_controller_states();
    std::stable_sort(controllers.begin(), controllers.end(), [](const auto& lhs, const auto& rhs)
    {
        const int lhs_slot = lhs.player_index < 0 ? 1000 : lhs.player_index;
        const int rhs_slot = rhs.player_index < 0 ? 1000 : rhs.player_index;
        return lhs_slot < rhs_slot;
    });
    return controllers;
}

std::size_t hardware_controller_count()
{
    return sorted_hardware_controllers().size();
}
}

namespace rpcs3::ios
{
void set_virtual_controller_state(controller_state state)
{
    state.player_index = 0;
    state.vendor_name = "RPCS3 Touch Controller";
    state.connected = true;
    state.has_extended_gamepad = true;

    std::lock_guard lock(g_virtual_controller_mutex);
    g_virtual_controller = std::move(state);
}

bool get_virtual_controller_state(controller_state* state)
{
    if (!state)
    {
        return false;
    }

    std::lock_guard lock(g_virtual_controller_mutex);
    if (!g_virtual_controller.connected)
    {
        return false;
    }

    *state = g_virtual_controller;
    return true;
}

void clear_virtual_controller_state()
{
    std::lock_guard lock(g_virtual_controller_mutex);
    g_virtual_controller = {};
}

std::vector<controller_state> get_combined_controller_states()
{
    std::vector<controller_state> controllers = sorted_hardware_controllers();

    controller_state virtual_controller;
    if (get_virtual_controller_state(&virtual_controller))
    {
        controllers.emplace_back(std::move(virtual_controller));
    }

    for (std::size_t index = 0; index < controllers.size(); ++index)
    {
        controllers[index].player_index = static_cast<int>(index);
    }
    return controllers;
}

bool get_combined_controller_state(std::size_t logical_index, controller_state* state)
{
    if (!state)
    {
        return false;
    }

    std::vector<controller_state> controllers = get_combined_controller_states();
    if (logical_index >= controllers.size())
    {
        return false;
    }

    *state = std::move(controllers[logical_index]);
    return true;
}

controller_capabilities get_combined_controller_capabilities(std::size_t logical_index)
{
    const std::size_t hardware_count = hardware_controller_count();
    if (logical_index < hardware_count)
    {
        return detail::get_hardware_controller_capabilities(logical_index);
    }

    controller_state virtual_controller;
    if (logical_index == hardware_count && get_virtual_controller_state(&virtual_controller))
    {
        controller_capabilities result;
        result.has_motion = detail::get_device_motion().available;
        result.has_haptics = true;
        return result;
    }
    return {};
}

controller_motion_state get_combined_controller_motion(std::size_t logical_index)
{
    const std::size_t hardware_count = hardware_controller_count();
    if (logical_index < hardware_count)
    {
        controller_motion_state motion = detail::get_hardware_controller_motion(logical_index);
        if (motion.available)
        {
            return motion;
        }
        return detail::get_device_motion();
    }

    controller_state virtual_controller;
    if (logical_index == hardware_count && get_virtual_controller_state(&virtual_controller))
    {
        return detail::get_device_motion();
    }
    return {};
}

bool set_combined_controller_rumble(std::size_t logical_index, float low_frequency, float high_frequency)
{
    const std::size_t hardware_count = hardware_controller_count();
    if (logical_index < hardware_count)
    {
        if (detail::set_hardware_controller_rumble(logical_index, low_frequency, high_frequency))
        {
            return true;
        }
        return detail::set_device_rumble(low_frequency, high_frequency);
    }

    controller_state virtual_controller;
    if (logical_index == hardware_count && get_virtual_controller_state(&virtual_controller))
    {
        return detail::set_device_rumble(low_frequency, high_frequency);
    }
    return false;
}

void stop_all_controller_haptics()
{
    detail::stop_controller_feature_services();
}
}
