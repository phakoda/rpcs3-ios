#pragma once

namespace rpcs3::ios
{
void install_core_lifecycle_callbacks();
void remove_core_lifecycle_callbacks();
bool core_lifecycle_allows_boot();
void enforce_core_lifecycle_pause_after_run();
bool try_core_lifecycle_pause_after_run();
bool try_core_lifecycle_resume_after_reasons();
void schedule_core_lifecycle_pause_after_run();
void schedule_core_lifecycle_resume_after_reasons();
}
