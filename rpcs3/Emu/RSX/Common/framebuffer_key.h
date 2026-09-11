// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <cstdint>

namespace rsx
{
	constexpr std::uint64_t framebuffer_cache_key(std::uint16_t width, std::uint16_t height, bool input_attachments)
	{
		return std::uint64_t{width} | (std::uint64_t{height} << 16) |
			(std::uint64_t{input_attachments} << 32);
	}
}
