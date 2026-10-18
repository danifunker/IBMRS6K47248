# Resume prompt: IBMRS6K7248 (IBM RS/6000 43P 7248) MiSTer core

(Written 2026-10-17 by the first development session, on the Linux machine
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

## Where it stands (2026-10-17 late evening, the end of the second session)

Read `docs/bringup_log.md`'s last six sections first: they are the day. The
two open problems, in the order to take them:

### A. The board's sizing halt: SOLVED (2026-10-17 late night)

The MiSTer SDRAM boards wire the chip's DQMH/DQML to A12/A11; the
controller put zeros there in WRITEs, so every word write stored all four
bytes and the main block's byte-store test (FFF15630, run from RAM 0 by the
sizing FFF15490) failed on every bank. Fixed in `IBMRS6K7248_sdram.sv`
(commit "sdram: the write byte masks on A12-A11"); the SDRAM bench now takes
DQM from A12-A11 and reproduces the old halt. **The board now reaches the
same boot screen as the bench** (the drive icon and the SMS diskette). The
codes 23/24/22 mean "slot empty" / "error: switch off the lowest bank" /
"no bank left" (`docs/bringup_log.md`, the last two sections). MacPPC7300
has the same omission: `docs/cpu_patches/sdram_dqm_on_a12_a11.patch` (not
applied there; tell the user). Board tools: `scratch/work/stage.sh`, then
`scratch/work/capture.sh OUT SECS` (loads the core, captures the debug UART
into `scratch/work/OUT`); `scratch/work/ppcdis.py A B` disassembles the ROM.
The debug UART also logs the RAM test's PCs (`Ppppppppp-xxx`).

### B. The firmware boots to a screen and waits (now the first problem, board and bench)

- With the CD at ID 3 the scan's INQUIRY is good (progress 98), LUN 1 too.
- After 00017006 the firmware sleeps 3 s on the timebase (`sleep(3,1)` in
  `text_errormsg_tr`; the "idle at 7B" of every earlier run), then
  `cold_boot_path` goes on: D2, D4, DE, FE (word FF007BFE), a boot screen (a
  drive icon and the "System Management Services" diskette,
  `docs/images/boot_screen_sms_diskette.png`) and **a wait**: `rxchar`
  (1A204) polls COM1's LSR, and the hot loop is loaded code at 0x20D9F4-
  0x20DA08 (a countdown calling a service through 0x208D74, with an `out16`
  each time: which port was being logged at the end, `run_wait_io.txt`,
  `scratch/work/run_wait_io.sh`). Enter, F1, F4, F5, F6, ESC (PS/2) with
  CR/"1"/"4"/"5"/"6"/ESC on COM1 changed nothing (`scratch/work/run_key2.sh`,
  `run_key_*.txt`, `frame_key_*.ppm`). No SCSI command after the scan.
  Next: find what the loop waits for (the port; a diskette? a timeout on the
  timebase: a `TB_FAST` knob like `RTC_FAST` would shorten it); then the boot
  list (diskette first by default: the empty drive; then "SCSI CDROM").
- Bench tools made today: `RTC_FAST` (the RTC's seconds 64 x faster, on by
  default), `--key-at CLOCK:CODE[:e]`, `--com1-at CLOCK:BYTE`, `--pcs-from`,
  `--cpu-mhz/--mem-mhz`, `make machine_sd`; `scratch/work/pcs_path.py` maps a
  `--pcs` trace to the firmware's symbols; `sizing_path.py` to the sizing's
  blocks. Snapshots (`~/ibmrs6k/` in WSL, the `build3` binary = RTC_FAST):
  `snap3_mc.bin` (main_control, clock 520,051,476), `snap3_cbp.bin`
  (cold_boot_path with the CD, clock 1,232,285,474); the wait begins about
  322 M clocks after it.

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
- The board: `ssh -i ~/mister_key root@192.168.99.92` from WSL;
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
