#pragma once

#include "Emu/Io/PadHandler.h"
#include "ios_controller_bridge.h"

class ios_pad_handler final : public PadHandlerBase
{
	enum key_code
	{
		none,
		button_a,
		button_b,
		button_x,
		button_y,
		dpad_left,
		dpad_right,
		dpad_up,
		dpad_down,
		left_shoulder,
		right_shoulder,
		left_stick,
		right_stick,
		menu,
		options,
		home,
		left_trigger,
		right_trigger,
		left_x_negative,
		left_x_positive,
		left_y_negative,
		left_y_positive,
		right_x_negative,
		right_x_positive,
		right_y_negative,
		right_y_positive,
	};

	struct ios_device final : PadDevice
	{
		std::size_t index{};
		ios_controller_snapshot snapshot{};
	};

public:
	ios_pad_handler();
	~ios_pad_handler() override;

	static std::string device_name(std::size_t index);
	bool Init() override;
	std::vector<pad_list_entry> list_devices() override;
	void init_config(cfg_pad* cfg) override;
	void SetPadData(const std::string& pad_id, u8 player_id, u8 large_motor, u8 small_motor,
		s32 r, s32 g, s32 b, bool player_led, bool battery_led, u32 battery_led_brightness) override;
	u32 get_battery_level(const std::string& pad_id) override;

private:
	static int device_index(std::string_view name);
	std::shared_ptr<PadDevice> get_device(const std::string& device) override;
	connection update_connection(const std::shared_ptr<PadDevice>& device) override;
	std::unordered_map<u32, u16> get_button_values(const std::shared_ptr<PadDevice>& device) override;
	bool get_is_left_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
	bool get_is_right_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
	bool get_is_left_stick(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
	bool get_is_right_stick(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
	void get_extended_info(const pad_ensemble& binding) override;
	void apply_pad_data(const pad_ensemble& binding) override;
	pad_preview_values get_preview_values(const std::unordered_map<u32, u16>& data,
		const std::vector<std::string>& buttons) override;
};
