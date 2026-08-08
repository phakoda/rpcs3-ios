#include "stdafx.h"
#include "util/vm.hpp"
#include "util/logs.hpp"

#include <TargetConditionals.h>
#include <cerrno>
#include <sys/mman.h>

#if !defined(__APPLE__) || !TARGET_OS_IPHONE || !defined(ARCH_ARM64)
#error vm_native_ios.cpp is only valid for arm64 iOS targets
#endif

LOG_CHANNEL(vm_ios_log, "VM-IOS");

namespace utils
{
	// vm_native.cpp is compiled with memory_decommit renamed to this symbol for
	// iOS preset builds. Non-JIT decommits continue through the original code.
	void memory_decommit_platform(void* pointer, usz size, bool can_be_jit);

	void memory_decommit(void* pointer, usz size, bool can_be_jit)
	{
		if (!size)
		{
			return;
		}

		if (!can_be_jit)
		{
			memory_decommit_platform(pointer, size, false);
			return;
		}

		// MAP_JIT cannot be safely recreated at a requested address with
		// MAP_FIXED. The old macOS path unmaps first and then only supplies the
		// address as a hint, which can move the 2 GiB RPCS3 JIT arena. Keep the
		// reservation mapped on iOS and make resident-page reclamation best effort.
		const auto page_size = static_cast<uptr>(get_page_size());
		const uptr address = reinterpret_cast<uptr>(pointer);
		void* const page_base = reinterpret_cast<void*>(address & -page_size);
		const usz page_span = size + (address & (page_size - 1));

#if defined(MADV_FREE)
		constexpr int advice = MADV_FREE;
#elif defined(MADV_DONTNEED)
		constexpr int advice = MADV_DONTNEED;
#else
		constexpr int advice = 0;
#endif

		if constexpr (advice != 0)
		{
			if (::madvise(page_base, page_span, advice) == -1)
			{
				const int error = errno;
				vm_ios_log.warning("JIT decommit kept reservation %p+0x%x but madvise failed (errno=%d)",
					page_base, page_span, error);
			}
			else
			{
				vm_ios_log.trace("JIT decommit preserved reservation %p+0x%x (callback=%d)",
					page_base, page_span, memory_uses_jit_write_callback());
			}
		}
		else
		{
			vm_ios_log.trace("JIT decommit preserved reservation %p+0x%x without page advice (callback=%d)",
				page_base, page_span, memory_uses_jit_write_callback());
		}
	}
}
