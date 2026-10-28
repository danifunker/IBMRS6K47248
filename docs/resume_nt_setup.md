# Resume prompt: Windows NT 4.0 setup on the 7248 core (a trap at a `beq`)

(Written 2026-10-28 ~14:15 EDT at the end of the overnight session that made the ARC diskette boot and
started NT setup. Paste everything below the line into a new session started in this repository.)

---

## The task, in the user's order

1. **Get Windows NT 4.0 (PowerPC) setup through text mode** on the IBMRS6K7248 core. It now stops on a
   CPU-side bug (below): fix that first.
2. Then the cosmetic and side issues listed under "Open issues".
3. AIX 5.1 (volume 1 boots, then stalls: see below), OS/2 Warp PPC (last; may need the Power Series 850
   personality), freeing FPGA logic (98-99 % ALMs used).

Work independently (memory: `work-independently`); the board is shared with the user, who drives it at
times: ask before taking it if they said they are using it. The user wants raw bench logs on **Y:**
(`/mnt/y/ibmrs6k-bench-logs`), never filtered at capture, extracted then deleted (memory
`bench-keep-raw-logs`); never write big files inside WSL (its vhdx is on a nearly full C:).

## Where things stand (all on master)

| Commit | What |
|---|---|
| `c9a718a` | PReP **port 92 bit 1** switches the bridge to little-endian (ARC uses it, not PICR1) |
| `82ffb4b` | SCSI requests to the Main up to **32 blocks (16 KB)** (was 4); AIX 4.3.3 boots fine |
| `ea12ce1` | **integer scaling** (P2 Video, Scale; user confirmed V-Integer works); the **CD drive always on the bus** (empty: NOT READY 3A; a disc mounted after reset: UNIT ATTENTION 06/28 once); `releases/IBMRS6K7248_default.nvr` |
| `725b435` | **the real LE model**: in little-endian mode the MPC105 swaps only the device side (8000_0000-FEFF_FFFF), **not RAM/ROM** (memory holds the 604's munged image: ARC's loader reverses its own LE part per doubleword before it switches); **DMA masters' doublewords reversed** in LE mode (LE_DMA_SWAP=1 in `IBMRS6K7248_machine.sv`) |
| `c874cee` | keyboard **scan set 1** (ARC sends F0 01); CMOS century 1A = 20 |
| `d4f5442` | 53C810 GPREG input pins read 1 (pull-ups, no serial NVRAM); debug stream logs all 810 regs (`io_ncr`) |
| `ce61d61` | 53C810 **CHMOV runs as MOVE** (ARC's SCRIPTS move data with it; was "illegal instruction") |
| `d8e60fa` | `tools/mk_ntdisk.py`: builds a blank NT disk: PReP boot partition (type 41) holding ARC, a 5 MB FAT16 system partition, the rest free |

Uncommitted at hand-off (commit it with the next result): `IBMRS6K7248.sv` debug-only changes: the
floppy/DMA logger also logs 3F7 (DIR/CCR) both ways and reads of DMA ports 00-0F; `isi_go` fires on the
**first program exception (PC 0x700) after the LE switch** and dumps LR/CTR/MSR then 40 retired
instructions with the GPR each wrote. That build is on the board (`scratch/work/IBMRS6K7248_pgm.rbf`).

Logs: `docs/bringup_log.md` (2026-10-28 sections), `docs/stubbed-hardware.md` (dated log).

## The board (.92, MiSTer-SS1) right now

- Core: `/media/fat/_Unstable/IBMRS6K7248.rbf` = the pgm-capture build above (debug build).
- Media in `/media/fat/games/IBMRS6K7248/`: **`NT4_ppc_arc.img`** (made by `tools/mk_ntdisk.py`,
  MD5 382bc5ee7e0faab0836d03aba1bc96ee as made; NT setup may have written to it since),
  `winnt40wks_sp1_en.iso` (despite the name: **NT 4.0 RTM** Workstation, kernel 4.0.1381.1, label
  NTWKS40A, full PPC tree), `rs6karc151.img` (ARC 2.11 EC diskette), `blank144.img`, `NT4_ppc.img`
  (the user's own experiments), `AIX433_4GB.img` (installed AIX 4.3.3), `AIX51_VOLUME1.iso`,
  OS/2 media. NVRAM file = `releases/IBMRS6K7248_default.nvr` (backups `IBMRS6K7248.nvr.bak-20261028-*`).
- Boot NT setup: `/tmp/ntarc.mgl` (rbf + blank floppy idx 4, `NT4_ppc_arc.img` idx 0, the NT ISO idx 2):
  `echo load_core /tmp/ntarc.mgl > /dev/MiSTer_cmd`. The firmware boots **ARC from the disk** (no
  diskette). ARC: Enter (US English), Enter (US keyboard), Down + Enter ("Run a Maintenance Program"),
  then type `cd:\ppc\setupldr` + Enter. **The KVM tool's `type` drops backslashes**: type `cd:`, then
  `kv92.sh key '\'`, `ppc`, `key '\'`, `setupldr` (scratch/work/kv92.sh; keys lag 10-40 s).
- Debug stream: UART mode None (saved), record with
  `stty -F /dev/ttyS1 115200 raw -echo; nohup sh -c 'timeout 7200 cat /dev/ttyS1 > /tmp/c1boot.raw' &`
  before loading. `scratch/work/snap92.sh WAIT NAME [BYTES]` screenshots + tails it.
  `scratch/work/r92.sh` runs a stdin script on the board (avoids quoting trouble).
- Board lock: `/tmp/board.lock` on .92 was taken by this session (ibmrs6k-overnight-...): remove or
  re-take.

## The current blocker: a trap exception at a plain `beq` (CPU side)

What NT does: `setupldr` loads from the CD, draws "Windows NT Setup", loads the kernel and drivers, the
kernel starts (`NTOSKRNL.EXE` base 0x80010000) and then its boot debugger sends a KD state-change packet
over COM1 forever (`30 30 30 30` leader; exception **0x80000003 STATUS_BREAKPOINT**, PC 0x800A3B58),
waiting for a debugger. Before that, **22 program exceptions**: 21 at the same spot, one more.

The capture (first program exception after the switch): SRR0 = **0x800A3B80**, SRR1 = **0x00023031**
(bit 0x00020000 = trap). The kernel's bytes there (from the ISO's `PPC\NTOSKRNL.EXE`, RVA 0x93B80, in
the PAGE section): `800a3b7c 288a0000 cmplwi cr1,r10,0` / **`800a3b80 41860024 beq cr1,0x800a3ba4`**.
In DSPPC604 the only trap path is `x_trap = is_int & ex_dec.trap & trap_hit_q` (DSPPC604.sv ~2304;
`trap` is set only for tw/twi in `DSPPC604_decode.sv`). So **the CPU executed a tw/twi at a PC whose
memory word is a `beq`**. NT's handler reads the word as data, sees no breakpoint, resumes, the CPU traps
again (21x), then NT gives up into the debugger.

Ruled out: the firmware's RAM image at physical 0xA3B80 is a palette table (no stale firmware code);
no twi/tw near the site in the kernel image (the kernel has 88 twi in all).

Suspects, in order:
1. **The folded conditional branch.** `cmplwi` at 0x...7C precedes the `beq`; DSPPC604's BTB folds "the
   conditional branch after this word" (`if2_cf`, `cf_word` reconstruction ~DSPPC604.sv 1975-1997,
   `if2_fold`). An exception attributed to the folded branch's PC with stale decode (`trap` bit) or a
   wrong compare would look exactly like this. Check how SRR0 and `ex_dec` are formed for a folded pair,
   and whether anything differs with MSR[LE] (the fetch address is munged, `if_addr = pc ^ 4`).
2. **Instruction/data view disagreement**: a stale I-cache line (NT should sweep with icbi/HID0 after
   loading code; check `icbi` and the I-cache snoop in LE mode), or the LE fetch path delivering the
   other word of a doubleword.
3. Next diagnostic, cheap: add a debug-only CPU output with the instruction word in EX when an exception
   is taken (and the `ex_cf`/fold state), log it at the first 0x700 after the switch; one board run
   tells which. The bench can reproduce but NT setup is ~8 h of bench time (0.36 M clocks/s); prefer the
   board, or a directed test ROM: LE code with `cmplwi cr1` + `beq cr1` in a loop, run long enough for
   the BTB to fold it, check for a spurious trap.

## Open issues found today (not yet fixed)

- **NT setup's screen**: red where it should be blue (palette R/B swapped: DAC writes in LE, likely a
  lane issue for a 16/32-bit write to 3C8/3C9) and everything drawn twice side by side (the mode setup
  writes gives our S3 scan-out the wrong pixel width/stride). Cosmetic until text setup runs.
- **ARC's date shows 1926**: CMOS 1A = 20 did not change it; find where ARC takes the century (CMOS 32?
  the NVRAM? an RTC register).
- **ARC reading the floppy (Simple Setup, "error 8" = EIO)**: it reads C0/H0/R1 by DMA (high page 0x80,
  mode 46, count 0x200), the FDC reports success, ARC recalibrates and retries forever. Suspects: the
  disk-change line polarity (DIR bit 7) or the DMA status/TC. The uncommitted logger change logs 3F7 and
  DMA port reads: one ARC Simple Setup run on the board shows which. Worked around by
  `tools/mk_ntdisk.py` (ARC installed on the disk from the PC).
- **The SMS diskette's restart halts** (progress DC: an unexpected external interrupt in POST after a
  software restart that resets no device). Plan in `docs/stubbed-hardware.md` (log the 8259s, check ICW1
  clears latched requests, a device reset on port 92 bit 0).
- **AIX 5.1** (volume 1): kernel runs, `rc.boot` parks (the shell's FP-unavailable loop, like 4.3.3's
  `loopled`); AIX logged an `ER01` entry for scsi0 (error id 0BA49C99) in the NVRAM OS area. Its
  install CD booting sets NVRAM `fw-boot-device` to the CD (that confused disk boots: restore with the
  default NVRAM).
- **OS/2 Warp PPC CD** boots its loader directly (type-41 partition) and loops at 0x000DC88C before any
  LE switch: likely its machine check. Personality plan: planar ID F0-F3 = IDE planar = "IBM PPS Model
  6050/6070 (E)" (same firmware; `docs/firmware_analysis.md` 4.4, `Get_PrintableModel` RAM 0x20654); an
  OSD Model option; the 850 has IDE where the 7248 has the 53C810, so the firmware may need an IDE/ATAPI
  model if it won't boot from the 810 as a PCI card. 6050/6070 ROMs are in `firmware/images/other/`.
- **The old LE test ROMs** (`sim/tests/le_test*.rom`) encode the old swap-everything model and hang:
  rewrite for the munged-memory model (binutils for PowerPC is missing in WSL; clang-18 assembles, see
  `sim/tests/le_sled.S` and its Makefile rule).
- **FPGA space**: 41,302/41,910 ALMs (99 %) in the debug build. Breakdown and options were given to the
  user: release build without the debug stream (~1.5-2 k), drop the OPL FM synth (830), framework
  options (YC/ALSA/adaptive ~1 k), then trimming the 53C810 (2,331), SCSI target (1,501), DMA (1,414).

## Facts worth keeping

- PPC `TXTSETUP.SIF`: `symc810.sys` ("Symbios Logic C810 PCI SCSI Host Adapter") loads by default;
  computer type for us = `carolina_up` "IBM Power Series 6050,6070 and RS/6000 Model 7248"
  (`[Map.Computer]` maps only IBM-6070 to it: pick it by hand if asked). No F6 on PPC (S in text setup).
- ARC's SCRIPTS: in the diskette image at 0xB7088 (`47000000 00000528` SELECT ATN from table first).
- The 53C810 bench model prints each SCRIPTS instruction (`ncr <addr>: ...`); the SCSI target prints
  each CDB/status under Verilator (`scsi dev N lun L cdb ...`).
- WSL bench: `scratch/work/run_arc2.sh` (ARC on the bench, ~2.4 G clocks to ARC's scan, 2+ h);
  `scratch/work/run_sled.sh` (the LE switch test, seconds). Bench build dir `/home/dani/ibmrs6k/build16`.
- Quartus full build ~25 min (`quartus_sh --flow compile IBMRS6K7248`); CPU clock slack has been
  -2.3 to -3.2 ns all session and runs fine on the board.
