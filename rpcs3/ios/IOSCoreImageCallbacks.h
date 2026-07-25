#pragma once

struct EmuCallbacks;

namespace rpcs3::ios
{
// Replaces the generic ImageIO callbacks with values matching RPCS3's desktop
// callback contract: filename-extension subtype and 0–4 rotation orientation.
void extend_core_image_callbacks(EmuCallbacks& callbacks);
}
