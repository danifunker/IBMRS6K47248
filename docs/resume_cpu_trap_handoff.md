# Hand-off, CPU only: DSPPC604 takes a phantom trap in little-endian mode

**SUPERSEDED 2026-10-28 evening: the trap is NT's own `twi` (DbgLoadImageSymbols), the kernel is ntkrnlmp.exe at 0x80049000, the CPU is fine. See `docs/resume_nt_kernel_break.md`.**

(Written 2026-10-28, a CPU-scoped cut of `docs/resume_cpu_trap_fable.md`. Paste everything below the
line into a new session started in this repository, `C:\Temp\mistercore\IBMRS6K47248`. The board
procedure, NT media, the debug logger and the NT work list stay in `docs/resume_cpu_trap_fable.md` and
`docs/resume_nt_setup.md`; this document is about the RTL in `rtl/DSPPC604/` and nothing else.)

---

## The task

Find and fix the bug in the CPU model `rtl/DSPPC604/` (our 604e, shared with the MacPPC7300 master,
70 MHz) that makes it take a **program exception with the trap bit set (SRR1 0x00020000) at an address
holding no trap instruction**, in little-endian mode only. The workload that shows it is the Windows NT
4.0 PowerPC kernel; big-endian workloads (firmware POST/SMS, AIX 4.3.3) have never shown it.

Done means:

1. The mechanism is shown: a directed Verilator test in `sim/tests/` reproduces the wrong PC or
   phantom trap in LE and passes in BE before the fix.
2. The fix is in `DSPPC604.sv` (or the decode/cache files), the directed test passes in both
   endiannesses, `scratch/work/run_sled.sh` (the existing LE switch test) still passes.
3. No regression in BE: the firmware reaches SMS and AIX 4.3.3 boots on the board (the board steps are
   in `docs/resume_cpu_trap_fable.md`, "Working rules" and "Plan" step 3). NT setup getting further is
   the proof the fix is the right one.
4. Timing is not made worse: the CPU clock's slack has been -2.3 to -3.2 ns all along and the core
   runs; the debug build is at 99 % ALMs.

## Working rules (from the user, durable)

- Work independently; do not ask step by step.
- One simulation at a time; once a fix exists, run only the fixed build.
- Raw bench logs go to **Y:** (`/mnt/y/ibmrs6k-bench-logs` in WSL), unfiltered; extract, then delete.
  Nothing large inside WSL (its vhdx is on a nearly full C:), nothing on D: (slow).
- Verilator bench in WSL Ubuntu-24.04, user dani: `sim/`,
  `make VERILATOR=/home/dani/oss-cad-suite/bin/verilator BUILD=/home/dani/ibmrs6k/build16 MEM=12G JOBS=4`.
  About 0.36 M clocks/s, so NT itself is out of reach; directed tests are the bench's job.
  clang-18 assembles PowerPC: see `sim/tests/le_sled.S` and its rule in `sim/Makefile` for how an LE
  test image is built (the words are stored munged, as the CPU expects them in LE).
- Commits go straight to master, message style as in `git log` (prose: what was found and how); end
  with your own `Co-Authored-By` line. Add dated findings to `docs/bringup_log.md`.

## What the CPU did (from the board capture of 2026-10-28)

The debug build's retire logger recorded, at the first vector-0x700 exception after the switch to
little-endian: LR = **0x800A3D04**, CTR = 0, MSR = 0x00011001, last retired PC before the vector =
**0x800A3D00**. NT's first-level handler then stored SRR0 = **0x800A3B80** and SRR1 = **0x00023031**
(trap bit; EE and PR clear; IR, DR, RI, LE set). The same exception, with identical values, repeated 21
times: NT resumes at SRR0 and comes back through 3D00 each time. Deterministic, so logic, not a race.

The kernel's words at the two places (NTOSKRNL.EXE, image base 0x80010000, loaded at its base, raw
offset = RVA; `python -I scratch/work/pe_words.py <pe> <from> <to>` prints them):

```
800a3b78 815c0008 lwz    r10,8(r28)        <- a bdnz target (CTR loop of 2 starts here)
800a3b7c 288a0000 cmplwi cr1,r10,0          writes cr1
800a3b80 41860024 beq    cr1,800a3ba4      <- SRR0: "the trap was here"
...
800a3cfc 80630018 lwz    r3,0x18(r3)
800a3d00 907b0014 stw    r3,0x14(r27)      <- last instruction retired before the exception
800a3d04 41860aa0 beq    cr1,800a47a4      <- LR at the exception = this address
800a3d08 817f02f4 lwz    r11,0x2f4(r31)
```

There is no tw/twi anywhere near either site. Stale RAM is not the trap word's source either: before the
kernel load the RAM at physical 0xA3B80 held a palette table, whose words decode as illegal instructions
(SRR1 0x00080000), not as a trap.

### What EX must have held

`x_trap = is_int & ex_dec.trap & trap_hit_q` (DSPPC604.sv:2304) is the only source of SRR1 0x20000
(exc_info, :2385), and `dec.trap` is set only for opcode 3 (twi) and opcode 31 xo 4 (tw)
(DSPPC604_decode.sv:89, :402). LR is written only from `ex_dec.br_lk` (`lr_next = ex_pc4`, :2502), and
the decoder sets `br_lk` only for the branch opcodes 16, 18 and 19 (decode :135, :140, :150), never from
a D-form word's low bits. So, at the two retire slots in question, EX held:

- at `ex_pc` = 0x800A3D00: a decode with `br_lk` set and a taken branch whose target was 0x800A3B80
  (exactly what `bl -0x180` would do; the kernel's word there is `stw`);
- at `ex_pc` = 0x800A3B80: a decode with `trap` set whose TO test passed (the kernel's word there is
  `beq cr1`).

Neither the kernel's word, its doubleword partner (the word at +4/-4, which a missing or doubled LE
munge would deliver: 3D04 is `beq`, not `bl`) nor its byte swap decodes that way. So either the words
came from somewhere other than the kernel image (a stale or mis-filled I-cache line, a BTB entry
standing in for a word), or the decode and the PC that travelled with it belong to different
instructions (a pipeline mix-up on a redirect).

### Why the fold logic is the first suspect

3D00/3D04 is precisely the pair the BTB's conditional-branch fold makes: `stw` is a plain word memory op
that writes no CR (`fold_prev_cfok`, :2163) followed by `beq cr1` (bc, relative, no link, BO[2] set:
`cf_branch`, :2107-2109). 3B7C/3B80 is a pair it must not fold because `cmplwi` writes cr1 (`cf_dep`,
:2110). Both branches are `41860xxx` (BO 12, BI 6), so a cf entry learned for one carries the same
`cf_bo`/`cf_bi` as the other; only `cf_tgt` differs. And the only thing new about NT is the endianness:
in LE the fetch address is munged (`if_addr = {pc_f[31:3], pc_f[2:0] ^ le_inst}`, :586-587, and
`i_addr_next` likewise at :2927), so "the word after this one" and the doubleword boundary differ from
the logical PC order the BTB, the fold learning and `pc_f + 8` use.

## Suspects, in order, with the code

1. **The conditional-branch fold (`ex_cf`) in LE.** Learning: `fold_cand`/`cf_cand`/`cf_learn` and the
   BTB write mux (:2095-2154); what may fold the next instruction and the epoch (:2156-2172). Fetch:
   `btb_hit_cf` (:753), `pred_pc = btb_taken ? dest : btb_hit_cf ? pc_f + 8 : pc_f + 4` (:798), the
   predicted index/ITT (:954, :961), `if2_fold`/`if2_cf` into the fetch queue (:244-249, :580-581,
   :981-1012). ID: `id_cf*` (:1583-1588). EX: `ex_cf*` (:2682-2687); the branch resolve uses the
   folded fields when `ex_cf` (`br_kind` :1975, `br_bo` :1976, `br_taken` :1982, `br_target` :1988,
   `ex_seq = ex_cf ? ex_pc8 : ex_pc4` :1993); `cf_word` rebuilds the folded branch's word for the
   retire trace (:1996, used at :3222). Questions to answer on the bench:
   - After a folded cf at a fetch address with pc[2] set, does `pc_f + 8` in LE fetch the right
     words? (The pair 3D00/3D04 is one doubleword; its fetch in LE comes from 3D04/3D00 physically.)
   - When a cf pair resolves and redirects, can the fetch queue or ID hand EX a word from one path with
     the PC of another? SRR0 = 3B80 with LR = 3D04 = `ex_pc4` of the previous slot is what that looks
     like.
   - Settled already: a host instruction's `br_lk` cannot leak into the folded branch (decode only sets
     it for branch opcodes), so the LR write came from a word EX decoded as a branch with LK, not from
     `stw`'s low bits.
2. **BTB entry validity.** Fold and cf entries are checked against `fold_epoch` and MSR[IR] only
   (`fold_ok`, :650-651, used at :727-737): **not MSR[LE]**. The epoch steps on icbi and on `is_xlate`
   (isync, mtsr, tlbie...) (:2157), **not on HID0[ICFI]** (the flash invalidate, :2778, :2988 ff.).
   Plain (non-fold) entries carry no epoch at all, which is fine for predictions EX checks but fatal
   for anything that replaces a word unseen. A fold or cf entry learned from code that lived at the same
   VA earlier (the loader and ARC run LE at 0x8xxxxxxx addresses; whether with IR on at 0x800Axxxx is
   unverified) would make the fetch skip the real word and execute a ghost branch. Candidate fixes if
   this is it: include MSR[LE] in `fold_ok` (store `fold_le` beside `fold_ir`), step `fold_epoch` on
   ICFI and on the MSR[LE] change, or clear the BTB on both.
3. **I-cache versus memory in LE** (`DSPPC604_cache.sv` and the fill path): the fill order and which
   word of a doubleword lands where when the address is munged; whether HID0[ICFI] and icbi really drop
   lines after the loader DMAs the kernel in (DMA doublewords are swapped in LE by the machine, outside
   the CPU, `LE_DMA_SWAP` in `rtl/IBMRS6K7248_machine.sv`).

## Plan

1. **Read the words, not the PCs.** The board's retire ring (64 entries of PC + the word as executed,
   `wb_insn`) exists but dumps only at a stall; making it dump at the exception is a logger change, not a
   CPU change (details in `docs/resume_cpu_trap_fable.md`, Plan step 1). If that capture is available
   when you start (look for a newer `nt_*.raw` on Y:), it tells you directly which words EX ran at
   3CE0-3D00 and what entered EX after. If not, the CPU work below does not depend on it.
2. **Directed bench test.** Write `sim/tests/le_fold.S` (name free) in the style of `le_sled.S`: switch
   to LE, then run the kernel's shape at the kernel's alignments: a `bdnz` loop of CTR = 2 whose target
   is at an address ending 0x...78 holding `lwz; cmplwi cr1; beq cr1` (3B78/3B7C/3B80), and further on a
   `lwz; stw; beq cr1` triple at 0x...CFC/D00/D04 with the same BO/BI (12, 6) and a different target, in
   a loop that runs long enough for the BTB to learn the cf fold (several passes) and for the CTR loop to
   be predicted. Make the test fail loudly on any exception (a handler at 0x700 that writes a marker)
   and on any wrong value. Run it in BE first: it must pass. Then LE. Vary what the suspects say
   matters: the pc[2] of the folded pair, a BTB entry pre-learned at the same VA before the LE switch
   (run the same addresses with other code first, then overwrite, with and without icbi/ICFI/isync),
   IR on and off.
3. **Fix** in `DSPPC604.sv`; rerun the directed test in both endiannesses and `run_sled.sh`. Keep the
   change small (ALMs at 99 % in the debug build) and avoid the critical path through the BTB read and
   `pred_pc`.
4. **Regression on the board** per `docs/resume_cpu_trap_fable.md` (firmware to SMS, AIX 4.3.3 boot,
   then NT setup). If NT setup goes on past the kernel's start, hand the rest back to the NT list in
   `docs/resume_nt_setup.md`.

## Files

- `rtl/DSPPC604/DSPPC604.sv` (3472 lines): fetch and BTB ~230-1012, ID ~1580, branch resolve
  ~1966-2000, fold learning ~2095-2172, exceptions ~2290-2420, SPRs ~2770, I-cache invalidate ~2988.
- `rtl/DSPPC604/DSPPC604_decode.sv`: traps :87-89, :402; branches :135-150.
- `rtl/DSPPC604/DSPPC604_cache.sv`: the I-cache and its fill.
- `sim/tests/le_sled.S`, `sim/Makefile`, `scratch/work/run_sled.sh`: the LE test pattern to copy.
- `scratch/work/pe_words.py`: words of a VA range from a PE image.
- On Y: `NTOSKRNL.ppc` (the kernel), `nt_c1boot_20261028.raw` (the capture summarised above).
