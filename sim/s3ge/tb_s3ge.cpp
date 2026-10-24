// IBMRS6K7248 - a bench of the S3's graphics engine alone (IBMRS6K7248_s3ge): a VRAM model on its port,
// the commands the firmware and AIX's X server issue, each result checked pixel by pixel against a model
// in C++ here. ./run.sh builds and runs it; it prints each test and "ALL PASS" or the first differences.

#include "VIBMRS6K7248_s3ge.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>
#include <functional>

static VIBMRS6K7248_s3ge *t;
static uint8_t vram[2 << 20];             // byte a at a (the port's words: the lowest address in bits 31:24)
static uint8_t ref[2 << 20];
static const int PITCH = 1024;
static uint64_t cyc;
static int lat;                           // the VRAM's answer: some clocks after a request

static void tick() {
	// VRAM: answer a request after 3 clocks
	t->v_ack = 0;
	if (t->v_req) {
		if (++lat == 3) {
			uint32_t a = (uint32_t)t->v_addr << 2;
			if (t->v_we) {
				for (int k = 0; k < 4; k++)
					if (t->v_be & (8 >> k)) vram[a + k] = (t->v_wdata >> (24 - 8 * k)) & 0xFF;
			} else {
				t->v_rdata = (vram[a] << 24) | (vram[a + 1] << 16) | (vram[a + 2] << 8) | vram[a + 3];
			}
			t->v_ack = 1;
			lat = -100;                     // (until the request drops)
		}
	} else lat = 0;
	t->clk = 0; t->eval();
	t->clk = 1; t->eval();
	cyc++;
}

static void wait_idle() {
	int n = 0;
	while (t->busy) { tick(); if (++n > 20000000) { printf("  engine stuck busy\n"); exit(1); } }
}
// a register write as the S3's port gives it: the low byte (xxE8), then the high (xxE9), each once the engine is idle
static void wbyte(int idx, bool hi, uint8_t d) {
	wait_idle();
	t->r_we = 1; t->r_idx = idx; t->r_hi = hi; t->r_data = d; tick();
	t->r_we = 0; tick();
}
static void w16(uint16_t port, uint16_t v) { int idx = port >> 10; wbyte(idx, 0, v & 0xFF); wbyte(idx, 1, v >> 8); }
static void mf(int index, uint16_t v) { w16(0xBEE8, (index << 12) | (v & 0xFFF)); }
// a PIX_TRANS write: the bus's bytes little-endian (E2E8 in bits 7:0)
static void pt(uint32_t d) {
	int n = 0;
	t->pt_valid = 1; t->pt_data = d;
	while (!t->pt_ready) { tick(); if (!t->busy || ++n > 1000000) { t->pt_valid = 0; printf("  PIX_TRANS dropped\n"); return; } }
	tick();
	t->pt_valid = 0; tick();
}
static uint32_t ptr() {
	int n = 0;
	while (!t->rd_valid) { tick(); if (++n > 1000000) { printf("  no PIX_TRANS read data\n"); exit(1); } }
	uint32_t d = t->rd_data;
	t->rd_take = 1; tick(); t->rd_take = 0; tick();
	return d;
}

static int fails;
static bool check(const char *name, int x0, int y0, int w, int h) {
	int bad = 0;
	for (int y = y0; y < y0 + h; y++)
		for (int x = x0; x < x0 + w; x++) {
			int a = y * PITCH + x;
			if (vram[a] != ref[a]) {
				if (bad < 8) printf("  %s: (%d,%d) is %02X, want %02X\n", name, x, y, vram[a], ref[a]);
				bad++;
			}
		}
	printf("%-44s %s (%d pixels differ)\n", name, bad ? "FAIL" : "pass", bad);
	if (bad) fails++;
	return !bad;
}
static void same() { memcpy(ref, vram, sizeof vram); }
static void fill(uint8_t v) { memset(vram, v, sizeof vram); same(); }
static void setpx(int x, int y, uint8_t v) { ref[y * PITCH + x] = v; }
static void common() {
	mf(1, 0); mf(2, 0); mf(3, 0xFFF); mf(4, 0xFFF);       // scissors open
	mf(0xE, 0);                                         // MULT_MISC
	w16(0xAAE8, 0xFF); w16(0xAEE8, 0xFF);               // write and read masks
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new VIBMRS6K7248_s3ge;
	t->pitch = PITCH;
	t->reset = 1; for (int i = 0; i < 5; i++) tick(); t->reset = 0; tick();
	common();

	// 1. the firmware's rectangle fill (40F3), foreground colour
	fill(0x11);
	w16(0xBAE8, 0x27); w16(0xA6E8, 0x5A); mf(0xA, 0x000);
	w16(0x86E8, 10); w16(0x82E8, 20); w16(0x96E8, 29); mf(0, 9); w16(0x9AE8, 0x40F3);
	wait_idle();
	for (int y = 20; y < 30; y++) for (int x = 10; x < 40; x++) setpx(x, y, 0x5A);
	check("rect fill 40F3", 0, 0, 64, 40);

	// 2. the firmware's glyph (51B3): mono, 8-bit bus with BYTSEQ, a byte a row in out16le(E2E8, b)
	fill(0x00);
	w16(0xBAE8, 0x27); w16(0xA6E8, 0x0F); w16(0xB6E8, 0x07); w16(0xA2E8, 0x01); mf(0xA, 0x080);
	w16(0x86E8, 100); w16(0x82E8, 50); w16(0x96E8, 7); mf(0, 3); w16(0x9AE8, 0x51B3);
	{ uint8_t g[4] = {0x81, 0x42, 0x24, 0x18};
	  for (int r = 0; r < 4; r++) { pt(g[r]); for (int i = 0; i < 8; i++) setpx(100 + i, 50 + r, (g[r] >> (7 - i)) & 1 ? 0x0F : 0x01); } }
	wait_idle();
	check("mono glyph 51B3 (8-bit, BYTSEQ)", 90, 45, 30, 15);

	// 3. a mono glyph on a 32-bit bus without BYTSEQ: the highest byte (E2EB) first; 20 pixels a row, one transfer a row
	fill(0x00);
	w16(0x86E8, 200); w16(0x82E8, 60); w16(0x96E8, 19); mf(0, 1); w16(0x9AE8, 0x45B3 & ~0x1000);  // bus 10, mono
	{ uint32_t rows[2] = {0xF0F0A000, 0x0F0F5000};     // the bits in use order: E2EB first
	  for (int r = 0; r < 2; r++) {
		  uint32_t v = rows[r];
		  pt(v);                                         // E2EB = v[31:24] in the transfer's top byte
		  for (int i = 0; i < 20; i++) setpx(200 + i, 60 + r, (v >> (31 - i)) & 1 ? 0x0F : 0x01);
	  } }
	wait_idle();
	check("mono 32-bit bus, no BYTSEQ", 190, 55, 40, 10);

	// 4. the same with BYTSEQ: E2E8 first
	fill(0x00);
	w16(0x86E8, 200); w16(0x82E8, 60); w16(0x96E8, 19); mf(0, 1); w16(0x9AE8, 0x55B3);
	{ uint32_t rows[2] = {0x00A0F0F0, 0x00500F0F};     // E2E8 = bits 7:0 first
	  for (int r = 0; r < 2; r++) {
		  uint32_t v = rows[r];
		  uint32_t o = ((v & 0xFF) << 24) | ((v & 0xFF00) << 8) | ((v >> 8) & 0xFF00) | (v >> 24);
		  pt(v);
		  for (int i = 0; i < 20; i++) setpx(200 + i, 60 + r, (o >> (31 - i)) & 1 ? 0x0F : 0x01);
	  } }
	wait_idle();
	check("mono 32-bit bus, BYTSEQ", 190, 55, 40, 10);

	// 5. the firmware's putbitmap (4331): colour data, 16-bit bus, rows going up, E2E9 the first pixel
	fill(0x00);
	w16(0xBAE8, 0x47); mf(0xA, 0x000);
	w16(0x86E8, 300); w16(0x82E8, 109); w16(0x96E8, 4); mf(0, 2); w16(0x9AE8, 0x4331);
	for (int r = 0; r < 3; r++) {
		uint8_t p[6]; for (int i = 0; i < 6; i++) p[i] = 0x20 + r * 8 + i;
		for (int k = 0; k < 3; k++) pt((p[2 * k] << 8) | p[2 * k + 1]);      // E2E9 pixel 2k, E2E8 pixel 2k+1
		for (int i = 0; i < 5; i++) setpx(300 + i, 109 - r, p[i]);
	}
	wait_idle();
	check("putbitmap 4331 (16-bit, rows up)", 295, 100, 15, 15);

	// 6. colour compare (E100): source colour 0 is not written
	fill(0x77);
	mf(0xE, 0x100); w16(0xB2E8, 0x00);
	w16(0x86E8, 300); w16(0x82E8, 109); w16(0x96E8, 3); mf(0, 0); w16(0x9AE8, 0x4331);
	pt((0x00 << 8) | 0x33); pt((0x44 << 8) | 0x00);
	wait_idle();
	setpx(301, 109, 0x33); setpx(302, 109, 0x44);
	check("colour compare 10: source 0 transparent", 295, 105, 15, 8);
	mf(0xE, 0x180); w16(0xB2E8, 0x33);
	w16(0x86E8, 300); w16(0x82E8, 110); w16(0x96E8, 3); mf(0, 0); w16(0x9AE8, 0x4331);
	pt((0x33 << 8) | 0x34); pt((0x33 << 8) | 0x35);
	wait_idle();
	setpx(300, 110, 0x33); setpx(302, 110, 0x33);
	check("colour compare 11: only COLOR_CMP written", 295, 105, 15, 8);
	mf(0xE, 0x000);

	// 7. a BitBLT (C0B3), display memory source, mix 7
	fill(0x00);
	for (int y = 0; y < 8; y++) for (int x = 0; x < 16; x++) vram[(400 + y) * PITCH + 10 + x] = x + 16 * y;
	same();
	w16(0xBAE8, 0x67); mf(0xA, 0x000);
	w16(0x86E8, 10); w16(0x82E8, 400); w16(0x8EE8, 500); w16(0x8AE8, 300); w16(0x96E8, 15); mf(0, 7); w16(0x9AE8, 0xC0B3);
	wait_idle();
	for (int y = 0; y < 8; y++) for (int x = 0; x < 16; x++) setpx(500 + x, 300 + y, x + 16 * y);
	check("BitBLT C0B3", 495, 295, 30, 20);

	// 8. a pattern fill (E0B3): an 8 x 8 at (0, 600) over 21 x 11 at (40, 640)
	fill(0x00);
	for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) vram[(600 + y) * PITCH + x] = 0x80 + x + 8 * y;
	same();
	w16(0x86E8, 0); w16(0x82E8, 600); w16(0x8EE8, 40); w16(0x8AE8, 640); w16(0x96E8, 20); mf(0, 10); w16(0x9AE8, 0xE0B3);
	wait_idle();
	for (int y = 0; y < 11; y++) for (int x = 0; x < 21; x++) setpx(40 + x, 640 + y, 0x80 + (x & 7) + 8 * (y & 7));
	check("pattern fill E0B3", 35, 635, 30, 20);

	// 9. display memory picks the mix (PIX_CNTL C0): a mono bitmap in plane 0 expanded by a BitBLT
	fill(0x00);
	for (int x = 0; x < 16; x++) vram[700 * PITCH + x] = (x % 3) == 0 ? 0x01 : 0x00;
	same();
	w16(0xAEE8, 0x01); mf(0xA, 0x0C0); w16(0xBAE8, 0x27); w16(0xA6E8, 0xEE); w16(0xB6E8, 0x07); w16(0xA2E8, 0x22);
	w16(0x86E8, 0); w16(0x82E8, 700); w16(0x8EE8, 100); w16(0x8AE8, 710); w16(0x96E8, 15); mf(0, 0); w16(0x9AE8, 0xC0B3);
	wait_idle();
	for (int x = 0; x < 16; x++) setpx(100 + x, 710, (x % 3) == 0 ? 0xEE : 0x22);
	check("mono from display memory (RD_MASK 01)", 95, 705, 30, 10);
	w16(0xAEE8, 0xFF); mf(0xA, 0x000);

	// 10. a Bresenham line (2017: INC_X, DRAW, LPO off, X major, INC_Y) from (10, 10) to (30, 18)
	fill(0x00);
	w16(0xBAE8, 0x27); w16(0xA6E8, 0x99); mf(0xA, 0x000);
	{
		int x0 = 10, y0 = 10, x1 = 30, y1 = 18, dmaj = x1 - x0, dmin = y1 - y0;
		w16(0x86E8, x0); w16(0x82E8, y0);
		w16(0x8AE8, (2 * dmin) & 0x3FFF);                // the axial step
		w16(0x8EE8, (2 * (dmin - dmaj)) & 0x3FFF);       // the diagonal step
		w16(0x92E8, (2 * dmin - dmaj - 1) & 0x3FFF);     // the error term (INC_X: one less)
		w16(0x96E8, dmaj);
		w16(0x9AE8, 0x20B1);
		wait_idle();
		int err = 2 * dmin - dmaj - 1, x = x0, y = y0;
		for (int i = 0; i <= dmaj; i++) {
			setpx(x, y, 0x99);
			if (err >= 0) { y++; err += 2 * (dmin - dmaj); } else err += 2 * dmin;
			x++;
		}
	}
	check("Bresenham line 20B1", 0, 0, 40, 30);

	// 11. a radial line (2019 | dir): 6 steps at 315 degrees (down-right), then short strokes from where it ended
	fill(0x00);
	w16(0x86E8, 50); w16(0x82E8, 50); w16(0x96E8, 6); w16(0x9AE8, 0x2019 | (7 << 5));
	wait_idle();
	for (int i = 0; i <= 6; i++) setpx(50 + i, 50 + i, 0x99);
	check("radial line 2019, 315 degrees", 40, 40, 30, 30);
	// short strokes, a NOP's flags (001C: radial, DRAW, last pixel off): 4 right drawn, 3 up moved, 2 left drawn
	w16(0x9AE8, 0x001D);
	w16(0x9EE8, (0x14 << 8) | 0x43);     // high byte first: 0x14 (0 degrees, drawn, 4), then 0x43 (90, moved, 3)
	w16(0x9EE8, (0x92 << 8) | 0x00);     // 0x92 (180 degrees, drawn, 2), then 0x00 (0 degrees, moved, 0)
	wait_idle();
	for (int i = 0; i < 4; i++) setpx(56 + i, 56, 0x99);                // from (56, 56): 4 steps, the last off
	for (int i = 0; i < 2; i++) setpx(60 - i, 53, 0x99);                // from (60, 53): 2 steps left, the last off
	check("short-stroke vectors", 40, 40, 30, 30);

	// 12. an image read (4130: rectangle, 32-bit bus, WAIT YES, no WRTDATA): 7 x 2 pixels
	fill(0x00);
	for (int y = 0; y < 2; y++) for (int x = 0; x < 7; x++) vram[(800 + y) * PITCH + 20 + x] = 0x40 + 10 * y + x;
	same();
	w16(0x86E8, 20); w16(0x82E8, 800); w16(0x96E8, 6); mf(0, 1); w16(0x9AE8, 0x45B0);
	{
		int bad = 0;
		for (int y = 0; y < 2; y++) {
			uint32_t a = ptr(), b = ptr();
			// no BYTSEQ: the first pixel in E2EB (bits 31:24); a row of 7: a whole transfer and 3 in the next
			uint32_t wa = 0, wb = 0;
			for (int i = 0; i < 4; i++) wa |= (uint32_t)(0x40 + 10 * y + i) << (24 - 8 * i);
			for (int i = 0; i < 3; i++) wb |= (uint32_t)(0x44 + 10 * y + i) << (24 - 8 * i);
			if (a != wa || b != wb) { printf("  row %d: %08X %08X, want %08X %08X\n", y, a, b, wa, wb); bad++; }
		}
		wait_idle();
		printf("%-44s %s\n", "image read 45B0 (32-bit)", bad ? "FAIL" : "pass");
		if (bad) fails++;
	}
	check("image read leaves VRAM alone", 0, 795, 64, 10);

	// ---- 16 bits a pixel (CR50 bits 5:4 = 01): a pixel at 2x, its low byte first ----
	t->psz = 1;
	w16(0xAAE8, 0xFFFF); w16(0xAEE8, 0xFFFF);
	auto set16 = [](int x, int y, uint16_t v) { ref[y * PITCH + 2 * x] = v & 0xFF; ref[y * PITCH + 2 * x + 1] = v >> 8; };

	// 13. a rectangle fill, foreground 0x1234
	fill(0x00);
	w16(0xBAE8, 0x27); w16(0xA6E8, 0x1234); mf(0xA, 0x000);
	w16(0x86E8, 10); w16(0x82E8, 20); w16(0x96E8, 4); mf(0, 2); w16(0x9AE8, 0x40F3);
	wait_idle();
	for (int y = 20; y < 23; y++) for (int x = 10; x < 15; x++) set16(x, y, 0x1234);
	check("16 bpp: rect fill", 0, 15, 64, 15);

	// 14. colour data on a 16-bit bus: with BYTSEQ a pixel a transfer as written, without it swapped
	fill(0x00);
	w16(0xBAE8, 0x47);
	w16(0x86E8, 100); w16(0x82E8, 30); w16(0x96E8, 2); mf(0, 1); w16(0x9AE8, 0x53B1);   // BYTSEQ, rows down
	for (int r = 0; r < 2; r++) for (int i = 0; i < 3; i++) { uint16_t v = 0xA000 + 0x100 * r + i; pt(v); set16(100 + i, 30 + r, v); }
	wait_idle();
	w16(0x86E8, 100); w16(0x82E8, 40); w16(0x96E8, 2); mf(0, 0); w16(0x9AE8, 0x43B1);   // no BYTSEQ
	for (int i = 0; i < 3; i++) { uint16_t v = 0xB100 + i; pt(v); set16(100 + i, 40, (v >> 8) | ((v & 0xFF) << 8)); }
	wait_idle();
	check("16 bpp: colour data, 16-bit bus", 180, 25, 60, 20);

	// 15. the write mask (low byte only) and colour compare (10: source 0x0000 not written)
	fill(0x55);
	w16(0xAAE8, 0x00FF); w16(0xBAE8, 0x27); w16(0xA6E8, 0xCDEF);
	w16(0x86E8, 0); w16(0x82E8, 50); w16(0x96E8, 3); mf(0, 0); w16(0x9AE8, 0x40F3);
	wait_idle();
	for (int x = 0; x < 4; x++) set16(x, 50, 0x55EF);
	w16(0xAAE8, 0xFFFF);
	mf(0xE, 0x100); w16(0xB2E8, 0x0000); w16(0xBAE8, 0x47);
	w16(0x86E8, 0); w16(0x82E8, 52); w16(0x96E8, 3); mf(0, 0); w16(0x9AE8, 0x53B1);
	pt(0x0000); pt(0x1111); pt(0x0100); pt(0x0000);
	wait_idle();
	set16(1, 52, 0x1111); set16(2, 52, 0x0100);
	mf(0xE, 0x000);
	check("16 bpp: write mask, colour compare", 0, 48, 16, 8);

	// 16. a BitBLT and an image read (32-bit bus, BYTSEQ: two pixels a transfer, the first in bits 15:0)
	fill(0x00);
	for (int y = 0; y < 2; y++) for (int x = 0; x < 3; x++) { uint16_t v = 0x4000 + 0x100 * y + x; vram[(60 + y) * PITCH + 2 * (5 + x)] = v & 0xFF; vram[(60 + y) * PITCH + 2 * (5 + x) + 1] = v >> 8; }
	same();
	w16(0xBAE8, 0x67);
	w16(0x86E8, 5); w16(0x82E8, 60); w16(0x8EE8, 50); w16(0x8AE8, 70); w16(0x96E8, 2); mf(0, 1); w16(0x9AE8, 0xC0B3);
	wait_idle();
	for (int y = 0; y < 2; y++) for (int x = 0; x < 3; x++) set16(50 + x, 70 + y, 0x4000 + 0x100 * y + x);
	check("16 bpp: BitBLT", 0, 55, 120, 20);
	w16(0x86E8, 5); w16(0x82E8, 60); w16(0x96E8, 2); mf(0, 1); w16(0x9AE8, 0x55B0);
	{
		int bad = 0;
		for (int y = 0; y < 2; y++) {
			uint32_t a = ptr(), b = ptr();
			uint32_t wa = (0x4000 + 0x100 * y) | ((uint32_t)(0x4001 + 0x100 * y) << 16), wb = 0x4002 + 0x100 * y;
			if (a != wa || b != wb) { printf("  row %d: %08X %08X, want %08X %08X\n", y, a, b, wa, wb); bad++; }
		}
		wait_idle();
		printf("%-44s %s\n", "16 bpp: image read (32-bit, BYTSEQ)", bad ? "FAIL" : "pass");
		if (bad) fails++;
	}

	// ---- 32 bits a pixel (CR50 bits 5:4 = 11): the colour registers in two writes (RSF) ----
	t->psz = 2;
	mf(0xE, 0x000);
	w16(0xAAE8, 0xFFFF); w16(0xAAE8, 0xFFFF); w16(0xAEE8, 0xFFFF); w16(0xAEE8, 0xFFFF);
	auto set32 = [](int x, int y, uint32_t v) { for (int k = 0; k < 4; k++) ref[y * PITCH + 4 * x + k] = (v >> (8 * k)) & 0xFF; };

	// 17. a rectangle fill, foreground 0x00C0FFEE (low half, then high)
	fill(0x00);
	w16(0xBAE8, 0x27); w16(0xA6E8, 0xFFEE); w16(0xA6E8, 0x00C0); mf(0xA, 0x000);
	w16(0x86E8, 3); w16(0x82E8, 80); w16(0x96E8, 5); mf(0, 1); w16(0x9AE8, 0x40F3);
	wait_idle();
	for (int y = 80; y < 82; y++) for (int x = 3; x < 9; x++) set32(x, y, 0x00C0FFEE);
	check("32 bpp: rect fill (RSF halves)", 0, 75, 64, 10);

	// 18. colour data: a 32-bit bus with BYTSEQ (a pixel a transfer), a 16-bit bus (a pixel in two, low half first)
	fill(0x00);
	w16(0xBAE8, 0x47);
	w16(0x86E8, 10); w16(0x82E8, 90); w16(0x96E8, 2); mf(0, 0); w16(0x9AE8, 0x55B1);
	for (int i = 0; i < 3; i++) { uint32_t v = 0x11223300 + i; pt(v); set32(10 + i, 90, v); }
	wait_idle();
	w16(0x86E8, 10); w16(0x82E8, 92); w16(0x96E8, 1); mf(0, 0); w16(0x9AE8, 0x53B1);
	for (int i = 0; i < 2; i++) { uint32_t v = 0x00ABCD00 + 0x10 * i; pt(v & 0xFFFF); pt(v >> 16); set32(10 + i, 92, v); }
	wait_idle();
	check("32 bpp: colour data, 32- and 16-bit bus", 0, 88, 80, 8);

	// 19. a BitBLT with a mix that reads the destination (XOR, 0x65)
	fill(0x00);
	for (int x = 0; x < 4; x++) { set32(x, 100, 0x01020304 * (x + 1)); set32(20 + x, 110, 0x00FF00FF); }
	memcpy(vram, ref, sizeof vram);
	w16(0xBAE8, 0x65);
	w16(0x86E8, 0); w16(0x82E8, 100); w16(0x8EE8, 20); w16(0x8AE8, 110); w16(0x96E8, 3); mf(0, 0); w16(0x9AE8, 0xC0B3);
	wait_idle();
	for (int x = 0; x < 4; x++) set32(20 + x, 110, (0x01020304 * (x + 1)) ^ 0x00FF00FF);
	check("32 bpp: BitBLT, XOR", 0, 98, 120, 15);
	t->psz = 0;

	printf(fails ?"%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
