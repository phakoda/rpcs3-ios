// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>
#include <span>
#include <utility>
#include <vector>

// API-independent presentation decisions. Kept separate so edge cases can be
// tested without a GPU, window system, or Apple SDK.
namespace rsx::presentation
{
	struct extent
	{
		std::uint32_t width{};
		std::uint32_t height{};
		bool operator==(const extent&) const = default;
	};

	inline std::optional<extent> choose_extent(extent requested, extent current, extent minimum, extent maximum)
	{
		if (!maximum.width || !maximum.height || minimum.width > maximum.width || minimum.height > maximum.height)
			return std::nullopt;

		// A fixed surface size is authoritative, even when the last window-size
		// notification is stale (e.g. during rotation).
		if (current.width != std::numeric_limits<std::uint32_t>::max())
		{
			if (!current.width || !current.height || current.width < minimum.width || current.height < minimum.height ||
				current.width > maximum.width || current.height > maximum.height)
				return std::nullopt;
			return current;
		}

		// Do not turn a minimized window into an artificial 1x1 surface.
		if (!requested.width || !requested.height)
			return std::nullopt;
		return extent{std::clamp(requested.width, minimum.width, maximum.width),
			std::clamp(requested.height, minimum.height, maximum.height)};
	}

	inline std::uint32_t choose_image_count(std::uint32_t minimum, std::uint32_t maximum)
	{
		// Prefer one spare image and at least triple buffering. Zero maximum
		// means unlimited, not zero images. Use 64-bit arithmetic before clamping.
		const auto desired = std::max<std::uint64_t>(3, std::uint64_t{minimum} + 1);
		const auto limit = maximum ? maximum : std::numeric_limits<std::uint32_t>::max();
		return static_cast<std::uint32_t>(std::min<std::uint64_t>(desired, limit));
	}

	template <typename SurfaceFormat, typename Format, typename ColorSpace>
	std::optional<SurfaceFormat> choose_surface_format(std::span<const SurfaceFormat> formats,
		Format undefined, Format preferred, ColorSpace preferred_space)
	{
		if (formats.empty())
			return std::nullopt;
		if (formats.size() == 1 && formats.front().format == undefined)
			return SurfaceFormat{preferred, formats.front().colorSpace};

		for (const auto& format : formats)
			if (format.format == preferred && format.colorSpace == preferred_space)
				return format;
		for (const auto& format : formats)
			if (format.format == preferred)
				return format;
		// Never combine a format with another entry's color space.
		return formats.front();
	}

	inline std::optional<std::uint32_t> choose_composite_alpha(std::uint32_t supported,
		std::span<const std::uint32_t> preference)
	{
		for (const auto mode : preference)
			if (mode && (supported & mode) == mode)
				return mode;
		return std::nullopt;
	}

	template <typename T, typename Status, typename Query>
	Status enumerate(Query&& query, std::vector<T>& output, Status success, Status incomplete)
	{
		// The count can grow between queries. Publish only a complete result;
		// bounded retries also protect against a driver that never settles.
		for (unsigned attempt = 0; attempt < 8; ++attempt)
		{
			std::uint32_t count = 0;
			Status status = query(&count, nullptr);
			if (status != success && status != incomplete)
				return status;
			if (!count)
			{
				if (status == incomplete)
					continue;
				output.clear();
				return success;
			}
			std::vector<T> values(count);
			status = query(&count, values.data());
			if (status == success && count <= values.size())
			{
				values.resize(count);
				output = std::move(values);
				return success;
			}
			if (status != success && status != incomplete)
				return status;
		}
		return incomplete;
	}
}
