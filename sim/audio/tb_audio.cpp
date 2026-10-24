// IBMRS6K7248 - the audio path's bench (audtb.sv: IBMRS6K7248_dma and IBMRS6K7248_cs4232, CLK_HZ 2 MHz): the
// firmware's audio_play sequence (scatter/gather on DMA channel 1, 16-bit stereo at 44.1 kHz), then the
// 8237's own path (auto-initialise, 8-bit mono, the codec's PI interrupt). ./run.sh builds and runs it.

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
	while (!t->aud_irq && n < 200000) { tick(); n++; }
	expect("PI interrupt (IRQ 5)", t->aud_irq, 1);
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
	expect("INT cleared", t->aud_irq, 0);
	run(20000);
	expect("still playing (auto-initialise)", (long)out.size() > 64, 1);
	printf("%-46s %s\n", "8237 auto-initialise, 8-bit mono, PI", fails != f0 ? "FAIL" : "pass");

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
