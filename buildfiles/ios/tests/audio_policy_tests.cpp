// SPDX-License-Identifier: GPL-2.0-only
#include "Emu/Audio/AudioUnit/ios_audio_policy.h"
#include "test_support.h"
#include <array>
#include <random>
#include <vector>

int main()
{
	using namespace ios_audio;
	using test_support::run;
	run("all supported PCM formats and invalid formats", [] {
		for (auto rate : {32000u, 44100u, 48000u, 88200u, 96000u, 176400u, 192000u})
			for (auto channels : {1u, 2u})
				for (auto bytes : {2u, 4u})
					CHECK((pcm_format{rate, channels, bytes}.valid()));
		for (auto f : {pcm_format{0,2,4}, {48000,0,4}, {48000,8,4}, {48000,2,3}, {1,2,4}})
			CHECK(!f.valid());
	});
	run("direct output preserves samples and buffer guards", [] {
		std::array<std::uint8_t, 48> b; b.fill(0xcd);
		auto result = render_pcm(b.data()+8, 32, 4, {}, [](auto bytes, void* output) {
			CHECK(bytes == 32); std::memset(output, 0x23, bytes); return bytes;
		});
		CHECK(result.valid && result.bytes == 32 && result.supplied_frames == 4);
		for (unsigned i=0; i<b.size(); ++i) CHECK(b[i] == (i>=8 && i<40 ? 0x23 : 0xcd));
	});
	run("short and non-frame-aligned writes clear exactly the tail", [] {
		for (std::uint32_t written=0; written<=64; ++written)
		{
			std::array<std::uint8_t, 80> b; b.fill(0xad);
			auto result = render_pcm(b.data()+8, 64, 8, {}, [&](auto, void* output) {
				std::memset(output, 0x56, written); return written;
			});
			CHECK(result.valid && result.supplied_frames == written/8);
			for (unsigned i=0; i<64; ++i) CHECK(b[8+i] == (i<written/8*8 ? 0x56 : 0));
			for (unsigned i=0; i<8; ++i) { CHECK(b[i] == 0xad); CHECK(b[72+i] == 0xad); }
		}
	});
	run("over-reported callback count cannot escape output bounds", [] {
		std::array<std::uint8_t, 8> b{};
		const auto r = render_pcm(b.data(), b.size(), 1, {}, [](auto count, void* out) {
			std::memset(out, 0x22, count); return UINT32_MAX;
		});
		CHECK(r.valid && r.supplied_frames == 1); for (auto v : b) CHECK(v == 0x22);
	});
	run("callback exception is contained and output is silenced", [] {
		std::array<std::uint8_t, 8> b; b.fill(0xff);
		const auto r = render_pcm(b.data(), b.size(), 1, {}, [](auto, void*) -> std::uint32_t {
			throw std::runtime_error("injected producer failure");
		});
		CHECK(r.valid && !r.supplied_frames); for (auto v : b) CHECK(v == 0);
	});
	run("zero, null, undersized and overflowing buffer contracts", [] {
		unsigned calls=0; auto pull = [&](auto, void*) { ++calls; return 0u; };
		std::array<std::uint8_t, 8> b; b.fill(0x34);
		CHECK(render_pcm(nullptr, 0, 0, {}, pull).valid);
		CHECK(!render_pcm(nullptr, 8, 1, {}, pull).valid);
		CHECK(!render_pcm(b.data(), 7, 1, {}, pull).valid);
		CHECK(!render_pcm(b.data(), SIZE_MAX, UINT32_MAX, {}, pull).valid);
		CHECK(!render_pcm(b.data(), 8, 1, {48000, 0, 4}, pull).valid);
		CHECK(calls == 0); for (auto v : b) CHECK(v == 0x34);
	});
	run("randomized PCM size and underrun invariants (10000 cases)", [] {
		std::mt19937 random(0x41554449);
		for (unsigned i=0; i<10000; ++i)
		{
			const auto frames=static_cast<std::uint32_t>(random()%128);
			pcm_format format{48000, static_cast<std::uint32_t>(1+random()%2), static_cast<std::uint32_t>(2+2*(random()%2))};
			const auto frame_bytes=format.channels*format.sample_bytes;
			const auto bytes=frames*frame_bytes;
			const auto written=static_cast<std::uint32_t>(random()%(bytes+1));
			std::vector<std::uint8_t> b(bytes+32, 0xbc);
			const auto r=render_pcm(b.data()+16, bytes, frames, format, [&](auto n, void* out) {
				CHECK(n == bytes); std::memset(out, 0x12, written); return written;
			});
			CHECK(r.valid && r.bytes == bytes && r.supplied_frames == written/frame_bytes);
			for (unsigned j=0; j<bytes; ++j) CHECK(b[j+16] == (j<written/frame_bytes*frame_bytes ? 0x12 : 0));
			for (unsigned j=0; j<16; ++j) { CHECK(b[j] == 0xbc); CHECK(b[16+bytes+j] == 0xbc); }
		}
	});
	run("interruption and foreground state preserve user pause", [] {
		playback_state s;
		CHECK(!s.should_run()); s.play(); CHECK(s.should_run());
		s.interrupt(); CHECK(!s.should_run()); s.interruption_ended(); CHECK(s.should_run());
		s.interrupt(); s.pause(); s.interruption_ended(); CHECK(!s.should_run());
		s.play(); s.set_foreground(false); CHECK(!s.should_run());
		s.interrupt(); s.set_foreground(true); CHECK(s.should_run());
		s.pause(); s.set_foreground(false); s.set_foreground(true); CHECK(!s.should_run());
	});
	run("explicit play recovers a missing interruption end", [] {
		playback_state s; s.play(); s.interrupt(); CHECK(!s.should_run());
		s.play(); CHECK(s.should_run());
	});
	run("close is terminal for every notification order", [] {
		for (unsigned mask=0; mask<256; ++mask)
		{
			playback_state s; s.play(); s.close();
			for (unsigned j=0; j<8; ++j)
			{
				if (mask & (1u<<j)) s.play(); else s.interruption_ended();
				s.set_foreground(j%2); CHECK(s.closed()); CHECK(!s.should_run());
			}
		}
	});
	return test_support::finish();
}
