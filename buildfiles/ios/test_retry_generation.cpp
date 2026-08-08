#include "rpcs3/ios/IOSRetryGeneration.h"

#include <atomic>
#include <cassert>
#include <thread>

using rpcs3::ios::retry_generation_latch;

int main()
{
    retry_generation_latch latch;

    const auto first = latch.request();
    assert(first.should_start);
    assert(first.generation == 1);

    const auto coalesced = latch.request();
    assert(!coalesced.should_start);
    assert(coalesced.generation == 2);

    const auto handoff = latch.complete(first.generation);
    assert(handoff.should_restart);
    assert(handoff.generation == coalesced.generation);

    const auto settled = latch.complete(handoff.generation);
    assert(!settled.should_restart);

    const auto next = latch.request();
    assert(next.should_start);
    assert(next.generation == 3);
    assert(!latch.complete(next.generation).should_restart);

    // Exercise the completion/request race repeatedly. Every request either
    // starts a chain itself or advances the generation observed by completion.
    for (int iteration = 0; iteration < 2000; ++iteration)
    {
        retry_generation_latch concurrent;
        const auto active = concurrent.request();
        assert(active.should_start);

        std::atomic_bool go = false;
        rpcs3::ios::retry_generation_request raced;
        std::thread requester([&]
        {
            while (!go.load(std::memory_order_acquire))
            {
            }
            raced = concurrent.request();
        });

        go.store(true, std::memory_order_release);
        const auto completed = concurrent.complete(active.generation);
        requester.join();

        assert(raced.generation == 2);
        assert(raced.should_start || completed.should_restart);
        assert(!(raced.should_start && completed.should_restart));

        const std::uint64_t running_generation =
            raced.should_start ? raced.generation : completed.generation;
        assert(!concurrent.complete(running_generation).should_restart);
    }

    return 0;
}
