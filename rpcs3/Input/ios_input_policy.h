// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <span>
#include <vector>

namespace ios_input
{
	inline float finite_clamp(float value, float low, float high, float fallback = 0.f)
	{
		return std::isfinite(value) ? std::clamp(value, low, high) : fallback;
	}

	inline std::uint16_t axis_value(float value, bool positive)
	{
		value = finite_clamp(value, -1.f, 1.f);
		return static_cast<std::uint16_t>(std::max(0.f, positive ? value : -value) * 32767.f);
	}

	inline std::uint16_t trigger_value(float value)
	{
		return static_cast<std::uint16_t>(finite_clamp(value, 0.f, 1.f) * 255.f);
	}

	inline float battery_level(float value)
	{
		// GameController can report a negative value when the level is unknown.
		return value < 0.f ? 1.f : finite_clamp(value, 0.f, 1.f, 1.f);
	}

	inline std::uint16_t sensor_value(float value, float scale)
	{
		// Sanitize before arithmetic/casts, including overflow of finite inputs.
		if (!std::isfinite(value) || !std::isfinite(scale))
			return 512;
		const double scaled = 512.0 + static_cast<double>(value) * scale;
		return static_cast<std::uint16_t>(std::clamp(scaled, 0.0, 1023.0));
	}

	struct stick_position
	{
		float x{};
		float y{};
	};

	inline stick_position normalize_stick(float x, float y, float radius)
	{
		if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(radius) || radius <= 0.f)
			return {};
		// Double intermediates avoid overflow for malformed finite touch data.
		const double length = std::hypot(static_cast<double>(x), static_cast<double>(y));
		const double divisor = std::max(static_cast<double>(radius), length);
		return {static_cast<float>(x / divisor), static_cast<float>(y / divisor)};
	}

	template <typename Id>
	std::vector<Id> update_slots(std::span<const Id> previous, std::span<const Id> connected)
	{
		// Preserve surviving players' port numbers; new devices fill empty ports.
		// Id{} denotes an empty slot. Never index by OS discovery order alone.
		std::vector<Id> slots(previous.begin(), previous.end());
		for (auto& slot : slots)
			if (std::find(connected.begin(), connected.end(), slot) == connected.end())
				slot = Id{};
		for (const auto id : connected)
		{
			if (id == Id{} || std::find(slots.begin(), slots.end(), id) != slots.end())
				continue;
			const auto empty = std::find(slots.begin(), slots.end(), Id{});
			if (empty != slots.end())
				*empty = id;
			else
				slots.push_back(id);
		}
		while (!slots.empty() && slots.back() == Id{})
			slots.pop_back();
		return slots;
	}
}
