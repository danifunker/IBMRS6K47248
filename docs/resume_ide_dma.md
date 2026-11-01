# Resume prompt: IDE DMA for the 850 personality (parked 2026-11-01)

Paste this into a new session to pick the work up.

---

The IBMRS6K7248 core (this repository) runs OS/2 Warp PPC under Model = Power Series 850: the IDE disk
(`rtl/machine/IBMRS6K7248_idehd.sv`, the primary master, 1F0/3F6) and the ATAPI CD-ROM
(`IBMRS6K7248_atapi.sv`, the secondary master, 170/376) are PIO only. OS/2 installs and boots, but its
disk runs at about 100 KB/s: a 2 GB Easy Installation format takes 5-6 hours.

Where the time goes was measured on the board (build os2u, per-second counters, `docs/resume_os2.md`,
"the installation runs" and the os2u notes; raw log `Y:\ibmrs6k-bench-logs\board_os2u_dbg.raw`):
0.67 ms a 512-byte sector on the disk side (the SCSI target and the Main's image access, in 32-sector
chunks) against 6.2 ms on the host's. OS/2's `dd_ide` uses READ/WRITE SECTORS only (no SET MULTIPLE),
takes an interrupt a sector, and for each one runs `R1F7 W3F6=0A R3F6 R1F7 R3F6 R3F6 W3F6=08`, the
256-word PIO, and the 0838 latch acknowledge. So the per-sector interrupt path on the 70 MHz CPU is
~90 % of the cost; double-buffering the disk side would gain a tenth at most.

The goal: the disk at several times its present speed, the way a real Power Series 850 does it (no
patches to OS/2 or to a disk image: the user wants permanent fixes that match the real machine).

Questions to answer first, in this order, before writing RTL:

1. **Does a real 850's IDE have DMA at all, and through what?** The IDE sits behind Fire Coral (IBM
   1014:000A at PCI device 0xB; the firmware's `build_ide` writes 0x73 to its register 0x24 to enable
   both channels; `docs/firmware_analysis.md`). Look for a bus-master IDE register block (a BAR, an
   SFF-8038-like command/status/PRD at some I/O range) in the firmware's IDE code (RAM image
   `firmware/images/7248_v1.12_main_ram_image_at_00000000.bin`, TOC 0x105980, named functions via
   `firmware/tools/tbtab.py`), in the 850's residual data / device tree the firmware builds, and in
   the IBM 850 technical reference if it can be found. The 82378-style scatter/gather (IRQ 13) is
   already modelled in `IBMRS6K7248_dma.sv`; whether the 850's IDE uses ISA DMA channels is open.
2. **Does any 850 OS use IDE DMA?** Disassemble OS/2's `dd_ide` (on the installed disk image
   `OS2_warp_ppc.img` on .92, or the install CD) for the DMA commands (C8/CA READ/WRITE DMA, 25/35),
   SET FEATURES transfer mode 0x2x/0x4x, and any bus-master register accesses. Do the same for NT's
   PPC `atapi.sys` and Solaris 2.5.1 PPC's `ata` driver. If OS/2's driver is PIO only, DMA cannot help
   OS/2 and the answer is elsewhere (step 3).
3. **If DMA is not the lever:** SET MULTIPLE is offered (IDENTIFY word 47 = 0x8008) but OS/2 never
   sends it; check whether `dd_ide` has a multiple-sector path that a different IDENTIFY answer (word
   59, the multiple setting valid at power-on, as some drives report) would turn on. That is a real
   drive's behaviour, not a patch. Then the CPU: the per-sector path is CPU-bound, and the user wants
   more than 70 MHz (`ibmrs6k-cpu-and-clock` memory).

Rules from the user and the project: work independently; one bench run at a time; raw board logs to
`Y:\ibmrs6k-bench-logs`; stage builds to `/media/fat/_Unstable` on .92 and load them through the OSD;
keep `docs/stubbed-hardware.md` current (the IDE rows); never a README in `releases/`.
