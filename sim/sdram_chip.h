// The SDRAM board as a behavioural model, from MacPPC7300's SDRAM bench
// (Scratch/mutsdram/verilator/sdram_main.cpp, 2026-10-15): two ranks of
// 4 banks x 8192 rows x 1024 columns x 16 bits (128 MB), the commands checked
// against an AS4C32M16SB-6's sequence and timings, every protocol error
// counted (sdram_chip::errors) and the first ones printed. See that file's header.
#pragma once
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace sdram_chip {

uint32_t SIZE = 128u << 20;                  // the board
uint32_t UP_BASE = SIZE - (4u << 20);        // where the ROM goes
int RANKS = 2, COLS = 1024;

// timings in ns (AS4C32M16SB-6: tRCD = tRP = 18; the -7 grade's 21 ns would
// need three clocks at 100 MHz where sdram.sv has run two on hardware)
const double T_RCD = 18, T_RP = 18, T_RAS = 42, T_RC = 60, T_RFC = 60, T_RRD = 12, T_WR = 12;
const double T_REFI = 7812.5, T_POWERUP = 100000;
const int CL = 2;

int errors = 0, show = 10;
void fail(long cyc, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void fail(long cyc, const char* fmt, ...) {
	if (errors++ < show) {
		std::printf("SDRAM clock %ld: ", cyc);
		va_list ap;
		va_start(ap, fmt);
		std::vprintf(fmt, ap);
		va_end(ap);
		std::printf("\n");
	}
}

uint8_t init_byte(uint32_t a) { return (uint8_t)((a * 2654435761u) >> 24); }

struct Chip {
	double tck;                                   // SDRAM clock period, ns
	std::vector<uint16_t> mem;                    // [rank][bank][row][col]
	struct Bank { bool open = false; int row = 0; long t_act = -1000000, t_pre = -1000000, t_wr = -1000000; };
	struct Rank {
		Bank b[4];
		int stage = 0;                            // 0 none, 1 precharged, 2-3 refreshes, 4 mode set
		long t_ref = -1000000, t_mode = -1000000, t_act = -1000000;
		long refreshes = 0, ready_at = -1;
	} rk[2];
	// read data on the bus: per SDRAM clock, the halfword index or -1
	struct Beat { long cyc; int rank; uint32_t index; };
	std::vector<Beat> beats;                      // pending, in order
	int dqm_hist[3] = {0, 0, 0};                  // DQM of the last three clocks
	long first_cmd = -1;
	int max_owed = 0;

	explicit Chip(double tck_ns) : tck(tck_ns), mem(SIZE / 2) {
		for (uint32_t i = 0; i < SIZE / 2; i++) {
			// the same contents the bench's copy starts with, by byte offset
			uint32_t off = offset_of(i);
			mem[i] = (uint16_t)(init_byte(off) << 8 | init_byte(off + 1));
		}
	}
	static uint32_t index(int rank, int bank, int row, int col) {
		return (((uint32_t)rank * 4 + bank) * 8192 + row) * COLS + col;
	}
	// the controller's documented map: rank off[26], column bit 9 off[25],
	// bank off[24:23], row off[22:10], columns 8-0 off[9:1]
	static uint32_t offset_of(uint32_t idx) {
		uint32_t col = idx % COLS, rest = idx / COLS;
		uint32_t row = rest & 8191, bank = (rest >> 13) & 3, rank = rest >> 15;
		return rank << 26 | (col >> 9) << 25 | bank << 23 | row << 10 | (col & 511) << 1;
	}
	bool met(long since, double ns, long now) const { return (now - since) * tck >= ns - 1e-6; }

	// one SDRAM clock: the command on the pins, and the bus for the next half
	void edge(long n, bool ncs, bool nras, bool ncas, bool nwe, int ba, int a, int dqm,
	          bool fpga_drives, uint16_t fpga_dq, bool& drive, uint16_t& dq) {
		int r = ncs ? 1 : 0;                      // the board inverts nCS for rank 1
		int cmd = (nras << 2) | (ncas << 1) | nwe;
		if (r >= RANKS) cmd = 7;                  // a one-chip board: nCS high deselects it
		Rank& R = rk[r];
		dqm_hist[2] = dqm_hist[1]; dqm_hist[1] = dqm_hist[0]; dqm_hist[0] = dqm;
		if (cmd != 7) {
			if (first_cmd < 0) {
				first_cmd = n;
				if (n * tck < T_POWERUP) fail(n, "first command after %.1f us, before 100 us of NOPs", n * tck / 1000);
			}
			if (cmd != 2 && cmd != 1 && cmd != 0 && R.stage < 4) fail(n, "rank %d: command %d before its mode register is set", r, cmd);
			if (R.stage == 4 && !met(R.t_mode, 2 * tck, n)) fail(n, "rank %d: command within tMRD of LOAD MODE", r);
			if (!met(R.t_ref, T_RFC, n)) fail(n, "rank %d: command %d within tRFC of a refresh", r, cmd);
		}
		switch (cmd) {
		case 3: {                                  // ACTIVE
			Bank& B = R.b[ba];
			if (B.open) fail(n, "rank %d bank %d: ACTIVE on an open bank", r, ba);
			if (!met(B.t_pre, T_RP, n)) fail(n, "rank %d bank %d: ACTIVE %ld clocks after PRECHARGE (tRP)", r, ba, n - B.t_pre);
			if (!met(B.t_act, T_RC, n)) fail(n, "rank %d bank %d: ACTIVE %ld clocks after ACTIVE (tRC)", r, ba, n - B.t_act);
			if (!met(R.t_act, T_RRD, n)) fail(n, "rank %d: ACTIVE within tRRD of another", r);
			B.open = true; B.row = a & 8191; B.t_act = n; R.t_act = n;
			break;
		}
		case 5: case 4: {                          // READ, WRITE
			Bank& B = R.b[ba];
			int col = a & (COLS - 1);
			if (a & 0x400) fail(n, "auto-precharge requested (A10) on a %s", cmd == 5 ? "READ" : "WRITE");
			if (!B.open) { fail(n, "rank %d bank %d: %s on a closed bank", r, ba, cmd == 5 ? "READ" : "WRITE"); break; }
			if (!met(B.t_act, T_RCD, n)) fail(n, "rank %d bank %d: %s %ld clocks after ACTIVE (tRCD)", r, ba, cmd == 5 ? "READ" : "WRITE", n - B.t_act);
			// a new command ends a read burst still on the bus
			while (!beats.empty() && beats.back().cyc > n + (cmd == 5 ? CL - 1 : -1)) {
				if (cmd == 4 && beats.back().cyc <= n) fail(n, "WRITE while read data is on the bus");
				beats.pop_back();
			}
			if (cmd == 5) {
				for (int k = 0; k < 8; k++) {      // burst of 8, sequential, wrapping in the aligned block
					int c = (col & ~7) | ((col + k) & 7);
					beats.push_back({n + CL + k, r, index(r, ba, B.row, c)});
				}
			} else {
				if (!fpga_drives) fail(n, "WRITE without the data bus driven");
				uint16_t& w = mem[index(r, ba, B.row, col)];
				if (!(dqm & 2)) w = (uint16_t)((w & 0x00FF) | (fpga_dq & 0xFF00));
				if (!(dqm & 1)) w = (uint16_t)((w & 0xFF00) | (fpga_dq & 0x00FF));
				B.t_wr = n;
			}
			break;
		}
		case 2: {                                  // PRECHARGE
			for (int b = 0; b < 4; b++) {
				if (!(a & 0x400) && b != ba) continue;
				Bank& B = R.b[b];
				if (B.open && !met(B.t_act, T_RAS, n)) fail(n, "rank %d bank %d: PRECHARGE %ld clocks after ACTIVE (tRAS)", r, b, n - B.t_act);
				if (B.open && !met(B.t_wr, T_WR, n) ) fail(n, "rank %d bank %d: PRECHARGE within tWR of a write", r, b);
				if (B.open || (a & 0x400)) B.t_pre = n;
				B.open = false;
			}
			for (const Beat& bt : beats) if (bt.rank == r && bt.cyc > n) fail(n, "PRECHARGE during a read burst");
			if ((a & 0x400) && R.stage == 0) R.stage = 1;
			break;
		}
		case 1: {                                  // AUTO REFRESH
			for (int b = 0; b < 4; b++) {
				if (R.b[b].open) fail(n, "rank %d: refresh with bank %d open", r, b);
				if (!met(R.b[b].t_pre, T_RP, n)) fail(n, "rank %d: refresh within tRP of a precharge", r);
			}
			if (R.stage >= 1 && R.stage < 3) R.stage++;
			R.t_ref = n;
			R.refreshes++;
			break;
		}
		case 0: {                                  // LOAD MODE
			for (int b = 0; b < 4; b++) if (R.b[b].open) fail(n, "rank %d: LOAD MODE with a bank open", r);
			if (R.stage != 3) fail(n, "rank %d: LOAD MODE before PRECHARGE ALL and two refreshes", r);
			if ((a & 0x1FFF) != 0x223) fail(n, "rank %d: mode %03X, expected 223 (burst 8, sequential, CAS 2, single writes)", r, a & 0x1FFF);
			R.stage = 4; R.t_mode = n; R.ready_at = n;
			break;
		}
		default: break;
		}
		// refresh debt, once the rank is set up
		for (int k = 0; k < 2; k++) {
			if (rk[k].ready_at < 0) continue;
			long owed = (long)((n - rk[k].ready_at) * tck / T_REFI) - rk[k].refreshes + 2;
			if (owed > max_owed) max_owed = (int)owed;
			if (owed > 8) { fail(n, "rank %d owes %ld refreshes", k, owed); rk[k].ready_at = n; rk[k].refreshes = 0; }
		}
		// the bus for the next half clock
		drive = false;
		dq = 0xDEAD;
		while (!beats.empty() && beats.front().cyc < n) beats.erase(beats.begin());
		if (!beats.empty() && beats.front().cyc == n) {
			if (dqm_hist[2] != 0) fail(n, "a read beat masked by DQM");
			drive = true;
			dq = mem[beats.front().index];
		}
	}
};

} // namespace sdram_chip
