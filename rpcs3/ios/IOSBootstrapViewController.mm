#include "IOSBootstrapViewController.h"
#include "IOSVulkanProbe.h"
#include "platform/IOSPlatform.h"

#import <QuartzCore/CAMetalLayer.h>

#include <string>
#include <vector>

NSNotificationName const RPCS3ControllerConfigurationChanged = @"RPCS3ControllerConfigurationChanged";
NSNotificationName const RPCS3ExternalDisplayChanged = @"RPCS3ExternalDisplayChanged";
NSNotificationName const RPCS3PerformanceChanged = @"RPCS3PerformanceChanged";

namespace
{
NSString* ns_string(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

NSString* controller_summary()
{
    const std::vector<rpcs3::ios::controller_state> controllers = rpcs3::ios::get_controller_states();
    if (controllers.empty())
    {
        return @"Controllers: none connected";
    }

    NSMutableArray<NSString*>* names = [NSMutableArray arrayWithCapacity:controllers.size()];
    for (std::size_t index = 0; index < controllers.size(); ++index)
    {
        const auto capabilities = rpcs3::ios::get_combined_controller_capabilities(index);
        NSString* name = controllers[index].vendor_name.empty() ? @"Game Controller" : ns_string(controllers[index].vendor_name);
        NSMutableArray<NSString*>* features = [NSMutableArray array];
        if (capabilities.has_motion) [features addObject:@"motion"];
        if (capabilities.has_haptics) [features addObject:@"haptics"];
        if (capabilities.has_battery && capabilities.battery_level >= 0.0f)
        {
            [features addObject:[NSString stringWithFormat:@"%.0f%%", capabilities.battery_level * 100.0f]];
        }
        NSString* suffix = features.count > 0
            ? [NSString stringWithFormat:@" [%@]", [features componentsJoinedByString:@", "]]
            : @"";
        [names addObject:[NSString stringWithFormat:@"P%lu %@%@", (unsigned long)index + 1, name, suffix]];
    }
    return [NSString stringWithFormat:@"Controllers: %@", [names componentsJoinedByString:@"; "]];
}

NSString* external_display_summary()
{
    const auto display = rpcs3::ios::get_external_display_state();
    if (!display.connected)
    {
        return @"External display: not connected";
    }
    return [NSString stringWithFormat:@"External display: %ux%u @ %.0f Hz (scale %.2f)",
        display.width, display.height, display.maximum_frames_per_second, display.scale];
}

NSString* performance_summary()
{
    const auto performance = rpcs3::ios::get_performance_state();
    return [NSString stringWithFormat:@"Memory: %.2f GiB available / %.2f GiB physical\nLow Power Mode: %@",
        performance.available_memory / 1073741824.0,
        performance.physical_memory / 1073741824.0,
        performance.low_power_mode ? @"enabled" : @"disabled"];
}
}

@interface RPCS3MetalView : UIView
@end

@implementation RPCS3MetalView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

@implementation RPCS3BootstrapViewController
{
    UILabel* _graphics_status;
    UILabel* _platform_status;
    UILabel* _controller_status;
    UILabel* _display_status;
    UILabel* _performance_status;
    UILabel* _action_status;
    RPCS3MetalView* _metal_view;
}

- (UILabel*)makeStatusLabel
{
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (UIButton*)makeButton:(NSString*)title action:(SEL)action prominent:(bool)prominent
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.configuration = prominent
        ? [UIButtonConfiguration borderedProminentButtonConfiguration]
        : [UIButtonConfiguration borderedButtonConfiguration];
    if (action)
    {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (UIButton*)makeJITProviderButton
{
    UIButton* button = [self makeButton:@"Request External JIT" action:nil prominent:false];
    NSMutableArray<UIMenuElement*>* actions = [NSMutableArray array];
    for (const auto& provider : rpcs3::ios::get_jit_provider_states())
    {
        const rpcs3::ios::jit_provider provider_id = provider.provider;
        const bool provider_available = provider.available;
        NSString* title = ns_string(provider.display_name);
        if (!provider_available)
        {
            title = [title stringByAppendingString:@" (not installed)"];
        }

        UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction* selected)
        {
            (void)selected;
            if (!provider_available)
            {
                self->_action_status.text = @"The selected JIT provider is not available on this device.";
                return;
            }

            std::string error;
            if (rpcs3::ios::request_jit(provider_id, &error))
            {
                self->_action_status.text = @"External JIT request sent. Return to RPCS3 and run the capability probe after attachment.";
            }
            else
            {
                self->_action_status.text = [NSString stringWithFormat:@"JIT request failed: %@", ns_string(error)];
            }
        }];
        [actions addObject:action];
    }
    button.menu = [UIMenu menuWithTitle:@"JIT Providers" children:actions];
    button.showsMenuAsPrimaryAction = YES;
    return button;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;

    UILabel* title_label = [[UILabel alloc] init];
    title_label.translatesAutoresizingMaskIntoConstraints = NO;
    title_label.text = @"RPCS3 iOS";
    title_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title_label.textAlignment = NSTextAlignmentCenter;

    UILabel* subtitle = [self makeStatusLabel];
    subtitle.text = @"Native platform, renderer, memory, input, and signing bring-up";
    subtitle.textColor = UIColor.secondaryLabelColor;

    _graphics_status = [self makeStatusLabel];
    _graphics_status.text = @"Checking MoltenVK…";
    _platform_status = [self makeStatusLabel];
    _controller_status = [self makeStatusLabel];
    _display_status = [self makeStatusLabel];
    _performance_status = [self makeStatusLabel];
    _action_status = [self makeStatusLabel];
    _action_status.textColor = UIColor.secondaryLabelColor;
    _action_status.text = @"No developer action has run yet.";

    UIButton* run_jit_probe = [self makeButton:@"Run Executable JIT Probe" action:@selector(runJITProbe:) prominent:false];
    UIButton* request_jit = [self makeJITProviderButton];
    UIButton* export_diagnostics = [self makeButton:@"Export Diagnostics" action:@selector(exportDiagnostics:) prominent:false];
    UIButton* import_files = [self makeButton:@"Import Files" action:@selector(importFiles:) prominent:true];
    UIButton* import_folder = [self makeButton:@"Import Folder" action:@selector(importFolder:) prominent:true];

    UIStackView* import_buttons = [[UIStackView alloc] initWithArrangedSubviews:@[import_files, import_folder]];
    import_buttons.axis = UILayoutConstraintAxisHorizontal;
    import_buttons.spacing = 12.0;
    import_buttons.distribution = UIStackViewDistributionFillEqually;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title_label,
        subtitle,
        _graphics_status,
        _platform_status,
        _performance_status,
        _controller_status,
        _display_status,
        run_jit_probe,
        request_jit,
        export_diagnostics,
        import_buttons,
        _action_status,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.alignment = UIStackViewAlignmentFill;

    _metal_view = [[RPCS3MetalView alloc] init];
    _metal_view.translatesAutoresizingMaskIntoConstraints = NO;
    _metal_view.hidden = YES;
    CAMetalLayer* metal_layer = (CAMetalLayer*)_metal_view.layer;
    metal_layer.framebufferOnly = NO;
    metal_layer.contentsScale = UIScreen.mainScreen.scale;

    [scroll addSubview:stack];
    [self.view addSubview:scroll];
    [self.view addSubview:_metal_view];

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
        [_metal_view.widthAnchor constraintEqualToConstant:16.0],
        [_metal_view.heightAnchor constraintEqualToConstant:16.0],
        [_metal_view.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [_metal_view.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(platformStateChanged:) name:RPCS3ControllerConfigurationChanged object:nil];
    [center addObserver:self selector:@selector(platformStateChanged:) name:RPCS3ExternalDisplayChanged object:nil];
    [center addObserver:self selector:@selector(platformStateChanged:) name:RPCS3PerformanceChanged object:nil];

    [self refreshPlatformStatus];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_graphics_status.text = RPCS3RunVulkanProbe((CAMetalLayer*)self->_metal_view.layer);
    });
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshPlatformStatus
{
    const auto paths = rpcs3::ios::get_runtime_paths();
    const auto jit = rpcs3::ios::query_extended_jit_capabilities();
    _platform_status.text = [NSString stringWithFormat:@"JIT: %@\nImports: %@", ns_string(jit.detail), ns_string(paths.imports)];
    _performance_status.text = performance_summary();
    _controller_status.text = controller_summary();
    _display_status.text = external_display_summary();
}

- (void)platformStateChanged:(NSNotification*)notification
{
    (void)notification;
    [self refreshPlatformStatus];
}

- (void)runJITProbe:(UIButton*)sender
{
    sender.enabled = NO;
    _action_status.text = @"Running executable-memory probe…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const auto result = rpcs3::ios::run_jit_execution_probe();
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            self->_action_status.text = [NSString stringWithFormat:@"JIT probe: %@", ns_string(result.detail)];
            [self refreshPlatformStatus];
        });
    });
}

- (void)exportDiagnostics:(UIButton*)sender
{
    sender.enabled = NO;
    std::string path;
    std::string error;
    if (!rpcs3::ios::write_diagnostics_report(&path, &error))
    {
        sender.enabled = YES;
        _action_status.text = [NSString stringWithFormat:@"Diagnostics failed: %@", ns_string(error)];
        return;
    }

    NSURL* url = [NSURL fileURLWithPath:ns_string(path)];
    UIActivityViewController* activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = sender;
    activity.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:activity animated:YES completion:^{
        sender.enabled = YES;
        self->_action_status.text = [NSString stringWithFormat:@"Diagnostics written to %@", url.lastPathComponent];
    }];
}

- (void)importFiles:(UIButton*)sender
{
    (void)sender;
    [self presentImporterAllowingDirectories:false];
}

- (void)importFolder:(UIButton*)sender
{
    (void)sender;
    [self presentImporterAllowingDirectories:true];
}

- (void)presentImporterAllowingDirectories:(bool)allow_directories
{
    _action_status.text = @"Waiting for document picker…";
    __weak RPCS3BootstrapViewController* weak_self = self;
    rpcs3::ios::present_import_picker((__bridge void*)self, allow_directories,
        [weak_self](std::vector<std::string> paths, std::string error)
    {
        RPCS3BootstrapViewController* strong_self = weak_self;
        if (!strong_self)
        {
            return;
        }
        if (!error.empty())
        {
            strong_self->_action_status.text = [NSString stringWithFormat:@"Import failed: %@", ns_string(error)];
            return;
        }
        if (paths.empty())
        {
            strong_self->_action_status.text = @"Import cancelled.";
            return;
        }

        NSMutableArray<NSString*>* imported = [NSMutableArray arrayWithCapacity:paths.size()];
        for (const std::string& path : paths)
        {
            [imported addObject:ns_string(path).lastPathComponent];
        }
        strong_self->_action_status.text = [NSString stringWithFormat:@"Imported: %@", [imported componentsJoinedByString:@", "]];
    });
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
    return UIRectEdgeAll;
}
@end
