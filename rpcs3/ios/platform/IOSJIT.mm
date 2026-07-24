#include "IOSPlatform.h"

#import <Security/SecTask.h>

#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstring>

namespace
{
bool entitlement_is_true(CFStringRef entitlement)
{
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task)
    {
        return false;
    }

    CFErrorRef error = nullptr;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, entitlement, &error);
    const bool result = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);

    if (value)
    {
        CFRelease(value);
    }
    if (error)
    {
        CFRelease(error);
    }
    CFRelease(task);
    return result;
}

bool process_is_debugged()
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    kinfo_proc process_info{};
    std::size_t size = sizeof(process_info);
    if (sysctl(mib, static_cast<u_int>(std::size(mib)), &process_info, &size, nullptr, 0) != 0)
    {
        return false;
    }
    return (process_info.kp_proc.p_flag & P_TRACED) != 0;
}

std::size_t aligned_jit_size(std::size_t size)
{
    const long queried_page_size = ::sysconf(_SC_PAGESIZE);
    const std::size_t page_size = static_cast<std::size_t>(std::max<long>(queried_page_size, 4096));
    return (size + page_size - 1) & ~(page_size - 1);
}

void set_error(std::string* error, const char* operation, int code)
{
    if (error)
    {
        *error = std::string(operation) + " failed (" + std::to_string(code) + "): " + std::strerror(code);
    }
}
}

namespace rpcs3::ios
{
bool set_jit_write_protection(bool executable_mode)
{
#if defined(__aarch64__) || defined(__arm64__)
    if (@available(iOS 14.0, *))
    {
        if (pthread_jit_write_protect_supported_np() != 0)
        {
            pthread_jit_write_protect_np(executable_mode ? 1 : 0);
            return true;
        }
    }
#else
    (void)executable_mode;
#endif
    return false;
}

jit_write_scope::jit_write_scope()
    : m_active(set_jit_write_protection(false))
{
}

jit_write_scope::~jit_write_scope()
{
    if (m_active)
    {
        set_jit_write_protection(true);
    }
}

bool jit_write_scope::active() const noexcept
{
    return m_active;
}

jit_capabilities query_extended_jit_capabilities()
{
    jit_capabilities result = query_jit_capabilities();
    result.increased_memory_limit_entitlement = entitlement_is_true(CFSTR("com.apple.developer.kernel.increased-memory-limit"));
    result.extended_virtual_addressing_entitlement = entitlement_is_true(CFSTR("com.apple.developer.kernel.extended-virtual-addressing"));
    result.process_is_debugged = process_is_debugged();

    result.detail +=
        ", increased-memory-limit=" + std::string(result.increased_memory_limit_entitlement ? "present" : "absent") +
        ", extended-virtual-addressing=" + std::string(result.extended_virtual_addressing_entitlement ? "present" : "absent") +
        ", debugged=" + std::string(result.process_is_debugged ? "yes" : "no");
    return result;
}

bool allocate_jit_memory(std::size_t size, jit_memory_region* region, std::string* error)
{
    if (!region || size == 0)
    {
        if (error)
        {
            *error = "A non-empty output region and allocation size are required.";
        }
        return false;
    }

#ifndef MAP_JIT
    if (error)
    {
        *error = "MAP_JIT is unavailable in this SDK.";
    }
    return false;
#else
    *region = {};
    size = aligned_jit_size(size);

    void* executable = ::mmap(nullptr, size, PROT_READ | PROT_EXEC,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (executable != MAP_FAILED)
    {
        mach_vm_address_t writable_address = 0;
        vm_prot_t current_protection = VM_PROT_NONE;
        vm_prot_t maximum_protection = VM_PROT_NONE;
        const kern_return_t remap_result = mach_vm_remap(
            mach_task_self(),
            &writable_address,
            static_cast<mach_vm_size_t>(size),
            0,
            VM_FLAGS_ANYWHERE,
            mach_task_self(),
            reinterpret_cast<mach_vm_address_t>(executable),
            FALSE,
            &current_protection,
            &maximum_protection,
            VM_INHERIT_NONE);

        if (remap_result == KERN_SUCCESS)
        {
            const kern_return_t protect_result = mach_vm_protect(
                mach_task_self(),
                writable_address,
                static_cast<mach_vm_size_t>(size),
                FALSE,
                VM_PROT_READ | VM_PROT_WRITE);
            if (protect_result == KERN_SUCCESS)
            {
                region->writable = reinterpret_cast<void*>(writable_address);
                region->executable = executable;
                region->size = size;
                region->dual_mapped = true;
                return true;
            }

            mach_vm_deallocate(mach_task_self(), writable_address, static_cast<mach_vm_size_t>(size));
        }
        ::munmap(executable, size);
    }

    void* shared = ::mmap(nullptr, size, PROT_READ | PROT_WRITE | PROT_EXEC,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (shared == MAP_FAILED)
    {
        set_error(error, "MAP_JIT allocation", errno);
        return false;
    }

    region->writable = shared;
    region->executable = shared;
    region->size = size;
    region->dual_mapped = false;
    set_jit_write_protection(false);
    return true;
#endif
}

bool publish_jit_memory(jit_memory_region* region, std::size_t offset, std::size_t length, std::string* error)
{
    if (!region || !region->writable || !region->executable || offset > region->size || length > region->size - offset)
    {
        if (error)
        {
            *error = "The JIT publication range is outside the allocated region.";
        }
        return false;
    }

    std::atomic_thread_fence(std::memory_order_release);
    void* executable_start = static_cast<unsigned char*>(region->executable) + offset;
    ::sys_icache_invalidate(executable_start, length);

    if (!region->dual_mapped)
    {
        set_jit_write_protection(true);
    }
    return true;
}

void release_jit_memory(jit_memory_region* region)
{
    if (!region || !region->size)
    {
        return;
    }

    if (region->dual_mapped && region->writable)
    {
        mach_vm_deallocate(mach_task_self(), reinterpret_cast<mach_vm_address_t>(region->writable), static_cast<mach_vm_size_t>(region->size));
    }
    if (region->executable)
    {
        ::munmap(region->executable, region->size);
    }
    *region = {};
}

jit_probe_result run_jit_execution_probe()
{
    jit_probe_result result;
#if !defined(__aarch64__) && !defined(__arm64__)
    result.detail = "The executable JIT probe is implemented only for ARM64.";
    return result;
#else
    const jit_capabilities capabilities = query_extended_jit_capabilities();
    if (!capabilities.map_jit_available || !capabilities.map_jit_allocation_succeeded)
    {
        result.detail = "MAP_JIT preflight failed; execution was not attempted.";
        return result;
    }
    if (!capabilities.dynamic_codesigning_entitlement && !capabilities.allow_jit_entitlement &&
        !capabilities.debugger_entitlement && !capabilities.process_is_debugged)
    {
        result.detail = "No executable-memory entitlement or debugger attachment was detected.";
        return result;
    }

    jit_memory_region region;
    std::string allocation_error;
    if (!allocate_jit_memory(4096, &region, &allocation_error))
    {
        result.detail = std::move(allocation_error);
        return result;
    }

    // mov w0, #42; ret
    constexpr std::uint32_t code[] = {0x52800540u, 0xd65f03c0u};
    result.attempted = true;
    result.dual_mapped = region.dual_mapped;

    if (!region.dual_mapped)
    {
        set_jit_write_protection(false);
    }
    std::memcpy(region.writable, code, sizeof(code));

    std::string publish_error;
    if (!publish_jit_memory(&region, 0, sizeof(code), &publish_error))
    {
        result.detail = std::move(publish_error);
        release_jit_memory(&region);
        return result;
    }

    using probe_function = int (*)();
    const auto function = reinterpret_cast<probe_function>(region.executable);
    result.return_value = function();
    result.succeeded = result.return_value == 42;
    result.detail = result.succeeded
        ? std::string("Executable JIT probe returned 42 using ") + (region.dual_mapped ? "dual mappings." : "thread write protection.")
        : "Executable JIT probe returned " + std::to_string(result.return_value) + ".";

    release_jit_memory(&region);
    return result;
#endif
}
}
