# Compatibility entry point for the historical dependency directory name used
# by the iOS aggregate. The RPCS3 wrapper lives in ../miniupnp and creates the
# stable 3rdparty_miniupnpc target consumed by the emulator core.
add_subdirectory(
    "${CMAKE_CURRENT_LIST_DIR}/../miniupnp"
    "${CMAKE_CURRENT_BINARY_DIR}/miniupnp"
    EXCLUDE_FROM_ALL)
