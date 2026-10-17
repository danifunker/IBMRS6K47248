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
#include "verilated_save.h"
#if VM_TRACE
#include "verilated_fst_c.h"
#endif

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
static std::vector<uint64_t> ddr(4u << 17, 0);         // DDR3 from 3000_0000: the S3's VRAM (4 MB reserved)
static const uint32_t DDR_BASE = 0x06000000;            // in 64-bit words (IBMRS6K7248_s3video)

static uint32_t rd32(uint32_t a) {
	return (uint32_t(mem[a]) << 24) | (uint32_t(mem[a + 1]) << 16) | (uint32_t(mem[a + 2]) << 8) | mem[a + 3];
}
static void wr8(uint32_t a, uint8_t v) { mem[a] = v; }

struct StubInfo { uint64_t reads = 0, writes = 0; uint32_t first_pc = 0; uint32_t last_wdata = 0; uint32_t last_rdata = 0; };

static void usage() {
	printf("machine_tb --rom FILE [--ram MB] [--cycles N] [--instr N] [--io] [--pcs N] [--stall N]\n"
	       "  --rom FILE   the ROM image (512 KB: the flash at FFF00000, FFF80000 empty)\n"
	       "  --ram MB     installed RAM, as SIMM pairs: 8 16 24 32 48 56 64 96 112 (default 32)\n"
	       "  --planar ID  the planar ID at port 0852 (default 0xF5, a 7248-100; F0-F3 a Power Series 830/850)\n"
	       "  --watch PC   report when PC (hex) first retires (FFF10100 and 8398, main_control, always)\n"
	       "  --beat N     every N clocks, a line with the instructions retired, the PC and the last progress code (default 20,000,000; 0 none)\n"
	       "  --save FILE  snapshot the machine when --save-pc PC (hex; default 8398, main_control) first retires\n"
	       "  --restore FILE  start from a snapshot (the same build and ROM; the options given apply from there)\n"
	       "  --vram FILE  the S3's 2 MB VRAM at the end, raw (tools/vram.py draws it)\n"
	       "  --frame FILE the picture's latest whole frame, as a PPM, rewritten at each vertical sync\n"
	       "  --com1 FILE  COM1's bytes as sent, raw (tools/vt.py FILE draws the terminal's screen)\n"
	       "  --fst FILE   write a waveform (needs a make TRACE=1 build) of clocks --from N --to M\n"
	       "  --lat N      the bench memory answers N clocks after a request (default 6, about the SDRAM's)\n"
	       "  --cycles N   stop after N clocks (default 50,000,000)\n"
	       "  --instr N    stop after N instructions retired\n"
	       "  --io         print every device access as it happens\n"
	       "  --quiet-progress  do not print the firmware's progress codes (port 680) as they come\n"
	       "  --pcs N      print the first N retired PCs\n"
	       "  --stall N    stop when no new PC was retired in the last N instructions (default 2,000,000; 0 never)\n");
}

int main(int argc, char** argv) {
	setvbuf(stdout, nullptr, _IOLBF, 0);          // a run cut short still shows how far it got
	Verilated::commandArgs(argc, argv);
	const char* rom_path = nullptr;
	unsigned ram_mb = 32;
	unsigned planar_id = 0xF5;                         // a 7248-100
	std::vector<uint32_t> extra_watch;
	// the SIMM pairs for each size (3 bits a pair, pair 0 lowest: 1 8 MB, 2 16, 3 32, 4 64)
	static const struct { unsigned mb, cfg; } simm_sets[] = {
		{8, 1}, {16, 2}, {24, 2 | 1 << 3}, {32, 3}, {48, 3 | 2 << 3}, {56, 3 | 2 << 3 | 1 << 6},
		{64, 4}, {96, 4 | 3 << 3}, {112, 4 | 3 << 3 | 2 << 6}};
	uint64_t max_cycles = 50000000, max_instr = 0, stall_lim = 2000000;
	bool io_print = false, post_print = true;
	uint64_t pcs_print = 0;
	uint64_t beat = 20000000;
	int lat = 6;                                   // the bench memory's answer, in clocks after the request
	const char* save_path = nullptr;               // a snapshot of the machine (model and memory) ...
	uint32_t save_pc = 0x00008398;                 // ... when this PC first retires (default main_control)
	const char* restore_path = nullptr;            // start from a snapshot instead of from reset
	const char* vram_path = nullptr;               // the S3's VRAM at the end, raw
	const char* frame_path = nullptr;              // the latest whole frame of the picture (PPM)
	const char* com1_path = nullptr;               // COM1's bytes as sent (tools/vt.py draws the screen)
	const char* fst_path = nullptr;                // a waveform (a TRACE=1 build) ...
	uint64_t fst_from = 0, fst_to = ~0ull;         // ... of these clocks                      // a heartbeat line every so many clocks (0 none)
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { if (i + 1 >= argc) { usage(); exit(2); } return argv[++i]; };
		if (a == "--rom") rom_path = next();
		else if (a == "--ram") ram_mb = strtoul(next(), nullptr, 0);
		else if (a == "--planar") planar_id = strtoul(next(), nullptr, 0);
		else if (a == "--watch") extra_watch.push_back(strtoul(next(), nullptr, 16));
		else if (a == "--cycles") max_cycles = strtoull(next(), nullptr, 0);
		else if (a == "--instr") max_instr = strtoull(next(), nullptr, 0);
		else if (a == "--io") io_print = true;
		else if (a == "--quiet-progress") post_print = false;
		else if (a == "--com1") com1_path = next();
		else if (a == "--vram") vram_path = next();
		else if (a == "--frame") frame_path = next();
		else if (a == "--save") save_path = next();
		else if (a == "--save-pc") save_pc = strtoul(next(), nullptr, 16);
		else if (a == "--restore") restore_path = next();
		else if (a == "--fst") fst_path = next();
		else if (a == "--from") fst_from = strtoull(next(), nullptr, 0);
		else if (a == "--to") fst_to = strtoull(next(), nullptr, 0);
		else if (a == "--lat") lat = atoi(next());
		else if (a == "--beat") beat = strtoull(next(), nullptr, 0);
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

	FILE* com1_raw = com1_path ? fopen(com1_path, "wb") : nullptr;
	auto* top = new VIBMRS6K7248_system;
	top->reset_pc = 0xFFF00100;
	unsigned simm_cfg = ~0u;
	for (auto& e : simm_sets) if (e.mb == ram_mb) simm_cfg = e.cfg;
	if (simm_cfg == ~0u) { fprintf(stderr, "--ram %u: not a SIMM size this bench builds\n", ram_mb); return 2; }
	top->simm_cfg = simm_cfg;
	top->planar_id = planar_id;
	top->ps2_key = 0;
	top->ps2_mouse = 0;
	top->rtc_set = 0;
	// the RTC starts at 2026-10-17 12:00:00, a Saturday (hps_io's RTC: BCD seconds, minutes, hours, date, month, year; weekday 0-6 from Sunday)
	top->rtc_time = (0x00ull) | (0x00ull << 8) | (0x12ull << 16) | (0x17ull << 24) | (0x10ull << 32) | (0x26ull << 40) | (0x06ull << 48);
	top->rom_at   = ROM_AT;
	top->rom_512k = rom_len == 512u * 1024;
	top->com1_rxd = 1;
	top->com1_cts_n = 0;
	top->b_ack = 0;
	top->reset = 1;
	top->reset_b = 1;

	// the memory: a request is answered LAT clocks after it is seen
	// (--lat: its latency changes how long the machine waits, not what it does)
	int  mem_wait = -1;
	uint32_t rd_addr = 0, rd_left = 0; int rd_wait = 0;     // DDR3: the read burst being answered
	std::vector<uint8_t> frame(1600 * 1200 * 3, 0);        // the picture
	uint32_t fx = 0, fy = 0, fw = 0, fh = 0; uint64_t frames = 0;
	bool was_de = false, was_vs = false;
	bool ack_now = false;

	std::map<uint32_t, StubInfo> stubs;
	uint64_t instr = 0, cycle = 0, since_new = 0;
	uint32_t last_pc = 0;
	std::map<uint32_t, uint64_t> seen_pc;              // for the stall test: PCs retired lately
	uint32_t lcr = 0;
	std::string line;
	uint64_t io_count = 0;
	struct Watch { uint32_t pc; std::string name; bool hit; };
	std::vector<Watch> watch = {
		{0xFFF10100, "the main block's reset vector", false},
		{0x00008398, "main_control", false},
	};
	for (auto& w : extra_watch) watch.push_back({w, "--watch", false});
	unsigned post_last = 0;
	uint64_t post_count = 0;

#if VM_TRACE
	VerilatedFstC* tfp = nullptr;
	if (fst_path) {
		Verilated::traceEverOn(true);
		tfp = new VerilatedFstC;
		top->trace(tfp, 99);
		tfp->open(fst_path);
	}
#else
	if (fst_path) { fprintf(stderr, "--fst needs a make TRACE=1 build\n"); return 2; }
#endif
	uint64_t tcycle = 0;
	auto tick = [&]() {
		top->clk = 0; top->clk_b = 0; top->eval();
#if VM_TRACE
		if (tfp && tcycle >= fst_from && tcycle <= fst_to) tfp->dump(2 * tcycle);
#endif
		top->clk = 1; top->clk_b = 1; top->eval();
#if VM_TRACE
		if (tfp && tcycle >= fst_from && tcycle <= fst_to) tfp->dump(2 * tcycle + 1);
#endif
		tcycle++;
	};

	// the bench's own state that a snapshot carries beside the model's
	auto snap = [&](auto& f) {
		f(&cycle, sizeof cycle); f(&instr, sizeof instr); f(&last_pc, sizeof last_pc); f(&lcr, sizeof lcr);
		f(&post_last, sizeof post_last); f(&post_count, sizeof post_count); f(&io_count, sizeof io_count);
		f(&mem_wait, sizeof mem_wait); f(&ack_now, sizeof ack_now); f(&tcycle, sizeof tcycle);
		f(mem.data(), mem.size());
		f(ddr.data(), ddr.size() * 8);
	};
	uint64_t cycle0 = 0;
	if (restore_path) {
		VerilatedRestore is;
		is.open(restore_path);
		if (!is.isOpen()) { perror(restore_path); return 1; }
		is >> *top;
		auto rd = [&](void* p, size_t n) { is.read(p, n); };
		snap(rd);
		is.close();
		cycle0 = cycle + 1;
		printf("restored %s: clock %llu, %llu instructions, pc %08X\n", restore_path,
		       (unsigned long long)cycle, (unsigned long long)instr, last_pc);
	}
	else {
		top->rtc_set = 1;
		for (int i = 0; i < 20; i++) tick();
		top->rtc_set = 0;
		top->reset = 0;
		top->reset_b = 0;
	}
	bool saved = false;

	const char* why = "cycle limit";
	for (cycle = cycle0; cycle < max_cycles; cycle++) {
		// the memory side, before the edge: set ack/rdata for this edge
		if (ack_now) { top->b_ack = 0; ack_now = false; }
		else if (top->b_req) {
			if (mem_wait < 0) mem_wait = lat;
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
		// DDR3 (the S3's VRAM): a read burst answered a beat a clock after 4 clocks; writes at once
		top->ddr_busy = 0;
		top->ddr_dout_ready = 0;
		if (rd_left && rd_wait == 0) {
			uint32_t w = rd_addr - DDR_BASE;
			top->ddr_dout = (w < ddr.size()) ? ddr[w] : ~0ull;
			top->ddr_dout_ready = 1;
			rd_addr++; rd_left--;
		}
		else if (rd_left) rd_wait--;
		tick();
		if (top->ddr_rd && !rd_left) { rd_addr = top->ddr_addr; rd_left = top->ddr_burstcnt; rd_wait = 4; }
		if (top->ddr_we) {
			uint32_t w = uint32_t(top->ddr_addr) - DDR_BASE;
			if (w < ddr.size())
				for (int b = 0; b < 8; b++)
					if (top->ddr_be & (1 << b)) ddr[w] = (ddr[w] & ~(0xFFull << (8 * b))) | (uint64_t(top->ddr_din) & (0xFFull << (8 * b)));
		}
		// the picture: the visible pixels into a frame, saved at each vertical sync
		if (top->vid_ce) {
			bool de = !top->vid_hblank && !top->vid_vblank;
			if (de) {
				if (fy < 1200 && fx < 1600) {
					uint8_t* px = &frame[(fy * 1600 + fx) * 3];
					px[0] = top->vid_r; px[1] = top->vid_g; px[2] = top->vid_b;
				}
				fx++;
				if (fx > fw) fw = fx;
			}
			else if (was_de) { fx = 0; fy++; if (fy > fh) fh = fy; }
			was_de = de;
			if (top->vid_vs && !was_vs) {
				if (frame_path && fw && fh) {
					FILE* ff = fopen(frame_path, "wb");
					if (ff) {
						fprintf(ff, "P6\n%u %u\n255\n", fw, fh);
						for (uint32_t y = 0; y < fh; y++) fwrite(&frame[y * 1600 * 3], 1, fw * 3, ff);
						fclose(ff);
					}
				}
				frames++;
				fx = fy = fw = fh = 0;
			}
			was_vs = top->vid_vs;
		}
		if (beat && cycle && cycle % beat == 0)
			printf("  [clock %llu: %llu instructions, pc %08X, progress %02X]\n", (unsigned long long)cycle,
			       (unsigned long long)instr, last_pc, post_last);

		if (top->trace_valid && top->trace_last) {
			uint32_t pc = top->trace_pc;
			if (save_path && !saved && pc == save_pc) {
				last_pc = pc;
				instr++;
				VerilatedSave os;
				os.open(save_path);
				os << *top;
				auto wr = [&](void* p, size_t n) { os.write(p, n); };
				snap(wr);
				os.close();
				instr--;
				saved = true;
				printf("  saved %s at pc %08X, clock %llu\n", save_path, pc, (unsigned long long)cycle);
			}
			for (auto& w : watch)
				if (!w.hit && pc == w.pc) {
					w.hit = true;
					printf("  reached %08X (%s) at instr %llu, clock %llu\n", pc, w.name.c_str(),
					       (unsigned long long)instr, (unsigned long long)cycle);
				}
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
				if (com1_raw) { fputc(c, com1_raw); fflush(com1_raw); }
				if (c == '\n' || line.size() > 200) { printf("COM1| %s\n", line.c_str()); line.clear(); }
				else if (c != '\r') line += (c >= 32 && c < 127) ? c : '.';
			}
			if (we && (a & ~3u) == 0x800003F8 && (be & 1)) lcr = top->io_wdata & 0xFF;   // 3FB
			// the firmware's progress codes: every step writes a little-endian word 000x00nn to
			// 680 (the assembly also writes nn to 8C0, the C code only to 680)
			if (we && a == 0x80000680 && be == 0xF) {
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
	if (vram_path) {
		FILE* vf = fopen(vram_path, "wb");
		if (vf) {
			// in VRAM's byte order: byte a in DDR3 word a >> 3, lane a & 7
			for (uint32_t a = 0; a < (2u << 20); a++) fputc(int(ddr[a >> 3] >> (8 * (a & 7))) & 0xFF, vf);
			fclose(vf);
		}
	}
	printf("%llu frames of the picture\n", (unsigned long long)frames);
#if VM_TRACE
	if (tfp) tfp->close();
#endif
	delete top;
	return 0;
}
