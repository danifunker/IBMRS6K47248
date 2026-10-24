// IBMRS6K7248 - a bench of the S3's picture side alone (IBMRS6K7248_s3video): a DDR3 model on its DDRAM port, a
// small mode at each depth (8 bits through the palette, 15, 16 and 32 direct), the hardware cursor over it; every
// shown pixel of a frame checked against a model here. ./run.sh builds and runs it.

#include "VIBMRS6K7248_s3video.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <deque>

static VIBMRS6K7248_s3video *t;
static uint8_t vram[2 << 20];
static uint32_t pal[256];                 // 18 bits: 6 a component
static const uint32_t DDR_BASE = 0x06000000;
static std::deque<uint64_t> rq;           // the words a burst read owes
static int fails;

static void tick() {
	// DDR3: never busy; a burst read's words one a clock, from the clock after it is asked
	t->ddr_busy = 0;
	t->ddr_dout_ready = 0;
	if (!rq.empty()) { t->ddr_dout = rq.front(); rq.pop_front(); t->ddr_dout_ready = 1; }
	if (t->ddr_rd) {
		uint32_t w = t->ddr_addr - DDR_BASE;
		for (int i = 0; i < t->ddr_burstcnt; i++) {
			uint64_t d = 0;
			for (int k = 0; k < 8; k++) d |= (uint64_t)vram[((w + i) * 8 + k) & ((2 << 20) - 1)] << (8 * k);
			rq.push_back(d);
		}
	}
	// the palette's port: the colour a clock later
	uint32_t q = pal[t->pal_addr];
	t->clk = 0; t->eval();
	t->clk = 1; t->eval();
	t->pal_q = q;
	t->eval();
}

static uint32_t dcol(int depth, uint32_t p) {
	auto w5 = [](uint32_t v) { return (v << 3) | (v >> 2); };
	auto w6 = [](uint32_t v) { return (v << 2) | (v >> 4); };
	if (depth == 1) return (w5((p >> 10) & 31) << 16) | (w5((p >> 5) & 31) << 8) | w5(p & 31);
	if (depth == 2) return (w5((p >> 11) & 31) << 16) | (w6((p >> 5) & 63) << 8) | w5(p & 31);
	return p & 0xFFFFFF;
}
static uint32_t pcol(uint32_t e) {          // a palette entry widened
	auto w = [](uint32_t v) { return (v << 2) | (v >> 4); };
	return (w((e >> 12) & 63) << 16) | (w((e >> 6) & 63) << 8) | w(e & 63);
}

static const int W = 40, H = 8, START = 0x108, PITCH = 256, CX = 5, CY = 2, CBASE = 1;  // the cursor at KB 1

static void run_depth(int depth, const char *name, uint32_t fg, uint32_t bg) {
	int ps = depth == 0 ? 1 : depth == 3 ? 4 : 2;
	// the frame: a different value at every pixel
	for (int y = 0; y < H; y++)
		for (int x = 0; x < W; x++) {
			uint32_t v = (uint32_t)(0x9E3779B1u * (y * 64 + x + 1 + depth * 1000));
			for (int k = 0; k < ps; k++) vram[START + y * PITCH + x * ps + k] = (v >> (8 * k)) & 0xFF;
		}
	// the cursor: row 0's first group AND 3FFF XOR C000 (pixels 0, 1 the foreground), pixel 2 AND 0 XOR 0 (the
	// background) by group 0 being AND 1FFF XOR C000; every other bit AND 1 XOR 0 (the screen)
	for (int r = 0; r < 64; r++)
		for (int g = 0; g < 4; g++) {
			uint8_t *p = &vram[CBASE * 1024 + r * 16 + g * 4];
			uint16_t a = 0xFFFF, xo = 0x0000;
			if (r == 0 && g == 0) { a = 0x1FFF; xo = 0xC000; }
			p[0] = a >> 8; p[1] = a & 0xFF; p[2] = xo >> 8; p[3] = xo & 0xFF;
		}

	t->reset = 1;
	t->h_total = 64; t->h_disp = W; t->h_ss = 48; t->h_sl = 8;
	t->v_total = 12; t->v_disp = H; t->v_ss = 9; t->v_sl = 1;
	t->depth = depth; t->start = START; t->pitch = PITCH; t->screen_on = 1; t->pix_mask = 0xFF;
	t->pll_m = 127; t->pll_n = 0;                     // at or above the video clock: a pixel every clock
	t->cur_on = 1; t->cur_x = CX; t->cur_y = CY; t->cur_base = CBASE; t->cur_x11 = 0;
	t->cur_fg = fg; t->cur_bg = bg;
	t->c_req = 0;
	rq.clear();
	for (int i = 0; i < 10; i++) tick();
	t->reset = 0;

	// two frames; the second checked
	static uint32_t got[H][W];
	int x = 0, y = 0, frame = 0, seen = 0;
	bool hb_q = true, vb_q = true;
	for (long i = 0; i < 64 * 12 * 3 + 200 && frame < 3; i++) {
		tick();
		if (!t->ce_pix) continue;
		if (t->vblank && !vb_q) frame++;
		if (!t->vblank && vb_q) y = 0;
		if (t->hblank && !hb_q && !t->vblank) y++;
		if (!t->hblank && hb_q) x = 0;
		if (frame == 1 && !t->hblank && !t->vblank && y < H && x < W) { got[y][x] = (t->r << 16) | (t->g << 8) | t->b; x++; seen++; }
		hb_q = t->hblank; vb_q = t->vblank;
	}
	int bad = 0;
	for (int yy = 0; yy < H; yy++)
		for (int xx = 0; xx < W; xx++) {
			uint32_t v = 0;
			for (int k = 0; k < ps; k++) v |= (uint32_t)vram[START + yy * PITCH + xx * ps + k] << (8 * k);
			uint32_t want;
			bool cur = yy == CY && xx >= CX && xx < CX + 3;
			if (depth == 0) want = pcol(pal[cur ? (xx < CX + 2 ? fg : bg) & 0xFF : v & 0xFF]);
			else            want = dcol(depth, cur ? (xx < CX + 2 ? fg : bg) : v);
			if (got[yy][xx] != want) { if (bad < 6) printf("  (%d,%d) %06X, want %06X\n", xx, yy, got[yy][xx], want); bad++; }
		}
	if (seen != W * H) { printf("  %d pixels seen, want %d\n", seen, W * H); bad++; }
	printf("%-44s %s (%d differ)\n", name, bad ? "FAIL" : "pass", bad);
	if (bad) fails++;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new VIBMRS6K7248_s3video;
	for (int i = 0; i < 256; i++) pal[i] = (uint32_t)(i * 2654435761u) & 0x3FFFF;
	run_depth(0, "8 bits a pixel, the palette, the cursor", 0xC3, 0x3C);
	run_depth(1, "15 bits a pixel (5-5-5), the cursor", 0x7C00, 0x001F);
	run_depth(2, "16 bits a pixel (5-6-5), the cursor", 0xF800, 0x07E0);
	run_depth(3, "32 bits a pixel (8-8-8), the cursor", 0x123456, 0xABCDEF);
	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
