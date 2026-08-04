#include "IOSCoreEmulator.h"
#include "IOSCoreOperations.h"
#include "RPCS3Core.h"

#include <string>

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_add_game_directory_base(const char* path, uint32_t* added_games);
rpcs3_ios_core_result rpcs3_ios_core_remove_game_directory_base(
    const char* path, uint8_t remove_library_entries, uint32_t* removed_games);
rpcs3_ios_core_result rpcs3_ios_core_rescan_game_directories_base(uint32_t* added_games);
rpcs3_ios_core_result rpcs3_ios_core_prune_missing_game_directories_base(uint32_t* removed_directories);
rpcs3_ios_core_result rpcs3_ios_core_clear_game_directories_base(
    uint8_t remove_library_entries, uint32_t* removed_games);
rpcs3_ios_core_result rpcs3_ios_core_add_game_base(const char* path);
rpcs3_ios_core_result rpcs3_ios_core_remove_game_base(const char* title_id);
rpcs3_ios_core_result rpcs3_ios_core_set_configuration_base(const rpcs3_ios_configuration* configuration);
rpcs3_ios_core_result rpcs3_ios_core_reset_configuration_base(void);
rpcs3_ios_core_result rpcs3_ios_core_set_midi_assignment_base(
    uint32_t slot, uint32_t type, const char* source_name);
rpcs3_ios_core_result rpcs3_ios_core_clear_midi_assignment_base(uint32_t slot);
rpcs3_ios_core_result rpcs3_ios_core_clear_all_midi_assignments_base(void);
}

namespace
{
template <typename Function>
rpcs3_ios_core_result run_mutation(rpcs3::ios::core_operation operation, Function&& function)
{
    std::string error;
    rpcs3::ios::core_operation_scope scope(operation, &error);
    if (!scope)
    {
        rpcs3::ios::set_core_last_error(std::move(error));
        return RPCS3_IOS_CORE_BUSY;
    }
    return function();
}
}

extern "C"
{
rpcs3_ios_core_result rpcs3_ios_core_add_game_directory(const char* path, uint32_t* added_games)
{
    if (added_games)
    {
        *added_games = 0;
    }
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_add_game_directory_base(path, added_games); });
}

rpcs3_ios_core_result rpcs3_ios_core_remove_game_directory(
    const char* path,
    uint8_t remove_library_entries,
    uint32_t* removed_games)
{
    if (removed_games)
    {
        *removed_games = 0;
    }
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_remove_game_directory_base(path, remove_library_entries, removed_games); });
}

rpcs3_ios_core_result rpcs3_ios_core_rescan_game_directories(uint32_t* added_games)
{
    if (added_games)
    {
        *added_games = 0;
    }
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_rescan_game_directories_base(added_games); });
}

rpcs3_ios_core_result rpcs3_ios_core_prune_missing_game_directories(uint32_t* removed_directories)
{
    if (removed_directories)
    {
        *removed_directories = 0;
    }
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_prune_missing_game_directories_base(removed_directories); });
}

rpcs3_ios_core_result rpcs3_ios_core_clear_game_directories(
    uint8_t remove_library_entries,
    uint32_t* removed_games)
{
    if (removed_games)
    {
        *removed_games = 0;
    }
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_clear_game_directories_base(remove_library_entries, removed_games); });
}

rpcs3_ios_core_result rpcs3_ios_core_add_game(const char* path)
{
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_add_game_base(path); });
}

rpcs3_ios_core_result rpcs3_ios_core_remove_game(const char* title_id)
{
    return run_mutation(rpcs3::ios::core_operation::library,
        [=] { return rpcs3_ios_core_remove_game_base(title_id); });
}

rpcs3_ios_core_result rpcs3_ios_core_set_configuration(const rpcs3_ios_configuration* configuration)
{
    return run_mutation(rpcs3::ios::core_operation::settings,
        [=] { return rpcs3_ios_core_set_configuration_base(configuration); });
}

rpcs3_ios_core_result rpcs3_ios_core_reset_configuration(void)
{
    return run_mutation(rpcs3::ios::core_operation::settings,
        [] { return rpcs3_ios_core_reset_configuration_base(); });
}

rpcs3_ios_core_result rpcs3_ios_core_set_midi_assignment(
    uint32_t slot,
    uint32_t type,
    const char* source_name)
{
    return run_mutation(rpcs3::ios::core_operation::midi,
        [=] { return rpcs3_ios_core_set_midi_assignment_base(slot, type, source_name); });
}

rpcs3_ios_core_result rpcs3_ios_core_clear_midi_assignment(uint32_t slot)
{
    return run_mutation(rpcs3::ios::core_operation::midi,
        [=] { return rpcs3_ios_core_clear_midi_assignment_base(slot); });
}

rpcs3_ios_core_result rpcs3_ios_core_clear_all_midi_assignments(void)
{
    return run_mutation(rpcs3::ios::core_operation::midi,
        [] { return rpcs3_ios_core_clear_all_midi_assignments_base(); });
}
}
