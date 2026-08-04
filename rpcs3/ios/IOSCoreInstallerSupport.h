#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios
{
std::vector<unsigned long long> parse_firmware_version_components(const std::string& value);
bool firmware_version_less(const std::string& candidate, const std::string& installed);
std::uintmax_t saturating_size_add(std::uintmax_t left, std::uintmax_t right) noexcept;
std::uintmax_t saturating_size_multiply(std::uintmax_t value, std::uintmax_t multiplier) noexcept;
std::uintmax_t estimate_firmware_transaction_bytes(
    std::uintmax_t live_size,
    std::uintmax_t pup_size) noexcept;
}
