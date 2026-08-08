#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import <QuartzCore/CAMetalLayer.h>

void* GetCAMetalLayerFromMetalView(void* view)
{
#if TARGET_OS_IPHONE
	UIView* metal_view = (__bridge UIView*)view;
#else
	NSView* metal_view = (__bridge NSView*)view;
#endif

	return (__bridge void*)metal_view.layer;
}
#pragma GCC diagnostic pop
