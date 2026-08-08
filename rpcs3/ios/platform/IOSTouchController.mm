#include "IOSPlatform.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <cmath>

namespace
{
enum class touch_control : NSInteger
{
    none,
    left_stick,
    right_stick,
    dpad,
    cross,
    circle,
    square,
    triangle,
    l1,
    r1,
    l2,
    r2,
    l3,
    r3,
    options,
    menu,
    home,
};

CGFloat distance(CGPoint lhs, CGPoint rhs)
{
    return std::hypot(lhs.x - rhs.x, lhs.y - rhs.y);
}

CGPoint subtract(CGPoint lhs, CGPoint rhs)
{
    return CGPointMake(lhs.x - rhs.x, lhs.y - rhs.y);
}

CGPoint clamp_vector(CGPoint value, CGFloat radius)
{
    const CGFloat length = std::hypot(value.x, value.y);
    if (length <= radius || length <= 0.0)
    {
        return value;
    }

    const CGFloat scale = radius / length;
    return CGPointMake(value.x * scale, value.y * scale);
}

void draw_control_circle(CGPoint center, CGFloat radius, NSString* label, bool pressed)
{
    UIColor* fill = pressed ? [UIColor colorWithWhite:1.0 alpha:0.38] : [UIColor colorWithWhite:0.0 alpha:0.24];
    UIColor* stroke = [UIColor colorWithWhite:1.0 alpha:0.65];
    UIBezierPath* path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)];
    [fill setFill];
    [stroke setStroke];
    path.lineWidth = 2.0;
    [path fill];
    [path stroke];

    NSDictionary* attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:std::max<CGFloat>(12.0, radius * 0.55)],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    };
    const CGSize text_size = [label sizeWithAttributes:attributes];
    [label drawAtPoint:CGPointMake(center.x - text_size.width / 2.0, center.y - text_size.height / 2.0)
          withAttributes:attributes];
}

void draw_control_rect(CGRect rect, NSString* label, bool pressed)
{
    UIColor* fill = pressed ? [UIColor colorWithWhite:1.0 alpha:0.38] : [UIColor colorWithWhite:0.0 alpha:0.24];
    UIColor* stroke = [UIColor colorWithWhite:1.0 alpha:0.65];
    UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:10.0];
    [fill setFill];
    [stroke setStroke];
    path.lineWidth = 2.0;
    [path fill];
    [path stroke];

    NSDictionary* attributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:13.0],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    };
    const CGSize text_size = [label sizeWithAttributes:attributes];
    [label drawAtPoint:CGPointMake(CGRectGetMidX(rect) - text_size.width / 2.0, CGRectGetMidY(rect) - text_size.height / 2.0)
          withAttributes:attributes];
}
}

@interface RPCS3TouchControllerView : UIView
@end

@implementation RPCS3TouchControllerView
{
    NSMutableDictionary<NSValue*, NSNumber*>* _touch_controls;
    rpcs3::ios::controller_state _state;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self)
    {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.multipleTouchEnabled = YES;
    self.userInteractionEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _touch_controls = [[NSMutableDictionary alloc] init];
    [self publishState];
    return self;
}

- (void)dealloc
{
    rpcs3::ios::clear_virtual_controller_state();
}

- (CGFloat)unit
{
    return std::clamp<CGFloat>(std::min(self.bounds.size.width, self.bounds.size.height) / 8.0, 38.0, 72.0);
}

- (CGPoint)leftStickCenter
{
    return CGPointMake(self.bounds.size.width * 0.20, self.bounds.size.height * 0.73);
}

- (CGPoint)rightStickCenter
{
    return CGPointMake(self.bounds.size.width * 0.66, self.bounds.size.height * 0.79);
}

- (CGPoint)dpadCenter
{
    return CGPointMake(self.bounds.size.width * 0.18, self.bounds.size.height * 0.43);
}

- (CGPoint)faceCenter
{
    return CGPointMake(self.bounds.size.width * 0.84, self.bounds.size.height * 0.60);
}

- (CGRect)shoulderRect:(bool)right trigger:(bool)trigger
{
    const CGFloat unit = self.unit;
    const CGFloat width = unit * 1.45;
    const CGFloat x = right ? self.bounds.size.width - width - 16.0 : 16.0;
    const CGFloat y = self.safeAreaInsets.top + (trigger ? unit * 0.63 : 0.0);
    return CGRectMake(x, y, width, unit * 0.52);
}

- (CGRect)centerButtonRect:(touch_control)control
{
    const CGFloat unit = self.unit;
    const CGFloat width = unit * 0.92;
    const CGFloat gap = 8.0;
    CGFloat offset = 0.0;
    if (control == touch_control::options)
    {
        offset = -(width + gap);
    }
    else if (control == touch_control::menu)
    {
        offset = width + gap;
    }
    return CGRectMake(self.bounds.size.width / 2.0 - width / 2.0 + offset,
        self.safeAreaInsets.top + unit * 0.12,
        width,
        unit * 0.46);
}

- (CGPoint)faceButtonCenter:(touch_control)control
{
    const CGPoint center = self.faceCenter;
    const CGFloat spacing = self.unit * 0.72;
    switch (control)
    {
    case touch_control::cross: return CGPointMake(center.x, center.y + spacing);
    case touch_control::circle: return CGPointMake(center.x + spacing, center.y);
    case touch_control::square: return CGPointMake(center.x - spacing, center.y);
    case touch_control::triangle: return CGPointMake(center.x, center.y - spacing);
    default: return center;
    }
}

- (void)drawRect:(CGRect)rect
{
    (void)rect;
    const CGFloat unit = self.unit;
    const CGFloat stick_radius = unit * 0.82;
    const CGFloat button_radius = unit * 0.42;

    draw_control_circle(self.leftStickCenter, stick_radius, @"L", std::abs(_state.left_x) > 0.02f || std::abs(_state.left_y) > 0.02f);
    draw_control_circle(self.rightStickCenter, stick_radius, @"R", std::abs(_state.right_x) > 0.02f || std::abs(_state.right_y) > 0.02f);
    draw_control_circle(self.dpadCenter, stick_radius * 0.82, @"＋", _state.dpad_up || _state.dpad_down || _state.dpad_left || _state.dpad_right);

    draw_control_circle([self faceButtonCenter:touch_control::cross], button_radius, @"×", _state.button_a);
    draw_control_circle([self faceButtonCenter:touch_control::circle], button_radius, @"○", _state.button_b);
    draw_control_circle([self faceButtonCenter:touch_control::square], button_radius, @"□", _state.button_x);
    draw_control_circle([self faceButtonCenter:touch_control::triangle], button_radius, @"△", _state.button_y);

    draw_control_rect([self shoulderRect:false trigger:false], @"L1", _state.left_shoulder);
    draw_control_rect([self shoulderRect:true trigger:false], @"R1", _state.right_shoulder);
    draw_control_rect([self shoulderRect:false trigger:true], @"L2", _state.left_trigger > 0.0f);
    draw_control_rect([self shoulderRect:true trigger:true], @"R2", _state.right_trigger > 0.0f);
    draw_control_rect([self centerButtonRect:touch_control::options], @"SELECT", _state.options);
    draw_control_rect([self centerButtonRect:touch_control::home], @"PS", _state.home);
    draw_control_rect([self centerButtonRect:touch_control::menu], @"START", _state.menu);

    draw_control_circle(CGPointMake(self.leftStickCenter.x, self.leftStickCenter.y - stick_radius - button_radius * 1.3),
        button_radius * 0.72, @"L3", _state.left_thumbstick);
    draw_control_circle(CGPointMake(self.rightStickCenter.x, self.rightStickCenter.y - stick_radius - button_radius * 1.3),
        button_radius * 0.72, @"R3", _state.right_thumbstick);
}

- (touch_control)controlAtPoint:(CGPoint)point
{
    const CGFloat unit = self.unit;
    const CGFloat stick_radius = unit * 1.05;
    const CGFloat button_radius = unit * 0.62;

    if (distance(point, self.leftStickCenter) <= stick_radius) return touch_control::left_stick;
    if (distance(point, self.rightStickCenter) <= stick_radius) return touch_control::right_stick;
    if (distance(point, self.dpadCenter) <= stick_radius * 0.88) return touch_control::dpad;

    for (touch_control control : {touch_control::cross, touch_control::circle, touch_control::square, touch_control::triangle})
    {
        if (distance(point, [self faceButtonCenter:control]) <= button_radius)
        {
            return control;
        }
    }

    if (CGRectContainsPoint([self shoulderRect:false trigger:false], point)) return touch_control::l1;
    if (CGRectContainsPoint([self shoulderRect:true trigger:false], point)) return touch_control::r1;
    if (CGRectContainsPoint([self shoulderRect:false trigger:true], point)) return touch_control::l2;
    if (CGRectContainsPoint([self shoulderRect:true trigger:true], point)) return touch_control::r2;
    if (CGRectContainsPoint([self centerButtonRect:touch_control::options], point)) return touch_control::options;
    if (CGRectContainsPoint([self centerButtonRect:touch_control::home], point)) return touch_control::home;
    if (CGRectContainsPoint([self centerButtonRect:touch_control::menu], point)) return touch_control::menu;

    const CGPoint l3 = CGPointMake(self.leftStickCenter.x, self.leftStickCenter.y - unit * 0.82 - button_radius * 0.9);
    const CGPoint r3 = CGPointMake(self.rightStickCenter.x, self.rightStickCenter.y - unit * 0.82 - button_radius * 0.9);
    if (distance(point, l3) <= button_radius) return touch_control::l3;
    if (distance(point, r3) <= button_radius) return touch_control::r3;
    return touch_control::none;
}

- (void)updateContinuousControl:(touch_control)control point:(CGPoint)point
{
    const CGFloat radius = self.unit * 0.82;
    if (control == touch_control::left_stick || control == touch_control::right_stick)
    {
        const CGPoint center = control == touch_control::left_stick ? self.leftStickCenter : self.rightStickCenter;
        const CGPoint value = clamp_vector(subtract(point, center), radius);
        const float x = static_cast<float>(value.x / radius);
        const float y = static_cast<float>(-value.y / radius);
        if (control == touch_control::left_stick)
        {
            _state.left_x = x;
            _state.left_y = y;
        }
        else
        {
            _state.right_x = x;
            _state.right_y = y;
        }
        return;
    }

    if (control == touch_control::dpad)
    {
        const CGPoint value = subtract(point, self.dpadCenter);
        const CGFloat threshold = radius * 0.20;
        _state.dpad_left = value.x < -threshold;
        _state.dpad_right = value.x > threshold;
        _state.dpad_up = value.y < -threshold;
        _state.dpad_down = value.y > threshold;
    }
}

- (void)setButtonControl:(touch_control)control pressed:(bool)pressed
{
    switch (control)
    {
    case touch_control::cross: _state.button_a = pressed; break;
    case touch_control::circle: _state.button_b = pressed; break;
    case touch_control::square: _state.button_x = pressed; break;
    case touch_control::triangle: _state.button_y = pressed; break;
    case touch_control::l1: _state.left_shoulder = pressed; break;
    case touch_control::r1: _state.right_shoulder = pressed; break;
    case touch_control::l2: _state.left_trigger = pressed ? 1.0f : 0.0f; break;
    case touch_control::r2: _state.right_trigger = pressed ? 1.0f : 0.0f; break;
    case touch_control::l3: _state.left_thumbstick = pressed; break;
    case touch_control::r3: _state.right_thumbstick = pressed; break;
    case touch_control::options: _state.options = pressed; break;
    case touch_control::menu: _state.menu = pressed; break;
    case touch_control::home: _state.home = pressed; break;
    default: break;
    }
}

- (void)releaseControl:(touch_control)control
{
    if (control == touch_control::left_stick)
    {
        _state.left_x = 0.0f;
        _state.left_y = 0.0f;
    }
    else if (control == touch_control::right_stick)
    {
        _state.right_x = 0.0f;
        _state.right_y = 0.0f;
    }
    else if (control == touch_control::dpad)
    {
        _state.dpad_up = false;
        _state.dpad_down = false;
        _state.dpad_left = false;
        _state.dpad_right = false;
    }
    else
    {
        [self setButtonControl:control pressed:false];
    }
}

- (void)publishState
{
    rpcs3::ios::set_virtual_controller_state(_state);
    [self setNeedsDisplay];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    for (UITouch* touch in touches)
    {
        const CGPoint point = [touch locationInView:self];
        const touch_control control = [self controlAtPoint:point];
        if (control == touch_control::none)
        {
            continue;
        }

        _touch_controls[[NSValue valueWithNonretainedObject:touch]] = @(static_cast<NSInteger>(control));
        [self setButtonControl:control pressed:true];
        [self updateContinuousControl:control point:point];
    }
    [self publishState];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    for (UITouch* touch in touches)
    {
        NSNumber* stored = _touch_controls[[NSValue valueWithNonretainedObject:touch]];
        if (!stored)
        {
            continue;
        }
        [self updateContinuousControl:static_cast<touch_control>(stored.integerValue) point:[touch locationInView:self]];
    }
    [self publishState];
}

- (void)finishTouches:(NSSet<UITouch*>*)touches
{
    for (UITouch* touch in touches)
    {
        NSValue* key = [NSValue valueWithNonretainedObject:touch];
        NSNumber* stored = _touch_controls[key];
        if (!stored)
        {
            continue;
        }

        const touch_control control = static_cast<touch_control>(stored.integerValue);
        [_touch_controls removeObjectForKey:key];

        bool still_active = false;
        for (NSNumber* other in _touch_controls.objectEnumerator)
        {
            if (other.integerValue == stored.integerValue)
            {
                still_active = true;
                break;
            }
        }
        if (!still_active)
        {
            [self releaseControl:control];
        }
    }
    [self publishState];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    [self finishTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    [self finishTouches:touches];
}
@end

static NSMapTable<UIView*, RPCS3TouchControllerView*>* g_touch_overlays = nil;
static bool g_touch_overlays_visible = true;

namespace rpcs3::ios
{
void attach_touch_controller_overlay(void* native_view)
{
    if (!native_view)
    {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView* parent = (__bridge UIView*)native_view;
        if (!g_touch_overlays)
        {
            g_touch_overlays = [NSMapTable weakToStrongObjectsMapTable];
        }
        if ([g_touch_overlays objectForKey:parent])
        {
            return;
        }

        RPCS3TouchControllerView* overlay = [[RPCS3TouchControllerView alloc] initWithFrame:parent.bounds];
        overlay.hidden = !g_touch_overlays_visible;
        [parent addSubview:overlay];
        [parent bringSubviewToFront:overlay];
        [g_touch_overlays setObject:overlay forKey:parent];
    });
}

void detach_touch_controller_overlay(void* native_view)
{
    if (!native_view)
    {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView* parent = (__bridge UIView*)native_view;
        RPCS3TouchControllerView* overlay = [g_touch_overlays objectForKey:parent];
        [overlay removeFromSuperview];
        [g_touch_overlays removeObjectForKey:parent];
        if (g_touch_overlays.count == 0)
        {
            clear_virtual_controller_state();
        }
    });
}

void set_touch_controller_overlay_visible(bool visible)
{
    g_touch_overlays_visible = visible;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (RPCS3TouchControllerView* overlay in g_touch_overlays.objectEnumerator)
        {
            overlay.hidden = !visible;
        }
        if (!visible)
        {
            clear_virtual_controller_state();
        }
    });
}
}
