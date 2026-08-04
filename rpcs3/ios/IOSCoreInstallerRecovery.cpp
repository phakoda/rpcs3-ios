#include "IOSCoreInstaller.h"

#include "Emu/System.h"
#include "Emu/VFS.h"
#include "Emu/vfs_config.h"

#include <filesystem>
#include <string>
#include <system_error>

namespace
{
namespace hostfs = std::filesystem;

hostfs::path normalized_path(std::string value)
{
    while (value.size() > 1 && (value.back() == '/' || value.back() == '\\'))
    {
        value.pop_back();
    }
    return hostfs::path(std::move(value)).lexically_normal();
}

struct recovery_paths
{
    hostfs::path live;
    hostfs::path staging;
    hostfs::path backup;
    hostfs::path marker;
};

recovery_paths make_paths()
{
    recovery_paths paths;
    paths.live = normalized_path(g_cfg_vfs.get_dev_flash());
    const hostfs::path parent = paths.live.parent_path();
    const std::string stem = paths.live.filename().string();
    paths.staging = parent / (stem + ".ios-installing");
    paths.backup = parent / (stem + ".ios-backup");
    paths.marker = parent / (stem + ".ios-install-transaction");
    return paths;
}

bool remove_all(const hostfs::path& path, std::string* error_message)
{
    std::error_code error;
    hostfs::remove_all(path, error);
    if (error && error_message)
    {
        *error_message = "Could not remove " + path.string() + ": " + error.message();
    }
    return !error;
}

void remount_live(const recovery_paths& paths)
{
    vfs::unmount("/dev_flash");
    (void)vfs::mount("/dev_flash", paths.live.string());
    Emu.Init();
}
}

namespace rpcs3::ios
{
bool recover_core_firmware_transaction(std::string* error_message)
{
    const recovery_paths paths = make_paths();
    std::error_code error;
    if (!hostfs::exists(paths.marker, error))
    {
        if (error && error_message)
        {
            *error_message = "Could not inspect the firmware recovery marker: " + error.message();
        }
        return !error;
    }

    const bool live_exists = hostfs::exists(paths.live, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not inspect the live firmware tree: " + error.message();
        }
        return false;
    }
    const bool backup_exists = hostfs::exists(paths.backup, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not inspect the firmware backup: " + error.message();
        }
        return false;
    }

    if (!live_exists && backup_exists)
    {
        hostfs::rename(paths.backup, paths.live, error);
        if (error)
        {
            if (error_message)
            {
                *error_message = "Could not restore interrupted firmware backup: " + error.message();
            }
            return false;
        }
    }
    else if (live_exists && backup_exists && !remove_all(paths.backup, error_message))
    {
        return false;
    }

    if (!remove_all(paths.staging, error_message))
    {
        return false;
    }
    hostfs::remove(paths.marker, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not clear the firmware recovery marker: " + error.message();
        }
        return false;
    }

    try
    {
        remount_live(paths);
    }
    catch (const std::exception& exception)
    {
        if (error_message)
        {
            *error_message = std::string("Firmware recovery completed, but VFS refresh failed: ") + exception.what();
        }
        return false;
    }
    catch (...)
    {
        if (error_message)
        {
            *error_message = "Firmware recovery completed, but VFS refresh failed with an unknown exception.";
        }
        return false;
    }
    return true;
}
}
