#include "ios_controller_bridge.h"

#import <CoreHaptics/CoreHaptics.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>

@interface RPCS3IOSStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@property(nonatomic, strong) UIView* knob;
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

- (void)layoutSubviews
{
	[super layoutSubviews];
	self.layer.cornerRadius = self.bounds.size.width * 0.5;
	self.knob.layer.cornerRadius = self.knob.bounds.size.width * 0.5;
	if (CGPointEqualToPoint(self.knob.center, CGPointZero))
	{
		self.knob.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
	}
}

- (void)updateWithTouch:(UITouch*)touch
{
	const CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
	const CGPoint point = [touch locationInView:self];
	float x = static_cast<float>(point.x - center.x);
	float y = static_cast<float>(point.y - center.y);
	const float radius = static_cast<float>(std::max(1.0, self.bounds.size.width * 0.5 - self.knob.bounds.size.width * 0.25));
	const float length = std::sqrt(x * x + y * y);
	if (length > radius)
	{
		x *= radius / length;
		y *= radius / length;
	}
	self.knob.center = CGPointMake(center.x + x, center.y + y);
	if (self.valueChanged)
	{
		self.valueChanged(x / radius, -y / radius);
	}
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)event;
	[self updateWithTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)event;
	[self updateWithTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	(void)touches;
	(void)event;
	self.knob.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
	if (self.valueChanged)
	{
		self.valueChanged(0, 0);
	}
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
	[self touchesEnded:touches withEvent:event];
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
	[button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
	[button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
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

@interface RPCS3IOSControllerManager : NSObject
@property(nonatomic, copy) NSArray<GCController*>* physicalControllers;
@property(nonatomic, strong) NSMapTable<GCController*, CHHapticEngine*>* hapticEngines;
@property(nonatomic, strong) RPCS3IOSVirtualPadView* virtualPadView;
@property(nonatomic) BOOL started;
- (void)start;
- (void)stop;
- (GCController*)controllerAtIndex:(NSUInteger)index;
- (NSUInteger)controllerCount;
@end

@implementation RPCS3IOSControllerManager

- (instancetype)init
{
	if ((self = [super init]))
	{
		_physicalControllers = @[];
		_hapticEngines = [NSMapTable weakToStrongObjectsMapTable];
	}
	return self;
}

- (void)refreshControllers
{
	NSMutableArray<GCController*>* controllers = [NSMutableArray array];
	for (GCController* controller in GCController.controllers)
	{
		if (controller.extendedGamepad)
		{
			[controllers addObject:controller];
		}
	}
	self.physicalControllers = controllers;
	self.virtualPadView.hidden = controllers.count != 0;
}

- (void)start
{
	if (self.started)
	{
		return;
	}
	self.started = YES;

	NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
	[center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidConnectNotification object:nil];
	[center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidDisconnectNotification object:nil];

	UIWindow* window = nil;
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
	{
		if (![scene isKindOfClass:UIWindowScene.class])
		{
			continue;
		}
		UIWindowScene* windowScene = static_cast<UIWindowScene*>(scene);
		for (UIWindow* candidate in windowScene.windows)
		{
			if (candidate.isKeyWindow)
			{
				window = candidate;
				break;
			}
		}
		if (window)
		{
			break;
		}
	}
	if (window)
	{
		self.virtualPadView = [[RPCS3IOSVirtualPadView alloc] initWithFrame:window.bounds];
		[window addSubview:self.virtualPadView];
		[window bringSubviewToFront:self.virtualPadView];
	}
	[self refreshControllers];
}

- (void)stop
{
	if (!self.started)
	{
		return;
	}
	self.started = NO;
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self.virtualPadView removeFromSuperview];
	self.virtualPadView = nil;
	self.physicalControllers = @[];
	[self.hapticEngines removeAllObjects];
}

- (void)controllerChanged:(NSNotification*)notification
{
	(void)notification;
	[self refreshControllers];
}

- (GCController*)controllerAtIndex:(NSUInteger)index
{
	@synchronized(self)
	{
		if (index < self.physicalControllers.count)
		{
			return self.physicalControllers[index];
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
		return std::clamp(value, -1.0f, 1.0f);
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
	GCController* controller = [controller_manager() controllerAtIndex:index];
	GCExtendedGamepad* gamepad = controller.extendedGamepad;
	if (!gamepad)
	{
		RPCS3IOSVirtualPadView* virtualPad = controller_manager().virtualPadView;
		if (index == 0 && virtualPad && !virtualPad.hidden)
		{
			@synchronized(virtualPad)
			{
				snapshot = virtualPad->snapshot;
			}
			return true;
		}
		snapshot = {};
		return false;
	}

	snapshot = {};
	snapshot.connected = true;
	snapshot.left_x = clamp_unit(gamepad.leftThumbstick.xAxis.value);
	snapshot.left_y = clamp_unit(gamepad.leftThumbstick.yAxis.value);
	snapshot.right_x = clamp_unit(gamepad.rightThumbstick.xAxis.value);
	snapshot.right_y = clamp_unit(gamepad.rightThumbstick.yAxis.value);
	snapshot.left_trigger = std::clamp(gamepad.leftTrigger.value, 0.0f, 1.0f);
	snapshot.right_trigger = std::clamp(gamepad.rightTrigger.value, 0.0f, 1.0f);
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
		snapshot.battery_level = std::clamp(battery.batteryLevel, 0.0f, 1.0f);
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

void ios_controller_rumble(std::size_t index, float low_frequency, float high_frequency)
{
	GCController* controller = [controller_manager() controllerAtIndex:index];
	if (!controller && index == 0 && controller_manager().virtualPadView && !controller_manager().virtualPadView.hidden)
	{
		const float intensity = std::clamp(std::max(low_frequency, high_frequency), 0.0f, 1.0f);
		if (intensity > 0.0f)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				UIImpactFeedbackGenerator* feedback = [[UIImpactFeedbackGenerator alloc]
					initWithStyle:intensity > 0.65f ? UIImpactFeedbackStyleHeavy : UIImpactFeedbackStyleMedium];
				[feedback prepare];
				[feedback impactOccurredWithIntensity:intensity];
			});
		}
		return;
	}
	GCDeviceHaptics* haptics = controller.haptics;
	if (!haptics)
	{
		return;
	}

	const float intensity = std::clamp(std::max(low_frequency, high_frequency), 0.0f, 1.0f);
	if (intensity <= 0.0f)
	{
		return;
	}
	const float sharpness = std::clamp(high_frequency, 0.0f, 1.0f);
	dispatch_async(dispatch_get_main_queue(), ^{
		NSError* error = nil;
		CHHapticEngine* engine = [controller_manager().hapticEngines objectForKey:controller];
		if (!engine)
		{
			engine = [haptics createEngineWithLocality:GCHapticsLocalityDefault];
			if (!engine)
			{
				return;
			}
			[controller_manager().hapticEngines setObject:engine forKey:controller];
		}
		[engine startAndReturnError:&error];
		if (error)
		{
			return;
		}
		NSArray<CHHapticEventParameter*>* parameters = @[
			[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity],
			[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharpness]
		];
		CHHapticEvent* event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
			parameters:parameters relativeTime:0 duration:0.08];
		CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&error];
		id<CHHapticPatternPlayer> player = error ? nil : [engine createPlayerWithPattern:pattern error:&error];
		if (player && !error)
		{
			[player startAtTime:CHHapticTimeImmediate error:nil];
		}
	});
}
