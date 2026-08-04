#pragma once

#include "RPCS3Core.h"

#if defined(__cplusplus)
extern "C" {
#endif

typedef enum rpcs3_ios_core_operation_kind
{
    RPCS3_IOS_CORE_OPERATION_NONE = 0,
    RPCS3_IOS_CORE_OPERATION_INITIALIZE = 1,
    RPCS3_IOS_CORE_OPERATION_SHUTDOWN = 2,
    RPCS3_IOS_CORE_OPERATION_BOOT = 3,
    RPCS3_IOS_CORE_OPERATION_RESTART = 4,
    RPCS3_IOS_CORE_OPERATION_PAUSE = 5,
    RPCS3_IOS_CORE_OPERATION_RESUME = 6,
    RPCS3_IOS_CORE_OPERATION_STOP = 7,
    RPCS3_IOS_CORE_OPERATION_INSTALL_FIRMWARE = 8,
    RPCS3_IOS_CORE_OPERATION_INSTALL_PACKAGE = 9,
    RPCS3_IOS_CORE_OPERATION_LIBRARY = 10,
    RPCS3_IOS_CORE_OPERATION_SETTINGS = 11,
    RPCS3_IOS_CORE_OPERATION_MIDI = 12,
    RPCS3_IOS_CORE_OPERATION_RENDER_HOST = 13,
} rpcs3_ios_core_operation_kind;

typedef enum rpcs3_ios_installation_terminal_state
{
    RPCS3_IOS_INSTALLATION_TERMINAL_NONE = 0,
    RPCS3_IOS_INSTALLATION_TERMINAL_SUCCEEDED = 1,
    RPCS3_IOS_INSTALLATION_TERMINAL_FAILED = 2,
    RPCS3_IOS_INSTALLATION_TERMINAL_CANCELLED = 3,
} rpcs3_ios_installation_terminal_state;

typedef struct rpcs3_ios_core_operation_status
{
    uint32_t struct_size;
    uint32_t active_operation;
    uint64_t generation;
    uint32_t owned_by_calling_thread;
} rpcs3_ios_core_operation_status;

typedef struct rpcs3_ios_installation_status_v2
{
    uint32_t struct_size;
    uint32_t active;
    uint32_t cancel_requested;
    uint32_t kind;
    uint32_t stage;
    uint32_t completed;
    uint32_t total;
    uint32_t terminal_state;
    uint32_t result;
    uint64_t operation_id;
} rpcs3_ios_installation_status_v2;

typedef struct rpcs3_ios_core_capabilities
{
    uint32_t struct_size;
    uint32_t api_major;
    uint32_t api_minor;
    uint32_t api_patch;
    uint32_t has_vulkan;
    uint32_t has_llvm;
    uint32_t has_coremidi;
    uint32_t has_installers;
    uint32_t has_native_dialogs;
    uint32_t has_physical_usb_passthrough;
} rpcs3_ios_core_capabilities;

RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_operation_status rpcs3_ios_core_query_operation_status(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_installation_status_v2 rpcs3_ios_core_query_installation_status_v2(void);
RPCS3_IOS_CORE_EXPORT rpcs3_ios_core_capabilities rpcs3_ios_core_query_capabilities(void);

#if defined(__cplusplus)
}
#endif
