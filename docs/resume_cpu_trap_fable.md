# Hand-off for a Fable session: DSPPC604 takes a phantom trap under Windows NT (little-endian)

**SUPERSEDED 2026-10-28 evening: the trap is NT's own `twi` (DbgLoadImageSymbols), the kernel is ntkrnlmp.exe at 0x80049000, the CPU is fine. See `docs/resume_nt_kernel_break.md`.**

(Written 2026-10-28 by the session that resumed `docs/resume_nt_setup.md`. Paste everything below the
line into a new session started in this repository, `C:\Temp\mistercore\IBMRS6K47248`.)

---

## The task

Find and fix the CPU bug that stops Windows NT 4.0 (PowerPC) on the IBMRS6K7248 core: the kernel takes a
**program exception with SRR1 trap bit (0x00020000) at an address that holds no trap instruction**,
21 times in a row at the same place, then NT's boot debugger waits on COM1 forever. The CPU is
`rtl/DSPPC604/` (our own 604e model, the same core as the MacPPC7300 master, 70 MHz). Done means: the
cause is found and shown (bench or board capture), fixed in the RTL, and NT setup gets past this point
on the board with no regression in the big-endian workloads (firmware POST/SMS, AIX 4.3.3 boot).

Background for everything else NT-related: `docs/resume_nt_setup.md` (board procedure, media, open
issues). Read its "The board" section before touching the board.

## Working rules (from the user, durable)

- Work independently; don't ask step by step. The board (.92) is shared with the user: if the user said
  they are on it, wait. Another session (Pippin) may also coordinate on .92 via `/tmp/board.lock`
  (noclobber). The lock currently holds `ibmrs6k-overnight-1793174836` from the overnight session that
  is finished: re-take it with your own name.
- One simulation at a time; once a fix exists, run only the fixed build.
- Raw bench/board logs go to **Y:** (`/mnt/y/ibmrs6k-bench-logs` in WSL, `Y:\ibmrs6k-bench-logs` on
  Windows), unfiltered; extract what you need, then delete. Never write large files inside WSL (its
  vhdx is on a nearly full C:) and not to D: (slow).
- Board access: from WSL Ubuntu-24.04 user dani, `ssh -i ~/mister_key root@192.168.99.92`;
  `scratch/work/r92.sh` runs a stdin script there (from PowerShell:
  `'cmd' | wsl -d Ubuntu-24.04 -u dani -- bash /mnt/c/Temp/mistercore/IBMRS6K47248/scratch/work/r92.sh`).
  Cores go to `/media/fat/_Unstable/IBMRS6K7248.rbf`; NT setup is loaded with
  `echo load_core /tmp/ntarc.mgl > /dev/MiSTer_cmd`. Screens/keys: `scratch/work/kv92.sh`,
  `scratch/work/snap92.sh` (keys arrive 10-40 s late; one key, wait, screenshot).
- Quartus 17.0 Lite: `C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh --flow compile IBMRS6K7248`
  from the repo root, ~25 min. ALMs are at 99 % in the debug build: keep debug additions small.
- Verilator bench in WSL: `sim/`, `make VERILATOR=/home/dani/oss-cad-suite/bin/verilator
  BUILD=/home/dani/ibmrs6k/build16 MEM=12G JOBS=4`. ~0.36 M clocks/s: NT itself is out of reach
  (~8 h); directed tests are the bench's job (`scratch/work/run_sled.sh` runs the LE switch test in
  seconds; clang-18 assembles PPC: see `sim/tests/le_sled.S` and its Makefile rule).
- Commits go straight to master, message style as in `git log` (long prose, what was found and how);
  end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or your own model line).
  Update `docs/bringup_log.md` with dated findings.

## The evidence

### From the overnight capture (`Y:\ibmrs6k-bench-logs\nt_c1boot_20261028.raw`, 17 MB, raw)

The debug build on the board (`scratch/work/IBMRS6K7248_pgm.rbf`, the uncommitted-then-committed
logger in `IBMRS6K7248.sv` ~700-900) dumps, at the first vector-0x700 retire after the port-92 LE
switch: `IL=` LR, ` C=` CTR, ` M=` MSR, then 40 retired instructions as `pppp=vvvvvvvv` (low 16 bits of
the PC = the GPR value it wrote, `--------` none). `Pxxxxxxxx-vvv` events are "last retired PC before
a jump to vector vvv". What it recorded:

```
IL=800A3D04  C=00000000  M=00011001  P800A3D00-700
0700=-------- 0704=00047000 0708=-------- 070C=80076380 0710=-------- 0714=800A3B80 0718=--------
071C=00023031 0720=-------- 0724=00010000 0728=00013031 072C=00013031 0730=-------- 0734=--------
0738=FFFFFFFF 073C=00000018 ...  (then NT's handler at 0x6380: 80076380 = its C-level dispatcher)
P800A3D00-700  x21 in all, identical; then the DSI faults go on (P800AA558-300, P800AA600-300, ...)
```

NT's handler stores SRR0 = **0x800A3B80** (at 0714) and SRR1 = **0x00023031** (at 071C; trap bit,
MSR EE/PR=0, IR/DR, RI, LE).

### What the kernel holds there (`Y:\ibmrs6k-bench-logs\NTOSKRNL.ppc`, the ISO's PPC\NTOSKRNL.EXE)

Image base 0x80010000, loaded at its base (KSEG0: VA 0x8xxxxxxx = physical 0x0xxxxxxx through a BAT);
raw file offset = RVA for every section. `python -I scratch/work/pe_words.py <pe> <from> <to>` prints
the words (little-endian file). Around the two sites (PAGE section):

```
800a3b78 815c0008 lwz   r10,8(r28)        <- bdnz target (loop of CTR=2 starts here)
800a3b7c 288a0000 cmplwi cr1,r10,0
800a3b80 41860024 beq   cr1,800a3ba4      <- SRR0 says the trap was here
...
800a3cfc 80630018 lwz   r3,0x18(r3)
800a3d00 907b0014 stw   r3,0x14(r27)      <- the last instruction retired before the exception
800a3d04 41860aa0 beq   cr1,800a47a4      <- LR at the exception = this address
800a3d08 817f02f4 lwz   r11,0x2f4(r31)
```

No tw/twi anywhere near either site (the kernel has 88 twi; e.g. `0x80069620 0fe00017 twi 31,r0,0x17`,
called by `bl` at 0x800697A0, is NT's DbgBreakPointWithStatus).

### What that says (new today; the old resume doc had only SRR0/SRR1)

1. **The exception is taken right after `stw` at 3D00 retires, but SRR0 points 0x180 bytes back at
   3B80.** Nothing in between retired. The path 3D00 -> 3B80 matches no real control flow.
2. **LR = 0x800A3D04** although nothing near links (no `bl` between 3CC4 and 3D00; 3CC4's `bl` would
   leave LR = 3CC8). A `bl 0x800A3B80` at 3D00 would produce *exactly* LR = 3D04 and a next PC of
   3B80. So the CPU behaved as if the words it ran at 3D00 and 3B80 were not the kernel's: something
   like `bl -0x180` at "3D00" and a tw/twi at "3B80" — or the right words with the wrong PCs/decode.
3. **3D00/3D04 is exactly the pair the BTB's conditional-branch fold makes**: `stw` (a plain word
   memory op, writes no CR: `fold_prev_cfok`) followed by `beq cr1` (bc, no link, BO[2]=1, `cf_branch`).
   3B7C/3B80 is a pair it must not fold (cmplwi writes cr1 → `cf_dep`). Both branches are
   `41860xxx` (BO 12, BI 6): same `ex_cf_bo`/`ex_cf_bi`, only the target differs.
4. It is **deterministic** (21 identical repeats, each resuming from SRR0 and coming back through
   3D00), so a logic bug, not a random cache race.
5. It shows up only in NT, the first big **little-endian** workload: firmware, SMS and AIX (all
   big-endian, IR on, heavy) run fine. In LE the fetch address is munged (`if_addr = {pc[31:3],
   pc[2:0] ^ {le,2'b00}}`, DSPPC604.sv:586-587; `i_addr_next` likewise at :2927), so "the word after
   this one" and doubleword boundaries differ from the logical PC order the BTB and the fold logic use.
6. Stale data is ruled out as the *source of the trap word*: before the kernel load the RAM at physical
   0xA3B80 held a palette table (`0000006600003366...` in `Y:\...\arc2_ram.bin`); executing it would be
   an illegal-instruction exception (SRR1 0x00080000), not a trap.

`x_trap = is_int & ex_dec.trap & trap_hit_q` (DSPPC604.sv:2304) is the only source of SRR1 0x20000
(exc_info, :2385), and `dec.trap` is set only for opcode 3 (twi) and 31/4 (tw) in DSPPC604_decode.sv
(:89, :402). So at the exception EX held an operation whose `ex_dec.trap` = 1 with `ex_pc` = 3B80.

## Suspects, in order

1. **The conditional-branch fold (`ex_cf`) in LE**, and what follows it in the fetch queue. Code:
   fold learning `fold_cand`/`cf_cand`/`cf_learn` (DSPPC604.sv ~2095-2153), the BTB read and
   `btb_hit_cf`/`pred_pc` (`pc_f + 8` past a folded cf, ~734-798, 954-961), `if2_fold`/`if2_cf` and the
   fetch queue (~244-245, 580, 981-1007), ID `id_cf` (~1583), EX `ex_cf*` (~2682-2687), the branch
   resolve (~1966-1997: `br_kind`, `br_target`, `ex_seq = ex_cf ? ex_pc8 : ex_pc4`). Questions: in LE,
   does skipping "pc_f + 8" after a folded cf at a fetch address with pc[2] set pick the right words
   (the pair 3D00/3D04 straddles nothing, but its *fetch* in LE is from 3D04/3D00 of one doubleword)?
   When a cf pair resolves (taken or not) and redirects, does the fetch queue / ID keep a word or
   `ex_dec` from the wrong path with a PC from another (SRR0 = 3B80, LR = ex_pc + 4 = 3D04)? Does
   the link path ever fire for a cf (`br_lk` comes from the host instruction's decode, not the folded
   branch's: check that a host `stw`'s decode fields — bits 0/1 of a D-form word — are never read as
   LK/AA for the folded branch).
2. **BTB entry validity**: fold entries are checked against `fold_epoch` and MSR[IR] only
   (`fold_ok`, :650), **not MSR[LE]**; the epoch steps on icbi and on `is_xlate` (isync, mtsr, tlbie...)
   (:2157), **not on a HID0[ICFI] flash invalidate** (:2778, :2997). Plain (non-fold) entries carry no
   epoch at all (fine for predictions EX checks; fatal for anything that replaces a word unseen). A fold
   or cf entry learned from code that lived at the same VA before the kernel was loaded (setupldr/ARC
   ran LE, probably with IR off, unverified — check whether NT's loader ran any code with IR on at 0x800Axxxx) would make the
   fetch skip the real word and execute a ghost branch.
3. **I-cache vs. memory in LE**: line fill order and which word of a doubleword lands where when the
   fill is munged; HID0[ICFI]/icbi effectiveness after the loader DMAs the kernel in (the 53C810 writes
   RAM directly; DMA doublewords are swapped in LE: `LE_DMA_SWAP` in `IBMRS6K7248_machine.sv`).

## Plan

1. **One board capture that names the words** (cheapest, decisive). The logger already keeps a 64-entry
   ring of retired PC + word (`le_pc`/`le_in`, IBMRS6K7248.sv ~711-727, `trace_insn` = `wb_insn`, the
   word as executed) from the LE switch on, but dumps it only at a stall (`stall_go & le_arm`, ~808).
   Make `isi_go` dump it too (set `le_r <= le_w; le_left <= 64` on `isi_go`), and add to the ring the
   per-retire flags `trace_fold` (and a cf indication if the trace has one; else export `ex_cf` and the
   word in EX at the exception from DSPPC604 as debug-only outputs). Build (~25 min), stage to
   `_Unstable`, boot NT setup per `docs/resume_nt_setup.md` (~15-20 min to the kernel), record COM1
   (`/dev/ttyS1`, UART mode None) to the board's /tmp, copy to Y:. Compare the 64 retired words with
   the kernel image: which words the CPU really ran at 3CE0-3D00, whether 3D00 retired with a folded cf,
   and what entered EX after it.
2. **Reproduce on the bench with a directed test** once the shape is known: LE code (munged as
   `le_sled.S` does it) with the kernel's sequence (`lwz; stw; beq cr1` pairs, a bdnz loop of 2 at a
   0x...78 target, the same alignments: 3B78/3B7C/3B80, 3CFC/3D00/3D04), run long enough for the BTB to
   learn the fold, check for a wrong PC/trap. Also run it big-endian: it must pass there today.
3. **Fix** in DSPPC604; rerun the directed test in both endiannesses, `run_sled.sh`, and on the board
   the firmware POST to SMS, AIX 4.3.3 from `AIX433_4GB.img`, then NT setup. Watch timing: CPU clock
   slack has been -2.3 to -3.2 ns all along and runs fine; don't make it worse.
4. If NT setup then goes on, hand back to the NT work list in `docs/resume_nt_setup.md` (screen colours
   and double width, ARC's 1926 date, ARC's floppy read error 8, the SMS restart halt).

## Files

- CPU: `rtl/DSPPC604/DSPPC604.sv` (3472 lines: fetch/BTB ~230-1010, ID ~1580, EX/branch ~1960-2200,
  exceptions ~2290-2420, SPRs ~2770, I-cache invalidate ~2990), `DSPPC604_decode.sv`, `DSPPC604_cache.sv`.
- Machine/debug stream: `IBMRS6K7248.sv` (logger ~590-900), `rtl/IBMRS6K7248_machine.sv`.
- Images on Y: `NTOSKRNL.ppc`, `SETUPLDR.ppc` (not a PE: raw loader image with a 0x200 header),
  `arc2_ram.bin` (32 MB RAM dump at ARC's disk scan), `nt_c1boot_20261028.raw` (the capture above).
- Helper: `scratch/work/pe_words.py` (PE section table + words for a VA range).
