#include "IOSCoreInstallerSupport.h"

#include <algorithm>
#include <cctype>
#include <limits>

namespace rpcs3::ios
{
std::vector<unsigned long long> parse_firmware_version_components(const std::string& value)
{
    std::vector<unsigned long long> components;
    unsigned long long component = 0;
    bool reading = false;

    for (const unsigned char byte : value)
    {
        if (std::isdigit(byte))
        {
            reading = true;
            const unsigned int digit = byte - '0';
            if (component <= (std::numeric_limits<unsigned long long>::max() - digit) / 10)
            {
                component = component * 10 + digit;
            }
            else
            {
                component = std::numeric_limits<unsigned long long>::max();
            }
        }
        else if (reading)
        {
            components.push_back(component);
            component = 0;
            reading = false;
        }
    }

    if (reading)
    {
        components.push_back(component);
    }
    while (components.size() > 1 && components.back() == 0)
    {
        components.pop_back();
    }
    return components;
}

bool firmware_version_less(const std::string& candidate, const std::string& installed)
{
    std::vector<unsigned long long> left = parse_firmware_version_components(candidate);
    std::vector<unsigned long long> right = parse_firmware_version_components(installed);
    if (left.empty() || right.empty())
    {
        return false;
    }

    const std::size_t count = std::max(left.size(), right.size());
    left.resize(count);
    right.resize(count);
    return std::lexicographical_compare(left.begin(), left.end(), right.begin(), right.end());
}

std::uintmax_t saturating_size_add(std::uintmax_t left, std::uintmax_t right) noexcept
{
    const auto maximum = std::numeric_limits<std::uintmax_t>::max();
    return right > maximum - left ? maximum : left + right;
}

std::uintmax_t saturating_size_multiply(std::uintmax_t value, std::uintmax_t multiplier) noexcept
{
    const auto maximum = std::numeric_limits<std::uintmax_t>::max();
    return value && multiplier > maximum / value ? maximum : value * multiplier;
}

std::uintmax_t estimate_firmware_transaction_bytes(
    std::uintmax_t live_size,
    std::uintmax_t pup_size) noexcept
{
    constexpr std::uintmax_t one_gibibyte = 1024ull * 1024ull * 1024ull;
    constexpr std::uintmax_t safety_margin = 256ull * 1024ull * 1024ull;
    const std::uintmax_t expansion = std::max(saturating_size_multiply(pup_size, 4), one_gibibyte);
    return saturating_size_add(saturating_size_add(live_size, expansion), safety_margin);
}
}
