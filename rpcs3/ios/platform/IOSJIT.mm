#include "IOSPlatform.h"

#include <pthread.h>

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
}
