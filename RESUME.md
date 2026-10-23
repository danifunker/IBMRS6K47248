# Resume prompt: IBMRS6K7248 (IBM RS/6000 43P 7248) MiSTer core

(Written 2026-10-17 by the first development session, last updated 2026-10-18 night by the fifth, on the Linux machine
`m900` (15 GB, 6 cores), for continuing here or on another computer. It is
the only resume prompt for this core; everything it needs is here or in
the files it names. MacPPC7300 has its own, `RESUME_le_mode.md`, for the
CPU change that goes back there.)

Paste everything below the line into a new session started in this
repository.

---

## What this is

A MiSTer core for the IBM RS/6000 43P model 7248 ("Carolina", a PReP
board: PowerPC 604, Motorola MPC105 host bridge, IBM Fire Coral PCI-ISA
bridge, PC87312 Super I/O, S3 Vision864, NCR 53C810, CS4232), and the same
board's IBM Power Series 830/850 (one firmware, told apart by the planar ID
at port 0852). Goal: the machine's own firmware, then AIX 4.3.3 and 5.1;
later Windows NT/OS/2 (little-endian mode, already done).

Read first, in this order: `Readme.md` (state, decisions, the bench),
`docs/plan.md` (milestones M0-M7, little-endian mode, the speed techniques,
the Main_MiSTer branch for SCSI/Ethernet), `docs/bringup_log.md` (what the
firmware does on the core, run by run: the most recent sections are where
things stand), then as needed `docs/hardware_inventory.md` (with Linux's
Carolina tables in Appendix B), `docs/firmware_analysis.md`,
`docs/s3_design.md`, `docs/scsi_design.md` (if present: a research agent
was writing it when this prompt was written), `docs/emulators_and_software.md`.

The user's standing instructions (also in the memory files of the first
machine):
- Work independently; the user may be away (MiSTer boards at a show):
  the Verilator bench is the test bed, not the board.
- **Commit before every build** (a rollback point), and commit regularly.
- CPU changes are made here behind a parameter and carried to MacPPC7300 as
  a patch (`docs/cpu_patches/`), verified there with its own suites.
- SCSI and network need a new Main_MiSTer branch cut from `master`
  (`support/ibmrs6k/`, reusing the disk write buffer, fast SCSI service loop
  and Ethernet mailbox of the user's other family branches): `docs/plan.md` M5/M7.

## Where it stands (2026-10-18 night, the end of the fifth session)

Read first: `docs/plan.md` ("Priorities": SCSI, then video, then the rest),
`docs/stubbed-hardware.md` (every device, the core's state of each, the
plan per device: keep it current with every stub a run finds), and the
bringup log's four "2026-10-18" sections from "afternoon" on.

### What was settled today

- **The diagnostics CD rejects the 7248 by design.** The 3-minute re-boot
  cycle was its own `rc.boot`: `bootinfo -M` must return 101/103 and returns
  100 on a real 7248 with firmware 1.12 as well (the model code 0x0803004C
  comes from the firmware's fixed "IBM PPS Model 7248 (E)" through the CD's
  PReP loader; only an 'A' or 'D' machine passes). The core reproduced a real
  machine. **The medium is the AIX 4.3.3 install CD (volume 1)**:
  `scratch/downloads/fsck.technology/aix433/LCD4_0286_07_VOLUME1.ISO` (MD5
  verified), on the board as `/media/fat/games/IBMRS6K7248/`, MGL
  `scratch/work/ibm_cd433.mgl`, scripts `capture_cd433.sh` /
  `com1_listen433.sh` (OUT SECS BAUD CFG0), `board433.sh`.
- **Hardware added**: the NVRAM starts with the firmware's own formatted image
  (`firmware/tools/nvram_image.py` -> the marked block in `IBMRS6K7248_rtc.sv`);
  the VPD EEPROM's controller at 78-7C (`IBMRS6K7248_eeprom.sv`, image by
  `firmware/tools/eeprom_image.py`: the CRC word, a 16-digit serial, no
  passwords: inferred, no real dump exists); the IDE ports answer FF. The
  RTC's time comes from Main (hps_io); NVRAM/CMOS persistence across core
  loads belongs to the Main_MiSTer branch.
- **The install CD on the board** (bitstream `ba84bca`): the kernel and user
  space run, no re-boot, but about a minute in, `rc.boot`'s shell sits in
  `loopled`'s `while :` forever (a step failed before any device was
  touched: no device access after user start at all). COM1 is **not silent**:
  202 bytes in 15 minutes, garbled by a rate mismatch of ~1.43 (`aix433_com1.raw`;
  the UART's clock parameters are right): AIX does write something, 100-odd
  characters, before the loop. **These two are the first problems now.**

### What to do first (before the priorities)

**Update 2026-10-23: all three are settled** (`docs/bringup_log.md`, the 2026-10-23 sections):
COM1 carries no text (AIX programs 9600 8N1 and never writes it), the Serial reaches the
residual data, and the failing step is the `/SPOT` mount (LED 0x518) because AIX's SCSI scan
finds no `cd0`. **Next is SCSI (M5)**, starting from build10's snapshots `snap24_a.bin`
(clock 4.45 G, before the scan's waits) and `snap25_b.bin` (in the loop). The list below is
kept for its methods.

The user confirmed this order on 2026-10-22 (`docs/plan.md` "Priorities",
item 0): the three install-CD blockers below (COM1's rate, the failing
`rc.boot` step, the Serial check), then SCSI, video, the rest.

0. Read COM1: on the bench boot the install CD from `snap20_mc.bin` with
   `--com1` (exact bytes, any rate) and `--io-range 800003F8:800003FF`
   (the divisor AIX programs); then record the board at the matching rate
   (`com1_listen433.sh OUT SECS BAUD 10`). The text may name the failed step.
1. Find the failed `rc.boot` step. The script is at `ramfs_vol1.img`
   0x157000-0x160000 (`ramfs_boot.py` inflates a boot image's RAM disk; the
   install RAM disk has 1171 pages). The order: restbase, `cfgmgr -f`,
   `bootinfo -b`/`-t`, the ipldevice, the `/SPOT` mount. Ways in: (a) the
   bench: from `snap20_mc.bin` (build8, RTC_FAST) with `--cd` the install
   ISO, `--calls` from the first user exec and `--daddr` to see which
   programs run and what they open (`scratch/work/calls_user.py` names the
   kernel calls; the snapshot's RAM lags the write-back cache); (b) the
   board: the debug UART's one-shot capture retargeted (IBMRS6K7248.sv,
   `isi_go`) to the shell's loop PC 10020638 or to `loopled`'s `showled`
   path, to read the LED code (the capture logs LR, CTR, MSR and 40
   instructions with their GPR writes); (c) `showled` on rspc may write the
   code through the kernel's NVRAM driver: watch ports 74/76.
2. (NvramSize = 0x1000 is verified: the NVRAM image works; the firmware
   boots through the EEPROM model with no lock path.) Verify the Serial: the
   NVRAM image's header carries the EEPROM image's serial since `bf5f755`,
   which build8 predates, so this needs a new bench build (and a new
   `main_control` snapshot) or a board run. `run20.sh` (bench) snapshots at the decompressor (`snap20_lzw.bin` -> `ram20.bin`);
   the residual at 0x1FF6974: NvramSize at +0x78 (4096, not -1), Serial at
   +0x28 (the image's digits, not "ffff..."), and no password/lock prompt in
   the firmware's progress codes. Adjust `eeprom_image.py` to what the
   firmware's readers want.
3. Then the priorities: SCSI (M5), video (M4 under AIX), the rest.

### Lessons of the day (to save time)

- `pkill -f PATTERN` from a `wsl -- bash -lc '...'` whose command line
  contains PATTERN kills the caller first: put kills in a script file whose
  name does not match (`restart8.sh` style).
- A generator that rewrites an RTL file must find its markers or fail; one
  overwrote `_rtc.sv` and the clobbered file got committed (`d183558`): check
  `wc -l` before committing generated edits.
- The bench's `--io-range` only filters; `--io` enables the printing.
- The debug UART's one-shot capture is a PC trigger now (`isi_go`): one build
  per question, 36 minutes; choose the PC with the LR in mind.
- The model-code chase: `cfgsys_rspc` <- `/dev/nvram` ioctl 0xE (the IPL
  control block's system-info area, +0x34) <- the CD's PReP loader
  (`aixmon`, `prep_boot.bin` file 0x430, runtime +0x4BD0, TOC 0xFD7C) <- the
  residual's PrintableModel. Tools: `scratch/work/aix/` (the diag RAM disk
  `ramfs.img`, `ramfs_vol1.img`, `bootinfo_rspc.xcoff`, `rc.boot.sh`).

**Lessons from this session (to save time):** the debug UART's queue is 4 KB
and drops events when full, so a burst (page faults: thousands a second)
hides later events; filter at the source. The exception log's vector field is
12 bits (0x1400 looked like 0x400). A PC logged before an exception is the
last instruction that *retired*: the faulting one is usually the next.
A per-page fault repeating at one PC can be a loop over pages, not a hang:
check the data addresses or the call tree before calling it stuck.

The OSD's RAM menu now lists sizes (32, 48, 56, 64, 96, 112 MB, then 16, 24;
32 the default): commit 63d6756, bitstream being built at the end of the
session. The core's options on the board are in `/media/fat/config/IBMRS6K7248.CFG`
(byte 0: bits 3-1 the RAM entry, bit 4 the UART: 1 = COM1).

### The rest

- The first Quartus fits: 100 MHz misses by 6.2 ns, 70 MHz by 1.8-2.6 ns
  (the CPU's paths). **The CPU is MacPPC7300's master as it stands** (only
  the LE patch differs; MacPPC7300 runs at 70, not 100). The top is at 70
  (`CPU_MHZ`; the PLL has a 50 MHz counter too: a diagnostic only, the user
  wants the core faster, never slower). 80-82 % of the ALMs.
- Then: the Main_MiSTer branch (ask first), M6 (AIX), M7; the EEPROM at
  78-7C (stubbed) and the NVRAM's configuration.

## On this machine (Windows 11, 32 GB, 20 cores)

- The bench builds in WSL Ubuntu-24.04 (user dani): the distro's Verilator
  5.020 is too old; use `make machine_tb VERILATOR=/home/dani/oss-cad-suite/bin/verilator
  BUILD=/home/dani/ibmrs6k/build3 JOBS=4` from `/mnt/c/Temp/mistercore/IBMRS6K47248/sim`
  (objects on the ext4 disk; `make` with the systemd cap fails from a plain
  `wsl -- bash`). Long runs: `setsid nohup bash /mnt/c/.../scratch/work/X.sh &`
  inside `wsl -d Ubuntu-24.04 -- bash -lc '...'` (a `$var` in that string is
  eaten: keep commands in script files). Snapshots: `~/ibmrs6k/snap3_mc.bin`
  (main_control, the RTC_FAST build `build3`), `snap3_cbp.bin` (cold_boot_path,
  with the CD, if the run finished); `build`/`snap_mc.bin`/`snap_cbp.bin` are
  the earlier build without RTC_FAST.
- Quartus 17.0 Lite: `C:\intelFPGA_lite.0\quartusin64\quartus_sh --flow compile IBMRS6K7248`
  from the repo (16-17 minutes; the first error list is in the bringup log:
  Quartus 17 misreads `N'(int)` casts as signed, needs `genvar` declared
  before `generate`, cannot slice a concatenation).
- The board: **use 192.168.99.92** (MiSTer-SS1; the user, 2026-10-23: .143 is
  the PPC_Mac/Sun sessions' board). Ask before replacing a running core there, do
  not write .CFG files over SSH on .92, and stage with `scratch/work/stage92.sh`
  (some older scripts still name .143). `ssh -i ~/mister_key root@192.168.99.92` from WSL;
  `scratch/work/stage.sh` copies the rbf, boot.rom and the ISO; `echo
  load_core /media/fat/_Computer/IBMRS6K7248.rbf > /dev/MiSTer_cmd`; the
  screen through the MiSTerKVMS capture server on this PC
  (`scratch/work/grab.py MiSTer-SS1 out.jpg`); keys through mrext
  (`POST http://192.168.99.92:8182/api/controls/keyboard-raw/<linux keycode>`);
  the debug UART: on the board `stty -F /dev/ttyS1 115200 raw -echo; (timeout 30 cat /dev/ttyS1 > /tmp/x.raw) & sleep 1; echo load_core ... > /dev/MiSTer_cmd; sleep 32; tr -d '\000' < /tmp/x.raw | grep -o -a 'R.\{0,1600\}'`
  (the ssh heredoc must not share stdin with stage.sh: run them in separate calls).
- Long WSL runs: `setsid nohup bash /mnt/c/.../scratch/work/X.sh args > /dev/null 2>&1 &`
  inside `wsl -d Ubuntu-24.04 -- bash -lc '...'`; a `$var` or `pkill -f` pattern in that
  string is eaten or self-matching: keep commands in script files, poll with a watch script.

## The bench (sim/)

```
cd sim
make                      # inside a memory-capped systemd scope (MEM=7G, JOBS=2); ~5-15 min
make TRACE=1              # a waveform-capable bench in build_trace/ (--fst, tools/fst2vcd, tools/vcdq.py)
./build/machine_tb --help
# from reset, saving a snapshot at main_control (520 M clocks, ~25 min):
./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8 --lat 1 \
    --cycles 2500000000 --stall 0 --beat 50000000 --save ../scratch/work/snap_mc.bin \
    --com1 ../scratch/work/com1.raw --vram ../scratch/work/vram.bin --frame ../scratch/work/frame.ppm
# later runs from the snapshot (same build only):
./build/machine_tb --rom ... --ram 8 --lat 1 --restore ../scratch/work/snap_mc.bin --cycles ...
python3 tools/vt.py ../scratch/work/com1.raw      # the serial console's screen
make -C tests && ./build/machine_tb --rom tests/le_test.rom --ram 8   # LE PASS
```

The firmware's progress codes (port 680) print as they come; the
`main_control` checkpoints are mapped in `docs/bringup_log.md`. The bench's
serial ports run at the clock / 16 (`UART_FAST`, bench only).

## Memory: why builds were killed on m900, and what was done

The CPU's Verilator model compiles into two 45-50 MB C++ files (about
2.5 GB of g++ each). On m900 (15 GB, `/tmp` a RAM-backed tmpfs shared with
other sessions' scratch areas, swap full, other sessions running Quartus),
uncapped `-j 4`/`-j 0` builds took the whole session down twice. Now:
`make` runs in `systemd-run --user --scope -p MemoryMax=$(MEM)` (contained:
only the build is killed), generate-then-compile (Verilator exits before
g++), `-j 2`, ccache, `GCC_MEM` (g++ collects garbage more often: measured
in `scratch/work/build_gccmem.txt`), big files on disk in `scratch/work/`,
never in `/tmp`. **On another machine**: if it has 32 GB or more, `MEM`,
`JOBS` and `GCC_MEM` can be relaxed (`make MEM=16G JOBS=4 GCC_MEM=`). If it is
Windows with WSL (as MacPPC7300's), `systemd-run --user` may not exist
there: build with `make machine_tb` (no cap) and keep `JOBS` modest.

## Moving to another computer

**Snapshots are tied to the build that made them**: on a new machine, build,
then make a fresh `main_control` snapshot from reset (the `--save` command
above, ~25 min) before the SCSI runs. **Disk**: m900's root filled up
(233 GB, 0 free) during these runs, which broke a relink; a run writes
little, but a build needs ~1 GB free.

The repository is on GitHub: `git clone
https://github.com/danifunker/IBMRS6K47248.git IBMRS6K42p` (branch
`master`; its history was rewritten once to drop a committed build
directory, so discard any clone made before that). Not in
git (`.gitignore`): `scratch/` (the manuals and firmware archives in
`scratch/IBMPowerPC/`, the downloaded AIX 4.3.3 volume 1 and 5.1 disc 1
ISOs and the diagnostics CD in `scratch/downloads/` with their sources and
md5s listed in `docs/emulators_and_software.md`, `scratch/work/`: bench
outputs, snapshots, the MacPPC7300 check copy and dingusppc), and every
build directory. Copy `scratch/` if convenient (1.4 GB), else re-download as
needed. The sibling repositories this core reads: `../MacPPC7300_MiSTer`
(the CPU's home), `../Template_MiSTer`, `../Main_MiSTer` (do not modify
other sessions' branches there), `../qemu` and `../mame` (references).
Tools: Verilator 5.028 (5.020 works for MacPPC7300; this bench adds
-Wno-SYMRSVDWORD), powerpc-linux-gnu binutils (the LE test ROMs), Python 3,
ccache; Quartus 17.0 Lite for the bitstream (never fitted yet: the first
fit is due once M4 runs on the bench; expect the CPU near 90 % of the
DE10-Nano as in MacPPC7300).
