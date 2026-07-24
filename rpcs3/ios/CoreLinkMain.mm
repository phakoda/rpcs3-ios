#import <UIKit/UIKit.h>

#include "RPCS3Core.h"

#include <array>
#include <string>
#include <vector>

namespace
{
std::string copy_core_string(size_t (*copy_function)(char*, size_t))
{
    const size_t required = copy_function(nullptr, 0);
    if (required == 0)
    {
        return {};
    }

    std::vector<char> buffer(required);
    copy_function(buffer.data(), buffer.size());
    return std::string(buffer.data());
}

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
    title.text = @"RPCS3Core.framework";

    UILabel* status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;

    const rpcs3_ios_jit_status jit = rpcs3_ios_core_query_jit_status();
    const rpcs3_ios_performance_status performance = rpcs3_ios_core_query_performance_status();
    const std::string jit_detail = copy_core_string(rpcs3_ios_core_copy_jit_detail);
    status.text = [NSString stringWithFormat:
        @"The application imports only RPCS3Core's public C header. The framework force-links the adapted rpcs3_emu archive and its complete static dependency closure.\n\n"
         "Initialized: %@\n"
         "Application Support: %s\n"
         "Available memory: %.2f GiB\n"
         "MAP_JIT allocation: %@\n"
         "JIT capability: %@\n\n"
         "No firmware or game workload is executed by this harness.",
        rpcs3_ios_core_is_initialized() ? @"yes" : @"no",
        rpcs3_ios_core_application_support_path(),
        performance.available_memory / 1073741824.0,
        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable",
        ns_string(jit_detail)];

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

    const rpcs3_ios_core_result result = rpcs3_ios_core_initialize();
    if (result != RPCS3_IOS_CORE_SUCCESS && result != RPCS3_IOS_CORE_ALREADY_INITIALIZED)
    {
        const std::string error = copy_core_string(rpcs3_ios_core_copy_last_error);
        NSLog(@"RPCS3Core initialization failed: %@", ns_string(error));
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RPCS3CoreLinkViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    (void)application;
    rpcs3_ios_core_shutdown();
}
@end

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RPCS3CoreLinkAppDelegate.class));
    }
}
