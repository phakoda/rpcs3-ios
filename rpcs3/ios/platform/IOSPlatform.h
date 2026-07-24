#pragma once

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
    std::string detail;
};

enum class thermal_state
{
    nominal,
    fair,
    serious,
    critical,
    unknown,
};

enum class performance_event
{
    thermal_state_changed,
    low_power_mode_changed,
    memory_warning,
};

struct performance_state
{
    thermal_state thermal = thermal_state::unknown;
    bool low_power_mode = false;
    unsigned long long physical_memory = 0;
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

using performance_callback = std::function<void(performance_event event, performance_state state)>;
using import_callback = std::function<void(std::vector<std::string> imported_paths, std::string error)>;

// Initializes directory creation, application lifecycle observers, audio
// interruption observers, and controller connection monitoring. Safe to call
// more than once.
void initialize();
void shutdown();

runtime_paths get_runtime_paths();
bool prepare_runtime_directories(std::string* error = nullptr);

// Configures the process-wide AVAudioSession used by Cubeb/AudioUnit. This does
// not create an RPCS3 audio backend; it only establishes the iOS session and
// route policy required before a backend starts.
bool configure_audio_session(bool mix_with_others, bool respect_silent_mode, std::string* error = nullptr);
void deactivate_audio_session();

jit_capabilities query_jit_capabilities();

// Switches the current thread between executable mode (true) and writable mode
// (false) for MAP_JIT-backed memory on Apple arm64. Returns false when the API
// is unavailable. Callers must still synchronize code publication and flush
// instruction caches as required by their code generator.
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

performance_state get_performance_state();
void set_performance_callback(performance_callback callback);
void set_idle_timer_disabled(bool disabled);

std::vector<controller_state> get_controller_states();

// Synthetic controller state used by the native multitouch overlay. Hardware
// controllers remain separate; input handlers may prepend this state as Player
// 1 when it is connected.
void set_virtual_controller_state(controller_state state);
bool get_virtual_controller_state(controller_state* state);
void clear_virtual_controller_state();

// Attaches a transparent multitouch DualShock-style overlay to a UIView pointer
// (normally the Qt game window's native view). Calls are marshalled to the main
// thread and are idempotent for the same parent view.
void attach_touch_controller_overlay(void* native_view);
void detach_touch_controller_overlay(void* native_view);
void set_touch_controller_overlay_visible(bool visible);

void set_lifecycle_callbacks(lifecycle_callbacks callbacks);

// Presents the system document picker from a UIViewController pointer. Chosen
// items are coordinated and copied into Documents/Imports so the emulator can
// keep stable paths after the security-scoped picker session ends.
void present_import_picker(void* presenter, bool allow_directories, import_callback callback);

// Copies a single security-scoped item into Documents/Imports. source_path may
// point to a file or directory returned by a system picker.
bool import_item(std::string_view source_path, std::string* imported_path, std::string* error = nullptr);
}
