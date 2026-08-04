#pragma once

#include <string>

namespace rpcs3::ios
{
// Requests cancellation and waits for any synchronous framework installation
// operation to leave RPCS3/VFS state before framework shutdown continues.
void shutdown_core_installer();

// Completes or rolls back a firmware transaction interrupted between staging,
// backup, and activation. Call only under framework initialization admission.
bool recover_core_firmware_transaction(std::string* error = nullptr);
}
