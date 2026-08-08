#include "RPCS3Core.h"
#include "RPCS3CoreStatus.h"

#include <cstddef>
#include <cstdint>
#include <type_traits>

static_assert(std::is_standard_layout_v<rpcs3_ios_configuration>);
static_assert(std::is_standard_layout_v<rpcs3_ios_installation_status>);
static_assert(std::is_standard_layout_v<rpcs3_ios_installation_status_v2>);
static_assert(std::is_standard_layout_v<rpcs3_ios_core_operation_status>);
static_assert(std::is_standard_layout_v<rpcs3_ios_core_capabilities>);

static_assert(sizeof(rpcs3_ios_configuration) == 9 * sizeof(std::uint32_t));
static_assert(sizeof(rpcs3_ios_installation_status) == 7 * sizeof(std::uint32_t));
static_assert(offsetof(rpcs3_ios_installation_status_v2, operation_id) == 40);
static_assert(sizeof(rpcs3_ios_installation_status_v2) == 48);
static_assert(offsetof(rpcs3_ios_core_operation_status, generation) == 8);
static_assert(offsetof(rpcs3_ios_core_operation_status, owned_by_calling_thread) == 16);
static_assert(sizeof(rpcs3_ios_core_operation_status) == 24);
static_assert(sizeof(rpcs3_ios_core_capabilities) == 10 * sizeof(std::uint32_t));

static_assert(RPCS3_IOS_CORE_SUCCESS == 0);
static_assert(RPCS3_IOS_CORE_CANCELLED == 8);
static_assert(RPCS3_IOS_BOOT_SUCCESS == 0);
static_assert(RPCS3_IOS_BOOT_CURRENTLY_RESTRICTED == 16);
static_assert(RPCS3_IOS_BOOT_CORE_NOT_INITIALIZED == 0xfffffffeu);
static_assert(RPCS3_IOS_BOOT_INVALID_ARGUMENT == 0xffffffffu);
static_assert(RPCS3_IOS_CORE_OPERATION_NONE == 0);
static_assert(RPCS3_IOS_CORE_OPERATION_IMPORT == 14);
static_assert(RPCS3_IOS_INSTALLATION_TERMINAL_NONE == 0);
static_assert(RPCS3_IOS_INSTALLATION_TERMINAL_CANCELLED == 3);

int main()
{
    rpcs3_ios_configuration configuration{};
    configuration.struct_size = sizeof(configuration);
    rpcs3_ios_installation_status_v2 installation{};
    installation.struct_size = sizeof(installation);
    rpcs3_ios_core_operation_status operation{};
    operation.struct_size = sizeof(operation);
    rpcs3_ios_core_capabilities capabilities{};
    capabilities.struct_size = sizeof(capabilities);

    return configuration.struct_size == sizeof(configuration) &&
        installation.struct_size == sizeof(installation) &&
        operation.struct_size == sizeof(operation) &&
        capabilities.struct_size == sizeof(capabilities)
        ? 0
        : 1;
}
