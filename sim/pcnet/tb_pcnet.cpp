// IBMRS6K7248 - a bench of the PCnet alone (IBMRS6K7248_pcnet): its registers as the CPU's device bus
// gives them, a memory model on its DMA port (PCI address 8000_0000 + n = memory n), the wire driven
// here. ./run.sh builds and runs it; it prints each test and "ALL PASS" or the differences.

#include "VIBMRS6K7248_pcnet.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static VIBMRS6K7248_pcnet *t;
static uint8_t mem[1 << 20];               // PCI 8000_0000 + n
static int fails;
static int dma_wait;
static const uint8_t MAC[6] = {0x08, 0x00, 0x5A, 0x11, 0x22, 0x33};

static void tick() {
	// DMA: answer after 2 clocks
	t->dm_ack = 0;
	if (t->dm_req) {
		if (++dma_wait == 2) {
			uint64_t a = (uint64_t(t->dm_addr) << 3);
			t->dm_err = !(a >= 0x80000000ull && a < 0x80000000ull + sizeof mem);
			uint32_t o = uint32_t(a - 0x80000000ull);
			if (!t->dm_err) {
				if (t->dm_we) {
					for (int k = 0; k < 8; k++) if (t->dm_be & (0x80 >> k)) mem[o + k] = (t->dm_wdata >> (56 - 8 * k)) & 0xFF;
				} else {
					uint64_t d = 0;
					for (int k = 0; k < 8; k++) d = (d << 8) | mem[o + k];
					t->dm_rdata = d;
				}
			}
			t->dm_ack = 1;
			dma_wait = -100;
		}
	} else dma_wait = 0;
	t->clk = 0; t->clk_m = 0; t->eval();
	t->clk = 1; t->clk_m = 1; t->eval();
}
static void run(int n) { for (int i = 0; i < n; i++) tick(); }

// the device bus: off = word (0-7), be[3] the lowest address, its byte in wdata[31:24]
static void bus_w(int off, int be, uint32_t d) { t->sel = 1; t->we = 1; t->off = off; t->be = be; t->wdata = d; tick(); t->sel = 0; t->we = 0; tick(); }
static uint32_t bus_r(int off, int be) { t->sel = 1; t->we = 0; t->off = off; t->be = be; tick(); t->sel = 0; tick(); return t->rdata; }
static void rap(int n) { bus_w(4, 0x3, uint32_t(n) << 8); }
static void csr_w(int n, uint16_t v) { rap(n); bus_w(4, 0xC, (uint32_t(v & 0xFF) << 24) | (uint32_t(v >> 8) << 16)); }
static uint16_t csr_r(int n) { rap(n); uint32_t r = bus_r(4, 0xC); return uint16_t(((r >> 24) & 0xFF) | ((r >> 8) & 0xFF00)); }
static void bcr_w(int n, uint16_t v) { rap(n); bus_w(5, 0x3, (uint32_t(v & 0xFF) << 8) | (v >> 8)); }
static uint16_t bcr_r(int n) { rap(n); uint32_t r = bus_r(5, 0x3); return uint16_t(((r >> 8) & 0xFF) | ((r & 0xFF) << 8)); }
static void cfg_w(int reg, uint32_t v) { t->cfg_sel = 1; t->cfg_we = 1; t->cfg_reg = reg; t->cfg_be = 0xF; t->cfg_wdata = v; tick(); t->cfg_sel = 0; t->cfg_we = 0; tick(); }
static uint32_t cfg_r(int reg) { t->cfg_sel = 1; t->cfg_we = 0; t->cfg_reg = reg; tick(); t->cfg_sel = 0; tick(); return t->cfg_rdata; }

static void w16(uint32_t a, uint16_t v) { mem[a] = v; mem[a + 1] = v >> 8; }
static void w32(uint32_t a, uint32_t v) { for (int k = 0; k < 4; k++) mem[a + k] = v >> (8 * k); }
static uint16_t r16(uint32_t a) { return mem[a] | (mem[a + 1] << 8); }
static uint32_t r32(uint32_t a) { return mem[a] | (mem[a + 1] << 8) | (mem[a + 2] << 16) | (uint32_t(mem[a + 3]) << 24); }
static void expect(const char *what, uint64_t got, uint64_t want) {
	if (got != want) { printf("  %s: %llX, want %llX\n", what, (unsigned long long)got, (unsigned long long)want); fails++; }
}
static int section(const char *name, int f0) { printf("%-46s %s\n", name, fails != f0 ? "FAIL" : "pass"); return fails; }

static uint32_t crc32(const uint8_t *p, int n) {
	uint32_t c = 0xFFFFFFFF;
	while (n--) { c ^= *p++; for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1)); }
	return c;
}

// the wire: a frame the PCnet sent (tx_pend), taken; a frame posted to it
static std::vector<uint8_t> wire_take() {
	std::vector<uint8_t> f;
	int n = 0;
	while (!t->tx_pend) { tick(); if (++n > 200000) return f; }
	int len = t->tx_len;
	for (int i = 0; i < len; i++) { t->m_tx_a = i; tick(); f.push_back(t->m_tx_q); }
	t->m_tx_done = 1; tick(); t->m_tx_done = 0; run(10);
	return f;
}
static void wire_post(const std::vector<uint8_t> &f, int hash) {
	int n = 0;
	while (!t->rx_free) { tick(); if (++n > 200000) { printf("  rx never free\n"); fails++; return; } }
	for (size_t i = 0; i < f.size(); i++) { t->m_rx_we = 1; t->m_rx_a = i; t->m_rx_d = f[i]; tick(); }
	t->m_rx_we = 0;
	t->m_rx_len = f.size(); t->m_rx_hash = hash; t->m_rx_post = 1; tick(); t->m_rx_post = 0;
}
static std::vector<uint8_t> frame(const uint8_t *dst, int len, int seed) {
	std::vector<uint8_t> f(len);
	memcpy(&f[0], dst, 6); memcpy(&f[6], MAC, 6); f[12] = 0x08; f[13] = 0x00;
	for (int i = 14; i < len; i++) f[i] = uint8_t(seed + i * 7);
	return f;
}

// rings (SWSTYLE 2, 16-byte descriptors): TX at 0x1000, RX at 0x2000, buffers from 0x10000
static const uint32_t IB = 0x0100, TDR = 0x1000, RDR = 0x2000;
static void rx_desc2(int i, uint32_t buf, int len, bool own) {
	uint32_t a = RDR + 16 * i;
	w32(a, 0x80000000 + buf); w16(a + 4, uint16_t(0xF000 | (-len & 0xFFF))); w16(a + 6, own ? 0x8000 : 0); w32(a + 8, 0); w32(a + 12, 0);
}
static void tx_desc2(int i, uint32_t buf, int len, uint16_t st) {
	uint32_t a = TDR + 16 * i;
	w32(a, 0x80000000 + buf); w16(a + 4, uint16_t(0xF000 | (-len & 0xFFF))); w16(a + 6, st); w32(a + 8, 0); w32(a + 12, 0);
}
static bool wait_csr0(uint16_t bit, int lim = 300000) {
	for (int n = 0; n < lim; n += 200) { if (csr_r(0) & bit) return true; run(200); }
	return false;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new VIBMRS6K7248_pcnet;
	t->aprom_mac = (uint64_t(MAC[0]) << 40) | (uint64_t(MAC[1]) << 32) | (MAC[2] << 24) | (MAC[3] << 16) | (MAC[4] << 8) | MAC[5];
	t->reset = 1; run(5); t->reset = 0; run(5);

	// 1. PCI configuration, the address PROM
	int f0 = fails;
	expect("ID", cfg_r(0), 0x20001022);
	expect("class/rev", cfg_r(2), 0x02000010);
	cfg_w(4, 0x00001000); cfg_w(1, 0x0005);              // BAR0, I/O and bus master on
	expect("BAR0", cfg_r(4), 0x00001001);
	expect("io_on", t->io_on, 1);
	{
		uint8_t p[16]; uint16_t sum = 0;
		for (int w = 0; w < 4; w++) { uint32_t r = bus_r(w, 0xF); for (int k = 0; k < 4; k++) p[4 * w + k] = r >> (24 - 8 * k); }
		for (int i = 0; i < 6; i++) expect("PROM MAC", p[i], MAC[i]);
		for (int i = 0; i < 12; i++) sum += p[i];
		sum += p[14] + p[15];
		expect("PROM checksum", p[12] | (p[13] << 8), sum);
		expect("PROM W W", p[14] << 8 | p[15], 0x5757);
	}
	expect("CSR0 after reset", csr_r(0), 0x0004);
	expect("chip ID", csr_r(88) | (uint32_t(csr_r(89)) << 16), 0x02621003);
	f0 = section("PCI configuration, the PROM, the CSRs", f0);

	// 2. a 32-bit init block (SWSTYLE 2): 8 RX and 8 TX descriptors
	bcr_w(20, 2);
	expect("SWSTYLE", bcr_r(20), 0x0302);
	w16(IB + 0, 0x0000);                                 // mode
	mem[IB + 2] = 3 << 4; mem[IB + 3] = 3 << 4;          // RLEN, TLEN: 8
	for (int i = 0; i < 6; i++) mem[IB + 4 + i] = MAC[i];
	w32(IB + 12, 0); w32(IB + 16, 0x00000000);            // LADRF
	mem[IB + 12 + 2] = 0x00;
	w32(IB + 20, 0x80000000 + RDR); w32(IB + 24, 0x80000000 + TDR);
	for (int i = 0; i < 8; i++) { rx_desc2(i, 0x10000 + 0x800 * i, 1536, true); tx_desc2(i, 0x20000 + 0x800 * i, 0, 0); }
	csr_w(1, (0x80000000 + IB) & 0xFFFF); csr_w(2, (0x80000000 + IB) >> 16);
	csr_w(0, 0x0001);
	expect("IDON", wait_csr0(0x0100), 1);
	expect("CSR0 after init", csr_r(0), 0x0181);         // IDON, INTR (no INEA: irq low), INIT
	expect("irq without INEA", t->irq, 0);
	expect("RCVRL", csr_r(76), 8);
	expect("PADR", t->padr, (uint64_t(MAC[0]) << 40) | (uint64_t(MAC[1]) << 32) | (MAC[2] << 24) | (MAC[3] << 16) | (MAC[4] << 8) | MAC[5]);
	csr_w(0, 0x0142);                                    // clear IDON, STRT, INEA
	run(20);
	expect("CSR0 started", csr_r(0) & 0x00F7, 0x0073);   // INEA, RXON, TXON, STRT, INIT
	f0 = section("init block (32-bit), start", f0);

	// 3. transmit a 60-byte frame from one descriptor
	{
		uint8_t bc[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
		auto f = frame(bc, 60, 1);
		memcpy(&mem[0x20000], f.data(), f.size());
		tx_desc2(0, 0x20000, 60, 0x8300);                // OWN, STP, ENP
		csr_w(0, 0x0048);                                // TDMD, INEA
		auto g = wire_take();
		expect("TX length", g.size(), 60);
		expect("TX bytes", g == f, 1);
		run(500);
		expect("TX descriptor released", r16(TDR + 6) & 0x8000, 0);
		expect("TINT", csr_r(0) & 0x0200, 0x0200);
		expect("irq", t->irq, 1);
		csr_w(0, 0x0240);                                // clear TINT
		expect("irq cleared", t->irq, 0);
	}
	f0 = section("transmit: one descriptor", f0);

	// 3b. a frame gathered from two descriptors (STP; then ENP), odd lengths and addresses
	{
		uint8_t d[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01};
		auto f = frame(d, 101, 9);
		memcpy(&mem[0x20803], &f[0], 37);
		memcpy(&mem[0x21001], &f[37], 64);
		tx_desc2(1, 0x20803, 37, 0x8200);                // OWN, STP
		tx_desc2(2, 0x21001, 64, 0x8100);                // OWN, ENP
		csr_w(0, 0x0048);
		auto g = wire_take();
		expect("TX2 length", g.size(), 101);
		expect("TX2 bytes", g == f, 1);
		run(500);
		expect("TX2 descriptors released", (r16(TDR + 16 + 6) | r16(TDR + 32 + 6)) & 0x8000, 0);
		csr_w(0, 0x0240);
	}
	f0 = section("transmit: a frame across two descriptors", f0);

	// 4. receive a frame for our address into descriptor 0
	{
		auto f = frame(MAC, 64, 3);                      // (64 with its FCS)
		wire_post(f, 0);
		expect("RINT", wait_csr0(0x0400), 1);
		expect("RX descriptor released", r16(RDR + 6) & 0x8000, 0);
		expect("RX STP ENP PAM", r16(RDR + 6) & 0x0340, 0x0340);
		expect("RX MCNT", r32(RDR + 8) & 0xFFF, 64);
		expect("RX bytes", memcmp(&mem[0x10000], f.data(), 64), 0);
		csr_w(0, 0x0440);
		// a frame for someone else: dropped; a broadcast: taken (BAM)
		uint8_t other[6] = {0x02, 0x11, 0x11, 0x11, 0x11, 0x11};
		wire_post(frame(other, 70, 4), 0);
		run(3000);
		expect("filtered: no RINT", csr_r(0) & 0x0400, 0);
		expect("filtered: descriptor 1 still ours", r16(RDR + 16 + 6) & 0x8000, 0x8000);
		uint8_t bc[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
		wire_post(frame(bc, 70, 5), 0);
		expect("broadcast RINT", wait_csr0(0x0400), 1);
		expect("broadcast BAM", r16(RDR + 16 + 6) & 0x0310, 0x0310);
		csr_w(0, 0x0440);
	}
	f0 = section("receive: filter, physical and broadcast", f0);

	// 5. a frame chained over small buffers (descriptors 2-4: 40 bytes each, a 100-byte frame)
	{
		rx_desc2(2, 0x30000, 40, true); rx_desc2(3, 0x30100, 40, true); rx_desc2(4, 0x30200, 40, true);
		auto f = frame(MAC, 100, 6);
		wire_post(f, 0);
		expect("chain RINT", wait_csr0(0x0400), 1);
		expect("chain desc 2: STP, not ENP", r16(RDR + 32 + 6) & 0x8300, 0x0200);
		expect("chain desc 3: neither", r16(RDR + 48 + 6) & 0x8300, 0x0000);
		expect("chain desc 4: ENP", r16(RDR + 64 + 6) & 0x8300, 0x0100);
		expect("chain MCNT", r32(RDR + 64 + 8) & 0xFFF, 100);
		expect("chain bytes 1", memcmp(&mem[0x30000], &f[0], 40), 0);
		expect("chain bytes 2", memcmp(&mem[0x30100], &f[40], 40), 0);
		expect("chain bytes 3", memcmp(&mem[0x30200], &f[80], 20), 0);
		csr_w(0, 0x0440);
	}
	f0 = section("receive: a frame chained over three buffers", f0);

	// 6. internal loopback (mode LOOP + INTL): the frame comes back with its FCS
	{
		csr_w(0, 0x0004);                                // STOP
		w16(IB, 0x0044);                                 // LOOP, INTL
		for (int i = 0; i < 8; i++) { rx_desc2(i, 0x10000 + 0x800 * i, 1536, true); tx_desc2(i, 0x20000 + 0x800 * i, 0, 0); }
		csr_w(0, 0x0001);
		expect("loop IDON", wait_csr0(0x0100), 1);
		csr_w(0, 0x0142);
		auto f = frame(MAC, 64, 8);
		memcpy(&mem[0x20000], f.data(), 64);
		tx_desc2(0, 0x20000, 64, 0x8300);
		csr_w(0, 0x0048);
		expect("loop RINT", wait_csr0(0x0400), 1);
		expect("loop MCNT", r32(RDR + 8) & 0xFFF, 68);
		uint32_t fcs = ~crc32(f.data(), 64);
		expect("loop bytes", memcmp(&mem[0x10000], f.data(), 64), 0);
		expect("loop FCS", r32(0x10000 + 64), fcs);
		expect("loop: nothing on the wire", t->tx_pend, 0);
		csr_w(0, 0x0640);
	}
	f0 = section("internal loopback with its FCS", f0);

	// 7. missed: no descriptor owned
	{
		csr_w(0, 0x0004);
		w16(IB, 0x0000);
		for (int i = 0; i < 8; i++) { rx_desc2(i, 0x10000 + 0x800 * i, 1536, false); tx_desc2(i, 0x20000, 0, 0); }
		csr_w(0, 0x0001); wait_csr0(0x0100); csr_w(0, 0x0142);
		wire_post(frame(MAC, 64, 2), 0);
		expect("MISS", wait_csr0(0x1000), 1);
		expect("missed count", csr_r(112), 1);
		expect("rx free again", (run(200), t->rx_free), 1);
		csr_w(0, 0x1040);
	}
	f0 = section("missed frame: MISS, CSR112", f0);

	// 8. software style 0 (16-bit descriptors and init block)
	{
		csr_w(0, 0x0004);
		bcr_w(20, 0);
		uint32_t ib = 0x0200, rd = 0x3000, td = 0x3100;
		w16(ib, 0x0000);
		for (int i = 0; i < 6; i++) mem[ib + 2 + i] = MAC[i];
		for (int i = 0; i < 8; i++) mem[ib + 8 + i] = 0;
		w32(ib + 16, ((0x80000000 + rd) & 0xFFFFFF) | (2u << 29));   // 4 RX
		w32(ib + 20, ((0x80000000 + td) & 0xFFFFFF) | (2u << 29));   // 4 TX
		for (int i = 0; i < 4; i++) {
			w32(rd + 8 * i, ((0x80000000 + 0x40000 + 0x800 * i) & 0xFFFFFF) | 0x80000000u); w16(rd + 8 * i + 4, uint16_t(-1536)); w16(rd + 8 * i + 6, 0);
			w32(td + 8 * i, 0); w16(td + 8 * i + 4, 0); w16(td + 8 * i + 6, 0);
		}
		csr_w(1, (0x80000000 + ib) & 0xFFFF); csr_w(2, (0x80000000 + ib) >> 16);
		csr_w(0, 0x0001);
		expect("style 0 IDON", wait_csr0(0x0100), 1);
		csr_w(0, 0x0142);
		auto f = frame(MAC, 80, 11);
		wire_post(f, 0);
		expect("style 0 RINT", wait_csr0(0x0400), 1);
		expect("style 0 RX released, STP ENP", mem[rd + 3] & 0x83, 0x03);
		expect("style 0 MCNT", r16(rd + 6) & 0xFFF, 80);
		expect("style 0 RX bytes", memcmp(&mem[0x40000], f.data(), 80), 0);
		auto g = frame(MAC, 60, 12);
		memcpy(&mem[0x48000], g.data(), 60);
		w32(td, ((0x80000000 + 0x48000) & 0xFFFFFF) | 0x83000000u); w16(td + 4, uint16_t(-60));
		csr_w(0, 0x0448);
		auto h = wire_take();
		expect("style 0 TX bytes", h == g, 1);
		run(500);
		expect("style 0 TX released", mem[td + 3] & 0x80, 0);
	}
	f0 = section("software style 0 (16-bit)", f0);

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
