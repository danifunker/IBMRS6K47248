// IBMRS6K7248 - the audio path's bench (audtb.sv: the DMA controller and the CS4232's parts, CLK_HZ 2 MHz): the
// firmware's audio_play sequence (scatter/gather on DMA channel 1, 16-bit stereo at 44.1 kHz), the 8237's
// own path (auto-initialise, 8-bit mono, the codec's PI interrupt), the codec's capture, the Sound Blaster,
// the FM chip's detection, the MPU-401 and the joystick port. ./run.sh builds and runs it.

#include "Vaudtb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static Vaudtb *t;
static uint8_t mem[1 << 20];               // PCI 8000_0000 + n
static int fails, dma_wait;
static std::vector<std::pair<int16_t, int16_t>> out;
static int16_t last_l, last_r;
static bool track;

static void tick() {
	t->dm_ack = 0;
	if (t->dm_req) {
		if (++dma_wait == 2) {
			uint32_t o = uint32_t((uint64_t(t->dm_addr) << 3) - 0x80000000ull);
			if (t->dm_we) { for (int k = 0; k < 8; k++) if (t->dm_be & (0x80 >> k)) mem[o + k] = (t->dm_wdata >> (56 - 8 * k)) & 0xFF; }
			else { uint64_t d = 0; for (int k = 0; k < 8; k++) d = (d << 8) | mem[o + k]; t->dm_rdata = d; }
			t->dm_ack = 1; dma_wait = -100;
		}
	} else dma_wait = 0;
	t->clk = 0; t->eval(); t->clk = 1; t->eval();
	if (track && (int16_t(t->aud_l) != last_l || int16_t(t->aud_r) != last_r)) {
		last_l = t->aud_l; last_r = t->aud_r;
		out.push_back({last_l, last_r});
	}
}
static void run(int n) { for (int i = 0; i < n; i++) tick(); }
static void out8(int port, int v) { t->sel = 1; t->we = 1; t->port = port; t->wdata = v; tick(); t->sel = 0; t->we = 0; tick(); }
static int in8(int port) { t->sel = 1; t->we = 0; t->port = port; tick(); t->sel = 0; tick(); return t->rdata; }
static void wss(int i, int v) { out8(0x534, i); out8(0x535, v); }
static void w32(uint32_t a, uint32_t v) { for (int k = 0; k < 4; k++) mem[a + k] = v >> (8 * k); }
static void expect(const char *what, long got, long want) {
	if (got != want) { printf("  %s: %lX, want %lX\n", what, got, want); fails++; }
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vaudtb;
	t->midi_rx = 1;                                         // an idle MIDI line
	t->reset = 1; run(5); t->reset = 0; run(5);

	// the chip placed and activated (Plug and Play: 00 00, the key, logical device 0, activate, done)
	out8(0x279, 0); out8(0x279, 0);
	out8(0x279, 0x96); for (int i = 0; i < 31; i++) out8(0x279, 0x35 + i);
	out8(0x279, 0x15); out8(0x279, 0x00); out8(0x279, 0x33); out8(0x279, 0x01); out8(0x279, 0x79);
	int f0 = fails;
	expect("WSS present (I12)", (out8(0x534, 12), in8(0x535)), 0x8A);
	expect("version (I25)", (wss(12, 0x40), out8(0x534, 25), in8(0x535)), 0xA2);
	printf("%-46s %s\n", "the codec found and identified", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// audio_play: 16-bit stereo at 44.1 kHz (I8 5B), the DACs on, IEN off
	wss(8, 0x5B); wss(6, 0x00); wss(7, 0x00);
	out8(0x534, 10); int i10 = in8(0x535); out8(0x535, i10 & 0xFD);
	// the sound: 384 frames, two buffers (1024 and 512 bytes), each frame (n, -n - 1)
	const int N = 384;
	for (int n = 0; n < N; n++) {
		uint32_t a = n < 256 ? 0x10000 + 4 * n : 0x20000 + 4 * (n - 256);
		int16_t l = int16_t(n * 37 + 1), r = int16_t(-(n * 37) - 2);
		mem[a] = l & 0xFF; mem[a + 1] = (l >> 8) & 0xFF; mem[a + 2] = r & 0xFF; mem[a + 3] = (r >> 8) & 0xFF;
	}
	w32(0x100, 0x80010000); w32(0x104, 1024 - 1);
	w32(0x108, 0x80020000); w32(0x10C, 0x80000000u | (512 - 1));
	out8(0x0A, 5); out8(0x0B, 9); out8(0x40B, 0x31);
	out8(0x424, 0x00); out8(0x425, 0x01); out8(0x426, 0x00); out8(0x427, 0x80);
	out8(0x411, 1); out8(0xD6, 0xD0); out8(0x0A, 1); out8(0xD4, 0);
	track = true; last_l = 0; last_r = 0; out.clear();
	wss(9, 0x01);                                           // PEN
	int n = 0;
	while (!t->sg_irq && n < 400000) { tick(); n++; }
	expect("IRQ 13 at the list's end", t->sg_irq, 1);
	run(200);
	{
		int bad = 0, k = 0;
		for (int i = 0; i < N && k < (int)out.size(); i++, k++) {
			int16_t l = int16_t(i * 37 + 1), r = int16_t(-(i * 37) - 2);
			if (out[k].first != l || out[k].second != r) { if (bad < 4) printf("  frame %d: %d %d, want %d %d\n", i, out[k].first, out[k].second, l, r); bad++; }
		}
		expect("frames out", (long)out.size() >= N, 1);
		expect("frames wrong", bad, 0);
	}
	expect("channel 1 masked", in8(0x0F) & 0x02, 0x02);
	expect("S/G status: ended", in8(0x419) & 0x0C, 0x04);
	expect("40A: channel 1", in8(0x40A), 0x02);
	expect("IRQ 13 cleared by 40A", t->sg_irq, 0);
	printf("%-46s %s\n", "audio_play: scatter/gather, 16-bit stereo", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// the 8237's own: channel 1 auto-initialise over 64 bytes, 8-bit mono, the playback count 15 (16 frames)
	wss(9, 0x00);
	run(50);
	for (int i = 0; i < 64; i++) mem[0x30000 + i] = uint8_t(0x80 + i * 2 + 1);
	wss(8, 0x0B);                                           // 8-bit unsigned, mono, 44.1 kHz
	out8(0x536, 0);                                         // the status written: the first test's INT clear
	wss(10, 0x02);                                          // IEN
	wss(14, 0x00); wss(15, 0x0F);
	out8(0x0A, 5); out8(0x0C, 0);
	out8(0x02, 0x00); out8(0x02, 0x00);                     // ch1 address 0000
	out8(0x03, 63); out8(0x03, 0);                          // 64 bytes
	out8(0x83, 0x03); out8(0x483, 0x80);                    // page 03, high page 80: 8003_0000
	out8(0x0B, 0x59);                                       // ch1, read, auto-initialise, single
	out8(0x0A, 1);
	track = true; last_l = t->aud_l; last_r = t->aud_r; out.clear();
	wss(9, 0x01);
	n = 0;
	while (!t->irq5 && n < 200000) { tick(); n++; }
	expect("PI interrupt (IRQ 5)", t->irq5, 1);
	expect("I24 PI", (out8(0x534, 24), in8(0x535)) & 0x10, 0x10);
	{
		int bad = 0;
		for (int i = 0; i < 16 && i < (int)out.size(); i++) {
			int16_t v = int16_t((((0x80 + i * 2 + 1) ^ 0x80) & 0xFF) << 8);
			if (out[i].first != v) { if (bad < 4) printf("  frame %d: %d, want %d\n", i, out[i].first, v); bad++; }
		}
		expect("frames before PI", (long)out.size() >= 16, 1);
		expect("frames wrong", bad, 0);
	}
	out8(0x536, 0);                                         // the status written: INT clear
	expect("INT cleared", t->irq5, 0);
	run(20000);
	expect("still playing (auto-initialise)", (long)out.size() > 64, 1);
	printf("%-46s %s\n", "8237 auto-initialise, 8-bit mono, PI", fails != f0 ? "FAIL" : "pass");

	// the codec's capture: 8-bit unsigned mono, the capture count 7 (8 frames); DMA channel 0 writes them
	f0 = fails;
	wss(9, 0x00); run(50);
	for (int i = 0; i < 64; i++) mem[0x38000 + i] = 0x11;
	out8(0x536, 0);
	wss(12, 0x40);                                          // mode 2
	wss(28, 0x00); wss(30, 0x00); wss(31, 0x07);
	out8(0x0A, 4); out8(0x0C, 0);
	out8(0x00, 0x00); out8(0x00, 0x80); out8(0x01, 7); out8(0x01, 0);   // ch0 address 8000, 8 bytes
	out8(0x87, 0x03); out8(0x487, 0x80);                    // 8003_8000
	out8(0x0B, 0x44);                                       // ch0, write (to memory), single
	out8(0x0A, 0);
	wss(9, 0x02);                                           // CEN
	n = 0;
	while (!t->irq5 && n < 200000) { tick(); n++; }
	expect("CI interrupt", t->irq5, 1);
	expect("I24 CI", (out8(0x534, 24), in8(0x535)) & 0x20, 0x20);
	run(3000);                                              // (the transfers of the frames counted)
	{ int bad = 0; for (int i = 0; i < 8; i++) if (mem[0x38000 + 0x8000 + i - 0x8000] != 0x80) bad++; expect("silence written", bad, 0); }
	wss(9, 0x00); out8(0x536, 0); wss(12, 0x00);
	printf("%-46s %s\n", "codec capture: silence by DMA, CI", fails != f0 ? "FAIL" : "pass");

	// the Sound Blaster: the DSP's reset and version, an 8-bit DMA block (11 kHz, 32 bytes) and its IRQ
	f0 = fails;
	out8(0x226, 1); out8(0x226, 0); run(10);
	expect("DSP data waiting", in8(0x22E) & 0x80, 0x80);
	expect("DSP reset AA", in8(0x22A), 0xAA);
	out8(0x22C, 0xE1);
	expect("version 3", in8(0x22A), 0x03);
	expect("version .02", in8(0x22A), 0x02);
	out8(0x224, 0x22); out8(0x225, 0xFF);
	expect("mixer master", (out8(0x224, 0x22), in8(0x225)), 0xFF);
	out8(0x224, 0x04); out8(0x225, 0xFF);
	for (int i = 0; i < 32; i++) mem[0x40000 + i] = uint8_t(0x80 + 4 * i);
	out8(0x0A, 5); out8(0x0C, 0);
	out8(0x02, 0x00); out8(0x02, 0x00); out8(0x03, 31); out8(0x03, 0);
	out8(0x83, 0x04); out8(0x483, 0x80);                    // 8004_0000
	out8(0x0B, 0x49);                                       // ch1, read, single
	out8(0x0A, 1);
	out8(0x22C, 0xD1);                                      // the speaker on
	out8(0x22C, 0x40); out8(0x22C, 165);                    // the time constant: 1,000,000 / 91 = 10989 Hz
	track = true; last_l = t->aud_l; last_r = t->aud_r; out.clear();
	out8(0x22C, 0x14); out8(0x22C, 31); out8(0x22C, 0);     // 32 bytes
	n = 0;
	while (!t->irq5 && n < 400000) { tick(); n++; }
	expect("SB IRQ at the block's end", t->irq5, 1);
	run(3000);
	{
		int bad = 0;
		for (int i = 1; i < 16 && i < (int)out.size(); i++)
			if (out[i].first <= out[i - 1].first) bad++;          // a rising ramp
		expect("SB frames out", (long)out.size() >= 16, 1);
		expect("SB ramp broken", bad, 0);
		if (bad) { for (size_t i = 0; i < out.size() && i < 24; i++) printf(" %d", out[i].first); printf("\n"); }
	}
	in8(0x22E);                                             // acknowledge
	expect("SB IRQ acknowledged", t->irq5, 0);
	track = false;
	printf("%-46s %s\n", "Sound Blaster: reset, version, DMA block, IRQ", fails != f0 ? "FAIL" : "pass");

	// the FM chip found as software finds it: the timers' flags (an AdLib test), the OPL3's status bits clear
	f0 = fails;
	auto fmw = [&](int r, int v) { out8(0x388, r); run(20); out8(0x389, v); run(100); };
	fmw(4, 0x60); fmw(4, 0x80);
	int s1 = in8(0x388);
	fmw(2, 0xFF); fmw(4, 0x21);
	run(400);                                               // 200 us (timer 1: 80 us a step)
	int s2 = in8(0x388);
	fmw(4, 0x60); fmw(4, 0x80);
	expect("status before: clear", s1 & 0xE0, 0x00);
	expect("status after: timer 1", s2 & 0xE0, 0xC0);
	expect("an OPL3 (bits 2:1 clear)", s2 & 0x06, 0x00);
	// a note: FM output moves
	fmw(0x20, 0x01); fmw(0x40, 0x10); fmw(0x60, 0xF0); fmw(0x80, 0x77); fmw(0xA0, 0x98);
	fmw(0x23, 0x01); fmw(0x43, 0x00); fmw(0x63, 0xF0); fmw(0x83, 0x77); fmw(0xB0, 0x31);
	{ int moves = 0; int16_t prev = int16_t(t->fm_snd); for (int i = 0; i < 4000; i++) { tick(); if (int16_t(t->fm_snd) != prev) { moves++; prev = int16_t(t->fm_snd); } } expect("FM output moves", moves > 20, 1); }
	printf("%-46s %s\n", "FM: AdLib detection, OPL3 status, a note", fails != f0 ? "FAIL" : "pass");

	// the MPU-401: reset and UART mode answered FE; a byte out at 31,250 baud, looped back in
	f0 = fails;
	out8(0x331, 0xFF);
	expect("reset: FE waiting", in8(0x331) & 0x80, 0x00);
	expect("reset ack", in8(0x330), 0xFE);
	out8(0x331, 0x3F);
	expect("UART ack", in8(0x330), 0xFE);
	{
		out8(0x330, 0x93);
		// the line: a start bit, 0x93 LSB first, a stop bit; 64 clocks a bit at 2 MHz; looped to midi_rx
		std::vector<int> line;
		for (int i = 0; i < 64 * 12; i++) { t->midi_rx = t->midi_tx; tick(); line.push_back(t->midi_tx); }
		int start = 0; while (start < (int)line.size() && line[start]) start++;
		int b = 0; for (int k = 0; k < 8; k++) b |= line[start + 64 * (k + 1) + 32] << k;
		expect("MIDI byte on the line", b, 0x93);
		t->midi_rx = 1; run(200);
		expect("looped back: waiting", in8(0x331) & 0x80, 0x00);
		expect("looped back: the byte", in8(0x330), 0x93);
	}
	out8(0x331, 0xFF); in8(0x330);
	printf("%-46s %s\n", "MPU-401: commands, MIDI out and in", fails != f0 ? "FAIL" : "pass");

	// the joystick port: left (short), centre, right (long); button A pressed
	f0 = fails;
	auto axis_time = [&](int joy, int ana) {
		t->joy1 = joy; t->ana1 = ana; run(5);
		out8(0x201, 0);
		int k = 0; while ((in8(0x201) & 1) && k < 10000) k++;
		return k;
	};
	int tl = axis_time(0x02, 0), tm = axis_time(0x00, 0), tr = axis_time(0x01, 0);
	expect("left < centre", tl < tm, 1);
	expect("centre < right", tm < tr, 1);
	t->joy1 = 0x10; run(5);
	expect("button A low", in8(0x201) & 0x10, 0x00);
	expect("button B high", in8(0x201) & 0x20, 0x20);
	t->joy1 = 0;
	printf("%-46s %s\n", "joystick: the axes' times, the buttons", fails != f0 ? "FAIL" : "pass");

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
