// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <utility>

namespace ios_audio
{
	struct pcm_format
	{
		std::uint32_t sample_rate = 48000;
		std::uint32_t channels = 2;
		std::uint32_t sample_bytes = sizeof(float);

		constexpr bool valid() const noexcept
		{
			if ((channels != 1 && channels != 2) || (sample_bytes != 2 && sample_bytes != 4))
				return false;
			switch (sample_rate)
			{
			case 32000: case 44100: case 48000: case 88200:
			case 96000: case 176400: case 192000: return true;
			default: return false;
			}
		}
	};

	struct render_result
	{
		std::uint32_t bytes = 0;
		std::uint32_t supplied_frames = 0;
		bool valid = false;
	};

	// The producer writes directly into the Audio Unit's buffer. No temporary
	// allocation or full-buffer copy on the normal path. The producer must not
	// write beyond the requested count, and returns the bytes it actually wrote.
	// A short/partial frame is discarded; repeat-last-sample would introduce DC
	// during prolonged underruns. Invalid buffer contracts do not touch memory.
	template <typename Pull>
	render_result render_pcm(void* output, std::size_t capacity,
		std::uint32_t frames, pcm_format format, Pull&& pull) noexcept
	{
		if (!format.valid())
			return {};
		const std::uint32_t frame_bytes = format.channels * format.sample_bytes;
		const std::uint64_t needed = std::uint64_t{frames} * frame_bytes;
		if (needed > capacity || needed > std::numeric_limits<std::uint32_t>::max() || (needed && !output))
			return {};
		const auto bytes = static_cast<std::uint32_t>(needed);
		if (!bytes)
			return {0, 0, true};

		std::uint32_t supplied = 0;
		try
		{
			supplied = std::min<std::uint32_t>(std::forward<Pull>(pull)(bytes, output), bytes);
			supplied -= supplied % frame_bytes;
		}
		catch (...)
		{
			// Never unwind across an Apple C render callback. Silence replaces any
			// partially written data; the adapter records callback failure separately.
			supplied = 0;
		}
		std::memset(static_cast<std::byte*>(output) + supplied, 0, bytes - supplied);
		return {bytes, supplied / frame_bytes, true};
	}

	// Accessed only on the audio control queue, never from the render thread.
	// A late interruption/activation notification must not restart a paused or
	// closed stream. Foreground activation also recovers a missing end event.
	class playback_state
	{
	public:
		void play() noexcept { m_requested = true; m_interrupted = false; }
		void pause() noexcept { m_requested = false; }
		void interrupt() noexcept { m_interrupted = true; }
		void interruption_ended() noexcept { m_interrupted = false; }
		void set_foreground(bool active) noexcept
		{
			if (active && !m_foreground)
				m_interrupted = false;
			m_foreground = active;
		}
		void close() noexcept { m_closed = true; m_requested = false; }
		bool should_run() const noexcept
		{
			return m_requested && m_foreground && !m_interrupted && !m_closed;
		}
		bool closed() const noexcept { return m_closed; }

	private:
		bool m_requested = false;
		bool m_foreground = true;
		bool m_interrupted = false;
		bool m_closed = false;
	};
}
