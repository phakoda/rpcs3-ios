#include <RPCS3Core/RPCS3Core.h>
#include <RPCS3Core/RPCS3CoreStatus.h>

int main(void)
{
    const rpcs3_ios_core_capabilities capabilities = rpcs3_ios_core_query_capabilities();
    const rpcs3_ios_core_operation_status operation = rpcs3_ios_core_query_operation_status();
    return capabilities.api_minor == 5 && operation.struct_size == sizeof(operation) ? 0 : 1;
}
