#pragma once

namespace rpcs3::ios
{
void install_core_lifecycle_callbacks();
void remove_core_lifecycle_callbacks();
bool core_lifecycle_allows_boot();
void enforce_core_lifecycle_pause_after_run();
}
