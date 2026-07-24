#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3Core.h"

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

NSString* state_name(rpcs3_ios_emulator_state state)
{
    switch (state)
    {
    case RPCS3_IOS_EMULATOR_STOPPED: return @"stopped";
    case RPCS3_IOS_EMULATOR_LOADING: return @"loading";
    case RPCS3_IOS_EMULATOR_STOPPING: return @"stopping";
    case RPCS3_IOS_EMULATOR_RUNNING: return @"running";
    case RPCS3_IOS_EMULATOR_PAUSED: return @"paused";
    case RPCS3_IOS_EMULATOR_FROZEN: return @"frozen";
    case RPCS3_IOS_EMULATOR_READY: return @"ready";
    case RPCS3_IOS_EMULATOR_STARTING: return @"starting";
    case RPCS3_IOS_EMULATOR_UNAVAILABLE: return @"unavailable";
    }
    return @"unknown";
}

NSString* event_name(rpcs3_ios_core_event event)
{
    switch (event)
    {
    case RPCS3_IOS_CORE_EVENT_READY: return @"ready";
    case RPCS3_IOS_CORE_EVENT_RUN: return @"run";
    case RPCS3_IOS_CORE_EVENT_PAUSE: return @"pause";
    case RPCS3_IOS_CORE_EVENT_RESUME: return @"resume";
    case RPCS3_IOS_CORE_EVENT_STOP: return @"stop";
    case RPCS3_IOS_CORE_EVENT_MISSING_FIRMWARE: return @"missing firmware";
    case RPCS3_IOS_CORE_EVENT_PAD_CONNECTION_CHANGED: return @"controller change";
    case RPCS3_IOS_CORE_EVENT_FATAL_ERROR: return @"fatal error";
    }
    return @"unknown";
}
}

@class RPCS3CoreLinkViewController;

static void core_event_callback(rpcs3_ios_core_event event, const char* detail, void* context)
{
    RPCS3CoreLinkViewController* controller = (__bridge RPCS3CoreLinkViewController*)context;
    NSString* detail_string = detail ? [NSString stringWithUTF8String:detail] : @"";
    [controller performSelectorOnMainThread:@selector(handleCoreEvent:)
                                withObject:@{
                                    @"event": @(event),
                                    @"detail": detail_string ?: @"",
                                }
                             waitUntilDone:NO];
}

@interface RPCS3CoreLinkViewController : UIViewController <UIDocumentPickerDelegate>
- (void)handleCoreEvent:(NSDictionary*)payload;
@end

@implementation RPCS3CoreLinkViewController
{
    UILabel* _status;
    UILabel* _event_status;
    UIButton* _import_button;
    UIButton* _pause_button;
    UIButton* _resume_button;
    UIButton* _stop_button;
}

- (UIButton*)buttonWithTitle:(NSString*)title action:(SEL)action prominent:(BOOL)prominent
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.configuration = prominent
        ? [UIButtonConfiguration borderedProminentButtonConfiguration]
        : [UIButtonConfiguration borderedButtonConfiguration];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel* title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"RPCS3Core.framework";

    UILabel* explanation = [[UILabel alloc] init];
    explanation.translatesAutoresizingMaskIntoConstraints = NO;
    explanation.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    explanation.textAlignment = NSTextAlignmentCenter;
    explanation.numberOfLines = 0;
    explanation.textColor = UIColor.secondaryLabelColor;
    explanation.text = @"This host imports only RPCS3Core's public C module. It can initialize the real emulator, import local content, and drive a headless boot. RSX output remains Null until a native renderer host is connected.";

    _status = [[UILabel alloc] init];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    _status.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    _status.textAlignment = NSTextAlignmentLeft;
    _status.numberOfLines = 0;

    _event_status = [[UILabel alloc] init];
    _event_status.translatesAutoresizingMaskIntoConstraints = NO;
    _event_status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _event_status.textAlignment = NSTextAlignmentCenter;
    _event_status.numberOfLines = 0;
    _event_status.textColor = UIColor.secondaryLabelColor;
    _event_status.text = @"No emulator event received yet.";

    _import_button = [self buttonWithTitle:@"Import and Boot Content" action:@selector(importAndBoot:) prominent:YES];
    _pause_button = [self buttonWithTitle:@"Pause" action:@selector(pauseCore:) prominent:NO];
    _resume_button = [self buttonWithTitle:@"Resume" action:@selector(resumeCore:) prominent:NO];
    _stop_button = [self buttonWithTitle:@"Stop" action:@selector(stopCore:) prominent:NO];

    UIStackView* control_row = [[UIStackView alloc] initWithArrangedSubviews:@[_pause_button, _resume_button, _stop_button]];
    control_row.axis = UILayoutConstraintAxisHorizontal;
    control_row.distribution = UIStackViewDistributionFillEqually;
    control_row.spacing = 10.0;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title,
        explanation,
        _status,
        _import_button,
        control_row,
        _event_status,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16.0;

    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];

    UILayoutGuide* guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48.0],
    ]];

    rpcs3_ios_core_set_event_callback(core_event_callback, (__bridge void*)self);
    [self refreshStatus];
}

- (void)dealloc
{
    rpcs3_ios_core_set_event_callback(nullptr, nullptr);
}

- (void)refreshStatus
{
    const rpcs3_ios_jit_status jit = rpcs3_ios_core_query_jit_status();
    const rpcs3_ios_performance_status performance = rpcs3_ios_core_query_performance_status();
    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    const std::string title = copy_core_string(rpcs3_ios_core_copy_title);
    const std::string title_id = copy_core_string(rpcs3_ios_core_copy_title_id);
    const std::string boot_path = copy_core_string(rpcs3_ios_core_copy_boot_path);

    _status.text = [NSString stringWithFormat:
        @"Initialized: %@\n"
         "State: %@\n"
         "Title: %@\n"
         "Title ID: %@\n"
         "Boot path: %@\n"
         "Imports: %s\n"
         "Available memory: %.2f GiB\n"
         "MAP_JIT allocation: %@",
        rpcs3_ios_core_is_initialized() ? @"yes" : @"no",
        state_name(state),
        title.empty() ? @"—" : ns_string(title),
        title_id.empty() ? @"—" : ns_string(title_id),
        boot_path.empty() ? @"—" : ns_string(boot_path),
        rpcs3_ios_core_imports_path(),
        performance.available_memory / 1073741824.0,
        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable"];

    _pause_button.enabled = state == RPCS3_IOS_EMULATOR_RUNNING;
    _resume_button.enabled = state == RPCS3_IOS_EMULATOR_PAUSED;
    _stop_button.enabled = state != RPCS3_IOS_EMULATOR_STOPPED && state != RPCS3_IOS_EMULATOR_UNAVAILABLE;
}

- (void)handleCoreEvent:(NSDictionary*)payload
{
    const rpcs3_ios_core_event event = (rpcs3_ios_core_event)[payload[@"event"] unsignedIntValue];
    NSString* detail = payload[@"detail"];
    _event_status.text = detail.length > 0
        ? [NSString stringWithFormat:@"Event: %@ — %@", event_name(event), detail]
        : [NSString stringWithFormat:@"Event: %@", event_name(event)];
    [self refreshStatus];
}

- (void)importAndBoot:(UIButton*)sender
{
    (void)sender;
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeData, UTTypeFolder]
        asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    NSURL* url = urls.firstObject;
    if (!url.fileURL)
    {
        _event_status.text = @"The selected item does not have a local file URL.";
        return;
    }

    const BOOL scoped = [url startAccessingSecurityScopedResource];
    size_t required = 0;
    rpcs3_ios_core_result import_result = rpcs3_ios_core_import_path(
        url.fileSystemRepresentation,
        nullptr,
        0,
        &required);

    std::vector<char> imported(required > 0 ? required : 1);
    if (import_result == RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        import_result = rpcs3_ios_core_import_path(
            url.fileSystemRepresentation,
            imported.data(),
            imported.size(),
            &required);
    }

    if (scoped)
    {
        [url stopAccessingSecurityScopedResource];
    }

    if (import_result != RPCS3_IOS_CORE_SUCCESS)
    {
        _event_status.text = [NSString stringWithFormat:@"Import failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        return;
    }

    const rpcs3_ios_boot_result boot_result = rpcs3_ios_core_boot_path(imported.data(), 1);
    if (boot_result != RPCS3_IOS_BOOT_SUCCESS)
    {
        _event_status.text = [NSString stringWithFormat:@"Boot result %u: %@",
            (unsigned int)boot_result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    }
    else
    {
        _event_status.text = [NSString stringWithFormat:@"Boot accepted: %@", url.lastPathComponent];
    }
    [self refreshStatus];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
    (void)controller;
    _event_status.text = @"Import cancelled.";
}

- (void)pauseCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_pause();
    _event_status.text = [NSString stringWithFormat:@"Pause returned %u.", (unsigned int)result];
    [self refreshStatus];
}

- (void)resumeCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_resume();
    _event_status.text = [NSString stringWithFormat:@"Resume returned %u.", (unsigned int)result];
    [self refreshStatus];
}

- (void)stopCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_stop();
    _event_status.text = [NSString stringWithFormat:@"Stop returned %u.", (unsigned int)result];
    [self refreshStatus];
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
    rpcs3_ios_core_set_event_callback(nullptr, nullptr);
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
