#include "IOSCoreOperations.h"
#include "RPCS3CoreStatus.h"

static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::none) == RPCS3_IOS_CORE_OPERATION_NONE);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::initialize) == RPCS3_IOS_CORE_OPERATION_INITIALIZE);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::shutdown) == RPCS3_IOS_CORE_OPERATION_SHUTDOWN);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::boot) == RPCS3_IOS_CORE_OPERATION_BOOT);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::restart) == RPCS3_IOS_CORE_OPERATION_RESTART);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::pause) == RPCS3_IOS_CORE_OPERATION_PAUSE);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::resume) == RPCS3_IOS_CORE_OPERATION_RESUME);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::stop) == RPCS3_IOS_CORE_OPERATION_STOP);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::install_firmware) == RPCS3_IOS_CORE_OPERATION_INSTALL_FIRMWARE);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::install_package) == RPCS3_IOS_CORE_OPERATION_INSTALL_PACKAGE);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::library) == RPCS3_IOS_CORE_OPERATION_LIBRARY);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::settings) == RPCS3_IOS_CORE_OPERATION_SETTINGS);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::midi) == RPCS3_IOS_CORE_OPERATION_MIDI);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::render_host) == RPCS3_IOS_CORE_OPERATION_RENDER_HOST);
static_assert(static_cast<uint32_t>(rpcs3::ios::core_operation::import_item) == RPCS3_IOS_CORE_OPERATION_IMPORT);

extern "C"
{
rpcs3_ios_core_operation_status rpcs3_ios_core_query_operation_status(void)
{
    return {
        sizeof(rpcs3_ios_core_operation_status),
        static_cast<uint32_t>(rpcs3::ios::active_core_operation()),
        rpcs3::ios::active_core_operation_generation(),
        rpcs3::ios::core_operation_owned_by_current_thread() ? 1u : 0u,
    };
}

rpcs3_ios_core_capabilities rpcs3_ios_core_query_capabilities(void)
{
    return {
        sizeof(rpcs3_ios_core_capabilities),
        0,
        5,
        0,
        1,
#ifdef RPCS3_IOS_HAS_LLVM
        1,
#else
        0,
#endif
        1,
        1,
        1,
        0,
    };
}
}
