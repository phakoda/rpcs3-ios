#include "ios_controller_bridge.h"
#include "ios_input_policy.h"

#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>

@interface RPCS3IOSStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@property(nonatomic, strong) UIView* knob;
@property(nonatomic, strong) UITouch* activeTouch;
@property(nonatomic) CGPoint stickPosition;
- (void)resetInput;
@end

@implementation RPCS3IOSStickView

- (instancetype)initWithFrame:(CGRect)frame
{
	if ((self = [super initWithFrame:frame]))
	{
		self.multipleTouchEnabled = NO;
		self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.42];
		self.layer.cornerRadius = frame.size.width * 0.5;
		self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
		self.layer.borderWidth = 1.0;
		_knob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width * 0.46, frame.size.height * 0.46)];
		_knob.backgroundColor = [UIColor colorWithWhite:0.95 alpha:0.60];
		_knob.layer.cornerRadius = _knob.bounds.size.width * 0.5;
		_knob.userInteractionEnabled = NO;
		[self addSubview:_knob];
	}
	return self;
}

- (CGFloat)travelRadius
{
	return std::max(1.0, (std::min(self.bounds.size.width, self.bounds.size.height) - self.knob.bounds.size.width) * 0.5);
}

- (void)positionKnob
{
	const CGFloat radius = [self travelRadius];
	self.knob.center = CGPointMake(CGRectGetMidX(self.bounds) + self.stickPosition.x * radius,
		CGRectGetMidY(self.bounds) + self.stickPosition.y * radius);
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	const CGFloat diameter = std::min(self.bounds.size.width, self.bounds.size.height);
	self.layer.cornerRadius = diameter * 0.5;
	self.knob.bounds = CGRectMake(0, 0, diameter * 0.46, diameter * 0.46);
	self.knob.layer.cornerRadius = self.knob.bounds.size.width * 0.5;
	// A newly-created knob has a nonzero center, so checking center == zero
	// never centered the original control. Retain normalized input on resize.
	[self positionKnob];
}

- (void)updateWithTouch:(UITouch*)touch
{
	if (!touch)
		return;
	const CGPoint point = [touch locationInView:self];
	const auto position = ios_input::normalize_stick(
		static_cast<float>(point.x - CGRectGetMidX(self.bounds)),
		static_cast<float>(point.y - CGRectGetMidY(self.bounds)),
		static_cast<float>([self travelRadius]));
	self.stickPosition = CGPointMake(position.x, position.y);
	[self positionKnob];
	if (self.valueChanged)
		self.valueChanged(position.x, -position.y);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)event;
	if (!self.activeTouch)
	{
		self.activeTouch = touches.anyObject;
		[self updateWithTouch:self.activeTouch];
	}
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)event;
	if (self.activeTouch && [touches containsObject:self.activeTouch])
		[self updateWithTouch:self.activeTouch];
}

- (void)resetInput
{
	self.activeTouch = nil;
	self.stickPosition = CGPointZero;
	[self positionKnob];
	if (self.valueChanged)
		self.valueChanged(0, 0);
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)event;
	if (self.activeTouch && [touches containsObject:self.activeTouch])
		[self resetInput];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self touchesEnded:touches withEvent:event];
}

- (void)didMoveToWindow
{
	[super didMoveToWindow];
	if (!self.window)
		[self resetInput];
}

@end

enum : NSInteger
{
	rpcs3_button_a = 1,
	rpcs3_button_b,
	rpcs3_button_x,
	rpcs3_button_y,
	rpcs3_dpad_left,
	rpcs3_dpad_right,
	rpcs3_dpad_up,
	rpcs3_dpad_down,
	rpcs3_left_shoulder,
	rpcs3_right_shoulder,
	rpcs3_left_trigger,
	rpcs3_right_trigger,
	rpcs3_left_stick,
	rpcs3_right_stick,
	rpcs3_menu,
	rpcs3_options,
	rpcs3_home,
};

@interface RPCS3IOSVirtualPadView : UIView
{
@public
	ios_controller_snapshot snapshot;
}
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, UIButton*>* buttons;
@property(nonatomic, strong) RPCS3IOSStickView* leftStick;
@property(nonatomic, strong) RPCS3IOSStickView* rightStick;
- (void)resetInputs;
@end

@implementation RPCS3IOSVirtualPadView

- (UIButton*)makeButton:(NSString*)title tag:(NSInteger)tag accessibility:(NSString*)accessibility
{
	UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.tag = tag;
	button.accessibilityLabel = accessibility;
	button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.46];
	button.tintColor = UIColor.whiteColor;
	button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
	button.layer.borderWidth = 1.0;
	[button setTitle:title forState:UIControlStateNormal];
	[button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
	[button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
	[self addSubview:button];
	self.buttons[@(tag)] = button;
	return button;
}

- (instancetype)initWithFrame:(CGRect)frame
{
	if ((self = [super initWithFrame:frame]))
	{
		self.backgroundColor = UIColor.clearColor;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_buttons = [NSMutableDictionary dictionary];
		snapshot = {};
		snapshot.connected = true;
		snapshot.battery_level = 1.0f;
		snapshot.charging = true;

		[self makeButton:@"✕" tag:rpcs3_button_a accessibility:@"Cross"];
		[self makeButton:@"○" tag:rpcs3_button_b accessibility:@"Circle"];
		[self makeButton:@"□" tag:rpcs3_button_x accessibility:@"Square"];
		[self makeButton:@"△" tag:rpcs3_button_y accessibility:@"Triangle"];
		[self makeButton:@"◀" tag:rpcs3_dpad_left accessibility:@"D-Pad Left"];
		[self makeButton:@"▶" tag:rpcs3_dpad_right accessibility:@"D-Pad Right"];
		[self makeButton:@"▲" tag:rpcs3_dpad_up accessibility:@"D-Pad Up"];
		[self makeButton:@"▼" tag:rpcs3_dpad_down accessibility:@"D-Pad Down"];
		[self makeButton:@"L1" tag:rpcs3_left_shoulder accessibility:@"L1"];
		[self makeButton:@"R1" tag:rpcs3_right_shoulder accessibility:@"R1"];
		[self makeButton:@"L2" tag:rpcs3_left_trigger accessibility:@"L2"];
		[self makeButton:@"R2" tag:rpcs3_right_trigger accessibility:@"R2"];
		[self makeButton:@"L3" tag:rpcs3_left_stick accessibility:@"L3"];
		[self makeButton:@"R3" tag:rpcs3_right_stick accessibility:@"R3"];
		[self makeButton:@"SELECT" tag:rpcs3_options accessibility:@"Select"];
		[self makeButton:@"START" tag:rpcs3_menu accessibility:@"Start"];
		[self makeButton:@"PS" tag:rpcs3_home accessibility:@"PlayStation Button"];

		_leftStick = [[RPCS3IOSStickView alloc] initWithFrame:CGRectMake(0, 0, 112, 112)];
		_leftStick.accessibilityLabel = @"Left Stick";
		_rightStick = [[RPCS3IOSStickView alloc] initWithFrame:CGRectMake(0, 0, 112, 112)];
		_rightStick.accessibilityLabel = @"Right Stick";
		__weak RPCS3IOSVirtualPadView* weakSelf = self;
		_leftStick.valueChanged = ^(float x, float y) {
			RPCS3IOSVirtualPadView* view = weakSelf;
			if (view)
			{
				@synchronized(view) { view->snapshot.left_x = x; view->snapshot.left_y = y; }
			}
		};
		_rightStick.valueChanged = ^(float x, float y) {
			RPCS3IOSVirtualPadView* view = weakSelf;
			if (view)
			{
				@synchronized(view) { view->snapshot.right_x = x; view->snapshot.right_y = y; }
			}
		};
		[self addSubview:_leftStick];
		[self addSubview:_rightStick];
	}
	return self;
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event
{
	UIView* hit = [super hitTest:point withEvent:event];
	// Transparent space must not swallow taps intended for Qt's game window.
	return hit == self ? nil : hit;
}

- (void)resetInputs
{
	[self.leftStick resetInput];
	[self.rightStick resetInput];
	for (UIButton* button in self.buttons.allValues)
	{
		[button cancelTrackingWithEvent:nil];
		button.highlighted = NO;
		button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.46];
	}
	@synchronized(self)
	{
		snapshot = {};
		snapshot.connected = true;
		snapshot.battery_level = 1.f;
		snapshot.charging = true;
	}
}

- (void)setButton:(NSInteger)tag pressed:(bool)pressed
{
	@synchronized(self)
	{
		switch (tag)
		{
		case rpcs3_button_a: snapshot.button_a = pressed; break;
		case rpcs3_button_b: snapshot.button_b = pressed; break;
		case rpcs3_button_x: snapshot.button_x = pressed; break;
		case rpcs3_button_y: snapshot.button_y = pressed; break;
		case rpcs3_dpad_left: snapshot.dpad_left = pressed; break;
		case rpcs3_dpad_right: snapshot.dpad_right = pressed; break;
		case rpcs3_dpad_up: snapshot.dpad_up = pressed; break;
		case rpcs3_dpad_down: snapshot.dpad_down = pressed; break;
		case rpcs3_left_shoulder: snapshot.left_shoulder = pressed; break;
		case rpcs3_right_shoulder: snapshot.right_shoulder = pressed; break;
		case rpcs3_left_trigger: snapshot.left_trigger = pressed ? 1.0f : 0.0f; break;
		case rpcs3_right_trigger: snapshot.right_trigger = pressed ? 1.0f : 0.0f; break;
		case rpcs3_left_stick: snapshot.left_stick = pressed; break;
		case rpcs3_right_stick: snapshot.right_stick = pressed; break;
		case rpcs3_menu: snapshot.menu = pressed; break;
		case rpcs3_options: snapshot.options = pressed; break;
		case rpcs3_home: snapshot.home = pressed; break;
		default: break;
		}
	}
}

- (void)buttonDown:(UIButton*)button
{
	button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.42];
	[self setButton:button.tag pressed:true];
}

- (void)buttonUp:(UIButton*)button
{
	button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.46];
	[self setButton:button.tag pressed:false];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	const UIEdgeInsets safe = self.safeAreaInsets;
	const CGFloat width = self.bounds.size.width;
	const CGFloat height = self.bounds.size.height;
	const CGFloat buttonSize = std::clamp(height * 0.13, 46.0, 62.0);
	const CGFloat smallWidth = std::clamp(width * 0.10, 58.0, 86.0);
	const CGFloat edge = std::max(16.0, safe.left + 8.0);
	const CGFloat rightEdge = std::max(16.0, safe.right + 8.0);
	const CGFloat upper = safe.top + 12.0;
	const CGFloat lower = height - safe.bottom - buttonSize - 12.0;

	auto place = [&](NSInteger tag, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
		UIButton* button = self.buttons[@(tag)];
		button.frame = CGRectMake(x, y, w, h);
		button.layer.cornerRadius = std::min(w, h) * 0.5;
	};
	place(rpcs3_left_shoulder, edge, upper, smallWidth, buttonSize * 0.72);
	place(rpcs3_left_trigger, edge + smallWidth + 8.0, upper, smallWidth, buttonSize * 0.72);
	place(rpcs3_right_trigger, width - rightEdge - smallWidth * 2.0 - 8.0, upper, smallWidth, buttonSize * 0.72);
	place(rpcs3_right_shoulder, width - rightEdge - smallWidth, upper, smallWidth, buttonSize * 0.72);

	const CGFloat dpadX = edge + buttonSize;
	const CGFloat dpadY = std::max(upper + buttonSize * 1.4, height * 0.38);
	place(rpcs3_dpad_left, dpadX - buttonSize, dpadY, buttonSize, buttonSize);
	place(rpcs3_dpad_right, dpadX + buttonSize, dpadY, buttonSize, buttonSize);
	place(rpcs3_dpad_up, dpadX, dpadY - buttonSize, buttonSize, buttonSize);
	place(rpcs3_dpad_down, dpadX, dpadY + buttonSize, buttonSize, buttonSize);

	const CGFloat faceX = width - rightEdge - buttonSize * 2.0;
	const CGFloat faceY = dpadY;
	place(rpcs3_button_x, faceX - buttonSize, faceY, buttonSize, buttonSize);
	place(rpcs3_button_b, faceX + buttonSize, faceY, buttonSize, buttonSize);
	place(rpcs3_button_y, faceX, faceY - buttonSize, buttonSize, buttonSize);
	place(rpcs3_button_a, faceX, faceY + buttonSize, buttonSize, buttonSize);

	const CGFloat stickSize = std::clamp(height * 0.27, 92.0, 132.0);
	self.leftStick.frame = CGRectMake(edge + buttonSize * 0.25, lower - stickSize + buttonSize * 0.15, stickSize, stickSize);
	self.rightStick.frame = CGRectMake(width - rightEdge - stickSize - buttonSize * 0.25, lower - stickSize + buttonSize * 0.15, stickSize, stickSize);
	place(rpcs3_left_stick, CGRectGetMaxX(self.leftStick.frame) + 8.0, lower + buttonSize * 0.15, buttonSize, buttonSize * 0.72);
	place(rpcs3_right_stick, CGRectGetMinX(self.rightStick.frame) - buttonSize - 8.0, lower + buttonSize * 0.15, buttonSize, buttonSize * 0.72);

	const CGFloat centerWidth = std::clamp(width * 0.09, 60.0, 86.0);
	const CGFloat centerY = height - safe.bottom - buttonSize * 0.80;
	place(rpcs3_options, width * 0.5 - centerWidth - 34.0, centerY, centerWidth, buttonSize * 0.58);
	place(rpcs3_home, width * 0.5 - 26.0, centerY - 3.0, 52.0, 52.0);
	place(rpcs3_menu, width * 0.5 + 34.0, centerY, centerWidth, buttonSize * 0.58);
}

@end

// Lifecycle and UIKit/haptic operations run on the main queue. Published input
// availability, slots and the virtual view are protected for the pad worker.
@interface RPCS3IOSControllerManager : NSObject
@property(nonatomic, copy) NSArray<id>* physicalControllers;
@property(nonatomic, strong) NSMapTable<GCController*, CHHapticEngine*>* hapticEngines;
@property(nonatomic, strong) NSMapTable<GCController*, id<CHHapticPatternPlayer>>* hapticPlayers;
@property(nonatomic, strong) UIImpactFeedbackGenerator* touchFeedback;
@property(nonatomic) CFTimeInterval lastTouchFeedback;
@property(nonatomic, strong) RPCS3IOSVirtualPadView* virtualPadView;
@property(nonatomic) NSUInteger clientCount;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL applicationActive;
@property(nonatomic) BOOL virtualPadActive;
- (void)start;
- (void)stop;
- (GCController*)controllerAtIndex:(NSUInteger)index;
- (NSUInteger)controllerCount;
- (BOOL)readVirtualSnapshot:(ios_controller_snapshot*)output;
- (void)rumbleController:(GCController*)controller index:(NSUInteger)index intensity:(float)intensity sharpness:(float)sharpness;
@end

@implementation RPCS3IOSControllerManager

- (instancetype)init
{
	if ((self = [super init]))
	{
		_physicalControllers = @[];
		_hapticEngines = [NSMapTable weakToStrongObjectsMapTable];
		_hapticPlayers = [NSMapTable weakToStrongObjectsMapTable];
	}
	return self;
}

- (void)stopHapticsForController:(GCController*)controller
{
	id<CHHapticPatternPlayer> player = [self.hapticPlayers objectForKey:controller];
	[player stopAtTime:CHHapticTimeImmediate error:nil];
	[self.hapticPlayers removeObjectForKey:controller];
	CHHapticEngine* engine = [self.hapticEngines objectForKey:controller];
	[engine stopWithCompletionHandler:nil];
	[self.hapticEngines removeObjectForKey:controller];
}

- (void)stopAllHaptics
{
	for (GCController* controller in self.hapticEngines.keyEnumerator.allObjects)
		[self stopHapticsForController:controller];
	self.touchFeedback = nil;
	self.lastTouchFeedback = 0;
}

- (void)attachVirtualPad
{
	UIWindow* window = nil;
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
	{
		if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive)
			continue;
		for (UIWindow* candidate in static_cast<UIWindowScene*>(scene).windows)
		{
			if (candidate.isKeyWindow)
			{
				window = candidate;
				break;
			}
		}
		if (window)
			break;
	}
	if (!window)
		return; // UIWindowDidBecomeKey retries attachment, rather than losing input forever.

	RPCS3IOSVirtualPadView* pad = self.virtualPadView;
	if (!pad)
	{
		pad = [[RPCS3IOSVirtualPadView alloc] initWithFrame:window.bounds];
		pad.hidden = YES;
		@synchronized(self) { self.virtualPadView = pad; }
	}
	if (pad.superview != window)
	{
		[pad resetInputs];
		[pad removeFromSuperview];
		pad.frame = window.bounds;
		[window addSubview:pad];
	}
	[window bringSubviewToFront:pad];
}

- (void)refreshControllers
{
	if (!self.started)
		return;
	NSMutableArray<GCController*>* connected = [NSMutableArray array];
	std::vector<std::uintptr_t> connectedIds;
	for (GCController* controller in GCController.controllers)
	{
		if (controller.extendedGamepad)
		{
			[connected addObject:controller];
			connectedIds.push_back(reinterpret_cast<std::uintptr_t>((__bridge void*)controller));
		}
	}
	std::vector<std::uintptr_t> previousIds;
	for (id slot in self.physicalControllers)
		previousIds.push_back([slot isKindOfClass:GCController.class]
			? reinterpret_cast<std::uintptr_t>((__bridge void*)slot) : 0);
	const auto slots = ios_input::update_slots<std::uintptr_t>(previousIds, connectedIds);
	NSMutableArray<id>* assigned = [NSMutableArray arrayWithCapacity:slots.size()];
	for (const auto slot : slots)
	{
		const auto found = std::find(connectedIds.begin(), connectedIds.end(), slot);
		id value = NSNull.null;
		if (found != connectedIds.end())
			value = connected[static_cast<NSUInteger>(found - connectedIds.begin())];
		[assigned addObject:value];
	}
	for (GCController* controller in self.hapticEngines.keyEnumerator.allObjects)
		if (![connected containsObject:controller])
			[self stopHapticsForController:controller];

	[self attachVirtualPad];
	RPCS3IOSVirtualPadView* pad = self.virtualPadView;
	const BOOL visible = self.applicationActive && connected.count == 0 && pad.window != nil;
	@synchronized(self)
	{
		self.physicalControllers = assigned;
		self.virtualPadActive = visible;
	}
	pad.hidden = !visible;
	if (!visible)
		[pad resetInputs];
}

- (void)start
{
	@synchronized(self)
	{
		if (++self.clientCount != 1)
			return;
		self.started = YES;
		self.applicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
	}
	NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
	[center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidConnectNotification object:nil];
	[center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidDisconnectNotification object:nil];
	[center addObserver:self selector:@selector(controllerChanged:) name:UIWindowDidBecomeKeyNotification object:nil];
	[center addObserver:self selector:@selector(applicationInactive:) name:UIApplicationWillResignActiveNotification object:nil];
	[center addObserver:self selector:@selector(applicationActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	[self refreshControllers];
}

- (void)stop
{
	RPCS3IOSVirtualPadView* pad = nil;
	@synchronized(self)
	{
		if (!self.clientCount || --self.clientCount != 0)
			return;
		self.started = NO;
		self.applicationActive = NO;
		self.virtualPadActive = NO;
		pad = self.virtualPadView;
		self.virtualPadView = nil;
		self.physicalControllers = @[];
	}
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[pad resetInputs];
	[pad removeFromSuperview];
	[self stopAllHaptics];
}

- (void)controllerChanged:(NSNotification*)notification
{
	if (!NSThread.isMainThread)
	{
		dispatch_async(dispatch_get_main_queue(), ^{ [self controllerChanged:notification]; });
		return;
	}
	[self refreshControllers];
}

- (void)applicationInactive:(NSNotification*)notification
{
	(void)notification;
	@synchronized(self)
	{
		self.applicationActive = NO;
		self.virtualPadActive = NO;
	}
	self.virtualPadView.hidden = YES;
	[self.virtualPadView resetInputs];
	[self stopAllHaptics];
}

- (void)applicationActive:(NSNotification*)notification
{
	(void)notification;
	@synchronized(self) { self.applicationActive = self.started; }
	[self refreshControllers];
}

- (GCController*)controllerAtIndex:(NSUInteger)index
{
	@synchronized(self)
	{
		if (self.started && self.applicationActive && index < self.physicalControllers.count)
		{
			id slot = self.physicalControllers[index];
			return [slot isKindOfClass:GCController.class] ? slot : nil;
		}
		return nil;
	}
}

- (NSUInteger)controllerCount
{
	@synchronized(self)
	{
		return std::max<NSUInteger>(1, self.physicalControllers.count);
	}
}

- (BOOL)readVirtualSnapshot:(ios_controller_snapshot*)output
{
	@synchronized(self)
	{
		if (!self.started || !self.applicationActive || !self.virtualPadActive || !self.virtualPadView)
			return NO;
		RPCS3IOSVirtualPadView* pad = self.virtualPadView;
		@synchronized(pad) { *output = pad->snapshot; }
		return YES;
	}
}

- (void)rumbleController:(GCController*)controller index:(NSUInteger)index intensity:(float)intensity sharpness:(float)sharpness
{
	// Discard work queued before shutdown, suspension or replacement of a pad.
	if (!self.started || !self.applicationActive || [self controllerAtIndex:index] != controller)
		return;
	if (!controller)
	{
		if (index != 0 || !self.virtualPadActive || intensity <= 0.f)
			return;
		const CFTimeInterval now = CACurrentMediaTime();
		if (now - self.lastTouchFeedback < 0.08)
			return;
		self.lastTouchFeedback = now;
		if (!self.touchFeedback)
			self.touchFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
		[self.touchFeedback impactOccurredWithIntensity:intensity];
		return;
	}

	id<CHHapticPatternPlayer> previous = [self.hapticPlayers objectForKey:controller];
	[previous stopAtTime:CHHapticTimeImmediate error:nil];
	[self.hapticPlayers removeObjectForKey:controller];
	if (intensity <= 0.f)
		return; // A zero command must actually stop a previously-started player.

	GCDeviceHaptics* haptics = controller.haptics;
	if (!haptics)
		return;
	NSError* error = nil;
	CHHapticEngine* engine = [self.hapticEngines objectForKey:controller];
	if (!engine)
	{
		engine = [haptics createEngineWithLocality:GCHapticsLocalityDefault];
		if (!engine)
			return;
		engine.autoShutdownEnabled = YES;
		[self.hapticEngines setObject:engine forKey:controller];
	}
	if (![engine startAndReturnError:&error])
	{
		[self stopHapticsForController:controller];
		return;
	}
	NSArray<CHHapticEventParameter*>* parameters = @[
		[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity],
		[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharpness]
	];
	// PadHandler's heartbeat is 300 ms. Cover it with a bounded 400 ms event,
	// rather than the previous 80 ms pulse followed by a 220 ms silent gap.
	CHHapticEvent* event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
		parameters:parameters relativeTime:0 duration:0.4];
	CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&error];
	id<CHHapticPatternPlayer> player = error ? nil : [engine createPlayerWithPattern:pattern error:&error];
	if (player && !error && [player startAtTime:CHHapticTimeImmediate error:&error])
		[self.hapticPlayers setObject:player forKey:controller];
}

@end

namespace
{
	RPCS3IOSControllerManager* controller_manager()
	{
		static RPCS3IOSControllerManager* manager = [RPCS3IOSControllerManager new];
		return manager;
	}

	float clamp_unit(float value)
	{
		return ios_input::finite_clamp(value, -1.0f, 1.0f);
	}
}

void ios_controller_start()
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[controller_manager() start];
	});
}

void ios_controller_stop()
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[controller_manager() stop];
	});
}

std::size_t ios_controller_count()
{
	return [controller_manager() controllerCount];
}

bool ios_controller_read(std::size_t index, ios_controller_snapshot& snapshot)
{
	@autoreleasepool
	{
		GCController* controller = [controller_manager() controllerAtIndex:index];
		GCExtendedGamepad* gamepad = controller.extendedGamepad;
		if (!gamepad)
		{
			if (index == 0 && [controller_manager() readVirtualSnapshot:&snapshot])
				return true;
			snapshot = {};
			return false;
		}

		snapshot = {};
		snapshot.connected = true;
		snapshot.left_x = clamp_unit(gamepad.leftThumbstick.xAxis.value);
		snapshot.left_y = clamp_unit(gamepad.leftThumbstick.yAxis.value);
		snapshot.right_x = clamp_unit(gamepad.rightThumbstick.xAxis.value);
		snapshot.right_y = clamp_unit(gamepad.rightThumbstick.yAxis.value);
		snapshot.left_trigger = ios_input::finite_clamp(gamepad.leftTrigger.value, 0.0f, 1.0f);
		snapshot.right_trigger = ios_input::finite_clamp(gamepad.rightTrigger.value, 0.0f, 1.0f);
		snapshot.button_a = gamepad.buttonA.isPressed;
		snapshot.button_b = gamepad.buttonB.isPressed;
		snapshot.button_x = gamepad.buttonX.isPressed;
		snapshot.button_y = gamepad.buttonY.isPressed;
		snapshot.dpad_left = gamepad.dpad.left.isPressed;
		snapshot.dpad_right = gamepad.dpad.right.isPressed;
		snapshot.dpad_up = gamepad.dpad.up.isPressed;
		snapshot.dpad_down = gamepad.dpad.down.isPressed;
		snapshot.left_shoulder = gamepad.leftShoulder.isPressed;
		snapshot.right_shoulder = gamepad.rightShoulder.isPressed;
		snapshot.left_stick = gamepad.leftThumbstickButton.isPressed;
		snapshot.right_stick = gamepad.rightThumbstickButton.isPressed;
		snapshot.menu = gamepad.buttonMenu.isPressed;
		snapshot.options = gamepad.buttonOptions.isPressed;
		snapshot.home = gamepad.buttonHome.isPressed;

		GCMotion* motion = controller.motion;
		if (motion)
		{
			snapshot.acceleration_x = motion.userAcceleration.x + motion.gravity.x;
			snapshot.acceleration_y = motion.userAcceleration.y + motion.gravity.y;
			snapshot.acceleration_z = motion.userAcceleration.z + motion.gravity.z;
			snapshot.rotation_x = motion.rotationRate.x;
			snapshot.rotation_y = motion.rotationRate.y;
			snapshot.rotation_z = motion.rotationRate.z;
		}

		GCDeviceBattery* battery = controller.battery;
		if (battery)
		{
			snapshot.battery_level = ios_input::battery_level(battery.batteryLevel);
			snapshot.charging = battery.batteryState == GCDeviceBatteryStateCharging ||
				battery.batteryState == GCDeviceBatteryStateFull;
		}
		else
		{
			snapshot.battery_level = 1.0f;
			snapshot.charging = true;
		}
		return true;
	}
}

void ios_controller_rumble(std::size_t index, float low_frequency, float high_frequency)
{
	@autoreleasepool
	{
		GCController* controller = [controller_manager() controllerAtIndex:index];
		const float low = ios_input::finite_clamp(low_frequency, 0.f, 1.f);
		const float high = ios_input::finite_clamp(high_frequency, 0.f, 1.f);
		const float intensity = std::max(low, high);
		dispatch_async(dispatch_get_main_queue(), ^{
			[controller_manager() rumbleController:controller index:index intensity:intensity sharpness:high];
		});
	}
}
