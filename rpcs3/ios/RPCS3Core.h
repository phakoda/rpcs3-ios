#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(__GNUC__)
#define RPCS3_IOS_CORE_EXPORT __attribute__((visibility("default")))
#else
#define RPCS3_IOS_CORE_EXPORT
#endif

typedef enum rpcs3_ios_core_result
{
    RPCS3_IOS_CORE_SUCCESS = 0,
    RPCS3_IOS_CORE_ALREADY_INITIALIZED = 1,
    RPCS3_IOS_CORE_NOT_INITIALIZED = 2,
    RPCS3_IOS_CORE_INVALID_ARGUMENT = 3,
    RPCS3_IOS_CORE_PLATFORM_ERROR = 4,
    RPCS3_IOS_CORE_BUSY = 5,
    RPCS3_IOS_CORE_UNSUPPORTED = 6,
    RPCS3_IOS_CORE_BUFFER_TOO_SMALL = 7,
    RPCS3_IOS_CORE_CANCELLED = 8,
} rpcs3_ios_core_result;

typedef enum rpcs3_ios_emulator_state
{
    RPCS3_IOS_EMULATOR_STOPPED = 0,
    RPCS3_IOS_EMULATOR_LOADING = 1,
    RPCS3_IOS_EMULATOR_STOPPING = 2,
    RPCS3_IOS_EMULATOR_RUNNING = 3,
    RPCS3_IOS_EMULATOR_PAUSED = 4,
    RPCS3_IOS_EMULATOR_FROZEN = 5,
    RPCS3_IOS_EMULATOR_READY = 6,
    RPCS3_IOS_EMULATOR_STARTING = 7,
    RPCS3_IOS_EMULATOR_UNAVAILABLE = 0xffffffffu,
} rpcs3_ios_emulator_state;

typedef enum rpcs3_ios_boot_result
{
    RPCS3_IOS_BOOT_SUCCESS = 0,
    RPCS3_IOS_BOOT_GENERIC_ERROR = 1,
    RPCS3_IOS_BOOT_NOTHING_TO_BOOT = 2,
    RPCS3_IOS_BOOT_WRONG_DISC_LOCATION = 3,
    RPCS3_IOS_BOOT_INVALID_FILE_OR_FOLDER = 4,
    RPCS3_IOS_BOOT_INVALID_BDVD_FOLDER = 5,
    RPCS3_IOS_BOOT_INSTALL_FAILED = 6,
    RPCS3_IOS_BOOT_DECRYPTION_ERROR = 7,
    RPCS3_IOS_BOOT_FILE_CREATION_ERROR = 8,
    RPCS3_IOS_BOOT_FIRMWARE_MISSING = 9,
    RPCS3_IOS_BOOT_FIRMWARE_TOO_OLD = 10,
    RPCS3_IOS_BOOT_UNSUPPORTED_DISC_TYPE = 11,
    RPCS3_IOS_BOOT_SAVESTATE_CORRUPTED = 12,
    RPCS3_IOS_BOOT_SAVESTATE_VERSION_UNSUPPORTED = 13,
    RPCS3_IOS_BOOT_STILL_RUNNING = 14,
    RPCS3_IOS_BOOT_ALREADY_ADDED = 15,
    RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED = 16,
    RPCS3_IOS_BOOT_DATABASE_CONFIG_MISSING = 17,
    RPCS3_IOS_BOOT_CORE_NOT_INITIALIZED = 0xfffffffeu,
    RPCS3_IOS_BOOT_INVALID_ARGUMENT = 0xffffffffu,
} rpcs3_ios_boot_result;

typedef enum rpcs3_ios_core_event
{
    RPCS3_IOS_CORE_EVENT_READY = 0,
    RPCS3_IOS_CORE_EVENT_RUN = 1,
    RPCS3_IOS_CORE_EVENT_PAUSE = 2,
    RPCS3_IOS_CORE_EVENT_RESUME = 3,
    RPCS3_IOS_CORE_EVENT_STOP = 4,
    RPCS3_IOS_CORE_EVENT_MISSING_FIRMWARE = 5,
    RPCS3_IOS_CORE_EVENT_PAD_CONNECTION_CHANGED = 6,
    RPCS3_IOS_CORE_EVENT_FATAL_ERROR = 7,
} rpcs3_ios_core_event;

typedef void (*rpcs3_ios_core_event_callback)(
    rpcs3_ios_core_event event,
    const char* detail,
    void* context);

typedef enum rpcs3_ios_cpu_mode
{
    RPCS3_IOS_CPU_PORTABLE = 0,
    RPCS3_IOS_CPU_PPU_LLVM = 1,
    RPCS3_IOS_CPU_FULL_LLVM = 2,
} rpcs3_ios_cpu_mode;

typedef enum rpcs3_ios_frame_limit
{
    RPCS3_IOS_FRAME_LIMIT_AUTO = 0,
    RPCS3_IOS_FRAME_LIMIT_30 = 1,
    RPCS3_IOS_FRAME_LIMIT_60 = 2,
    RPCS3_IOS_FRAME_LIMIT_120 = 3,
    RPCS3_IOS_FRAME_LIMIT_DISPLAY = 4,
} rpcs3_ios_frame_limit;

typedef enum rpcs3_ios_midi_device_type
{
    RPCS3_IOS_MIDI_KEYBOARD = 0,
    RPCS3_IOS_MIDI_GUITAR_17_FRET = 1,
    RPCS3_IOS_MIDI_GUITAR_22_FRET = 2,
    RPCS3_IOS_MIDI_DRUMS = 3,
} rpcs3_ios_midi_device_type;

typedef struct rpcs3_ios_configuration
{
    uint32_t struct_size;
    uint32_t cpu_mode;
    uint32_t audio_enabled;
    uint32_t audio_volume;
    uint32_t resolution_scale_percent;
    uint32_t frame_limit;
    uint32_t shader_cache_enabled;
    uint32_t performance_overlay_enabled;
    uint32_t preferred_spu_threads;
} rpcs3_ios_configuration;

typedef enum rpcs3_ios_installation_kind
{
    RPCS3_IOS_INSTALLATION_FIRMWARE = 0,
    RPCS3_IOS_INSTALLATION_PACKAGE = 1,
} rpcs3_ios_installation_kind;

typedef enum rpcs3_ios_installation_stage
{
    RPCS3_IOS_INSTALLATION_VALIDATING = 0,
    RPCS3_IOS_INSTALLATION_EXTRACTING = 1,
    RPCS3_IOS_INSTALLATION_FINALIZING = 2,
    RPCS3_IOS_INSTALLATION_COMPLETE = 3,
} rpcs3_ios_installation_stage;

typedef void (*rpcs3_ios_installation_progress_callback)(
    rpcs3_ios_installation_kind kind,
    rpcs3_ios_installation_stage stage,
    uint32_t completed,
    uint32_t total,
    const char* detail,
    void* context);

typedef struct rpcs3_ios_installation_status
{
    uint32_t struct_size;
    uint32_t active;
    uint32_t cancel_requested;
    uint32_t kind;
    uint32_t stage;
    uint32_t completed;
    uint32_t total;
} rpcs3_ios_installation_status;

typedef struct rpcs3_ios_jit_status
{
    uint8_t map_jit_available;
    uint8_t map_jit_allocation_succeeded;
    uint8_t jit_write_protect_available;
    uint8_t dynamic_codesigning_entitlement;
    uint8_t allow_jit_entitlement;
    uint8_t debugger_entitlement;
    uint8_t increased_memory_limit_entitlement;
    uint8_t extended_virtual_addressing_entitlement;
    uint8_t process_is_debugged;
} rpcs3_ios_jit_status;

typedef struct rpcs3_ios_performance_status
{
    uint32_t thermal_state;
    uint32_t memory_pressure;
    uint8_t low_power_mode;
    uint64_t physical_memory;
    uint64_t available_memory;
} rpcs3_ios_performance_status;

RPCS3_IOS_CORE_EXPORT extern double RPCS3CoreVersionNumber;
RPCS3_IOS_CORE_EXPORT extern const unsigned char RPCS3CoreVersionString[];

// Initializes native iOS services and the RPCS3 emulator object. The core can
// run headlessly with Null RSX or select Vulkan/MoltenVK when a render view has
// been supplied before boot.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_initialize(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_shutdown(void);
RPCS3_IOS_CORE_EXPORT uint8_t rpcs3_ios_core_is_initialized(void);

// native_view must be a retained or otherwise live UIView backed by
// CAMetalLayer. Pass it from Objective-C/Objective-C++ as (__bridge void*)view.
// The view can be changed only while emulation is stopped. Call refresh after
// host layout or orientation changes to update contentsScale and drawableSize.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_set_render_view(void* native_view);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_clear_render_view(void);
RPCS3_IOS_CORE_EXPORT uint8_t rpcs3_ios_core_has_render_view(void);
RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_refresh_render_view(void);

// Events are delivered on the UIKit main queue. The caller owns context and
// must clear the callback before releasing it or unloading the framework host.
RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_set_event_callback(
    rpcs3_ios_core_event_callback callback,
    void* context);

// Copies a security-scoped local file or directory into Documents/Imports. The
// caller must keep any security-scoped URL active for the duration of this call.
// required_size receives the full UTF-8 path length including the trailing NUL.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_import_path(
    const char* source_path,
    char* imported_path,
    size_t imported_path_size,
    size_t* required_size);

RPCS3_IOS_CORE_EXPORT rpcs3_ios_boot_result rpcs3_ios_core_boot_path(
    const char* path,
    uint8_t direct_boot);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_pause(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_resume(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_stop(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_boot_result rpcs3_ios_core_restart(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_emulator_state rpcs3_ios_core_emulator_state(void);

// Configuration is persistent in the framework host's NSUserDefaults domain.
// Mutating calls are accepted only while emulation is fully stopped.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_get_configuration(
    rpcs3_ios_configuration* configuration);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_set_configuration(
    const rpcs3_ios_configuration* configuration);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_reset_configuration(void);

// Qt-free game-library management. Title-ID/path mappings use RPCS3's normal
// games.yml. Scan roots are persisted separately in the host's NSUserDefaults
// domain. Scans and mutations require fully stopped emulation.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_add_game_directory(
    const char* path,
    uint32_t* added_games);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_remove_game_directory(
    const char* path,
    uint8_t remove_library_entries,
    uint32_t* removed_games);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_rescan_game_directories(
    uint32_t* added_games);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_prune_missing_game_directories(
    uint32_t* removed_directories);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_clear_game_directories(
    uint8_t remove_library_entries,
    uint32_t* removed_games);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_add_game(const char* path);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_remove_game(const char* title_id);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_game_count(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_copy_game(
    size_t index,
    char* title_id,
    size_t title_id_size,
    size_t* title_id_required,
    char* path,
    size_t path_size,
    size_t* path_required);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_game_directory_count(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_copy_game_directory(
    size_t index,
    char* path,
    size_t path_size,
    size_t* path_required);

// Public CoreMIDI source enumeration and persistent mapping to RPCS3's three
// emulated Rock Band 3 MIDI adapter slots. Names must match a current CoreMIDI
// source display name. Mutations require fully stopped emulation.
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_midi_source_count(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_copy_midi_source(
    size_t index,
    char* name,
    size_t name_size,
    size_t* required_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_midi_slot_count(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_set_midi_assignment(
    uint32_t slot,
    uint32_t type,
    const char* source_name);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_clear_midi_assignment(
    uint32_t slot);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_copy_midi_assignment(
    uint32_t slot,
    uint32_t* type,
    char* source_name,
    size_t source_name_size,
    size_t* required_size);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_clear_all_midi_assignments(void);

// Installers are synchronous and may perform substantial decryption and file
// I/O. Invoke them on a serial background queue while emulation is stopped.
// Progress callbacks run on the calling thread. Cancellation can be requested
// from another thread; partially extracted files may remain after cancellation.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_install_firmware(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_install_package(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_installation_status rpcs3_ios_core_query_installation_status(void);

RPCS3_IOS_CORE_EXPORT const char* rpcs3_ios_core_application_support_path(void);
RPCS3_IOS_CORE_EXPORT const char* rpcs3_ios_core_caches_path(void);
RPCS3_IOS_CORE_EXPORT const char* rpcs3_ios_core_documents_path(void);
RPCS3_IOS_CORE_EXPORT const char* rpcs3_ios_core_imports_path(void);
RPCS3_IOS_CORE_EXPORT const char* rpcs3_ios_core_temporary_path(void);

RPCS3_IOS_CORE_EXPORT rpcs3_ios_jit_status rpcs3_ios_core_query_jit_status(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_performance_status rpcs3_ios_core_query_performance_status(void);

// Returns the required byte count including the trailing NUL. When buffer is
// non-null, at most buffer_size bytes are written and the result is always NUL
// terminated when buffer_size is non-zero.
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_jit_detail(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_installation_detail(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_diagnostics(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_last_error(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_boot_path(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_title(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_title_id(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_firmware_version(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_last_installed_path(char* buffer, size_t buffer_size);

// Configures public MoltenVK environment variables before Vulkan instance
// creation. Safe to call before or after rpcs3_ios_core_initialize.
RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_configure_moltenvk_defaults(void);

#if defined(__cplusplus)
}
#endif
