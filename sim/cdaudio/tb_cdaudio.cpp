// IBMRS6K7248 - the CD player's bench (IBMRS6K7248_scsitgt with IBMRS6K7248_CDAUDIO, CLK_HZ 2 MHz): the
// initiator's side of the byte-level bus, the Main's side of the CD slot (the track table at C000_0000, the
// audio window at 8000_0000 + 5 x frame); READ TOC, PLAY AUDIO MSF and (10), the samples played,
// READ SUB-CHANNEL while playing, PAUSE/RESUME, MODE SELECT page 0E's volume, a play to its end
// (completed, then no status), STOP, and a disk read while a frame's fetch is in flight. ./run.sh.

#include "VIBMRS6K7248_scsitgt.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static VIBMRS6K7248_scsitgt *t;
static int fails;
static uint64_t cyc;
static std::vector<std::pair<int16_t, int16_t>> out;
static int16_t last_l, last_r;
static bool track_out;
static int audio_reqs;

// the disc: track 1 data at 0, track 2 audio at 1000, lead-out 1100
static const uint32_t T2 = 1000, LEADOUT = 1100;
static int16_t smp_l(uint32_t f, int i) { return int16_t(f * 1200 + 2 * i); }
static int16_t smp_r(uint32_t f, int i) { return int16_t(-int(f * 1200 + 2 * i)); }

static uint8_t main_byte(uint64_t lba, int off) {
	if (lba >= 0xC0000000ull) {
		uint8_t b[1024] = {};
		auto ent = [&](int n, uint8_t ctl, uint8_t trk, uint32_t a) {
			uint8_t *e = b + 8 + 8 * n; uint32_t m = a + 150;
			e[0] = ctl; e[1] = trk; e[2] = m / 4500; e[3] = m / 75 % 60; e[4] = m % 75;
			e[5] = a >> 16; e[6] = a >> 8; e[7] = a;
		};
		if (lba == 0xC0000000ull) {
			b[0] = 1; b[1] = 2; b[2] = 3; b[3] = 1;
			ent(0, 0x14, 1, 0); ent(1, 0x10, 2, T2); ent(2, 0x10, 0xAA, LEADOUT);
		}
		return off < 1024 ? b[off] : 0;
	}
	if (lba >= 0x80000000ull) {
		uint64_t o = (lba - 0x80000000ull) * 512 + off;
		uint32_t f = o / 2560, fo = o % 2560;
		if (fo >= 2352) return 0;
		int i = fo / 4, k = fo % 4;
		uint16_t v = k < 2 ? uint16_t(smp_l(f, i)) : uint16_t(smp_r(f, i));
		return (k & 1) ? v >> 8 : v & 0xFF;
	}
	return uint8_t(lba * 7 + off);
}

// hps_io: a request on any slot answered after a turnaround, a byte a clock
static int h_state, h_slot, h_wait, h_n, h_i;
static uint64_t h_lba;
static void hps() {
	t->sd_buff_wr = 0;
	switch (h_state) {
	case 0:
		for (int s = 0; s < 3; s++) if ((t->sd_rd >> s) & 1) {
			h_slot = s; h_lba = t->sd_lba[s]; h_n = (t->sd_blk_cnt[s] + 1) * 512; h_i = 0;
			h_wait = 300; h_state = 1;
			if (s == 2 && h_lba >= 0x80000000ull && h_lba < 0xC0000000ull) audio_reqs++;
			break;
		}
		break;
	case 1: if (--h_wait == 0) { t->sd_ack = 1 << h_slot; h_state = 2; } break;
	case 2:
		if (h_i < h_n) {
			t->sd_buff_addr = h_i; t->sd_buff_dout = main_byte(h_lba + h_i / 512, h_i % 512); t->sd_buff_wr = 1; h_i++;
		} else { t->sd_ack = 0; h_state = 3; h_wait = 4; }
		break;
	case 3: if (--h_wait == 0) h_state = 0; break;
	}
}

static void tick() {
	hps();
	t->clk = 0; t->clk_h = 0; t->eval(); t->clk = 1; t->clk_h = 1; t->eval(); cyc++;
	if (track_out && (int16_t(t->cd_l) != last_l || int16_t(t->cd_r) != last_r)) {
		last_l = t->cd_l; last_r = t->cd_r;
		out.push_back({last_l, last_r});
	}
}
static void run(int n) { for (int i = 0; i < n; i++) tick(); }

// the initiator: select (no ATN), the CDB, data out, data in, status, message in
static int cmd(int id, std::vector<uint8_t> cdb, std::vector<uint8_t> *din = nullptr, std::vector<uint8_t> dout = {}) {
	t->sel_id = id; t->sel = 1; tick(); t->sel = 0;
	for (int i = 0; i < 20 && !t->sel_done && !t->sel_fail; i++) tick();
	if (!t->bsy) { printf("  no selection\n"); fails++; return -1; }
	size_t ci = 0, oi = 0; int status = -1;
	for (int n = 0; n < 2000000 && t->bsy; n++) {
		if (t->req && !t->ack) {
			int ph = t->phase;
			if (ph == 2) t->idata = ci < cdb.size() ? cdb[ci++] : 0;
			else if (ph == 0) t->idata = oi < dout.size() ? dout[oi++] : 0;
			else if (ph == 1) { if (din) din->push_back(t->tdata); }
			else if (ph == 3) status = t->tdata;
			t->ack = 1;
		} else if (!t->req) t->ack = 0;
		tick();
	}
	t->ack = 0; tick();
	return status;
}
static void expect(const char *what, long got, long want) {
	if (got != want) { printf("  %s: %lX, want %lX\n", what, got, want); fails++; }
}
static void report(const char *what, int f0) { printf("%-52s %s\n", what, fails != f0 ? "FAIL" : "pass"); }

static std::vector<uint8_t> subchan(bool msf) {
	std::vector<uint8_t> d;
	cmd(3, {0x42, uint8_t(msf ? 2 : 0), 0x40, 1, 0, 0, 0, 0, 16, 0}, &d);
	return d;
}
static uint32_t msf_of(uint32_t lba) { uint32_t a = lba + 150; return (a / 4500) << 16 | (a / 75 % 60) << 8 | a % 75; }

// the samples of frames [f0, f1) as played, in order
static void check_samples(const char *what, uint32_t f0, uint32_t f1, int vreg) {
	int vol = vreg + (vreg >> 7);                          // the port volume as the player scales: 255 is unity
	int bad = 0; size_t k = 0;
	while (k < out.size() && out[k].first == 0 && out[k].second == 0) k++;
	for (uint32_t f = f0; f < f1; f++) for (int i = 0; i < 588; i++, k++) {
		int16_t wl = int16_t((int32_t(smp_l(f, i)) * vol) >> 8), wr = int16_t((int32_t(smp_r(f, i)) * vol) >> 8);
		if (k >= out.size() || out[k].first != wl || out[k].second != wr) {
			if (bad++ < 3) printf("  %s: sample %zu (frame %u, %d): %d %d, want %d %d\n", what, k, f, i,
				k < out.size() ? out[k].first : -1, k < out.size() ? out[k].second : -1, wl, wr);
		}
	}
	if (bad) fails++;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new VIBMRS6K7248_scsitgt;
	t->img_present = 7;
	t->img_blocks[0] = 100000; t->img_blocks[1] = 100000; t->img_blocks[2] = LEADOUT * 4;
	t->rst = 1; run(5); t->rst = 0; run(5);
	int f0;

	// READ TOC: the table from the Main
	f0 = fails;
	{
		std::vector<uint8_t> d;
		expect("READ TOC status", cmd(3, {0x43, 0, 0, 0, 0, 0, 0, 0, 100, 0}, &d), 0);
		expect("TOC length", d.size(), 4 + 3 * 8);
		if (d.size() >= 28) {
			expect("first, last", d[2] << 8 | d[3], 0x0102);
			expect("track 2 ctl", d[4 + 8 + 1], 0x10);
			expect("track 2 lba", d[4 + 8 + 6] << 8 | d[4 + 8 + 7], T2);
			expect("lead-out", d[4 + 16 + 2], 0xAA);
		}
	}
	report("READ TOC from the Main's table", f0);

	// nothing playing: no audio status
	f0 = fails;
	{ auto d = subchan(false); expect("status idle", d.size() > 1 ? d[1] : -1, 0x15); }
	report("READ SUB-CHANNEL idle: no audio status", f0);

	// PLAY AUDIO MSF, track 2's first three frames; the samples, the position while playing
	f0 = fails;
	out.clear(); last_l = last_r = 0; track_out = true;
	{
		uint32_t s = msf_of(T2), e = msf_of(T2 + 3);
		expect("PLAY MSF", cmd(3, {0x47, 0, 0, uint8_t(s >> 16), uint8_t(s >> 8), uint8_t(s), uint8_t(e >> 16), uint8_t(e >> 8), uint8_t(e), 0}), 0);
		run(2000000 / 75 * 3 / 2);                          // a frame and a half
		auto d = subchan(true);
		expect("status playing", d.size() > 1 ? d[1] : -1, 0x11);
		if (d.size() >= 16) {
			expect("ctl", d[5], 0x10);
			expect("track", d[6], 2);
			expect("abs MSF", d[9] << 16 | d[10] << 8 | d[11], msf_of(T2 + 1));
			expect("rel MSF", d[13] << 16 | d[14] << 8 | d[15], 0x000001);
		}
		d = subchan(false);
		if (d.size() >= 16) expect("abs LBA", d[9] << 16 | d[10] << 8 | d[11], T2 + 1);
		run(2000000 / 75 * 2);
		d = subchan(false);
		expect("status completed", d.size() > 1 ? d[1] : -1, 0x13);
		d = subchan(false);
		expect("status then none", d.size() > 1 ? d[1] : -1, 0x15);
	}
	track_out = false;
	check_samples("samples", T2, T2 + 3, 255);
	report("PLAY AUDIO MSF: three frames played, Q channel, end", f0);

	// PAUSE/RESUME during PLAY AUDIO(10); MODE SELECT page 0E: half volume
	f0 = fails;
	{
		std::vector<uint8_t> ms = {0, 0, 0, 0, 0x0E, 14, 4, 0, 0, 0, 0, 0, 1, 128, 2, 128, 0, 0, 0, 0};
		expect("MODE SELECT", cmd(3, {0x15, 0x10, 0, 0, uint8_t(ms.size()), 0}, nullptr, ms), 0);
		out.clear(); last_l = last_r = 0; track_out = true;
		expect("PLAY(10)", cmd(3, {0x45, 0, 0, 0, uint8_t((T2 + 10) >> 8), uint8_t(T2 + 10), 0, 0, 2, 0}), 0);
		run(2000000 / 75 / 2);
		expect("PAUSE", cmd(3, {0x4B, 0, 0, 0, 0, 0, 0, 0, 0, 0}), 0);
		auto d = subchan(false);
		expect("status paused", d.size() > 1 ? d[1] : -1, 0x12);
		size_t n = out.size(); run(20000);
		// paused: silence (one change to 0, then nothing)
		if (out.size() > n + 1) { printf("  paused but %zu changes\n", out.size() - n); fails++; }
		expect("RESUME", cmd(3, {0x4B, 0, 0, 0, 0, 0, 0, 0, 1, 0}), 0);
		d = subchan(false);
		expect("status resumed", d.size() > 1 ? d[1] : -1, 0x11);
		run(2000000 / 75 * 2);
		d = subchan(false);
		expect("status completed", d.size() > 1 ? d[1] : -1, 0x13);
		// the samples: drop the pause's zeros
		std::vector<std::pair<int16_t, int16_t>> o;
		for (auto &p : out) if (p.first || p.second) o.push_back(p);
		// a sample can repeat across the pause (the same value twice is one change): rebuild from distinct values
		out = o;
		check_samples("samples at half volume", T2 + 10, T2 + 12, 128);
	}
	track_out = false;
	report("PLAY(10), PAUSE/RESUME, page 0E's volume", f0);

	// STOP during a play; a disk read during a play (the fetch in flight) still reads its data
	f0 = fails;
	{
		expect("PLAY(10)", cmd(3, {0x45, 0, 0, 0, uint8_t(T2 >> 8), uint8_t(T2), 0, 0, 50, 0}), 0);
		run(1000);
		std::vector<uint8_t> d;
		expect("disk READ(10)", cmd(0, {0x28, 0, 0, 0, 0x10, 0, 0, 0, 2, 0}, &d), 0);
		expect("read length", d.size(), 1024);
		int bad = 0;
		for (size_t i = 0; i < d.size(); i++) if (d[i] != main_byte(0x1000 + i / 512, i % 512)) bad++;
		expect("read bytes wrong", bad, 0);
		auto s = subchan(false);
		expect("status still playing", s.size() > 1 ? s[1] : -1, 0x11);
		expect("STOP", cmd(3, {0x4E, 0, 0, 0, 0, 0, 0, 0, 0, 0}), 0);
		s = subchan(false);
		expect("status stopped", s.size() > 1 ? s[1] : -1, 0x15);
		int r0 = audio_reqs; run(100000);
		expect("no fetches after STOP", audio_reqs - r0 <= 1, 1);
	}
	report("disk read during a play; STOP", f0);

	printf("%s (%d failure%s)\n", fails ? "FAIL" : "all pass", fails, fails == 1 ? "" : "s");
	delete t;
	return fails ? 1 : 0;
}
