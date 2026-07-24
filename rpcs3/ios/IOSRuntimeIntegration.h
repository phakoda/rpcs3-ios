#pragma once

namespace rpcs3::ios
{
// Called after Qt has created the iOS QApplication/UIApplication bridge.
void initialize_rpcs3_runtime();

// Called after the Qt event loop exits.
void shutdown_rpcs3_runtime();
}
