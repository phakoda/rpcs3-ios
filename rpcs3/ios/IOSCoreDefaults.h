#pragma once

namespace rpcs3::ios
{
// Constrains configuration values to backends that are actually present in the
// selected iOS build. This is intentionally idempotent and may be called after
// loading a user configuration as well as during first-run initialization.
void apply_core_compatibility_defaults();
}
