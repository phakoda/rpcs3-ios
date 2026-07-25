#include "IOSCoreMIDI.h"
#include "IOSCoreEmulator.h"
#include "RPCS3Core.h"

#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>

#include "Emu/System.h"
#include "Emu/Io/midi_config_types.h"
#include "Emu/system_config.h"

#include <array>
#include <cstring>
#include <mutex>
#include <string>

namespace
{
std::mutex g_midi_mutex;
NSString* const midi_assignments_key = @"RPCS3Core.MIDI.Assignments";
NSString* const midi_type_key = @"Type";
NSString* const midi_name_key = @"Name";

struct midi_assignment
{
    uint32_t type = RPCS3_IOS_MIDI_KEYBOARD;
    std::string name;
};

using midi_assignments = std::array<midi_assignment, max_midi_devices>;

static_assert(max_midi_devices == 3);
static_assert(static_cast<uint32_t>(midi_device_type::keyboard) == RPCS3_IOS_MIDI_KEYBOARD);
static_assert(static_cast<uint32_t>(midi_device_type::guitar) == RPCS3_IOS_MIDI_GUITAR_17_FRET);
static_assert(static_cast<uint32_t>(midi_device_type::guitar_22fret) == RPCS3_IOS_MIDI_GUITAR_22_FRET);
static_assert(static_cast<uint32_t>(midi_device_type::drums) == RPCS3_IOS_MIDI_DRUMS);

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

std::string endpoint_name(MIDIEndpointRef endpoint)
{
    CFStringRef value = nullptr;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || !value)
    {
        if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value) != noErr || !value)
        {
            return {};
        }
    }

    NSString* name = (__bridge_transfer NSString*)value;
    return utf8_string(name);
}

const char* type_name(uint32_t type)
{
    switch (type)
    {
    case RPCS3_IOS_MIDI_KEYBOARD: return "Keyboard";
    case RPCS3_IOS_MIDI_GUITAR_17_FRET: return "Guitar (17 frets)";
    case RPCS3_IOS_MIDI_GUITAR_22_FRET: return "Guitar (22 frets)";
    case RPCS3_IOS_MIDI_DRUMS: return "Drums";
    default: return nullptr;
    }
}

bool valid_slot(uint32_t slot)
{
    return slot < max_midi_devices;
}

bool valid_source_name(const std::string& name)
{
    return name.find("@@@") == std::string::npos &&
        name.find("ßßß") == std::string::npos;
}

midi_assignments load_assignments()
{
    midi_assignments result{};
    NSArray<NSDictionary*>* stored = [NSUserDefaults.standardUserDefaults arrayForKey:midi_assignments_key];
    const NSUInteger count = std::min<NSUInteger>(stored.count, result.size());
    for (NSUInteger index = 0; index < count; ++index)
    {
        NSDictionary* entry = stored[index];
        NSNumber* type = entry[midi_type_key];
        NSString* name = entry[midi_name_key];
        const uint32_t type_value = type ? type.unsignedIntValue : RPCS3_IOS_MIDI_KEYBOARD;
        result[index].type = type_name(type_value) ? type_value : RPCS3_IOS_MIDI_KEYBOARD;
        result[index].name = name ? utf8_string(name) : std::string{};
        if (!valid_source_name(result[index].name))
        {
            result[index].name.clear();
        }
    }
    return result;
}

void save_assignments(const midi_assignments& assignments)
{
    NSMutableArray<NSDictionary*>* stored = [NSMutableArray arrayWithCapacity:assignments.size()];
    for (const midi_assignment& assignment : assignments)
    {
        [stored addObject:@{
            midi_type_key: @(assignment.type),
            midi_name_key: ns_utf8(assignment.name),
        }];
    }
    [NSUserDefaults.standardUserDefaults setObject:stored forKey:midi_assignments_key];
}

std::string serialize_assignments(const midi_assignments& assignments)
{
    std::string result;
    for (const midi_assignment& assignment : assignments)
    {
        result += type_name(assignment.type);
        result += "ßßß";
        result += assignment.name;
        result += "@@@";
    }
    return result;
}

void apply_assignments(const midi_assignments& assignments)
{
    g_cfg.io.midi_devices = serialize_assignments(assignments);
}

bool mutation_allowed()
{
    return Emulator::IsAvailable() && Emu.IsStopped(true);
}

bool copy_value(const std::string& value, char* buffer, size_t buffer_size, size_t* required_size)
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

namespace rpcs3::ios
{
void apply_core_midi_configuration()
{
    std::lock_guard lock(g_midi_mutex);
    apply_assignments(load_assignments());
}
}

extern "C"
{
size_t rpcs3_ios_core_midi_source_count(void)
{
    return static_cast<size_t>(MIDIGetNumberOfSources());
}

rpcs3_ios_core_result rpcs3_ios_core_copy_midi_source(
    size_t index,
    char* name,
    size_t name_size,
    size_t* required_size)
{
    if (!required_size)
    {
        rpcs3::ios::set_core_last_error("A MIDI source required-size output is required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    const ItemCount count = MIDIGetNumberOfSources();
    if (index >= count)
    {
        rpcs3::ios::set_core_last_error("The requested CoreMIDI source index is out of range.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    const std::string value = endpoint_name(MIDIGetSource(index));
    if (value.empty())
    {
        rpcs3::ios::set_core_last_error("The selected CoreMIDI source has no readable display name.");
        return RPCS3_IOS_CORE_PLATFORM_ERROR;
    }
    if (!copy_value(value, name, name_size, required_size))
    {
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

size_t rpcs3_ios_core_midi_slot_count(void)
{
    return max_midi_devices;
}

rpcs3_ios_core_result rpcs3_ios_core_set_midi_assignment(
    uint32_t slot,
    uint32_t type,
    const char* source_name)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!valid_slot(slot) || !type_name(type) || !source_name || !*source_name)
    {
        rpcs3::ios::set_core_last_error("A valid MIDI slot, adapter type, and non-empty CoreMIDI source name are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("MIDI assignments can be changed only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    const std::string name = source_name;
    if (!valid_source_name(name))
    {
        rpcs3::ios::set_core_last_error("The CoreMIDI source name contains a delimiter reserved by RPCS3 configuration.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_midi_mutex);
    midi_assignments assignments = load_assignments();
    assignments[slot] = {type, name};
    save_assignments(assignments);
    apply_assignments(assignments);
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_clear_midi_assignment(uint32_t slot)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!valid_slot(slot))
    {
        rpcs3::ios::set_core_last_error("The requested MIDI assignment slot is out of range.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }
    if (!mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("MIDI assignments can be changed only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_midi_mutex);
    midi_assignments assignments = load_assignments();
    assignments[slot].name.clear();
    save_assignments(assignments);
    apply_assignments(assignments);
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_copy_midi_assignment(
    uint32_t slot,
    uint32_t* type,
    char* source_name,
    size_t source_name_size,
    size_t* required_size)
{
    if (!valid_slot(slot) || !type || !required_size)
    {
        rpcs3::ios::set_core_last_error("A valid MIDI slot, type output, and required-size output are required.");
        return RPCS3_IOS_CORE_INVALID_ARGUMENT;
    }

    std::lock_guard lock(g_midi_mutex);
    const midi_assignments assignments = load_assignments();
    *type = assignments[slot].type;
    if (!copy_value(assignments[slot].name, source_name, source_name_size, required_size))
    {
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

rpcs3_ios_core_result rpcs3_ios_core_clear_all_midi_assignments(void)
{
    if (!rpcs3_ios_core_is_initialized())
    {
        return RPCS3_IOS_CORE_NOT_INITIALIZED;
    }
    if (!mutation_allowed())
    {
        rpcs3::ios::set_core_last_error("MIDI assignments can be cleared only while emulation is fully stopped.");
        return RPCS3_IOS_CORE_BUSY;
    }

    std::lock_guard lock(g_midi_mutex);
    const midi_assignments assignments{};
    [NSUserDefaults.standardUserDefaults removeObjectForKey:midi_assignments_key];
    apply_assignments(assignments);
    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}
}
