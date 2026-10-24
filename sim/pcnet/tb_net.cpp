// IBMRS6K7248 - the PCnet's wire end to end (nettb.sv: the PCnet, IBMRS6K7248_enetbox, IBMRS6K7248_ddrarb):
// a DDR3 model under the mailbox, this program as the Main's bridge (support/sun/sun_enet.cpp's side of
// the mailbox), the picture side's burst reads now and then. ./run.sh net builds and runs it.

#include "Vnettb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>
#include <map>

static Vnettb *t;
static uint8_t mem[1 << 20];
static std::map<uint32_t, uint64_t> ddr;               // 64-bit words by word address
static int fails, dma_wait;
static int rd_left, rd_wait; static uint32_t rd_addr;
static uint64_t cyc;
static const uint8_t MAC[6] = {0x08, 0x00, 0x5A, 0x11, 0x22, 0x33};
static const uint32_t MB = 0x03FE0000;                  // the mailbox, in words

static void tick() {
	// the CPU side's DMA, as tb_pcnet
	t->dm_ack = 0;
	if (t->dm_req) {
		if (++dma_wait == 2) {
			uint64_t a = uint64_t(t->dm_addr) << 3; uint32_t o = uint32_t(a - 0x80000000ull);
			t->dm_err = 0;
			if (t->dm_we) { for (int k = 0; k < 8; k++) if (t->dm_be & (0x80 >> k)) mem[o + k] = (t->dm_wdata >> (56 - 8 * k)) & 0xFF; }
			else { uint64_t d = 0; for (int k = 0; k < 8; k++) d = (d << 8) | mem[o + k]; t->dm_rdata = d; }
			t->dm_ack = 1; dma_wait = -100;
		}
	} else dma_wait = 0;
	// DDR3: busy now and then; a read burst a beat a clock after 5
	t->ddr_busy = (cyc % 7) == 0;
	t->ddr_dout_ready = 0;
	if (rd_left && rd_wait == 0) { t->ddr_dout = ddr.count(rd_addr) ? ddr[rd_addr] : 0; t->ddr_dout_ready = 1; rd_addr++; rd_left--; }
	else if (rd_left) rd_wait--;
	// the picture side: a 16-word read every 300 clocks
	if (cyc % 300 == 0) { t->v_rd = 1; t->v_addr = 0x06000000 + (cyc & 0xFFF); }
	// the port's request as it stands this cycle (before the edge): taken unless busy
	t->clk = 0; t->clk_m = 0; t->eval();
	if (!t->ddr_busy) {
		if (t->ddr_rd && !rd_left) { rd_addr = t->ddr_addr; rd_left = t->ddr_burstcnt; rd_wait = 5; }
		if (t->ddr_we) {
			uint64_t &w = ddr[t->ddr_addr];
			for (int b = 0; b < 8; b++) if (t->ddr_be & (1 << b)) w = (w & ~(0xFFull << (8 * b))) | (t->ddr_din & (0xFFull << (8 * b)));
		}
	}
	bool v_taken = t->v_rd && !t->v_busy;
	t->clk = 1; t->clk_m = 1; t->eval();
	if (v_taken) t->v_rd = 0;
	cyc++;
}
static void run(int n) { for (int i = 0; i < n; i++) tick(); }
static void bus_w(int off, int be, uint32_t d) { t->sel = 1; t->we = 1; t->off = off; t->be = be; t->wdata = d; tick(); t->sel = 0; t->we = 0; tick(); }
static uint32_t bus_r(int off, int be) { t->sel = 1; t->we = 0; t->off = off; t->be = be; tick(); t->sel = 0; tick(); return t->rdata; }
static void rap(int n) { bus_w(4, 0x3, uint32_t(n) << 8); }
static void csr_w(int n, uint16_t v) { rap(n); bus_w(4, 0xC, (uint32_t(v & 0xFF) << 24) | (uint32_t(v >> 8) << 16)); }
static uint16_t csr_r(int n) { rap(n); uint32_t r = bus_r(4, 0xC); return uint16_t(((r >> 24) & 0xFF) | ((r >> 8) & 0xFF00)); }
static void bcr_w(int n, uint16_t v) { rap(n); bus_w(5, 0x3, (uint32_t(v & 0xFF) << 8) | (v >> 8)); }
static void cfg_w(int reg, uint32_t v) { t->cfg_sel = 1; t->cfg_we = 1; t->cfg_reg = reg; t->cfg_be = 0xF; t->cfg_wdata = v; tick(); t->cfg_sel = 0; t->cfg_we = 0; tick(); }
static void w16(uint32_t a, uint16_t v) { mem[a] = v; mem[a + 1] = v >> 8; }
static void w32(uint32_t a, uint32_t v) { for (int k = 0; k < 4; k++) mem[a + k] = v >> (8 * k); }
static uint16_t r16(uint32_t a) { return mem[a] | (mem[a + 1] << 8); }
static void expect(const char *what, uint64_t got, uint64_t want) {
	if (got != want) { printf("  %s: %llX, want %llX\n", what, (unsigned long long)got, (unsigned long long)want); fails++; }
}
static uint64_t rd64(uint32_t off) { return ddr.count(MB + off / 8) ? ddr[MB + off / 8] : 0; }
static void wr64(uint32_t off, uint64_t v) { ddr[MB + off / 8] = v; }
static uint8_t rdb(uint32_t off) { return (rd64(off & ~7u) >> (8 * (off & 7))) & 0xFF; }
static void wrb(uint32_t off, uint8_t v) { uint64_t w = rd64(off & ~7u); w = (w & ~(0xFFull << (8 * (off & 7)))) | (uint64_t(v) << (8 * (off & 7))); wr64(off & ~7u, w); }
static bool wait_csr0(uint16_t bit) { for (int n = 0; n < 2000000; n += 500) { if (csr_r(0) & bit) return true; run(500); } return false; }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vnettb;
	t->reset = 1; run(10); t->reset = 0;

	// the mailbox comes up: MAGIC "RS6ETH01" last, the pointers zero
	run(3000);
	expect("MAGIC", rd64(0), 0x5253364554483031ull);
	expect("TX_WPTR", rd64(0x10), 0);
	// the Main's MAC for the PROM
	wr64(0x38, (1ull << 63) | 0x08005A112233ull);
	run(20000);
	{
		uint32_t r = bus_r(0, 0xF), r2 = bus_r(1, 0xF);
		expect("PROM from the Main", (uint64_t(r) << 16) | (r2 >> 16), 0x08005A112233ull);
	}

	// the PCnet initialised (style 2), as in tb_pcnet
	cfg_w(1, 0x0005);
	bcr_w(20, 2);
	const uint32_t IB = 0x100, TDR = 0x1000, RDR = 0x2000;
	mem[IB + 2] = 0x30; mem[IB + 3] = 0x30;
	for (int i = 0; i < 6; i++) mem[IB + 4 + i] = MAC[i];
	w32(IB + 20, 0x80000000 + RDR); w32(IB + 24, 0x80000000 + TDR);
	for (int i = 0; i < 8; i++) {
		uint32_t a = RDR + 16 * i; w32(a, 0x80010000 + 0x800 * i); w16(a + 4, uint16_t(0xF000 | (-1536 & 0xFFF))); w16(a + 6, 0x8000);
	}
	csr_w(1, (0x80000000 + IB) & 0xFFFF); csr_w(2, 0x8000);
	csr_w(0, 0x0001); wait_csr0(0x0100); csr_w(0, 0x0142);
	run(20000);
	expect("MAC word (the driver's)", rd64(0x30), (1ull << 63) | 0x08005A112233ull);

	// TX: a frame into slot 0, its length, TX_WPTR 1
	int f0 = fails;
	{
		uint8_t f[75];
		for (int i = 0; i < 75; i++) f[i] = uint8_t(i * 13 + 5);
		memcpy(&mem[0x20000], f, 75);
		uint32_t a = TDR; w32(a, 0x80020000); w16(a + 4, uint16_t(0xF000 | (-75 & 0xFFF))); w16(a + 6, 0x8300);
		csr_w(0, 0x0048);
		for (int n = 0; n < 400 && rd64(0x10) != 1; n++) run(500);
		expect("TX_WPTR", rd64(0x10), 1);
		expect("TX slot length", rd64(0x1000) & 0x7FF, 75);
		int bad = 0; for (int i = 0; i < 75; i++) if (rdb(0x1008 + i) != f[i]) bad++;
		expect("TX slot bytes wrong", bad, 0);
		wr64(0x18, 1);                                   // the Main took it
	}
	printf("%-46s %s\n", "transmit through the mailbox", fails != f0 ? "FAIL" : "pass"); f0 = fails;

	// RX: the Main posts a frame (with its FCS and hash) into slot 0, RX_WPTR 1
	{
		uint8_t f[68];
		memcpy(f, MAC, 6); for (int i = 6; i < 68; i++) f[i] = uint8_t(i * 3 + 1);
		for (int i = 0; i < 68; i++) wrb(0x5008 + i, f[i]);
		wr64(0x5000, 68 | (5ull << 16));
		wr64(0x20, 1);
		expect("RINT", wait_csr0(0x0400), 1);
		expect("RX bytes", memcmp(&mem[0x10000], f, 68), 0);
		expect("RX STP ENP PAM", r16(RDR + 6) & 0x8340, 0x0340);
		run(5000);
		expect("RX_RPTR", rd64(0x28), 1);
	}
	printf("%-46s %s\n", "receive through the mailbox", fails != f0 ? "FAIL" : "pass");

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
