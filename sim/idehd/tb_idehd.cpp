// IBMRS6K7248 - the IDE hard disk's bench (idehdtb.sv: IBMRS6K7248_idehd as device 1 beside the ATAPI CD-ROM,
// both on IBMRS6K7248_scsitgt): the signature after reset, IDENTIFY DEVICE (geometry, LBA), READ SECTORS by LBA
// and by CHS (16- and 32-bit data port), WRITE SECTORS then the data read back (through the image), SET
// MULTIPLE + READ/WRITE MULTIPLE in 8-sector blocks, READ VERIFY, an LBA past the end (IDNF), an unknown
// command (ABRT), and the CD-ROM still answering as device 0. ./run.sh.

#include "Videhdtb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <map>

static Videhdtb *t;
static int fails;
static const uint32_t HD_BLOCKS = 20000;         // 512-byte blocks (~10 MB)
static const uint32_t CD_BLOCKS = 4000;          // 2 KB blocks

static std::map<uint64_t, uint8_t> written;     // the image's changed bytes (block * 512 + offset)
static uint8_t img(int slot, uint64_t blk, int off) {
	if (slot == 0) { auto it = written.find(blk * 512 + off); if (it != written.end()) return it->second; }
	return uint8_t(blk * 13 + off * 7 + (off >> 8) + slot * 101);
}

// hps_io: a request answered after a turnaround; a read fills a byte a clock; a write reads the target's
// sd_buff_din at each address (the byte is valid the clock after the address)
static int h_state, h_slot, h_wait, h_n, h_i, h_wr;
static uint64_t h_lba;
static void hps() {
	t->sd_buff_wr = 0;
	switch (h_state) {
	case 0:
		for (int s = 0; s < 3; s++) if (((t->sd_rd | t->sd_wr) >> s) & 1) {
			h_slot = s; h_wr = (t->sd_wr >> s) & 1; h_lba = t->sd_lba[s]; h_n = (t->sd_blk_cnt[s] + 1) * 512; h_i = -1; h_wait = 200; h_state = 1;
			break;
		}
		break;
	case 1: if (--h_wait == 0) { t->sd_ack = 1 << h_slot; h_state = 2; } break;
	case 2:
		if (!h_wr) {
			if (h_i < 0) h_i = 0;
			if (h_i < h_n) { t->sd_buff_addr = h_i; t->sd_buff_dout = img(h_slot, h_lba + h_i / 512, h_i % 512); t->sd_buff_wr = 1; h_i++; }
			else { t->sd_ack = 0; h_state = 3; h_wait = 4; }
		} else {
			if (h_i >= 0 && h_i < h_n) written[(h_lba + h_i / 512) * 512 + h_i % 512] = t->sd_buff_din[h_slot];   // the byte of the address set last clock
			h_i++;
			if (h_i < h_n) t->sd_buff_addr = h_i;
			else if (h_i > h_n) { t->sd_ack = 0; h_state = 3; h_wait = 4; }
		}
		break;
	case 3: if (--h_wait == 0) h_state = 0; break;
	}
}
static void tick() { hps(); t->clk = 0; t->clk_h = 0; t->eval(); t->clk = 1; t->clk_h = 1; t->eval(); }
static void run(int n) { for (int i = 0; i < n; i++) tick(); }

static uint32_t acc(bool w, int r, int be, uint32_t d = 0, bool cs1 = false) {
	t->sel = 1; t->we = w; t->reg_a = r; t->be = be; t->wdata = d; t->cs1 = cs1;
	tick(); t->sel = 0; t->we = 0;
	uint32_t q = t->rdata;
	run(3);
	return q;
}
static uint8_t rd8(int r) { return acc(false, r, 8) >> 24; }
static void wr8(int r, uint8_t v) { acc(true, r, 8, uint32_t(v) << 24); }
static uint16_t rd16() { uint32_t q = acc(false, 0, 0xC); return uint16_t((q >> 24) | ((q >> 8) & 0xFF00)); }
static void wr16(uint16_t v) { acc(true, 0, 0xC, uint32_t(v & 0xFF) << 24 | uint32_t(v >> 8) << 16); }
static uint32_t rd32() { uint32_t q = acc(false, 0, 0xF); return (q >> 24) | ((q >> 8) & 0xFF00) | ((q << 8) & 0xFF0000) | (q << 24); }
static void wr32(uint32_t v) { acc(true, 0, 0xF, (v & 0xFF) << 24 | ((v >> 8) & 0xFF) << 16 | ((v >> 16) & 0xFF) << 8 | (v >> 24)); }

static void expect(const char *what, long got, long want) {
	if (got != want) { printf("  %s: %lX, want %lX\n", what, got, want); fails++; }
}
static void report(const char *what, int f0) { printf("%-56s %s\n", what, fails != f0 ? "FAIL" : "pass"); }
static int wait_not_busy(int lim = 4000000) {
	int s = 0;
	for (int i = 0; i < lim; i++) { s = rd8(7); if (!(s & 0x80)) return s; run(20); }
	printf("  still busy\n"); fails++; return s;
}
static int wait_irq(int lim = 4000000) {
	for (int i = 0; i < lim; i++) { if (t->irq) return 1; run(10); }
	printf("  no interrupt\n"); fails++; return 0;
}

// a read command: n sectors, each DRQ block drained with 16- or 32-bit reads, an interrupt per block
static int read_cmd(uint8_t cmd, uint32_t lba, int n, std::vector<uint8_t> *d, bool wide = false, int blk = 1, bool chs = false) {
	wr8(2, n & 0xFF);
	if (chs) { uint32_t c = lba / (16 * 63), h = (lba / 63) % 16, s = lba % 63 + 1; wr8(3, s); wr8(4, c); wr8(5, c >> 8); wr8(6, 0x10 | h); }
	else { wr8(3, lba); wr8(4, lba >> 8); wr8(5, lba >> 16); wr8(6, 0xF0 | ((lba >> 24) & 0xF)); }
	wr8(7, cmd);
	int st = 0, blocks = 0;
	for (int left = n; left > 0; ) {
		if (!wait_irq()) { printf("  (read block %d of %d: status %02X, error %02X)\n", blocks, n, rd8(7), rd8(1)); return -1; }
		st = wait_not_busy();
		if (st & 1) { printf("  (read block %d: ERR, error %02X)\n", blocks, rd8(1)); return st; }
		if (!(st & 0x08)) { printf("  no DRQ (status %02X)\n", st); fails++; return st; }
		int k = left < blk ? left : blk;
		for (int i = 0; i < k * 512; ) {
			if (wide) { uint32_t v = rd32(); for (int j = 0; j < 4; j++) d->push_back(v >> (8 * j)); i += 4; }
			else { uint16_t v = rd16(); d->push_back(v & 0xFF); d->push_back(v >> 8); i += 2; }
		}
		left -= k; blocks++;
	}
	st = wait_not_busy();
	expect("read: DRQ clear at the end", st & 0x08, 0);
	return st;
}
// a write command: n sectors from d, the first block on DRQ (no interrupt), then an interrupt per block
static int write_cmd(uint8_t cmd, uint32_t lba, int n, const std::vector<uint8_t> &d, int blk = 1) {
	wr8(2, n & 0xFF); wr8(3, lba); wr8(4, lba >> 8); wr8(5, lba >> 16); wr8(6, 0xF0 | ((lba >> 24) & 0xF));
	wr8(7, cmd);
	size_t p = 0;
	for (int left = n; left > 0; ) {
		int st = wait_not_busy();
		if (st & 1) return st;
		if (!(st & 0x08)) { printf("  write: no DRQ (status %02X)\n", st); fails++; return st; }
		int k = left < blk ? left : blk;
		for (int i = 0; i < k * 512; i += 2) { wr16(d[p] | d[p + 1] << 8); p += 2; }
		left -= k;
		if (!wait_irq()) return -1;                 // the block written (or the next block's DRQ)
	}
	return wait_not_busy();
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Videhdtb;
	t->img_blocks[0] = HD_BLOCKS; t->img_blocks[1] = 0; t->img_blocks[2] = CD_BLOCKS * 4;
	t->rst = 1; run(5); t->rst = 0; run(5);
	int f0;

	f0 = fails;
	wr8(6, 0x10);
	expect("device 1 status DRDY", rd8(7) & 0xC8, 0x40);
	expect("signature 1F3", rd8(3), 0x01); expect("signature 1F4", rd8(4), 0x00); expect("signature 1F5", rd8(5), 0x00);
	wr8(6, 0x00); expect("device 0 (CD) signature 1F4", rd8(4), 0x14); expect("device 0 signature 1F5", rd8(5), 0xEB);
	report("reset: device 1 present with the ATA signature, device 0 the CD", f0);

	f0 = fails;
	wr8(6, 0x10); wr8(7, 0xEC);
	wait_irq(); int s = wait_not_busy();
	expect("IDENTIFY DEVICE: DRQ", s & 0x08, 0x08);
	std::vector<uint16_t> id;
	for (int i = 0; i < 256; i++) id.push_back(rd16());
	expect("word 0: fixed disk", id[0], 0x0040);
	expect("cylinders", id[1], HD_BLOCKS / (16 * 63)); expect("heads", id[3], 16); expect("sectors", id[6], 63);
	expect("LBA capable", id[49] & 0x200, 0x200);
	expect("LBA sectors low", id[60], HD_BLOCKS & 0xFFFF); expect("LBA sectors high", id[61], HD_BLOCKS >> 16);
	expect("model's first word", id[27], 0x4942);
	expect("DRQ after", rd8(7) & 0x08, 0);
	report("IDENTIFY DEVICE", f0);

	f0 = fails;
	for (int pass = 0; pass < 2; pass++) {
		std::vector<uint8_t> d;
		s = read_cmd(0x20, 100, 3, &d, pass == 1);
		expect("READ SECTORS ERR", s & 1, 0); expect("bytes", d.size(), 1536);
		int bad = 0;
		for (size_t i = 0; i < d.size(); i++) if (d[i] != img(0, 100 + i / 512, i % 512)) { if (bad++ < 3) printf("  byte %zu: %02X, want %02X\n", i, d[i], img(0, 100 + i / 512, i % 512)); }
		if (bad) fails++;
	}
	report("READ SECTORS, 3 sectors by LBA: 16-bit, then 32-bit reads", f0);

	f0 = fails;
	{
		std::vector<uint8_t> d;
		s = read_cmd(0x20, 5000, 2, &d, false, 1, true);
		expect("READ SECTORS (CHS) ERR", s & 1, 0); expect("bytes", d.size(), 1024);
		int bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != img(0, 5000 + i / 512, i % 512)) bad++;
		if (bad) { printf("  %d bytes wrong\n", bad); fails++; }
	}
	report("READ SECTORS by CHS (16 heads, 63 sectors)", f0);

	f0 = fails;
	{
		std::vector<uint8_t> w;
		for (int i = 0; i < 2 * 512; i++) w.push_back(uint8_t(i * 3 + 1));
		s = write_cmd(0x30, 300, 2, w);
		expect("WRITE SECTORS ERR", s & 1, 0);
		int bad = 0; for (int i = 0; i < 1024; i++) if (img(0, 300 + i / 512, i % 512) != w[i]) bad++;
		if (bad) { printf("  %d bytes not written\n", bad); fails++; }
		std::vector<uint8_t> d; s = read_cmd(0x20, 300, 2, &d);
		bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != w[i]) bad++;
		if (bad || d.size() != 1024) { printf("  read back: %d bytes wrong of %zu\n", bad, d.size()); fails++; }
	}
	report("WRITE SECTORS, 2 sectors, read back", f0);

	f0 = fails;
	{
		wr8(2, 8); wr8(7, 0xC6); wait_irq(); s = wait_not_busy(); expect("SET MULTIPLE 8: no ERR", s & 1, 0);
		std::vector<uint8_t> d;
		s = read_cmd(0xC4, 1000, 19, &d, true, 8);                // 8 + 8 + 3
		expect("READ MULTIPLE ERR", s & 1, 0); expect("bytes", d.size(), 19 * 512);
		int bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != img(0, 1000 + i / 512, i % 512)) bad++;
		if (bad) { printf("  %d bytes wrong\n", bad); fails++; }
		std::vector<uint8_t> w; for (int i = 0; i < 10 * 512; i++) w.push_back(uint8_t(i ^ (i >> 7)));
		s = write_cmd(0xC5, 2000, 10, w, 8);                      // 8 + 2
		expect("WRITE MULTIPLE ERR", s & 1, 0);
		bad = 0; for (int i = 0; i < 10 * 512; i++) if (img(0, 2000 + i / 512, i % 512) != w[i]) bad++;
		if (bad) { printf("  %d bytes not written\n", bad); fails++; }
	}
	report("SET MULTIPLE 8, READ MULTIPLE 19, WRITE MULTIPLE 10", f0);

	f0 = fails;
	{
		std::vector<uint8_t> d;
		s = read_cmd(0x20, 7000, 40, &d, true);                   // 32 + 8: two chunks
		expect("READ SECTORS 40 ERR", s & 1, 0); expect("bytes", d.size(), 40 * 512);
		int bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != img(0, 7000 + i / 512, i % 512)) bad++;
		if (bad) { printf("  %d bytes wrong\n", bad); fails++; }
		std::vector<uint8_t> w; for (int i = 0; i < 256 * 512; i++) w.push_back(uint8_t(i * 5 + (i >> 9)));
		s = write_cmd(0x30, 8000, 256, w);                        // sector count 0: 8 chunks
		expect("WRITE SECTORS 256 ERR", s & 1, 0);
		bad = 0; for (int i = 0; i < 256 * 512; i++) if (img(0, 8000 + i / 512, i % 512) != w[i]) bad++;
		if (bad) { printf("  %d bytes not written\n", bad); fails++; }
		d.clear(); s = read_cmd(0xC4, 8000, 40, &d, false, 8);     // read back in multiples across a chunk edge
		bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != w[i]) bad++;
		if (bad || d.size() != 40 * 512) { printf("  read back: %d wrong of %zu\n", bad, d.size()); fails++; }
	}
	report("40 sectors read, 256 written (sector count 0), 40 read back in 8s", f0);

	f0 = fails;
	wr8(2, 4); wr8(3, 50); wr8(4, 0); wr8(5, 0); wr8(6, 0xF0); wr8(7, 0x40);
	wait_irq(); s = wait_not_busy(); expect("READ VERIFY: no ERR, no DRQ", s & 0x09, 0);
	wr8(2, 1); wr8(3, HD_BLOCKS & 0xFF); wr8(4, HD_BLOCKS >> 8); wr8(5, HD_BLOCKS >> 16); wr8(6, 0xF0); wr8(7, 0x20);
	wait_irq(); s = wait_not_busy(); expect("READ past the end: ERR", s & 1, 1); expect("its error IDNF", rd8(1), 0x10);
	wr8(7, 0xF5); wait_irq(); s = wait_not_busy(); expect("unknown command: ERR", s & 1, 1); expect("its error ABRT", rd8(1), 0x04);
	wr8(7, 0x10); wait_irq(); s = wait_not_busy(); expect("RECALIBRATE: done", s & 0x41, 0x40);
	report("READ VERIFY, an LBA past the end, an unknown command, RECALIBRATE", f0);

	f0 = fails;
	wr8(6, 0x00); wr8(7, 0xA1);
	expect("device 0 IDENTIFY PACKET DEVICE: DRQ", wait_not_busy() & 0x08, 0x08);
	std::vector<uint16_t> cid; for (int i = 0; i < 256; i++) cid.push_back(rd16());
	expect("the CD's word 0", cid[0], 0x85C0);
	wr8(6, 0x10); expect("device 1 again: DRDY, no DRQ", rd8(7) & 0x48, 0x40);
	report("the CD-ROM still device 0", f0);

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	return fails != 0;
}
