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
} rpcs3_ios_core_result;

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

RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_initialize(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_result rpcs3_ios_core_shutdown(void);
RPCS3_IOS_CORE_EXPORT uint8_t rpcs3_ios_core_is_initialized(void);

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

// Configures public MoltenVK environment variables before Vulkan instance
// creation. Safe to call before or after rpcs3_ios_core_initialize.
RPCS3_IOS_CORE_EXPORT void rpcs3_ios_core_configure_moltenvk_defaults(void);

#if defined(__cplusplus)
}
#endif
