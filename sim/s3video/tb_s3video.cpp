// IBMRS6K7248 - a bench of the S3's picture side alone (IBMRS6K7248_s3video): a DDR3 model on its DDRAM port, a
// small mode at each depth (8 bits through the palette, 15, 16, 24 packed and 32 direct), the hardware cursor over it; every
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
static uint8_t font[8192];                // the text mode's font copy, on its port

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
	uint8_t fq = font[t->font_addr];
	t->clk = 0; t->eval();
	t->clk = 1; t->eval();
	t->pal_q = q;
	t->font_q = fq;
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
	int ps = depth == 0 ? 1 : depth == 3 ? 4 : depth == 4 ? 3 : 2;
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

// the VGA text mode: 5 characters of 9 dots a line, rows of 4 lines, 8 characters a row in memory (CR13 4), the
// start at character 3; the font's copy, the attribute palette, AR14, the line graphics' ninth dot, the cursor
static void set_txt(bool on, bool nine, int chm1, int cs, int ce, bool coff, int cloc, int ar10, int ar14, int cols,
                    const uint8_t *arpal) {
	uint32_t w[5] = {0, 0, 0, 0, 0};
	auto put = [&](int lo, int n, uint32_t v) { for (int i = 0; i < n; i++) if ((v >> i) & 1) w[(lo + i) / 32] |= 1u << ((lo + i) % 32); };
	for (int i = 0; i < 16; i++) put(6 * i, 6, arpal[i]);
	put(96, 10, cols); put(106, 4, ar14); put(110, 8, ar10); put(118, 16, cloc); put(134, 1, coff);
	put(135, 5, ce); put(140, 5, cs); put(145, 5, chm1); put(150, 1, nine); put(151, 1, on);
	for (int i = 0; i < 5; i++) t->txt[i] = w[i];
}
static void run_text() {
	const int CW = 9, COLS = 5, CH = 4, ROWCH = 8, SC = 3, TW = CW * COLS, TH = 8;
	const int CLOC = SC + 1 * ROWCH + 2, CS = 1, CE = 2, AR10 = 0x0C, AR14 = 0x5;
	uint8_t arpal[16];
	for (int i = 0; i < 16; i++) arpal[i] = (uint8_t)((i * 37 + 11) & 63);
	for (int i = 0; i < 8192; i++) font[i] = (uint8_t)(i * 2654435761u >> 13);
	for (int r = 0; r < 2; r++)
		for (int c = 0; c < ROWCH; c++) {
			int ma = SC + r * ROWCH + c;
			vram[8 * ma] = (r == 0 && c == 1) ? 0xC5 : (r == 1 && c == 3) ? 0xC2 : (uint8_t)(0x41 + 7 * ma);
			vram[8 * ma + 1] = (uint8_t)(0x9E * ma + 0x17);
		}
	t->reset = 1;
	t->h_total = 64; t->h_disp = TW; t->h_ss = 50; t->h_sl = 6;
	t->v_total = 12; t->v_disp = TH; t->v_ss = 9; t->v_sl = 1;
	t->depth = 0; t->start = SC * 8; t->pitch = ROWCH * 8; t->screen_on = 1; t->pix_mask = 0xFF;
	t->pll_m = 127; t->pll_n = 0; t->cur_on = 0;
	set_txt(true, CW == 9, CH - 1, CS, CE, false, CLOC, AR10, AR14, COLS, arpal);
	t->c_req = 0;
	rq.clear();
	for (int i = 0; i < 10; i++) tick();
	t->reset = 0;
	static uint32_t got[TH][TW];
	int x = 0, y = 0, frame = 0, seen = 0;
	bool hb_q = true, vb_q = true;
	for (long i = 0; i < 64 * 12 * 3 + 200 && frame < 3; i++) {
		tick();
		if (!t->ce_pix) continue;
		if (t->vblank && !vb_q) frame++;
		if (!t->vblank && vb_q) y = 0;
		if (t->hblank && !hb_q && !t->vblank) y++;
		if (!t->hblank && hb_q) x = 0;
		if (frame == 1 && !t->hblank && !t->vblank && y < TH && x < TW) { got[y][x] = (t->r << 16) | (t->g << 8) | t->b; x++; seen++; }
		hb_q = t->hblank; vb_q = t->vblank;
	}
	int bad = 0;
	for (int yy = 0; yy < TH; yy++)
		for (int xx = 0; xx < TW; xx++) {
			int row = yy / CH, line = yy % CH, col = xx / CW, dot = xx % CW, ma = SC + row * ROWCH + col;
			int ch = vram[8 * ma], at = vram[8 * ma + 1], fb = font[ch * 32 + line];
			int dl = dot < 8 ? (fb >> (7 - dot)) & 1 : ((AR10 & 4) && (ch & 0xE0) == 0xC0 ? fb & 1 : 0);
			int cur = ma == CLOC && line >= CS && line <= CE;
			int idx = (dl | cur) ? at & 15 : (at >> 4) & ((AR10 & 8) ? 7 : 15);
			int v6 = arpal[idx];
			int i8 = ((AR14 >> 2) & 3) << 6 | ((AR10 & 0x80) ? (AR14 & 3) : (v6 >> 4) & 3) << 4 | (v6 & 15);
			uint32_t want = pcol(pal[i8]);
			if (got[yy][xx] != want) { if (bad < 6) printf("  (%d,%d) %06X, want %06X\n", xx, yy, got[yy][xx], want); bad++; }
		}
	if (seen != TW * TH) { printf("  %d pixels seen, want %d\n", seen, TW * TH); bad++; }
	printf("%-44s %s (%d differ)\n", "text, 9 dots, attributes, the cursor", bad ? "FAIL" : "pass", bad);
	if (bad) fails++;
	set_txt(false, false, 0, 0, 0, true, 0, 0, 0, 0, arpal);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new VIBMRS6K7248_s3video;
	for (int i = 0; i < 256; i++) pal[i] = (uint32_t)(i * 2654435761u) & 0x3FFFF;
	run_depth(0, "8 bits a pixel, the palette, the cursor", 0xC3, 0x3C);
	run_depth(1, "15 bits a pixel (5-5-5), the cursor", 0x7C00, 0x001F);
	run_depth(2, "16 bits a pixel (5-6-5), the cursor", 0xF800, 0x07E0);
	run_depth(3, "32 bits a pixel (8-8-8), the cursor", 0x123456, 0xABCDEF);
	run_depth(4, "24 bits a pixel packed, the cursor", 0x654321, 0x0F1E2D);
	run_text();
	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
