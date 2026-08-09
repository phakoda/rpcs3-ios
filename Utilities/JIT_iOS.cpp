#include "util/logs.hpp"

#include <TargetConditionals.h>
#include <atomic>
#include <cerrno>
#include <pthread.h>

#if !defined(__APPLE__) || !TARGET_OS_IPHONE
#error JIT_iOS.cpp is only valid for iOS targets
#endif

LOG_CHANNEL(jit_ios_log, "JIT-IOS");

namespace
{
	std::atomic_bool s_logged_callback_path{false};

	void sync_jit_failure_log() noexcept
	{
		try
		{
			logs::listener::sync_all();
		}
		catch (...)
		{
		}
	}
}

#if defined(RPCS3_IOS_STIKDEBUG) && defined(__aarch64__)
// StikDebug's iOS 26 universal script handles this breakpoint by touching each
// page through debugserver. TXM then permits the prepared mapping to acquire
// executable maximum protection. x0 and x1 already contain address and size.
extern "C" __attribute__((noinline, optnone, naked)) void* rpcs3_ios_stikdebug_prepare_jit_region(void*, size_t)
{
	__asm__ volatile(
		"mov x16, #1\n"
		"brk #0xf00d\n"
		"ret\n");
}
#endif

extern "C" int rpcs3_ios_pthread_jit_write_with_callback_np(pthread_jit_write_callback_t callback, void* context)
{
	errno = 0;
	const int result = pthread_jit_write_with_callback_np(callback, context);
	const int error = errno;

	if (result != 0)
	{
		jit_ios_log.fatal("pthread_jit_write_with_callback_np failed (result=%d, errno=%d, context=%p)",
			result, error, context);
		sync_jit_failure_log();
	}
	else if (!s_logged_callback_path.exchange(true, std::memory_order_relaxed))
	{
		jit_ios_log.notice("Apple JIT write callback path is active");
	}

	errno = error;
	return result;
}
