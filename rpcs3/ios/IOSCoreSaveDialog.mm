#include "IOSCoreSaveDialog.h"

#import <UIKit/UIKit.h>

#include "Emu/System.h"
#include "Emu/Cell/Modules/cellSaveData.h"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

namespace
{
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

class ios_bounded_save_dialog final : public SaveDialogBase
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
            // RPCS3 may request a blocking chooser while already running on the
            // UIKit queue. Presenting and waiting there would deadlock, so use
            // the caller's focused item deterministically.
            return fallback;
        }

        NSMutableArray<NSString*>* titles = [NSMutableArray arrayWithCapacity:save_entries.size()];
        for (const SaveDataEntry& entry : save_entries)
        {
            [titles addObject:entry.title.empty() ? ns_utf8(entry.dirName) : ns_utf8(entry.title)];
        }
        NSArray<NSString*>* immutable_titles = [titles copy];

        __block s32 selection = fallback;
        __block UIAlertController* presented_sheet = nil;
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
            presented_sheet = sheet;
            [immutable_titles enumerateObjectsUsingBlock:^(NSString* title, NSUInteger index, BOOL*) {
                [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
                    selection = static_cast<s32>(index);
                    dispatch_semaphore_signal(semaphore);
                }]];
            }];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction*) {
                selection = -1;
                dispatch_semaphore_signal(semaphore);
            }]];
            sheet.popoverPresentationController.sourceView = presenter.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
            [presenter presentViewController:sheet animated:YES completion:nil];
        });

        constexpr int64_t timeout_seconds = 120;
        const long wait_result = dispatch_semaphore_wait(
            semaphore,
            dispatch_time(DISPATCH_TIME_NOW, timeout_seconds * NSEC_PER_SEC));
        if (wait_result != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [presented_sheet dismissViewControllerAnimated:YES completion:nil];
            });
            return fallback;
        }
        return selection;
    }
};
}

namespace rpcs3::ios
{
void extend_core_save_dialog_callback(EmuCallbacks& callbacks)
{
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase>
    {
        return std::make_unique<ios_bounded_save_dialog>();
    };
}
}
