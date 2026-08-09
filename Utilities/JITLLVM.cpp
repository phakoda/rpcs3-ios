#include "util/types.hpp"
#include "util/sysinfo.hpp"
#include "Utilities/Thread.h"
#include "JIT.h"
#include "StrFmt.h"
#include "File.h"
#include "util/logs.hpp"
#include "mutex.h"
#include "util/vm.hpp"
#include "util/asm.hpp"
#include "Crypto/unzip.h"

#include <charconv>
#include <mutex>

#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#endif

LOG_CHANNEL(jit_log, "JIT");

#ifdef LLVM_AVAILABLE

#include <unordered_map>

#ifdef _MSC_VER
#pragma warning(push, 0)
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#pragma GCC diagnostic ignored "-Wredundant-decls"
#pragma GCC diagnostic ignored "-Weffc++"
#pragma GCC diagnostic ignored "-Wmissing-noreturn"
#endif
#include <llvm/Support/CodeGen.h>
#include "llvm/Support/TargetSelect.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/RTDyldMemoryManager.h"
#include "llvm/ExecutionEngine/ObjectCache.h"
#include "llvm/ExecutionEngine/JITEventListener.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Object/SymbolSize.h"
#ifdef _MSC_VER
#pragma warning(pop)
#else
#pragma GCC diagnostic pop
#endif

#ifdef ARCH_ARM64
#include "Emu/CPU/Backends/AArch64/AArch64Common.h"
#endif

namespace
{
	thread_local std::string* g_llvm_fatal_message = nullptr;

	template <typename F>
	bool run_recoverable_llvm(F&& func, std::string& error)
	{
		error.clear();

		// Run LLVM codegen in a disposable thread. If LLVM invokes the fatal
		// handler, only this helper thread exits.
		named_thread worker("LLVM JIT", [&]()
		{
#if defined(__APPLE__)
			jit_write_protect(false);
#endif
			g_llvm_fatal_message = &error;

			std::forward<F>(func)();

			g_llvm_fatal_message = nullptr;
#if defined(__APPLE__)
			jit_write_protect(true);
#endif
		});

		worker();
		const bool result = static_cast<thread_state>(worker) == thread_state::finished;

		if (!result && error.empty())
		{
			error = "LLVM crash recovery invoked";
		}

		return result;
	}
}

const bool jit_initialize = []() -> bool
{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	// LLVM derives its "native" architecture from the macOS build host while
	// cross-compiling for iOS.  With an AArch64-only LLVM build that leaves the
	// LLVM_NATIVE_TARGET macros undefined, so InitializeNativeTarget() becomes
	// a no-op and MCJIT later reports that no targets are registered.  Register
	// the targets actually compiled into the target-side LLVM instead.
	llvm::InitializeAllTargets();
	llvm::InitializeAllTargetMCs();
	llvm::InitializeAllAsmPrinters();
	llvm::InitializeAllAsmParsers();
#else
	llvm::InitializeNativeTarget();
	llvm::InitializeNativeTargetAsmPrinter();
	llvm::InitializeNativeTargetAsmParser();
#endif
	LLVMLinkInMCJIT();
	return true;
}();

[[noreturn]] static void null(const char* name)
{
	fmt::throw_exception("Null function: %s", name);
}

namespace vm
{
	extern u8* const g_sudo_addr;
}

static shared_mutex null_mtx;

static std::unordered_map<std::string, u64> null_funcs;

static u64 make_null_function(const std::string& name)
{
	if (name.starts_with("__0x"))
	{
		u32 addr = -1;
		auto res = std::from_chars(name.c_str() + 4, name.c_str() + name.size(), addr, 16);

		if (res.ec == std::errc() && res.ptr == name.c_str() + name.size() && addr < 0x8000'0000)
		{
			fmt::throw_exception("Unhandled symbols cementing! (name='%s'", name);
		}
	}

	std::lock_guard lock(null_mtx);

	if (u64& func_ptr = null_funcs[name]) [[likely]]
	{
		// Already exists
		return func_ptr;
	}
	else
	{
		using namespace asmjit;

		// Build a "null" function that contains its name
		const auto func = build_function_asm<void (*)()>("NULL", [&](native_asm& c, auto& args)
		{
#if defined(ARCH_X64)
			Label data = c.newLabel();
			c.lea(args[0], x86::qword_ptr(data, 0));
			c.jmp(Imm(&null));
			c.align(AlignMode::kCode, 16);
			c.bind(data);

			// Copy function name bytes
			for (char ch : name)
				c.db(ch);
			c.db(0);
			c.align(AlignMode::kData, 16);
#else
			// AArch64 implementation
			Label data = c.newLabel();
			Label jump_address = c.newLabel();
			c.ldr(args[0], arm::ptr(data, 0));
			c.ldr(a64::x14, arm::ptr(jump_address, 0));
			c.br(a64::x14);

			// Data frame
			c.align(AlignMode::kCode, 16);
			c.bind(jump_address);
			c.embedUInt64(reinterpret_cast<u64>(&null));

			c.align(AlignMode::kData, 16);
			c.bind(data);
			c.embed(name.c_str(), name.size());
			c.embedUInt8(0U);
			c.align(AlignMode::kData, 16);
#endif
		});

		func_ptr = reinterpret_cast<u64>(func);
		return func_ptr;
	}
}

struct JITAnnouncer : llvm::JITEventListener
{
	void notifyObjectLoaded(u64, const llvm::object::ObjectFile& obj, const llvm::RuntimeDyld::LoadedObjectInfo& info) override
	{
		using namespace llvm;

		object::OwningBinary<object::ObjectFile> debug_obj_ = info.getObjectForDebug(obj);
		if (!debug_obj_.getBinary())
		{
#ifdef __linux__
			jit_log.error("LLVM: Failed to announce JIT events (no debug object)");
#endif
			return;
		}

		const object::ObjectFile& debug_obj = *debug_obj_.getBinary();

		for (const auto& [sym, size] : computeSymbolSizes(debug_obj))
		{
			Expected<object::SymbolRef::Type> type_ = sym.getType();
			if (!type_ || *type_ != object::SymbolRef::ST_Function)
				continue;

			Expected<StringRef> name = sym.getName();
			if (!name)
				continue;

			Expected<u64> addr = sym.getAddress();
			if (!addr)
				continue;

			jit_announce(*addr, size, {name->data(), name->size()});
		}
	}
};

// Simple memory manager
struct MemoryManager1 : llvm::RTDyldMemoryManager
{
	// Direct RWX mappings count against vPhone's process memory allowance even
	// before LLVM writes code into them. Per-module iOS compilers need a small
	// fraction of the desktop reservation, so avoid committing 768 MiB across
	// the three regions merely by constructing the memory manager.
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	static constexpr u64 c_max_size = 0x0200'0000; // 32 MiB for code or data
#else
	// 256 MiB for code or data
	static constexpr u64 c_max_size = 0x1000'0000;
#endif

	// Avoid consuming vPhone's small executable-map allowance in 2 MiB steps.
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	static constexpr u64 c_page_size = 512 * 1024;
#else
	// Allocation unit (2M)
	static constexpr u64 c_page_size = 2 * 1024 * 1024;
#endif

	// Reserve 256 MiB blocks
	void* m_code_mems = nullptr;
	void* m_data_ro_mems = nullptr;
	void* m_data_rw_mems = nullptr;

	u64 code_ptr = 0;
	u64 data_ro_ptr = 0;
	u64 data_rw_ptr = 0;
	bool m_code_finalized = false;
	bool m_executable = true;
	u64 m_code_committed = 0;
	u64 m_data_rw_committed = 0;

#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	struct recycled_arena
	{
		void* base;
		u64 code_committed;
		u64 data_rw_committed;
	};

	inline static std::mutex s_recycled_mutex;
	inline static std::vector<recycled_arena> s_recycled_arenas;
#endif

	// First fallback for non-existing symbols
	// May be a memory container internally
	std::function<u64(const std::string&)> m_symbols_cement;

	MemoryManager1(std::function<u64(const std::string&)> symbols_cement = {}, bool executable = true) noexcept
		: m_executable(executable)
		, m_symbols_cement(std::move(symbols_cement))
	{
		u8* ptr = nullptr;
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (m_executable && !utils::memory_uses_jit_write_callback())
		{
			std::lock_guard lock(s_recycled_mutex);
			if (!s_recycled_arenas.empty())
			{
				const recycled_arena arena = s_recycled_arenas.back();
				s_recycled_arenas.pop_back();
				ptr = static_cast<u8*>(arena.base);
				m_code_committed = arena.code_committed;
				m_data_rw_committed = arena.data_rw_committed;
				if (m_code_committed)
				{
					utils::memory_protect(ptr, m_code_committed, utils::protection::rw);
				}
				if (m_data_rw_committed)
				{
					std::memset(ptr + c_max_size, 0, m_data_rw_committed);
				}
				jit_log.notice("LLVM JIT arena recycled: base=%p, code=0x%x, data=0x%x",
					ptr, m_code_committed, m_data_rw_committed);
			}
		}
#endif
		if (!ptr)
		{
			ptr = reinterpret_cast<u8*>(utils::memory_reserve(c_max_size * 3, m_executable));
		}
		jit_log.notice("LLVM JIT arena reserve: base=%p, size=0x%x, callback=%d",
			ptr, c_max_size * 3, utils::memory_uses_jit_write_callback());
		m_code_mems = ptr;
		// ptr += c_max_size;
		// m_data_ro_mems = ptr;
		 ptr += c_max_size;
		m_data_rw_mems = ptr;
	}

	MemoryManager1(const MemoryManager1&) = delete;

	MemoryManager1& operator=(const MemoryManager1&) = delete;

	~MemoryManager1() override
	{
	#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (m_executable && !utils::memory_uses_jit_write_callback())
		{
			// TXM's executable-map allowance is not immediately returned when a
			// mapping is unmapped. Preserve and recycle retired runtime arenas so a
			// later module reuses already-authorized pages instead of exhausting the
			// allowance through repeated mmap(MAP_FIXED, PROT_EXEC) calls.
			std::lock_guard lock(s_recycled_mutex);
			s_recycled_arenas.push_back({m_code_mems, m_code_committed, m_data_rw_committed});
		}
		else
		{
			utils::memory_release(m_code_mems, c_max_size * 3);
		}
	#else
		// Hack: don't release to prevent reuse of address space, see jit_announce
		// constexpr auto how_much = [](u64 pos) { return utils::align(pos, pos < c_page_size ? c_page_size / 4 : c_page_size); };
		// utils::memory_decommit(m_code_mems, how_much(code_ptr));
		// utils::memory_decommit(m_data_ro_mems, how_much(data_ro_ptr));
		// utils::memory_decommit(m_data_rw_mems, how_much(data_rw_ptr));
		utils::memory_decommit(m_code_mems, c_max_size * 3, true);
	#endif
	}

	void commit_if_needed(void* block, u64 offset, u64 size, utils::protection prot)
	{
		u64& committed = block == m_code_mems ? m_code_committed : m_data_rw_committed;
		const u64 end = offset + size;
		if (end <= committed)
		{
			return;
		}

		const u64 begin = std::max(offset, committed);
		utils::memory_commit(static_cast<u8*>(block) + begin, end - begin, prot);
		committed = end;
	}

	llvm::JITSymbol findSymbol(const std::string& name) override
	{
		u64 addr = RTDyldMemoryManager::getSymbolAddress(name);

		if (!addr && m_symbols_cement)
		{
			addr = m_symbols_cement(name);
		}

		if (!addr)
		{
			addr = make_null_function(name);

			if (!addr)
			{
				fmt::throw_exception("Failed to link '%s'", name);
			}
		}

		return {addr, llvm::JITSymbolFlags::Exported};
	}

	u8* allocate(u64& alloc_pos, void* block, uptr size, u64 align, utils::protection prot)
	{
		align = align ? align : 16;
 
		const u64 sizea = utils::align(size, align);

		if (!size || align > c_page_size || sizea > c_max_size || sizea < size)
		{
			jit_log.fatal("Unsupported size/alignment (size=0x%x, align=0x%x)", size, align);
			return nullptr;
		}

		u64 oldp = alloc_pos;

		u64 olda = utils::align(oldp, align);

		ensure(olda >= oldp);
		ensure(olda < ~sizea);

		u64 newp = olda + sizea;

		if ((newp - 1) / c_max_size != (oldp - 1) / c_max_size)
		{
			constexpr usz num_of_allocations = 1;

			if ((newp - 1) / c_max_size > num_of_allocations)
			{
				// Allocating more than one region does not work for relocations, needs more robust solution
				fmt::throw_exception("Out of memory (size=0x%x, align=0x%x)", size, align);
			}
		}

		// Update allocation counter
		alloc_pos = newp;

		constexpr usz page_quarter = c_page_size / 4;

		// Optimization: split the first allocation to 512 KiB for single-module compilers
		if (oldp < c_page_size && align < page_quarter && (std::min(newp, c_page_size) - 1) / page_quarter != (oldp - 1) / page_quarter)
		{
			const u64 pagea = utils::align(oldp, page_quarter);
			const u64 psize = utils::align(std::min(newp, c_page_size) - pagea, page_quarter);
			jit_log.notice("LLVM JIT initial section commit: block=%p, offset=0x%x, size=0x%x, prot=%d",
				block, pagea % c_max_size, psize, static_cast<int>(prot));
			commit_if_needed(block, pagea % c_max_size, psize, prot);
			jit_log.notice("LLVM JIT initial section commit complete: block=%p, offset=0x%x, size=0x%x",
				block, pagea % c_max_size, psize);

			// Advance
			oldp = pagea + psize;
		}

		if ((newp - 1) / c_page_size != (oldp - 1) / c_page_size)
		{
			// Allocate pages on demand
			const u64 pagea = utils::align(oldp, c_page_size);
			const u64 psize = utils::align(newp - pagea, c_page_size);
			jit_log.notice("LLVM JIT section commit: block=%p, offset=0x%x, size=0x%x, prot=%d",
				block, pagea % c_max_size, psize, static_cast<int>(prot));
			commit_if_needed(block, pagea % c_max_size, psize, prot);
			jit_log.notice("LLVM JIT section commit complete: block=%p, offset=0x%x, size=0x%x",
				block, pagea % c_max_size, psize);
		}

		return reinterpret_cast<u8*>(block) + (olda % c_max_size);
	}

	u8* allocateCodeSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/) override
	{
		auto protection = utils::protection::wx;
	#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (!m_executable)
		{
			protection = utils::protection::rw;
		}

		// vPhone's non-MAP_JIT fallback enforces W^X even when a mapping's
		// maximum protection includes both write and execute. MCJIT can append
		// code after an earlier finalize, so make the existing code range
		// writable again before LLVM touches it and restore RX in finalizeMemory.
		if (m_executable && m_code_finalized && !utils::memory_uses_jit_write_callback())
		{
			utils::memory_protect(m_code_mems, utils::align(code_ptr, utils::get_page_size()), utils::protection::rw);
			m_code_finalized = false;
		}
	#endif
		return allocate(code_ptr, m_code_mems, size, align, protection);
	}

	u8* allocateDataSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/, bool is_ro) override
	{
		if (is_ro)
		{
			// Disabled
			//return allocate(data_ro_ptr, m_data_ro_mems, size, align, utils::protection::rw);
		}

		return allocate(data_rw_ptr, m_data_rw_mems, size, align, utils::protection::rw);
	}

	bool finalizeMemory(std::string* = nullptr) override
	{
	#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (m_executable && code_ptr && !utils::memory_uses_jit_write_callback())
		{
			const usz code_size = utils::align(code_ptr, utils::get_page_size());
			::sys_icache_invalidate(m_code_mems, code_size);
			utils::memory_protect(m_code_mems, code_size, utils::protection::rx);
			m_code_finalized = true;
			jit_log.notice("LLVM JIT code finalized RX: base=%p, size=0x%x", m_code_mems, code_size);
		}
	#endif
		return false;
	}

	void registerEHFrames(u8*, u64, usz) override
	{
	}

	void deregisterEHFrames() override
	{
	}
};

// Simple memory manager
struct MemoryManager2 : llvm::RTDyldMemoryManager
{
	// First fallback for non-existing symbols
	// May be a memory container internally
	std::function<u64(const std::string&)> m_symbols_cement;

#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	std::vector<std::pair<u8*, usz>> m_pending_code;
#endif

	MemoryManager2(std::function<u64(const std::string&)> symbols_cement = {}) noexcept
		: m_symbols_cement(std::move(symbols_cement))
	{
	}

	~MemoryManager2() override
	{
	}

	llvm::JITSymbol findSymbol(const std::string& name) override
	{
		u64 addr = RTDyldMemoryManager::getSymbolAddress(name);

		if (!addr && m_symbols_cement)
		{
			addr = m_symbols_cement(name);
		}

		if (!addr)
		{
			addr = make_null_function(name);

			if (!addr)
			{
				fmt::throw_exception("Failed to link '%s' (MM2)", name);
			}
		}

		return {addr, llvm::JITSymbolFlags::Exported};
	}

	u8* allocateCodeSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/) override
	{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (!utils::memory_uses_jit_write_callback())
		{
			// This manager normally shares RPCS3's AsmJit pool. A prior
			// trampoline can have finalized the current pool page RX, while LLVM
			// writes its section directly instead of using jit_write_copy(). Keep
			// LLVM sections page-disjoint, reopen them RW, then finalize them RX.
			const usz page_size = utils::get_page_size();
			u8* const result = jit_runtime::alloc(size, std::max<usz>(align, page_size), true);
			utils::memory_protect(result, size, utils::protection::rw);
			m_pending_code.emplace_back(result, size);
			return result;
		}
#endif
		return jit_runtime::alloc(size, align, true);
	}

	u8* allocateDataSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/, bool /*is_ro*/) override
	{
		return jit_runtime::alloc(size, align, false);
	}

	bool finalizeMemory(std::string* = nullptr) override
	{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
		if (!utils::memory_uses_jit_write_callback())
		{
			for (const auto& [pointer, size] : m_pending_code)
			{
				::sys_icache_invalidate(pointer, size);
				utils::memory_protect(pointer, size, utils::protection::rx);
			}
			m_pending_code.clear();
		}
#endif
		return false;
	}

	void registerEHFrames(u8*, u64, usz) override
	{
	}

	void deregisterEHFrames() override
	{
	}
};

// Helper class
class ObjectCache final : public llvm::ObjectCache
{
	const std::string& m_path;
	const std::add_pointer_t<jit_compiler> m_compiler = nullptr;

public:
	ObjectCache(const std::string& path, jit_compiler* compiler = nullptr)
		: m_path(path)
		, m_compiler(compiler)
	{
	}

	~ObjectCache() override = default;

	void notifyObjectCompiled(const llvm::Module* _module, llvm::MemoryBufferRef obj) override
	{
		std::string name = m_path;

		name.append(_module->getName());
		//fs::file(name, fs::rewrite).write(obj.getBufferStart(), obj.getBufferSize());
		name.append(".gz");

		if (!obj.getBufferSize())
		{
			jit_log.error("LLVM: Nothing to write: %s", name);
			return;
		}

		ensure(m_compiler);

		fs::pending_file module_file;

		if (!module_file.open((name)))
		{
			jit_log.error("LLVM: Failed to create module file: %s (%s)", name, fs::g_tls_error);
			return;
		}

		// Bold assumption about upper limit of space consumption
		const usz max_size = obj.getBufferSize() * 4;

		if (!m_compiler->add_sub_disk_space(0 - max_size))
		{
			jit_log.error("LLVM: Failed to create module file: %s (not enough disk space left)", name);
			return;
		}

		if (!zip(obj.getBufferStart(), obj.getBufferSize(), module_file.file))
		{
			jit_log.error("LLVM: Failed to compress module: %s", std::string(_module->getName()));
			return;
		}

		jit_log.trace("LLVM: Created module: %s", std::string(_module->getName()));

		// Restore space that was overestimated
		ensure(m_compiler->add_sub_disk_space(max_size - module_file.file.size()));
		module_file.commit();
	}

	static std::unique_ptr<llvm::MemoryBuffer> load(const std::string& path)
	{
		if (fs::file cached{path + ".gz", fs::read})
		{
			const std::vector<u8> cached_data = cached.to_vector<u8>();

			if (cached_data.empty()) [[unlikely]]
			{
				return nullptr;
			}

			const std::vector<u8> out = unzip(cached_data);

			if (out.empty())
			{
				jit_log.error("LLVM: Failed to unzip module: '%s'", path);
				return nullptr;
			}

			auto buf = llvm::WritableMemoryBuffer::getNewUninitMemBuffer(out.size());
			std::memcpy(buf->getBufferStart(), out.data(), out.size());
			return buf;
		}

		if (fs::file cached{path, fs::read})
		{
			if (cached.size() == 0) [[unlikely]]
			{
				return nullptr;
			}

			auto buf = llvm::WritableMemoryBuffer::getNewUninitMemBuffer(cached.size());
			cached.read(buf->getBufferStart(), buf->getBufferSize());
			return buf;
		}

		return nullptr;
	}

	std::unique_ptr<llvm::MemoryBuffer> getObject(const llvm::Module* _module) override
	{
		std::string path = m_path;
		path.append(_module->getName().data());

		if (auto buf = load(path))
		{
			jit_log.notice("LLVM: Loaded module: %s", _module->getName().data());
			return buf;
		}

		return nullptr;
	}
};

std::string jit_compiler::cpu(std::string_view _cpu)
{
	std::string m_cpu = std::string(_cpu);

	if (m_cpu.empty())
	{
		m_cpu = llvm::sys::getHostCPUName().str();

		if (m_cpu == "generic")
		{
			// Try to detect a best match based on other criteria
			m_cpu = fallback_cpu_detection();
		}

		if (m_cpu == "sandybridge" ||
			m_cpu == "ivybridge" ||
			m_cpu == "haswell" ||
			m_cpu == "broadwell" ||
			m_cpu == "skylake" ||
			m_cpu == "skylake-avx512" ||
			m_cpu == "cascadelake" ||
			m_cpu == "cooperlake" ||
			m_cpu == "cannonlake" ||
			m_cpu == "icelake" ||
			m_cpu == "icelake-client" ||
			m_cpu == "icelake-server" ||
			m_cpu == "tigerlake" ||
			m_cpu == "rocketlake" ||
			m_cpu == "alderlake" ||
			m_cpu == "raptorlake" ||
			m_cpu == "meteorlake")
		{
			// Downgrade if AVX is not supported by some chips
			if (!utils::has_avx())
			{
				m_cpu = "nehalem";
			}
		}

		if (m_cpu == "skylake-avx512" ||
			m_cpu == "cascadelake" ||
			m_cpu == "cooperlake" ||
			m_cpu == "cannonlake" ||
			m_cpu == "icelake" ||
			m_cpu == "icelake-client" ||
			m_cpu == "icelake-server" ||
			m_cpu == "tigerlake" ||
			m_cpu == "rocketlake")
		{
			// Downgrade if AVX-512 is disabled or not supported
			if (!utils::has_avx512())
			{
				m_cpu = "skylake";
			}
		}

		if (m_cpu == "znver1" && utils::has_clwb())
		{
			// Upgrade
			m_cpu = "znver2";
		}

		if ((m_cpu == "znver3" || m_cpu == "goldmont" || m_cpu == "alderlake" || m_cpu == "raptorlake" || m_cpu == "meteorlake") && utils::has_avx512_icl())
		{
			// Upgrade
			m_cpu = "icelake-client";
		}

		if (m_cpu == "goldmont" && utils::has_avx2())
		{
			// Upgrade
			m_cpu = "alderlake";
		}
	}

	return m_cpu;
}

std::string jit_compiler::triple1()
{
#if defined(_WIN32)
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#elif defined(__APPLE__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif (defined(__ANDROID__) || defined(__APPLE__)) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-android"); // Set environment to android to reserve x18
#elif defined(__ANDROID__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-android");
#else
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#endif
}

std::string jit_compiler::triple2()
{
#if defined(_WIN32) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif defined(_WIN32) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-gnu");
#elif defined(__APPLE__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif (defined(__ANDROID__) || defined(__APPLE__)) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-android"); // Set environment to android to reserve x18
#elif defined(__ANDROID__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-android"); // Set environment to android to reserve x18
#else
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#endif
}

bool jit_compiler::add_sub_disk_space(ssz space)
{
	if (space >= 0)
	{
		ensure(m_disk_space.fetch_add(space) < ~static_cast<usz>(space));
		return true;
	}

	return m_disk_space.fetch_op([sub_size = static_cast<usz>(0 - space)](usz& val)
	{
		if (val >= sub_size)
		{
			val -= sub_size;
			return true;
		}

		return false;
	}).second;
}

jit_compiler::jit_compiler(const std::unordered_map<std::string, u64>& _link, std::string_view _cpu, u32 flags, std::function<u64(const std::string&)> symbols_cement) noexcept
	: m_context(new llvm::LLVMContext)
	, m_cpu(cpu(_cpu))
{
#if defined(__APPLE__) && defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
	// The vPhone CPU is reported as an Apple host model, but RPCS3 deliberately
	// targets the Android AArch64 ABI to reserve x18. Combining that ABI triple
	// with the Apple-specific scheduler model fails during target-machine
	// construction on the iOS cross-build. Keep RPCS3's explicit feature list
	// while using LLVM's ABI-neutral AArch64 CPU model.
	m_cpu = "generic";
#endif

	[[maybe_unused]] static const bool s_install_llvm_error_handler = []()
	{
		llvm::remove_fatal_error_handler();
		llvm::install_fatal_error_handler([](void*, const char* msg, bool)
		{
			const std::string_view out = msg ? msg : "";

			if (g_llvm_fatal_message)
			{
				*g_llvm_fatal_message = out;
				thread_ctrl::silent_exit();
			}

			fmt::throw_exception("LLVM Emergency Exit Invoked: '%s'", out);
		}, nullptr);

		return true;
	}();

	std::string result;

	auto null_mod = std::make_unique<llvm::Module> ("null_", *m_context);
#if LLVM_VERSION_MAJOR >= 21 && (LLVM_VERSION_MINOR >= 1 || LLVM_VERSION_MAJOR >= 22)
	null_mod->setTargetTriple(llvm::Triple(jit_compiler::triple1()));
#else
	null_mod->setTargetTriple(jit_compiler::triple1());
#endif

	std::unique_ptr<llvm::RTDyldMemoryManager> mem;

	if (_link.empty())
	{
		// Auxiliary JIT (does not use custom memory manager, only writes the objects)
		if (flags & 0x1)
		{
			mem = std::make_unique<MemoryManager1>(std::move(symbols_cement), false);
		}
		else
		{
			mem = std::make_unique<MemoryManager2>(std::move(symbols_cement));
#if LLVM_VERSION_MAJOR >= 21 && (LLVM_VERSION_MINOR >= 1 || LLVM_VERSION_MAJOR >= 22)
			null_mod->setTargetTriple(llvm::Triple(jit_compiler::triple2()));
#else
			null_mod->setTargetTriple(jit_compiler::triple2());
#endif
		}
	}
	else
	{
		mem = std::make_unique<MemoryManager1>(std::move(symbols_cement));
	}

	std::vector<std::string> attributes;

#if defined(ARCH_ARM64)
	if (utils::has_sha3())
		attributes.push_back("+sha3");
	else
		attributes.push_back("-sha3");

	if (utils::has_dotprod())
		attributes.push_back("+dotprod");
	else
		attributes.push_back("-dotprod");

	// The recompilers emit i8mm intrinsics (e.g. ummla) gated on utils::has_i8mm().
	// The JIT target features must advertise i8mm too, otherwise the backend fails
	// with "Cannot select: intrinsic %llvm.aarch64.neon.ummla" whenever the resolved
	// -mcpu does not already imply it (e.g. the cortex-a78 fallback on Apple silicon).
	if (utils::has_i8mm())
		attributes.push_back("+i8mm");
	else
		attributes.push_back("-i8mm");

	if (utils::has_sve())
		attributes.push_back("+sve");
	else
		attributes.push_back("-sve");

	if (utils::has_sve2())
		attributes.push_back("+sve2");
	else
		attributes.push_back("-sve2");
#endif

	{
		jit_log.notice("LLVM engine creation begin: triple='%s', cpu='%s', flags=0x%x",
			null_mod->getTargetTriple(), m_cpu, flags);
		m_engine.reset(llvm::EngineBuilder(std::move(null_mod))
			.setErrorStr(&result)
			.setEngineKind(llvm::EngineKind::JIT)
			.setMCJITMemoryManager(std::move(mem))
			.setOptLevel(llvm::CodeGenOptLevel::Aggressive)
			.setCodeModel(flags & 0x2 ? llvm::CodeModel::Large : llvm::CodeModel::Small)
#ifdef __APPLE__
			//.setCodeModel(llvm::CodeModel::Large)
#endif
			.setRelocationModel(llvm::Reloc::Model::PIC_)
			.setMAttrs(attributes)
			.setMCPU(m_cpu)
			.create());
		jit_log.notice("LLVM engine creation complete: engine=%p, error='%s'", m_engine.get(), result);
	}

	if (!_link.empty())
	{
		for (auto&& [name, addr] : _link)
		{
			m_engine->updateGlobalMapping(name, addr);
		}
	}

	if (!_link.empty() || !(flags & 0x1))
	{
		jit_log.notice("LLVM JIT listener registration begin");
		m_engine->RegisterJITEventListener(llvm::JITEventListener::createIntelJITEventListener());
		m_engine->RegisterJITEventListener(new JITAnnouncer);
		jit_log.notice("LLVM JIT listener registration complete");
	}

	if (!m_engine)
	{
		fmt::throw_exception("LLVM: Failed to create ExecutionEngine: %s", result);
	}

	fs::device_stat stats{};

	if (fs::statfs(fs::get_cache_dir(), stats))
	{
		m_disk_space = stats.avail_free / 4;
	}
}

jit_compiler& jit_compiler::operator=(thread_state s) noexcept
{
	if (s == thread_state::destroying_context)
	{
		// Release resources explicitly
		m_engine.reset();
		m_context.reset();
	}

	return *this;
}

jit_compiler::~jit_compiler() noexcept
{
}

void jit_compiler::add(std::unique_ptr<llvm::Module> _module, const std::string& path)
{
	ObjectCache cache{path, this};
	m_engine->setObjectCache(&cache);

	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));
	m_engine->generateCodeForModule(ptr);
	m_engine->setObjectCache(nullptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}
}

bool jit_compiler::try_add(std::unique_ptr<llvm::Module> _module, const std::string& path, std::string& error)
{
	ObjectCache cache{path, this};
	m_engine->setObjectCache(&cache);

	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));

	if (!run_recoverable_llvm([&]()
	{
		m_engine->generateCodeForModule(ptr);
	}, error))
	{
		return false;
	}

	m_engine->setObjectCache(nullptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}

	return true;
}

void jit_compiler::add(std::unique_ptr<llvm::Module> _module)
{
	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));
	m_engine->generateCodeForModule(ptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}
}

bool jit_compiler::try_add(std::unique_ptr<llvm::Module> _module, std::string& error)
{
	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));

	if (!run_recoverable_llvm([&]()
	{
		m_engine->generateCodeForModule(ptr);
	}, error))
	{
		return false;
	}

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}

	return true;
}

bool jit_compiler::add(const std::string& path)
{
	auto cache = ObjectCache::load(path);

	if (!cache)
	{
		jit_log.error("ObjectCache: Failed to read file. (path='%s', error=%s)", path, fs::g_tls_error);
		return false;
	}

	if (auto object_file = llvm::object::ObjectFile::createObjectFile(*cache))
	{
		m_engine->addObjectFile(llvm::object::OwningBinary<llvm::object::ObjectFile>(std::move(*object_file), std::move(cache)));
		jit_log.trace("ObjectCache: Successfully added %s", path);
		return true;
	}
	else
	{
		jit_log.error("ObjectCache: Adding failed: %s", path);
		return false;
	}
}

bool jit_compiler::check(const std::string& path)
{
	if (auto cache = ObjectCache::load(path))
	{
		if (auto object_file = llvm::object::ObjectFile::createObjectFile(*cache))
		{
			return true;
		}

		if (fs::remove_file(path))
		{
			jit_log.error("ObjectCache: Removed damaged file: %s", path);
		}
	}

	return false;
}

void jit_compiler::update_global_mapping(const std::string& name, u64 addr)
{
	m_engine->updateGlobalMapping(name, addr);
}

void jit_compiler::fin()
{
	m_engine->finalizeObject();
}

bool jit_compiler::try_fin(std::string& error)
{
	return run_recoverable_llvm([&]()
	{
		m_engine->finalizeObject();
	}, error);
}

u64 jit_compiler::get(const std::string& name)
{
	return m_engine->getGlobalValueAddress(name);
}

const char * fallback_cpu_detection()
{
#if defined(ARCH_X64)
	// If we got here we either have a very old and outdated CPU or a new CPU that has not been seen by LLVM yet.
	const std::string brand = utils::get_cpu_brand();
	const auto family = utils::get_cpu_family();
	const auto model = utils::get_cpu_model();

	jit_log.error("CPU wasn't identified by LLVM, brand = %s, family = 0x%x, model = 0x%x", brand, family, model);

	if (brand.starts_with("AMD"))
	{
		switch (family)
		{
		case 0x10:
		case 0x12: // Unimplemented in LLVM
			return "amdfam10";
		case 0x15:
			// Bulldozer class, includes piledriver, excavator, steamroller, etc
			return utils::has_avx2() ? "bdver4" : "bdver1";
		case 0x17:
		case 0x18:
			// No major differences between znver1 and znver2, return the lesser
			return "znver1";
		case 0x19:
			// Models 0-Fh are zen3 as are 20h-60h. The rest we can assume are zen4
			return ((model >= 0x20 && model <= 0x60) || model < 0x10) ? "znver3" : "znver4";
		case 0x1a:
			// Only one generation in family 1a so far, zen5, which we do not support yet.
			// Return zen4 as a workaround until the next LLVM upgrade.
			return "znver4";
		default:
			// Safest guesses
			return utils::has_avx512() ? "znver4" :
			       utils::has_avx2()   ? "znver1" :
			       utils::has_avx()    ? "bdver1" :
			                             "nehalem";
		}
	}
	else if (brand.find("Intel") != std::string::npos)
	{
		if (!utils::has_avx())
		{
			return "nehalem";
		}
		if (!utils::has_avx2())
		{
			return "ivybridge";
		}
		if (!utils::has_avx512())
		{
			return "skylake";
		}
		if (utils::has_avx512_icl())
		{
			return "cannonlake";
		}
		return "icelake-client";
	}
	else if (brand.starts_with("VirtualApple"))
	{
		// No AVX. This will change in MacOS 15+, at which point we may revise this.
		return utils::has_avx() ? "haswell" : "nehalem";
	}

#elif defined(ARCH_ARM64)
#ifdef ANDROID
	static std::string s_result = []() -> std::string
	{
		std::string result = aarch64::get_cpu_name();
		if (result.empty())
		{
			return "cortex-a78";
		}

		std::transform(result.begin(), result.end(), result.begin(), ::tolower);
		return result;
	}();

	return s_result.c_str();
#else
	// TODO: Read the data from /proc/cpuinfo. ARM CPU registers are not accessible from usermode.
	// This will be a pain when supporting snapdragon on windows but we'll cross that bridge when we get there.
	// Require at least armv8-2a. Older chips are going to be useless anyway.
	return "cortex-a78";
#endif
#endif

	// Failed to guess, use generic fallback
	return "generic";
}

#endif // LLVM_AVAILABLE
