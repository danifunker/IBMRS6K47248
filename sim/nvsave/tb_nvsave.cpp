// IBMRS6K7248 - a bench of the NVRAM keeper (IBMRS6K7248_nvsave) with the RTC: an SD model serving
// block device 3 as hps_io does; ./run.sh builds and runs it
#include "Vnvtb.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <cstdlib>

static Vnvtb *t;
static uint8_t file[4608];
static int fails;
static int ph;                      // the two clocks: clk_s 100 MHz, clk_c 70 MHz (steps of 1/700 us)
static int sd_state, sd_i;          // the SD model: 0 idle, 1 reading to the core, 2 writing from it
static uint32_t sd_blk;

static void step() {
	// SD model, on clk_s
	ph++;
	bool s_edge = (ph % 7) == 0, c_edge = (ph % 10) == 0;
	if (s_edge) {
		t->sd_buff_wr = 0;
		if (sd_state == 0) {
			if (t->sd_rd || t->sd_wr) { sd_blk = t->sd_lba; sd_state = t->sd_rd ? 1 : 2; sd_i = 0; t->sd_ack = 1;
				if (getenv("SDLOG")) printf("    [%d] SD %s block %u\n", ph, t->sd_rd ? "read" : "write", sd_blk); }
		} else if (sd_state == 1) {
			if (sd_i < 512) { t->sd_buff_addr = sd_i; t->sd_buff_dout = file[sd_blk * 512 + sd_i]; t->sd_buff_wr = 1; sd_i++; }
			else { t->sd_ack = 0; sd_state = 0; }
		} else {
			// an address for two clocks, the data taken at the second (the buffer's read is registered)
			if (sd_i < 1024) {
				if (sd_i & 1) file[sd_blk * 512 + (sd_i >> 1)] = t->sd_buff_din;
				t->sd_buff_addr = (sd_i + 1) >> 1;
				sd_i++;
			} else { t->sd_ack = 0; sd_state = 0; }
		}
	}
	t->clk_s = s_edge; t->clk_c = c_edge; t->eval();
	t->clk_s = 0; t->clk_c = 0; t->eval();
}
static void run(int n) { for (int i = 0; i < n; i++) step(); }
static void cpu(int port, int we, int d) {
	// one access: sel for one clk_c edge
	while ((ph + 1) % 10) step();
	t->sel = 1; t->we = we; t->port = port; t->wdata = d; step();
	t->sel = 0; t->we = 0; run(20);
}
static int nv_read(int a) { cpu(4, 1, a & 0xFF); cpu(5, 1, a >> 8); cpu(6, 0, 0); return t->rdata; }
static void nv_write(int a, int d) { cpu(4, 1, a & 0xFF); cpu(5, 1, a >> 8); cpu(6, 1, d); }
static int cmos_read(int i) { cpu(0, 1, i); cpu(1, 0, 0); return t->rdata; }
static void cmos_write(int i, int d) { cpu(0, 1, i); cpu(1, 1, d); }
static void mount() { t->img_size = sizeof file; t->img_mounted = 1; run(14); t->img_mounted = 0; }
static void expect(const char *what, int got, int want) {
	if (got != want) { printf("  %s: %02X, want %02X\n", what, got, want); fails++; }
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vnvtb;
	run(100);

	// 1. a new file (zeros): the RTC's image goes into it, with the marker
	memset(file, 0, sizeof file);
	mount(); run(400000);
	expect("new file: NVRAM byte 2 (version)", file[2], 0x01);
	expect("new file: NVRAM byte 3 (revision)", file[3], 0x04);
	expect("new file: CMOS 1A (century)", file[4096 + 128 + 0x1A], 0x19);
	expect("new file: marker I", file[4096], 'I');
	expect("new file: marker 1", file[4096 + 7], '1');
	printf("%-44s %s\n", "a new file gets the RTC's image", fails ? "FAIL" : "pass");

	// 2. the CPU writes the NVRAM and the CMOS; after the quiet time the file has them
	int f0 = fails;
	if (getenv("SDLOG")) printf("    [%d] test 2 writes\n", ph);
	nv_write(0x123, 0xA5); nv_write(0xFFF, 0x5A); cmos_write(0x40, 0x77);
	if (getenv("SDLOG")) printf("    [%d] test 2 writes done\n", ph);
	run(600000);
	expect("save: NVRAM 123", file[0x123], 0xA5);
	expect("save: NVRAM FFF", file[0xFFF], 0x5A);
	expect("save: CMOS 40", file[4096 + 128 + 0x40], 0x77);
	printf("%-44s %s\n", "the CPU's writes are saved", fails != f0 ? "FAIL" : "pass");

	// 3. a kept file mounted again: its contents come into the RTC (not CMOS 00-0D)
	f0 = fails;
	
	nv_write(0x200, 0x00);
	run(600000);                                       // (the RTC's write is saved first: 200 back to 0)
	file[0x200] = 0x3C; file[0x0] = 0x99; file[4096 + 128 + 0x50] = 0x42; file[4096 + 128 + 0x05] = 0x13;
	mount(); run(400000);
	expect("load: NVRAM 200", nv_read(0x200), 0x3C);
	expect("load: NVRAM 000", nv_read(0x000), 0x99);
	expect("load: NVRAM 123", nv_read(0x123), 0xA5);
	expect("load: CMOS 50", cmos_read(0x50), 0x42);
	expect("load: CMOS 05 (the time: not loaded)", cmos_read(0x05) == 0x13, 0);
	printf("%-44s %s\n", "a kept file loads into the RTC", fails != f0 ? "FAIL" : "pass");

	printf(fails ? "%d FAILED\n" : "ALL PASS\n", fails);
	delete t;
	return fails ? 1 : 0;
}
