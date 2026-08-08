#pragma once

// RPCS3's microphone module keeps a few OpenAL context types in its public
// implementation surface even when WITHOUT_OPENAL disables capture support.
// iOS core builds intentionally use the null microphone backend, so expose only
// the declarations that remain referenced by always-compiled code.

#ifdef __cplusplus
extern "C" {
#endif

typedef char ALCchar;
typedef int ALCenum;
typedef struct ALCdevice_struct ALCdevice;

static inline const ALCchar* alcGetString(ALCdevice* device, ALCenum error)
{
    (void)device;
    (void)error;
    return "OpenAL unavailable on this iOS build";
}

#ifdef __cplusplus
}
#endif
