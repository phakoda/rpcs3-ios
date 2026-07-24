#pragma once

#ifdef RPCS3_IOS

#include "Emu/Io/PadHandler.h"

#include <array>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

class ios_gamecontroller_pad_handler final : public PadHandlerBase
{
    enum key_code : u32
    {
        key_none = 0,
        key_dpad_up,
        key_dpad_down,
        key_dpad_left,
        key_dpad_right,
        key_a,
        key_b,
        key_x,
        key_y,
        key_l1,
        key_r1,
        key_l2,
        key_r2,
        key_l3,
        key_r3,
        key_menu,
        key_options,
        key_home,
        key_ls_left,
        key_ls_right,
        key_ls_down,
        key_ls_up,
        key_rs_left,
        key_rs_right,
        key_rs_down,
        key_rs_up,
    };

    struct ios_device final : PadDevice
    {
        usz controller_index = umax;
        std::string device_name;
        std::vector<std::set<u32>> trigger_code_left;
        std::vector<std::set<u32>> trigger_code_right;
        std::array<std::vector<std::set<u32>>, 4> axis_code_left;
        std::array<std::vector<std::set<u32>>, 4> axis_code_right;
    };

public:
    ios_gamecontroller_pad_handler();
    ~ios_gamecontroller_pad_handler() override;

    bool Init() override;
    std::vector<pad_list_entry> list_devices() override;
    void init_config(cfg_pad* cfg) override;
    u32 get_battery_level(const std::string& pad_id) override;

private:
    std::array<std::vector<std::set<u32>>, PadHandlerBase::button::button_count>
        get_mapped_key_codes(const std::shared_ptr<PadDevice>& device, const cfg_pad* cfg) override;
    std::shared_ptr<PadDevice> get_device(const std::string& device) override;
    bool get_is_left_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
    bool get_is_right_trigger(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
    bool get_is_left_stick(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
    bool get_is_right_stick(const std::shared_ptr<PadDevice>& device, u32 key_code) override;
    connection update_connection(const std::shared_ptr<PadDevice>& device) override;
    void get_extended_info(const pad_ensemble& binding) override;
    void apply_pad_data(const pad_ensemble& binding) override;
    std::unordered_map<u32, u16> get_button_values(const std::shared_ptr<PadDevice>& device) override;
    pad_preview_values get_preview_values(const std::unordered_map<u32, u16>& data, const std::vector<std::string>& buttons) override;

    static std::string device_name(usz index);
    static bool parse_device_index(std::string_view name, usz* index);

    std::map<std::string, std::shared_ptr<ios_device>> m_devices;
};

#endif
