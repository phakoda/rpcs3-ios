#include "stdafx.h"
#include "ios_pad_handler.h"
#include "Emu/Io/pad_config.h"

#include <algorithm>
#include <charconv>
#include <cmath>

namespace
{
	constexpr std::string_view c_device_prefix = "iOS Controller #";

	u16 axis_value(float value, bool positive)
	{
		value = std::clamp(value, -1.0f, 1.0f);
		const float directed = positive ? value : -value;
		return static_cast<u16>(std::max(0.0f, directed) * 32767.0f);
	}

	u16 pressed(bool value)
	{
		return value ? 255 : 0;
	}
}

ios_pad_handler::ios_pad_handler()
	: PadHandlerBase(pad_handler::ios)
{
	button_list = {
		{none, ""}, {button_a, "A / Cross"}, {button_b, "B / Circle"},
		{button_x, "X / Square"}, {button_y, "Y / Triangle"},
		{dpad_left, "D-Pad Left"}, {dpad_right, "D-Pad Right"},
		{dpad_up, "D-Pad Up"}, {dpad_down, "D-Pad Down"},
		{left_shoulder, "L1"}, {right_shoulder, "R1"},
		{left_stick, "L3"}, {right_stick, "R3"},
		{menu, "Start"}, {options, "Select"}, {home, "PS"},
		{left_trigger, "L2"}, {right_trigger, "R2"},
		{left_x_negative, "Left Stick X-"}, {left_x_positive, "Left Stick X+"},
		{left_y_negative, "Left Stick Y-"}, {left_y_positive, "Left Stick Y+"},
		{right_x_negative, "Right Stick X-"}, {right_x_positive, "Right Stick X+"},
		{right_y_negative, "Right Stick Y-"}, {right_y_positive, "Right Stick Y+"},
	};

	init_configs();
	thumb_max = 32767;
	trigger_min = 0;
	trigger_max = 255;
	b_has_config = true;
	b_has_rumble = true;
	b_has_deadzones = true;
	b_has_battery = true;
	b_has_motion = true;
	b_has_orientation = true;
	m_max_devices = MAX_GAMEPADS;
	m_name_string = std::string(c_device_prefix);
	m_trigger_threshold = 0;
	m_thumb_threshold = thumb_max / 2;
}

ios_pad_handler::~ios_pad_handler()
{
	ios_controller_stop();
}

std::string ios_pad_handler::device_name(std::size_t index)
{
	return fmt::format("iOS Controller #%u", index + 1);
}

int ios_pad_handler::device_index(std::string_view name)
{
	if (!name.starts_with(c_device_prefix))
	{
		return -1;
	}
	const std::string_view suffix = name.substr(c_device_prefix.size());
	u64 number = 0;
	const auto [end, error] = std::from_chars(suffix.data(), suffix.data() + suffix.size(), number);
	if (error != std::errc{} || end != suffix.data() + suffix.size())
	{
		return -1;
	}
	return number >= 1 && number <= MAX_GAMEPADS ? static_cast<int>(number - 1) : -1;
}

bool ios_pad_handler::Init()
{
	if (!m_is_init)
	{
		ios_controller_start();
		m_is_init = true;
	}
	return true;
}

std::vector<pad_list_entry> ios_pad_handler::list_devices()
{
	Init();
	std::vector<pad_list_entry> result;
	const std::size_t count = std::min<std::size_t>(ios_controller_count(), MAX_GAMEPADS);
	for (std::size_t index = 0; index < count; ++index)
	{
		result.emplace_back(device_name(index), false);
	}
	return result;
}

void ios_pad_handler::init_config(cfg_pad* cfg)
{
	if (!cfg)
	{
		return;
	}
	cfg->ls_left.def = ::at32(button_list, left_x_negative);
	cfg->ls_down.def = ::at32(button_list, left_y_negative);
	cfg->ls_right.def = ::at32(button_list, left_x_positive);
	cfg->ls_up.def = ::at32(button_list, left_y_positive);
	cfg->rs_left.def = ::at32(button_list, right_x_negative);
	cfg->rs_down.def = ::at32(button_list, right_y_negative);
	cfg->rs_right.def = ::at32(button_list, right_x_positive);
	cfg->rs_up.def = ::at32(button_list, right_y_positive);
	cfg->start.def = ::at32(button_list, menu);
	cfg->select.def = ::at32(button_list, options);
	cfg->ps.def = cfg_pad::make_button_string(button_list, {{home}, {menu, options}});
	cfg->square.def = ::at32(button_list, button_x);
	cfg->cross.def = ::at32(button_list, button_a);
	cfg->circle.def = ::at32(button_list, button_b);
	cfg->triangle.def = ::at32(button_list, button_y);
	cfg->left.def = ::at32(button_list, dpad_left);
	cfg->down.def = ::at32(button_list, dpad_down);
	cfg->right.def = ::at32(button_list, dpad_right);
	cfg->up.def = ::at32(button_list, dpad_up);
	cfg->r1.def = ::at32(button_list, right_shoulder);
	cfg->r2.def = ::at32(button_list, right_trigger);
	cfg->r3.def = ::at32(button_list, right_stick);
	cfg->l1.def = ::at32(button_list, left_shoulder);
	cfg->l2.def = ::at32(button_list, left_trigger);
	cfg->l3.def = ::at32(button_list, left_stick);
	cfg->pressure_intensity_button.def = ::at32(button_list, none);
	cfg->analog_limiter_button.def = ::at32(button_list, none);
	cfg->orientation_reset_button.def = ::at32(button_list, none);
	cfg->lstick_anti_deadzone.def = static_cast<u32>(0.13 * thumb_max);
	cfg->rstick_anti_deadzone.def = static_cast<u32>(0.13 * thumb_max);
	cfg->lstickdeadzone.def = static_cast<u32>(0.08 * thumb_max);
	cfg->rstickdeadzone.def = static_cast<u32>(0.08 * thumb_max);
	cfg->ltriggerthreshold.def = 0;
	cfg->rtriggerthreshold.def = 0;
	cfg->from_default();
}

std::shared_ptr<PadDevice> ios_pad_handler::get_device(const std::string& device)
{
	const int index = device_index(device);
	if (index < 0)
	{
		return nullptr;
	}
	auto result = std::make_shared<ios_device>();
	result->index = index;
	return result;
}

PadHandlerBase::connection ios_pad_handler::update_connection(const std::shared_ptr<PadDevice>& device)
{
	auto* ios = static_cast<ios_device*>(device.get());
	if (!ios)
	{
		return connection::disconnected;
	}
	return ios_controller_read(ios->index, ios->snapshot) ? connection::connected : connection::disconnected;
}

std::unordered_map<u32, u16> ios_pad_handler::get_button_values(const std::shared_ptr<PadDevice>& device)
{
	const auto* ios = static_cast<const ios_device*>(device.get());
	if (!ios || !ios->snapshot.connected)
	{
		return {};
	}
	const auto& state = ios->snapshot;
	return {
		{button_a, pressed(state.button_a)}, {button_b, pressed(state.button_b)},
		{button_x, pressed(state.button_x)}, {button_y, pressed(state.button_y)},
		{dpad_left, pressed(state.dpad_left)}, {dpad_right, pressed(state.dpad_right)},
		{dpad_up, pressed(state.dpad_up)}, {dpad_down, pressed(state.dpad_down)},
		{left_shoulder, pressed(state.left_shoulder)}, {right_shoulder, pressed(state.right_shoulder)},
		{left_stick, pressed(state.left_stick)}, {right_stick, pressed(state.right_stick)},
		{menu, pressed(state.menu)}, {options, pressed(state.options)}, {home, pressed(state.home)},
		{left_trigger, static_cast<u16>(state.left_trigger * 255.0f)},
		{right_trigger, static_cast<u16>(state.right_trigger * 255.0f)},
		{left_x_negative, axis_value(state.left_x, false)},
		{left_x_positive, axis_value(state.left_x, true)},
		{left_y_negative, axis_value(state.left_y, false)},
		{left_y_positive, axis_value(state.left_y, true)},
		{right_x_negative, axis_value(state.right_x, false)},
		{right_x_positive, axis_value(state.right_x, true)},
		{right_y_negative, axis_value(state.right_y, false)},
		{right_y_positive, axis_value(state.right_y, true)},
	};
}

bool ios_pad_handler::get_is_left_trigger(const std::shared_ptr<PadDevice>&, u32 key) { return key == left_trigger; }
bool ios_pad_handler::get_is_right_trigger(const std::shared_ptr<PadDevice>&, u32 key) { return key == right_trigger; }

bool ios_pad_handler::get_is_left_stick(const std::shared_ptr<PadDevice>&, u32 key)
{
	return key >= left_x_negative && key <= left_y_positive;
}

bool ios_pad_handler::get_is_right_stick(const std::shared_ptr<PadDevice>&, u32 key)
{
	return key >= right_x_negative && key <= right_y_positive;
}

void ios_pad_handler::SetPadData(const std::string& pad_id, u8, u8 large_motor, u8 small_motor,
	s32, s32, s32, bool, bool, u32)
{
	const int index = device_index(pad_id);
	if (index >= 0)
	{
		ios_controller_rumble(index, large_motor / 255.0f, small_motor / 255.0f);
	}
}

u32 ios_pad_handler::get_battery_level(const std::string& pad_id)
{
	ios_controller_snapshot snapshot{};
	const int index = device_index(pad_id);
	return index >= 0 && ios_controller_read(index, snapshot)
		? static_cast<u32>(snapshot.battery_level * 100.0f) : 0;
}

void ios_pad_handler::get_extended_info(const pad_ensemble& binding)
{
	const auto* ios = static_cast<const ios_device*>(binding.device.get());
	if (!ios || !binding.pad)
	{
		return;
	}
	const auto sensor = [](float value, float scale)
	{
		return static_cast<u16>(std::clamp(512.0f + value * scale, 0.0f, 1023.0f));
	};
	binding.pad->m_battery_level = static_cast<u8>(std::clamp(ios->snapshot.battery_level * 5.0f, 0.0f, 5.0f));
	binding.pad->m_cable_state = ios->snapshot.charging ? 1 : 0;
	binding.pad->m_sensors[0].m_value = sensor(ios->snapshot.acceleration_x, 113.0f);
	binding.pad->m_sensors[1].m_value = sensor(ios->snapshot.acceleration_y, 113.0f);
	binding.pad->m_sensors[2].m_value = sensor(ios->snapshot.acceleration_z, 113.0f);
	binding.pad->m_sensors[3].m_value = sensor(ios->snapshot.rotation_y, 64.0f);
	set_raw_orientation(*binding.pad);
}

void ios_pad_handler::apply_pad_data(const pad_ensemble& binding)
{
	auto* ios = static_cast<ios_device*>(binding.device.get());
	if (!ios || !ios->config || !binding.pad)
	{
		return;
	}
	const u8 large = ios->config->get_large_motor_speed(binding.pad->m_vibrate_motors);
	const u8 small = ios->config->get_small_motor_speed(binding.pad->m_vibrate_motors);
	const auto now = steady_clock::now();
	if (ios->large_motor != large || ios->small_motor != small || now - ios->last_output > min_output_interval)
	{
		ios->large_motor = large;
		ios->small_motor = small;
		ios->last_output = now;
		ios_controller_rumble(ios->index, large / 255.0f, small / 255.0f);
	}
}

pad_preview_values ios_pad_handler::get_preview_values(const std::unordered_map<u32, u16>& data,
	const std::vector<std::string>&)
{
	return {
		::at32(data, left_trigger), ::at32(data, right_trigger),
		::at32(data, left_x_positive) - ::at32(data, left_x_negative),
		::at32(data, left_y_positive) - ::at32(data, left_y_negative),
		::at32(data, right_x_positive) - ::at32(data, right_x_negative),
		::at32(data, right_y_positive) - ::at32(data, right_y_negative),
	};
}
