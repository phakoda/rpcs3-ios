#pragma once

namespace rpcs3::ios
{
// Loads the framework host's persisted mobile-safe configuration and applies it
// to g_cfg before the Emulator callback table is initialized.
void load_core_configuration();
}
