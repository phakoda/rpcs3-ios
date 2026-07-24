#include "IOSPlatform.h"

#include <mutex>
#include <utility>

namespace
{
std::mutex g_virtual_controller_mutex;
rpcs3::ios::controller_state g_virtual_controller;
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
    std::vector<controller_state> controllers;
    controller_state virtual_controller;
    if (get_virtual_controller_state(&virtual_controller))
    {
        controllers.emplace_back(std::move(virtual_controller));
    }

    std::vector<controller_state> hardware = get_controller_states();
    controllers.reserve(controllers.size() + hardware.size());
    for (controller_state& controller : hardware)
    {
        controller.player_index = static_cast<int>(controllers.size());
        controllers.emplace_back(std::move(controller));
    }
    return controllers;
}
}
