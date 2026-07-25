#import <UIKit/UIKit.h>

#include "RPCS3Core.h"

#include <algorithm>
#include <string>
#include <vector>

namespace
{
NSString* ns_string(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

std::string copy_core_string(size_t (*copy_function)(char*, size_t))
{
    const size_t required = copy_function(nullptr, 0);
    if (!required)
    {
        return {};
    }

    std::vector<char> buffer(required);
    copy_function(buffer.data(), buffer.size());
    return buffer.data();
}

std::string import_url(NSURL* url, rpcs3_ios_core_result* result)
{
    if (!url.fileURL)
    {
        if (result)
        {
            *result = RPCS3_IOS_CORE_INVALID_ARGUMENT;
        }
        return {};
    }

    const BOOL scoped = [url startAccessingSecurityScopedResource];
    size_t required = 0;
    rpcs3_ios_core_result import_result = rpcs3_ios_core_import_path(
        url.fileSystemRepresentation, nullptr, 0, &required);
    std::vector<char> imported(std::max<size_t>(required, 1));
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
    if (result)
    {
        *result = import_result;
    }
    return import_result == RPCS3_IOS_CORE_SUCCESS ? std::string(imported.data()) : std::string{};
}
}

@interface RPCS3CoreLinkAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@interface RPCS3CoreLinkAppDelegate (OpenURL)
@end

@implementation RPCS3CoreLinkAppDelegate (OpenURL)

- (UIViewController*)rpcs3_presentingViewController
{
    UIViewController* controller = self.window.rootViewController;
    while (controller.presentedViewController)
    {
        controller = controller.presentedViewController;
    }
    return controller;
}

- (void)rpcs3_presentMessage:(NSString*)title detail:(NSString*)detail
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
            message:detail preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self rpcs3_presentingViewController] presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rpcs3_installImportedPath:(std::string)path firmware:(BOOL)firmware
{
    const std::string path_copy = std::move(path);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const rpcs3_ios_core_result result = firmware
            ? rpcs3_ios_core_install_firmware(path_copy.c_str(), 0, 1, nullptr, nullptr)
            : rpcs3_ios_core_install_package(path_copy.c_str(), nullptr, nullptr);
        const std::string detail = copy_core_string(rpcs3_ios_core_copy_last_error);
        NSString* title = result == RPCS3_IOS_CORE_SUCCESS
            ? (firmware ? @"Firmware Installed" : @"Package Installed")
            : (firmware ? @"Firmware Installation Failed" : @"Package Installation Failed");
        NSString* message = result == RPCS3_IOS_CORE_SUCCESS
            ? @"The imported item was installed successfully."
            : (detail.empty() ? @"The installation did not complete." : ns_string(detail));
        [self rpcs3_presentMessage:title detail:message];
    });
}

- (void)rpcs3_confirmInstallation:(std::string)path
                         filename:(NSString*)filename
                         firmware:(BOOL)firmware
{
    const std::string path_copy = std::move(path);
    NSString* title = firmware ? @"Install PS3 Firmware" : @"Install Package";
    NSString* message = [NSString stringWithFormat:@"Import completed. Install %@ now?", filename];
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Install"
        style:firmware ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
        handler:^(UIAlertAction*) {
            [self rpcs3_installImportedPath:path_copy firmware:firmware];
        }]];
    [[self rpcs3_presentingViewController] presentViewController:alert animated:YES completion:nil];
}

- (BOOL)application:(UIApplication*)application
            openURL:(NSURL*)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options
{
    (void)application;
    (void)options;

    if (!url.fileURL || !rpcs3_ios_core_is_initialized())
    {
        return NO;
    }

    rpcs3_ios_core_result import_result = RPCS3_IOS_CORE_PLATFORM_ERROR;
    const std::string imported = import_url(url, &import_result);
    if (import_result != RPCS3_IOS_CORE_SUCCESS)
    {
        const std::string detail = copy_core_string(rpcs3_ios_core_copy_last_error);
        [self rpcs3_presentMessage:@"Import Failed"
            detail:detail.empty() ? @"The selected item could not be imported." : ns_string(detail)];
        return NO;
    }

    NSString* extension = url.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"pup"])
    {
        [self rpcs3_confirmInstallation:imported filename:url.lastPathComponent firmware:YES];
        return YES;
    }
    if ([extension isEqualToString:@"pkg"])
    {
        [self rpcs3_confirmInstallation:imported filename:url.lastPathComponent firmware:NO];
        return YES;
    }

    const rpcs3_ios_boot_result boot_result = rpcs3_ios_core_boot_path(imported.c_str(), 1);
    if (boot_result != RPCS3_IOS_BOOT_SUCCESS)
    {
        const std::string detail = copy_core_string(rpcs3_ios_core_copy_last_error);
        [self rpcs3_presentMessage:@"Boot Request Failed"
            detail:detail.empty()
                ? [NSString stringWithFormat:@"RPCS3 returned boot result %u.", (unsigned int)boot_result]
                : ns_string(detail)];
        return NO;
    }

    return YES;
}

@end
