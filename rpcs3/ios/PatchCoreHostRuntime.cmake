# Apply runtime-oriented UIKit host adaptations after PatchCoreHost.cmake has
# produced its anchor-checked safe Objective-C++ translation unit. Keeping this
# second pass separate makes the large management host source easy to audit and
# lets configuration fail loudly if the expected host contract changes.

if(NOT TARGET rpcs3_ios_core_link)
    return()
endif()

set(_runtime_host_generated "${CMAKE_CURRENT_BINARY_DIR}/ios-generated/CoreLinkMainSafe.mm")
if(NOT EXISTS "${_runtime_host_generated}")
    message(FATAL_ERROR "The safe iOS core host must be generated before runtime adaptations")
endif()

file(READ "${_runtime_host_generated}" _runtime_host_contents)

string(REPLACE
    "- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName;\n- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName;\n- (void)runInstallation:(rpcs3_ios_installation_kind)kind path:(std::string)path;"
    "- (void)confirmFirmwareInstallationURL:(NSURL*)url;\n- (void)confirmPackageInstallations:(NSArray<NSURL*>*)urls;\n- (void)runInstallations:(rpcs3_ios_installation_kind)kind URLs:(NSArray<NSURL*>*)urls;\n- (void)runImportedContentURL:(NSURL*)url purpose:(RPCS3PickerPurpose)purpose;\n- (void)runLibraryBootPath:(std::string)path displayName:(NSString*)displayName;"
    _runtime_host_contents "${_runtime_host_contents}")

string(REPLACE
    "_packageButton = [self buttonWithTitle:@\"Install PKG\" action:@selector(choosePackage:) prominent:NO];"
    "_packageButton = [self buttonWithTitle:@\"Install PKG / RAP / EDAT\" action:@selector(choosePackage:) prominent:NO];"
    _runtime_host_contents "${_runtime_host_contents}")
string(REPLACE
    "[self sectionLabel:@\"Firmware and Packages\"]"
    "[self sectionLabel:@\"Firmware, Packages, and Licenses\"]"
    _runtime_host_contents "${_runtime_host_contents}")
string(REPLACE
    "    picker.allowsMultipleSelection = NO;"
    "    picker.allowsMultipleSelection = purpose == RPCS3PickerPurposePackage;"
    _runtime_host_contents "${_runtime_host_contents}")

set(_picker_anchor [=[- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
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
]=])
set(_picker_replacement [=[- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    if (!urls.count)
    {
        _eventStatus.text = @"No document was selected.";
        return;
    }

    if (_pickerPurpose == RPCS3PickerPurposePackage)
    {
        NSMutableArray<NSURL*>* local_urls = [NSMutableArray array];
        for (NSURL* candidate in urls)
        {
            if (candidate.fileURL)
            {
                [local_urls addObject:candidate];
            }
        }
        if (!local_urls.count)
        {
            _eventStatus.text = @"The selected items do not have local file URLs.";
            return;
        }
        [self confirmPackageInstallations:local_urls];
        return;
    }

    NSURL* url = urls.firstObject;
    if (!url.fileURL)
    {
        _eventStatus.text = @"The selected item does not have a local file URL.";
        return;
    }

    if (_pickerPurpose == RPCS3PickerPurposeFirmware)
    {
        [self confirmFirmwareInstallationURL:url];
        return;
    }

    [self runImportedContentURL:url purpose:_pickerPurpose];
}

- (void)runImportedContentURL:(NSURL*)url purpose:(RPCS3PickerPurpose)purpose
{
    if (_operationActive)
    {
        return;
    }

    [self setOperationActive:YES];
    NSURL* selected_url = [url copy];
    NSString* display_name = [selected_url.lastPathComponent copy];
    __strong RPCS3CoreLinkViewController* strong_self = self;
    dispatch_async(_operationQueue, ^{
        rpcs3_ios_core_result import_result = RPCS3_IOS_CORE_PLATFORM_ERROR;
        const std::string imported = [strong_self importURL:selected_url result:&import_result];
        rpcs3_ios_boot_result boot_result = RPCS3_IOS_BOOT_GENERIC_ERROR;
        rpcs3_ios_core_result library_result = RPCS3_IOS_CORE_PLATFORM_ERROR;
        uint32_t added_games = 0;

        if (import_result == RPCS3_IOS_CORE_SUCCESS)
        {
            if (purpose == RPCS3PickerPurposeBoot)
            {
                boot_result = rpcs3_ios_core_boot_path(imported.c_str(), 1);
            }
            else if (purpose == RPCS3PickerPurposeGameDirectory)
            {
                library_result = rpcs3_ios_core_add_game_directory(imported.c_str(), &added_games);
            }
        }
        const std::string error = copy_core_string(rpcs3_ios_core_copy_last_error);

        dispatch_async(dispatch_get_main_queue(), ^{
            strong_self->_operationActive = NO;
            if (import_result != RPCS3_IOS_CORE_SUCCESS)
            {
                strong_self->_eventStatus.text = [NSString stringWithFormat:@"Import failed: %@",
                    error.empty() ? @"No error detail." : ns_string(error)];
            }
            else if (purpose == RPCS3PickerPurposeBoot)
            {
                strong_self->_eventStatus.text = boot_result == RPCS3_IOS_BOOT_SUCCESS
                    ? [NSString stringWithFormat:@"Boot accepted: %@", display_name]
                    : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)boot_result,
                        error.empty() ? @"No error detail." : ns_string(error)];
            }
            else
            {
                strong_self->_eventStatus.text = library_result == RPCS3_IOS_CORE_SUCCESS
                    ? [NSString stringWithFormat:@"Registered %@ and added %u game(s).", display_name, added_games]
                    : [NSString stringWithFormat:@"Library scan failed: %@",
                        error.empty() ? @"No error detail." : ns_string(error)];
            }
            [strong_self refreshStatus];
        });
    });
}
]=])
string(REPLACE "${_picker_anchor}" "${_picker_replacement}"
    _runtime_host_contents "${_runtime_host_contents}")

set(_install_anchor [=[- (void)confirmFirmwareInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    const std::string path_copy = path;
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PS3 Firmware"
        message:[NSString stringWithFormat:@"Validate and install %@? Existing firmware may be replaced; downgrades are rejected.", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install or Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self runInstallation:RPCS3_IOS_INSTALLATION_FIRMWARE path:path_copy];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmPackageInstallation:(const std::string&)path displayName:(NSString*)displayName
{
    const std::string path_copy = path;
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PKG"
        message:[NSString stringWithFormat:@"Validate and install %@ into RPCS3's virtual HDD?", displayName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weak_self runInstallation:RPCS3_IOS_INSTALLATION_PACKAGE path:path_copy];
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
]=])
set(_install_replacement [=[- (void)confirmFirmwareInstallationURL:(NSURL*)url
{
    NSURL* url_copy = [url copy];
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PS3 Firmware"
        message:[NSString stringWithFormat:@"Validate and install %@? Existing firmware may be replaced; downgrades are rejected.", url.lastPathComponent]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install or Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
        [weak_self runInstallations:RPCS3_IOS_INSTALLATION_FIRMWARE URLs:@[url_copy]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmPackageInstallations:(NSArray<NSURL*>*)urls
{
    NSArray<NSURL*>* urls_copy = [urls copy];
    NSString* message = urls_copy.count == 1
        ? [NSString stringWithFormat:@"Validate and install %@? PKG content is added to the virtual HDD; RAP/EDAT files are installed into the active user's exdata directory.", urls_copy.firstObject.lastPathComponent]
        : [NSString stringWithFormat:@"Validate and install %lu selected PKG/RAP/EDAT items?", (unsigned long)urls_copy.count];
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install PS3 Content"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak RPCS3CoreLinkViewController* weak_self = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        [weak_self runInstallations:RPCS3_IOS_INSTALLATION_PACKAGE URLs:urls_copy];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runInstallations:(rpcs3_ios_installation_kind)kind URLs:(NSArray<NSURL*>*)urls
{
    if (_operationActive || !urls.count)
    {
        return;
    }

    [self setOperationActive:YES];
    _installationProgress.progress = 0.0f;
    _installationStatus.text = kind == RPCS3_IOS_INSTALLATION_FIRMWARE
        ? @"Preparing firmware installation…" : @"Preparing package/license installation…";

    NSArray<NSURL*>* urls_copy = [urls copy];
    __strong RPCS3CoreLinkViewController* strong_self = self;
    dispatch_async(_operationQueue, ^{
        rpcs3_ios_core_result result = RPCS3_IOS_CORE_SUCCESS;
        std::string error;
        std::string installed;
        NSUInteger completed_items = 0;

        for (NSURL* url in urls_copy)
        {
            if (!url.fileURL)
            {
                result = RPCS3_IOS_CORE_INVALID_ARGUMENT;
                error = "The selected item does not have a local file URL.";
                break;
            }

            const BOOL scoped = [url startAccessingSecurityScopedResource];
            const char* path = url.fileSystemRepresentation;
            result = kind == RPCS3_IOS_INSTALLATION_FIRMWARE
                ? rpcs3_ios_core_install_firmware(path, 0, 1, installation_progress_callback, (__bridge void*)strong_self)
                : rpcs3_ios_core_install_package(path, installation_progress_callback, (__bridge void*)strong_self);
            if (scoped)
            {
                [url stopAccessingSecurityScopedResource];
            }

            if (result != RPCS3_IOS_CORE_SUCCESS)
            {
                error = copy_core_string(rpcs3_ios_core_copy_last_error);
                break;
            }

            installed = copy_core_string(rpcs3_ios_core_copy_last_installed_path);
            ++completed_items;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            strong_self->_operationActive = NO;
            if (result == RPCS3_IOS_CORE_SUCCESS)
            {
                strong_self->_installationProgress.progress = 1.0f;
                if (urls_copy.count > 1)
                {
                    strong_self->_installationStatus.text = [NSString stringWithFormat:@"Installed %lu PS3 content item(s).",
                        (unsigned long)completed_items];
                }
                else
                {
                    strong_self->_installationStatus.text = installed.empty()
                        ? @"Installation completed."
                        : [NSString stringWithFormat:@"Installation completed: %@", ns_string(installed)];
                }
            }
            else
            {
                strong_self->_installationStatus.text = [NSString stringWithFormat:@"Installation returned %u after %lu item(s): %@",
                    (unsigned int)result,
                    (unsigned long)completed_items,
                    error.empty() ? @"No error detail." : ns_string(error)];
            }
            [strong_self refreshStatus];
        });
    });
}

- (void)runLibraryBootPath:(std::string)path displayName:(NSString*)displayName
{
    if (_operationActive)
    {
        return;
    }

    [self setOperationActive:YES];
    const std::string path_copy = path;
    NSString* display_name = [displayName copy];
    __strong RPCS3CoreLinkViewController* strong_self = self;
    dispatch_async(_operationQueue, ^{
        const rpcs3_ios_boot_result result = rpcs3_ios_core_boot_path(path_copy.c_str(), 1);
        const std::string error = copy_core_string(rpcs3_ios_core_copy_last_error);
        dispatch_async(dispatch_get_main_queue(), ^{
            strong_self->_operationActive = NO;
            strong_self->_eventStatus.text = result == RPCS3_IOS_BOOT_SUCCESS
                ? [NSString stringWithFormat:@"Boot accepted: %@", display_name]
                : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)result,
                    error.empty() ? @"No error detail." : ns_string(error)];
            [strong_self refreshStatus];
        });
    });
}
]=])
string(REPLACE "${_install_anchor}" "${_install_replacement}"
    _runtime_host_contents "${_runtime_host_contents}")

set(_library_boot_anchor [=[                else
                {
                    const rpcs3_ios_boot_result result = rpcs3_ios_core_boot_path(game_path_copy.c_str(), 1);
                    strong_self->_eventStatus.text = result == RPCS3_IOS_BOOT_SUCCESS
                        ? [NSString stringWithFormat:@"Boot accepted: %@", title]
                        : [NSString stringWithFormat:@"Boot result %u: %@", (unsigned int)result,
                            ns_string(copy_core_string(rpcs3_ios_core_copy_last_error))];
                }
                [strong_self refreshStatus];]=])
set(_library_boot_replacement [=[                else
                {
                    [strong_self runLibraryBootPath:game_path_copy displayName:title];
                }
                [strong_self refreshStatus];]=])
string(REPLACE "${_library_boot_anchor}" "${_library_boot_replacement}"
    _runtime_host_contents "${_runtime_host_contents}")

if(NOT _runtime_host_contents MATCHES "Install PKG / RAP / EDAT" OR
   NOT _runtime_host_contents MATCHES "purpose == RPCS3PickerPurposePackage" OR
   NOT _runtime_host_contents MATCHES "confirmPackageInstallations" OR
   NOT _runtime_host_contents MATCHES "runImportedContentURL" OR
   NOT _runtime_host_contents MATCHES "runLibraryBootPath" OR
   NOT _runtime_host_contents MATCHES "startAccessingSecurityScopedResource" OR
   _runtime_host_contents MATCHES "confirmPackageInstallation:imported" OR
   _runtime_host_contents MATCHES "const std::string imported = \\[self importURL:url" OR
   _runtime_host_contents MATCHES "rpcs3_ios_core_boot_path\\(game_path_copy\\.c_str\\(\\), 1\\)")
    message(FATAL_ERROR "Could not apply the iOS core runtime-host adaptation")
endif()

file(WRITE "${_runtime_host_generated}" "${_runtime_host_contents}")
