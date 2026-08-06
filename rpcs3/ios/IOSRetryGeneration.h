#pragma once

#include <atomic>
#include <cstdint>

namespace rpcs3::ios
{
struct retry_generation_request
{
    std::uint64_t generation = 0;
    bool should_start = false;
};

struct retry_generation_completion
{
    std::uint64_t generation = 0;
    bool should_restart = false;
};

// Coalesces repeated retry requests into one active chain without losing a
// request that arrives while the active chain is completing.
class retry_generation_latch final
{
public:
    retry_generation_request request() noexcept
    {
        const std::uint64_t generation =
            m_generation.fetch_add(1, std::memory_order_acq_rel) + 1;
        const bool should_start = !m_active.exchange(true, std::memory_order_acq_rel);
        return {generation, should_start};
    }

    retry_generation_completion complete(std::uint64_t completed_generation) noexcept
    {
        m_active.store(false, std::memory_order_release);

        const std::uint64_t latest_generation =
            m_generation.load(std::memory_order_acquire);
        if (latest_generation == completed_generation)
        {
            return {latest_generation, false};
        }

        // A request raced with completion. Whichever thread claims the latch is
        // responsible for starting the next chain; the other thread does nothing.
        const bool should_restart = !m_active.exchange(true, std::memory_order_acq_rel);
        return {latest_generation, should_restart};
    }

private:
    std::atomic_uint64_t m_generation = 0;
    std::atomic_bool m_active = false;
};
}
