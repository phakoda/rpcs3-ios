#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#import <Foundation/Foundation.h>

#include "Emu/System.h"
#include "Utilities/File.h"

#include <algorithm>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace
{
std::mutex g_library_mutex;
NSString* const game_directories_key = @"RPCS3Core.Library.GameDirectories";

bool library_mutation_allowed()
{
    return Emulator::IsAvailable() && Emu.IsStopped(true);
}

std::string normalized_directory(std::string path)
{
    while (path.size() > 1 && (path.back() == '/' || path.back() == '\\'))
    {
        path.pop_back();
    }
    return path;
}

NSString* ns_utf8(const std::string& value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

std::string utf8_string(NSString* value)
{
    const char* bytes = value.UTF8String;
    return bytes ? std::string(bytes) : std::string{};
}

std::vector<std::string> load_registered_directories()
{
    NSArray<NSString*>* values = [NSUserDefaults.standardUserDefaults arrayForKey:game_directories_key];
    std::vector<std::string> result;
    result.reserve(values.count);
    for (NSString* value in values)
    {
        std::string path = normalized_directory(utf8_string(value));
        if (!path.empty() && std::find(result.begin(), result.end(), path) == result.end())
        {
            result.emplace_back(std::move(path));
        }
    }
    return result;
}

void save_registered_directories(const std::vector<std::string>& directories)
{
    NSMutableArray<NSString*>* values = [NSMutableArray arrayWithCapacity:directories.size()];
    for (const std::string& path : directories)
    {
        [values addObject:ns_utf8(path)];
    }
    [NSUserDefaults.standardUserDefaults setObject:values forKey:game_directories_key];
}

bool register_directory(const std::string& path)
{
    std::vector<std::string> directories = load_registered_directories();
    if (std::find(directories.begin(), directories.end(), path) != directories.end())
    {
        return false;
    }
    directories.push_back(path);
    save_registered_directories(directories);
    return true;
}

bool unregister_directory(const std::string& path)
{
    std::vector<std::string> directories = load_registered_directories();
    const auto iterator = std::remove(directories.begin(), directories.end(), path);
    if (iterator == directories.end())
    {
        return false;
    }
    directories.erase(iterator, directories.end());
    save_registered_directories(directories);
    return true;
}

std::vector<std::pair<std::string, std::string>> game_snapshot()
{
    std::vector<std::pair<std::string, std::string>> result;
    if (!Emulator::IsAvailable())
    {
        return result;
    }

    const auto games = Emu.GetGamesConfig().get_games();
    result.reserve(games.size());
    for (const auto& [title_id, path] : games)
    {
        result.emplace_back(title_id, path);
    }
    return result;
}

bool copy_value(
    const std::string& value,
    char* buffer,
    size_t buffer_size,
    size_t* required_size)
{
    if (!required_size)
    {
        return false;
    }

    *required_size = value.size() + 1;
    if (!buffer || buffer_size < *required_size)
    {
        return false;
    }

    std::memcpy(buffer, value.c_str(), *required_size);
    return true;
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_add_game_directory(const char* path, uint32_t* added_games)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!path || !*path || !added_games)
    {
        rpcs3::ios::set_core_last_error("A non-empty game directory and added-game output are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!library_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Game directories can be scanned only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_library_mutex);
    try
    {
        const std::string directory = normalized_directory(path);
        if (directory.empty() || !fs::is_dir(directory))
        {
            rpcs3::ios::set_core_last_error("The selected game-library path is not a readable directory.");
            return RPCS3_IOS_CORE_INVALID_ARGUMENT;
        }

        *added_games = Emu.AddGamesFromDir(directory);
        register_directory(directory);
        rpcs3::ios::set_core_last_error({});
        return RPCS3_IOS_CORE_SUCCESS;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Game-directory scan failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Game-directory scan failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_remove_game_directory(
    const char* path,
    uint8_t remove_library_entries,
    uint32_t* removed_games)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!path || !*path || !removed_games)
    {
        rpcs3::ios::set_core_last_error("A non-empty registered directory and removed-game output are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!library_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Game directories can be removed only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_library_mutex);
    try
    {
        const std::string directory = normalized_directory(path);
        *removed_games = remove_library_entries
            ? Emu.RemoveGamesFromDir(directory, {}, true)
            : 0;
        if (!unregister_directory(directory))
        {
            rpcs3::ios::set_core_last_error("The requested game directory was not registered.");
            return RPCS3_IOS_CORE_INVALID_ARGUMENT;
        }

        rpcs3::ios::set_core_last_error({});
        return RPCS3_IOS_CORE_SUCCESS;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Removing the game directory failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Removing the game directory failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_rescan_game_directories(uint32_t* added_games)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!added_games)
    {
        rpcs3::ios::set_core_last_error("An added-game output is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!library_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Game directories can be rescanned only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_library_mutex);
    try
    {
        uint32_t total = 0;
        for (const std::string& directory : load_registered_directories())
        {
            if (fs::is_dir(directory))
            {
                total += Emu.AddGamesFromDir(directory);
            }
        }
        *added_games = total;
        rpcs3::ios::set_core_last_error({});
        return RPCS3_IOS_CORE_SUCCESS;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Game-directory rescan failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Game-directory rescan failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_add_game(const char* path)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!path || !*path)
    {
        rpcs3::ios::set_core_last_error("A non-empty game path is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!library_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Games can be added only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_library_mutex);
    try
    {
        const game_boot_result result = Emu.AddGame(path);
        if (result == game_boot_result::no_errors || result == game_boot_result::already_added)
        {
            rpcs3::ios::set_core_last_error({});
            return RPCS3_IOS_CORE_SUCCESS;
        }

        rpcs3::ios::set_core_last_error("RPCS3 did not recognize the selected path as an installable game.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Adding the game failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Adding the game failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

rpcs3_ios_core_result rpcs3_ios_core_remove_game(const char* title_id)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!title_id || !*title_id)
    {
        rpcs3::ios::set_core_last_error("A non-empty title ID is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!library_mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("Games can be removed only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_library_mutex);
    try
    {
        const game_boot_result result = Emu.RemoveGameFromYml(title_id);
        if (result == game_boot_result::no_errors)
        {
            rpcs3::ios::set_core_last_error({});
            return RPCS3_IOS_CORE_SUCCESS;
        }

        rpcs3::ios::set_core_last_error("The requested title ID was not present in the RPCS3 game library.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (const std::exception& exception)
    {
        rpcs3::ios::set_core_last_error(std::string("Removing the game failed: ") + exception.what());
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    catch (...)
    {
        rpcs3::ios::set_core_last_error("Removing the game failed with an unknown exception.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
}

size_t rpcs3_ios_core_game_count(void)
{
    std::lock_guard lock(g_library_mutex);
    return game_snapshot().size();
}

rpcs3_ios_core_result rpcs3_ios_core_copy_game(
    size_t index,
    char* title_id,
    size_t title_id_size,
    size_t* title_id_required,
    char* path,
    size_t path_size,
    size_t* path_required)
{
    if (!title_id_required || !path_required)
    {
        rpcs3::ios::set_core_last_error("Both required-size outputs are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_library_mutex);
    const auto games = game_snapshot();
    if (index >= games.size())
    {
        rpcs3::ios::set_core_last_error("The requested game-library index is out of range.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    const bool copied_title = copy_value(games[index].first, title_id, title_id_size, title_id_required);
    const bool copied_path = copy_value(games[index].second, path, path_size, path_required);
    if (!copied_title || !copied_path)
    {
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

size_t rpcs3_ios_core_game_directory_count(void)
{
    std::lock_guard lock(g_library_mutex);
    return load_registered_directories().size();
}

rpcs3_ios_core_result rpcs3_ios_core_copy_game_directory(
    size_t index,
    char* path,
    size_t path_size,
    size_t* path_required)
{
    if (!path_required)
    {
        rpcs3::ios::set_core_last_error("A required-size output is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_library_mutex);
    const auto directories = load_registered_directories();
    if (index >= directories.size())
    {
        rpcs3::ios::set_core_last_error("The requested game-directory index is out of range.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    if (!copy_value(directories[index], path, path_size, path_required))
    {
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}
}
