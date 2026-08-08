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
#include <exception>
#include <pthread.h>
#include <typeinfo>
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

			const std::string report = fmt::format(
				"RPCS3 has abnormally terminated.\n"
				"Thread = \"%s\"\n"
				"Native thread id = 0x%x\n"
				"Emulator state = %u\n"
				"Boot path = \"%s\"\n"
				"Title ID = \"%s\"\n"
				"Exception type = \"%s\"\n"
				"Active exception = \"%s\"",
				thread_name, native_thread_id, emulator_state, boot_path, title_id, exception_type, exception_text);

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
}
#endif

int main(int argc, char** argv)
{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	install_ios_terminate_handler();
#endif

	const int exit_code = run_rpcs3(argc, argv);
	sys_log.notice("RPCS3 terminated with exit code %d", exit_code);
	return exit_code;
}
