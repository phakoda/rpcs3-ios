#pragma once

struct EmuCallbacks;

namespace rpcs3::ios
{
// Installs public Foundation/AVFoundation fallbacks for callback slots that are
// otherwise supplied by the desktop Qt application.
void extend_core_fallback_callbacks(EmuCallbacks& callbacks);
void shutdown_core_fallback_services();
}
