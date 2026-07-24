#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include "platform/IOSPlatform.h"

#include <vulkan/vulkan.h>

#include <cstring>
#include <string>
#include <vector>

namespace
{
NSString* const RPCS3ControllerConfigurationChanged = @"RPCS3ControllerConfigurationChanged";

NSString* ns_string(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

bool has_extension(const std::vector<VkExtensionProperties>& extensions, const char* name)
{
    for (const VkExtensionProperties& extension : extensions)
    {
        if (std::strcmp(extension.extensionName, name) == 0)
        {
            return true;
        }
    }

    return false;
}

NSString* result_description(VkResult result)
{
    return [NSString stringWithFormat:@"Vulkan error %d", static_cast<int>(result)];
}

NSString* run_vulkan_probe(CAMetalLayer* layer)
{
    uint32_t extension_count = 0;
    VkResult result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, nullptr);
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    std::vector<VkExtensionProperties> available_extensions(extension_count);
    result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, available_extensions.data());
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    if (!has_extension(available_extensions, VK_KHR_SURFACE_EXTENSION_NAME))
    {
        return @"MoltenVK loaded, but VK_KHR_surface is unavailable.";
    }

    if (!has_extension(available_extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME))
    {
        return @"MoltenVK loaded, but VK_EXT_metal_surface is unavailable.";
    }

    std::vector<const char*> enabled_extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };

    VkInstanceCreateFlags instance_flags = 0;
#ifdef VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
    if (has_extension(available_extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))
    {
        enabled_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instance_flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
#endif
#ifdef VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME
    if (has_extension(available_extensions, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME))
    {
        enabled_extensions.push_back(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
    }
#endif

    VkApplicationInfo application_info{};
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application_info.pApplicationName = "RPCS3 iOS bring-up";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 2, 0);
    application_info.pEngineName = "RPCS3";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 0, 2, 0);
    application_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instance_info{};
    instance_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.flags = instance_flags;
    instance_info.pApplicationInfo = &application_info;
    instance_info.enabledExtensionCount = static_cast<uint32_t>(enabled_extensions.size());
    instance_info.ppEnabledExtensionNames = enabled_extensions.data();

    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&instance_info, nullptr, &instance);
    if (result != VK_SUCCESS)
    {
        return result_description(result);
    }

    const auto create_metal_surface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT"));
    if (!create_metal_surface)
    {
        vkDestroyInstance(instance, nullptr);
        return @"vkCreateMetalSurfaceEXT was not exported by MoltenVK.";
    }

    VkMetalSurfaceCreateInfoEXT surface_info{};
    surface_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surface_info.pLayer = layer;

    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = create_metal_surface(instance, &surface_info, nullptr, &surface);
    if (result != VK_SUCCESS)
    {
        vkDestroyInstance(instance, nullptr);
        return result_description(result);
    }

    uint32_t device_count = 0;
    result = vkEnumeratePhysicalDevices(instance, &device_count, nullptr);
    if (result != VK_SUCCESS || device_count == 0)
    {
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return result == VK_SUCCESS ? @"Metal surface created, but no Vulkan device was enumerated." : result_description(result);
    }

    std::vector<VkPhysicalDevice> devices(device_count);
    result = vkEnumeratePhysicalDevices(instance, &device_count, devices.data());
    if (result != VK_SUCCESS)
    {
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return result_description(result);
    }

    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(devices.front(), &properties);

    const uint32_t api_version = properties.apiVersion;
    NSString* status = [NSString stringWithFormat:
        @"MoltenVK bring-up passed.\nGPU: %s\nVulkan: %u.%u.%u\nSurface: VK_EXT_metal_surface",
        properties.deviceName,
        VK_API_VERSION_MAJOR(api_version),
        VK_API_VERSION_MINOR(api_version),
        VK_API_VERSION_PATCH(api_version)];

    vkDestroySurfaceKHR(instance, surface, nullptr);
    vkDestroyInstance(instance, nullptr);
    return status;
}

NSString* controller_summary()
{
    const std::vector<rpcs3::ios::controller_state> controllers = rpcs3::ios::get_controller_states();
    if (controllers.empty())
    {
        return @"Controllers: none connected";
    }

    NSMutableArray<NSString*>* names = [NSMutableArray arrayWithCapacity:controllers.size()];
    for (const rpcs3::ios::controller_state& controller : controllers)
    {
        NSString* name = controller.vendor_name.empty() ? @"Game Controller" : ns_string(controller.vendor_name);
        [names addObject:[NSString stringWithFormat:@"P%d %@%@",
            controller.player_index < 0 ? static_cast<int>(names.count + 1) : controller.player_index + 1,
            name,
            controller.has_extended_gamepad ? @" (extended)" : @""]];
    }
    return [NSString stringWithFormat:@"Controllers: %@", [names componentsJoinedByString:@", "]];
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

@interface RPCS3ViewController : UIViewController
@end

@implementation RPCS3ViewController
{
    UILabel* _graphics_status;
    UILabel* _platform_status;
    UILabel* _controller_status;
    UILabel* _import_status;
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

- (UIButton*)makeButton:(NSString*)title action:(SEL)action
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    button.configuration = [UIButtonConfiguration borderedProminentButtonConfiguration];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel* title_label = [[UILabel alloc] init];
    title_label.translatesAutoresizingMaskIntoConstraints = NO;
    title_label.text = @"RPCS3 iOS";
    title_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title_label.textAlignment = NSTextAlignmentCenter;

    UILabel* subtitle = [self makeStatusLabel];
    subtitle.text = @"Native platform and renderer bring-up";
    subtitle.textColor = UIColor.secondaryLabelColor;

    _graphics_status = [self makeStatusLabel];
    _graphics_status.text = @"Checking MoltenVK…";

    _platform_status = [self makeStatusLabel];
    _controller_status = [self makeStatusLabel];
    _import_status = [self makeStatusLabel];
    _import_status.textColor = UIColor.secondaryLabelColor;
    _import_status.text = @"Imported files are copied into Documents/Imports.";

    UIButton* import_files = [self makeButton:@"Import Files" action:@selector(importFiles:)];
    UIButton* import_folder = [self makeButton:@"Import Folder" action:@selector(importFolder:)];

    UIStackView* button_stack = [[UIStackView alloc] initWithArrangedSubviews:@[import_files, import_folder]];
    button_stack.translatesAutoresizingMaskIntoConstraints = NO;
    button_stack.axis = UILayoutConstraintAxisHorizontal;
    button_stack.spacing = 12.0;
    button_stack.distribution = UIStackViewDistributionFillEqually;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title_label,
        subtitle,
        _graphics_status,
        _platform_status,
        _controller_status,
        button_stack,
        _import_status,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    stack.alignment = UIStackViewAlignmentFill;

    _metal_view = [[RPCS3MetalView alloc] init];
    _metal_view.translatesAutoresizingMaskIntoConstraints = NO;
    _metal_view.hidden = YES;

    CAMetalLayer* metal_layer = (CAMetalLayer*)_metal_view.layer;
    metal_layer.framebufferOnly = NO;
    metal_layer.contentsScale = UIScreen.mainScreen.scale;

    [self.view addSubview:stack];
    [self.view addSubview:_metal_view];

    UILayoutGuide* guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],
        [_metal_view.widthAnchor constraintEqualToConstant:16.0],
        [_metal_view.heightAnchor constraintEqualToConstant:16.0],
        [_metal_view.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [_metal_view.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(controllerConfigurationChanged:)
                                               name:RPCS3ControllerConfigurationChanged
                                             object:nil];

    [self refreshPlatformStatus];
    [self refreshControllerStatus];

    dispatch_async(dispatch_get_main_queue(), ^{
        self->_graphics_status.text = run_vulkan_probe((CAMetalLayer*)self->_metal_view.layer);
    });
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshPlatformStatus
{
    const rpcs3::ios::runtime_paths paths = rpcs3::ios::get_runtime_paths();
    const rpcs3::ios::jit_capabilities jit = rpcs3::ios::query_jit_capabilities();
    _platform_status.text = [NSString stringWithFormat:@"JIT: %@\nImports: %@",
        ns_string(jit.detail), ns_string(paths.imports)];
}

- (void)refreshControllerStatus
{
    _controller_status.text = controller_summary();
}

- (void)controllerConfigurationChanged:(NSNotification*)notification
{
    (void)notification;
    [self refreshControllerStatus];
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
    _import_status.text = @"Waiting for document picker…";
    __weak RPCS3ViewController* weak_self = self;
    rpcs3::ios::present_import_picker((__bridge void*)self, allow_directories,
        [weak_self](std::vector<std::string> paths, std::string error)
    {
        RPCS3ViewController* strong_self = weak_self;
        if (!strong_self)
        {
            return;
        }

        if (!error.empty())
        {
            strong_self->_import_status.text = [NSString stringWithFormat:@"Import failed: %@", ns_string(error)];
            return;
        }
        if (paths.empty())
        {
            strong_self->_import_status.text = @"Import cancelled.";
            return;
        }

        NSMutableArray<NSString*>* imported = [NSMutableArray arrayWithCapacity:paths.size()];
        for (const std::string& path : paths)
        {
            [imported addObject:ns_string(path).lastPathComponent];
        }
        strong_self->_import_status.text = [NSString stringWithFormat:@"Imported: %@",
            [imported componentsJoinedByString:@", "]];
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

@interface RPCS3AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RPCS3AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launch_options
{
    (void)application;
    (void)launch_options;

    rpcs3::ios::initialize();
    rpcs3::ios::set_lifecycle_callbacks({
        .controller_configuration_changed = []
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:RPCS3ControllerConfigurationChanged object:nil];
            });
        },
    });

    std::string audio_error;
    if (!rpcs3::ios::configure_audio_session(false, false, &audio_error))
    {
        NSLog(@"RPCS3 iOS audio session setup failed: %@", ns_string(audio_error));
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RPCS3ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    (void)application;
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
