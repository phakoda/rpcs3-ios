#include "rtmidi_c.h"

#include <cstdlib>
#include <cstring>

namespace
{
constexpr const char* unavailable_message = "MIDI input is unavailable in the current iOS core target";

void set_ok(RtMidiPtr device, bool ok, const char* message)
{
    if (!device)
    {
        return;
    }
    device->ok = ok;
    device->msg = message;
}
}

extern "C"
{
RtMidiInPtr rtmidi_in_create_default(void)
{
    RtMidiInPtr device = static_cast<RtMidiInPtr>(std::calloc(1, sizeof(RtMidiWrapper)));
    if (device)
    {
        device->ok = true;
        device->msg = unavailable_message;
    }
    return device;
}

void rtmidi_in_free(RtMidiInPtr device)
{
    std::free(device);
}

RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device)
{
    set_ok(device, true, unavailable_message);
    return RT_MIDI_API_RTMIDI_DUMMY;
}

void rtmidi_in_ignore_types(RtMidiInPtr device, bool midi_sysex, bool midi_time, bool midi_sense)
{
    (void)midi_sysex;
    (void)midi_time;
    (void)midi_sense;
    set_ok(device, true, unavailable_message);
}

double rtmidi_in_get_message(RtMidiInPtr device, unsigned char* message, size_t* size)
{
    (void)message;
    if (size)
    {
        *size = 0;
    }
    set_ok(device, true, unavailable_message);
    return 0.0;
}

unsigned int rtmidi_get_port_count(RtMidiPtr device)
{
    set_ok(device, true, unavailable_message);
    return 0;
}

int rtmidi_get_port_name(RtMidiPtr device, unsigned int port_number, char* buffer, int* buffer_length)
{
    (void)port_number;
    if (!device || !buffer_length || *buffer_length < 0)
    {
        set_ok(device, false, "Invalid RtMidi port-name request");
        return -1;
    }

    if (buffer && *buffer_length > 0)
    {
        buffer[0] = '\0';
    }
    *buffer_length = 0;
    set_ok(device, false, unavailable_message);
    return -1;
}

void rtmidi_open_port(RtMidiPtr device, unsigned int port_number, const char* port_name)
{
    (void)port_number;
    (void)port_name;
    set_ok(device, false, unavailable_message);
}

void rtmidi_close_port(RtMidiPtr device)
{
    set_ok(device, true, unavailable_message);
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
