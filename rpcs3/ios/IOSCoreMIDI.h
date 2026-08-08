#pragma once

#include <string>

namespace rpcs3::ios
{
// Applies the host application's persisted CoreMIDI-to-RPCS3 adapter mappings
// to g_cfg. Safe to call repeatedly before a stopped-game boot.
void apply_core_midi_configuration();
void apply_core_midi_configuration_base();
std::string resolve_core_midi_source_identity(const std::string& stored_name);
void shutdown_core_midi_identity();
}
