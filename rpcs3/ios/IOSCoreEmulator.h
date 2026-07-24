#pragma once

#include <string>

namespace rpcs3::ios
{
bool initialize_core_emulator(std::string* error);
void shutdown_core_emulator();
void set_core_last_error(std::string error);
std::string get_core_last_error();
}
