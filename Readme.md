# IBMRS6K7248 (IBM RS/6000 43P 7248) for MiSTer

A core for the [MiSTer](https://github.com/MiSTer-devel) FPGA platform
modelling the IBM RS/6000 43P model 7248, IBM's "Carolina" PReP workstation
(the board family of the IBM Power Series 830/850). The goal is the
machine's own firmware (SMS) running, then AIX 4.3.3 and AIX 5.1.

Work in progress: just started (2026-10-16).

## Status

| Piece | State |
|---|---|
| Project skeleton | Template_MiSTer `5dda373` (2026-10-16), renamed `IBMRS6K7248`; `sys/` unmodified |
| CPU | `DSPPC604` from MacPPC7300_MiSTer `21ba191` (2026-10-16; `rtl/DSPPC604/`): a 32-bit PowerPC 604-class core, verified against a real 604 there; plus little-endian mode behind `LE_MODE` (1 here), the one change so far (`docs/cpu_patches/`) |
| Clock | CPU and machine 100 MHz, SDRAM 100 MHz: MacPPC7300's PLL in its 100 MHz-only form |
| SDRAM controller | MacPPC7300's (`rtl/machine/IBMRS6K7248_sdram.sv`, renamed only); the ROM in the board's top 4 MB, RAM below it |
| Machine | `rtl/machine/`: the PReP map; the MPC105 (configuration, the RAM banks as SIMM pairs, the little-endian byte-lane swap); Fire Coral's configuration; the 8259s, the 8254, the RTC and 4 KB NVRAM, the 8042 with a PS/2 keyboard and mouse, the PC87312 (COM1 on the MiSTer's UART, COM2, the parallel port), a silent CS4232; the planar ID (F5, a 7248-100). The rest is a logged stub |
| Firmware | v1.12 on the bench: through the recovery block (memory sizing, the CS4232, the main block's CRC) into the main block, to its RAM test (`docs/bringup_log.md`) |
| Bench | `sim/`: Verilator, the whole machine from the reset vector on a ROM image, COM1's output and every stubbed device access logged |
| Video, SCSI, floppy, Ethernet, sound | not yet: `docs/plan.md` |

## Documents

- `docs/hardware_inventory.md`: the machine's hardware, from the service
  manuals and handbooks in `scratch/`
- `docs/firmware_analysis.md`: the firmware images and their disassembly
  (`firmware/`)
- `docs/emulators_and_software.md`: other emulators of this and related
  machines, and where the operating systems are
- `docs/bringup_log.md`: what the firmware does on the core, run by run
- `docs/plan.md`: the milestones, little-endian mode, the speed techniques,
  the Main_MiSTer branch for SCSI and Ethernet

## Decisions

- MiSTer on the DE10-Nano (Cyclone V `5CSEBA6U23I7`), Quartus 17.0.x.
- `sys/` is the MiSTer framework exactly as in Template_MiSTer. It is never
  edited here.
- The CPU is MacPPC7300's `DSPPC604`. CPU changes found by either core are
  made in that core's copy behind a parameter and carried to the other as a
  patch (`docs/cpu_patches/`); the first is little-endian mode (`LE_MODE`),
  which Windows NT and OS/2 need. Nothing machine-specific goes into the CPU.
- CPU clock 100 MHz (the 7248-100's own speed).
- One core for both machines of the Carolina board: the 7248 (with SCSI)
  and the Power Series 830/850 run the same firmware code, which tells
  them apart by the planar ID at port 0852.
- Real hardware outranks every emulator.

## Using it on the MiSTer

Put the files in `games/IBMRS6K7248/`:

- `boot.rom`: the 7248's firmware (512 KB). It loads at every start.
- A disk image for AIX, made with `dd if=/dev/zero of=AIX.img bs=1M count=4096`.
- `IBMRS6K7248.nvr`: the NVRAM image, made with `dd if=/dev/zero of=IBMRS6K7248.nvr bs=512 count=9`.
  The core fills it on first mount.
- The AIX install CD, as an ISO.

### The OSD

The OSD follows the computer cores' standard ([osd-standard.md](https://github.com/danifunker/hp9000-715_MiSTer/blob/master/docs/osd-standard.md)).
Mounted images are remembered and mounted again at every core load.

| Page | Row | Meaning |
|---|---|---|
| top | `Pri. disk (ID 0)` | the SCSI disk at ID 0, hdisk0 under AIX. "Pri." is the usual boot disk; the firmware's boot list (SMS) can boot another device |
| top | `Disk (ID 1)` | a second SCSI disk |
| top | `CD-ROM (ID 3)` | the CD image (the AIX install CD) |
| top | `Floppy` | drive A:'s diskette image (720 KB, 1.2 MB, 1.44 MB or 2.88 MB); a read-only image is write-protected |
| top | `Load ROM` | another firmware ROM for this session (a normal start loads `boot.rom`); it resets the machine |
| top | `Memory` | the RAM as SIMM pairs. AIX needs 32 MB at least. A size the SDRAM can't hold gives the most it can: 24, 56 or 112 MB on a 32, 64 or 128 MB module |
| top | `Apply and reset` | resets the machine with the OSD's settings. "Changes pending" shows while they differ from the running ones |
| P2 Video | `Aspect ratio` | Original (4:3), Full Screen, or the custom ratios |
| P3 Input | `Swap Alt/Win keys` | swaps the Alt and Win keys (acts at once) |
| P4 Audio | `Use MT32-pi`, `Synth`, `Munt ROM` / `SoundFont` | the MPU-401's MIDI to an MT32-pi on the user port, and its synth's settings (they act at once, like the Input page) |
| P5 Advanced | `NVRAM image` | the file holding the 4 KB PReP NVRAM and the CMOS: the boot list, the console choice, SMS settings. Loaded at the mount, saved two seconds after AIX or the firmware writes them |
| P9 Debug | `UART` | debug builds only (`IBMRS6K7248_DEBUG` in the `.qsf`): the MiSTer's UART carries the bring-up log (POST codes) or COM1. A release build carries COM1 |

Memory, the UART and the aspect ratio take effect at the next reset. Media, Input, the MT32-pi rows and Network interface take effect at once.

The FM synthesiser is JTOPL by Jose Tejada (jotego), an OPL2, in `rtl/jtopl/` under the GPL v3. The rest of the core is GPL v2 or later, so the combined core is distributed under the GPL v3.

## Running the bench

```
cd sim
make
./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8
```

It prints the firmware's progress codes (port 680) and a heartbeat as it
goes; `--io` prints every device access, `--pcs N` the first N
instructions retired, `--watch PC` when a PC is reached; at the end it
lists every stubbed device address with how often it was read and written
and the PC that touched it first. `machine_tb --help` lists the rest.
`make` builds inside a memory-capped systemd scope (about 14 minutes);
`make TRACE=1` builds a waveform-capable bench in `build_trace/`.

Reaching the firmware's `main_control` takes about 520 million clocks (half
an hour); save a snapshot there once and start later runs from it:

```
./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8 --lat 1 --save ../scratch/work/snap_main_control.bin --cycles 530000000
./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8 --lat 1 --restore ../scratch/work/snap_main_control.bin --cycles 1500000000 --com1 com1.raw
python3 tools/vt.py com1.raw
```

(A snapshot belongs to the build that wrote it: rebuild, re-save. The
bench's serial ports run at the clock / 16, `UART_FAST`, so the firmware's
9600 baud console does not cost 100,000 clocks a character.)

The little-endian tests: `make -C tests`, then
`./build/machine_tb --rom tests/le_test.rom --ram 8` (and
`le_test_dc.rom`); each prints `LE PASS` on COM1.

## Building

Open `IBMRS6K7248.qpf` in Quartus 17.0 and compile; the bitstream is
`output_files/IBMRS6K7248.rbf`. On the MiSTer the firmware ROM is loaded as
`boot.rom` in the core's folder, or from the OSD.
