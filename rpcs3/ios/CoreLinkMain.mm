#import <UIKit/UIKit.h>

#include "platform/IOSPlatform.h"

#include <string>

namespace rpcs3::ios
{
int core_port_anchor();
}

namespace
{
NSString* ns_string(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}
}

@interface RPCS3CoreLinkViewController : UIViewController
@end

@implementation RPCS3CoreLinkViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel* title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"RPCS3 iOS Core";

    UILabel* status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;

    const int anchor_result = rpcs3::ios::core_port_anchor();
    const auto jit = rpcs3::ios::query_extended_jit_capabilities();
    const auto performance = rpcs3::ios::get_performance_state();
    status.text = [NSString stringWithFormat:
        @"The complete rpcs3_emu static archive and its transitive dependency graph were linked into this application target.\n\n"
         "Core anchor: %@\n"
         "Available memory: %.2f GiB\n"
         "JIT capability: %@\n\n"
         "This harness validates final symbol resolution only. It does not boot firmware or execute a game.",
        anchor_result == 0 ? @"ready" : @"runtime path error",
        performance.available_memory / 1073741824.0,
        ns_string(jit.detail)];

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, status]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 20.0;

    [self.view addSubview:stack];
    UILayoutGuide* guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],
        [stack.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
    ]];
}
@end

@interface RPCS3CoreLinkAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RPCS3CoreLinkAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launch_options
{
    (void)application;
    (void)launch_options;

    rpcs3::ios::configure_moltenvk({});
    rpcs3::ios::initialize();
    rpcs3::ios::set_idle_timer_disabled(true);

    std::string audio_error;
    if (!rpcs3::ios::configure_audio_session(false, false, &audio_error))
    {
        NSLog(@"RPCS3 core-link audio session setup failed: %@", ns_string(audio_error));
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RPCS3CoreLinkViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    (void)application;
    rpcs3::ios::set_idle_timer_disabled(false);
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::shutdown();
}
@end

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RPCS3CoreLinkAppDelegate.class));
    }
}
