#include "IOSCoreOperations.h"
#include "RPCS3CoreStatus.h"

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
