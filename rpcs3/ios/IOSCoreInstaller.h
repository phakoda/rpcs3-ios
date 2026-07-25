#pragma once

namespace rpcs3::ios
{
// Requests cancellation and waits for any synchronous framework installation
// operation to leave RPCS3/VFS state before framework shutdown continues.
void shutdown_core_installer();
}
