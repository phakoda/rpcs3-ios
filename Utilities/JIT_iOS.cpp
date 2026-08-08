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
