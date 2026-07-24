#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace rpcs3::ios
{
struct runtime_paths
{
    std::string application_support;
    std::string caches;
    std::string documents;
    std::string imports;
    std::string temporary;
};

struct jit_capabilities
{
    bool map_jit_available = false;
    bool map_jit_allocation_succeeded = false;
    bool jit_write_protect_available = false;
    bool dynamic_codesigning_entitlement = false;
    bool allow_jit_entitlement = false;
    bool debugger_entitlement = false;
    bool increased_memory_limit_entitlement = false;
    bool extended_virtual_addressing_entitlement = false;
    bool process_is_debugged = false;
    std::string detail;
};

struct jit_probe_result
{
    bool attempted = false;
    bool succeeded = false;
    bool dual_mapped = false;
    int return_value = 0;
    std::string detail;
};

struct jit_memory_region
{
    void* writable = nullptr;
    void* executable = nullptr;
    std::size_t size = 0;
    bool dual_mapped = false;
};

enum class jit_provider
{
    apple_magnifier,
    stikjit,
    jitstreamer,
};

struct jit_provider_state
{
    jit_provider provider = jit_provider::jitstreamer;
    std::string display_name;
    bool available = false;
};

enum class thermal_state
{
    nominal,
    fair,
    serious,
    critical,
    unknown,
};

enum class memory_pressure_level
{
    normal,
    warning,
    critical,
    unknown,
};

enum class performance_event
{
    thermal_state_changed,
    low_power_mode_changed,
    memory_warning,
    memory_pressure_changed,
};

struct performance_state
{
    thermal_state thermal = thermal_state::unknown;
    memory_pressure_level memory_pressure = memory_pressure_level::unknown;
    bool low_power_mode = false;
    unsigned long long physical_memory = 0;
    unsigned long long available_memory = 0;
};

enum class controller_battery_state
{
    unknown,
    discharging,
    charging,
    full,
};

struct controller_capabilities
{
    bool has_motion = false;
    bool has_haptics = false;
    bool has_light = false;
    bool has_battery = false;
    float battery_level = -1.0f;
    controller_battery_state battery_state = controller_battery_state::unknown;
};

struct controller_motion_state
{
    bool available = false;
    float acceleration_x = 0.0f;
    float acceleration_y = 0.0f;
    float acceleration_z = 0.0f;
    float gyro_x = 0.0f;
    float gyro_y = 0.0f;
    float gyro_z = 0.0f;
};

struct controller_state
{
    int player_index = -1;
    std::string vendor_name;
    bool connected = false;
    bool has_extended_gamepad = false;

    float left_x = 0.0f;
    float left_y = 0.0f;
    float right_x = 0.0f;
    float right_y = 0.0f;
    float left_trigger = 0.0f;
    float right_trigger = 0.0f;

    bool dpad_up = false;
    bool dpad_down = false;
    bool dpad_left = false;
    bool dpad_right = false;
    bool button_a = false;
    bool button_b = false;
    bool button_x = false;
    bool button_y = false;
    bool left_shoulder = false;
    bool right_shoulder = false;
    bool left_thumbstick = false;
    bool right_thumbstick = false;
    bool menu = false;
    bool options = false;
    bool home = false;
};

struct external_display_state
{
    bool connected = false;
    unsigned int width = 0;
    unsigned int height = 0;
    float scale = 1.0f;
    float maximum_frames_per_second = 0.0f;
};

struct moltenvk_options
{
    bool configure_argument_buffers = true;
    bool resume_lost_device = true;
    bool synchronous_queue_submits = false;
    bool present_with_command_buffer = true;
    bool use_command_pooling = true;
    unsigned int max_active_command_buffers = 128;
};

struct device_information
{
    std::string model_identifier;
    std::string operating_system;
    std::string operating_system_version;
    std::string application_version;
    unsigned int active_processor_count = 0;
    unsigned int page_size = 0;
    unsigned long long physical_memory = 0;
    unsigned long long available_memory = 0;
};

struct lifecycle_callbacks
{
    std::function<void()> will_resign_active;
    std::function<void()> did_become_active;
    std::function<void()> did_enter_background;
    std::function<void()> will_enter_foreground;
    std::function<void()> audio_interruption_began;
    std::function<void()> audio_interruption_ended;
    std::function<void()> controller_configuration_changed;
};

using jit_enablement_callback = std::function<void(bool enabled, jit_capabilities capabilities, std::string detail)>;
using performance_callback = std::function<void(performance_event event, performance_state state)>;
using external_display_callback = std::function<void(external_display_state state)>;
using import_callback = std::function<void(std::vector<std::string> imported_paths, std::string error)>;

void initialize();
void shutdown();

runtime_paths get_runtime_paths();
bool prepare_runtime_directories(std::string* error = nullptr);

bool configure_audio_session(bool mix_with_others, bool respect_silent_mode, std::string* error = nullptr);
void deactivate_audio_session();

jit_capabilities query_jit_capabilities();
jit_capabilities query_extended_jit_capabilities();
jit_probe_result run_jit_execution_probe();
bool allocate_jit_memory(std::size_t size, jit_memory_region* region, std::string* error = nullptr);
bool publish_jit_memory(jit_memory_region* region, std::size_t offset, std::size_t length, std::string* error = nullptr);
void release_jit_memory(jit_memory_region* region);

bool set_jit_write_protection(bool executable_mode);

class jit_write_scope
{
public:
    jit_write_scope();
    ~jit_write_scope();

    jit_write_scope(const jit_write_scope&) = delete;
    jit_write_scope& operator=(const jit_write_scope&) = delete;

    bool active() const noexcept;

private:
    bool m_active = false;
};

std::vector<jit_provider_state> get_jit_provider_states();
bool request_jit(jit_provider provider, std::string* error = nullptr);
void wait_for_jit_enablement(double timeout_seconds, jit_enablement_callback callback);

performance_state get_performance_state();
void set_performance_callback(performance_callback callback);
void set_idle_timer_disabled(bool disabled);

std::vector<controller_state> get_controller_states();
std::vector<controller_state> get_combined_controller_states();
bool get_combined_controller_state(std::size_t logical_index, controller_state* state);
controller_capabilities get_combined_controller_capabilities(std::size_t logical_index);
controller_motion_state get_combined_controller_motion(std::size_t logical_index);
bool set_combined_controller_rumble(std::size_t logical_index, float low_frequency, float high_frequency);
bool set_combined_controller_light(std::size_t logical_index, float red, float green, float blue);
void stop_all_controller_haptics();

void set_virtual_controller_state(controller_state state);
bool get_virtual_controller_state(controller_state* state);
void clear_virtual_controller_state();

void attach_touch_controller_overlay(void* native_view);
void detach_touch_controller_overlay(void* native_view);
void set_touch_controller_overlay_visible(bool visible);

external_display_state get_external_display_state();
void set_external_display_callback(external_display_callback callback);

void configure_moltenvk(const moltenvk_options& options);
device_information get_device_information();
std::string build_diagnostics_report();
bool write_diagnostics_report(std::string* report_path, std::string* error = nullptr);

void set_lifecycle_callbacks(lifecycle_callbacks callbacks);

void present_import_picker(void* presenter, bool allow_directories, import_callback callback);
bool import_item(std::string_view source_path, std::string* imported_path, std::string* error = nullptr);
}
