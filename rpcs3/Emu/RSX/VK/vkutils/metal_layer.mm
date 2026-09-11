#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"

#import <TargetConditionals.h>
#import <objc/runtime.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#else
#import <AppKit/AppKit.h>
#endif

#import <QuartzCore/CAMetalLayer.h>

#if TARGET_OS_IPHONE
#include <algorithm>
#include <cmath>

// Qt may supply an ordinary UIView rather than one backed by CAMetalLayer.
// A child UIView receives layout/scale/window changes; a raw sublayer does not.
@interface RPCS3IOSMetalView : UIView
@end

@implementation RPCS3IOSMetalView
+ (Class)layerClass
{
	return CAMetalLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame
{
	if ((self = [super initWithFrame:frame]))
	{
		self.userInteractionEnabled = NO;
		self.opaque = YES;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		CAMetalLayer* metalLayer = static_cast<CAMetalLayer*>(self.layer);
		metalLayer.device = MTLCreateSystemDefaultDevice();
		metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		// The Vulkan presentation path uses transfer writes and color attachments.
		metalLayer.framebufferOnly = NO;
		metalLayer.opaque = YES;
		metalLayer.allowsNextDrawableTimeout = YES;
	}
	return self;
}

- (void)updateDrawableSize
{
	CAMetalLayer* metalLayer = static_cast<CAMetalLayer*>(self.layer);
	const CGFloat scale = self.window.screen.scale ?: self.traitCollection.displayScale;
	const CGFloat safeScale = (std::isfinite(scale) && scale > 0) ? scale : 1;
	const CGSize size = CGSizeMake(std::max(0.0, std::round(self.bounds.size.width * safeScale)),
		std::max(0.0, std::round(self.bounds.size.height * safeScale)));
	// UIKit owns these writes. Suppress interpolation of layer size during
	// rotation, and do not continually recreate same-sized drawable storage.
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	if (metalLayer.contentsScale != safeScale)
		metalLayer.contentsScale = safeScale;
	if (!CGSizeEqualToSize(metalLayer.drawableSize, size))
		metalLayer.drawableSize = size;
	[CATransaction commit];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	[self updateDrawableSize];
}

- (void)didMoveToWindow
{
	[super didMoveToWindow];
	[self updateDrawableSize];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection
{
	[super traitCollectionDidChange:previousTraitCollection];
	[self updateDrawableSize];
}
@end
#endif

void* GetCAMetalLayerFromMetalView(void* view)
{
#if TARGET_OS_IPHONE
	if (!view)
		return nullptr;

	__block CAMetalLayer* result = nil;
	void (^resolveLayer)(void) = ^{
		UIView* hostView = (__bridge UIView*)view;
		if ([hostView.layer isKindOfClass:CAMetalLayer.class])
		{
			// Qt owns the native Metal view's layer and its resizing policy.
			result = static_cast<CAMetalLayer*>(hostView.layer);
			return;
		}
		static const void* viewKey = &viewKey;
		RPCS3IOSMetalView* metalView = objc_getAssociatedObject(hostView, viewKey);
		if (!metalView)
		{
			metalView = [[RPCS3IOSMetalView alloc] initWithFrame:hostView.bounds];
			[hostView insertSubview:metalView atIndex:0];
			objc_setAssociatedObject(hostView, viewKey, metalView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		metalView.frame = hostView.bounds;
		[metalView updateDrawableSize];
		result = static_cast<CAMetalLayer*>(metalView.layer);
	};
	// Only surface creation dispatches synchronously; rendering has no per-frame
	// main-thread round trip. Never touch UIKit from the RSX worker thread.
	if (NSThread.isMainThread)
		resolveLayer();
	else
		dispatch_sync(dispatch_get_main_queue(), resolveLayer);
	return (__bridge void*)result;
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
