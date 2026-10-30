// IBMRS6K7248 - the ATAPI CD-ROM's bench (atapitb.sv: IBMRS6K7248_atapi as the initiator of
// IBMRS6K7248_scsitgt's CD-ROM): the packet signature after reset, IDENTIFY PACKET DEVICE, INQUIRY,
// READ CAPACITY, READ(10) of two blocks in 2 KB DRQ blocks (16-bit and 32-bit data port reads),
// a short byte count (512-byte blocks), an unknown packet (ERR), IDENTIFY DEVICE (aborted). ./run.sh.

#include "Vatapitb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static Vatapitb *t;
static int fails;
static const uint32_t CD_BLOCKS = 4000;          // 2 KB blocks: 8000 512-byte image blocks

static uint8_t img(uint64_t blk, int off) { return uint8_t(blk * 13 + off * 7 + (off >> 8)); }

// hps_io: a request answered after a turnaround, a byte a clock
static int h_state, h_slot, h_wait, h_n, h_i;
static uint64_t h_lba;
static void hps() {
	t->sd_buff_wr = 0;
	switch (h_state) {
	case 0:
		for (int s = 0; s < 3; s++) if ((t->sd_rd >> s) & 1) {
			h_slot = s; h_lba = t->sd_lba[s]; h_n = (t->sd_blk_cnt[s] + 1) * 512; h_i = 0; h_wait = 200; h_state = 1;
			break;
		}
		break;
	case 1: if (--h_wait == 0) { t->sd_ack = 1 << h_slot; h_state = 2; } break;
	case 2:
		if (h_i < h_n) { t->sd_buff_addr = h_i; t->sd_buff_dout = img(h_lba + h_i / 512, h_i % 512); t->sd_buff_wr = 1; h_i++; }
		else { t->sd_ack = 0; h_state = 3; h_wait = 4; }
		break;
	case 3: if (--h_wait == 0) h_state = 0; break;
	}
}
static void tick() { hps(); t->clk = 0; t->clk_h = 0; t->eval(); t->clk = 1; t->clk_h = 1; t->eval(); }
static void run(int n) { for (int i = 0; i < n; i++) tick(); }

// the host: an access at register r (cs1: 3F6) with lanes be (bit 3 = lane 0), as the CPU's bus makes it
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

static void expect(const char *what, long got, long want) {
	if (got != want) { printf("  %s: %lX, want %lX\n", what, got, want); fails++; }
}
static void report(const char *what, int f0) { printf("%-52s %s\n", what, fails != f0 ? "FAIL" : "pass"); }

static int wait_not_busy(int lim = 4000000) {
	int s = 0;
	for (int i = 0; i < lim; i++) { s = rd8(7); if (!(s & 0x80)) return s; run(20); }
	printf("  still busy\n"); fails++; return s;
}

// a packet: its data in (DRQ blocks of the device's byte count) with 16- or 32-bit reads; the final status
static int packet(std::vector<uint8_t> cdb, uint16_t limit, std::vector<uint8_t> *din, bool wide = false,
                  std::vector<int> *blocks = nullptr) {
	wr8(1, 0); wr8(4, limit & 0xFF); wr8(5, limit >> 8); wr8(7, 0xA0);
	int s = wait_not_busy();
	if (!(s & 0x08) || rd8(2) != 1) { printf("  no packet DRQ (status %02X, reason %02X)\n", s, rd8(2)); fails++; return -1; }
	cdb.resize(12);
	for (int i = 0; i < 12; i += 2) wr16(cdb[i] | cdb[i + 1] << 8);
	for (;;) {
		s = wait_not_busy();
		int ir = rd8(2);
		if ((s & 0x08) && ir == 2) {
			int n = rd8(4) | rd8(5) << 8;
			if (blocks) blocks->push_back(n);
			for (int i = 0; i < n; ) {
				if (wide && n - i >= 4) { uint32_t v = rd32(); for (int k = 0; k < 4; k++) din->push_back(v >> (8 * k)); i += 4; }
				else { uint16_t v = rd16(); din->push_back(v & 0xFF); din->push_back(v >> 8); i += 2; }
			}
		} else if (ir == 3 && !(s & 0x08)) return s;
		else { printf("  unexpected status %02X reason %02X\n", s, ir); fails++; return s; }
	}
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vatapitb;
	t->img_blocks[0] = 0; t->img_blocks[1] = 0; t->img_blocks[2] = CD_BLOCKS * 4;
	t->rst = 1; run(5); t->rst = 0; run(5);
	int f0;

	f0 = fails;
	expect("signature 1F4", rd8(4), 0x14); expect("signature 1F5", rd8(5), 0xEB);
	wr8(6, 0x10); expect("device 1's status", rd8(7), 0x00); wr8(6, 0x00);
	wr8(7, 0xEC); expect("IDENTIFY DEVICE: ERR", rd8(7) & 1, 1); expect("its error", rd8(1), 4);
	expect("its signature", rd8(4) | rd8(5) << 8, 0xEB14);
	report("signature, device 1 absent, IDENTIFY DEVICE aborted", f0);

	f0 = fails;
	wr8(7, 0xA1);
	expect("IDENTIFY PACKET DEVICE: DRQ", wait_not_busy() & 0x08, 0x08);
	std::vector<uint16_t> id;
	for (int i = 0; i < 256; i++) id.push_back(rd16());
	expect("word 0", id[0], 0x85C0); expect("model's first word", id[27], 0x4942);
	expect("DRQ after", rd8(7) & 0x08, 0);
	report("IDENTIFY PACKET DEVICE", f0);

	f0 = fails;
	std::vector<uint8_t> d;
	int s = packet({0x12, 0, 0, 0, 36, 0}, 36, &d);
	expect("INQUIRY status ERR", s & 1, 0); expect("INQUIRY length", d.size(), 36); if (d.size()) expect("peripheral type", d[0] & 0x1F, 5);
	d.clear(); s = packet({0x25}, 8, &d);
	expect("READ CAPACITY length", d.size(), 8);
	if (d.size() == 8) {
		expect("last block", d[0] << 24 | d[1] << 16 | d[2] << 8 | d[3], CD_BLOCKS - 1);
		expect("block size", d[4] << 24 | d[5] << 16 | d[6] << 8 | d[7], 2048);
	}
	report("INQUIRY, READ CAPACITY", f0);

	f0 = fails;
	for (int pass = 0; pass < 2; pass++) {
		d.clear(); std::vector<int> bl;
		s = packet({0x28, 0, 0, 0, 0, 16, 0, 0, 2, 0}, 0xFFFF, &d, pass == 1, &bl);
		expect("READ(10) ERR", s & 1, 0); expect("bytes", d.size(), 4096); expect("blocks", bl.size(), 2);
		int bad = 0;
		for (size_t i = 0; i < d.size(); i++) if (d[i] != img(64 + i / 512, i % 512)) { if (bad++ < 3) printf("  byte %zu: %02X, want %02X\n", i, d[i], img(64 + i / 512, i % 512)); }
		if (bad) fails++;
	}
	report("READ(10) of 2 blocks: 16-bit, then 32-bit reads", f0);

	f0 = fails;
	d.clear(); std::vector<int> bl;
	s = packet({0x28, 0, 0, 0, 0, 3, 0, 0, 1, 0}, 512, &d, false, &bl);
	expect("bytes", d.size(), 2048); expect("blocks of 512", bl.size(), 4);
	{ int bad = 0; for (size_t i = 0; i < d.size(); i++) if (d[i] != img(12 + i / 512, i % 512)) bad++; if (bad) { printf("  %d bytes wrong\n", bad); fails++; } }
	report("READ(10) with a 512-byte byte count", f0);

	f0 = fails;
	d.clear(); s = packet({0xF5}, 64, &d);
	expect("unknown packet: ERR", s & 1, 1); expect("its error's sense key", rd8(1) >> 4, 5);
	d.clear(); s = packet({0x00}, 0, &d);                  // TEST UNIT READY after it
	expect("TEST UNIT READY: no ERR", s & 1, 0);
	report("an unknown packet (ERR), then TEST UNIT READY", f0);

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	return fails != 0;
}
