#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios
{
bool prepare_headless_emulator(std::string* error = nullptr);
void shutdown_headless_emulator();

std::uint32_t boot_headless_path(const std::string& path);
std::uint32_t restart_headless_emulator(bool graceful);
bool pause_headless_emulator();
bool resume_headless_emulator();
bool stop_headless_emulator(bool graceful);
std::uint32_t get_headless_emulator_state();
}
