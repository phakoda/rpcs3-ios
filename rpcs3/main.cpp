#include "stdafx.h"
#include "rpcs3.h"

#ifdef RPCS3_IOS
#include "ios/IOSRuntimeIntegration.h"
#endif

LOG_CHANNEL(sys_log, "SYS");

int main(int argc, char** argv)
{
    const int exit_code = run_rpcs3(argc, argv);
    sys_log.notice("RPCS3 terminated with exit code %d", exit_code);

#ifdef RPCS3_IOS
    rpcs3::ios::shutdown_rpcs3_runtime();
#endif
    return exit_code;
}
