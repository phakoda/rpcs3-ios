#ifdef RPCS3_IOS

#include "stdafx.h"
#include "ios_gamecontroller_pad_handler.h"
#include "ios/platform/IOSPlatform.h"

#include <algorithm>
#include <cmath>

namespace
{
u16 button_value(bool pressed)
{
    return pressed ? 255 : 0;
}

u16 axis_direction(float value, bool positive)
{
    const float directed = positive ? value : -value;
    return PadHandlerBase::Clamp0To255(std::max(0.0f, directed) * 255.0f);
}

bool contains_key(const std::vector<std::set<u32>>& combinations, u32 key_code)
{
    return std::any_of(combinations.cbegin(), combinations.cend(), [key_code](const std::set<u32>& combination)
    {
        return combination.contains(key_code);
    });
}

bool contains_axis_key(const std::array<std::vector<std::set<u32>>, 4>& axes, u32 key_code)
{
    return std::any_of(axes.cbegin(), axes.cend(), [key_code](const std::vector<std::set<u32>>& combinations)
    {
        return contains_key(combinations, key_code);
    });
}
}

ios_gamecontroller_pad_handler::ios_gamecontroller_pad_handler()
    : PadHandlerBase(pad_handler::ios_gamecontroller)
{
    button_list =
    {
        { key_none, "" },
        { key_dpad_up, "D-Pad Up" },
        { key_dpad_down, "D-Pad Down" },
        { key_dpad_left, "D-Pad Left" },
        { key_dpad_right, "D-Pad Right" },
        { key_a, "Button A" },
        { key_b, "Button B" },
        { key_x, "Button X" },
        { key_y, "Button Y" },
        { key_l1, "Left Shoulder" },
        { key_r1, "Right Shoulder" },
        { key_l2, "Left Trigger" },
        { key_r2, "Right Trigger" },
        { key_l3, "Left Thumbstick" },
        { key_r3, "Right Thumbstick" },
        { key_menu, "Menu" },
        { key_options, "Options" },
        { key_home, "Home" },
        { key_ls_left, "Left Stick Left" },
        { key_ls_right, "Left Stick Right" },
        { key_ls_down, "Left Stick Down" },
        { key_ls_up, "Left Stick Up" },
        { key_rs_left, "Right Stick Left" },
        { key_rs_right, "Right Stick Right" },
        { key_rs_down, "Right Stick Down" },
        { key_rs_up, "Right Stick Up" },
    };

    thumb_max = 255;
    trigger_min = 0;
    trigger_max = 255;
    m_trigger_threshold = trigger_max / 2;
    m_thumb_threshold = thumb_max / 2;
    m_max_devices = MAX_GAMEPADS;
    m_name_string = "iOS Controller ";

    b_has_config = true;
    b_has_deadzones = true;
    b_has_rumble = false;
    b_has_motion = false;
    b_has_pressure_intensity_button = false;
    b_has_analog_limiter_button = false;

    init_configs();
}

bool ios_gamecontroller_pad_handler::Init()
{
    m_is_init = true;
    return true;
}

std::string ios_gamecontroller_pad_handler::device_name(usz index)
{
    return "iOS Controller " + std::to_string(index + 1);
}

bool ios_gamecontroller_pad_handler::parse_device_index(std::string_view name, usz* index)
{
    constexpr std::string_view prefix = "iOS Controller ";
    if (!index || !name.starts_with(prefix))
    {
        return false;
    }

    u64 parsed = 0;
    if (!try_to_uint64(&parsed, name.substr(prefix.size()), 1, MAX_GAMEPADS))
    {
        return false;
    }

    *index = static_cast<usz>(parsed - 1);
    return true;
}

std::vector<pad_list_entry> ios_gamecontroller_pad_handler::list_devices()
{
    std::vector<pad_list_entry> devices;
    const auto controllers = rpcs3::ios::get_controller_states();
    devices.reserve(std::max<usz>(controllers.size(), 1));

    for (usz index = 0; index < controllers.size() && index < MAX_GAMEPADS; ++index)
    {
        devices.emplace_back(device_name(index), false);
    }

    // Keep a stable first device available in configuration UIs even before a
    // controller is connected. The connection state will remain disconnected.
    if (devices.empty())
    {
        devices.emplace_back(device_name(0), false);
    }
    return devices;
}

void ios_gamecontroller_pad_handler::init_config(cfg_pad* cfg)
{
    if (!cfg)
    {
        return;
    }

    // Apple labels face buttons by physical position. Map them to the matching
    // PlayStation layout rather than matching the letters printed by Xbox-style
    // controllers: bottom=A/Cross, left=X/Square, right=B/Circle, top=Y/Triangle.
    cfg->cross.def = ::at32(button_list, key_a);
    cfg->circle.def = ::at32(button_list, key_b);
    cfg->square.def = ::at32(button_list, key_x);
    cfg->triangle.def = ::at32(button_list, key_y);
    cfg->up.def = ::at32(button_list, key_dpad_up);
    cfg->down.def = ::at32(button_list, key_dpad_down);
    cfg->left.def = ::at32(button_list, key_dpad_left);
    cfg->right.def = ::at32(button_list, key_dpad_right);
    cfg->l1.def = ::at32(button_list, key_l1);
    cfg->r1.def = ::at32(button_list, key_r1);
    cfg->l2.def = ::at32(button_list, key_l2);
    cfg->r2.def = ::at32(button_list, key_r2);
    cfg->l3.def = ::at32(button_list, key_l3);
    cfg->r3.def = ::at32(button_list, key_r3);
    cfg->start.def = ::at32(button_list, key_menu);
    cfg->select.def = ::at32(button_list, key_options);
    cfg->ps.def = ::at32(button_list, key_home);
    cfg->ls_left.def = ::at32(button_list, key_ls_left);
    cfg->ls_right.def = ::at32(button_list, key_ls_right);
    cfg->ls_down.def = ::at32(button_list, key_ls_down);
    cfg->ls_up.def = ::at32(button_list, key_ls_up);
    cfg->rs_left.def = ::at32(button_list, key_rs_left);
    cfg->rs_right.def = ::at32(button_list, key_rs_right);
    cfg->rs_down.def = ::at32(button_list, key_rs_down);
    cfg->rs_up.def = ::at32(button_list, key_rs_up);
    cfg->pressure_intensity_button.def = ::at32(button_list, key_none);
    cfg->analog_limiter_button.def = ::at32(button_list, key_none);
    cfg->orientation_reset_button.def = ::at32(button_list, key_none);

    cfg->lstick_anti_deadzone.def = static_cast<u32>(0.13f * thumb_max);
    cfg->rstick_anti_deadzone.def = static_cast<u32>(0.13f * thumb_max);
    cfg->lstickdeadzone.def = static_cast<u32>(0.08f * thumb_max);
    cfg->rstickdeadzone.def = static_cast<u32>(0.08f * thumb_max);
    cfg->ltriggerthreshold.def = 0;
    cfg->rtriggerthreshold.def = 0;
    cfg->from_default();
}

std::array<std::vector<std::set<u32>>, PadHandlerBase::button::button_count>
ios_gamecontroller_pad_handler::get_mapped_key_codes(const std::shared_ptr<PadDevice>& device, const cfg_pad* cfg)
{
    const auto mapping = PadHandlerBase::get_mapped_key_codes(device, cfg);
    if (auto* controller = static_cast<ios_device*>(device.get()))
    {
        controller->trigger_code_left = mapping[button::l2];
        controller->trigger_code_right = mapping[button::r2];
        controller->axis_code_left[0] = mapping[button::ls_left];
        controller->axis_code_left[1] = mapping[button::ls_right];
        controller->axis_code_left[2] = mapping[button::ls_down];
        controller->axis_code_left[3] = mapping[button::ls_up];
        controller->axis_code_right[0] = mapping[button::rs_left];
        controller->axis_code_right[1] = mapping[button::rs_right];
        controller->axis_code_right[2] = mapping[button::rs_down];
        controller->axis_code_right[3] = mapping[button::rs_up];
    }
    return mapping;
}

std::shared_ptr<PadDevice> ios_gamecontroller_pad_handler::get_device(const std::string& device)
{
    if (!Init())
    {
        return nullptr;
    }

    if (const auto found = m_devices.find(device); found != m_devices.end())
    {
        return found->second;
    }

    usz index = 0;
    if (!parse_device_index(device, &index))
    {
        return nullptr;
    }

    auto result = std::make_shared<ios_device>();
    result->controller_index = index;
    result->device_name = device;
    m_devices.emplace(device, result);
    return result;
}

bool ios_gamecontroller_pad_handler::get_is_left_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code)
{
    const auto* controller = static_cast<const ios_device*>(device.get());
    return controller && contains_key(controller->trigger_code_left, key_code);
}

bool ios_gamecontroller_pad_handler::get_is_right_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code)
{
    const auto* controller = static_cast<const ios_device*>(device.get());
    return controller && contains_key(controller->trigger_code_right, key_code);
}

bool ios_gamecontroller_pad_handler::get_is_left_stick(const std::shared_ptr<PadDevice>& device, u32 key_code)
{
    const auto* controller = static_cast<const ios_device*>(device.get());
    return controller && contains_axis_key(controller->axis_code_left, key_code);
}

bool ios_gamecontroller_pad_handler::get_is_right_stick(const std::shared_ptr<PadDevice>& device, u32 key_code)
{
    const auto* controller = static_cast<const ios_device*>(device.get());
    return controller && contains_axis_key(controller->axis_code_right, key_code);
}

PadHandlerBase::connection ios_gamecontroller_pad_handler::update_connection(const std::shared_ptr<PadDevice>& device)
{
    const auto* controller = static_cast<const ios_device*>(device.get());
    if (!controller)
    {
        return connection::disconnected;
    }

    const auto controllers = rpcs3::ios::get_controller_states();
    if (controller->controller_index >= controllers.size())
    {
        return connection::disconnected;
    }
    return controllers[controller->controller_index].connected ? connection::connected : connection::disconnected;
}

std::unordered_map<u32, u16> ios_gamecontroller_pad_handler::get_button_values(const std::shared_ptr<PadDevice>& device)
{
    std::unordered_map<u32, u16> values;
    for (const auto& [key, name] : button_list)
    {
        (void)name;
        values.emplace(key, 0);
    }

    const auto* controller = static_cast<const ios_device*>(device.get());
    if (!controller)
    {
        return values;
    }

    const auto controllers = rpcs3::ios::get_controller_states();
    if (controller->controller_index >= controllers.size())
    {
        return values;
    }

    const rpcs3::ios::controller_state& state = controllers[controller->controller_index];
    values[key_dpad_up] = button_value(state.dpad_up);
    values[key_dpad_down] = button_value(state.dpad_down);
    values[key_dpad_left] = button_value(state.dpad_left);
    values[key_dpad_right] = button_value(state.dpad_right);
    values[key_a] = button_value(state.button_a);
    values[key_b] = button_value(state.button_b);
    values[key_x] = button_value(state.button_x);
    values[key_y] = button_value(state.button_y);
    values[key_l1] = button_value(state.left_shoulder);
    values[key_r1] = button_value(state.right_shoulder);
    values[key_l2] = Clamp0To255(state.left_trigger * 255.0f);
    values[key_r2] = Clamp0To255(state.right_trigger * 255.0f);
    values[key_l3] = button_value(state.left_thumbstick);
    values[key_r3] = button_value(state.right_thumbstick);
    values[key_menu] = button_value(state.menu);
    values[key_options] = button_value(state.options);
    values[key_home] = button_value(state.home);
    values[key_ls_left] = axis_direction(state.left_x, false);
    values[key_ls_right] = axis_direction(state.left_x, true);
    values[key_ls_down] = axis_direction(state.left_y, false);
    values[key_ls_up] = axis_direction(state.left_y, true);
    values[key_rs_left] = axis_direction(state.right_x, false);
    values[key_rs_right] = axis_direction(state.right_x, true);
    values[key_rs_down] = axis_direction(state.right_y, false);
    values[key_rs_up] = axis_direction(state.right_y, true);
    return values;
}

pad_preview_values ios_gamecontroller_pad_handler::get_preview_values(const std::unordered_map<u32, u16>& data, const std::vector<std::string>& buttons)
{
    pad_preview_values preview{};
    if (buttons.size() != 10)
    {
        return preview;
    }

    const auto configured_value = [this, &data](std::string_view configured) -> u16
    {
        u16 result = 0;
        for (const std::set<u32>& combination : find_key_combos(button_list, configured))
        {
            bool pressed = !combination.empty();
            u16 combination_value = 255;
            for (u32 code : combination)
            {
                const auto found = data.find(code);
                if (found == data.end() || found->second == 0)
                {
                    pressed = false;
                    break;
                }
                combination_value = std::min(combination_value, found->second);
            }
            if (pressed)
            {
                result = std::max(result, combination_value);
            }
        }
        return result;
    };

    preview[0] = configured_value(buttons[0]);
    preview[1] = configured_value(buttons[1]);
    preview[2] = configured_value(buttons[3]) - configured_value(buttons[2]);
    preview[3] = configured_value(buttons[5]) - configured_value(buttons[4]);
    preview[4] = configured_value(buttons[7]) - configured_value(buttons[6]);
    preview[5] = configured_value(buttons[9]) - configured_value(buttons[8]);
    return preview;
}

#endif
