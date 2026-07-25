#include "RPCS3Core.h"

#import <Foundation/Foundation.h>

extern "C" void rpcs3_ios_core_set_event_callback_base(
    rpcs3_ios_core_event_callback callback,
    void* context);

extern "C" void rpcs3_ios_core_set_event_callback(
    rpcs3_ios_core_event_callback callback,
    void* context)
{
    const auto update = ^{
        rpcs3_ios_core_set_event_callback_base(callback, context);
    };

    if (NSThread.isMainThread)
    {
        update();
    }
    else
    {
        // Event delivery is also serialized on the UIKit main queue. A clear
        // therefore waits for any in-flight callback to return before the host
        // may release its context.
        dispatch_sync(dispatch_get_main_queue(), update);
    }
}
