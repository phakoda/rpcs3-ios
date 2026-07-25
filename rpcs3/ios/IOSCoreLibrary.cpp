#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#include "Emu/System.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace
{
std::mutex g_library_mutex;

bool library_mutation_allowed()
{
    return Emulator::IsAvailable() && Emu.IsStopped(true);
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

std::vector<std::string> directory_snapshot()
{
    std::vector<std::string> result;
    if (!Emulator::IsAvailable())
    {
        return result;
    }

    const auto directories = Emu.GetGameDirs();
    result.assign(directories.begin(), directories.end());
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
        *added_games = Emu.AddGamesFromDir(path);
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
    return directory_snapshot().size();
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
    const auto directories = directory_snapshot();
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
