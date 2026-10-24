# IBMRS6K7248 plan

The machine: the IBM RS/6000 43P 7248 and the Power Series 830/850 (the
"Carolina" board: PowerPC 604, Motorola MPC105, IBM Fire Coral, PC87332,
S3 Vision864, NCR 53C810 on the 7248). One core for both: the firmware is
the same code and picks its personality from the planar ID (port 0852).
Goal: the machine's own firmware, then AIX 4.3.3 and 5.1; later the
little-endian systems (Windows NT, OS/2 Warp PPC, Solaris 2.5.1).

Sources: `docs/hardware_inventory.md`, `docs/firmware_analysis.md`
(with `firmware/disasm/`), `docs/emulators_and_software.md`. What the
firmware does on the core, run by run: `docs/bringup_log.md`.

How each milestone is proven: the Verilator bench (`sim/`) on the real
v1.12 ROM first (its progress codes at 8C0, COM1's output, the stub
list), then the board.

## Priorities (the user's order, 2026-10-18; confirmed 2026-10-22)

0. **The install CD's blockers**, before anything else, in this order:
   1. ~~**COM1's rate**~~ (done 2026-10-23: the core's rate is right, AIX
      programs 9600 8N1 and never writes COM1; there is no text to read): AIX's console text arrives ~1.43x off rate on the
      board; read it exactly on the bench (`--com1`, the divisor AIX programs
      at 3F8-3FF), find why the board's rate differs, then read the text
      (it may name the failed step).
   2. ~~**The failing `rc.boot` step**~~ (found 2026-10-23: the `/SPOT` mount, LED
      0x518: `cfgmgr`'s SCSI scan under `ncr810dd` finds no `cd0`, so `bootinfo -b`
      is empty; this is item 1, SCSI).
   3. ~~**The Serial check**~~ (done 2026-10-23: `0000000000012345`): the residual's Serial carries the EEPROM image's
      digits now that the NVRAM header holds them (`bf5f755`).
1. **SCSI** (M5): the Main_MiSTer branch (`support/ibmrs6k/`: the disk write
   buffer, the fast service loop, the CD layer, NVRAM/CMOS persistence) and
   the 53C810 as AIX's `ncr810dd` drives it (interrupts on IRQ15, DMA into
   kernel buffers, the message and status phases), so that AIX can mount the
   install CD and install onto a SCSI disk image.
2. **Video** (M4 under AIX): the S3 Vision864 as AIX's S15 driver sees it
   (modes, the accelerator, the SDAC), and the firmware's error-icon palette.
3. **The rest**, in this order: what `docs/stubbed-hardware.md` lists as the
   boot hits it (the 16550 under AIX, 8237 DMA, the EEPROM image's details),
   Ethernet (M7, with the branch), audio, floppy; then speed (the CPU clock
   misses 70 MHz by ~3 ns in the current fit).

Where AIX stands at the hand-over: the install CD boots to user space, no
device is touched, and `rc.boot` ends in its `loopled` forever-loop (a step
failed before any hardware was needed: see `bringup_log.md` 2026-10-18 late
evening). Item 0 is found first, then 1-3 above.

**2026-10-24**: with the 53C810 fixes (`2df9a08`, `1440701`, `2b0d399`) the install CD gets past the
`/SPOT` mount on the board: AIX's install program shows "Please define the System Console". With
the keyboard fixes (`2e1bb84`, `1bff1fe`: FE for a non-command, scan set 3, FC key lists) AIX
4.3.3 **installed onto a 4 GB SCSI disk image** (about 80 minutes, through the Main's standard
block writes) and boots from hdisk0 into X on the S3 (backup:
`~/ibmrs6k/disks/backup/AIX433_4GB_installed.zip` in WSL).

## Next stages (the user's order, 2026-10-24)

The places that can bite the installed AIX next, in this order:

1. **The mouse**: the 8042's auxiliary port and its PS/2 mouse as AIX (`mousedd`) and its X
   server drive them; the keyboard showed AIX's probes depend on exact answers (EF, FC lists).
2. **The S3 Vision864 under AIX's X server**: the accelerator, the SDAC/RAMDAC modes and the
   registers AIX's driver uses beyond the firmware's (`docs/s3_design.md`).
3. **NVRAM/CMOS persistence**: the 4 KB PReP NVRAM (AIX's boot list) and the CMOS are rebuilt
   on every core load, so after a reload the firmware may boot the CD instead of hdisk0; saved
   to the SD card through the Main_MiSTer branch (`support/ibmrs6k/`).

Then the rest of `docs/stubbed-hardware.md` (8237 DMA, Ethernet with the branch, audio, floppy),
the Main_MiSTer write buffer for faster disk writes, and timing (the latest fit misses by 3.36 ns).

## Milestones

### M0 Skeleton (done, 2026-10-17)

Template renamed, DSPPC604 at 100 MHz, the SDRAM controller, the PReP map,
COM1, the planar ID, the bench. The ROM runs from reset to memory sizing.

### M1 Memory: the MPC105 and Fire Coral's configuration (in progress)

- CF8/CFC configuration mechanism (the MPC105's; the firmware does not
  use the 80800000 window).
- MPC105 (bus 0 device 0, 1057:0001): its configuration registers
  stored (PICR1/2, MCCR1-4, error registers), the eight banks' start,
  end and enable registers decoding the CPU's RAM accesses onto the
  SDRAM, an address no enabled bank holds reading the value last
  driven onto the memory bus (the firmware's bank probe relies on it).
- The SIMM presence-detect bytes (ports 0880-0882, one per pair; FF
  empty) describing the RAM the OSD chose, as pairs of 8, 16, 32 or
  64 MB (the firmware's table at FFF05BA4).
- Fire Coral (device 11, 1014:000A): its configuration header, BAR0, its
  internal registers behind the index/data pair at BAR0 (1000/1004).
- Done when: the recovery block passes memory init and the main
  block's CRC, the main block decompresses the firmware into RAM and
  reaches `main_control` (0x8398), with the caches on and the DSI
  handler loading DBAT3 for I/O.

### M2 The ISA core and the console

- Two 8259s (and the interrupt acknowledge at BFFFFFF0, ELCR 4D0/4D1),
  ext_irq to the CPU; the 8254 (port 61, speaker gate); the DMA
  controllers' registers (no transfers yet); port 92.
- RTC (MC146818-compatible, 70/71) and the 4 KB NVRAM (74/75/76) kept
  on the SD card (as MacPPC7300's NVRAM); the VPD/password EEPROM
  (78-7C); IBM system registers (0808-08A0: equipment, L2 status and
  control, parity, planar ID).
- PC87312/PC87332 configuration (398/399), COM1/COM2 where it puts
  them; the firmware's ASCII terminal (`mode A`) on the MiSTer's UART.
- Done when: the firmware's menus or its error screen appear on the
  serial console.

### M3 Keyboard and mouse

The 8042 (60/64) with a PS/2 keyboard and mouse from hps_io (F1/F4/F5 at
start-up, the `eatabug` monitor).

### M4 Video

**Status (2026-10-17):** phase 1 works on the bench: the firmware's S3
driver sets 640x480x8 and draws the start-up screen (the PowerPC logo,
the POST icons, the error triangle with its code) through the 8514
engine, scanned out of VRAM in DDR3 (`docs/bringup_log.md`,
`docs/images/first_screen_powerpc_logo.png`). Phase 1a
(`IBMRS6K7248_s3.sv`: registers, frame buffer, vertical interrupt), 1b
(`IBMRS6K7248_s3ge.sv`: the engine) and 1c (`IBMRS6K7248_s3video.sv`:
VRAM in DDR3, CRTC, dot clock, palette, cursor), from
`docs/s3_design.md`. The bench models the DDR3 port and keeps the
picture's latest frame (`--frame`). Not yet on the board.

S3 Vision864 + SDAC (PCI, 5333:88C0): VGA text and graphics modes, the
linear frame buffer, the hardware cursor; 2 MB VRAM in the HPS's DDR3
(as MacPPC7300's video). The firmware's icons and SMS screens.

### M5 Storage

- Floppy (the PC87312's FDC) from an image: the SMS and diagnostics
  diskettes.
- NCR 53C810 (PCI device 0x10 on the 7248): SCRIPTS, DMA through the
  CPU's snoop port, SCSI disks and a CD-ROM from hps_io's block devices.
  **Status (2026-10-17): phase 1 written** (`docs/scsi_design.md` 5.8):
  `IBMRS6K7248_ncr810.sv` (the HP 9000/715 core's 53C710 SCRIPTS engine
  carried to the 810) and `IBMRS6K7248_scsitgt.sv` (the 715's byte-level
  targets, not MacPPC7300's signal-level ones: no PHY needed, and the two
  are proven together under HP-UX; a dual-clock buffer for hps_io); disks
  at IDs 0 and 1, the CD-ROM at 3; the bench serves images (`--disk0`,
  `--disk1`, `--cd`). First run on the bench under way.
- Fire Coral's EIDE (1F0/170) if a boot path needs it.

- The Main side (the user's direction, 2026-10-17): a new branch of
  Main_MiSTer cut from `master` for this core (not one of the other
  families' branches), with a self-contained `support/ibmrs6k/` as the
  HP 9000 family has `support/hp9k/` (Main_MiSTer `origin/hp9k-family`):
  the hard-disk write buffer (Sun's `support/sun/sun_disk.cpp`, as
  `hp9k_disk.cpp` copied it: sectors gathered into runs of up to 64 KB,
  written after 20 ms idle or 500 ms at most, reads flushing what they
  overlap), the multi-block reads and tight service loop of
  `origin/fast-mac-scsi`, a CD-ROM layer as `hp9k_cdrom.cpp` /
  `mac_cdrom`, and only small hooks in `support.h` and `user_io.cpp`.
  The FPGA side keeps to the same contracts as the 715's targets (8-bit
  hps_io here; the CD's track table from the block at C000_0000 when the
  Main serves one, as `support/hp9k` does).

### M6 AIX

The AIX 4.3.3 install CD (volume 1) first, then AIX 5.1. **Not the 4.3.3.3
standalone diagnostics CD**: its `rc.boot` requires `bootinfo -M` = 101/103,
which a real 7248 with firmware 1.12 does not give either (the model code
0x0803004C from "IBM PPS Model 7248 (E)"); it ejects and reboots on the
7248 by design (2026-10-18). Residual data and the time base frequency as
the firmware reports them; the NVRAM and the VPD EEPROM as the core now
supplies them (`docs/stubbed-hardware.md`).

### M7 The rest of the board

PCnet (Am79C970) with MacPPC7300's Ethernet bridge (its frames through
rings in DDR3) and, on the Main branch of M5, an Ethernet mailbox as
`support/hp9k/hp9k_enet.cpp` (magic string, RX slots, the OSD's
interface bits), CS4232 audio, the
L2 cache (the MPC105's, 256/512 KB), the model option (planar IDs F0-F7:
7248-100/120/132, Power Series 830/850), interrupts on IRQ15 shared.

## Speed (the techniques of the other cores)

- The L2 cache: MacPPC7300's `MacPPC7300_l2` (128 KB, between the
  machine's memory port and the clock crossing: 2-3 % CPU, 11 % disk,
  6-10 % graphics there) stands in for the 7248's own L2 (the MPC105's,
  256/512 KB); the firmware's L2 probing (ports 080C/0814/081C, PICR1/2)
  then reports what the core has.
- The device path from a register (MacPPC7300 build 29) is already this
  machine's shape (`IBMRS6K7248_machine`: devices answer from a registered
  copy of the request).
- On the Main side, the family branch's disk write buffer and fast SCSI
  service loop (M5).
- The CPU's own speed work stays in MacPPC7300 and comes over with the
  CPU.

## Little-endian mode (separate track)

**Status (2026-10-17): built and passing here.** The CPU half
(`DSPPC604`, `LE_MODE`) and the bridge half (`IBMRS6K7248_machine`: the
MPC105's PICR1 bit 5 swapping each doubleword's byte lanes) pass
`sim/tests/le_test.rom` and `le_test_dc.rom` (`docs/bringup_log.md`).
The CPU change as a patch against MacPPC7300's tree:
`docs/cpu_patches/0001-DSPPC604-little-endian-mode.patch` (applies to
MacPPC7300 `21ba191`). With it, at `LE_MODE = 0`, MacPPC7300's suites
pass: the real-604 golden vectors (`run.py`) and the pipeline suite
(`run_core.py`: every directed test and 1,071,506 random instructions in
lockstep with dingusppc `3f070249`); the logs are beside the patch. The
resume prompt for taking it into MacPPC7300 is that repository's
`RESUME_le_mode.md` (2026-10-17).

The original estimate follows.

AIX does not need it. Windows NT 3.51/4.0, OS/2 Warp PPC and Solaris 2.5.1
PPC run little-endian and do; so do the NT ARC boot loaders in scratch.

What the 604 does in little-endian mode (MSR[LE] = 1), and what is missing
from DSPPC604 today:

| Piece | 604 behaviour | DSPPC604 today | Work |
|---|---|---|---|
| Exceptions | MSR[LE] takes MSR[ILE] on every exception | done (`msr_exc`) | none |
| Instruction fetch | the fetch address's bit 29 inverted (EA XOR 4) | not done | one XOR at `if_addr` (DSPPC604.sv:573); SRR0 and branch targets stay unmunged |
| Loads and stores | the effective address munged: XOR 7 for a byte, 6 for a halfword, 4 for a word, 0 for a double | not done | one XOR on the memory unit's request address (DSPPC604.sv:2834), by size; `lwbrx`/`stwbrx` unchanged |
| Alignment | misaligned halfword/word/double accesses, `lmw`/`stmw`, the string instructions and `dcbz`... take an alignment exception in LE mode (the 604 manual's table) | the BE rules only | extend `x_align_w`/`x_align_s` with MSR[LE] |
| DAR, DSISR | the unmunged EA in DAR | - | check where DAR is taken |
| The bridge | MPC105 PICR1 LE bit (and PReP port 92 bit 1): byte-lane swap and address unmunging for PCI/ISA accesses; how memory is seen to be checked in the MPC105 manual | - | in the MPC105 model, after M1 |

Effort:

- **CPU: about 1-2 working sessions**, done here in this core's copy of
  DSPPC604 behind a parameter (`LE_MODE`, 1 here, 0 in MacPPC7300) so the
  Mac build pays nothing, then taken back to MacPPC7300 (below). 100-300 lines with directed tests. The risk is timing,
  not logic: the XORs sit on the fetch and data-address paths, which
  are the critical paths at 100 MHz, though only on the low three bits
  (below the caches' set index).
- **Verification: the long pole.** dingusppc (the lockstep reference)
  has no LE mode; QEMU does LE as a true byte swap, not munging, so it
  differs on misaligned and cached-mode-switch cases. Best reference:
  record LE vectors on the user's real 604 (the 7300) with
  MacPPC7300's `ppctest` harness, if it can run LE code there.
- **Bridge: about half a session** once the MPC105 model exists.
- **NT itself: weeks**, but not because of LE. It also needs the S3
  (its HAL and display driver), IDE or the 53C810, the 8259s, the NVRAM
  and an ARC environment (open question: does the 7248's ROM boot NT
  directly, or through one of the ARC loaders in `scratch/`?).

So: LE can come any time after M1 (the bridge's half needs the MPC105),
and is best done before M4 ends so NT can be tried as the devices land.

## Decisions

- The CPU is MacPPC7300's DSPPC604, imported at `21ba191`. Little-endian
  mode is added here (the user's decision, 2026-10-17) behind a parameter
  (`LE_MODE`; 0 leaves the CPU as it was), then carried back to
  MacPPC7300 as a patch of `rtl/DSPPC604/` since the import, not a copy
  of the files, so changes made there meanwhile survive. Before it counts
  as done there, MacPPC7300's CPU suites (`verilator/run.py`,
  `run_core.py`: the real-604 vectors and the dingusppc lockstep) pass
  with `LE_MODE = 0`. Other CPU fixes follow the same path, whichever
  core finds them.
- 100 MHz CPU clock.
- Real hardware outranks every emulator; of the emulators, QEMU's PReP
  devices and MAME's chips are references, none models this board.
- The Verilator build uses 2 jobs (`sim/Makefile`, JOBS): more ran the
  14 GB build machine out of memory.

## Open questions

- PCI device numbers of the on-board S3 and PCnet, and the PCI interrupt
  routing (firmware tables, next disassembly pass).
- Ports 0680, 08C0/08C1 (progress) and 4690/4691: what hardware they are.
- The MPC105's little-endian behaviour toward memory (its manual).
- How Windows NT boots on the 7248 (the ROM, or an ARC loader).
- Where firmware 1.11 (P93H4940.IMG, CRC-32 7C987E45) can be found
  unencrypted; whether v1.12 "test" has any defects that matter.
