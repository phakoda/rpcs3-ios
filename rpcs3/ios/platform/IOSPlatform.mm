#include "IOSPlatform.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <Security/SecTask.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <memory>
#include <mutex>
#include <utility>

namespace
{
using namespace rpcs3::ios;

std::mutex g_callbacks_mutex;
lifecycle_callbacks g_callbacks;
std::atomic_bool g_initialized = false;
std::atomic_bool g_audio_mix_with_others = false;
std::atomic_bool g_audio_respect_silent_mode = false;

std::string utf8_string(NSString* value)
{
    if (!value)
    {
        return {};
    }

    const char* utf8 = value.UTF8String;
    return utf8 ? std::string(utf8) : std::string{};
}

std::string path_string(NSString* value)
{
    if (!value)
    {
        return {};
    }

    const char* path = value.fileSystemRepresentation;
    return path ? std::string(path) : std::string{};
}

NSString* ns_path(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}

std::string with_trailing_slash(std::string path)
{
    if (!path.empty() && path.back() != '/')
    {
        path.push_back('/');
    }
    return path;
}

NSString* error_text(NSError* error)
{
    if (!error)
    {
        return @"Unknown iOS platform error";
    }

    if (error.localizedFailureReason.length > 0)
    {
        return [NSString stringWithFormat:@"%@: %@", error.localizedDescription, error.localizedFailureReason];
    }

    return error.localizedDescription;
}

void set_error(std::string* output, NSError* error)
{
    if (output)
    {
        *output = utf8_string(error_text(error));
    }
}

void invoke_callback(std::function<void()> lifecycle_callbacks::* member)
{
    std::function<void()> callback;
    {
        std::lock_guard lock(g_callbacks_mutex);
        callback = g_callbacks.*member;
    }

    if (callback)
    {
        callback();
    }
}

NSURL* directory_url(NSSearchPathDirectory directory, NSString* child, bool create)
{
    NSError* error = nil;
    NSURL* url = [[NSFileManager defaultManager] URLForDirectory:directory
                                                       inDomain:NSUserDomainMask
                                              appropriateForURL:nil
                                                         create:create
                                                          error:&error];
    if (!url)
    {
        return nil;
    }

    if (child.length > 0)
    {
        url = [url URLByAppendingPathComponent:child isDirectory:YES];
    }

    if (create)
    {
        error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:url
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error])
        {
            return nil;
        }
    }

    return url.standardizedURL;
}

runtime_paths build_runtime_paths()
{
    runtime_paths result;

    NSURL* support = directory_url(NSApplicationSupportDirectory, @"rpcs3", true);
    NSURL* caches = directory_url(NSCachesDirectory, @"rpcs3", true);
    NSURL* documents = directory_url(NSDocumentDirectory, nil, true);
    NSURL* imports = documents ? [documents URLByAppendingPathComponent:@"Imports" isDirectory:YES] : nil;
    NSURL* temporary = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    temporary = [temporary URLByAppendingPathComponent:@"rpcs3" isDirectory:YES];

    NSError* error = nil;
    if (imports)
    {
        [[NSFileManager defaultManager] createDirectoryAtURL:imports
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error];
    }
    error = nil;
    if (temporary)
    {
        [[NSFileManager defaultManager] createDirectoryAtURL:temporary
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error];
    }

    result.application_support = with_trailing_slash(path_string(support.path));
    result.caches = with_trailing_slash(path_string(caches.path));
    result.documents = with_trailing_slash(path_string(documents.path));
    result.imports = with_trailing_slash(path_string(imports.path));
    result.temporary = with_trailing_slash(path_string(temporary.path));
    return result;
}

const runtime_paths& cached_runtime_paths()
{
    static const runtime_paths paths = build_runtime_paths();
    return paths;
}

bool entitlement_is_true(CFStringRef entitlement)
{
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task)
    {
        return false;
    }

    CFErrorRef error = nullptr;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, entitlement, &error);
    bool enabled = false;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    }

    if (value)
    {
        CFRelease(value);
    }
    if (error)
    {
        CFRelease(error);
    }
    CFRelease(task);
    return enabled;
}

NSURL* unique_import_destination(NSURL* source_url)
{
    const runtime_paths paths = cached_runtime_paths();
    NSURL* imports_url = [NSURL fileURLWithPath:ns_path(paths.imports) isDirectory:YES];
    NSString* filename = source_url.lastPathComponent.length > 0 ? source_url.lastPathComponent : @"Imported Item";
    NSURL* destination = [imports_url URLByAppendingPathComponent:filename];

    NSString* stem = filename.stringByDeletingPathExtension;
    NSString* extension = filename.pathExtension;
    NSUInteger suffix = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:destination.path])
    {
        NSString* candidate = [NSString stringWithFormat:@"%@ %lu", stem, static_cast<unsigned long>(suffix++)];
        if (extension.length > 0)
        {
            candidate = [candidate stringByAppendingPathExtension:extension];
        }
        destination = [imports_url URLByAppendingPathComponent:candidate];
    }

    return destination;
}

bool import_url(NSURL* source_url, std::string* imported_path, std::string* error_output)
{
    if (!source_url || !source_url.isFileURL)
    {
        if (error_output)
        {
            *error_output = "The selected item is not a local file URL.";
        }
        return false;
    }

    const bool access_started = [source_url startAccessingSecurityScopedResource];
    NSURL* destination = unique_import_destination(source_url);

    __block NSError* coordination_error = nil;
    __block NSError* copy_error = nil;
    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:source_url
                                    options:0
                                      error:&coordination_error
                                 byAccessor:^(NSURL* coordinated_url)
    {
        [[NSFileManager defaultManager] copyItemAtURL:coordinated_url toURL:destination error:&copy_error];
    }];

    if (access_started)
    {
        [source_url stopAccessingSecurityScopedResource];
    }

    NSError* final_error = coordination_error ?: copy_error;
    if (final_error)
    {
        set_error(error_output, final_error);
        return false;
    }

    if (imported_path)
    {
        *imported_path = path_string(destination.path);
    }
    return true;
}

UIViewController* top_view_controller(UIViewController* controller)
{
    UIViewController* current = controller;
    while (current.presentedViewController)
    {
        current = current.presentedViewController;
    }

    if ([current isKindOfClass:UINavigationController.class])
    {
        return top_view_controller(((UINavigationController*)current).visibleViewController);
    }
    if ([current isKindOfClass:UITabBarController.class])
    {
        return top_view_controller(((UITabBarController*)current).selectedViewController);
    }
    return current;
}

UIViewController* active_presenter()
{
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class])
        {
            continue;
        }

        for (UIWindow* window in ((UIWindowScene*)scene).windows)
        {
            if (window.isKeyWindow && window.rootViewController)
            {
                return top_view_controller(window.rootViewController);
            }
        }
    }

    for (UIWindow* window in UIApplication.sharedApplication.windows)
    {
        if (window.isKeyWindow && window.rootViewController)
        {
            return top_view_controller(window.rootViewController);
        }
    }
    return nil;
}
}

@interface RPCS3PlatformObserver : NSObject
@end

@interface RPCS3ImportDelegate : NSObject <UIDocumentPickerDelegate>
- (instancetype)initWithCallback:(rpcs3::ios::import_callback)callback;
@end

static RPCS3PlatformObserver* g_observer = nil;
static NSMutableSet<RPCS3ImportDelegate*>* g_import_delegates = nil;

@implementation RPCS3PlatformObserver
- (instancetype)init
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [center addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
    [center addObserver:self selector:@selector(mediaServicesReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    [center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(controllerChanged:) name:GCControllerDidDisconnectNotification object:nil];

    if (@available(iOS 14.0, *))
    {
        GCController.shouldMonitorBackgroundEvents = YES;
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)willResignActive:(NSNotification*)notification
{
    (void)notification;
    invoke_callback(&rpcs3::ios::lifecycle_callbacks::will_resign_active);
}

- (void)didBecomeActive:(NSNotification*)notification
{
    (void)notification;
    invoke_callback(&rpcs3::ios::lifecycle_callbacks::did_become_active);
}

- (void)didEnterBackground:(NSNotification*)notification
{
    (void)notification;
    invoke_callback(&rpcs3::ios::lifecycle_callbacks::did_enter_background);
}

- (void)willEnterForeground:(NSNotification*)notification
{
    (void)notification;
    invoke_callback(&rpcs3::ios::lifecycle_callbacks::will_enter_foreground);
}

- (void)audioInterrupted:(NSNotification*)notification
{
    NSNumber* type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan)
    {
        invoke_callback(&rpcs3::ios::lifecycle_callbacks::audio_interruption_began);
    }
    else
    {
        invoke_callback(&rpcs3::ios::lifecycle_callbacks::audio_interruption_ended);
    }
}

- (void)mediaServicesReset:(NSNotification*)notification
{
    (void)notification;
    std::string ignored;
    rpcs3::ios::configure_audio_session(g_audio_mix_with_others, g_audio_respect_silent_mode, &ignored);
}

- (void)controllerChanged:(NSNotification*)notification
{
    (void)notification;
    invoke_callback(&rpcs3::ios::lifecycle_callbacks::controller_configuration_changed);
}
@end

@implementation RPCS3ImportDelegate
{
    rpcs3::ios::import_callback _callback;
}

- (instancetype)initWithCallback:(rpcs3::ios::import_callback)callback
{
    self = [super init];
    if (self)
    {
        _callback = std::move(callback);
    }
    return self;
}

- (void)finishWithPaths:(std::vector<std::string>)paths error:(std::string)error
{
    if (_callback)
    {
        _callback(std::move(paths), std::move(error));
    }
    [g_import_delegates removeObject:self];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    std::vector<std::string> imported;
    std::string first_error;

    for (NSURL* url in urls)
    {
        std::string destination;
        std::string error;
        if (import_url(url, &destination, &error))
        {
            imported.emplace_back(std::move(destination));
        }
        else if (first_error.empty())
        {
            first_error = std::move(error);
        }
    }

    [self finishWithPaths:std::move(imported) error:std::move(first_error)];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
    (void)controller;
    [self finishWithPaths:{} error:{}];
}
@end

namespace rpcs3::ios
{
void initialize()
{
    if (g_initialized.exchange(true))
    {
        return;
    }

    std::string ignored;
    prepare_runtime_directories(&ignored);

    if (NSThread.isMainThread)
    {
        g_observer = [[RPCS3PlatformObserver alloc] init];
        g_import_delegates = [[NSMutableSet alloc] init];
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), ^{
            g_observer = [[RPCS3PlatformObserver alloc] init];
            g_import_delegates = [[NSMutableSet alloc] init];
        });
    }
}

void shutdown()
{
    if (!g_initialized.exchange(false))
    {
        return;
    }

    if (NSThread.isMainThread)
    {
        g_observer = nil;
        [g_import_delegates removeAllObjects];
        g_import_delegates = nil;
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), ^{
            g_observer = nil;
            [g_import_delegates removeAllObjects];
            g_import_delegates = nil;
        });
    }

    deactivate_audio_session();
    set_lifecycle_callbacks({});
}

runtime_paths get_runtime_paths()
{
    return cached_runtime_paths();
}

bool prepare_runtime_directories(std::string* error)
{
    const runtime_paths paths = cached_runtime_paths();
    const std::string directories[] = {
        paths.application_support,
        paths.caches,
        paths.documents,
        paths.imports,
        paths.temporary,
    };

    for (const std::string& path : directories)
    {
        if (path.empty())
        {
            if (error)
            {
                *error = "iOS failed to resolve one or more sandbox directories.";
            }
            return false;
        }

        NSError* create_error = nil;
        NSURL* url = [NSURL fileURLWithPath:ns_path(path) isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:url
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&create_error])
        {
            set_error(error, create_error);
            return false;
        }
    }
    return true;
}

bool configure_audio_session(bool mix_with_others, bool respect_silent_mode, std::string* error)
{
    AVAudioSession* session = AVAudioSession.sharedInstance;
    AVAudioSessionCategory category = respect_silent_mode ? AVAudioSessionCategoryAmbient : AVAudioSessionCategoryPlayback;
    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionAllowAirPlay | AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    if (mix_with_others)
    {
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }

    NSError* session_error = nil;
    if (![session setCategory:category mode:AVAudioSessionModeDefault options:options error:&session_error])
    {
        set_error(error, session_error);
        return false;
    }

    session_error = nil;
    if (![session setPreferredSampleRate:48000.0 error:&session_error])
    {
        set_error(error, session_error);
        return false;
    }

    session_error = nil;
    if (![session setPreferredIOBufferDuration:(256.0 / 48000.0) error:&session_error])
    {
        set_error(error, session_error);
        return false;
    }

    session_error = nil;
    if (![session setActive:YES error:&session_error])
    {
        set_error(error, session_error);
        return false;
    }

    g_audio_mix_with_others = mix_with_others;
    g_audio_respect_silent_mode = respect_silent_mode;
    return true;
}

void deactivate_audio_session()
{
    NSError* error = nil;
    [AVAudioSession.sharedInstance setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:&error];
}

jit_capabilities query_jit_capabilities()
{
    jit_capabilities result;
#ifdef MAP_JIT
    result.map_jit_available = true;
    const long page_size = std::max<long>(::sysconf(_SC_PAGESIZE), 4096);
    void* mapping = ::mmap(nullptr, static_cast<size_t>(page_size), PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (mapping != MAP_FAILED)
    {
        result.map_jit_allocation_succeeded = true;
        ::munmap(mapping, static_cast<size_t>(page_size));
    }
#endif

    if (@available(iOS 14.0, *))
    {
        result.jit_write_protect_available = pthread_jit_write_protect_supported_np() != 0;
    }

    result.dynamic_codesigning_entitlement = entitlement_is_true(CFSTR("dynamic-codesigning"));
    result.allow_jit_entitlement = entitlement_is_true(CFSTR("com.apple.security.cs.allow-jit"));
    result.debugger_entitlement = entitlement_is_true(CFSTR("get-task-allow"));

    result.detail = "MAP_JIT=" + std::string(result.map_jit_available ? "available" : "unavailable") +
        ", allocation=" + std::string(result.map_jit_allocation_succeeded ? "ok" : "failed") +
        ", write-protect API=" + std::string(result.jit_write_protect_available ? "available" : "unavailable") +
        ", dynamic-codesigning=" + std::string(result.dynamic_codesigning_entitlement ? "present" : "absent") +
        ", allow-jit=" + std::string(result.allow_jit_entitlement ? "present" : "absent") +
        ", get-task-allow=" + std::string(result.debugger_entitlement ? "present" : "absent");
    return result;
}

std::vector<controller_state> get_controller_states()
{
    std::vector<controller_state> result;
    NSArray<GCController*>* controllers = GCController.controllers;
    result.reserve(controllers.count);

    for (GCController* controller in controllers)
    {
        controller_state state;
        state.connected = true;
        state.player_index = controller.playerIndex == GCControllerPlayerIndexUnset ? -1 : static_cast<int>(controller.playerIndex);
        state.vendor_name = utf8_string(controller.vendorName);

        GCExtendedGamepad* gamepad = controller.extendedGamepad;
        if (gamepad)
        {
            state.has_extended_gamepad = true;
            state.left_x = gamepad.leftThumbstick.xAxis.value;
            state.left_y = gamepad.leftThumbstick.yAxis.value;
            state.right_x = gamepad.rightThumbstick.xAxis.value;
            state.right_y = gamepad.rightThumbstick.yAxis.value;
            state.left_trigger = gamepad.leftTrigger.value;
            state.right_trigger = gamepad.rightTrigger.value;
            state.dpad_up = gamepad.dpad.up.isPressed;
            state.dpad_down = gamepad.dpad.down.isPressed;
            state.dpad_left = gamepad.dpad.left.isPressed;
            state.dpad_right = gamepad.dpad.right.isPressed;
            state.button_a = gamepad.buttonA.isPressed;
            state.button_b = gamepad.buttonB.isPressed;
            state.button_x = gamepad.buttonX.isPressed;
            state.button_y = gamepad.buttonY.isPressed;
            state.left_shoulder = gamepad.leftShoulder.isPressed;
            state.right_shoulder = gamepad.rightShoulder.isPressed;
            state.left_thumbstick = gamepad.leftThumbstickButton.isPressed;
            state.right_thumbstick = gamepad.rightThumbstickButton.isPressed;
            state.menu = gamepad.buttonMenu.isPressed;
            state.options = gamepad.buttonOptions.isPressed;
            state.home = gamepad.buttonHome.isPressed;
        }
        result.emplace_back(std::move(state));
    }
    return result;
}

void set_lifecycle_callbacks(lifecycle_callbacks callbacks)
{
    std::lock_guard lock(g_callbacks_mutex);
    g_callbacks = std::move(callbacks);
}

void present_import_picker(void* presenter, bool allow_directories, import_callback callback)
{
    auto work = std::make_shared<std::function<void()>>();
    *work = [presenter, allow_directories, callback = std::move(callback)]() mutable
    {
        UIViewController* controller = presenter ? (__bridge UIViewController*)presenter : active_presenter();
        if (!controller)
        {
            if (callback)
            {
                callback({}, "No active iOS view controller is available for the document picker.");
            }
            return;
        }

        NSArray<UTType*>* types = allow_directories ? @[UTTypeFolder] : @[UTTypeItem];
        UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:types asCopy:NO];
        picker.allowsMultipleSelection = !allow_directories;

        RPCS3ImportDelegate* delegate = [[RPCS3ImportDelegate alloc] initWithCallback:std::move(callback)];
        [g_import_delegates addObject:delegate];
        picker.delegate = delegate;
        [controller presentViewController:picker animated:YES completion:nil];
    };

    if (NSThread.isMainThread)
    {
        (*work)();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            (*work)();
        });
    }
}

bool import_item(std::string_view source_path, std::string* imported_path, std::string* error)
{
    if (source_path.empty())
    {
        if (error)
        {
            *error = "The import source path is empty.";
        }
        return false;
    }

    NSString* path = [[NSString alloc] initWithBytes:source_path.data()
                                             length:source_path.size()
                                           encoding:NSUTF8StringEncoding];
    if (!path)
    {
        if (error)
        {
            *error = "The import source path is not valid UTF-8.";
        }
        return false;
    }
    return import_url([NSURL fileURLWithPath:path], imported_path, error);
}
}
