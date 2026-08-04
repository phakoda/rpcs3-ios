#include <RPCS3Core/RPCS3Core.h>
#include <RPCS3Core/RPCS3CoreStatus.h>

#include <type_traits>

static_assert(std::is_standard_layout_v<rpcs3_ios_configuration>);
static_assert(std::is_standard_layout_v<rpcs3_ios_installation_status_v2>);

int main()
{
    const auto capabilities = rpcs3_ios_core_query_capabilities();
    return capabilities.api_major == 0 && capabilities.api_minor == 5 ? 0 : 1;
}
