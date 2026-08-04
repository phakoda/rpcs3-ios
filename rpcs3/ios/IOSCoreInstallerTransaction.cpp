#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#include "Emu/System.h"
#include "Emu/VFS.h"
#include "Emu/system_utils.hpp"
#include "Emu/vfs_config.h"
#include "Loader/PUP.h"
#include "Utilities/File.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_install_firmware_raw(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
rpcs3_ios_core_result rpcs3_ios_core_install_package_raw(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context);
rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel_raw(void);
size_t rpcs3_ios_core_copy_last_installed_path_raw(char* buffer, size_t buffer_size);
}

namespace
{
namespace hostfs = std::filesystem;

std::mutex g_transaction_mutex;
std::string g_transaction_last_path;
thread_local std::string g_transaction_last_path_copy;

size_t copy_string(const std::string& value, char* buffer, size_t buffer_size)
{
    const size_t required = value.size() + 1;
    if (!buffer || !buffer_size)
    {
        return required;
    }
    const size_t copied = std::min(value.size(), buffer_size - 1);
    std::memcpy(buffer, value.data(), copied);
    buffer[copied] = '\0';
    return required;
}

std::string copy_raw_string(size_t (*copy_function)(char*, size_t))
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

hostfs::path normalized_path(std::string value)
{
    while (value.size() > 1 && (value.back() == '/' || value.back() == '\\'))
    {
        value.pop_back();
    }
    return hostfs::path(std::move(value)).lexically_normal();
}

std::uintmax_t saturating_add(std::uintmax_t left, std::uintmax_t right)
{
    const auto maximum = std::numeric_limits<std::uintmax_t>::max();
    return right > maximum - left ? maximum : left + right;
}

std::uintmax_t saturating_multiply(std::uintmax_t value, std::uintmax_t multiplier)
{
    const auto maximum = std::numeric_limits<std::uintmax_t>::max();
    return value && multiplier > maximum / value ? maximum : value * multiplier;
}

std::uintmax_t directory_size(const hostfs::path& root, std::error_code& error)
{
    std::uintmax_t total = 0;
    if (!hostfs::exists(root, error))
    {
        error.clear();
        return 0;
    }

    hostfs::recursive_directory_iterator iterator(
        root,
        hostfs::directory_options::skip_permission_denied,
        error);
    const hostfs::recursive_directory_iterator end;
    while (!error && iterator != end)
    {
        if (iterator->is_regular_file(error))
        {
            total = saturating_add(total, iterator->file_size(error));
        }
        if (error)
        {
            return 0;
        }
        iterator.increment(error);
    }
    return error ? 0 : total;
}

bool copy_tree(const hostfs::path& source, const hostfs::path& destination, std::string* error_message)
{
    std::error_code error;
    hostfs::create_directories(destination, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not create firmware staging directory: " + error.message();
        }
        return false;
    }
    if (!hostfs::exists(source, error))
    {
        return !error;
    }

    hostfs::recursive_directory_iterator iterator(
        source,
        hostfs::directory_options::skip_permission_denied,
        error);
    const hostfs::recursive_directory_iterator end;
    while (!error && iterator != end)
    {
        const hostfs::path relative = hostfs::relative(iterator->path(), source, error);
        if (error)
        {
            break;
        }
        const hostfs::path target = destination / relative;
        if (iterator->is_directory(error))
        {
            hostfs::create_directories(target, error);
        }
        else if (iterator->is_symlink(error))
        {
            hostfs::create_directories(target.parent_path(), error);
            if (!error)
            {
                hostfs::copy_symlink(iterator->path(), target, error);
            }
        }
        else if (iterator->is_regular_file(error))
        {
            hostfs::create_directories(target.parent_path(), error);
            if (!error)
            {
                hostfs::copy_file(
                    iterator->path(),
                    target,
                    hostfs::copy_options::overwrite_existing,
                    error);
            }
        }
        if (error)
        {
            break;
        }
        iterator.increment(error);
    }

    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not copy the existing firmware into staging: " + error.message();
        }
        return false;
    }
    return true;
}

std::vector<unsigned long long> version_components(const std::string& value)
{
    std::vector<unsigned long long> components;
    unsigned long long component = 0;
    bool reading = false;
    for (const unsigned char byte : value)
    {
        if (std::isdigit(byte))
        {
            reading = true;
            const unsigned int digit = byte - '0';
            if (component <= (std::numeric_limits<unsigned long long>::max() - digit) / 10)
            {
                component = component * 10 + digit;
            }
        }
        else if (reading)
        {
            components.push_back(component);
            component = 0;
            reading = false;
        }
    }
    if (reading)
    {
        components.push_back(component);
    }
    while (components.size() > 1 && components.back() == 0)
    {
        components.pop_back();
    }
    return components;
}

bool version_less(const std::string& candidate, const std::string& installed)
{
    std::vector<unsigned long long> left = version_components(candidate);
    std::vector<unsigned long long> right = version_components(installed);
    if (left.empty() || right.empty())
    {
        return false;
    }
    const size_t count = std::max(left.size(), right.size());
    left.resize(count);
    right.resize(count);
    return std::lexicographical_compare(left.begin(), left.end(), right.begin(), right.end());
}

std::string read_pup_version(const char* pup_path)
{
    try
    {
        fs::file file(pup_path);
        if (!file)
        {
            return {};
        }
        pup_object pup(std::move(file));
        if (static_cast<pup_error>(pup) != pup_error::ok)
        {
            return {};
        }
        fs::file version_file = pup.get_file(0x100);
        std::string version = version_file ? version_file.to_string() : std::string{};
        if (const size_t newline = version.find_first_of("\r\n"); newline != std::string::npos)
        {
            version.erase(newline);
        }
        return version;
    }
    catch (...)
    {
        return {};
    }
}

struct transaction_paths
{
    hostfs::path live;
    hostfs::path staging;
    hostfs::path backup;
    hostfs::path marker;
};

transaction_paths make_transaction_paths()
{
    transaction_paths paths;
    paths.live = normalized_path(g_cfg_vfs.get_dev_flash());
    const hostfs::path parent = paths.live.parent_path();
    const std::string stem = paths.live.filename().string();
    paths.staging = parent / (stem + ".ios-installing");
    paths.backup = parent / (stem + ".ios-backup");
    paths.marker = parent / (stem + ".ios-install-transaction");
    return paths;
}

bool remove_tree(const hostfs::path& path, std::string* error_message)
{
    std::error_code error;
    hostfs::remove_all(path, error);
    if (error && error_message)
    {
        *error_message = "Could not remove " + path.string() + ": " + error.message();
    }
    return !error;
}

bool recover_transaction(const transaction_paths& paths, std::string* error_message)
{
    std::error_code error;
    const bool marker_exists = hostfs::exists(paths.marker, error);
    if (error || !marker_exists)
    {
        return !error;
    }

    const bool live_exists = hostfs::exists(paths.live, error);
    if (error)
    {
        return false;
    }
    const bool backup_exists = hostfs::exists(paths.backup, error);
    if (error)
    {
        return false;
    }

    if (!live_exists && backup_exists)
    {
        hostfs::rename(paths.backup, paths.live, error);
        if (error)
        {
            if (error_message)
            {
                *error_message = "Could not restore the firmware backup: " + error.message();
            }
            return false;
        }
    }
    else if (live_exists && backup_exists)
    {
        if (!remove_tree(paths.backup, error_message))
        {
            return false;
        }
    }

    if (!remove_tree(paths.staging, error_message))
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
    return true;
}

bool write_marker(const transaction_paths& paths, std::string* error_message)
{
    std::ofstream marker(paths.marker, std::ios::binary | std::ios::trunc);
    marker << "RPCS3Core firmware transaction v1\n"
           << "live=" << paths.live.string() << "\n"
           << "staging=" << paths.staging.string() << "\n"
           << "backup=" << paths.backup.string() << "\n";
    marker.flush();
    if (!marker)
    {
        if (error_message)
        {
            *error_message = "Could not create the firmware recovery marker.";
        }
        return false;
    }
    return true;
}

bool has_transaction_space(
    const transaction_paths& paths,
    const char* pup_path,
    std::string* error_message)
{
    std::error_code error;
    const std::uintmax_t live_size = directory_size(paths.live, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not measure the existing firmware tree: " + error.message();
        }
        return false;
    }

    const std::uintmax_t pup_size = hostfs::file_size(hostfs::path(pup_path), error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not measure the selected firmware file: " + error.message();
        }
        return false;
    }

    const hostfs::space_info space = hostfs::space(paths.live.parent_path(), error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Could not determine available firmware staging space: " + error.message();
        }
        return false;
    }

    constexpr std::uintmax_t one_gibibyte = 1024ull * 1024ull * 1024ull;
    constexpr std::uintmax_t safety_margin = 256ull * 1024ull * 1024ull;
    const std::uintmax_t expansion = std::max(saturating_multiply(pup_size, 4), one_gibibyte);
    const std::uintmax_t required = saturating_add(
        saturating_add(live_size, expansion), safety_margin);
    if (space.available < required)
    {
        if (error_message)
        {
            *error_message = "Firmware staging requires at least " + std::to_string(required) +
                " free bytes, but only " + std::to_string(space.available) + " are available.";
        }
        return false;
    }
    return true;
}

class dev_flash_redirect final
{
public:
    explicit dev_flash_redirect(const hostfs::path& path)
        : m_original(g_cfg_vfs.dev_flash)
    {
        g_cfg_vfs.dev_flash.set(path.string() + "/");
        vfs::unmount("/dev_flash");
    }

    ~dev_flash_redirect()
    {
        restore();
    }

    void restore()
    {
        if (!m_restored)
        {
            g_cfg_vfs.dev_flash.set(m_original);
            vfs::unmount("/dev_flash");
            m_restored = true;
        }
    }

private:
    std::string m_original;
    bool m_restored = false;
};

void remount_live_dev_flash(const transaction_paths& paths)
{
    vfs::unmount("/dev_flash");
    (void)vfs::mount("/dev_flash", paths.live.string());
    try
    {
        Emu.Init();
    }
    catch (...)
    {
        // The caller's primary transaction error remains more actionable. The
        // next framework initialization will rebuild VFS state from live paths.
    }
}

bool commit_staging(const transaction_paths& paths, std::string* error_message)
{
    std::error_code error;
    if (!remove_tree(paths.backup, error_message))
    {
        return false;
    }

    const bool had_live = hostfs::exists(paths.live, error);
    if (error)
    {
        return false;
    }
    if (had_live)
    {
        hostfs::rename(paths.live, paths.backup, error);
        if (error)
        {
            if (error_message)
            {
                *error_message = "Could not move the current firmware to backup: " + error.message();
            }
            return false;
        }
    }

    hostfs::rename(paths.staging, paths.live, error);
    if (error)
    {
        if (had_live)
        {
            std::error_code rollback_error;
            hostfs::rename(paths.backup, paths.live, rollback_error);
        }
        if (error_message)
        {
            *error_message = "Could not activate the staged firmware: " + error.message();
        }
        return false;
    }

    if (!remove_tree(paths.backup, error_message))
    {
        // The new live tree is already active. Retaining the backup is safe and
        // the marker will let the next operation finish cleanup deterministically.
        return false;
    }
    hostfs::remove(paths.marker, error);
    if (error)
    {
        if (error_message)
        {
            *error_message = "Firmware was activated, but its recovery marker could not be removed: " + error.message();
        }
        return false;
    }
    return true;
}

void set_transaction_last_path(std::string path)
{
    std::lock_guard lock(g_transaction_mutex);
    g_transaction_last_path = std::move(path);
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_install_firmware_base(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    if (!pup_path || !*pup_path)
    {
        return rpcs3_ios_core_install_firmware_raw(
            pup_path, allow_downgrade, overwrite_existing, callback, context);
    }

    std::lock_guard transaction_lock(g_transaction_mutex);
    g_transaction_last_path.clear();
    const transaction_paths paths = make_transaction_paths();
    std::string error;
    if (!recover_transaction(paths, &error))
    {
        rpcs3::ios::set_core_last_error(
            error.empty() ? "A previous firmware transaction could not be recovered." : error);
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    const std::string installed_version = rpcs3::utils::get_firmware_version();
    const std::string candidate_version = read_pup_version(pup_path);
    if (!allow_downgrade && !installed_version.empty() && !candidate_version.empty() &&
        version_less(candidate_version, installed_version))
    {
        rpcs3::ios::set_core_last_error(
            "Refusing to downgrade installed firmware " + installed_version +
            " to " + candidate_version + ".");
        return RPCS3_IOS_CORE_UNSUPPORTED;
    }

    if (!has_transaction_space(paths, pup_path, &error))
    {
        rpcs3::ios::set_core_last_error(
            error.empty() ? "There is not enough storage for transactional firmware installation." : error);
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    if (!remove_tree(paths.staging, &error) || !copy_tree(paths.live, paths.staging, &error) ||
        !write_marker(paths, &error))
    {
        (void)remove_tree(paths.staging, nullptr);
        rpcs3::ios::set_core_last_error(
            error.empty() ? "Could not prepare the firmware staging tree." : error);
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    rpcs3_ios_core_result result = RPCS3_IOS_CORE_PLATFORM_ERROR;
    {
        dev_flash_redirect redirect(paths.staging);
        // Numeric downgrade validation was performed above. Let the raw parser
        // skip its lexical comparison while retaining its overwrite checks.
        result = rpcs3_ios_core_install_firmware_raw(
            pup_path, 1, overwrite_existing, callback, context);
        redirect.restore();
    }

    if (result != RPCS3_IOS_CORE_SUCCESS)
    {
        (void)remove_tree(paths.staging, nullptr);
        std::error_code marker_error;
        hostfs::remove(paths.marker, marker_error);
        remount_live_dev_flash(paths);
        return result;
    }

    if (!commit_staging(paths, &error))
    {
        remount_live_dev_flash(paths);
        rpcs3::ios::set_core_last_error(
            error.empty() ? "The staged firmware could not be committed safely." : error);
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    remount_live_dev_flash(paths);
    g_transaction_last_path = paths.live.string();
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_install_package_base(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    const rpcs3_ios_core_result result =
        rpcs3_ios_core_install_package_raw(package_path, callback, context);
    std::lock_guard lock(g_transaction_mutex);
    g_transaction_last_path = result == RPCS3_IOS_CORE_SUCCESS
        ? copy_raw_string(rpcs3_ios_core_copy_last_installed_path_raw)
        : std::string{};
    return result;
}

rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel_base(void)
{
    return rpcs3_ios_core_request_installation_cancel_raw();
}

size_t rpcs3_ios_core_copy_last_installed_path_base(char* buffer, size_t buffer_size)
{
    {
        std::lock_guard lock(g_transaction_mutex);
        g_transaction_last_path_copy = g_transaction_last_path;
    }
    return copy_string(g_transaction_last_path_copy, buffer, buffer_size);
}
}
