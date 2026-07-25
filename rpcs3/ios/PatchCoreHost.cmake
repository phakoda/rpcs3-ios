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
if(NOT _core_host_contents MATCHES "@interface RPCS3CoreLinkViewController \\(\\)" OR
   NOT _host_path_copy_count EQUAL 3 OR
   _core_host_contents MATCHES "INSTALLATION_FIRMWARE path:path\\]" OR
   _core_host_contents MATCHES "INSTALLATION_PACKAGE path:path\\]" OR
   _core_host_contents MATCHES "removeDirectory:path removeEntries")
    message(FATAL_ERROR "Could not apply the iOS core management-host lifetime adaptation")
endif()

file(WRITE "${_core_host_generated}" "${_core_host_contents}")
get_target_property(_core_host_sources rpcs3_ios_core_link SOURCES)
list(FILTER _core_host_sources EXCLUDE REGEX "(^|/)CoreLinkMain\\.mm$")
set_property(TARGET rpcs3_ios_core_link PROPERTY SOURCES "${_core_host_sources}")
target_sources(rpcs3_ios_core_link PRIVATE
    "${_core_host_generated}"
    "${CMAKE_SOURCE_DIR}/rpcs3/ios/IOSCoreOpenURL.mm")
