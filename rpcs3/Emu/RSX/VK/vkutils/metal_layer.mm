#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#else
#import <AppKit/AppKit.h>
#endif

#import <QuartzCore/CAMetalLayer.h>

void* GetCAMetalLayerFromMetalView(void* view)
{
#if TARGET_OS_IPHONE
	UIView* metal_view = (__bridge UIView*)view;
	CAMetalLayer* metal_layer = nil;

	if ([metal_view.layer isKindOfClass:CAMetalLayer.class])
	{
		metal_layer = (CAMetalLayer*)metal_view.layer;
	}
	else
	{
		static const void* s_rpcs3_metal_layer_key = &s_rpcs3_metal_layer_key;
		metal_layer = objc_getAssociatedObject(metal_view, s_rpcs3_metal_layer_key);

		if (!metal_layer)
		{
			metal_layer = CAMetalLayer.layer;
			metal_layer.frame = metal_view.bounds;
			metal_layer.contentsScale = metal_view.window.screen.scale ?: UIScreen.mainScreen.scale;
			metal_layer.device = MTLCreateSystemDefaultDevice();
			metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
			metal_layer.framebufferOnly = NO;
			[metal_view.layer addSublayer:metal_layer];
			objc_setAssociatedObject(metal_view, s_rpcs3_metal_layer_key, metal_layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}

	return (__bridge void*)metal_layer;
#else
	NSView* metal_view = (__bridge NSView*)view;
	return (__bridge void*)metal_view.layer;
#endif
}

const char* GetMetalViewClassName(void* view)
{
	id object = (__bridge id)view;
	return object ? object_getClassName(object) : "(null)";
}

const char* GetMetalLayerClassName(void* layer)
{
	id object = (__bridge id)layer;
	return object ? object_getClassName(object) : "(null)";
}
#pragma GCC diagnostic pop
