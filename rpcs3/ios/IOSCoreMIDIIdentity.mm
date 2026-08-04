#include "IOSCoreEmulator.h"
#include "IOSCoreMIDI.h"
#include "RPCS3Core.h"
#include "RPCS3CoreStatus.h"

#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace
{
std::mutex g_identity_mutex;
MIDIClientRef g_identity_client = 0;
std::atomic<uint64_t> g_topology_generation = 1;

void identity_notify_proc(const MIDINotification* notification, void*)
{
    if (!notification)
    {
        return;
    }
    switch (notification->messageID)
    {
    case kMIDIMsgSetupChanged:
    case kMIDIMsgObjectAdded:
    case kMIDIMsgObjectRemoved:
    case kMIDIMsgPropertyChanged:
        g_topology_generation.fetch_add(1, std::memory_order_acq_rel);
        break;
    default:
        break;
    }
}

void ensure_identity_client()
{
    std::lock_guard lock(g_identity_mutex);
    if (!g_identity_client)
    {
        (void)MIDIClientCreate(
            CFSTR("RPCS3Core MIDI Identity"),
            identity_notify_proc,
            nullptr,
            &g_identity_client);
    }
}

std::string raw_endpoint_name(MIDIEndpointRef endpoint)
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
    const char* bytes = name.UTF8String;
    return bytes ? std::string(bytes) : std::string{};
}

SInt32 endpoint_unique_id(MIDIEndpointRef endpoint)
{
    SInt32 unique_id = 0;
    return MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &unique_id) == noErr
        ? unique_id
        : 0;
}

std::string stable_endpoint_name(MIDIEndpointRef endpoint, size_t index)
{
    std::string name = raw_endpoint_name(endpoint);
    if (name.empty())
    {
        name = "CoreMIDI Source " + std::to_string(index + 1);
    }

    const SInt32 unique_id = endpoint_unique_id(endpoint);
    if (unique_id)
    {
        name += " [CoreMIDI ID " + std::to_string(unique_id) + "]";
    }
    else
    {
        name += " [CoreMIDI Index " + std::to_string(index) + "]";
    }
    return name;
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
void shutdown_core_midi_identity()
{
    std::lock_guard lock(g_identity_mutex);
    if (g_identity_client)
    {
        MIDIClientDispose(g_identity_client);
        g_identity_client = 0;
        g_topology_generation.fetch_add(1, std::memory_order_acq_rel);
    }
}
}

extern "C"
{
size_t rpcs3_ios_core_midi_source_count(void)
{
    ensure_identity_client();
    return static_cast<size_t>(MIDIGetNumberOfSources());
}

rpcs3_ios_core_result rpcs3_ios_core_copy_midi_source(
    size_t index,
    char* name,
    size_t name_size,
    size_t* required_size)
{
    ensure_identity_client();
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

    const std::string value = stable_endpoint_name(MIDIGetSource(index), index);
    if (!copy_value(value, name, name_size, required_size))
    {
        return RPCS3_IOS_CORE_BUFFER_TOO_SMALL;
    }

    rpcs3::ios::set_core_last_error({});
    return RPCS3_IOS_CORE_SUCCESS;
}

uint64_t rpcs3_ios_core_midi_topology_generation(void)
{
    ensure_identity_client();
    return g_topology_generation.load(std::memory_order_acquire);
}
}
