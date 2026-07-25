#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3Core.h"

#include <algorithm>
#include <string>
#include <utility>
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

std::pair<std::string, std::string> copy_library_game(size_t index)
{
    size_t title_required = 0;
    size_t path_required = 0;
    const rpcs3_ios_core_result first = rpcs3_ios_core_copy_game(
        index, nullptr, 0, &title_required, nullptr, 0, &path_required);
    if (first != RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {};
    }

    std::vector<char> title(title_required > 0 ? title_required : 1);
    std::vector<char> path(path_required > 0 ? path_required : 1);
    if (rpcs3_ios_core_copy_game(
            index,
            title.data(), title.size(), &title_required,
            path.data(), path.size(), &path_required) != RPCS3_IOS_CORE_SUCCESS)
    {
        return {};
    }
    return {title.data(), path.data()};
}
}

@interface RPCS3CoreMetalView : UIView
@end

@implementation RPCS3CoreMetalView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    self.backgroundColor = UIColor.blackColor;
    self.clipsToBounds = YES;
    CAMetalLayer* layer = (CAMetalLayer*)self.layer;
    layer.framebufferOnly = NO;
    layer.opaque = YES;
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CAMetalLayer* layer = (CAMetalLayer*)self.layer;
    UIScreen* screen = self.window.screen ?: UIScreen.mainScreen;
    const CGFloat scale = std::max<CGFloat>(screen.nativeScale, 1.0);
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(
        std::max<CGFloat>(self.bounds.size.width * scale, 1.0),
        std::max<CGFloat>(self.bounds.size.height * scale, 1.0));
    rpcs3_ios_core_refresh_render_view();
}
@end

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

static void installation_progress_callback(
    rpcs3_ios_installation_kind kind,
    rpcs3_ios_installation_stage stage,
    uint32_t completed,
    uint32_t total,
    const char* detail,
    void* context)
{
    RPCS3CoreLinkViewController* controller = (__bridge RPCS3CoreLinkViewController*)context;
    NSString* detail_string = detail ? [NSString stringWithUTF8String:detail] : @"";
    [controller performSelectorOnMainThread:@selector(handleInstallationProgress:)
                                withObject:@{
                                    @"kind": @(kind),
                                    @"stage": @(stage),
                                    @"completed": @(completed),
                                    @"total": @(total),
                                    @"detail": detail_string ?: @"",
                                }
                             waitUntilDone:NO];
}

typedef NS_ENUM(NSInteger, RPCS3PickerPurpose)
{
    RPCS3PickerPurposeBoot,
    RPCS3PickerPurposeFirmware,
    RPCS3PickerPurposePackage,
    RPCS3PickerPurposeGameDirectory,
};

@interface RPCS3CoreLinkViewController : UIViewController <UIDocumentPickerDelegate>
- (void)handleCoreEvent:(NSDictionary*)payload;
- (void)handleInstallationProgress:(NSDictionary*)payload;
@end

@implementation RPCS3CoreLinkViewController
{
    RPCS3CoreMetalView* _metalView;
    UILabel* _status;
    UILabel* _eventStatus;
    UILabel* _libraryStatus;
    UILabel* _installationStatus;
    UIProgressView* _installationProgress;

    UIButton* _importButton;
    UIButton* _firmwareButton;
    UIButton* _packageButton;
    UIButton* _addDirectoryButton;
    UIButton* _bootLibraryButton;
    UIButton* _removeLibraryButton;
    UIButton* _pauseButton;
    UIButton* _resumeButton;
    UIButton* _stopButton;
    UIButton* _cancelOperationButton;
    UIButton* _saveSettingsButton;

    UISegmentedControl* _cpuMode;
    UISwitch* _audioEnabled;
    UISlider* _audioVolume;
    UILabel* _audioVolumeLabel;
    UISegmentedControl* _resolutionScale;
    UISegmentedControl* _frameLimit;
    UISwitch* _shaderCache;
    UISwitch* _performanceOverlay;
    UIStepper* _spuThreads;
    UILabel* _spuThreadsLabel;

    RPCS3PickerPurpose _pickerPurpose;
    dispatch_queue_t _operationQueue;
    BOOL _operationActive;
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

- (UILabel*)sectionLabel:(NSString*)text
{
    UILabel* label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.text = text;
    return label;
}

- (UIStackView*)rowWithTitle:(NSString*)title control:(UIView*)control
{
    UILabel* label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12.0;
    return row;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _operationQueue = dispatch_queue_create("net.rpcs3.ios.core.operations", DISPATCH_QUEUE_SERIAL);

    UILabel* title = [[UILabel alloc] init];
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"RPCS3Core.framework";

    UILabel* explanation = [[UILabel alloc] init];
    explanation.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    explanation.textAlignment = NSTextAlignmentCenter;
    explanation.numberOfLines = 0;
    explanation.textColor = UIColor.secondaryLabelColor;
    explanation.text = @"Native Qt-free RPCS3Core host. It supplies a CAMetalLayer, manages legal local firmware/content, persists mobile-safe settings, and drives the public emulator lifecycle. Apple compilation and workload compatibility still require external validation.";

    _metalView = [[RPCS3CoreMetalView alloc] init];
    _metalView.translatesAutoresizingMaskIntoConstraints = NO;
    _metalView.layer.cornerRadius = 10.0;

    _status = [[UILabel alloc] init];
    _status.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    _status.numberOfLines = 0;

    _eventStatus = [[UILabel alloc] init];
    _eventStatus.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _eventStatus.numberOfLines = 0;
    _eventStatus.textColor = UIColor.secondaryLabelColor;
    _eventStatus.text = @"No emulator event received yet.";

    _libraryStatus = [[UILabel alloc] init];
    _libraryStatus.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _libraryStatus.numberOfLines = 0;

    _installationStatus = [[UILabel alloc] init];
    _installationStatus.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _installationStatus.numberOfLines = 0;
    _installationStatus.text = @"No installation operation is active.";

    _installationProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _installationProgress.progress = 0.0f;

    _importButton = [self buttonWithTitle:@"Import and Boot Content" action:@selector(importAndBoot:) prominent:YES];
    _firmwareButton = [self buttonWithTitle:@"Install PS3 Firmware" action:@selector(chooseFirmware:) prominent:NO];
    _packageButton = [self buttonWithTitle:@"Install PKG" action:@selector(choosePackage:) prominent:NO];
    _addDirectoryButton = [self buttonWithTitle:@"Add Game Directory" action:@selector(addGameDirectory:) prominent:NO];
    _bootLibraryButton = [self buttonWithTitle:@"Boot Library Game" action:@selector(bootLibraryGame:) prominent:NO];
    _removeLibraryButton = [self buttonWithTitle:@"Remove Library Entry" action:@selector(removeLibraryGame:) prominent:NO];
    _cancelOperationButton = [self buttonWithTitle:@"Cancel Installation" action:@selector(cancelInstallation:) prominent:NO];
    _pauseButton = [self buttonWithTitle:@"Pause" action:@selector(pauseCore:) prominent:NO];
    _resumeButton = [self buttonWithTitle:@"Resume" action:@selector(resumeCore:) prominent:NO];
    _stopButton = [self buttonWithTitle:@"Stop" action:@selector(stopCore:) prominent:NO];

    _cpuMode = [[UISegmentedControl alloc] initWithItems:@[@"Portable", @"PPU LLVM", @"Full LLVM"]];
    _audioEnabled = [[UISwitch alloc] init];
    _audioVolume = [[UISlider alloc] init];
    _audioVolume.minimumValue = 0.0f;
    _audioVolume.maximumValue = 200.0f;
    [_audioVolume addTarget:self action:@selector(volumeChanged:) forControlEvents:UIControlEventValueChanged];
    _audioVolumeLabel = [[UILabel alloc] init];
    _audioVolumeLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    _audioVolumeLabel.textAlignment = NSTextAlignmentRight;
    [_audioVolumeLabel.widthAnchor constraintEqualToConstant:52.0].active = YES;

    UIStackView* volumeControl = [[UIStackView alloc] initWithArrangedSubviews:@[_audioVolume, _audioVolumeLabel]];
    volumeControl.axis = UILayoutConstraintAxisHorizontal;
    volumeControl.spacing = 8.0;
    [_audioVolume.widthAnchor constraintGreaterThanOrEqualToConstant:130.0].active = YES;

    _resolutionScale = [[UISegmentedControl alloc] initWithItems:@[@"50%", @"75%", @"100%", @"150%", @"200%"]];
    _frameLimit = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"30", @"60", @"120", @"Display"]];
    _shaderCache = [[UISwitch alloc] init];
    _performanceOverlay = [[UISwitch alloc] init];
    _spuThreads = [[UIStepper alloc] init];
    _spuThreads.minimumValue = 0;
    _spuThreads.maximumValue = 6;
    _spuThreads.stepValue = 1;
    [_spuThreads addTarget:self action:@selector(spuThreadsChanged:) forControlEvents:UIControlEventValueChanged];
    _spuThreadsLabel = [[UILabel alloc] init];
    _spuThreadsLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightRegular];

    UIStackView* spuControl = [[UIStackView alloc] initWithArrangedSubviews:@[_spuThreadsLabel, _spuThreads]];
    spuControl.axis = UILayoutConstraintAxisHorizontal;
    spuControl.spacing = 8.0;

    _saveSettingsButton = [self buttonWithTitle:@"Save Core Settings" action:@selector(saveSettings:) prominent:NO];

    UIStackView* lifecycleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_pauseButton, _resumeButton, _stopButton]];
    lifecycleRow.axis = UILayoutConstraintAxisHorizontal;
    lifecycleRow.distribution = UIStackViewDistributionFillEqually;
    lifecycleRow.spacing = 8.0;

    UIStackView* installRow = [[UIStackView alloc] initWithArrangedSubviews:@[_firmwareButton, _packageButton]];
    installRow.axis = UILayoutConstraintAxisHorizontal;
    installRow.distribution = UIStackViewDistributionFillEqually;
    installRow.spacing = 8.0;

    UIStackView* libraryRow = [[UIStackView alloc] initWithArrangedSubviews:@[_bootLibraryButton, _removeLibraryButton]];
    libraryRow.axis = UILayoutConstraintAxisHorizontal;
    libraryRow.distribution = UIStackViewDistributionFillEqually;
    libraryRow.spacing = 8.0;

    UIButton* shareDiagnostics = [self buttonWithTitle:@"Share Diagnostics" action:@selector(shareDiagnostics:) prominent:NO];

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title,
        explanation,
        _metalView,
        _status,
        _importButton,
        lifecycleRow,
        [self sectionLabel:@"Firmware and Packages"],
        installRow,
        _cancelOperationButton,
        _installationProgress,
        _installationStatus,
        [self sectionLabel:@"Game Library"],
        _addDirectoryButton,
        libraryRow,
        _libraryStatus,
        [self sectionLabel:@"Mobile-safe Core Settings"],
        [self rowWithTitle:@"CPU mode" control:_cpuMode],
        [self rowWithTitle:@"Audio" control:_audioEnabled],
        [self rowWithTitle:@"Volume" control:volumeControl],
        [self rowWithTitle:@"Resolution scale" control:_resolutionScale],
        [self rowWithTitle:@"Frame limit" control:_frameLimit],
        [self rowWithTitle:@"Shader cache" control:_shaderCache],
        [self rowWithTitle:@"Performance overlay" control:_performanceOverlay],
        [self rowWithTitle:@"Preferred SPU threads" control:spuControl],
        _saveSettingsButton,
        [self sectionLabel:@"Events and Diagnostics"],
        _eventStatus,
        shareDiagnostics,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 14.0;

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
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40.0],
        [_metalView.heightAnchor constraintEqualToAnchor:_metalView.widthAnchor multiplier:9.0 / 16.0],
    ]];

    const rpcs3_ios_core_result renderResult = rpcs3_ios_core_set_render_view((__bridge void*)_metalView);
    if (renderResult != RPCS3_IOS_CORE_SUCCESS)
    {
        _eventStatus.text = [NSString stringWithFormat:@"Render host failed: %@",
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    }

    rpcs3_ios_core_set_event_callback(core_event_callback, (__bridge void*)self);
    [self loadSettingsControls];
    [self refreshStatus];
}

- (void)dealloc
{
    rpcs3_ios_core_set_event_callback(nullptr, nullptr);
    rpcs3_ios_core_request_installation_cancel();
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    rpcs3_ios_core_refresh_render_view();
}

- (void)setOperationActive:(BOOL)active
{
    _operationActive = active;
    [self refreshStatus];
}

- (void)refreshStatus
{
    const rpcs3_ios_jit_status jit = rpcs3_ios_core_query_jit_status();
    const rpcs3_ios_performance_status performance = rpcs3_ios_core_query_performance_status();
    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    const std::string title = copy_core_string(rpcs3_ios_core_copy_title);
    const std::string titleID = copy_core_string(rpcs3_ios_core_copy_title_id);
    const std::string bootPath = copy_core_string(rpcs3_ios_core_copy_boot_path);
    const std::string firmware = copy_core_string(rpcs3_ios_core_copy_firmware_version);
    const size_t gameCount = rpcs3_ios_core_game_count();
    const size_t directoryCount = rpcs3_ios_core_game_directory_count();

    _status.text = [NSString stringWithFormat:
        @"Initialized: %@\n"
         "State: %@\n"
         "Vulkan host: %@\n"
         "Firmware: %@\n"
         "Title: %@\n"
         "Title ID: %@\n"
         "Boot path: %@\n"
         "Imports: %s\n"
         "Available memory: %.2f GiB\n"
         "MAP_JIT allocation: %@",
        rpcs3_ios_core_is_initialized() ? @"yes" : @"no",
        state_name(state),
        rpcs3_ios_core_has_render_view() ? @"attached" : @"headless",
        firmware.empty() ? @"not installed" : ns_string(firmware),
        title.empty() ? @"—" : ns_string(title),
        titleID.empty() ? @"—" : ns_string(titleID),
        bootPath.empty() ? @"—" : ns_string(bootPath),
        rpcs3_ios_core_imports_path(),
        performance.available_memory / 1073741824.0,
        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable"];

    _libraryStatus.text = [NSString stringWithFormat:@"%zu game(s) across %zu registered director%@.",
        gameCount,
        directoryCount,
        directoryCount == 1 ? @"y" : @"ies"];

    const BOOL stopped = state == RPCS3_IOS_EMULATOR_STOPPED;
    _pauseButton.enabled = state == RPCS3_IOS_EMULATOR_RUNNING && !_operationActive;
    _resumeButton.enabled = state == RPCS3_IOS_EMULATOR_PAUSED && !_operationActive;
    _stopButton.enabled = state != RPCS3_IOS_EMULATOR_STOPPED && state != RPCS3_IOS_EMULATOR_UNAVAILABLE && !_operationActive;
    _importButton.enabled = stopped && !_operationActive;
    _firmwareButton.enabled = stopped && !_operationActive;
    _packageButton.enabled = stopped && !_operationActive;
    _addDirectoryButton.enabled = stopped && !_operationActive;
    _bootLibraryButton.enabled = stopped && gameCount > 0 && !_operationActive;
    _removeLibraryButton.enabled = stopped && gameCount > 0 && !_operationActive;
    _cancelOperationButton.enabled = _operationActive;
    _saveSettingsButton.enabled = stopped && !_operationActive;
    _cpuMode.enabled = stopped && !_operationActive;
    _audioEnabled.enabled = stopped && !_operationActive;
    _audioVolume.enabled = stopped && !_operationActive;
    _resolutionScale.enabled = stopped && !_operationActive;
    _frameLimit.enabled = stopped && !_operationActive;
    _shaderCache.enabled = stopped && !_operationActive;
    _performanceOverlay.enabled = stopped && !_operationActive;
    _spuThreads.enabled = stopped && !_operationActive;
}

- (void)handleCoreEvent:(NSDictionary*)payload
{
    const rpcs3_ios_core_event event = (rpcs3_ios_core_event)[payload[@"event"] unsignedIntValue];
    NSString* detail = payload[@"detail"];
    _eventStatus.text = detail.length > 0
        ? [NSString stringWithFormat:@"Event: %@ — %@", event_name(event), detail]
        : [NSString stringWithFormat:@"Event: %@", event_name(event)];
    [self refreshStatus];
}

- (void)handleInstallationProgress:(NSDictionary*)payload
{
    const uint32_t completed = [payload[@"completed"] unsignedIntValue];
    const uint32_t total = [payload[@"total"] unsignedIntValue];
    NSString* detail = payload[@"detail"];
    _installationProgress.progress = total > 0 ? (float)completed / (float)total : 0.0f;
    _installationStatus.text = [NSString stringWithFormat:@"%@ (%u/%u)", detail, completed, total];
}

- (void)presentPickerForPurpose:(RPCS3PickerPurpose)purpose types:(NSArray<UTType*>*)types
{
    _pickerPurpose = purpose;
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types
        asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importAndBoot:(UIButton*)sender
{
    (void)sender;
    [self presentPickerForPurpose:RPCS3PickerPurposeBoot types:@[UTTypeData, UTTypeFolder]];
}

- (void)chooseFirmware:(UIButton*)sender
{
    (void)sender;
    [self presentPickerForPurpose:RPCS3PickerPurposeFirmware types:@[UTTypeData]];
}

- (void)choosePackage:(UIButton*)sender
{
    (void)sender;
    [self presentPickerForPurpose:RPCS3PickerPurposePackage types:@[UTTypeData]];
}

- (void)addGameDirectory:(UIButton*)sender
{
    (void)sender;
    [self presentPickerForPurpose:RPCS3PickerPurposeGameDirectory types:@[UTTypeFolder]];
}

- (std::string)importURL:(NSURL*)url result:(rpcs3_ios_core_result*)result
{
    const BOOL scoped = [url startAccessingSecurityScopedResource];
    size_t required = 0;
    rpcs3_ios_core_result importResult = rpcs3_ios_core_import_path(
        url.fileSystemRepresentation, nullptr, 0, &required);

    std::vector<char> imported(required > 0 ? required : 1);
    if (importResult == RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        importResult = rpcs3_ios_core_import_path(
            url.fileSystemRepresentation,
            imported.data(), imported.size(), &required);
    }
    if (scoped)
    {
        [url stopAccessingSecurityScopedResource];
    }
    if (result)
    {
        *result = importResult;
    }
    return importResult == RPCS3_IOS_CORE_SUCCESS ? std::string(imported.data()) : std::string{};
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    NSURL* url = urls.firstObject;
    if (!url.fileURL)
    {
        _eventStatus.text = @"The selected item does not have a local file URL.";
        return;
    }

    rpcs3_ios_core_result importResult = RPCS3_IOS_CORE_PLATFORM_ERROR;
    const std::string imported = [self importURL:url result:&importResult];
    if (importResult != RPCS3_IOS_CORE_SUCCESS)
    {
        _eventStatus.text = [NSString stringWithFormat:@"Import failed: %@",
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        return;
    }

    switch (_pickerPurpose)
    {
    case RPCS3PickerPurposeBoot:
    {
        const rpcs3_ios_boot_result result = rpcs3_ios_core_boot_path(imported.c_str(), 1);
        _eventStatus.text = result == RPCS3_IOS_BOOT_SUCCESS
            ? [NSString stringWithFormat:@"Boot accepted: %@", url.lastPathComponent]
            : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)result,
                ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [self refreshStatus];
        break;
    }
    case RPCS3PickerPurposeFirmware:
        [self confirmFirmwareInstallation:imported displayName:url.lastPathComponent];
        break;
    case RPCS3PickerPurposePackage:
        [self confirmPackageInstallation:imported displayName:url.lastPathComponent];
        break;
    case RPCS3PickerPurposeGameDirectory:
    {
        uint32_t added = 0;
        const rpcs3_ios_core_result result = rpcs3_ios_core_add_game_directory(imported.c_str(), &added);
        _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
            ? [NSString stringWithFormat:@"Added %u game(s) from %@.", added, url.lastPathComponent]
            : [NSString stringWithFormat:@"Library scan failed: %@",
                ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [self refreshStatus];
        break;
    }
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
    (void)controller;
    _eventStatus.text = @"Document selection cancelled.";
}

- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PS3 Firmware"
        message:[NSString stringWithFormat:@"Validate and install %@? Existing firmware may be replaced, but downgrades are rejected.", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install or Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weakSelf runInstallation:RPCS3_IOS_INSTALLATION_FIRMWARE path:path];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PKG"
        message:[NSString stringWithFormat:@"Validate and install %@ into RPCS3's virtual HDD?", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weakSelf runInstallation:RPCS3_IOS_INSTALLATION_PACKAGE path:path];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runInstallation:(rpcs3_ios_installation_kind)kind path:(std::string)path
{
    if (_operationActive)
    {
        return;
    }

    [self setOperationActive:YES];
    _installationProgress.progress = 0.0f;
    _installationStatus.text = kind == RPCS3_IOS_INSTALLATION_FIRMWARE
        ? @"Preparing firmware installation…"
        : @"Preparing package installation…";

    __strong RPCS3CoreLinkViewController* strongSelf = self;
    dispatch_async(_operationQueue, ^{
        const rpcs3_ios_core_result result = kind == RPCS3_IOS_INSTALLATION_FIRMWARE
            ? rpcs3_ios_core_install_firmware(path.c_str(), 0, 1, installation_progress_callback, (__bridge void*)strongSelf)
            : rpcs3_ios_core_install_package(path.c_str(), installation_progress_callback, (__bridge void*)strongSelf);
        const std::string error = copy_core_string(rpcs3_ios_core_copy_last_error);

        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf->_operationActive = NO;
            if (result == RPCS3_IOS_CORE_SUCCESS)
            {
                strongSelf->_installationProgress.progress = 1.0f;
                const std::string installed = copy_core_string(rpcs3_ios_core_copy_last_installed_path);
                strongSelf->_installationStatus.text = installed.empty()
                    ? @"Installation completed."
                    : [NSString stringWithFormat:@"Installation completed: %@", ns_string(installed)];
            }
            else
            {
                strongSelf->_installationStatus.text = [NSString stringWithFormat:@"Installation returned %u: %@",
                    (unsigned int)result,
                    error.empty() ? @"No error detail." : ns_string(error)];
            }
            [strongSelf refreshStatus];
        });
    });
}

- (void)cancelInstallation:(UIButton*)sender
{
    (void)sender;
    rpcs3_ios_core_request_installation_cancel();
    _installationStatus.text = @"Cancellation requested…";
}

- (void)presentGameActionSheetWithTitle:(NSString*)title destructive:(BOOL)destructive
{
    const size_t count = rpcs3_ios_core_game_count();
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:title
        message:count > 0 ? nil : @"The game library is empty."
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (size_t index = 0; index < count; ++index)
    {
        const auto [titleID, path] = copy_library_game(index);
        if (path.empty())
        {
            continue;
        }

        NSString* name = titleID.empty()
            ? [ns_string(path) lastPathComponent]
            : ns_string(titleID);
        __weak RPCS3CoreLinkViewController* weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:name
            style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
            handler:^(UIAlertAction*) {
                if (destructive)
                {
                    const rpcs3_ios_core_result result = rpcs3_ios_core_remove_game(titleID.c_str());
                    weakSelf->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
                        ? [NSString stringWithFormat:@"Removed %@ from the library.", name]
                        : [NSString stringWithFormat:@"Remove failed: %@",
                            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
                }
                else
                {
                    const rpcs3_ios_boot_result result = rpcs3_ios_core_boot_path(path.c_str(), 1);
                    weakSelf->_eventStatus.text = result == RPCS3_IOS_BOOT_SUCCESS
                        ? [NSString stringWithFormat:@"Boot accepted: %@", name]
                        : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)result,
                            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
                }
                [weakSelf refreshStatus];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController* popover = sheet.popoverPresentationController;
    popover.sourceView = destructive ? _removeLibraryButton : _bootLibraryButton;
    popover.sourceRect = popover.sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)bootLibraryGame:(UIButton*)sender
{
    (void)sender;
    [self presentGameActionSheetWithTitle:@"Boot Library Game" destructive:NO];
}

- (void)removeLibraryGame:(UIButton*)sender
{
    (void)sender;
    [self presentGameActionSheetWithTitle:@"Remove Library Entry" destructive:YES];
}

- (void)loadSettingsControls
{
    rpcs3_ios_configuration configuration{};
    configuration.struct_size = sizeof(configuration);
    if (rpcs3_ios_core_get_configuration(&configuration) != RPCS3_IOS_CORE_SUCCESS)
    {
        return;
    }

    _cpuMode.selectedSegmentIndex = std::min<uint32_t>(configuration.cpu_mode, 2);
    _audioEnabled.on = configuration.audio_enabled != 0;
    _audioVolume.value = configuration.audio_volume;
    [self volumeChanged:_audioVolume];

    static constexpr uint32_t scales[] = {50, 75, 100, 150, 200};
    NSInteger scaleIndex = 2;
    uint32_t closestDistance = UINT32_MAX;
    for (NSInteger index = 0; index < 5; ++index)
    {
        const uint32_t distance = scales[index] > configuration.resolution_scale_percent
            ? scales[index] - configuration.resolution_scale_percent
            : configuration.resolution_scale_percent - scales[index];
        if (distance < closestDistance)
        {
            closestDistance = distance;
            scaleIndex = index;
        }
    }
    _resolutionScale.selectedSegmentIndex = scaleIndex;
    _frameLimit.selectedSegmentIndex = std::min<uint32_t>(configuration.frame_limit, 4);
    _shaderCache.on = configuration.shader_cache_enabled != 0;
    _performanceOverlay.on = configuration.performance_overlay_enabled != 0;
    _spuThreads.value = std::min<uint32_t>(configuration.preferred_spu_threads, 6);
    [self spuThreadsChanged:_spuThreads];
}

- (void)volumeChanged:(UISlider*)slider
{
    _audioVolumeLabel.text = [NSString stringWithFormat:@"%u%%", (unsigned int)lroundf(slider.value)];
}

- (void)spuThreadsChanged:(UIStepper*)stepper
{
    _spuThreadsLabel.text = [NSString stringWithFormat:@"%u", (unsigned int)stepper.value];
}

- (void)saveSettings:(UIButton*)sender
{
    (void)sender;
    static constexpr uint32_t scales[] = {50, 75, 100, 150, 200};
    rpcs3_ios_configuration configuration{
        sizeof(rpcs3_ios_configuration),
        static_cast<uint32_t>(std::max<NSInteger>(_cpuMode.selectedSegmentIndex, 0)),
        _audioEnabled.on ? 1u : 0u,
        static_cast<uint32_t>(lroundf(_audioVolume.value)),
        scales[std::clamp<NSInteger>(_resolutionScale.selectedSegmentIndex, 0, 4)],
        static_cast<uint32_t>(std::max<NSInteger>(_frameLimit.selectedSegmentIndex, 0)),
        _shaderCache.on ? 1u : 0u,
        _performanceOverlay.on ? 1u : 0u,
        static_cast<uint32_t>(_spuThreads.value),
    };

    const rpcs3_ios_core_result result = rpcs3_ios_core_set_configuration(&configuration);
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? @"Core settings saved. They will be applied to the next boot."
        : [NSString stringWithFormat:@"Settings returned %u: %@", (unsigned int)result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self loadSettingsControls];
    [self refreshStatus];
}

- (void)shareDiagnostics:(UIButton*)sender
{
    const std::string diagnostics = copy_core_string(rpcs3_ios_core_copy_diagnostics);
    NSString* filename = [NSString stringWithFormat:@"RPCS3Core-Diagnostics-%@.txt", NSUUID.UUID.UUIDString];
    NSURL* url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    NSError* error = nil;
    if (![ns_string(diagnostics) writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error])
    {
        _eventStatus.text = [NSString stringWithFormat:@"Could not write diagnostics: %@", error.localizedDescription];
        return;
    }

    UIActivityViewController* activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = sender;
    activity.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)pauseCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_pause();
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? @"Pause accepted."
        : [NSString stringWithFormat:@"Pause returned %u: %@", (unsigned int)result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}

- (void)resumeCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_resume();
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? @"Resume accepted."
        : [NSString stringWithFormat:@"Resume returned %u: %@", (unsigned int)result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}

- (void)stopCore:(UIButton*)sender
{
    (void)sender;
    const rpcs3_ios_core_result result = rpcs3_ios_core_stop();
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? @"Stop accepted."
        : [NSString stringWithFormat:@"Stop returned %u: %@", (unsigned int)result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}
@end

@interface RPCS3CoreLinkAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RPCS3CoreLinkAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    (void)application;
    (void)launchOptions;

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
    rpcs3_ios_core_request_installation_cancel();
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
