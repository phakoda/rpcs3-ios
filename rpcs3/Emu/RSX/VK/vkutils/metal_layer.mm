#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"

#import <TargetConditionals.h>
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

void* GetCAMetalLayerFromMetalView(void* view)
{
#if TARGET_OS_IPHONE
    UIView* native_view = (__bridge UIView*)view;
    return (__bridge void*)native_view.layer;
#else
    return ((NSView*)view).layer;
#endif
}

#pragma GCC diagnostic pop
