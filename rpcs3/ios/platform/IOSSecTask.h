#pragma once

#include <CoreFoundation/CoreFoundation.h>

// SecTask is exported by the iOS Security framework, but recent iOS SDKs no
// longer ship its private C header. Keep the small ABI surface used by the
// diagnostics code local so the iOS target does not depend on that header.
#if __has_include(<Security/SecTask.h>)
#import <Security/SecTask.h>
#else
typedef struct __SecTask* SecTaskRef;

#ifdef __cplusplus
extern "C"
{
#endif
SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
CFTypeRef SecTaskCopyValueForEntitlement(
    SecTaskRef task,
    CFStringRef entitlement,
    CFErrorRef* error);
#ifdef __cplusplus
}
#endif
#endif
