# IBM RS/6000 43P 7248 for MiSTer

The IBM RS/6000 43P 7248 ("Carolina"), a PReP PowerPC workstation, on the MiSTer. It runs the machine's own
firmware (v1.12) and can also act as its sibling, the IBM Power Series 850.

## What runs

| Operating system | Works |
|---|---|
| AIX 4.3.3 | install, boot from disk, CDE, networking |
| AIX 5.1 | install from volume 1, boot from disk, CDE |
| Solaris 2.5.1 (PowerPC) | install, boot from disk, CDE; CDE developer kit, ODBC and Wabi from the Desktop 1.1 CD |
| OS/2 Warp (PowerPC Edition) | install, boot from disk, desktop (as a Power Series 850) |
| Windows NT 4.0 (PowerPC) | install, boot from disk, desktop |

## CPU and clock

The real 7248 has a 120 MHz PowerPC 604. This core uses the DSPPC604 CPU from the MacPPC7300 core, with
little-endian mode added for NT and OS/2. The FPGA can't run it at 120 MHz, so there are two builds:

- `IBMRS6K7248_<date>.rbf`: 70 MHz. Use this one if unsure.
- `IBMRS6K7248_90MHz_<date>.rbf`: 90 MHz. Faster, but past the FPGA's timing limit. Tested on the
  SuperStation; it may not run on other hardware.

A 100 MHz build was tried and fails to boot from disk.

## What's built in

- CPU: PowerPC 604, big- and little-endian.
- Memory: up to 112 MB (needs a 128 MB SDRAM module), set as SIMM pairs in the OSD.
- Firmware: the 7248's own ROM, its SMS menus and boot list, and the 4 KB NVRAM, saved to the SD card.
- Video: S3 Vision864 with its SDAC: VGA text and graphics, 8 to 32 bits per pixel, the 2D engine and the
  hardware cursor.
- SCSI: NCR 53C810, two hard disks (IDs 0 and 1) and a CD-ROM (ID 3) with a working eject.
- IDE (Power Series 850 mode only): one hard disk and an ATAPI CD-ROM.
- Floppy: one drive, 720 KB to 2.88 MB images.
- Network: AMD PCnet Ethernet, bridged to the MiSTer's network.
- Sound: CS4232 (Windows Sound System, Sound Blaster Pro, OPL2 FM, MPU-401 MIDI to an MT32-pi, joystick).
- Keyboard and mouse: PS/2, with key repeat.
- Serial: COM1 on the MiSTer's UART, plus COM2.

## What isn't

- The OPL3's second bank and 4-operator voices (FM is OPL2 only).
- CD audio (off by default; build with `IBMRS6K7248_CDAUDIO`).
- IDE DMA (PIO only).
- Video modes above a 100 MHz dot clock (1280x1024 and up) run slow.
- After X exits, the S3 doesn't switch back to text mode.
- The parallel port, a second floppy drive, ISA Plug and Play.
- Duplicate replies to pings from AIX (a known network quirk).

## Getting started

1. Copy a core from `releases/` to `_Unstable/` (or `_Computer/`) on the SD card, renamed to
   `IBMRS6K7248.rbf`. Main's network and CD support recognise the core by that name.
2. Copy `releases/boot.rom` (the firmware) to `games/IBMRS6K7248/`. It loads at every start.
3. Put your disk images, CDs, diskettes and NVRAM files in `games/IBMRS6K7248/`.

Win+F12 opens the MiSTer menu. F12 alone goes to the machine.

Make a blank hard disk image (4 GB here):

```bash
dd if=/dev/zero of=AIX.img bs=1M count=4096
```

Make a blank NVRAM file (the core fills it in):

```bash
dd if=/dev/zero of=AIX.nvr bs=512 count=9
```

Main_MiSTer needs IBMRS6K support for networking, CUE/BIN and CHD CDs, and fast disk writes
(`mister/README.md`). Without it, plain ISO images and disks still work.

## One NVRAM file per OS

The NVRAM holds the firmware's boot list and console choice and each OS's own settings. Installing an OS
rewrites the boot list, so OSes sharing one NVRAM file get in each other's way. Give each OS its own file
and pick it under Advanced > NVRAM image before you start that OS.

- AIX, Solaris and NT (Model 7248-100): start from a blank file, or from `releases/IBMRS6K7248_default.nvr`
  (boot order floppy, CD, disk at ID 0).
- OS/2 (Model Power Series 850): needs a blank file. A boot list left by the 7248 (SCSI devices) makes the
  850 stop at the diskette prompt; with no list, the firmware finds the IDE disk itself.

The NVRAM file is read when it is mounted. After copying a file over it, load the core again.

## Installing AIX

Model 7248-100, a blank NVRAM, a blank disk as Disk 0, the install CD as CD-ROM, at least 32 MB.
Apply and reset. At "Please define the System Console" press F1 then Enter on the display, pick a
language, then install. AIX 5.1 takes about 2.5 hours from volume 1. Unmount the CD before the reboot.

## Installing Solaris 2.5.1

Model 7248-100, a blank NVRAM, a blank disk as Disk 0, the install CD as CD-ROM, and Sun's IBM boot
diskette as Floppy. Leave the diskette mounted after installing: the firmware Solaris needs runs from it.
Choose terminal type 8 (Sun Workstation) in the installer. The firmware's "disk" alias doesn't find the
installed system, so at the `ok` prompt set the boot device once; later boots need nothing typed:

```
setenv boot-device /pci/pci1000,1@10/disk@0,0:,\solaris.elf
```

## Installing OS/2 Warp

1. Advanced > Model: Power Series 850.
2. Advanced > NVRAM image: a new blank file (for example `OS2_850.nvr`).
3. Disk 0: a blank image of 2 GB or more. CD-ROM: the OS/2 Warp PowerPC Edition CD. Floppy: a blank
   1.44 MB image.
4. Apply and reset. The installer starts by itself from the CD.
5. Choose Easy Installation. The surface check, format and file copy take a few hours.
6. At "Installation Complete", unmount the CD and Apply and reset. OS/2 boots from the disk.

Shut down from the LaunchPad's Shut down button.

## Installing Windows NT 4.0

NT boots through IBM's ARC firmware, which sits on the hard disk. `releases/7248_ARC_v2.11EC.img` is the
ARC 2.11 EC boot diskette; `tools/mk_ntdisk.py` builds a disk with ARC already on it:

```bash
python3 tools/mk_ntdisk.py releases/7248_ARC_v2.11EC.img NT4.img 2048
```

1. Advanced > Model: 7248-100.
2. Advanced > NVRAM image: a file of NT's own (copy `releases/IBMRS6K7248_default.nvr` to `NT4.nvr`).
3. Disk 0: `NT4.img`. CD-ROM: the NT 4.0 CD (it needs the `\PPC` folder).
4. Apply and reset. The ARC menu comes up from the disk.
5. Choose Run a program and enter `cd:\ppc\setupldr`.
6. When setup asks, the computer type is "IBM Power Series 6050,6070 and RS/6000 Model 7248", and the
   SCSI adapter is "Symbios Logic C810".
7. Install onto the free space on the disk (NTFS or FAT). Setup reboots through ARC into NT.

Ctrl+Alt+Del logs on. Shut down from the Start menu.

## SMS (the firmware's setup)

`releases/7248_SMS_v1.07.img` is the 7248's SMS diskette (from IBM's firmware 1.11 package). Mount it as
Floppy. Press F1 at the startup icons for the graphical SMS, F4 for the text SMS. Don't use the 7020-40P's
SMS 1.28 diskette: its configuration menus crash on the 7248's firmware.

## The OSD

| Page | Option | What it does |
|---|---|---|
| main | Pri. disk (ID 0), Disk (ID 1) | SCSI hard disks (under the 850: Disk 0 is the IDE disk) |
| main | CD-ROM (ID 3) | the CD image (under the 850: the IDE CD-ROM) |
| main | Floppy | the diskette image; a read-only file is write-protected |
| main | Load ROM | another firmware ROM for this session |
| main | Memory | RAM size, at the next reset; the most an SDRAM module holds: 24, 56 or 112 MB on 32, 64 or 128 MB |
| main | Network interface | eth0, eth1, macvlan, tap0 or None |
| main | Apply and reset | resets with the new settings |
| Video | Aspect ratio, Scale | 4:3 or full screen; normal or integer scaling |
| Input | Swap Alt/Win keys | swaps the two keys |
| Audio | Use MT32-pi, Synth, Munt ROM, SoundFont | MIDI to an MT32-pi on the user port |
| Advanced | NVRAM image | the NVRAM file (see above) |
| Advanced | Model | 7248-100 (SCSI) or Power Series 850 (IDE), at the next reset |
| System | UART mode | any mode but None connects the MiSTer's Linux to COM1 (`picocom -b 9600 /dev/ttyS1`) |

Mounted images are remembered and mounted again when the core loads.

## Building

Open `IBMRS6K7248.qpf` in Quartus 17.0 and compile; the result is `output_files/IBMRS6K7248.rbf`. For the
90 MHz build, add `--verilog_macro="IBMRS6K7248_CPU90=1"` to `quartus_map`. A 90 MHz build depends on the
fitter's placement: test each one before releasing it.

The Verilator test bench (`sim/`) runs the whole machine from the firmware's reset vector:

```bash
cd sim && make && ./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8
```

## Documents

- `docs/bringup_log.md`: what each OS needed, day by day
- `docs/stubbed-hardware.md`: every device and how complete it is
- `docs/hardware_inventory.md`: the real machine's hardware
- `docs/firmware_analysis.md`: the firmware and its disassembly
- `docs/s3_design.md`, `docs/scsi_design.md`: the video and SCSI models

## License

The FM synthesiser is JTOPL by Jose Tejada (jotego), GPL v3. The rest of the core is GPL v2 or later, so the
whole core is distributed under the GPL v3.
