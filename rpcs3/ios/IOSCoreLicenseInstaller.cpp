#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#include "Emu/System.h"
#include "Emu/system_utils.hpp"
#include "Utilities/File.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace
{
thread_local std::string g_license_path_copy;
std::string g_last_license_path;

std::string lower_extension(std::string_view path)
{
    const std::size_t slash = path.find_last_of("/\\");
    const std::size_t dot = path.find_last_of('.');
    if (dot == std::string_view::npos || (slash != std::string_view::npos && dot < slash) || dot + 1 >= path.size())
    {
        return {};
    }

    std::string extension(path.substr(dot + 1));
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char value)
    {
        return static_cast<char>(std::tolower(value));
    });
    return extension;
}

std::string filename_without_extension(std::string_view path)
{
    const std::size_t slash = path.find_last_of("/\\");
    const std::size_t begin = slash == std::string_view::npos ? 0 : slash + 1;
    const std::size_t dot = path.find_last_of('.');
    const std::size_t end = dot == std::string_view::npos || dot < begin ? path.size() : dot;
    return std::string(path.substr(begin, end - begin));
}

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

void report_progress(
    rpcs3_ios_installation_progress_callback callback,
    void* context,
    rpcs3_ios_installation_stage stage,
    uint32_t completed,
    uint32_t total,
    const std::string& detail)
{
    if (callback)
    {
        callback(
            RPCS3_IOS_INSTALLATION_PACKAGE,
            stage,
            completed,
            total,
            detail.c_str(),
            context);
    }
}
}

extern "C"
{
uint8_t rpcs3_ios_core_is_license_path(const char* path)
{
    if (!path || !*path)
    {
        return 0;
    }

    const std::string extension = lower_extension(path);
    return extension == "rap" || extension == "edat";
}

rpcs3_ios_core_result rpcs3_ios_core_install_license_base(
    const char* license_path,
    rpcs3_ios_installation_progress_callback callback,
    void* context)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (rpcs3_ios_core_emulator_state() != RPCS3_IOS_EMULATOR_STOPPED)
    {
        rpcs3::ios::set_core_last_error("License installation requires emulation to be fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }
    if (!license_path || !*license_path)
    {
        rpcs3::ios::set_core_last_error("A non-empty RAP or EDAT path is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    const std::string extension = lower_extension(license_path);
    if (extension != "rap" && extension != "edat")
    {
        rpcs3::ios::set_core_last_error("The selected license file must have a .rap or .edat extension.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    const std::string stem = filename_without_extension(license_path);
    if (stem.empty())
    {
        rpcs3::ios::set_core_last_error("The selected license file has no usable filename.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    report_progress(callback, context, RPCS3_IOS_INSTALLATION_VALIDATING, 0, 1,
        "Validating PlayStation 3 license file.");

    fs::file source(license_path);
    if (!source)
    {
        rpcs3::ios::set_core_last_error("The selected RAP or EDAT file could not be opened.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    if (source.size() < 0x10)
    {
        rpcs3::ios::set_core_last_error("The selected RAP or EDAT file is too small to be valid.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    const std::string user = Emu.GetUsr();
    if (user.empty())
    {
        rpcs3::ios::set_core_last_error("RPCS3 has no active user for license installation.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    const std::string exdata = rpcs3::utils::get_hdd0_dir() + "/home/" + user + "/exdata";
    if (!fs::is_dir(exdata) && !fs::create_path(exdata))
    {
        rpcs3::ios::set_core_last_error("RPCS3 could not create the current user's exdata directory.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    const std::string destination = exdata + "/" + stem + "." + extension;
    fs::pending_file pending(destination);
    if (!pending.file)
    {
        rpcs3::ios::set_core_last_error("RPCS3 could not create an atomic destination for the license file.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    report_progress(callback, context, RPCS3_IOS_INSTALLATION_EXTRACTING, 0, 1,
        "Copying license into the current user's exdata directory.");

    const std::vector<u8> contents = source.to_vector<u8>();
    source.close();
    if (contents.size() < 0x10 || pending.file.write(contents.data(), contents.size()) != contents.size())
    {
        rpcs3::ios::set_core_last_error("RPCS3 could not write the complete RAP or EDAT file.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    report_progress(callback, context, RPCS3_IOS_INSTALLATION_FINALIZING, 1, 1,
        "Committing license file atomically.");
    if (!pending.commit())
    {
        rpcs3::ios::set_core_last_error("RPCS3 could not atomically activate the RAP or EDAT file.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }

    g_last_license_path = destination;
    rpcs3::ios::set_core_last_error({});
    report_progress(callback, context, RPCS3_IOS_INSTALLATION_COMPLETE, 1, 1, destination);
    return RPCS3_IOS_CORE_SUCCESS;
}

size_t rpcs3_ios_core_copy_last_installed_license_path(char* buffer, size_t buffer_size)
{
    g_license_path_copy = g_last_license_path;
    return copy_string(g_license_path_copy, buffer, buffer_size);
}
}
