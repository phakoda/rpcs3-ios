#include "IOSCoreLifecycle.h"

#import <Foundation/Foundation.h>

namespace
{
void schedule_pause_attempt(unsigned int remaining_attempts)
{
    if (!remaining_attempts)
    {
        return;
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (!rpcs3::ios::try_core_lifecycle_pause_after_run())
            {
                schedule_pause_attempt(remaining_attempts - 1);
            }
        });
}
}

namespace rpcs3::ios
{
void schedule_core_lifecycle_pause_after_run()
{
    // A bounded five-second retry window covers asynchronous BootGame teardown
    // without leaving an unbounded timer chain if the emulator never reaches a
    // pausable state. Lifecycle boot admission prevents new work while inactive.
    schedule_pause_attempt(100);
}
}
