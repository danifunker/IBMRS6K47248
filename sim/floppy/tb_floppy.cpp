// IBMRS6K7248 - the floppy's bench (fdtb.sv: IBMRS6K7248_fdc, _fdimg, _dma): a memory model on the DMA port,
// an SD model serving block device 4 as hps_io does (its own clock), a 1.44 MB image. ./run.sh builds and runs it.

#include "Vfdtb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static Vfdtb *t;
static uint8_t mem[1 << 20];               // PCI 8000_0000 + n
static std::vector<uint8_t> img(1474560);
static int fails, dma_wait, ph, sd_state, sd_i, sd_len, sd_reqs;
static uint32_t sd_blk;

static void step() {
	// the SD model, on clk_s (7 steps); the machine on clk (10 steps)
	ph++;
	bool s_edge = (ph % 7) == 0, c_edge = (ph % 10) == 0;
	if (s_edge) {
		t->sd_buff_wr = 0;
		if (sd_state == 0) {
			if (t->sd_rd || t->sd_wr) {
				sd_blk = t->sd_lba; sd_state = t->sd_rd ? 1 : 2; sd_i = 0; t->sd_ack = 1; sd_reqs++;
				sd_len = (t->sd_blk_cnt + 1) * 512;           // (a read may take several blocks: a track)
			}
		} else if (sd_state == 1) {
			if (sd_i < sd_len) { t->sd_buff_addr = sd_i; t->sd_buff_dout = img[sd_blk * 512 + sd_i]; t->sd_buff_wr = 1; sd_i++; }
			else { t->sd_ack = 0; sd_state = 0; }
		} else {
			if (sd_i < 1024) {
				if (sd_i & 1) img[sd_blk * 512 + (sd_i >> 1)] = t->sd_buff_din;
				t->sd_buff_addr = (sd_i + 1) >> 1;
				sd_i++;
			} else { t->sd_ack = 0; sd_state = 0; }
		}
	}
	if (c_edge) {
		t->dm_ack = 0;
		if (t->dm_req) {
			if (++dma_wait == 2) {
				uint32_t o = uint32_t((uint64_t(t->dm_addr) << 3) - 0x80000000ull);
				if (t->dm_we) { for (int k = 0; k < 8; k++) if (t->dm_be & (0x80 >> k)) mem[o + k] = (t->dm_wdata >> (56 - 8 * k)) & 0xFF; }
				else { uint64_t d = 0; for (int k = 0; k < 8; k++) d = (d << 8) | mem[o + k]; t->dm_rdata = d; }
				t->dm_ack = 1; dma_wait = -100;
			}
		} else dma_wait = 0;
	}
	t->clk_s = s_edge; t->clk = c_edge; t->eval();
	t->clk_s = 0; t->clk = 0; t->eval();
}
static void tick() { do step(); while (ph % 10); }        // one machine clock
static void run(int n) { for (int i = 0; i < n; i++) tick(); }
static void out8(int port, int v) { t->sel = 1; t->we = 1; t->port = port; t->wdata = v; tick(); t->sel = 0; t->we = 0; tick(); }
static int in8(int port) { t->sel = 1; t->we = 0; t->port = port; tick(); t->sel = 0; tick(); return t->rdata; }
static void expect(const char *what, long got, long want) {
	if (got != want) { printf("  %s: %lX, want %lX\n", what, got, want); fails++; }
}
// the FDC's command and result phases through MSR
static void fcmd(std::vector<int> b) {
	for (int x : b) { int n = 0; while ((in8(0x3F4) & 0xC0) != 0x80 && n++ < 1000) ; out8(0x3F5, x); }
}
static std::vector<int> fres() {
	std::vector<int> r; int n = 0;
	while (n++ < 3000000) {
		int m = in8(0x3F4);
		if ((m & 0xD0) == 0xD0) r.push_back(in8(0x3F5));
		else if (!r.empty() && !(m & 0x10)) break;
	}
	return r;
}
static void mount(bool ro) {
	t->img_size = img.size(); t->img_readonly = ro; t->img_mounted = 1;
	for (int i = 0; i < 20; i++) step();
	t->img_mounted = 0; run(20);
}
// DMA channel 2: mode, count, address (8000_0000 + a)
static void dma2(int mode, int count, uint32_t a) {
	out8(0x0A, 6); out8(0x0C, 0);
	out8(0x04, a & 0xFF); out8(0x04, (a >> 8) & 0xFF);
	out8(0x05, (count - 1) & 0xFF); out8(0x05, (count - 1) >> 8);
	out8(0x81, (a >> 16) & 0xFF); out8(0x481, 0x80);
	out8(0x0B, mode); out8(0x0A, 2);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vfdtb;
	for (size_t i = 0; i < img.size(); i++) img[i] = uint8_t((i / 512) * 7 + i);
	t->reset = 1; run(5); t->reset = 0; run(5);
	out8(0x3F2, 0x00); out8(0x3F2, 0x0C);                    // out of reset, DMA and interrupts on
	run(20);
	for (int i = 0; i < 4; i++) { fcmd({0x08}); fres(); }   // the four owed after a reset
	fcmd({0x03, 0xDF, 0x02});                               // SPECIFY, DMA

	// 1. no diskette: READ ends "missing address mark"
	int f0 = fails;
	fcmd({0x46, 0x00, 0, 0, 1, 2, 18, 0x1B, 0xFF});
	{ auto r = fres(); expect("no medium: 7 results", r.size(), 7); if (r.size() == 7) { expect("ST0", r[0], 0x40); expect("ST1", r[1], 0x01); } }
	expect("disk change set", in8(0x3F7) & 0x80, 0x80);
	printf("%-46s %s\n", "no diskette", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 2. a 1.44 MB image mounted; RECALIBRATE clears the change line
	mount(false);
	fcmd({0x07, 0x00}); run(10); fcmd({0x08}); fres();
	expect("disk change cleared", in8(0x3F7) & 0x80, 0x00);
	printf("%-46s %s\n", "mounted, the change line", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 3. DMA read: C1 H0 R1, two sectors by the terminal count (LBA 36, 37)
	memset(&mem[0x10000], 0, 2048);
	dma2(0x46, 1024, 0x10000);                              // ch2, write (to memory), single
	fcmd({0xE6, 0x00, 1, 0, 1, 2, 18, 0x1B, 0xFF});
	{
		auto r = fres();
		expect("read: 7 results", r.size(), 7);
		if (r.size() == 7) { expect("read ST0", r[0], 0x00); expect("read C", r[3], 1); expect("read R next", r[5], 3); }
		expect("read: sectors 36, 37", memcmp(&mem[0x10000], &img[36 * 512], 1024), 0);
		expect("read: no more", mem[0x10000 + 1024], 0);
	}
	printf("%-46s %s\n", "DMA read, two sectors, TC", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 4. DMA write: C2 H1 R5 (LBA (2*2+1)*18+4 = 94)
	for (int i = 0; i < 512; i++) mem[0x20000 + i] = uint8_t(0xA5 ^ i);
	dma2(0x4A, 512, 0x20000);                               // ch2, read (from memory)
	fcmd({0xC5, 0x04, 2, 1, 5, 2, 18, 0x1B, 0xFF});
	{
		auto r = fres();
		expect("write: 7 results", r.size(), 7);
		if (r.size() == 7) expect("write ST0", r[0] & 0xC0, 0x00);
		expect("write: sector 94", memcmp(&mem[0x20000], &img[94 * 512], 512), 0);
	}
	printf("%-46s %s\n", "DMA write, one sector", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 5. multi-track: C3 H0 R18 then H1 R1 (LBA 125, 126)
	memset(&mem[0x30000], 0, 1024);
	dma2(0x46, 1024, 0x30000);
	fcmd({0xC6, 0x00, 3, 0, 18, 2, 18, 0x1B, 0xFF});
	{
		auto r = fres();
		if (r.size() == 7) { expect("MT: ended on head 1", r[4], 1); expect("MT: R next", r[5], 2); }
		expect("MT: sectors 125, 126", memcmp(&mem[0x30000], &img[125 * 512], 1024), 0);
	}
	printf("%-46s %s\n", "DMA read across the heads (MT)", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 6. PIO (non-DMA): one sector, C0 H0 R2 EOT 2, through the FIFO
	fcmd({0x03, 0xDF, 0x03});                               // SPECIFY, ND
	fcmd({0x46, 0x00, 0, 0, 2, 2, 2, 0x1B, 0xFF});
	{
		std::vector<uint8_t> got; int n = 0;
		while (got.size() < 512 && n++ < 200000) { int m = in8(0x3F4); if ((m & 0xE0) == 0xE0) got.push_back(in8(0x3F5)); }
		expect("PIO: 512 bytes", got.size(), 512);
		if (got.size() == 512) expect("PIO: sector 1", memcmp(got.data(), &img[1 * 512], 512), 0);
		auto r = fres();
		if (r.size() == 7) expect("PIO ST0", r[0] & 0xC0, 0x00);
	}
	fcmd({0x03, 0xDF, 0x02});
	printf("%-46s %s\n", "PIO read through the FIFO", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 7. FORMAT: track 5 head 0, 18 sectors (IDs 5 0 r 2), filler F6
	for (int s = 0; s < 18; s++) { mem[0x40000 + 4 * s] = 5; mem[0x40001 + 4 * s] = 0; mem[0x40002 + 4 * s] = s + 1; mem[0x40003 + 4 * s] = 2; }
	fcmd({0x0F, 0x00, 5}); run(10); fcmd({0x08}); fres();  // SEEK to 5
	dma2(0x4A, 72, 0x40000);
	fcmd({0x4D, 0x00, 2, 18, 0x54, 0xF6});
	{
		auto r = fres();
		if (r.size() == 7) expect("format ST0", r[0] & 0xC0, 0x00);
		int bad = 0; for (int s = 0; s < 18; s++) for (int i = 0; i < 512; i++) if (img[(5 * 2 * 18 + s) * 512 + i] != 0xF6) bad++;
		expect("format: track filled", bad, 0);
		expect("format: track 6 untouched", img[(6 * 2 * 18) * 512 + 3], uint8_t((6 * 2 * 18) * 7 + (6 * 2 * 18) * 512 + 3));
	}
	printf("%-46s %s\n", "FORMAT a track", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 8. a read-only image: WRITE ends "not writable"
	mount(true);
	fcmd({0x07, 0x00}); run(10); fcmd({0x08}); fres();
	dma2(0x4A, 512, 0x20000);
	fcmd({0xC5, 0x00, 0, 0, 1, 2, 18, 0x1B, 0xFF});
	{ auto r = fres(); if (r.size() == 7) { expect("RO ST0", r[0] & 0xC0, 0x40); expect("RO ST1", r[1], 0x02); } else expect("RO: 7 results", r.size(), 7); }
	fcmd({0x04, 0x00});
	{ auto r = fres(); if (r.size() == 1) expect("sense drive: write protected", r[0] & 0x40, 0x40); }
	printf("%-46s %s\n", "write-protected image", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 9. the data rate: a 1.44 MB diskette at 1 Mbps (CCR 03) has no address marks to find; at 500 kbps
	// (CCR 00) READ ID finds one (the firmware probes the density this way, 1 Mbps first)
	out8(0x3F7, 0x03);
	fcmd({0x4A, 0x00});
	{ auto r = fres(); if (r.size() == 7) { expect("1 Mbps: ST0", r[0] & 0xC0, 0x40); expect("1 Mbps: ST1", r[1], 0x01); } else expect("1 Mbps: 7 results", r.size(), 7); }
	out8(0x3F7, 0x00);
	fcmd({0x4A, 0x00});
	{ auto r = fres(); if (r.size() == 7) { expect("500 kbps: ST0", r[0] & 0xC0, 0x00); expect("500 kbps: N", r[6], 2); } else expect("500 kbps: 7 results", r.size(), 7); }
	printf("%-46s %s\n", "the data rate (READ ID at 1 Mbps, 500 kbps)", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 10. the firmware's density check: READ ID, its results read (no SENSE INTERRUPT), then VERIFY of the
	// track's last sector with MT (D6): each command's result phase must raise IRQ 6 afresh (the 8259 takes
	// edges), and reading the first result byte drops it
	fcmd({0x4A, 0x00});
	{ int n = 0; while (!t->irq6 && n++ < 100000) tick(); expect("READ ID: IRQ 6", t->irq6, 1); }
	fres();
	expect("READ ID's results read: IRQ 6 low", t->irq6, 0);
	fcmd({0xD6, 0x00, 0, 0, 18, 2, 18, 0x1B, 0xFF});
	{
		int n = 0; while (!t->irq6 && n++ < 3000000) tick();
		expect("VERIFY: IRQ 6", t->irq6, 1);
		auto r = fres();
		if (r.size() == 7) {
			expect("VERIFY ST0", r[0] & 0xC0, 0x00);
			// past head 1's EOT: C+1, H back to 0, R 1
			expect("VERIFY C", r[3], 1); expect("VERIFY H", r[4], 0); expect("VERIFY R", r[5], 1);
		}
		else expect("VERIFY: 7 results", r.size(), 7);
		expect("VERIFY's results read: IRQ 6 low", t->irq6, 0);
	}
	printf("%-46s %s\n", "READ ID then VERIFY (MT): an interrupt each", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 11. a whole cylinder (C9 H0 R1 EOT18, MT: 36 sectors) by DMA: the image read a track at a time (two
	// requests of 18 sectors), the data whole; then a sector of the track held, with no request
	memset(&mem[0x50000], 0, 36 * 512);
	{
		int r0 = sd_reqs;
		dma2(0x46, 36 * 512, 0x50000);
		fcmd({0xC6, 0x00, 9, 0, 1, 2, 18, 0x1B, 0xFF});
		auto r = fres();
		if (r.size() == 7) expect("cylinder: ST0", r[0] & 0xC0, 0x00); else expect("cylinder: 7 results", r.size(), 7);
		expect("cylinder: the data", memcmp(&mem[0x50000], &img[9 * 36 * 512], 36 * 512), 0);
		expect("cylinder: two requests", sd_reqs - r0, 2);
		int r1 = sd_reqs;
		memset(&mem[0x60000], 0, 512);
		dma2(0x46, 512, 0x60000);
		fcmd({0xC6, 0x04, 9, 1, 5, 2, 18, 0x1B, 0xFF});      // H1 R5: in the track held
		fres();
		expect("re-read: from the track held", sd_reqs - r1, 0);
		expect("re-read: the data", memcmp(&mem[0x60000], &img[(9 * 36 + 18 + 4) * 512], 512), 0);
	}
	printf("%-46s %s\n", "a cylinder by DMA, a track a request", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// 12. a cylinder DMA'd across a 64 KB boundary (as the firmware loads SMS's files: cylinder 7 to
	// 3AEAF0-3B32EF): the address carries into the page, nothing lands at the page's start
	memset(&mem[0x60000], 0, 0x10000);
	memset(&mem[0x70000], 0, 0x4000);
	dma2(0x46, 36 * 512, 0x6EAF0);
	fcmd({0xC6, 0x00, 7, 0, 1, 2, 18, 0x1B, 0xFF});
	{
		auto r = fres();
		if (r.size() == 7) expect("boundary: ST0", r[0] & 0xC0, 0x00); else expect("boundary: 7 results", r.size(), 7);
		expect("boundary: the data", memcmp(&mem[0x6EAF0], &img[7 * 36 * 512], 36 * 512), 0);
		expect("boundary: the page's start untouched", mem[0x60000] | mem[0x60001] | mem[0x61000], 0);
	}
	printf("%-46s %s\n", "a cylinder by DMA across 64 KB", fails != f0 ? "FAIL" : "pass");

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
