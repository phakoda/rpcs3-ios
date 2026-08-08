#pragma once

struct EmuCallbacks;

namespace rpcs3::ios
{
// Replaces the generic callback extension's save-data chooser with a bounded
// implementation that never retains RPCS3's caller-owned entry vector.
void extend_core_save_dialog_callback(EmuCallbacks& callbacks);
}
