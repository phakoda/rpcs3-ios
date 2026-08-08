#include <TargetConditionals.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE || !defined(__aarch64__)
#error This probe must target arm64 iOS or arm64 iOS Simulator.
#endif

namespace
{
struct copy_context
{
	void* dst;
	const void* src;
	std::size_t size;
};

int copy_callback(void* opaque) noexcept
{
	if (!opaque)
	{
		return -1;
	}

	const auto& context = *static_cast<const copy_context*>(opaque);
	if (!context.dst || !context.src || !context.size)
	{
		return -1;
	}

	std::memcpy(context.dst, context.src, context.size);
	return 0;
}

struct alignas(16) atomic128_context
{
	void* dst;
	unsigned __int128 value;
};

int atomic128_callback(void* opaque) noexcept
{
	if (!opaque)
	{
		return -1;
	}

	const auto& context = *static_cast<const atomic128_context*>(opaque);
	if (!context.dst || (reinterpret_cast<std::uintptr_t>(context.dst) & 15))
	{
		return -1;
	}

	std::uint64_t words[2];
	std::memcpy(words, &context.value, sizeof(words));
	std::uint64_t previous[2];
	std::uint32_t status;
	__asm__ volatile(
		"1:\n"
		"ldaxp %x[old0], %x[old1], %[dst]\n"
		"stlxp %w[status], %x[new0], %x[new1], %[dst]\n"
		"cbnz %w[status], 1b\n"
		: [status] "=&r"(status), [dst] "+Q"(*static_cast<unsigned __int128*>(context.dst)),
		  [old0] "=&r"(previous[0]), [old1] "=&r"(previous[1])
		: [new0] "r"(words[0]), [new1] "r"(words[1])
		: "memory");
	return 0;
}

PTHREAD_JIT_WRITE_ALLOW_CALLBACKS_NP(copy_callback, atomic128_callback);

[[noreturn]] void fail(int code, const char* operation)
{
	std::fprintf(stderr, "JIT callback probe failed (%s, code %d)\n", operation, code);
	std::exit(code);
}
}

int main()
{
	if (__builtin_available(iOS 17.4, *))
	{
		// Continue with the callback API below.
	}
	else
	{
		fail(9, "iOS 17.4 availability");
	}

	const auto page_size = static_cast<std::size_t>(getpagesize());
	void* const mapping = mmap(nullptr, page_size * 2, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
	if (mapping == MAP_FAILED)
	{
		fail(10, "mmap MAP_JIT");
	}
	void* const data_region = static_cast<std::uint8_t*>(mapping) + page_size;
	if (mprotect(mapping, page_size, PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
	{
		fail(15, "mprotect MAP_JIT code page");
	}

	// mov w0, #42; ret; nop; nop
	alignas(16) constexpr std::uint32_t initial_code[]{
		0x52800540u, 0xd65f03c0u, 0xd503201fu, 0xd503201fu};
	copy_context copy{mapping, initial_code, sizeof(initial_code)};
	if (pthread_jit_write_with_callback_np(copy_callback, &copy) != 0)
	{
		fail(11, "callback copy");
	}

	sys_icache_invalidate(mapping, sizeof(initial_code));
	const auto function = reinterpret_cast<int (*)()>(mapping);
	if (function() != 42)
	{
		fail(12, "initial execution");
	}

	// Atomically replace the 16-byte patch with: mov w0, #43; ret; nop; nop.
	alignas(16) constexpr std::uint32_t patched_code[]{
		0x52800560u, 0xd65f03c0u, 0xd503201fu, 0xd503201fu};
	atomic128_context atomic{mapping, 0};
	std::memcpy(&atomic.value, patched_code, sizeof(patched_code));
	if (pthread_jit_write_with_callback_np(atomic128_callback, &atomic) != 0)
	{
		fail(13, "callback atomic patch");
	}

	sys_icache_invalidate(mapping, sizeof(patched_code));
	if (function() != 43)
	{
		fail(14, "patched execution");
	}

	// RPCS3 keeps non-executable JIT metadata in an RW-only part of the same
	// reservation. It must remain writable after the callback restores execute
	// mode for MAP_JIT code pages.
	constexpr std::uint64_t data_marker = 0x52504353334a4954ull;
	*static_cast<volatile std::uint64_t*>(data_region) = data_marker;
	if (*static_cast<volatile std::uint64_t*>(data_region) != data_marker)
	{
		fail(16, "MAP_JIT RW-only data page");
	}

	munmap(mapping, page_size * 2);
	std::puts("JIT callback probe passed: generated AArch64 returned 42, then 43 after an atomic patch; RW-only JIT data remained writable.");
	return 0;
}
