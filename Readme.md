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
| CPU | `DSPPC604` from MacPPC7300_MiSTer `21ba191` (2026-10-16; `rtl/DSPPC604/`, unmodified): a 32-bit PowerPC 604-class core, verified against a real 604 there |
| Clock | CPU and machine 100 MHz, SDRAM 100 MHz: MacPPC7300's PLL in its 100 MHz-only form |
| SDRAM controller | MacPPC7300's (`rtl/machine/IBMRS6K7248_sdram.sv`, renamed only); the ROM in the board's top 4 MB, RAM below it |
| Machine | first form (`rtl/machine/IBMRS6K7248_machine.sv`): the PReP address map, RAM, the ROM at FFF00000 (the 512 KB flash; the second socket empty), COM1 (a 16550A) on the MiSTer's UART, the planar ID (F5, a 7248-100); everything else is a logged stub. The board is a Motorola MPC105 host bridge with IBM's Fire Coral ISA bridge (not an 82660/SIO) |
| Firmware | v1.12 runs on the bench from reset through CPU and Fire Coral set-up to memory sizing, where it waits for an MPC105 model (`docs/bringup_log.md`) |
| Bench | `sim/`: Verilator, the whole machine from the reset vector on a ROM image, COM1's output and every stubbed device access logged |
| Video, SCSI, keyboard, interrupts, NVRAM | not yet: see `docs/hardware_inventory.md` |

## Documents

- `docs/hardware_inventory.md`: the machine's hardware, from the service
  manuals and handbooks in `scratch/`
- `docs/firmware_analysis.md`: the firmware images and their disassembly
  (`firmware/`)
- `docs/emulators_and_software.md`: other emulators of this and related
  machines, and where the operating systems are
- `docs/bringup_log.md`: what the firmware does on the core, run by run

## Decisions

- MiSTer on the DE10-Nano (Cyclone V `5CSEBA6U23I7`), Quartus 17.0.x.
- `sys/` is the MiSTer framework exactly as in Template_MiSTer. It is never
  edited here.
- The CPU is MacPPC7300's `DSPPC604`, taken unmodified: fixes to it are made
  there and brought over. Nothing machine-specific goes into the CPU.
  It has no little-endian mode yet (MSR[LE]): AIX runs big-endian, but
  Windows NT and OS/2 on this machine need it.
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

It prints the firmware's progress codes (port 8C0) as they come; `--io`
prints every device access, `--pcs N` the first N instructions retired; at the end it lists every stubbed device address with how often it
was read and written and the PC that touched it first.

## Building

Open `IBMRS6K7248.qpf` in Quartus 17.0 and compile; the bitstream is
`output_files/IBMRS6K7248.rbf`. On the MiSTer the firmware ROM is loaded as
`boot.rom` in the core's folder, or from the OSD.
