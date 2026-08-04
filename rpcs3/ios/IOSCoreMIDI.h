#pragma once

namespace rpcs3::ios
{
// Applies the host application's persisted CoreMIDI-to-RPCS3 adapter mappings
// to g_cfg. Safe to call repeatedly before a stopped-game boot.
void apply_core_midi_configuration();
void shutdown_core_midi_identity();
}
