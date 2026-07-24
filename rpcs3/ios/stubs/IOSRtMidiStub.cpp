#include "rtmidi_c.h"

#include <algorithm>
#include <cstring>
#include <new>

namespace
{
constexpr const char* unavailable_message = "CoreMIDI input is not implemented in the RPCS3 iOS core port";

RtMidiWrapper* create_wrapper()
{
    auto* wrapper = new (std::nothrow) RtMidiWrapper{};
    if (wrapper)
    {
        wrapper->ok = true;
        wrapper->msg = unavailable_message;
    }
    return wrapper;
}

void set_error(RtMidiPtr device, const char* message)
{
    if (device)
    {
        device->ok = false;
        device->msg = message;
    }
}
}

extern "C"
{
int rtmidi_get_compiled_api(RtMidiApi* apis, unsigned int apis_size)
{
    if (apis && apis_size > 0)
    {
        apis[0] = RTMIDI_API_RTMIDI_DUMMY;
    }
    return 1;
}

const char* rtmidi_api_name(RtMidiApi api)
{
    switch (api)
    {
    case RTMIDI_API_RTMIDI_DUMMY: return "dummy";
    case RTMIDI_API_MACOSX_CORE: return "core";
    case RTMIDI_API_UNSPECIFIED: return "unspecified";
    default: return "unavailable";
    }
}

const char* rtmidi_api_display_name(RtMidiApi api)
{
    switch (api)
    {
    case RTMIDI_API_RTMIDI_DUMMY: return "RPCS3 iOS no-device MIDI";
    case RTMIDI_API_MACOSX_CORE: return "CoreMIDI";
    default: return "Unavailable MIDI API";
    }
}

RtMidiApi rtmidi_compiled_api_by_name(const char* name)
{
    return name && std::strcmp(name, "dummy") == 0 ? RTMIDI_API_RTMIDI_DUMMY : RTMIDI_API_UNSPECIFIED;
}

void rtmidi_open_port(RtMidiPtr device, unsigned int port_number, const char* port_name)
{
    (void)port_number;
    (void)port_name;
    set_error(device, unavailable_message);
}

void rtmidi_open_virtual_port(RtMidiPtr device, const char* port_name)
{
    (void)port_name;
    set_error(device, unavailable_message);
}

void rtmidi_close_port(RtMidiPtr device)
{
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
}

unsigned int rtmidi_get_port_count(RtMidiPtr device)
{
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    return 0;
}

int rtmidi_get_port_name(RtMidiPtr device, unsigned int port_number, char* buffer, int* buffer_length)
{
    (void)port_number;
    if (!buffer_length)
    {
        set_error(device, "Invalid MIDI port-name length pointer");
        return -1;
    }

    constexpr const char* name = "";
    const int required = 1;
    if (buffer && *buffer_length > 0)
    {
        buffer[0] = '\0';
    }
    *buffer_length = required;
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    (void)name;
    return 0;
}

RtMidiInPtr rtmidi_in_create_default(void)
{
    return create_wrapper();
}

RtMidiInPtr rtmidi_in_create(RtMidiApi api, const char* client_name, unsigned int queue_size_limit)
{
    (void)api;
    (void)client_name;
    (void)queue_size_limit;
    return create_wrapper();
}

void rtmidi_in_free(RtMidiInPtr device)
{
    delete device;
}

RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device)
{
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    return RTMIDI_API_RTMIDI_DUMMY;
}

void rtmidi_in_set_callback(RtMidiInPtr device, RtMidiCCallback callback, void* user_data)
{
    (void)callback;
    (void)user_data;
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
}

void rtmidi_in_cancel_callback(RtMidiInPtr device)
{
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
}

void rtmidi_in_ignore_types(RtMidiInPtr device, bool midi_sysex, bool midi_time, bool midi_sense)
{
    (void)midi_sysex;
    (void)midi_time;
    (void)midi_sense;
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
}

double rtmidi_in_get_message(RtMidiInPtr device, unsigned char* message, size_t* size)
{
    (void)message;
    if (!size)
    {
        set_error(device, "Invalid MIDI message-size pointer");
        return -1.0;
    }

    *size = 0;
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    return 0.0;
}

RtMidiOutPtr rtmidi_out_create_default(void)
{
    return create_wrapper();
}

RtMidiOutPtr rtmidi_out_create(RtMidiApi api, const char* client_name)
{
    (void)api;
    (void)client_name;
    return create_wrapper();
}

void rtmidi_out_free(RtMidiOutPtr device)
{
    delete device;
}

RtMidiApi rtmidi_out_get_current_api(RtMidiPtr device)
{
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    return RTMIDI_API_RTMIDI_DUMMY;
}

int rtmidi_out_send_message(RtMidiOutPtr device, const unsigned char* message, int length)
{
    (void)message;
    (void)length;
    set_error(device, unavailable_message);
    return -1;
}
}
