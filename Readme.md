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
