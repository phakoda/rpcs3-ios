#include "IOSCoreInstallerSupport.h"

#include <cassert>
#include <cstdint>
#include <limits>

int main()
{
    using namespace rpcs3::ios;

    assert((parse_firmware_version_components("4.90") ==
        std::vector<unsigned long long>{4, 90}));
    assert((parse_firmware_version_components("4.90.0") ==
        std::vector<unsigned long long>{4, 90}));
    assert(parse_firmware_version_components("firmware").empty());
    assert(parse_firmware_version_components("999999999999999999999999").front() ==
        std::numeric_limits<unsigned long long>::max());

    assert(firmware_version_less("4.90", "4.100"));
    assert(!firmware_version_less("4.100", "4.90"));
    assert(!firmware_version_less("4.90", "4.90.0"));
    assert(!firmware_version_less("unknown", "4.90"));

    constexpr std::uintmax_t mib = 1024ull * 1024ull;
    constexpr std::uintmax_t gib = 1024ull * mib;
    assert(estimate_firmware_transaction_bytes(100 * mib, 10 * mib) ==
        100 * mib + gib + 256 * mib);
    assert(estimate_firmware_transaction_bytes(100 * mib, 400 * mib) ==
        100 * mib + 1600 * mib + 256 * mib);

    const std::uintmax_t maximum = std::numeric_limits<std::uintmax_t>::max();
    assert(saturating_size_add(maximum - 1, 2) == maximum);
    assert(saturating_size_multiply(maximum, 2) == maximum);
    assert(estimate_firmware_transaction_bytes(maximum, maximum) == maximum);
    return 0;
}
