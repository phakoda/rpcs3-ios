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

// Initializes native iOS services and the headless RPCS3 emulator object. The
// framework core uses Vulkan-compatible configuration defaults but a Null RSX
// output until a host application supplies a renderer surface.
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_initialize(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_shutdown(void);
RPCS3_IOS_CORE_EXPORT uint8_t rpcs3_ios_core_is_initialized(void);

RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_set_event_callback(
    rpcs3_ios_core_event_callback callback,
    void* context);

RPCS3_IOS_CORE_EXPORT rpcs3_ios_boot_result rpcs3_ios_core_boot_path(
    const char* path,
    uint8_t direct_boot);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_pause(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_resume(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_stop(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_boot_result rpcs3_ios_core_restart(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_emulator_state rpcs3_ios_core_emulator_state(void);

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
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_diagnostics(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_last_error(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_boot_path(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_title(char* buffer, size_t buffer_size);
RPCS3_IOS_CORE_EXPORT size_t rpcs3_ios_core_copy_title_id(char* buffer, size_t buffer_size);

// Configures public MoltenVK environment variables before Vulkan instance
// creation. Safe to call before or after rpcs3_ios_core_initialize.
RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_configure_moltenvk_defaults(void);

#if defined(__cplusplus)
}
#endif
