#include "IOSCoreCallbacks.h"

#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

#include "Emu/System.h"
#include "Emu/Cell/Modules/cellMsgDialog.h"
#include "Emu/Cell/Modules/cellOskDialog.h"
#include "Emu/Cell/Modules/cellSaveData.h"
#include "Emu/Cell/Modules/sceNpTrophy.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace
{
void run_on_main_async(dispatch_block_t block)
{
    if (NSThread.isMainThread)
    {
        block();
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

UIViewController* top_view_controller()
{
    UIWindow* window = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
    {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState == UISceneActivationStateUnattached)
        {
            continue;
        }

        UIWindowScene* window_scene = (UIWindowScene*)scene;
        for (UIWindow* candidate in window_scene.windows)
        {
            if (candidate.isKeyWindow)
            {
                window = candidate;
                break;
            }
            if (!window && !candidate.hidden)
            {
                window = candidate;
            }
        }
        if (window.isKeyWindow)
        {
            break;
        }
    }

    UIViewController* controller = window.rootViewController;
    while (controller.presentedViewController)
    {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class])
    {
        controller = ((UINavigationController*)controller).visibleViewController;
    }
    if ([controller isKindOfClass:UITabBarController.class])
    {
        controller = ((UITabBarController*)controller).selectedViewController;
    }
    return controller;
}

NSString* ns_utf8(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

NSString* ns_utf16(const std::u16string& value)
{
    return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(value.data())
                                         length:value.size()] ?: @"";
}

std::u16string utf16_string(NSString* value)
{
    if (!value.length)
    {
        return {};
    }

    std::u16string result(value.length, u'\0');
    [value getCharacters:reinterpret_cast<unichar*>(result.data())
                    range:NSMakeRange(0, value.length)];
    return result;
}

class ios_msg_dialog final
    : public MsgDialogBase
    , public std::enable_shared_from_this<ios_msg_dialog>
{
public:
    void Create(const std::string& msg, const std::string& title) override
    {
        {
            std::lock_guard lock(m_mutex);
            m_message = msg;
            m_title = title;
            m_values = {0, 0};
            m_limits = {100, 100};
            m_progress_messages = {std::string{}, std::string{}};
            m_closed = false;
        }
        state = MsgDialogState::Open;

        const std::shared_ptr<ios_msg_dialog> self = shared_from_this();
        run_on_main_async(^{
            UIViewController* presenter = top_view_controller();
            if (!presenter)
            {
                self->finish(CELL_MSGDIALOG_BUTTON_ESCAPE);
                return;
            }

            NSString* dialog_title = self->m_title.empty()
                ? (self->type.se_normal ? @"RPCS3" : @"RPCS3 Error")
                : ns_utf8(self->m_title);
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:dialog_title
                message:ns_utf8(self->formatted_message())
                preferredStyle:UIAlertControllerStyleAlert];

            const u32 button_type = self->type.button_type.unshifted();
            if (button_type == CELL_MSGDIALOG_TYPE_BUTTON_TYPE_YESNO)
            {
                [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
                    self->finish(CELL_MSGDIALOG_BUTTON_YES);
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) {
                    self->finish(CELL_MSGDIALOG_BUTTON_NO);
                }]];
            }
            else if (button_type == CELL_MSGDIALOG_TYPE_BUTTON_TYPE_OK)
            {
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
                    self->finish(CELL_MSGDIALOG_BUTTON_OK);
                }]];
            }
            else if (!self->type.disable_cancel)
            {
                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) {
                    self->finish(CELL_MSGDIALOG_BUTTON_ESCAPE);
                }]];
            }

            {
                std::lock_guard lock(self->m_mutex);
                self->m_alert = alert;
            }
            [presenter presentViewController:alert animated:YES completion:nil];
        });
    }

    void Close(bool success) override
    {
        (void)success;
        state = MsgDialogState::Close;
        __strong UIAlertController* alert = nil;
        {
            std::lock_guard lock(m_mutex);
            if (m_closed)
            {
                return;
            }
            m_closed = true;
            alert = m_alert;
            m_alert = nil;
        }
        run_on_main_async(^{ [alert dismissViewControllerAnimated:YES completion:nil]; });
    }

    void SetMsg(const std::string& msg) override
    {
        {
            std::lock_guard lock(m_mutex);
            m_message = msg;
        }
        refresh_alert();
    }

    void ProgressBarSetMsg(u32 index, const std::string& msg) override
    {
        if (index >= m_progress_messages.size())
        {
            return;
        }
        {
            std::lock_guard lock(m_mutex);
            m_progress_messages[index] = msg;
        }
        refresh_alert();
    }

    void ProgressBarReset(u32 index) override
    {
        ProgressBarSetValue(index, 0);
    }

    void ProgressBarInc(u32 index, u32 delta) override
    {
        if (index >= m_values.size())
        {
            return;
        }
        {
            std::lock_guard lock(m_mutex);
            m_values[index] = std::min<u32>(m_values[index] + delta, m_limits[index]);
        }
        refresh_alert();
    }

    void ProgressBarSetValue(u32 index, u32 value) override
    {
        if (index >= m_values.size())
        {
            return;
        }
        {
            std::lock_guard lock(m_mutex);
            m_values[index] = std::min<u32>(value, m_limits[index]);
        }
        refresh_alert();
    }

    void ProgressBarSetLimit(u32 index, u32 limit) override
    {
        if (index >= m_limits.size())
        {
            return;
        }
        {
            std::lock_guard lock(m_mutex);
            m_limits[index] = std::max<u32>(limit, 1);
            m_values[index] = std::min(m_values[index], m_limits[index]);
        }
        refresh_alert();
    }

private:
    std::string formatted_message()
    {
        std::lock_guard lock(m_mutex);
        std::string result = m_message;
        const u32 count = std::min<u32>(type.progress_bar_count, 2);
        for (u32 index = 0; index < count; ++index)
        {
            const u32 percent = m_limits[index]
                ? static_cast<u32>((static_cast<u64>(m_values[index]) * 100) / m_limits[index])
                : 0;
            result += "\n\n";
            if (!m_progress_messages[index].empty())
            {
                result += m_progress_messages[index] + " — ";
            }
            result += std::to_string(percent) + "%";
        }
        return result;
    }

    void refresh_alert()
    {
        const std::shared_ptr<ios_msg_dialog> self = shared_from_this();
        const std::string message = formatted_message();
        run_on_main_async(^{
            std::lock_guard lock(self->m_mutex);
            self->m_alert.message = ns_utf8(message);
        });
    }

    void finish(s32 status)
    {
        std::function<void(s32)> callback;
        __strong UIAlertController* alert = nil;
        {
            std::lock_guard lock(m_mutex);
            if (m_closed)
            {
                return;
            }
            m_closed = true;
            callback = on_close;
            alert = m_alert;
            m_alert = nil;
        }
        state = MsgDialogState::Close;
        [alert dismissViewControllerAnimated:YES completion:nil];
        if (callback)
        {
            callback(status);
        }
    }

    std::mutex m_mutex;
    std::string m_message;
    std::string m_title;
    std::array<std::string, 2> m_progress_messages;
    std::array<u32, 2> m_values{0, 0};
    std::array<u32, 2> m_limits{100, 100};
    __strong UIAlertController* m_alert = nil;
    bool m_closed = false;
};

class ios_osk_dialog final
    : public OskDialogBase
    , public std::enable_shared_from_this<ios_osk_dialog>
{
public:
    void Create(const osk_params& params) override
    {
        {
            std::lock_guard lock(m_mutex);
            m_params = params;
            m_finished = false;
            std::fill(osk_text.begin(), osk_text.end(), u'\0');
            if (params.init_text)
            {
                const u32 maximum = std::min<u32>(params.charlimit ? params.charlimit : CELL_OSKDIALOG_STRING_SIZE - 1,
                    CELL_OSKDIALOG_STRING_SIZE - 1);
                for (u32 index = 0; index < maximum && params.init_text[index]; ++index)
                {
                    osk_text[index] = params.init_text[index];
                }
            }
        }
        state = OskDialogState::Open;

        const std::shared_ptr<ios_osk_dialog> self = shared_from_this();
        run_on_main_async(^{
            UIViewController* presenter = top_view_controller();
            if (!presenter)
            {
                self->Close(FAKE_CELL_OSKDIALOG_CLOSE_ABORT);
                return;
            }

            UIAlertController* alert = [UIAlertController alertControllerWithTitle:ns_utf8(self->m_params.title)
                message:ns_utf16(self->m_params.message)
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField* field) {
                field.text = self->current_text();
                field.clearButtonMode = UITextFieldViewModeWhileEditing;
                const u32 panels = self->m_params.panel_flag;
                field.secureTextEntry = (panels & CELL_OSKDIALOG_PANELMODE_PASSWORD) != 0;
                if ((panels & CELL_OSKDIALOG_PANELMODE_NUMERAL) != 0 ||
                    (panels & CELL_OSKDIALOG_PANELMODE_NUMERAL_FULL_WIDTH) != 0)
                {
                    field.keyboardType = UIKeyboardTypeNumberPad;
                }
                else if ((panels & CELL_OSKDIALOG_PANELMODE_URL) != 0)
                {
                    field.keyboardType = UIKeyboardTypeURL;
                }
                self->m_field = field;
            }];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) {
                self->Close(CELL_OSKDIALOG_CLOSE_CANCEL);
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
                self->store_text(self->m_field.text ?: @"");
                self->Close(CELL_OSKDIALOG_CLOSE_CONFIRM);
            }]];

            {
                std::lock_guard lock(self->m_mutex);
                self->m_alert = alert;
            }
            [presenter presentViewController:alert animated:YES completion:nil];
        });
    }

    void Clear(bool clear_all_data) override
    {
        (void)clear_all_data;
        SetText({});
    }

    void Insert(const std::u16string& text) override
    {
        std::u16string combined;
        {
            std::lock_guard lock(m_mutex);
            combined.assign(osk_text.data());
        }
        combined += text;
        SetText(combined);
    }

    void SetText(const std::u16string& text) override
    {
        {
            std::lock_guard lock(m_mutex);
            std::fill(osk_text.begin(), osk_text.end(), u'\0');
            const usz count = std::min<usz>(text.size(), CELL_OSKDIALOG_STRING_SIZE - 1);
            std::copy_n(text.data(), count, osk_text.data());
        }
        const std::shared_ptr<ios_osk_dialog> self = shared_from_this();
        run_on_main_async(^{ self->m_field.text = self->current_text(); });
    }

    void Close(s32 status) override
    {
        std::function<void(s32)> callback;
        __strong UIAlertController* alert = nil;
        {
            std::lock_guard lock(m_mutex);
            if (m_finished)
            {
                return;
            }
            m_finished = true;
            callback = on_osk_close;
            alert = m_alert;
            m_alert = nil;
            m_field = nil;
        }

        if (status == CELL_OSKDIALOG_CLOSE_CONFIRM)
        {
            osk_input_result = CELL_OSKDIALOG_INPUT_FIELD_RESULT_OK;
        }
        else if (status == CELL_OSKDIALOG_CLOSE_CANCEL)
        {
            osk_input_result = CELL_OSKDIALOG_INPUT_FIELD_RESULT_CANCELED;
        }
        else
        {
            osk_input_result = CELL_OSKDIALOG_INPUT_FIELD_RESULT_ABORT;
        }
        state = OskDialogState::Closed;

        run_on_main_async(^{
            [alert dismissViewControllerAnimated:YES completion:nil];
            if (callback)
            {
                callback(status);
            }
        });
    }

private:
    NSString* current_text()
    {
        std::lock_guard lock(m_mutex);
        usz length = 0;
        while (length < osk_text.size() && osk_text[length])
        {
            ++length;
        }
        return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(osk_text.data())
                                             length:length] ?: @"";
    }

    void store_text(NSString* text)
    {
        std::u16string value = utf16_string(text);
        const u32 limit = m_params.charlimit
            ? std::min<u32>(m_params.charlimit, CELL_OSKDIALOG_STRING_SIZE - 1)
            : CELL_OSKDIALOG_STRING_SIZE - 1;
        if (value.size() > limit)
        {
            value.resize(limit);
        }
        {
            std::lock_guard lock(m_mutex);
            std::fill(osk_text.begin(), osk_text.end(), u'\0');
            std::copy(value.begin(), value.end(), osk_text.begin());
        }
    }

    std::mutex m_mutex;
    osk_params m_params{};
    __strong UIAlertController* m_alert = nil;
    __strong UITextField* m_field = nil;
    bool m_finished = false;
};

class ios_save_dialog final : public SaveDialogBase
{
public:
    s32 ShowSaveDataList(
        const std::string& base_dir,
        std::vector<SaveDataEntry>& save_entries,
        s32 focused,
        u32 op,
        vm::ptr<CellSaveDataListSet> list_set,
        bool enable_overlay) override
    {
        (void)base_dir;
        (void)op;
        (void)list_set;
        (void)enable_overlay;
        if (save_entries.empty())
        {
            return -1;
        }

        const s32 fallback = focused >= 0 && static_cast<usz>(focused) < save_entries.size() ? focused : 0;
        if (NSThread.isMainThread)
        {
            return fallback;
        }

        __block s32 selection = fallback;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController* presenter = top_view_controller();
            if (!presenter)
            {
                dispatch_semaphore_signal(semaphore);
                return;
            }

            UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"Select Save Data"
                message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];
            for (usz index = 0; index < save_entries.size(); ++index)
            {
                const SaveDataEntry& entry = save_entries[index];
                NSString* title = entry.title.empty() ? ns_utf8(entry.dirName) : ns_utf8(entry.title);
                [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
                    selection = static_cast<s32>(index);
                    dispatch_semaphore_signal(semaphore);
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) {
                selection = -1;
                dispatch_semaphore_signal(semaphore);
            }]];
            sheet.popoverPresentationController.sourceView = presenter.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
            [presenter presentViewController:sheet animated:YES completion:nil];
        });
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return selection;
    }
};

class ios_trophy_notification final : public TrophyNotificationBase
{
public:
    s32 ShowTrophyNotification(const SceNpTrophyDetails& trophy, const std::vector<uchar>& trophy_icon) override
    {
        (void)trophy_icon;
        const std::string name(trophy.name, strnlen(trophy.name, sizeof(trophy.name)));
        const std::string description(trophy.description, strnlen(trophy.description, sizeof(trophy.description)));
        run_on_main_async(^{
            UIViewController* presenter = top_view_controller();
            if (!presenter)
            {
                return;
            }
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:
                [NSString stringWithFormat:@"Trophy Unlocked — %@", ns_utf8(name)]
                message:ns_utf8(description)
                preferredStyle:UIAlertControllerStyleAlert];
            [presenter presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        });
        return 0;
    }
};

bool image_info(const std::string& filename, std::string& subtype, s32& width, s32& height, s32& orientation)
{
    subtype.clear();
    width = 0;
    height = 0;
    orientation = 0;

    NSURL* url = [NSURL fileURLWithPath:ns_utf8(filename)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source)
    {
        return false;
    }

    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr);
    if (properties)
    {
        NSNumber* pixel_width = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
        NSNumber* pixel_height = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
        NSNumber* image_orientation = (__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
        width = pixel_width.intValue;
        height = pixel_height.intValue;
        orientation = image_orientation ? image_orientation.intValue : 1;
        CFRelease(properties);
    }

    CFStringRef type = CGImageSourceGetType(source);
    if (type)
    {
        subtype = [(__bridge NSString*)type UTF8String] ?: "";
    }
    CFRelease(source);
    return width > 0 && height > 0;
}

bool scaled_image(
    const std::string& path,
    s32 target_width,
    s32 target_height,
    s32& width,
    s32& height,
    u8* destination,
    bool force_fit)
{
    width = 0;
    height = 0;
    if (target_width <= 0 || target_height <= 0 || !destination)
    {
        return false;
    }

    NSURL* url = [NSURL fileURLWithPath:ns_utf8(path)];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!source)
    {
        return false;
    }

    s32 source_width = 0;
    s32 source_height = 0;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr);
    if (properties)
    {
        source_width = [(__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth) intValue];
        source_height = [(__bridge NSNumber*)CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight) intValue];
        CFRelease(properties);
    }
    if (source_width <= 0 || source_height <= 0)
    {
        CFRelease(source);
        return false;
    }

    const double ratio = std::min(
        target_width / static_cast<double>(source_width),
        target_height / static_cast<double>(source_height));
    const double applied_ratio = force_fit ? ratio : std::min(ratio, 1.0);
    width = std::max<s32>(1, static_cast<s32>(source_width * applied_ratio));
    height = std::max<s32>(1, static_cast<s32>(source_height * applied_ratio));

    NSDictionary* options = @{
        (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize: @(std::max(width, height)),
        (__bridge NSString*)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!image)
    {
        return false;
    }

    width = static_cast<s32>(CGImageGetWidth(image));
    height = static_cast<s32>(CGImageGetHeight(image));
    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        destination,
        width,
        height,
        8,
        static_cast<size_t>(width) * 4,
        color_space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color_space);
    if (!context)
    {
        CGImageRelease(image);
        return false;
    }

    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    // Convert CoreGraphics' premultiplied RGBA output to the straight RGBA8888
    // layout expected by RPCS3's image callback contract.
    const usz pixels = static_cast<usz>(width) * static_cast<usz>(height);
    for (usz index = 0; index < pixels; ++index)
    {
        u8* pixel = destination + index * 4;
        const u32 alpha = pixel[3];
        if (alpha > 0 && alpha < 255)
        {
            pixel[0] = static_cast<u8>(std::min<u32>((pixel[0] * 255u + alpha / 2u) / alpha, 255));
            pixel[1] = static_cast<u8>(std::min<u32>((pixel[1] * 255u + alpha / 2u) / alpha, 255));
            pixel[2] = static_cast<u8>(std::min<u32>((pixel[2] * 255u + alpha / 2u) / alpha, 255));
        }
    }
    return true;
}
}

namespace rpcs3::ios
{
void extend_core_callbacks(EmuCallbacks& callbacks)
{
    callbacks.get_msg_dialog = []() -> std::shared_ptr<MsgDialogBase>
    {
        return std::make_shared<ios_msg_dialog>();
    };
    callbacks.get_osk_dialog = []() -> std::shared_ptr<OskDialogBase>
    {
        return std::make_shared<ios_osk_dialog>();
    };
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase>
    {
        return std::make_unique<ios_save_dialog>();
    };
    callbacks.get_trophy_notification_dialog = []() -> std::unique_ptr<TrophyNotificationBase>
    {
        return std::make_unique<ios_trophy_notification>();
    };
    callbacks.get_image_info = image_info;
    callbacks.get_scaled_image = scaled_image;
}
}
