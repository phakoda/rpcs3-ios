// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

namespace test_support
{
	inline std::uint64_t assertions = 0;
	inline unsigned groups = 0, failures = 0;
	inline void check(bool value, const char* expression, unsigned line)
	{
		++assertions;
		if (!value)
			throw std::runtime_error("line " + std::to_string(line) + ": " + expression);
	}
	template <typename Test> void run(const char* name, Test&& test)
	{
		++groups;
		try { test(); std::cout << "PASS " << name << '\n'; }
		catch (const std::exception& e) { ++failures; std::cerr << "FAIL " << name << ": " << e.what() << '\n'; }
	}
	inline int finish()
	{
		std::cout << groups << " groups, " << assertions << " assertions, " << failures << " failures\n";
		return failures ? 1 : 0;
	}
}
#define CHECK(...) test_support::check(static_cast<bool>((__VA_ARGS__)), #__VA_ARGS__, __LINE__)
