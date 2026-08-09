#pragma once

#include <cstddef>

struct ios_controller_snapshot
{
	bool connected{};
	float left_x{};
	float left_y{};
	float right_x{};
	float right_y{};
	float left_trigger{};
	float right_trigger{};
	float acceleration_x{};
	float acceleration_y{};
	float acceleration_z{};
	float rotation_x{};
	float rotation_y{};
	float rotation_z{};
	float battery_level{1.0f};
	bool charging{};
	bool button_a{};
	bool button_b{};
	bool button_x{};
	bool button_y{};
	bool dpad_left{};
	bool dpad_right{};
	bool dpad_up{};
	bool dpad_down{};
	bool left_shoulder{};
	bool right_shoulder{};
	bool left_stick{};
	bool right_stick{};
	bool menu{};
	bool options{};
	bool home{};
};

void ios_controller_start();
void ios_controller_stop();
std::size_t ios_controller_count();
bool ios_controller_read(std::size_t index, ios_controller_snapshot& snapshot);
void ios_controller_rumble(std::size_t index, float low_frequency, float high_frequency);
