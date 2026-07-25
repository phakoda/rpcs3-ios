#include "IOSCoreCallbacks.h"
#include "IOSCoreSaveDialog.h"

namespace rpcs3::ios
{
// IOSCoreCallbacks.mm is compiled with a source-local macro that renames its
// implementation to this base symbol. Keep the composition in a tiny ordinary
// C++ translation unit so callback ordering is explicit and reviewable.
void extend_core_callbacks_base(EmuCallbacks& callbacks);

void extend_core_callbacks(EmuCallbacks& callbacks)
{
    extend_core_callbacks_base(callbacks);
    extend_core_save_dialog_callback(callbacks);
}
}
