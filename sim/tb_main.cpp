// IBMRS6K7248 - the machine bench
//
// Runs IBMRS6K7248_system (the CPU, the machine, the clock crossing) from the
// reset vector on a ROM image, with a plain memory answering the crossing's
// far side as the SDRAM would (by SDRAM offset, the ROM in the top 4 MB of a
// 128 MB board). Reports:
//   - COM1's output (the bytes written to 0x800003F8 with DLAB clear), as text
//   - every device access in order (--io), and a summary of the stubbed ones
//     by address, with the PC that made each first
//   - where the CPU is at the end, and the loop it is in when it stops moving
//
// One clock drives both sides of the crossing (both are 100 MHz on the board).

#include "VIBMRS6K7248_system.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static const uint32_t MEM_BYTES = 128u << 20;
static const uint32_t ROM_AT    = 31;                 // 4 MB units: the top 4 MB of 128
static std::vector<uint8_t> mem(MEM_BYTES, 0);

static uint32_t rd32(uint32_t a) {
	return (uint32_t(mem[a]) << 24) | (uint32_t(mem[a + 1]) << 16) | (uint32_t(mem[a + 2]) << 8) | mem[a + 3];
}
static void wr8(uint32_t a, uint8_t v) { mem[a] = v; }

struct StubInfo { uint64_t reads = 0, writes = 0; uint32_t first_pc = 0; uint32_t last_wdata = 0; uint32_t last_rdata = 0; };

static void usage() {
	printf("machine_tb --rom FILE [--ram MB] [--cycles N] [--instr N] [--io] [--pcs N] [--stall N]\n"
	       "  --rom FILE   the ROM image (512 KB: the flash at FFF00000, FFF80000 empty)\n"
	       "  --ram MB     installed RAM (default 32)\n"
	       "  --cycles N   stop after N clocks (default 50,000,000)\n"
	       "  --instr N    stop after N instructions retired\n"
	       "  --io         print every device access as it happens\n"
	       "  --quiet-progress  do not print the firmware's progress codes (port 8C0) as they come\n"
	       "  --pcs N      print the first N retired PCs\n"
	       "  --stall N    stop when no new PC was retired in the last N instructions (default 2,000,000; 0 never)\n");
}

int main(int argc, char** argv) {
	Verilated::commandArgs(argc, argv);
	const char* rom_path = nullptr;
	unsigned ram_mb = 32;
	uint64_t max_cycles = 50000000, max_instr = 0, stall_lim = 2000000;
	bool io_print = false, post_print = true;
	uint64_t pcs_print = 0;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { if (i + 1 >= argc) { usage(); exit(2); } return argv[++i]; };
		if (a == "--rom") rom_path = next();
		else if (a == "--ram") ram_mb = strtoul(next(), nullptr, 0);
		else if (a == "--cycles") max_cycles = strtoull(next(), nullptr, 0);
		else if (a == "--instr") max_instr = strtoull(next(), nullptr, 0);
		else if (a == "--io") io_print = true;
		else if (a == "--quiet-progress") post_print = false;
		else if (a == "--pcs") pcs_print = strtoull(next(), nullptr, 0);
		else if (a == "--stall") stall_lim = strtoull(next(), nullptr, 0);
		else { usage(); return 2; }
	}
	if (!rom_path) { usage(); return 2; }
	FILE* f = fopen(rom_path, "rb");
	if (!f) { perror(rom_path); return 1; }
	std::vector<uint8_t> rom(4u << 20);
	size_t rom_len = fread(rom.data(), 1, rom.size(), f);
	fclose(f);
	if (rom_len != 512u * 1024 && rom_len != 1024u * 1024) {
		fprintf(stderr, "ROM is %zu bytes; expected 512 KB or 1 MB\n", rom_len);
		return 1;
	}
	memcpy(&mem[ROM_AT << 22], rom.data(), rom_len);
	printf("ROM %s, %zu KB; RAM %u MB; reset vector word %08X\n", rom_path, rom_len >> 10, ram_mb,
	       rd32((ROM_AT << 22) + 0x100));

	auto* top = new VIBMRS6K7248_system;
	top->reset_pc = 0xFFF00100;
	top->ram_mb   = ram_mb;
	top->rom_at   = ROM_AT;
	top->rom_512k = rom_len == 512u * 1024;
	top->com1_rxd = 1;
	top->com1_cts_n = 0;
	top->b_ack = 0;
	top->reset = 1;
	top->reset_b = 1;

	// the memory: a request is answered LAT clocks after it is seen
	const int LAT = 6;
	int  mem_wait = -1;
	bool ack_now = false;

	std::map<uint32_t, StubInfo> stubs;
	uint64_t instr = 0, cycle = 0, since_new = 0;
	uint32_t last_pc = 0;
	std::map<uint32_t, uint64_t> seen_pc;              // for the stall test: PCs retired lately
	uint32_t lcr = 0;
	std::string line;
	uint64_t io_count = 0;
	unsigned post_last = 0;
	uint64_t post_count = 0;

	auto tick = [&]() {
		top->clk = 0; top->clk_b = 0; top->eval();
		top->clk = 1; top->clk_b = 1; top->eval();
	};

	for (int i = 0; i < 20; i++) tick();
	top->reset = 0;
	top->reset_b = 0;

	const char* why = "cycle limit";
	for (cycle = 0; cycle < max_cycles; cycle++) {
		// the memory side, before the edge: set ack/rdata for this edge
		if (ack_now) { top->b_ack = 0; ack_now = false; }
		else if (top->b_req) {
			if (mem_wait < 0) mem_wait = LAT;
			else if (mem_wait == 0) {
				uint32_t a = uint32_t(top->b_addr) << 2;
				if (a >= MEM_BYTES) a &= MEM_BYTES - 1;
				if (top->b_line) {
					a &= ~31u;
					for (int w = 0; w < 8; w++) {
						if (top->b_we) {
							uint32_t v = top->b_wdata[7 - w];
							for (int b = 0; b < 4; b++) wr8(a + 4 * w + b, v >> (24 - 8 * b));
						} else top->b_rdata[7 - w] = rd32(a + 4 * w);
					}
				} else {
					if (top->b_we) {
						uint32_t v = top->b_wdata[0];
						for (int b = 0; b < 4; b++) if (top->b_be & (8 >> b)) wr8(a + b, v >> (24 - 8 * b));
					} else {
						for (int w = 0; w < 8; w++) top->b_rdata[w] = 0;
						top->b_rdata[0] = rd32(a);
					}
				}
				top->b_ack = 1;
				ack_now = true;
				mem_wait = -1;
			} else mem_wait--;
		}
		tick();

		if (top->trace_valid && top->trace_last) {
			uint32_t pc = top->trace_pc;
			if (instr < pcs_print) printf("  pc %08X  %08X  msr %08X\n", pc, top->trace_insn, top->trace_msr);
			instr++;
			last_pc = pc;
			if (seen_pc.emplace(pc, instr).second) since_new = 0;
			else since_new++;
			if (max_instr && instr >= max_instr) { why = "instruction limit"; break; }
			if (stall_lim && since_new >= stall_lim) { why = "no new code for the stall limit"; break; }
		}
		if (top->io_ev) {
			io_count++;
			uint32_t a = top->io_addr;
			uint8_t be = top->io_be;
			bool we = top->io_we;
			if (io_print)
				printf("  io %s %08X be %X %08X%s  (pc %08X)\n", we ? "W" : "R", a, be,
				       we ? uint32_t(top->io_wdata) : uint32_t(top->io_rdata), top->io_stub ? "  stub" : "", last_pc);
			// COM1: the byte written to THR, LCR followed for DLAB
			if (we && (a & ~3u) == 0x800003F8 && (be & 8) && !(lcr & 0x80)) {
				char c = char(top->io_wdata >> 24);
				if (c == '\n' || line.size() > 200) { printf("COM1| %s\n", line.c_str()); line.clear(); }
				else if (c != '\r') line += (c >= 32 && c < 127) ? c : '.';
			}
			if (we && (a & ~3u) == 0x800003F8 && (be & 1)) lcr = top->io_wdata & 0xFF;   // 3FB
			// the firmware's progress codes: each step writes its code to 8C0 (and 3BC, 680)
			if (we && a == 0x800008C0 && (be & 8)) {
				unsigned code = (top->io_wdata >> 24) & 0xFF;
				if (post_print) printf("  progress %02X  (pc %08X, instr %llu)\n", code, last_pc, (unsigned long long)instr);
				post_last = code;
				post_count++;
			}
			if (top->io_stub) {
				// the byte address of the first enabled lane
				uint32_t ba = a;
				for (int b = 0; b < 4; b++) if (be & (8 >> b)) { ba = a + b; break; }
				auto& s = stubs[ba];
				if (s.reads + s.writes == 0) s.first_pc = last_pc;
				if (we) { s.writes++; s.last_wdata = top->io_wdata; } else { s.reads++; s.last_rdata = top->io_rdata; }
			}
		}
	}
	if (!line.empty()) printf("COM1| %s\n", line.c_str());

	printf("\nstopped: %s after %llu clocks, %llu instructions retired (%.2f clocks each), %llu device accesses\n",
	       why, (unsigned long long)cycle, (unsigned long long)instr, instr ? double(cycle) / instr : 0.0,
	       (unsigned long long)io_count);
	printf("last PC %08X; %llu progress codes, the last %02X\n", last_pc, (unsigned long long)post_count, post_last);
	// the loop it is in: the PCs retired in the last stretch, by address
	if (since_new > 1000) {
		std::vector<uint32_t> recent;
		for (auto& [pc, first] : seen_pc) if (instr - first > 0) recent.push_back(pc);
		printf("(no new PC in the last %llu instructions)\n", (unsigned long long)since_new);
	}
	printf("\nstubbed device addresses (%zu):\n", stubs.size());
	printf("  %-10s %10s %10s  %-8s  %-8s  %s\n", "address", "reads", "writes", "last w", "read", "first PC");
	for (auto& [a, s] : stubs)
		printf("  %08X   %10llu %10llu  %08X  %08X  %08X\n", a, (unsigned long long)s.reads,
		       (unsigned long long)s.writes, s.last_wdata, s.last_rdata, s.first_pc);
	delete top;
	return 0;
}
