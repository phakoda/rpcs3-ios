#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios
{
// Emulator lifecycle operations must be called from the process main thread.
// The bridge catches all C++ exceptions and reports them through error.
bool prepare_headless_emulator(std::string* error = nullptr) noexcept;
void shutdown_headless_emulator() noexcept;

std::uint32_t boot_headless_path(const std::string& path, std::string* error = nullptr) noexcept;
std::uint32_t restart_headless_emulator(bool graceful, std::string* error = nullptr) noexcept;
bool pause_headless_emulator(std::string* error = nullptr) noexcept;
bool resume_headless_emulator(std::string* error = nullptr) noexcept;
bool stop_headless_emulator(bool graceful, std::string* error = nullptr) noexcept;
std::uint32_t get_headless_emulator_state() noexcept;
}
