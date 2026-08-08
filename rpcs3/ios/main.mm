#import <UIKit/UIKit.h>

#include "IOSBootstrapViewController.h"
#include "platform/IOSPlatform.h"

namespace
{
NSString* ns_string(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}
}

@interface RPCS3AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RPCS3AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launch_options
{
    (void)application;
    (void)launch_options;

    rpcs3::ios::configure_moltenvk({});
    rpcs3::ios::initialize();
    rpcs3::ios::set_lifecycle_callbacks({
        .controller_configuration_changed = []
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:RPCS3ControllerConfigurationChanged object:nil];
            });
        },
    });
    rpcs3::ios::set_external_display_callback([](rpcs3::ios::external_display_state)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RPCS3ExternalDisplayChanged object:nil];
        });
    });
    rpcs3::ios::set_performance_callback([](rpcs3::ios::performance_event, rpcs3::ios::performance_state)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RPCS3PerformanceChanged object:nil];
        });
    });

    std::string audio_error;
    if (!rpcs3::ios::configure_audio_session(false, false, &audio_error))
    {
        NSLog(@"RPCS3 iOS audio session setup failed: %@", ns_string(audio_error));
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RPCS3BootstrapViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    (void)application;
    rpcs3::ios::stop_all_controller_haptics();
    rpcs3::ios::set_external_display_callback({});
    rpcs3::ios::set_performance_callback({});
    rpcs3::ios::shutdown();
}
@end

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RPCS3AppDelegate.class));
    }
}
