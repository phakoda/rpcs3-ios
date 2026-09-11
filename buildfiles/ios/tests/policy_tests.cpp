// SPDX-License-Identifier: GPL-2.0-only
#include "Emu/RSX/Common/presentation_policy.h"
#include "Emu/RSX/Common/framebuffer_key.h"
#include "Input/ios_input_policy.h"

#include <array>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>

namespace
{
	std::uint64_t assertions = 0;
	unsigned groups = 0;
	unsigned failed = 0;

	void check(bool result, const char* expression, unsigned line)
	{
		++assertions;
		if (!result)
			throw std::runtime_error(std::string("line ") + std::to_string(line) + ": " + expression);
	}
#define CHECK(...) check(static_cast<bool>((__VA_ARGS__)), #__VA_ARGS__, __LINE__)

	template <typename Test>
	void test(const char* name, Test run)
	{
		++groups;
		try { run(); std::cout << "PASS " << name << '\n'; }
		catch (const std::exception& error)
		{
			++failed;
			std::cerr << "FAIL " << name << ": " << error.what() << '\n';
		}
	}

	enum class status { success, incomplete, error };
	enum class format { undefined, rgba, bgra, other };
	enum class color_space { srgb, other };
	struct surface_format
	{
		::format format;
		color_space colorSpace;
		bool operator==(const surface_format&) const = default;
	};
}

int main()
{
	using namespace rsx::presentation;
	constexpr auto unlimited = std::numeric_limits<std::uint32_t>::max();
	constexpr extent variable{unlimited, unlimited};

	test("fixed extent overrides stale requested size", [&] {
		CHECK(choose_extent({1, 2}, {1920, 1080}, {1, 1}, {4096, 4096}) == extent{1920, 1080});
		CHECK(choose_extent({99999, 99999}, {1080, 1920}, {1, 1}, {4096, 4096}) == extent{1080, 1920});
	});
	test("variable extent clamps to surface limits", [&] {
		CHECK(choose_extent({32, 9000}, variable, {64, 64}, {2048, 4096}) == extent{64, 4096});
		CHECK(choose_extent({1280, 720}, variable, {1, 1}, {4096, 4096}) == extent{1280, 720});
	});
	test("hidden and unavailable surfaces defer creation", [&] {
		CHECK(!choose_extent({0, 720}, variable, {1, 1}, {4096, 4096}));
		CHECK(!choose_extent({1280, 0}, variable, {1, 1}, {4096, 4096}));
		CHECK(!choose_extent({1280, 720}, {0, 0}, {0, 0}, {4096, 4096}));
		CHECK(!choose_extent({1280, 720}, variable, {0, 0}, {0, 0}));
	});
	test("invalid extent capabilities fail closed", [&] {
		CHECK(!choose_extent({100, 100}, variable, {1000, 1}, {100, 100}));
		CHECK(!choose_extent({100, 100}, {4097, 100}, {1, 1}, {4096, 4096}));
		CHECK(!choose_extent({100, 100}, {1, 1}, {2, 2}, {4096, 4096}));
	});
	test("random extent invariants (25000 cases)", [&] {
		std::mt19937 random(0x505333);
		for (unsigned i = 0; i < 25000; ++i)
		{
			const extent minimum{static_cast<std::uint32_t>(random()) % 128 + 1, static_cast<std::uint32_t>(random()) % 128 + 1};
			const extent maximum{minimum.width + static_cast<std::uint32_t>(random()) % 8192, minimum.height + static_cast<std::uint32_t>(random()) % 8192};
			const extent requested{static_cast<std::uint32_t>(random()) % 16384 + 1, static_cast<std::uint32_t>(random()) % 16384 + 1};
			const auto result = choose_extent(requested, variable, minimum, maximum);
			CHECK(result);
			CHECK(result->width >= minimum.width && result->width <= maximum.width);
			CHECK(result->height >= minimum.height && result->height <= maximum.height);
			CHECK(choose_extent(requested, *result, minimum, maximum) == result);
		}
	});
	test("swapchain image counts: finite and unlimited maxima", [] {
		CHECK(choose_image_count(1, 0) == 3);
		CHECK(choose_image_count(2, 0) == 3);
		CHECK(choose_image_count(3, 0) == 4);
		CHECK(choose_image_count(2, 2) == 2);
		CHECK(choose_image_count(2, 8) == 3);
		CHECK(choose_image_count(4, 4) == 4);
	});
	test("swapchain image count overflow boundary", [&] {
		CHECK(choose_image_count(unlimited, 0) == unlimited);
		CHECK(choose_image_count(unlimited - 1, 0) == unlimited);
		for (std::uint32_t minimum = 1; minimum <= 64; ++minimum)
			for (std::uint32_t maximum = minimum; maximum <= 128; ++maximum)
			{
				const auto result = choose_image_count(minimum, maximum);
				CHECK(result >= minimum && result <= maximum);
			}
	});
	test("format and color space stay paired (original regression)", [] {
		const std::array formats{surface_format{format::rgba, color_space::other},
			surface_format{format::bgra, color_space::srgb}};
		const auto selected = choose_surface_format<surface_format>(formats, format::undefined, format::bgra, color_space::srgb);
		CHECK(selected == formats[1]);
		CHECK(std::find(formats.begin(), formats.end(), *selected) != formats.end());
	});
	test("format preference doesn't fabricate an unsupported color space", [] {
		const std::array formats{surface_format{format::rgba, color_space::srgb},
			surface_format{format::bgra, color_space::other}};
		CHECK(choose_surface_format<surface_format>(formats, format::undefined, format::bgra, color_space::srgb) == formats[1]);
	});
	test("undefined, empty and fallback format lists", [] {
		std::vector<surface_format> formats;
		CHECK(!choose_surface_format<surface_format>(formats, format::undefined, format::bgra, color_space::srgb));
		formats = {{format::undefined, color_space::other}};
		CHECK(choose_surface_format<surface_format>(formats, format::undefined, format::bgra, color_space::srgb) ==
			surface_format{format::bgra, color_space::other});
		formats = {{format::other, color_space::other}, {format::rgba, color_space::srgb}};
		CHECK(choose_surface_format<surface_format>(formats, format::undefined, format::bgra, color_space::srgb) == formats.front());
	});
	test("all composite alpha capability masks", [] {
		const std::array<std::uint32_t, 4> order{1, 8, 2, 4};
		for (std::uint32_t mask = 0; mask < 16; ++mask)
		{
			const auto result = choose_composite_alpha(mask, order);
			CHECK(result.has_value() == (mask != 0));
			if (result)
			{
				CHECK((mask & *result) == *result);
				CHECK((*result & (*result - 1)) == 0);
				for (const auto candidate : order)
					if ((mask & candidate) != 0) { CHECK(*result == candidate); break; }
			}
		}
	});
	test("enumeration publishes exact returned image count", [] {
		std::vector<int> output{99};
		unsigned calls = 0;
		auto query = [&](std::uint32_t* count, int* values) {
			++calls;
			if (!values) { *count = 4; return status::success; }
			CHECK(*count == 4);
			values[0] = 10; values[1] = 20; *count = 2;
			return status::success;
		};
		CHECK(enumerate<int>(query, output, status::success, status::incomplete) == status::success);
		CHECK(output == std::vector<int>{10, 20});
		CHECK(calls == 2);
	});
	test("enumeration retries count growth instead of exposing partial handles", [] {
		std::vector<int> output{99};
		unsigned calls = 0;
		auto query = [&](std::uint32_t* count, int* values) {
			++calls;
			if (!values) { *count = calls == 1 ? 1 : 3; return status::success; }
			if (calls == 2) { values[0] = 1; return status::incomplete; }
			CHECK(*count == 3);
			values[0] = 1; values[1] = 2; values[2] = 3;
			return status::success;
		};
		CHECK(enumerate<int>(query, output, status::success, status::incomplete) == status::success);
		CHECK(output == std::vector<int>{1, 2, 3});
		CHECK(calls == 4);
	});
	test("enumeration errors preserve previously-published output", [] {
		for (const bool error_on_count : {false, true})
		{
			std::vector<int> output{42};
			auto query = [&](std::uint32_t* count, int* values) {
				*count = 1;
				if (error_on_count || values) return status::error;
				return status::success;
			};
			CHECK(enumerate<int>(query, output, status::success, status::incomplete) == status::error);
			CHECK(output == std::vector<int>{42});
		}
	});
	test("unstable driver enumeration has bounded retries", [] {
		unsigned calls = 0;
		std::vector<int> output{42};
		auto query = [&](std::uint32_t* count, int* values) {
			++calls; *count = 2;
			return values ? status::incomplete : status::success;
		};
		CHECK(enumerate<int>(query, output, status::success, status::incomplete) == status::incomplete);
		CHECK(calls == 16);
		CHECK(output == std::vector<int>{42});
	});
	test("zero-count success versus transient incomplete", [] {
		std::vector<int> output{42};
		auto empty = [](std::uint32_t* count, int*) { *count = 0; return status::success; };
		CHECK(enumerate<int>(empty, output, status::success, status::incomplete) == status::success);
		CHECK(output.empty());
		unsigned calls = 0;
		output = {42};
		auto unstable = [&](std::uint32_t* count, int*) { ++calls; *count = 0; return status::incomplete; };
		CHECK(enumerate<int>(unstable, output, status::success, status::incomplete) == status::incomplete);
		CHECK(calls == 8 && output == std::vector<int>{42});
	});
	test("oversized success counts are not published", [] {
		std::vector<int> output{42};
		auto query = [](std::uint32_t* count, int* values) {
			*count = values ? 4 : 1; // No write past the provided capacity.
			return status::success;
		};
		CHECK(enumerate<int>(query, output, status::success, status::incomplete) == status::incomplete);
		CHECK(output == std::vector<int>{42});
	});

	test("axis direction, bounds and neutral position", [] {
		CHECK(ios_input::axis_value(0.f, true) == 0);
		CHECK(ios_input::axis_value(1.f, true) == 32767);
		CHECK(ios_input::axis_value(-1.f, false) == 32767);
		CHECK(ios_input::axis_value(1.f, false) == 0);
		CHECK(ios_input::axis_value(-1.f, true) == 0);
		CHECK(ios_input::axis_value(4.f, true) == 32767);
	});
	test("NaN and infinity never reach integer input casts", [] {
		for (const float value : {std::numeric_limits<float>::quiet_NaN(),
			std::numeric_limits<float>::infinity(), -std::numeric_limits<float>::infinity()})
		{
			CHECK(ios_input::axis_value(value, true) == 0);
			CHECK(ios_input::axis_value(value, false) == 0);
			CHECK(ios_input::trigger_value(value) == 0);
			CHECK(ios_input::sensor_value(value, 113.f) == 512);
			CHECK(ios_input::battery_level(value) == 1.f);
		}
	});
	test("trigger and battery normalization", [] {
		CHECK(ios_input::trigger_value(-1.f) == 0);
		CHECK(ios_input::trigger_value(0.5f) == 127);
		CHECK(ios_input::trigger_value(2.f) == 255);
		CHECK(ios_input::battery_level(-1.f) == 1.f);
		CHECK(ios_input::battery_level(0.5f) == 0.5f);
		CHECK(ios_input::battery_level(2.f) == 1.f);
	});
	test("motion center, saturation and finite overflow", [] {
		CHECK(ios_input::sensor_value(0.f, 113.f) == 512);
		CHECK(ios_input::sensor_value(1.f, 113.f) == 625);
		CHECK(ios_input::sensor_value(-1.f, 113.f) == 399);
		CHECK(ios_input::sensor_value(10.f, 113.f) == 1023);
		CHECK(ios_input::sensor_value(-10.f, 113.f) == 0);
		CHECK(ios_input::sensor_value(std::numeric_limits<float>::max(), std::numeric_limits<float>::max()) == 1023);
		CHECK(ios_input::sensor_value(-std::numeric_limits<float>::max(), std::numeric_limits<float>::max()) == 0);
		CHECK(ios_input::sensor_value(1.f, std::numeric_limits<float>::quiet_NaN()) == 512);
	});
	test("stick center, axis edge and circular diagonal clamp", [] {
		auto p = ios_input::normalize_stick(0.f, 0.f, 50.f);
		CHECK(p.x == 0.f && p.y == 0.f);
		p = ios_input::normalize_stick(100.f, 0.f, 50.f);
		CHECK(p.x == 1.f && p.y == 0.f);
		p = ios_input::normalize_stick(100.f, 100.f, 50.f);
		CHECK(std::abs(p.x - 0.70710678f) < 0.000001f);
		CHECK(std::abs(p.y - 0.70710678f) < 0.000001f);
	});
	test("invalid touch geometry is neutral", [] {
		for (const float radius : {0.f, -1.f, std::numeric_limits<float>::infinity()})
		{
			const auto p = ios_input::normalize_stick(100.f, 100.f, radius);
			CHECK(p.x == 0.f && p.y == 0.f);
		}
		const auto p = ios_input::normalize_stick(std::numeric_limits<float>::quiet_NaN(), 1.f, 50.f);
		CHECK(p.x == 0.f && p.y == 0.f);
	});
	test("random input ranges and circular stick invariants (25000 cases)", [] {
		std::mt19937 random(0x494F53);
		std::uniform_real_distribution<float> position(-10000.f, 10000.f);
		std::uniform_real_distribution<float> radius(0.01f, 300.f);
		for (unsigned i = 0; i < 25000; ++i)
		{
			const float x = position(random), y = position(random);
			const auto p = ios_input::normalize_stick(x, y, radius(random));
			CHECK(std::isfinite(p.x) && std::isfinite(p.y));
			CHECK(std::hypot(p.x, p.y) <= 1.000001f);
			CHECK(ios_input::axis_value(x, true) <= 32767);
			CHECK(ios_input::trigger_value(y) <= 255);
			CHECK(ios_input::sensor_value(x, y) <= 1023);
		}
	});
	test("controller discovery reorder preserves assigned players", [] {
		const std::array previous{1, 2, 3}, connected{3, 1, 2};
		CHECK(ios_input::update_slots<int>(previous, connected) == std::vector<int>{1, 2, 3});
	});
	test("disconnect does not renumber another player", [] {
		const std::array previous{1, 2, 3};
		const std::array connected{2, 3};
		CHECK(ios_input::update_slots<int>(previous, connected) == std::vector<int>{0, 2, 3});
	});
	test("new controllers reuse free ports; trailing holes disappear", [] {
		const std::array previous{1, 2, 3};
		const std::array connected{4, 2};
		CHECK(ios_input::update_slots<int>(previous, connected) == std::vector<int>{4, 2});
	});
	test("empty and duplicate controller discovery is safe", [] {
		const std::array previous{1, 2, 3};
		CHECK(ios_input::update_slots<int>(previous, {}).empty());
		const std::array connected{0, 2, 2, 1, 0};
		CHECK(ios_input::update_slots<int>({}, connected) == std::vector<int>{2, 1});
	});
	test("random connect/disconnect slot stability (10000 cases)", [] {
		std::mt19937 random(0x434F4E54);
		std::vector<int> slots;
		for (unsigned i = 0; i < 10000; ++i)
		{
			std::vector<int> connected;
			for (int id = 1; id <= 7; ++id)
				if ((random() & 1u) != 0) connected.push_back(id);
			std::shuffle(connected.begin(), connected.end(), random);
			const auto next = ios_input::update_slots<int>(slots, connected);
			for (std::size_t index = 0; index < slots.size(); ++index)
				if (slots[index] != 0 && std::find(connected.begin(), connected.end(), slots[index]) != connected.end())
					CHECK(index < next.size() && next[index] == slots[index]);
			for (const int id : connected)
				CHECK(std::count(next.begin(), next.end(), id) == 1);
			for (const int id : next)
				CHECK(id == 0 || std::find(connected.begin(), connected.end(), id) != connected.end());
			slots = next;
		}
	});

	test("framebuffer keys have no indeterminate high bits", [] {
		CHECK(rsx::framebuffer_cache_key(0, 0, false) == 0);
		CHECK(rsx::framebuffer_cache_key(65535, 65535, false) == 0xFFFFFFFFull);
		CHECK(rsx::framebuffer_cache_key(65535, 65535, true) == 0x1FFFFFFFFull);
		CHECK(rsx::framebuffer_cache_key(1280, 720, false) != rsx::framebuffer_cache_key(720, 1280, false));
	});
	test("framebuffer keys preserve every 16-bit dimension", [] {
		for (std::uint32_t value = 0; value <= 65535; ++value)
		{
			const auto dimension = static_cast<std::uint16_t>(value);
			CHECK(rsx::framebuffer_cache_key(dimension, 0, false) == value);
			CHECK(rsx::framebuffer_cache_key(0, dimension, false) == (std::uint64_t{value} << 16));
			CHECK(rsx::framebuffer_cache_key(dimension, dimension, true) ==
				(rsx::framebuffer_cache_key(dimension, dimension, false) | (1ull << 32)));
		}
	});
	test("framebuffer key round-trip invariants (25000 cases)", [] {
		std::mt19937 random(0x46424F);
		for (unsigned i = 0; i < 25000; ++i)
		{
			const auto width = static_cast<std::uint16_t>(random());
			const auto height = static_cast<std::uint16_t>(random());
			const bool input = (random() & 1u) != 0;
			const auto key = rsx::framebuffer_cache_key(width, height, input);
			CHECK((key & 0xFFFF) == width);
			CHECK(((key >> 16) & 0xFFFF) == height);
			CHECK(((key >> 32) & 1) == input);
			CHECK((key >> 33) == 0);
		}
	});

	std::cout << groups << " groups, " << assertions << " assertions, " << failed << " failures\n";
	return failed ? 1 : 0;
}
