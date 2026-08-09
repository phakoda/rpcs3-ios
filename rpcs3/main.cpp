#include "stdafx.h"
#include "rpcs3.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#include "Emu/System.h"
#include "Utilities/Thread.h"
#include "util/logs.hpp"

#include <cstdio>
#include <cstdlib>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <exception>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <thread>
#include <typeinfo>
#include <unistd.h>
#endif

LOG_CHANNEL(sys_log, "SYS");

#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Report error and terminate the process after presenting RPCS3's fatal dialog.
[[noreturn]] void report_fatal_error(std::string_view text, bool is_html = false, bool include_help_text = true);

namespace
{
	std::terminate_handler s_previous_terminate_handler{};

	void flush_ios_fatal_logs() noexcept
	{
		try
		{
			logs::listener::sync_all();
		}
		catch (...)
		{
		}

		std::fflush(nullptr);
	}

	[[noreturn]] void ios_terminate_handler() noexcept
	{
		try
		{
			const std::string thread_name = thread_ctrl::get_name();
			const u64 native_thread_id = static_cast<u64>(pthread_mach_thread_np(pthread_self()));

			std::string exception_type = "none";
			std::string exception_text = "no active C++ exception";
			if (const std::exception_ptr exception = std::current_exception())
			{
				try
				{
					std::rethrow_exception(exception);
				}
				catch (const std::exception& error)
				{
					exception_type = typeid(error).name();
					exception_text = error.what();
				}
				catch (...)
				{
					exception_type = "non-std";
					exception_text = "non-std C++ exception";
				}
			}

			u32 emulator_state = umax;
			std::string boot_path;
			std::string title_id;
			if (Emulator::IsAvailable())
			{
				emulator_state = static_cast<u32>(Emu.GetStatus());
				boot_path = Emu.GetBoot();
				title_id = Emu.GetTitleID();
			}

			void* frames[64]{};
			const int frame_count = ::backtrace(frames, static_cast<int>(std::size(frames)));
			std::string backtrace_text;
			for (int index = 0; index < frame_count; index++)
			{
				Dl_info image{};
				if (::dladdr(frames[index], &image) && image.dli_fname)
				{
					const auto image_base = reinterpret_cast<uptr>(image.dli_fbase);
					const auto frame = reinterpret_cast<uptr>(frames[index]);
					fmt::append(backtrace_text, "\n  #%02d %p %s+0x%x (%s)", index, frames[index],
						image.dli_fname, frame - image_base, image.dli_sname ? image.dli_sname : "?");
				}
				else
				{
					fmt::append(backtrace_text, "\n  #%02d %p", index, frames[index]);
				}
			}

			const std::string report = fmt::format(
				"RPCS3 has abnormally terminated.\n"
				"Thread = \"%s\"\n"
				"Native thread id = 0x%x\n"
				"Emulator state = %u\n"
				"Boot path = \"%s\"\n"
				"Title ID = \"%s\"\n"
				"Exception type = \"%s\"\n"
				"Active exception = \"%s\"\n"
				"Native backtrace:%s",
				thread_name, native_thread_id, emulator_state, boot_path, title_id, exception_type, exception_text,
				backtrace_text);

			sys_log.fatal("%s", report);
			flush_ios_fatal_logs();
			report_fatal_error(report, false, true);
		}
		catch (...)
		{
			flush_ios_fatal_logs();
			if (s_previous_terminate_handler && s_previous_terminate_handler != ios_terminate_handler)
			{
				s_previous_terminate_handler();
			}
			std::abort();
		}
	}

	void install_ios_terminate_handler() noexcept
	{
		s_previous_terminate_handler = std::set_terminate(ios_terminate_handler);
		sys_log.notice("Installed iOS terminate diagnostics");
	}

#if !defined(RPCS3_IOS_STIKDEBUG)
	void authorize_vphone_jit() noexcept
	{
		constexpr u16 jit_authorization_port = 1339;
		const sockaddr_in address{
			.sin_len = sizeof(sockaddr_in),
			.sin_family = AF_INET,
			.sin_port = htons(jit_authorization_port),
			.sin_addr = {.s_addr = htonl(INADDR_LOOPBACK)},
		};

		bool authorized = false;
		for (int attempt = 0; attempt < 8 && !authorized; attempt++)
		{
			const int fd = ::socket(AF_INET, SOCK_STREAM, 0);
			if (fd >= 0)
			{
				const timeval timeout{3, 0};
				::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
				::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
				if (::connect(fd, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0)
				{
					char request[32]{};
					const int request_size = std::snprintf(request, sizeof(request), "%d\n", ::getpid());
					if (request_size > 0 && ::send(fd, request, request_size, 0) == request_size)
					{
						char response[16]{};
						const ssize_t response_size = ::recv(fd, response, sizeof(response) - 1, 0);
						authorized = response_size >= 2 && response[0] == 'O' && response[1] == 'K';
					}
				}
				::close(fd);
			}

			if (!authorized && attempt + 1 < 8)
			{
				::usleep(250000);
			}
		}
		if (authorized)
		{
			sys_log.notice("vPhone JIT debug authorization succeeded");
		}
		else
		{
			sys_log.error("vPhone JIT debug authorization failed; executable pages may be rejected by TXM");
		}
	}
#endif
}
#endif

int main(int argc, char** argv)
{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	install_ios_terminate_handler();
#if !defined(RPCS3_IOS_STIKDEBUG)
	// vPhone's debugserver cannot attach until FrontBoard has allowed the app to
	// finish its foreground transition. Let Qt create the scene while a bounded
	// worker retries the authorization handshake; JIT is not entered until boot.
	std::thread(authorize_vphone_jit).detach();
#else
	sys_log.notice("StikDebug JIT mode is active; waiting for the universal-script page handshake during boot");
#endif
#endif

	const int exit_code = run_rpcs3(argc, argv);
	sys_log.notice("RPCS3 terminated with exit code %d", exit_code);
	return exit_code;
}
