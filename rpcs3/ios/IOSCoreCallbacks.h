#pragma once

struct EmuCallbacks;

namespace rpcs3::ios
{
// Replaces desktop/null callback slots with public UIKit, ImageIO, and
// CoreGraphics implementations for the Qt-free framework target.
void extend_core_callbacks(EmuCallbacks& callbacks);
}
