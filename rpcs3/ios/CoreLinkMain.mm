#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3Core.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace
{
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

NSString* midi_type_name(uint32_t type)
{
    switch (type)
    {
    case RPCS3_IOS_MIDI_KEYBOARD: return @"Keyboard";
    case RPCS3_IOS_MIDI_GUITAR_17_FRET: return @"Guitar (17 frets)";
    case RPCS3_IOS_MIDI_GUITAR_22_FRET: return @"Guitar (22 frets)";
    case RPCS3_IOS_MIDI_DRUMS: return @"Drums";
    default: return @"Unknown";
    }
}

std::pair<std::string, std::string> copy_library_game(size_t index)
{
    size_t title_required = 0;
    size_t path_required = 0;
    if (rpcs3_ios_core_copy_game(index, nullptr, 0, &title_required, nullptr, 0, &path_required) !=
        RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {};
    }

    std::vector<char> title(std::max<size_t>(title_required, 1));
    std::vector<char> path(std::max<size_t>(path_required, 1));
    if (rpcs3_ios_core_copy_game(
            index,
            title.data(), title.size(), &title_required,
            path.data(), path.size(), &path_required) != RPCS3_IOS_CORE_SUCCESS)
    {
        return {};
    }
    return {title.data(), path.data()};
}

std::string copy_game_directory(size_t index)
{
    size_t required = 0;
    if (rpcs3_ios_core_copy_game_directory(index, nullptr, 0, &required) != RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {};
    }

    std::vector<char> buffer(std::max<size_t>(required, 1));
    return rpcs3_ios_core_copy_game_directory(index, buffer.data(), buffer.size(), &required) ==
        RPCS3_IOS_CORE_SUCCESS ? std::string(buffer.data()) : std::string{};
}

std::string copy_midi_source(size_t index)
{
    size_t required = 0;
    if (rpcs3_ios_core_copy_midi_source(index, nullptr, 0, &required) != RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {};
    }

    std::vector<char> buffer(std::max<size_t>(required, 1));
    return rpcs3_ios_core_copy_midi_source(index, buffer.data(), buffer.size(), &required) ==
        RPCS3_IOS_CORE_SUCCESS ? std::string(buffer.data()) : std::string{};
}

std::pair<uint32_t, std::string> copy_midi_assignment(uint32_t slot)
{
    uint32_t type = RPCS3_IOS_MIDI_KEYBOARD;
    size_t required = 0;
    if (rpcs3_ios_core_copy_midi_assignment(slot, &type, nullptr, 0, &required) !=
        RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        return {type, {}};
    }

    std::vector<char> buffer(std::max<size_t>(required, 1));
    if (rpcs3_ios_core_copy_midi_assignment(slot, &type, buffer.data(), buffer.size(), &required) !=
        RPCS3_IOS_CORE_SUCCESS)
    {
        return {type, {}};
    }
    return {type, buffer.data()};
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
    if (self)
    {
        self.backgroundColor = UIColor.blackColor;
        self.clipsToBounds = YES;
        CAMetalLayer* layer = (CAMetalLayer*)self.layer;
        layer.framebufferOnly = NO;
        layer.opaque = YES;
    }
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
                                withObject:@{@"event": @(event), @"detail": detail_string ?: @""}
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
                                    @"kind": @(kind), @"stage": @(stage),
                                    @"completed": @(completed), @"total": @(total),
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
    UILabel* _midiStatus;
    UILabel* _installationStatus;
    UIProgressView* _installationProgress;

    UIButton* _importButton;
    UIButton* _firmwareButton;
    UIButton* _packageButton;
    UIButton* _cancelOperationButton;
    UIButton* _addDirectoryButton;
    UIButton* _rescanDirectoriesButton;
    UIButton* _manageDirectoriesButton;
    UIButton* _bootLibraryButton;
    UIButton* _removeLibraryButton;
    UIButton* _configureMidiButton;
    UIButton* _pauseButton;
    UIButton* _resumeButton;
    UIButton* _stopButton;
    UIButton* _saveSettingsButton;
    UIButton* _resetSettingsButton;

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

- (UILabel*)detailLabel
{
    UILabel* label = [[UILabel alloc] init];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.numberOfLines = 0;
    label.textColor = UIColor.secondaryLabelColor;
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

- (UIStackView*)buttonRow:(NSArray<UIButton*>*)buttons
{
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8.0;
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
    title.text = @"RPCS3Core.framework 0.4";

    UILabel* explanation = [self detailLabel];
    explanation.textAlignment = NSTextAlignmentCenter;
    explanation.text = @"Qt-free native host for legal local firmware and content. It exercises the public renderer, lifecycle, installer, persistent library-root, settings, CoreMIDI, and diagnostics APIs. Apple compilation and workload compatibility remain external evidence gates.";

    _metalView = [[RPCS3CoreMetalView alloc] init];
    _metalView.translatesAutoresizingMaskIntoConstraints = NO;
    _metalView.layer.cornerRadius = 10.0;

    _status = [[UILabel alloc] init];
    _status.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    _status.numberOfLines = 0;
    _eventStatus = [self detailLabel];
    _eventStatus.text = @"No emulator event received yet.";
    _libraryStatus = [self detailLabel];
    _midiStatus = [self detailLabel];
    _installationStatus = [self detailLabel];
    _installationStatus.text = @"No installation operation is active.";
    _installationProgress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];

    _importButton = [self buttonWithTitle:@"Import and Boot Content" action:@selector(importAndBoot:) prominent:YES];
    _firmwareButton = [self buttonWithTitle:@"Install PS3 Firmware" action:@selector(chooseFirmware:) prominent:NO];
    _packageButton = [self buttonWithTitle:@"Install PKG" action:@selector(choosePackage:) prominent:NO];
    _cancelOperationButton = [self buttonWithTitle:@"Cancel Installation" action:@selector(cancelInstallation:) prominent:NO];
    _addDirectoryButton = [self buttonWithTitle:@"Add Game Directory" action:@selector(addGameDirectory:) prominent:NO];
    _rescanDirectoriesButton = [self buttonWithTitle:@"Rescan Roots" action:@selector(rescanDirectories:) prominent:NO];
    _manageDirectoriesButton = [self buttonWithTitle:@"Manage Roots" action:@selector(manageDirectories:) prominent:NO];
    _bootLibraryButton = [self buttonWithTitle:@"Boot Library Game" action:@selector(bootLibraryGame:) prominent:NO];
    _removeLibraryButton = [self buttonWithTitle:@"Remove Library Entry" action:@selector(removeLibraryGame:) prominent:NO];
    _configureMidiButton = [self buttonWithTitle:@"Configure CoreMIDI Adapters" action:@selector(configureMidi:) prominent:NO];
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
    [_audioVolumeLabel.widthAnchor constraintEqualToConstant:54.0].active = YES;
    UIStackView* volume = [[UIStackView alloc] initWithArrangedSubviews:@[_audioVolume, _audioVolumeLabel]];
    volume.axis = UILayoutConstraintAxisHorizontal;
    volume.spacing = 8.0;
    [_audioVolume.widthAnchor constraintGreaterThanOrEqualToConstant:130.0].active = YES;

    _resolutionScale = [[UISegmentedControl alloc] initWithItems:@[@"50%", @"75%", @"100%", @"150%", @"200%"]];
    _frameLimit = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"30", @"60", @"120", @"Display"]];
    _shaderCache = [[UISwitch alloc] init];
    _performanceOverlay = [[UISwitch alloc] init];
    _spuThreads = [[UIStepper alloc] init];
    _spuThreads.minimumValue = 0;
    _spuThreads.maximumValue = 6;
    [_spuThreads addTarget:self action:@selector(spuThreadsChanged:) forControlEvents:UIControlEventValueChanged];
    _spuThreadsLabel = [[UILabel alloc] init];
    _spuThreadsLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    UIStackView* spu = [[UIStackView alloc] initWithArrangedSubviews:@[_spuThreadsLabel, _spuThreads]];
    spu.axis = UILayoutConstraintAxisHorizontal;
    spu.spacing = 8.0;

    _saveSettingsButton = [self buttonWithTitle:@"Save Settings" action:@selector(saveSettings:) prominent:NO];
    _resetSettingsButton = [self buttonWithTitle:@"Reset Settings" action:@selector(resetSettings:) prominent:NO];
    UIButton* shareDiagnostics = [self buttonWithTitle:@"Share Diagnostics" action:@selector(shareDiagnostics:) prominent:NO];

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title,
        explanation,
        _metalView,
        _status,
        _importButton,
        [self buttonRow:@[_pauseButton, _resumeButton, _stopButton]],
        [self sectionLabel:@"Firmware and Packages"],
        [self buttonRow:@[_firmwareButton, _packageButton]],
        _cancelOperationButton,
        _installationProgress,
        _installationStatus,
        [self sectionLabel:@"Game Library"],
        _addDirectoryButton,
        [self buttonRow:@[_rescanDirectoriesButton, _manageDirectoriesButton]],
        [self buttonRow:@[_bootLibraryButton, _removeLibraryButton]],
        _libraryStatus,
        [self sectionLabel:@"CoreMIDI"],
        _configureMidiButton,
        _midiStatus,
        [self sectionLabel:@"Mobile-safe Core Settings"],
        [self rowWithTitle:@"CPU mode" control:_cpuMode],
        [self rowWithTitle:@"Audio" control:_audioEnabled],
        [self rowWithTitle:@"Volume" control:volume],
        [self rowWithTitle:@"Resolution scale" control:_resolutionScale],
        [self rowWithTitle:@"Frame limit" control:_frameLimit],
        [self rowWithTitle:@"Shader cache" control:_shaderCache],
        [self rowWithTitle:@"Performance overlay" control:_performanceOverlay],
        [self rowWithTitle:@"Preferred SPU threads" control:spu],
        [self buttonRow:@[_saveSettingsButton, _resetSettingsButton]],
        [self sectionLabel:@"Events and Diagnostics"],
        _eventStatus,
        shareDiagnostics,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
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

    const rpcs3_ios_core_result render_result = rpcs3_ios_core_set_render_view((__bridge void*)_metalView);
    if (render_result != RPCS3_IOS_CORE_SUCCESS)
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

- (void)configurePopover:(UIAlertController*)controller source:(UIView*)source
{
    controller.popoverPresentationController.sourceView = source ?: self.view;
    controller.popoverPresentationController.sourceRect = source ? source.bounds :
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
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
    const std::string title_id = copy_core_string(rpcs3_ios_core_copy_title_id);
    const std::string boot_path = copy_core_string(rpcs3_ios_core_copy_boot_path);
    const std::string firmware = copy_core_string(rpcs3_ios_core_copy_firmware_version);
    const size_t games = rpcs3_ios_core_game_count();
    const size_t roots = rpcs3_ios_core_game_directory_count();
    const size_t midi_sources = rpcs3_ios_core_midi_source_count();

    _status.text = [NSString stringWithFormat:
        @"Initialized: %@\nState: %@\nVulkan host: %@\nFirmware: %@\nTitle: %@\nTitle ID: %@\nBoot path: %@\nImports: %s\nAvailable memory: %.2f GiB\nMAP_JIT allocation: %@",
        rpcs3_ios_core_is_initialized() ? @"yes" : @"no",
        state_name(state),
        rpcs3_ios_core_has_render_view() ? @"attached" : @"headless",
        firmware.empty() ? @"not installed" : ns_string(firmware),
        title.empty() ? @"—" : ns_string(title),
        title_id.empty() ? @"—" : ns_string(title_id),
        boot_path.empty() ? @"—" : ns_string(boot_path),
        rpcs3_ios_core_imports_path(),
        performance.available_memory / 1073741824.0,
        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable"];

    _libraryStatus.text = [NSString stringWithFormat:@"%zu game(s), %zu persistent scan root(s).", games, roots];

    NSMutableArray<NSString*>* midi_lines = [NSMutableArray array];
    for (uint32_t slot = 0; slot < rpcs3_ios_core_midi_slot_count(); ++slot)
    {
        const auto [type, source] = copy_midi_assignment(slot);
        [midi_lines addObject:[NSString stringWithFormat:@"Slot %u: %@ — %@",
            slot + 1, midi_type_name(type), source.empty() ? @"None" : ns_string(source)]];
    }
    _midiStatus.text = [NSString stringWithFormat:@"%zu CoreMIDI source(s) available.\n%@",
        midi_sources, [midi_lines componentsJoinedByString:@"\n"]];

    const BOOL stopped = state == RPCS3_IOS_EMULATOR_STOPPED;
    const BOOL available = stopped && !_operationActive;
    _pauseButton.enabled = state == RPCS3_IOS_EMULATOR_RUNNING && !_operationActive;
    _resumeButton.enabled = state == RPCS3_IOS_EMULATOR_PAUSED && !_operationActive;
    _stopButton.enabled = state != RPCS3_IOS_EMULATOR_STOPPED && state != RPCS3_IOS_EMULATOR_UNAVAILABLE && !_operationActive;
    _importButton.enabled = available;
    _firmwareButton.enabled = available;
    _packageButton.enabled = available;
    _addDirectoryButton.enabled = available;
    _rescanDirectoriesButton.enabled = available && roots > 0;
    _manageDirectoriesButton.enabled = available && roots > 0;
    _bootLibraryButton.enabled = available && games > 0;
    _removeLibraryButton.enabled = available && games > 0;
    _configureMidiButton.enabled = available;
    _cancelOperationButton.enabled = _operationActive;
    _saveSettingsButton.enabled = available;
    _resetSettingsButton.enabled = available;
    for (UIControl* control in @[_cpuMode, _audioEnabled, _audioVolume, _resolutionScale,
                                _frameLimit, _shaderCache, _performanceOverlay, _spuThreads])
    {
        control.enabled = available;
    }
}

- (void)handleCoreEvent:(NSDictionary*)payload
{
    const rpcs3_ios_core_event event = (rpcs3_ios_core_event)[payload[@"event"] unsignedIntValue];
    NSString* detail = payload[@"detail"];
    _eventStatus.text = detail.length
        ? [NSString stringWithFormat:@"Event: %@ — %@", event_name(event), detail]
        : [NSString stringWithFormat:@"Event: %@", event_name(event)];
    [self refreshStatus];
}

- (void)handleInstallationProgress:(NSDictionary*)payload
{
    const uint32_t completed = [payload[@"completed"] unsignedIntValue];
    const uint32_t total = [payload[@"total"] unsignedIntValue];
    NSString* detail = payload[@"detail"];
    _installationProgress.progress = total ? (float)completed / (float)total : 0.0f;
    _installationStatus.text = [NSString stringWithFormat:@"%@ (%u/%u)", detail, completed, total];
}

- (void)presentPickerForPurpose:(RPCS3PickerPurpose)purpose types:(NSArray<UTType*>*)types
{
    _pickerPurpose = purpose;
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:NO];
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
    rpcs3_ios_core_result import_result = rpcs3_ios_core_import_path(
        url.fileSystemRepresentation, nullptr, 0, &required);
    std::vector<char> imported(std::max<size_t>(required, 1));
    if (import_result == RPCS3_IOS_CORE_BUFFER_TOO_SMALL)
    {
        import_result = rpcs3_ios_core_import_path(
            url.fileSystemRepresentation, imported.data(), imported.size(), &required);
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

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    NSURL* url = urls.firstObject;
    if (!url.fileURL)
    {
        _eventStatus.text = @"The selected item does not have a local file URL.";
        return;
    }

    rpcs3_ios_core_result import_result = RPCS3_IOS_CORE_PLATFORM_ERROR;
    const std::string imported = [self importURL:url result:&import_result];
    if (import_result != RPCS3_IOS_CORE_SUCCESS)
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
            ? [NSString stringWithFormat:@"Registered %@ and added %u game(s).", url.lastPathComponent, added]
            : [NSString stringWithFormat:@"Library scan failed: %@",
                ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        break;
    }
    }
    [self refreshStatus];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
    (void)controller;
    _eventStatus.text = @"Document selection cancelled.";
}

- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PS3 Firmware"
        message:[NSString stringWithFormat:@"Validate and install %@? Existing firmware may be replaced; downgrades are rejected.", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install or Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self runInstallation:RPCS3_IOS_INSTALLATION_FIRMWARE path:path];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PKG"
        message:[NSString stringWithFormat:@"Validate and install %@ into RPCS3's virtual HDD?", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weak_self runInstallation:RPCS3_IOS_INSTALLATION_PACKAGE path:path];
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
        ? @"Preparing firmware installation…" : @"Preparing package installation…";

    __strong RPCS3CoreLinkViewController* strong_self = self;
    dispatch_async(_operationQueue, ^{
        const rpcs3_ios_core_result result = kind == RPCS3_IOS_INSTALLATION_FIRMWARE
            ? rpcs3_ios_core_install_firmware(path.c_str(), 0, 1, installation_progress_callback, (__bridge void*)strong_self)
            : rpcs3_ios_core_install_package(path.c_str(), installation_progress_callback, (__bridge void*)strong_self);
        const std::string error = copy_core_string(rpcs3_ios_core_copy_last_error);

        dispatch_async(dispatch_get_main_queue(), ^{
            strong_self->_operationActive = NO;
            if (result == RPCS3_IOS_CORE_SUCCESS)
            {
                strong_self->_installationProgress.progress = 1.0f;
                const std::string installed = copy_core_string(rpcs3_ios_core_copy_last_installed_path);
                strong_self->_installationStatus.text = installed.empty()
                    ? @"Installation completed."
                    : [NSString stringWithFormat:@"Installation completed: %@", ns_string(installed)];
            }
            else
            {
                strong_self->_installationStatus.text = [NSString stringWithFormat:@"Installation returned %u: %@",
                    (unsigned int)result, error.empty() ? @"No error detail." : ns_string(error)];
            }
            [strong_self refreshStatus];
        });
    });
}

- (void)cancelInstallation:(UIButton*)sender
{
    (void)sender;
    rpcs3_ios_core_request_installation_cancel();
    _installationStatus.text = @"Cancellation requested…";
}

- (void)rescanDirectories:(UIButton*)sender
{
    (void)sender;
    uint32_t added = 0;
    const rpcs3_ios_core_result result = rpcs3_ios_core_rescan_game_directories(&added);
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? [NSString stringWithFormat:@"Rescan added %u game(s).", added]
        : [NSString stringWithFormat:@"Rescan failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}

- (void)manageDirectories:(UIButton*)sender
{
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"Persistent Game Roots"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    const size_t count = rpcs3_ios_core_game_directory_count();
    for (size_t index = 0; index < count; ++index)
    {
        const std::string path = copy_game_directory(index);
        if (path.empty())
        {
            continue;
        }
        NSString* title = [NSString stringWithFormat:@"Remove %@", ns_string(path).lastPathComponent];
        __weak RPCS3CoreLinkViewController* weak_self = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
            [weak_self confirmRemoveDirectory:path];
        }]];
    }

    __weak RPCS3CoreLinkViewController* weak_self = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Prune Missing Roots" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        uint32_t removed = 0;
        const rpcs3_ios_core_result result = rpcs3_ios_core_prune_missing_game_directories(&removed);
        weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
            ? [NSString stringWithFormat:@"Pruned %u missing root(s).", removed]
            : [NSString stringWithFormat:@"Prune failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [weak_self refreshStatus];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear All Roots" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self confirmClearDirectories];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet source:sender];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmRemoveDirectory:(const std::string&)path
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Unregister Game Root"
        message:ns_string(path) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Library Entries" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weak_self removeDirectory:path removeEntries:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove Entries" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self removeDirectory:path removeEntries:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeDirectory:(const std::string&)path removeEntries:(BOOL)remove_entries
{
    uint32_t removed = 0;
    const rpcs3_ios_core_result result = rpcs3_ios_core_remove_game_directory(path.c_str(), remove_entries, &removed);
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? [NSString stringWithFormat:@"Unregistered root; removed %u library entry/entries.", removed]
        : [NSString stringWithFormat:@"Root removal failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}

- (void)confirmClearDirectories
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Clear All Game Roots"
        message:@"Choose whether to keep the current games.yml entries or remove entries beneath every registered root."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Library Entries" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weak_self clearDirectoriesRemovingEntries:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove Entries" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self clearDirectoriesRemovingEntries:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearDirectoriesRemovingEntries:(BOOL)remove_entries
{
    uint32_t removed = 0;
    const rpcs3_ios_core_result result = rpcs3_ios_core_clear_game_directories(remove_entries, &removed);
    _eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
        ? [NSString stringWithFormat:@"Cleared all roots; removed %u library entry/entries.", removed]
        : [NSString stringWithFormat:@"Clear roots failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self refreshStatus];
}

- (void)presentGameSheet:(UIButton*)sender destructive:(BOOL)destructive
{
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:
        destructive ? @"Remove Library Entry" : @"Boot Library Game"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    const size_t count = rpcs3_ios_core_game_count();
    for (size_t index = 0; index < count; ++index)
    {
        const auto [title_id, path] = copy_library_game(index);
        if (path.empty())
        {
            continue;
        }
        NSString* title = title_id.empty() ? ns_string(path).lastPathComponent : ns_string(title_id);
        __weak RPCS3CoreLinkViewController* weak_self = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title
            style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
            handler:^(UIAlertAction*) {
                if (destructive)
                {
                    const rpcs3_ios_core_result result = rpcs3_ios_core_remove_game(title_id.c_str());
                    weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
                        ? [NSString stringWithFormat:@"Removed %@ from the library.", title]
                        : [NSString stringWithFormat:@"Remove failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
                }
                else
                {
                    const rpcs3_ios_boot_result result = rpcs3_ios_core_boot_path(path.c_str(), 1);
                    weak_self->_eventStatus.text = result == RPCS3_IOS_BOOT_SUCCESS
                        ? [NSString stringWithFormat:@"Boot accepted: %@", title]
                        : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)result,
                            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
                }
                [weak_self refreshStatus];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet source:sender];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)bootLibraryGame:(UIButton*)sender
{
    [self presentGameSheet:sender destructive:NO];
}

- (void)removeLibraryGame:(UIButton*)sender
{
    [self presentGameSheet:sender destructive:YES];
}

- (void)configureMidi:(UIButton*)sender
{
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"CoreMIDI Adapter Slots"
        message:@"RPCS3 exposes up to three emulated Rock Band 3 MIDI adapters."
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (uint32_t slot = 0; slot < rpcs3_ios_core_midi_slot_count(); ++slot)
    {
        const auto [type, source] = copy_midi_assignment(slot);
        NSString* title = [NSString stringWithFormat:@"Slot %u: %@ — %@", slot + 1,
            midi_type_name(type), source.empty() ? @"None" : ns_string(source)];
        __weak RPCS3CoreLinkViewController* weak_self = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
            [weak_self chooseMidiTypeForSlot:slot];
        }]];
    }
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear All Assignments" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        const rpcs3_ios_core_result result = rpcs3_ios_core_clear_all_midi_assignments();
        weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
            ? @"Cleared every CoreMIDI adapter assignment."
            : [NSString stringWithFormat:@"MIDI clear failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [weak_self refreshStatus];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet source:sender];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseMidiTypeForSlot:(uint32_t)slot
{
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:
        [NSString stringWithFormat:@"Slot %u Adapter Type", slot + 1]
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (uint32_t type = RPCS3_IOS_MIDI_KEYBOARD; type <= RPCS3_IOS_MIDI_DRUMS; ++type)
    {
        __weak RPCS3CoreLinkViewController* weak_self = self;
        [sheet addAction:[UIAlertAction actionWithTitle:midi_type_name(type) style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
            [weak_self chooseMidiSourceForSlot:slot type:type];
        }]];
    }
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear Slot" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        const rpcs3_ios_core_result result = rpcs3_ios_core_clear_midi_assignment(slot);
        weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
            ? [NSString stringWithFormat:@"Cleared MIDI slot %u.", slot + 1]
            : [NSString stringWithFormat:@"MIDI clear failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [weak_self refreshStatus];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet source:_configureMidiButton];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseMidiSourceForSlot:(uint32_t)slot type:(uint32_t)type
{
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:@"Choose CoreMIDI Source"
        message:midi_type_name(type) preferredStyle:UIAlertControllerStyleActionSheet];
    const size_t count = rpcs3_ios_core_midi_source_count();
    for (size_t index = 0; index < count; ++index)
    {
        const std::string source = copy_midi_source(index);
        if (source.empty())
        {
            continue;
        }
        __weak RPCS3CoreLinkViewController* weak_self = self;
        [sheet addAction:[UIAlertAction actionWithTitle:ns_string(source) style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
            const rpcs3_ios_core_result result = rpcs3_ios_core_set_midi_assignment(slot, type, source.c_str());
            weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
                ? [NSString stringWithFormat:@"Assigned %@ to MIDI slot %u as %@.", ns_string(source), slot + 1, midi_type_name(type)]
                : [NSString stringWithFormat:@"MIDI assignment failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
            [weak_self refreshStatus];
        }]];
    }
    if (!count)
    {
        [sheet addAction:[UIAlertAction actionWithTitle:@"No CoreMIDI Sources Available" style:UIAlertActionStyleDefault handler:nil]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self configurePopover:sheet source:_configureMidiButton];
    [self presentViewController:sheet animated:YES completion:nil];
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
    NSInteger scale_index = 2;
    uint32_t closest = UINT32_MAX;
    for (NSInteger index = 0; index < 5; ++index)
    {
        const uint32_t distance = scales[index] > configuration.resolution_scale_percent
            ? scales[index] - configuration.resolution_scale_percent
            : configuration.resolution_scale_percent - scales[index];
        if (distance < closest)
        {
            closest = distance;
            scale_index = index;
        }
    }
    _resolutionScale.selectedSegmentIndex = scale_index;
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
        ? @"Core settings saved for the next boot."
        : [NSString stringWithFormat:@"Settings returned %u: %@", (unsigned int)result,
            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
    [self loadSettingsControls];
    [self refreshStatus];
}

- (void)resetSettings:(UIButton*)sender
{
    (void)sender;
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reset Core Settings"
        message:@"Restore the mobile-safe RPCS3Core defaults?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        const rpcs3_ios_core_result result = rpcs3_ios_core_reset_configuration();
        weak_self->_eventStatus.text = result == RPCS3_IOS_CORE_SUCCESS
            ? @"Core settings reset to mobile-safe defaults."
            : [NSString stringWithFormat:@"Reset failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
        [weak_self loadSettingsControls];
        [weak_self refreshStatus];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
        NSLog(@"RPCS3Core initialization failed: %@", ns_string(copy_core_string(rpcs3_ios_core_copy_last_error)));
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
