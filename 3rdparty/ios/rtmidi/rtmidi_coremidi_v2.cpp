#include "rtmidi_c.h"

#include <CoreMIDI/CoreMIDI.h>
#include <mach/mach_time.h>

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

namespace
{
struct queued_message
{
    std::vector<unsigned char> bytes;
    uint64_t host_time = 0;
};

struct midi_input_state
{
    std::mutex mutex;
    std::deque<queued_message> messages;
    std::vector<unsigned char> pending;
    std::vector<unsigned char> sysex;
    size_t pending_size = 0;
    MIDIClientRef client = 0;
    MIDIPortRef port = 0;
    MIDIEndpointRef endpoint = 0;
    SInt32 desired_unique_id = 0;
    std::string desired_name;
    uint64_t last_delivery_time = 0;
    unsigned char running_status = 0;
    bool wants_connection = false;
    bool ignore_sysex = true;
    bool ignore_time = true;
    bool ignore_sense = true;
    std::atomic_bool topology_changed = false;
    std::atomic_bool shutting_down = false;
    std::string status = "CoreMIDI input is ready";
};

midi_input_state* state_for(RtMidiPtr device)
{
    return device ? static_cast<midi_input_state*>(device->ptr) : nullptr;
}

void set_status(RtMidiPtr device, bool ok, std::string status)
{
    if (!device)
    {
        return;
    }

    if (midi_input_state* state = state_for(device))
    {
        state->status = std::move(status);
        device->msg = state->status.c_str();
    }
    else
    {
        device->msg = "CoreMIDI input state is unavailable";
    }
    device->ok = ok;
}

void set_ok(RtMidiPtr device)
{
    if (device)
    {
        device->ok = true;
    }
}

double seconds_between(uint64_t newer, uint64_t older)
{
    if (!newer || !older || newer <= older)
    {
        return 0.0;
    }

    mach_timebase_info_data_t timebase{};
    mach_timebase_info(&timebase);
    const long double nanoseconds = static_cast<long double>(newer - older) *
        static_cast<long double>(timebase.numer) / static_cast<long double>(timebase.denom);
    return static_cast<double>(nanoseconds / 1'000'000'000.0L);
}

uint64_t effective_timestamp(MIDITimeStamp timestamp)
{
    return timestamp ? static_cast<uint64_t>(timestamp) : mach_absolute_time();
}

size_t channel_message_size(unsigned char status)
{
    const unsigned char family = status & 0xf0;
    return (family == 0xc0 || family == 0xd0) ? 2 : 3;
}

size_t system_message_size(unsigned char status)
{
    switch (status)
    {
    case 0xf1: return 2;
    case 0xf2: return 3;
    case 0xf3: return 2;
    case 0xf6:
    case 0xf7: return 1;
    default: return status >= 0xf8 ? 1 : 0;
    }
}

bool should_ignore(const midi_input_state& state, const std::vector<unsigned char>& bytes)
{
    if (bytes.empty())
    {
        return true;
    }

    const unsigned char status = bytes.front();
    if (status == 0xf0 && state.ignore_sysex)
    {
        return true;
    }
    if ((status == 0xf1 || status == 0xf8) && state.ignore_time)
    {
        return true;
    }
    if (status == 0xfe && state.ignore_sense)
    {
        return true;
    }
    return false;
}

void enqueue(midi_input_state& state, std::vector<unsigned char> bytes, uint64_t timestamp)
{
    if (bytes.empty() || should_ignore(state, bytes))
    {
        return;
    }

    constexpr size_t maximum_queued_messages = 2048;
    if (state.messages.size() >= maximum_queued_messages)
    {
        state.messages.pop_front();
    }
    state.messages.push_back({std::move(bytes), timestamp});
}

void finish_pending(midi_input_state& state, uint64_t timestamp)
{
    if (state.pending_size && state.pending.size() == state.pending_size)
    {
        enqueue(state, std::move(state.pending), timestamp);
    }
    state.pending.clear();
    state.pending_size = 0;
}

void begin_status(midi_input_state& state, unsigned char status, uint64_t timestamp)
{
    state.pending.clear();
    state.pending_size = 0;

    if (status == 0xf0)
    {
        state.running_status = 0;
        state.sysex = {status};
        return;
    }

    const size_t size = status < 0xf0
        ? channel_message_size(status)
        : system_message_size(status);
    if (status < 0xf0)
    {
        state.running_status = status;
    }
    else
    {
        state.running_status = 0;
    }

    if (!size)
    {
        return;
    }

    state.pending = {status};
    state.pending_size = size;
    if (size == 1)
    {
        finish_pending(state, timestamp);
    }
}

void parse_packet(midi_input_state& state, const unsigned char* data, size_t length, uint64_t timestamp)
{
    for (size_t offset = 0; offset < length; ++offset)
    {
        const unsigned char byte = data[offset];

        // System real-time bytes are valid between any two MIDI bytes. They do
        // not disturb channel running status, a short message, or SysEx state.
        if (byte >= 0xf8)
        {
            enqueue(state, {byte}, timestamp);
            continue;
        }

        if (!state.sysex.empty())
        {
            if (byte == 0xf7)
            {
                state.sysex.push_back(byte);
                enqueue(state, std::move(state.sysex), timestamp);
                state.sysex.clear();
                continue;
            }
            if (byte & 0x80)
            {
                // Abort malformed SysEx and treat the new status normally.
                state.sysex.clear();
            }
            else
            {
                state.sysex.push_back(byte);
                if (state.sysex.size() > 65536)
                {
                    state.sysex.clear();
                }
                continue;
            }
        }

        if (byte & 0x80)
        {
            begin_status(state, byte, timestamp);
            continue;
        }

        if (state.pending.empty())
        {
            if (!state.running_status)
            {
                continue;
            }
            state.pending = {state.running_status};
            state.pending_size = channel_message_size(state.running_status);
        }

        state.pending.push_back(byte);
        if (state.pending.size() == state.pending_size)
        {
            finish_pending(state, timestamp);
        }
        else if (state.pending.size() > state.pending_size)
        {
            state.pending.clear();
            state.pending_size = 0;
        }
    }
}

void midi_read_proc(
    const MIDIPacketList* packet_list,
    void* read_proc_ref_con,
    void* source_connection_ref_con)
{
    (void)source_connection_ref_con;
    auto* state = static_cast<midi_input_state*>(read_proc_ref_con);
    if (!state || !packet_list || state->shutting_down.load(std::memory_order_acquire))
    {
        return;
    }

    std::lock_guard lock(state->mutex);
    const MIDIPacket* packet = &packet_list->packet[0];
    for (UInt32 index = 0; index < packet_list->numPackets; ++index)
    {
        parse_packet(*state, packet->data, packet->length, effective_timestamp(packet->timeStamp));
        packet = MIDIPacketNext(packet);
    }
}

void midi_notify_proc(const MIDINotification* notification, void* ref_con)
{
    auto* state = static_cast<midi_input_state*>(ref_con);
    if (!state || !notification || state->shutting_down.load(std::memory_order_acquire))
    {
        return;
    }

    switch (notification->messageID)
    {
    case kMIDIMsgSetupChanged:
    case kMIDIMsgObjectAdded:
    case kMIDIMsgObjectRemoved:
    case kMIDIMsgPropertyChanged:
        state->topology_changed.store(true, std::memory_order_release);
        break;
    default:
        break;
    }
}

std::string raw_endpoint_name(MIDIEndpointRef endpoint)
{
    CFStringRef name = nullptr;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) != noErr || !name)
    {
        if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) != noErr || !name)
        {
            return {};
        }
    }

    const CFIndex capacity = CFStringGetMaximumSizeForEncoding(
        CFStringGetLength(name), kCFStringEncodingUTF8) + 1;
    std::vector<char> buffer(static_cast<size_t>(std::max<CFIndex>(capacity, 1)));
    const bool converted = CFStringGetCString(name, buffer.data(), capacity, kCFStringEncodingUTF8);
    CFRelease(name);
    return converted ? std::string(buffer.data()) : std::string{};
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

MIDIEndpointRef find_desired_endpoint(SInt32 unique_id, const std::string& stable_name)
{
    const ItemCount count = MIDIGetNumberOfSources();
    for (ItemCount index = 0; index < count; ++index)
    {
        const MIDIEndpointRef endpoint = MIDIGetSource(index);
        if (!endpoint)
        {
            continue;
        }
        if (unique_id && endpoint_unique_id(endpoint) == unique_id)
        {
            return endpoint;
        }
        if (!unique_id && stable_endpoint_name(endpoint, index) == stable_name)
        {
            return endpoint;
        }
    }
    return 0;
}

void clear_parser_state(midi_input_state& state)
{
    std::lock_guard lock(state.mutex);
    state.messages.clear();
    state.pending.clear();
    state.sysex.clear();
    state.pending_size = 0;
    state.running_status = 0;
    state.last_delivery_time = 0;
}

void disconnect_endpoint(midi_input_state& state, bool clear_desired)
{
    MIDIEndpointRef endpoint = 0;
    MIDIPortRef port = 0;
    {
        std::lock_guard lock(state.mutex);
        endpoint = state.endpoint;
        port = state.port;
    }
    if (port && endpoint)
    {
        MIDIPortDisconnectSource(port, endpoint);
    }

    clear_parser_state(state);
    std::lock_guard lock(state.mutex);
    if (state.endpoint == endpoint)
    {
        state.endpoint = 0;
    }
    if (clear_desired)
    {
        state.wants_connection = false;
        state.desired_unique_id = 0;
        state.desired_name.clear();
    }
}

bool connect_endpoint(
    midi_input_state& state,
    MIDIEndpointRef endpoint,
    SInt32 unique_id,
    std::string stable_name,
    bool remember)
{
    if (!endpoint || !state.port)
    {
        return false;
    }

    if (MIDIPortConnectSource(state.port, endpoint, nullptr) != noErr)
    {
        return false;
    }

    std::lock_guard lock(state.mutex);
    state.endpoint = endpoint;
    if (remember)
    {
        state.wants_connection = true;
        state.desired_unique_id = unique_id;
        state.desired_name = std::move(stable_name);
    }
    return true;
}

void refresh_connection(midi_input_state& state)
{
    if (!state.topology_changed.exchange(false, std::memory_order_acq_rel))
    {
        return;
    }

    SInt32 unique_id = 0;
    std::string desired_name;
    MIDIEndpointRef current_endpoint = 0;
    bool wants_connection = false;
    {
        std::lock_guard lock(state.mutex);
        wants_connection = state.wants_connection;
        unique_id = state.desired_unique_id;
        desired_name = state.desired_name;
        current_endpoint = state.endpoint;
    }
    if (!wants_connection)
    {
        return;
    }

    const MIDIEndpointRef replacement = find_desired_endpoint(unique_id, desired_name);
    if (replacement == current_endpoint)
    {
        return;
    }

    disconnect_endpoint(state, false);
    if (replacement)
    {
        (void)connect_endpoint(state, replacement, unique_id, std::move(desired_name), false);
    }
}
}

extern "C"
{
RtMidiInPtr rtmidi_in_create_default(void)
{
    RtMidiInPtr device = static_cast<RtMidiInPtr>(std::calloc(1, sizeof(RtMidiWrapper)));
    if (!device)
    {
        return nullptr;
    }

    auto* state = new (std::nothrow) midi_input_state();
    if (!state)
    {
        std::free(device);
        return nullptr;
    }
    device->ptr = state;
    device->data = nullptr;

    OSStatus status = MIDIClientCreate(
        CFSTR("RPCS3 iOS CoreMIDI"), midi_notify_proc, state, &state->client);
    if (status == noErr)
    {
        status = MIDIInputPortCreate(
            state->client,
            CFSTR("RPCS3 MIDI Input"),
            midi_read_proc,
            state,
            &state->port);
    }

    if (status != noErr)
    {
        if (state->port)
        {
            MIDIPortDispose(state->port);
        }
        if (state->client)
        {
            MIDIClientDispose(state->client);
        }
        delete state;
        device->ptr = nullptr;
        device->ok = false;
        device->msg = "CoreMIDI client or input-port creation failed";
        return device;
    }

    set_status(device, true, "CoreMIDI input is ready");
    return device;
}

void rtmidi_in_free(RtMidiInPtr device)
{
    if (!device)
    {
        return;
    }

    if (midi_input_state* state = state_for(device))
    {
        state->shutting_down.store(true, std::memory_order_release);
        disconnect_endpoint(*state, true);
        if (state->port)
        {
            MIDIPortDispose(state->port);
        }
        if (state->client)
        {
            MIDIClientDispose(state->client);
        }
        delete state;
        device->ptr = nullptr;
    }
    std::free(device);
}

RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device)
{
    if (!state_for(device))
    {
        set_status(device, false, "CoreMIDI input state is unavailable");
        return RT_MIDI_API_UNSPECIFIED;
    }
    set_status(device, true, "CoreMIDI");
    return RT_MIDI_API_MACOSX_CORE;
}

void rtmidi_in_ignore_types(RtMidiInPtr device, bool midi_sysex, bool midi_time, bool midi_sense)
{
    midi_input_state* state = state_for(device);
    if (!state)
    {
        set_status(device, false, "CoreMIDI input state is unavailable");
        return;
    }

    std::lock_guard lock(state->mutex);
    state->ignore_sysex = midi_sysex;
    state->ignore_time = midi_time;
    state->ignore_sense = midi_sense;
    set_status(device, true, "CoreMIDI message filters updated");
}

double rtmidi_in_get_message(RtMidiInPtr device, unsigned char* message, size_t* size)
{
    midi_input_state* state = state_for(device);
    if (!state || !size)
    {
        set_status(device, false, "Invalid CoreMIDI message request");
        return -1.0;
    }

    refresh_connection(*state);
    std::lock_guard lock(state->mutex);
    if (state->messages.empty())
    {
        *size = 0;
        set_ok(device);
        return 0.0;
    }

    const queued_message& queued = state->messages.front();
    const size_t capacity = *size;
    if (!message || capacity < queued.bytes.size())
    {
        *size = queued.bytes.size();
        set_status(device, false, "The supplied MIDI message buffer is too small");
        return -1.0;
    }

    std::memcpy(message, queued.bytes.data(), queued.bytes.size());
    *size = queued.bytes.size();
    const double delta = seconds_between(queued.host_time, state->last_delivery_time);
    state->last_delivery_time = queued.host_time;
    state->messages.pop_front();
    set_ok(device);
    return delta;
}

unsigned int rtmidi_get_port_count(RtMidiPtr device)
{
    midi_input_state* state = state_for(device);
    if (!state)
    {
        set_status(device, false, "CoreMIDI input state is unavailable");
        return static_cast<unsigned int>(-1);
    }

    refresh_connection(*state);
    set_status(device, true, "CoreMIDI source count read");
    return static_cast<unsigned int>(MIDIGetNumberOfSources());
}

int rtmidi_get_port_name(RtMidiPtr device, unsigned int port_number, char* buffer, int* buffer_length)
{
    midi_input_state* state = state_for(device);
    if (!state || !buffer_length || *buffer_length < 0)
    {
        set_status(device, false, "Invalid CoreMIDI port-name request");
        return -1;
    }

    refresh_connection(*state);
    const ItemCount count = MIDIGetNumberOfSources();
    if (port_number >= count)
    {
        set_status(device, false, "The requested CoreMIDI source is out of range");
        return -1;
    }

    const MIDIEndpointRef endpoint = MIDIGetSource(port_number);
    const std::string name = stable_endpoint_name(endpoint, port_number);
    const int required = static_cast<int>(name.size() + 1);
    const int capacity = *buffer_length;
    *buffer_length = required;
    if (!buffer || capacity < required)
    {
        set_status(device, false, "The supplied CoreMIDI port-name buffer is too small");
        return -1;
    }

    std::memcpy(buffer, name.c_str(), static_cast<size_t>(required));
    set_status(device, true, "CoreMIDI source name read");
    return 0;
}

void rtmidi_open_port(RtMidiPtr device, unsigned int port_number, const char* port_name)
{
    (void)port_name;
    midi_input_state* state = state_for(device);
    if (!state)
    {
        set_status(device, false, "CoreMIDI input state is unavailable");
        return;
    }

    const ItemCount count = MIDIGetNumberOfSources();
    if (port_number >= count)
    {
        set_status(device, false, "The requested CoreMIDI source is out of range");
        return;
    }

    const MIDIEndpointRef endpoint = MIDIGetSource(port_number);
    if (!endpoint)
    {
        set_status(device, false, "The selected CoreMIDI source is unavailable");
        return;
    }

    const SInt32 unique_id = endpoint_unique_id(endpoint);
    std::string stable_name = stable_endpoint_name(endpoint, port_number);
    disconnect_endpoint(*state, true);
    if (!connect_endpoint(*state, endpoint, unique_id, std::move(stable_name), true))
    {
        set_status(device, false, "CoreMIDI could not connect the selected source");
        return;
    }

    state->topology_changed.store(false, std::memory_order_release);
    set_status(device, true, "CoreMIDI source connected");
}

void rtmidi_close_port(RtMidiPtr device)
{
    midi_input_state* state = state_for(device);
    if (!state)
    {
        set_status(device, false, "CoreMIDI input state is unavailable");
        return;
    }

    disconnect_endpoint(*state, true);
    set_status(device, true, "CoreMIDI source disconnected");
}

const char* rtmidi_api_name(RtMidiApi api)
{
    switch (api)
    {
    case RT_MIDI_API_MACOSX_CORE: return "CoreMIDI";
    case RT_MIDI_API_RTMIDI_DUMMY: return "Dummy";
    case RT_MIDI_API_UNSPECIFIED: return "Unspecified";
    default: return "Unsupported";
    }
}
}
