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

## Where it stands (2026-10-18 afternoon, the end of the fourth session)

Read `docs/bringup_log.md`'s last four sections first. **The board is now
.143** (the user, 2026-10-18: "use .143 now, do not use .92 until I tell you
otherwise"); the scratch/work board scripts point there.

### Done today
- **The CMOS**: a blank CMOS fails its CRCs, `init_cmos` sets the
  "CMOS was reset" bit (1F bit 5), and with it BOOT.6XE (the VDISK's boot
  program, run by `main_control` as "boot 0") gives up: the no-bootable-media
  screen. The RTC now starts with `init_cmos`'s image, bit clear
  (`firmware/tools/cmos_image.py`). **The firmware then boots the CD** (board
  and bench): the PReP partition loads, `2F AD` (the hand-off), the AIX boot
  program decompresses the kernel (`firmware/tools/unz.py`), the kernel runs,
  fills its RAM disk (each `copypage` takes a demand fault: normal), loads
  kernel extensions and **starts init in user space** (faults at 10000188 /
  2009464C on the board).
- **The AIX kernel's full disassembly**: `scratch/work/aix/kernel.s` (3,692
  functions named from traceback tables; not in git). `scratch/work/aix_unz.bin`
  is the decompressed kernel XCOFF; `prep_boot.bin` the CD's boot partition.
- **Board tools**: `scratch/work/capture_cd.sh OUT SECS` loads the core with
  the ISO on S2 (through `scratch/work/ibm_cd.mgl`) and records the debug
  UART; `listen.sh` records without reloading; `com1_listen.sh` sets the OSD
  UART to COM1 (`/media/fat/config/IBMRS6K7248.CFG` byte 0 = 0x14; 0x04 =
  debug UART with 32 MB) and records COM1. The debug UART now logs the
  exceptions (`Pfrom-vec`, vectors 100-800 and F00), progress codes written
  from outside `out32le` with their PC, port 92, a one-shot capture (LR, CTR,
  MSR and 40 instructions with their GPR writes) at a chosen exception, the
  first 250 device accesses after user code starts, and `.pppppppp` (the PC)
  every 2^24 instructions.
- **Bench**: `--calls`, `--exc`, the SCSI image reads logged. Snapshots
  (32 MB, the CD, the CMOS fix; `build5` and `build6` restore them):
  `snap5_mc32.bin` (main_control), `snap7_lzw.bin` (the decompressor, instr
  809.7 M), `snap8_pcopy.bin` (copypage's first call, 1,178.76 M),
  `snap10_user.bin` (init's first instruction, 1,324.0 M). build6 is built
  with the build5-era `rtl/machine/IBMRS6K7248_system.sv` (the board's extra
  trace ports change the model's snapshot layout: build the bench from that
  file's 6451968 version to keep using these snapshots).

### Open: the diagnostics CD rejects the machine (the first problem now)

Read the bringup log's "2026-10-18 afternoon" section and
`docs/stubbed-hardware.md` ("The blocker today"). In short: AIX boots, runs
`cfgmgr -f`, then `rc.boot` (the CD's own script, `scratch/work/aix/rc.boot.sh`)
runs `bootinfo -M`; it must return 101 or 103 ("supports diagnostics") and
returns 100 because `sys0`'s `modelcode` has bits 2-3 clear; so the script
ejects the CD and calls `reboot(0)`, the firmware re-boots the CD, every ~3
minutes. Nothing touches a device in user space before that; COM1 would be
the console (the CD has no S3 driver) once the check passes. To do, in order:
1. Pin the source of `modelcode`: `cfgsys_rspc` (`ramfs.img` 0x63C000) fills a
   global system-info structure (TOC[0xd0]) in its routine at 0x10001118 from
   `/dev/nvram` ioctls; field +0x34 is the code. Candidates: the IPL control
   block's system-info area (built by the CD's boot program, `prep_boot.bin`
   XCOFF at 0x12C00, from the residual data: the PrintableModel string, the
   planar PnP ID IBM0005, or the VPD), or the NVRAM. Then make the core supply
   it: a real VPD EEPROM at 78-7C with a 7248-100 image and/or an NVRAM with a
   valid PReP header (the firmware's `nvram_good`: byte 2 = 1, byte 3 = 4).
2. Then the SCSI CD under AIX's `ncr810dd`, the tty on S1, `cfgcon`, and the
   diagnostics' console prompt on COM1 (`com1_listen.sh`).
3. Keep `docs/stubbed-hardware.md` current with every stub a run finds.

In flight at the end of the session: `run19.sh` (build7, from
`snap10_user.bin`, ~8 hours): `--watch` on the kernel's reboot entries and a
snapshot at the `reboot` syscall 3D830 (`snap12_reboot.bin`); its RAM would
hold the console messages ("INIT: ...", the commands' errors) and the ODM.

**Lessons from this session (to save time):** the debug UART's queue is 4 KB
and drops events when full, so a burst (page faults: thousands a second)
hides later events; filter at the source. The exception log's vector field is
12 bits (0x1400 looked like 0x400). A PC logged before an exception is the
last instruction that *retired*: the faulting one is usually the next.
A per-page fault repeating at one PC can be a loop over pages, not a hang:
check the data addresses or the call tree before calling it stuck.

The OSD's RAM menu now lists sizes (32, 48, 56, 64, 96, 112 MB, then 16, 24;
32 the default): commit 63d6756, bitstream being built at the end of the
session. The core's options on .143 are in `/media/fat/config/IBMRS6K7248.CFG`
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
