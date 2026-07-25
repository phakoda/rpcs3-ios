#include "IOSCoreCallbacks.h"
#include "IOSCoreFallbackCallbacks.h"
#include "IOSCoreImageCallbacks.h"
#include "IOSCoreSaveDialog.h"

namespace rpcs3::ios
{
// IOSCoreCallbacks.mm is compiled with a source-local macro that renames its
// implementation to this base symbol. Keep composition in a tiny ordinary C++
// translation unit so contract-specific overrides remain explicit.
void extend_core_callbacks_base(EmuCallbacks& callbacks);

void extend_core_callbacks(EmuCallbacks& callbacks)
{
    extend_core_callbacks_base(callbacks);
    extend_core_fallback_callbacks(callbacks);
    extend_core_image_callbacks(callbacks);
    extend_core_save_dialog_callback(callbacks);
}
}
