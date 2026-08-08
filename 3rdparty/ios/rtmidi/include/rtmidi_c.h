#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RtMidiApi
{
    RT_MIDI_API_UNSPECIFIED,
    RT_MIDI_API_MACOSX_CORE,
    RT_MIDI_API_LINUX_ALSA,
    RT_MIDI_API_UNIX_JACK,
    RT_MIDI_API_WINDOWS_MM,
    RT_MIDI_API_RTMIDI_DUMMY,
    RT_MIDI_API_WEB_MIDI,
    RT_MIDI_API_WINDOWS_UWP,
    RT_MIDI_API_ANDROID,
    RT_MIDI_API_NUM,
} RtMidiApi;

typedef struct RtMidiWrapper
{
    void* ptr;
    void* data;
    bool ok;
    const char* msg;
} RtMidiWrapper;

typedef RtMidiWrapper* RtMidiPtr;
typedef RtMidiWrapper* RtMidiInPtr;
typedef RtMidiWrapper* RtMidiOutPtr;

RtMidiInPtr rtmidi_in_create_default(void);
void rtmidi_in_free(RtMidiInPtr device);
RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device);
void rtmidi_in_ignore_types(RtMidiInPtr device, bool midi_sysex, bool midi_time, bool midi_sense);
double rtmidi_in_get_message(RtMidiInPtr device, unsigned char* message, size_t* size);

unsigned int rtmidi_get_port_count(RtMidiPtr device);
int rtmidi_get_port_name(RtMidiPtr device, unsigned int port_number, char* buffer, int* buffer_length);
void rtmidi_open_port(RtMidiPtr device, unsigned int port_number, const char* port_name);
void rtmidi_close_port(RtMidiPtr device);
const char* rtmidi_api_name(RtMidiApi api);

#ifdef __cplusplus
}
#endif
