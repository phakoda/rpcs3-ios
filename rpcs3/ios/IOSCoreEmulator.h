#pragma once

#include <string>

namespace rpcs3::ios
{
bool initialize_core_emulator(std::string* error);
void shutdown_core_emulator();
}
