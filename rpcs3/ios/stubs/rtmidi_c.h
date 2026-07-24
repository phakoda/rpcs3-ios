#pragma once

// Minimal RtMidi C API used by RPCS3's optional Rock Band MIDI devices. The
// iOS core keeps these emulated USB classes linkable, but reports zero host
// MIDI ports until a native CoreMIDI backend is implemented.

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RtMidiApi
{
    RTMIDI_API_UNSPECIFIED,
    RTMIDI_API_MACOSX_CORE,
    RTMIDI_API_LINUX_ALSA,
    RTMIDI_API_UNIX_JACK,
    RTMIDI_API_WINDOWS_MM,
    RTMIDI_API_RTMIDI_DUMMY,
    RTMIDI_API_WEB_MIDI_API,
    RTMIDI_API_NUM,
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

typedef void (*RtMidiCCallback)(double time_stamp, const unsigned char* message,
    size_t message_size, void* user_data);

typedef void (*RtMidiErrorCallback)(int error_type, const char* error_text, void* user_data);

int rtmidi_get_compiled_api(RtMidiApi* apis, unsigned int apis_size);
const char* rtmidi_api_name(RtMidiApi api);
const char* rtmidi_api_display_name(RtMidiApi api);
RtMidiApi rtmidi_compiled_api_by_name(const char* name);

void rtmidi_open_port(RtMidiPtr device, unsigned int port_number, const char* port_name);
void rtmidi_open_virtual_port(RtMidiPtr device, const char* port_name);
void rtmidi_close_port(RtMidiPtr device);
unsigned int rtmidi_get_port_count(RtMidiPtr device);
int rtmidi_get_port_name(RtMidiPtr device, unsigned int port_number, char* buffer, int* buffer_length);

RtMidiInPtr rtmidi_in_create_default(void);
RtMidiInPtr rtmidi_in_create(RtMidiApi api, const char* client_name, unsigned int queue_size_limit);
void rtmidi_in_free(RtMidiInPtr device);
RtMidiApi rtmidi_in_get_current_api(RtMidiPtr device);
void rtmidi_in_set_callback(RtMidiInPtr device, RtMidiCCallback callback, void* user_data);
void rtmidi_in_cancel_callback(RtMidiInPtr device);
void rtmidi_in_ignore_types(RtMidiInPtr device, bool midi_sysex, bool midi_time, bool midi_sense);
double rtmidi_in_get_message(RtMidiInPtr device, unsigned char* message, size_t* size);

RtMidiOutPtr rtmidi_out_create_default(void);
RtMidiOutPtr rtmidi_out_create(RtMidiApi api, const char* client_name);
void rtmidi_out_free(RtMidiOutPtr device);
RtMidiApi rtmidi_out_get_current_api(RtMidiPtr device);
int rtmidi_out_send_message(RtMidiOutPtr device, const unsigned char* message, int length);

#ifdef __cplusplus
}
#endif
