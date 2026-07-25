#include "IOSCoreInstaller.h"
#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#include "Crypto/unpkg.h"
#include "Crypto/unself.h"
#include "Emu/System.h"
#include "Emu/VFS.h"
#include "Emu/system_utils.hpp"
#include "Emu/vfs_config.h"
#include "Loader/PUP.h"
#include "Loader/TAR.h"
#include "Utilities/File.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <deque>
#include <exception>
#include <mutex>
#include <string>
#include <thread>

namespace
{
std::mutex g_operation_mutex;
std::mutex g_operation_state_mutex;
std::atomic_bool g_cancel_requested = false;
std::atomic<package_reader*> g_active_package_reader = nullptr;
std::thread::id g_operation_thread;
std::string g_last_installed_path;
thread_local std::string g_firmware_version;
thread_local std::string g_installed_path_copy;

class operation_scope
{
public:
    operation_scope()
    {
        std::lock_guard lock(g_operation_state_mutex);
        g_operation_thread = std::this_thread::get_id();
        g_cancel_requested = false;
        g_active_package_reader = nullptr;
    }

    ~operation_scope()
    {
        g_active_package_reader = nullptr;
        std::lock_guard lock(g_operation_state_mutex);
        g_operation_thread = {};
    }
};

void set_last_installed_path(std::string path)
{
    std::lock_guard lock(g_operation_state_mutex);
    g_last_installed_path = std::move(path);
}

std::string get_last_installed_path()
{
    std::lock_guard lock(g_operation_state_mutex);
    return g_last_installed_path;
}

void report_progress(
    rpcs3_ios_installation_progress_callback callback,
    void* context,
    rpcs3_ios_installation_kind kind,
    rpcs3_ios_installation_stage stage,
    uint32_t completed,
    uint32_t total,
    const std::string& detail)
{
    if (callback)
    {
        callback(kind, stage, completed, total, detail.c_str(), context);
    }
}

rpcs3_ios_core_result require_stopped_core()
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }

    const rpcs3_ios_emulator_state state = rpcs3_ios_core_emulator_state();
    if (state != RPCS3_IOS_EMULATOR_STOPPED)
    {
        rpcs3::ios::set_core_last_error("Installation requires emulation to be fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result pup_validation_result(const pup_object& pup)
{
    switch (static_cast<pup_error>(pup))
    {
    case pup_error::ok:
        return RPCS3_IOS_CORE_SUCCESS;
    case pup_error::header_read:
        rpcs3::ios::set_core_last_error("The selected firmware file is empty or its header could not be read.");
        break;
    case pup_error::header_magic:
        rpcs3::ios::set_core_last_error("The selected file is not a PlayStation 3 PUP firmware file.");
        break;
    case pup_error::expected_size:
        rpcs3::ios::set_core_last_error("The selected firmware file is incomplete.");
        break;
    case pup_error::hash_mismatch:
        rpcs3::ios::set_core_last_error("The selected firmware file failed its content hash check.");
        break;
    case pup_error::header_file_count:
    case pup_error::file_entries:
    case pup_error::stream:
        rpcs3::ios::set_core_last_error(
            pup.get_formatted_error().empty()
                ? "The selected firmware file is corrupted."
                : "The selected firmware file is corrupted: " + pup.get_formatted_error());
        break;
    }
    return RPCS3_IOS_CORE_PLATFORM_ERROR;
}

size_t copy_string(const std::string& value, char* buffer, size_t buffer_size)
{
    const size_t required = value.size() + 1;
    if (!buffer || buffer_size == 0)
    {
        return required;
    }

    const size_t copied = std::min(value.size(), buffer_size - 1);
    std::memcpy(buffer, value.data(), copied);
    buffer[copied] = '\0';
    return required;
}
}

namespace rpcs3::ios
{
void shutdown_core_installer()
{
    g_cancel_requested = true;
    if (package_reader* reader = g_active_package_reader.load())
    {
        reader->abort_extract();
    }

    {
        std::lock_guard state_lock(g_operation_state_mutex);
        if (g_operation_thread == std::this_thread::get_id())
        {
            return;
        }
    }

    // A synchronous installation is owned by its caller. Taking and releasing
    // this mutex waits until it has left RPCS3's VFS/package state.
    std::lock_guard operation_lock(g_operation_mutex);
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_request_installation_cancel(void)
{
    g_cancel_requested = true;
    if (package_reader* reader = g_active_package_reader.load())
    {
        reader->abort_extract();
    }
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_install_firmware(
    const char* pup_path,
    uint8_t allow_downgrade,
    uint8_t overwrite_existing,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    const rpcs3_ios_core_result state_result = require_stopped_core();
    if (state_result != RPCS3_IOS_CORE_SUCCESS)
    {
        return state_result;
    }
    if (!pup_path || !*pup_path)
    {
        rpcs3::ios::set_core_last_error("A non-empty PS3UPDAT.PUP path is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::unique_lock operation_lock(g_operation_mutex, std::try_to_lock);
    if (!operation_lock.owns_lock())
    {
        rpcs3::ios::set_core_last_error("Another RPCS3Core installation operation is already active.");
        return RPCS3_IOS_CORE_BUSY;
    }
    operation_scope operation;

    try
    {
        report_progress(callback, context, RPCS3_IOS_INSTALLATION_FIRMWARE,
            RPCS3_IOS_INSTALLATION_VALIDATING, 0, 1, "Validating PlayStation 3 firmware.");

        fs::file pup_file(pup_path);
        if (!pup_file)
        {
            rpcs3::ios::set_core_last_error("The selected firmware file could not be opened.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        pup_object pup(std::move(pup_file));
        if (const rpcs3_ios_core_result result = pup_validation_result(pup); result != RPCS3_IOS_CORE_SUCCESS)
        {
            return result;
        }

        fs::file update_files_file = pup.get_file(0x300);
        const uint64_t update_files_size = update_files_file ? update_files_file.size() : 0;
        if (!update_files_size)
        {
            rpcs3::ios::set_core_last_error("The firmware package database is missing.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        fs::device_stat device_stat{};
        if (!fs::statfs(g_cfg_vfs.get_dev_flash(), device_stat))
        {
            rpcs3::ios::set_core_last_error("Available space for dev_flash could not be determined.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }
        if (device_stat.avail_free < update_files_size)
        {
            rpcs3::ios::set_core_last_error("There is not enough free storage to install the selected firmware.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        tar_object update_files(update_files_file);
        auto update_filenames = update_files.get_filenames();
        update_filenames.erase(std::remove_if(update_filenames.begin(), update_filenames.end(),
            [](const std::string& filename)
            {
                return filename.find("dev_flash_") == std::string::npos;
            }), update_filenames.end());
        if (update_filenames.empty())
        {
            rpcs3::ios::set_core_last_error("The firmware contains no dev_flash packages.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        fs::file version_file = pup.get_file(0x100);
        std::string version = version_file ? version_file.to_string() : std::string{};
        if (const size_t newline = version.find('\n'); newline != std::string::npos)
        {
            version.erase(newline);
        }
        if (version.empty())
        {
            rpcs3::ios::set_core_last_error("The firmware version could not be read.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        const std::string installed_version = rpcs3::utils::get_firmware_version();
        if (!installed_version.empty())
        {
            if (!overwrite_existing)
            {
                rpcs3::ios::set_core_last_error(
                    "Firmware " + installed_version + " is already installed. Enable overwrite to replace it.");
                return RPCS3_IOS_CORE_BUSY;
            }
            if (!allow_downgrade && version < installed_version)
            {
                rpcs3::ios::set_core_last_error(
                    "Refusing to downgrade installed firmware " + installed_version + " to " + version + ".");
                return RPCS3_IOS_CORE_UNSUPPORTED;
            }
        }

        if (!vfs::mount("/dev_flash", g_cfg_vfs.get_dev_flash()))
        {
            rpcs3::ios::set_core_last_error("RPCS3 could not mount the dev_flash installation target.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        const uint32_t total = static_cast<uint32_t>(update_filenames.size());
        report_progress(callback, context, RPCS3_IOS_INSTALLATION_FIRMWARE,
            RPCS3_IOS_INSTALLATION_EXTRACTING, 0, total, "Installing firmware " + version + ".");

        uint32_t completed = 0;
        for (const std::string& update_filename : update_filenames)
        {
            if (g_cancel_requested.load())
            {
                rpcs3::ios::set_core_last_error("Firmware installation was cancelled. Partially extracted files may remain.");
                return RPCS3_IOS_CORE_CANCELLED;
            }

            auto update_stream = update_files.get_file(update_filename);
            if (!update_stream)
            {
                rpcs3::ios::set_core_last_error("A firmware dev_flash package could not be opened.");
                return RPCS3_IOS_CORE_PLATFORM_ERROR;
            }
            if (update_stream->m_file_handler)
            {
                update_stream->m_file_handler->handle_file_op(
                    *update_stream, 0, update_stream->get_size(umax), nullptr);
            }

            fs::file encrypted_package = fs::make_stream(std::move(update_stream->data));
            SCEDecrypter decrypter(encrypted_package);
            decrypter.LoadHeaders();
            decrypter.LoadMetadata(SCEPKG_ERK, SCEPKG_RIV);
            decrypter.DecryptData();

            auto decrypted_files = decrypter.MakeFile();
            if (decrypted_files.size() < 3)
            {
                rpcs3::ios::set_core_last_error("A firmware package could not be decrypted or decompressed.");
                return RPCS3_IOS_CORE_PLATFORM_ERROR;
            }

            tar_object dev_flash_tar(decrypted_files[2]);
            if (!dev_flash_tar.extract())
            {
                rpcs3::ios::set_core_last_error("A decrypted dev_flash archive could not be extracted.");
                return RPCS3_IOS_CORE_PLATFORM_ERROR;
            }

            ++completed;
            report_progress(callback, context, RPCS3_IOS_INSTALLATION_FIRMWARE,
                RPCS3_IOS_INSTALLATION_EXTRACTING, completed, total, update_filename);
        }

        if (g_cancel_requested.load())
        {
            rpcs3::ios::set_core_last_error("Firmware installation was cancelled before finalization.");
            return RPCS3_IOS_CORE_CANCELLED;
        }

        report_progress(callback, context, RPCS3_IOS_INSTALLATION_FIRMWARE,
            RPCS3_IOS_INSTALLATION_FINALIZING, total, total, "Refreshing RPCS3 virtual filesystem state.");
        Emu.Init();
        set_last_installed_path(g_cfg_vfs.get_dev_flash());
        rpcs3::ios::set_core_last_error({});
        report_progress(callback, context, RPCS3_IOS_INSTALLATION_FIRMWARE,
            RPCS3_IOS_INSTALLATION_COMPLETE, total, total, "Installed firmware " + version + ".");
        return RPCS3_IOS_CORE_SUCCESS;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Firmware installation failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Firmware installation failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_install_package(
    const char* package_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    const rpcs3_ios_core_result state_result = require_stopped_core();
    if (state_result != RPCS3_IOS_CORE_SUCCESS)
    {
        return state_result;
    }
    if (!package_path || !*package_path)
    {
        rpcs3::ios::set_core_last_error("A non-empty PKG path is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::unique_lock operation_lock(g_operation_mutex, std::try_to_lock);
    if (!operation_lock.owns_lock())
    {
        rpcs3::ios::set_core_last_error("Another RPCS3Core installation operation is already active.");
        return RPCS3_IOS_CORE_BUSY;
    }
    operation_scope operation;

    try
    {
        report_progress(callback, context, RPCS3_IOS_INSTALLATION_PACKAGE,
            RPCS3_IOS_INSTALLATION_VALIDATING, 0, 100, "Validating PlayStation 3 package.");

        std::deque<package_reader> readers;
        readers.emplace_back(package_path);
        if (!readers.front().is_valid())
        {
            rpcs3::ios::set_core_last_error("The selected PKG is invalid or corrupted.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        g_active_package_reader = &readers.front();
        std::deque<std::string> bootable_paths;
        package_install_result install_result{};
        std::atomic_bool extraction_finished = false;
        std::exception_ptr extraction_error;

        std::jthread extraction([&]
        {
            try
            {
                install_result = package_reader::extract_data(readers, bootable_paths);
            }
            catch (...)
            {
                extraction_error = std::current_exception();
            }
            extraction_finished.store(true, std::memory_order_release);
        });

        while (!extraction_finished.load(std::memory_order_acquire))
        {
            if (g_cancel_requested.load())
            {
                readers.front().abort_extract();
            }

            const uint32_t progress = static_cast<uint32_t>(std::clamp(readers.front().get_progress(100), 0, 100));
            report_progress(callback, context, RPCS3_IOS_INSTALLATION_PACKAGE,
                RPCS3_IOS_INSTALLATION_EXTRACTING, progress, 100, package_path);
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        extraction.join();
        g_active_package_reader = nullptr;

        if (extraction_error)
        {
            std::rethrow_exception(extraction_error);
        }

        if (g_cancel_requested.load() ||
            readers.front().get_result() == package_reader::result::aborted ||
            readers.front().get_result() == package_reader::result::aborted_dirty)
        {
            rpcs3::ios::set_core_last_error("Package installation was cancelled. Partially extracted files may remain.");
            return RPCS3_IOS_CORE_CANCELLED;
        }

        if (install_result.error == package_install_result::error_type::app_version)
        {
            std::string error = "The package does not match the currently installed application version.";
            if (!install_result.version.expected.empty() || !install_result.version.found.empty())
            {
                error += " Expected: " + install_result.version.expected + "; installed: " + install_result.version.found + ".";
            }
            rpcs3::ios::set_core_last_error(std::move(error));
            return RPCS3_IOS_CORE_UNSUPPORTED;
        }
        if (install_result.error != package_install_result::error_type::no_error ||
            readers.front().get_result() != package_reader::result::success)
        {
            rpcs3::ios::set_core_last_error("RPCS3 could not extract the selected package.");
            return RPCS3_IOS_CORE_PLATFORM_ERROR;
        }

        std::string installed_path;
        if (!bootable_paths.empty())
        {
            installed_path = bootable_paths.front();
            if (!installed_path.empty())
            {
                Emu.AddGame(installed_path);
            }
        }
        set_last_installed_path(installed_path);

        rpcs3::ios::set_core_last_error({});
        report_progress(callback, context, RPCS3_IOS_INSTALLATION_PACKAGE,
            RPCS3_IOS_INSTALLATION_COMPLETE, 100, 100,
            installed_path.empty() ? "Package installation completed." : installed_path);
        return RPCS3_IOS_CORE_SUCCESS;
    }
    catch (const std::exception& exception)
    {
        g_active_package_reader = nullptr;
        rpcs3::ios::set_core_last_error(std::string("Package installation failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        g_active_package_reader = nullptr;
        rpcs3::ios::set_core_last_error("Package installation failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

size_t rpcs3_ios_core_copy_firmware_version(char* buffer, size_t buffer_size)
{
    g_firmware_version = rpcs3::utils::get_firmware_version();
    return copy_string(g_firmware_version, buffer, buffer_size);
}

size_t rpcs3_ios_core_copy_last_installed_path(char* buffer, size_t buffer_size)
{
    g_installed_path_copy = get_last_installed_path();
    return copy_string(g_installed_path_copy, buffer, buffer_size);
}
}
