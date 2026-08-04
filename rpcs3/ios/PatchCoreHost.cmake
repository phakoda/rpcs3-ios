# Generate a hardened copy of the Qt-free UIKit management host.
#
# CoreLinkMain.mm is iOS-specific, but retaining anchor-checked generation keeps
# the large translation unit stable while making C++ object lifetimes across
# Objective-C blocks explicit. Configuration fails when an expected source
# contract moves instead of silently compiling an unsafe host.

if(NOT TARGET rpcs3_ios_core_link)
    return()
endif()

set(_core_host_source "${CMAKE_SOURCE_DIR}/rpcs3/ios/CoreLinkMain.mm")
set(_core_host_generated "${CMAKE_CURRENT_BINARY_DIR}/ios-generated/CoreLinkMainSafe.mm")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_core_host_source}")
file(READ "${_core_host_source}" _core_host_contents)

string(REPLACE
    "#include \"RPCS3Core.h\""
    "#include \"RPCS3Core.h\"\n#include \"RPCS3CoreStatus.h\""
    _core_host_contents "${_core_host_contents}")

set(_host_interface_anchor [=[@interface RPCS3CoreLinkViewController : UIViewController <UIDocumentPickerDelegate>
- (void)handleCoreEvent:(NSDictionary*)payload;
- (void)handleInstallationProgress:(NSDictionary*)payload;
@end

@implementation RPCS3CoreLinkViewController]=])
set(_host_interface_replacement [=[@interface RPCS3CoreLinkViewController : UIViewController <UIDocumentPickerDelegate>
- (void)handleCoreEvent:(NSDictionary*)payload;
- (void)handleInstallationProgress:(NSDictionary*)payload;
@end

@interface RPCS3CoreLinkViewController ()
- (void)refreshStatus;
- (void)loadSettingsControls;
- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName;
- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName;
- (void)runInstallation:(rpcs3_ios_installation_kind)kind path:(std::string)path;
- (void)confirmRemoveDirectory:(const std::string&)path;
- (void)removeDirectory:(const std::string&)path removeEntries:(BOOL)removeEntries;
- (void)confirmClearDirectories;
- (void)clearDirectoriesRemovingEntries:(BOOL)removeEntries;
- (void)chooseMidiTypeForSlot:(uint32_t)slot;
- (void)chooseMidiSourceForSlot:(uint32_t)slot type:(uint32_t)type;
- (void)importAndBoot:(UIButton*)sender;
- (void)chooseFirmware:(UIButton*)sender;
- (void)choosePackage:(UIButton*)sender;
- (void)addGameDirectory:(UIButton*)sender;
- (void)rescanDirectories:(UIButton*)sender;
- (void)manageDirectories:(UIButton*)sender;
- (void)bootLibraryGame:(UIButton*)sender;
- (void)removeLibraryGame:(UIButton*)sender;
- (void)configureMidi:(UIButton*)sender;
- (void)cancelInstallation:(UIButton*)sender;
- (void)pauseCore:(UIButton*)sender;
- (void)resumeCore:(UIButton*)sender;
- (void)stopCore:(UIButton*)sender;
- (void)saveSettings:(UIButton*)sender;
- (void)resetSettings:(UIButton*)sender;
- (void)shareDiagnostics:(UIButton*)sender;
- (void)volumeChanged:(UISlider*)slider;
- (void)spuThreadsChanged:(UIStepper*)stepper;
@end

@implementation RPCS3CoreLinkViewController]=])
string(REPLACE "${_host_interface_anchor}" "${_host_interface_replacement}"
    _core_host_contents "${_core_host_contents}")

string(REPLACE
    "    dispatch_queue_t _operationQueue;\n    BOOL _operationActive;"
    "    dispatch_queue_t _operationQueue;\n    BOOL _operationActive;\n    NSTimer* _statusTimer;"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "title.text = @\"RPCS3Core.framework 0.4\";"
    "title.text = @\"RPCS3Core.framework 0.5\";"
    _core_host_contents "${_core_host_contents}")

set(_timer_anchor [=[    rpcs3_ios_core_set_event_callback(core_event_callback, (__bridge void*)self);
    [self loadSettingsControls];
    [self refreshStatus];
}]=])
set(_timer_replacement [=[    rpcs3_ios_core_set_event_callback(core_event_callback, (__bridge void*)self);
    [self loadSettingsControls];
    [self refreshStatus];

    __weak RPCS3CoreLinkViewController* weak_self = self;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
        repeats:YES
          block:^(NSTimer*) { [weak_self refreshStatus]; }];
}]=])
string(REPLACE "${_timer_anchor}" "${_timer_replacement}"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "- (void)dealloc\n{\n    rpcs3_ios_core_set_event_callback(nullptr, nullptr);"
    "- (void)dealloc\n{\n    [_statusTimer invalidate];\n    _statusTimer = nil;\n    rpcs3_ios_core_set_event_callback(nullptr, nullptr);"
    _core_host_contents "${_core_host_contents}")

string(REPLACE
    "    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();"
    "    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();\n    const rpcs3_ios_core_operation_status operation = rpcs3_ios_core_query_operation_status();\n    const rpcs3_ios_installation_status_v2 installation = rpcs3_ios_core_query_installation_status_v2();\n    const BOOL framework_operation_active = operation.active_operation != RPCS3_IOS_CORE_OPERATION_NONE;\n    const BOOL operation_active = _operationActive || framework_operation_active;"
    _core_host_contents "${_core_host_contents}")

set(_status_append_anchor [=[        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable"];

    _libraryStatus.text]=])
set(_status_append_replacement [=[        jit.map_jit_allocation_succeeded ? @"available" : @"unavailable"];
    if (framework_operation_active)
    {
        _status.text = [_status.text stringByAppendingFormat:
            @"\nActive operation: %u (generation %llu)",
            operation.active_operation,
            (unsigned long long)operation.generation];
    }

    _libraryStatus.text]=])
string(REPLACE "${_status_append_anchor}" "${_status_append_replacement}"
    _core_host_contents "${_core_host_contents}")

set(_installation_poll_anchor [=[    _midiStatus.text = [NSString stringWithFormat:@"%zu CoreMIDI source(s) available.\n%@",
        midi_sources, [midi_lines componentsJoinedByString:@"\n"]];

    const BOOL stopped = state == RPCS3_IOS_EMULATOR_STOPPED;
    const BOOL available = stopped && !_operationActive;
    _pauseButton.enabled = state == RPCS3_IOS_EMULATOR_RUNNING && !_operationActive;
    _resumeButton.enabled = state == RPCS3_IOS_EMULATOR_PAUSED && !_operationActive;
    _stopButton.enabled = state != RPCS3_IOS_EMULATOR_STOPPED && state != RPCS3_IOS_EMULATOR_UNAVAILABLE && !_operationActive;]=])
set(_installation_poll_replacement [=[    _midiStatus.text = [NSString stringWithFormat:
        @"%zu CoreMIDI source(s) available (topology generation %llu).\n%@",
        midi_sources,
        (unsigned long long)rpcs3_ios_core_midi_topology_generation(),
        [midi_lines componentsJoinedByString:@"\n"]];

    if (installation.active || installation.terminal_state != RPCS3_IOS_INSTALLATION_TERMINAL_NONE)
    {
        const std::string detail = copy_core_string(rpcs3_ios_core_copy_installation_detail);
        _installationProgress.progress = installation.total
            ? (float)installation.completed / (float)installation.total
            : 0.0f;
        NSString* terminal = @"active";
        switch (installation.terminal_state)
        {
        case RPCS3_IOS_INSTALLATION_TERMINAL_SUCCEEDED: terminal = @"succeeded"; break;
        case RPCS3_IOS_INSTALLATION_TERMINAL_FAILED: terminal = @"failed"; break;
        case RPCS3_IOS_INSTALLATION_TERMINAL_CANCELLED: terminal = @"cancelled"; break;
        default: break;
        }
        _installationStatus.text = [NSString stringWithFormat:
            @"Operation %llu: %@, result %u, %u/%u — %@",
            (unsigned long long)installation.operation_id,
            terminal,
            installation.result,
            installation.completed,
            installation.total,
            detail.empty() ? @"No detail" : ns_string(detail)];
    }

    const BOOL stopped = state == RPCS3_IOS_EMULATOR_STOPPED;
    const BOOL available = stopped && !operation_active;
    _pauseButton.enabled = state == RPCS3_IOS_EMULATOR_RUNNING && !operation_active;
    _resumeButton.enabled = state == RPCS3_IOS_EMULATOR_PAUSED && !operation_active;
    _stopButton.enabled = state != RPCS3_IOS_EMULATOR_STOPPED && state != RPCS3_IOS_EMULATOR_UNAVAILABLE && !operation_active;]=])
string(REPLACE "${_installation_poll_anchor}" "${_installation_poll_replacement}"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "    _cancelOperationButton.enabled = _operationActive;"
    "    _cancelOperationButton.enabled = installation.active != 0;"
    _core_host_contents "${_core_host_contents}")

set(_firmware_anchor [=[- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert]=])
set(_firmware_replacement [=[- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    const std::string path_copy = path;
    UIAlertController* alert]=])
string(REPLACE "${_firmware_anchor}" "${_firmware_replacement}"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "[weak_self runInstallation:RPCS3_IOS_INSTALLATION_FIRMWARE path:path];"
    "[weak_self runInstallation:RPCS3_IOS_INSTALLATION_FIRMWARE path:path_copy];"
    _core_host_contents "${_core_host_contents}")

set(_package_anchor [=[- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    UIAlertController* alert]=])
set(_package_replacement [=[- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    const std::string path_copy = path;
    UIAlertController* alert]=])
string(REPLACE "${_package_anchor}" "${_package_replacement}"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "[weak_self runInstallation:RPCS3_IOS_INSTALLATION_PACKAGE path:path];"
    "[weak_self runInstallation:RPCS3_IOS_INSTALLATION_PACKAGE path:path_copy];"
    _core_host_contents "${_core_host_contents}")

set(_remove_anchor [=[- (void)confirmRemoveDirectory:(const std::string&)path
{
    UIAlertController* alert]=])
set(_remove_replacement [=[- (void)confirmRemoveDirectory:(const std::string&)path
{
    const std::string path_copy = path;
    UIAlertController* alert]=])
string(REPLACE "${_remove_anchor}" "${_remove_replacement}"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "[weak_self removeDirectory:path removeEntries:NO];"
    "[weak_self removeDirectory:path_copy removeEntries:NO];"
    _core_host_contents "${_core_host_contents}")
string(REPLACE
    "[weak_self removeDirectory:path removeEntries:YES];"
    "[weak_self removeDirectory:path_copy removeEntries:YES];"
    _core_host_contents "${_core_host_contents}")

string(REGEX MATCHALL "const std::string path_copy = path;" _host_path_copies
    "${_core_host_contents}")
list(LENGTH _host_path_copies _host_path_copy_count)
if(NOT _core_host_contents MATCHES "RPCS3CoreStatus\\.h" OR
   NOT _core_host_contents MATCHES "@interface RPCS3CoreLinkViewController \\(\\)" OR
   NOT _core_host_contents MATCHES "rpcs3_ios_core_query_operation_status" OR
   NOT _core_host_contents MATCHES "rpcs3_ios_core_query_installation_status_v2" OR
   NOT _core_host_contents MATCHES "scheduledTimerWithTimeInterval:0\\.5" OR
   NOT _host_path_copy_count EQUAL 3 OR
   _core_host_contents MATCHES "INSTALLATION_FIRMWARE path:path\\]" OR
   _core_host_contents MATCHES "INSTALLATION_PACKAGE path:path\\]" OR
   _core_host_contents MATCHES "removeDirectory:path removeEntries")
    message(FATAL_ERROR "Could not apply the iOS core management-host adaptation")
endif()

file(WRITE "${_core_host_generated}"
    "#line 1 \"${_core_host_source}\"\n${_core_host_contents}")
get_target_property(_core_host_sources rpcs3_ios_core_link SOURCES)
list(FILTER _core_host_sources EXCLUDE REGEX "(^|/)CoreLinkMain\\.mm$")
set_property(TARGET rpcs3_ios_core_link PROPERTY SOURCES "${_core_host_sources}")
target_sources(rpcs3_ios_core_link PRIVATE
    "${_core_host_generated}"
    "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreOpenURL.mm")
