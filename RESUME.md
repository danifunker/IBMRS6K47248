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

## Where it stands (2026-10-17)

- **M0-M2 done on the bench**: the v1.12 ROM runs from reset through the
  recovery block (MPC105 memory sizing, the CS4232's Crystal-key set-up,
  the main block's CRC), the main block (RAM test, LZW decompression) to
  `main_control` at clock 520 M, then the 8259s, RTC, 8042, debugger, file
  system, the serial-port monitor and the serial console (VT100 on COM1),
  to `diskette_init` (B1).
- **Little-endian mode**: done and verified (`sim/tests/le_test*.rom`; with
  MacPPC7300's golden vectors and `run_core.py` lockstep at LE_MODE = 0).
  The patch and the resume prompt for MacPPC7300 are written
  (`docs/cpu_patches/`, `../MacPPC7300_MiSTer/RESUME_le_mode.md`, the latter
  left uncommitted there).
- **The floppy controller** (drive empty) passes `diskette_init` (B1) in
  1.3 M instructions.
- **M4 (S3) phase 1 works on the bench**: the firmware's S3 driver draws
  its start-up screen (PowerPC logo, the POST icons, then the error
  triangle with 00017006: the console named in the blank NVRAM not found)
  and idles at progress 7B around clock 950 M. Picture:
  `docs/images/first_screen_powerpc_logo.png`; details in
  `docs/bringup_log.md` (the last section).
- **M5 phase 1 (the 53C810) runs on the bench**: `rtl/machine/IBMRS6K7248_ncr810.sv`
  (the HP 9000/715 core's 53C710 SCRIPTS engine carried to the 810),
  `IBMRS6K7248_scsitgt.sv` (the 715's targets with a dual-clock hps
  buffer), PCI I/O decode, DMA through the CPU's snoop port, IRQ 15; the
  bench's `--disk0/--disk1/--cd` image server and `--io-range LO:HI`; the
  top's three hps_io slots. First run (`docs/bringup_log.md`, last
  section): the driver opens the adapter (SCRIPTS self-test, selection
  timeouts all work), the scan runs to its end (a new progress 98 at ID 3,
  probably the CD's INQUIRY), then a new progress CB, and the firmware idles
  at 7B with 00017006 as before. **The CD image was never read.**
  **Next check**: rerun from the `main_control` snapshot with
  `--cd scratch/downloads/fsck.technology/diag/AIX_4.3.3.3_RS6000_standalone_diagnostics.iso
  --io-range A0000000:A00000FF` (and `--watch 9C27C` ncr_execute) to clock
  ~1,300 M and see which commands go to ID 3; find what 98 and CB mean;
  then make the firmware boot it (a boot list in NVRAM, or its menus).
  `docs/scsi_design.md` sections 1.5-1.10 are the checklist.
- Then: the Main_MiSTer branch (ask first), M6 (AIX), M7 (PCnet, CS4232
  sound, the L2, the model option). Not yet done: a Quartus fit (the top
  compiles only in the bench's subset so far: the first fit is due).

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

The repository has no remote yet (everything is committed locally). Take it
with `git bundle create ibmrs6k7248.bundle --all` and `git clone
ibmrs6k7248.bundle IBMRS6K42p` on the other side, or push it to a new
GitHub repository of the user's (ask before creating or pushing). Not in
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
