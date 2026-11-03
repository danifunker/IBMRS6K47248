# IBM RS/6000 43P 7248 for MiSTer

The IBM RS/6000 43P 7248 ("Carolina"), a PReP PowerPC workstation, on the MiSTer. It runs the machine's own
firmware and can also act as its sibling, the IBM Power Series 850.

## What runs

| Operating system | Works |
|---|---|
| AIX 4.3.3 | install, boot from disk, CDE, networking |
| AIX 5.1 | install from volume 1, boot from disk, CDE |
| Solaris 2.5.1 (PowerPC) | install, boot from disk, CDE; CDE developer kit, ODBC and Wabi from the Desktop 1.1 CD |
| OS/2 Warp (PowerPC Edition) | install, boot from disk, desktop (as a Power Series 850) |
| Windows NT 4.0 (PowerPC) | install, boot from disk, desktop, CD audio |

## Downloads

Everything is in `releases/`:

| File | What it is |
|---|---|
| `IBMRS6K7248_<date>.rbf` | the core, CPU at 70 MHz. Use this one if unsure |
| `IBMRS6K7248_90MHz_<date>.rbf` | the same core, CPU at 90 MHz (see below) |
| `boot.rom` | the 7248's firmware, v1.12 |
| `IBMRS6K7248_default.nvr` | an NVRAM file to start from: boot order floppy, CD, disk |
| `7248_SMS_v1.07.img` | the SMS diskette (the firmware's setup menus) |
| `7248_ARC_v2.11EC.img` | IBM's ARC boot diskette, needed for Windows NT |

## CPU speed

The real 7248 has a 120 MHz PowerPC 604. The MiSTer's FPGA can't run this core's CPU that fast, so there are
two cores:

- **70 MHz**: runs on any MiSTer.
- **90 MHz**: faster, but beyond the FPGA's rated timing. Tested on the SuperStation; on other hardware it may
  not boot. If it misbehaves, use the 70 MHz core.

## Setting up

1. Copy the cores to `_Unstable/` (or `_Computer/`) on the SD card. Both can sit side by side; they share
   the same settings and mounted images.
2. Copy `boot.rom` to `games/IBMRS6K7248/`.
3. Put disk images, CD images, diskettes and NVRAM files in `games/IBMRS6K7248/`.
4. Set Memory to 112 MB (needs a 128 MB SDRAM module; less works too, AIX needs 32 MB or more).

Win+F12 opens the MiSTer menu. F12 alone goes to the machine.

A blank 4 GB hard disk and a blank NVRAM file, made on a PC or on the MiSTer over ssh:

```bash
dd if=/dev/zero of=AIX.img bs=1M count=4096
```

```bash
dd if=/dev/zero of=AIX.nvr bs=512 count=9
```

Networking, CUE/BIN and CHD CD images, CD audio and fast disk writes need a Main_MiSTer with IBMRS6K
support (`mister/README.md`). Without it, plain ISO images and disks still work.

## One NVRAM file per OS

The NVRAM holds the firmware's boot list, the console choice and each OS's own settings. Installing an OS
rewrites the boot list, so OSes sharing one NVRAM file get in each other's way. Give each OS its own file and
pick it under Advanced > NVRAM image before starting that OS.

- AIX, Solaris and NT (Model 7248-100): a blank file, or a copy of `IBMRS6K7248_default.nvr`.
- OS/2 (Model Power Series 850): a blank file. A boot list left by the 7248 makes the 850 stop at the
  diskette prompt; with no list, the firmware finds the IDE disk by itself.

The NVRAM file is read when it is mounted. After replacing the file, load the core again.

## Installing AIX

Model 7248-100, a blank NVRAM, a blank disk as Disk 0, the install CD as CD-ROM. Apply and reset. At "Please
define the System Console" press F1 then Enter, pick a language, then install. AIX 5.1 takes about 2.5 hours
from volume 1. Unmount the CD before the reboot. Shut down with `shutdown -F`.

## Installing Solaris 2.5.1

Model 7248-100, a blank NVRAM, a blank disk as Disk 0, the install CD as CD-ROM, and Sun's IBM boot diskette
as Floppy. Leave the diskette mounted after installing: the firmware Solaris needs runs from it. Choose
terminal type 8 (Sun Workstation) in the installer. After installing, set the boot device once at the `ok`
prompt; later boots need nothing typed:

```
setenv boot-device /pci/pci1000,1@10/disk@0,0:,\solaris.elf
```

Shut down with `init 0`.

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

NT boots through IBM's ARC firmware, kept on the hard disk. Build that disk on a PC with Python 3 and
`tools/mk_ntdisk.py` from this repository:

```bash
python3 tools/mk_ntdisk.py 7248_ARC_v2.11EC.img NT4.img 2048
```

1. Advanced > Model: 7248-100.
2. Advanced > NVRAM image: a file of NT's own (a copy of `IBMRS6K7248_default.nvr`, for example `NT4.nvr`).
3. Disk 0: `NT4.img`. CD-ROM: the NT 4.0 CD (it needs the `\PPC` folder).
4. Apply and reset. The ARC menu comes up from the disk.
5. Choose Run a program and enter `cd:\ppc\setupldr`.
6. When setup asks, the computer type is "IBM Power Series 6050,6070 and RS/6000 Model 7248", and the SCSI
   adapter is "Symbios Logic C810".
7. Install onto the free space on the disk (NTFS or FAT). Setup reboots through ARC into NT.

Ctrl+Alt+Del logs on. Shut down from the Start menu. CD Player plays the audio tracks of CUE/BIN and CHD
images.

## SMS (the firmware's setup)

Mount `7248_SMS_v1.07.img` as Floppy. Press F1 at the startup icons for the graphical SMS, F4 for the text
SMS. Don't use the 7020-40P's SMS 1.28 diskette: its configuration menus crash on the 7248's firmware.

## The OSD

| Page | Option | What it does |
|---|---|---|
| main | Pri. disk (ID 0), Disk (ID 1) | SCSI hard disks (under the 850: Disk 0 is the IDE disk) |
| main | CD-ROM (ID 3) | the CD image (under the 850: the IDE CD-ROM) |
| main | Floppy | the diskette image; a read-only file is write-protected |
| main | Load ROM | another firmware ROM for this session |
| main | Memory | RAM size, at the next reset: 24, 56 or 112 MB at most on a 32, 64 or 128 MB module |
| main | Network interface | eth0, eth1, macvlan, tap0 or None |
| main | Apply and reset | resets with the new settings |
| Video | Aspect ratio, Scale | 4:3 or full screen; normal or integer scaling |
| Input | Swap Alt/Win keys | swaps the two keys |
| Audio | Use MT32-pi, Synth, Munt ROM, SoundFont | MIDI to an MT32-pi on the user port |
| Advanced | NVRAM image | the NVRAM file (see above) |
| Advanced | Model | 7248-100 (SCSI) or Power Series 850 (IDE), at the next reset |
| System | UART mode | any mode but None connects the MiSTer's Linux to COM1 (`picocom -b 9600 /dev/ttyS1`) |

Mounted images are remembered and mounted again when the core loads.

## What the core has

- CPU: PowerPC 604, big- and little-endian.
- Memory: up to 112 MB.
- Firmware: the 7248's own ROM, its SMS menus and boot list, and the 4 KB NVRAM, saved to the SD card.
- Video: S3 Vision864 with its SDAC: VGA text and graphics, 8 to 32 bits per pixel, the 2D engine and the
  hardware cursor.
- SCSI: NCR 53C810, two hard disks (IDs 0 and 1) and a CD-ROM (ID 3) with eject and CD audio.
- IDE (Power Series 850 only): one hard disk and an ATAPI CD-ROM.
- Floppy: one drive, 720 KB to 2.88 MB images.
- Network: AMD PCnet Ethernet, bridged to the MiSTer's network.
- Sound: CS4232 (Windows Sound System, Sound Blaster Pro, OPL2 FM, MPU-401 MIDI to an MT32-pi, joystick).
- Keyboard and mouse: PS/2, with key repeat.
- Serial: COM1 on the MiSTer's UART, plus COM2.

## Known limitations

- FM music is OPL2 only (no OPL3 second bank or 4-operator voices).
- IDE is PIO only (no DMA): slow under OS/2.
- Video modes above a 100 MHz dot clock (1280x1024 and up) run slow.
- Solaris: after X exits, the console text doesn't come back.
- No parallel port, second floppy drive or ISA Plug and Play.

## For developers

Build in Quartus 17.0 from `IBMRS6K7248.qpf`; the result is `output_files/IBMRS6K7248.rbf`. For the 90 MHz
core add `--verilog_macro="IBMRS6K7248_CPU90=1"` to `quartus_map` (the release also used `--seed=1` on
`quartus_fit`). A 90 MHz build depends on the fitter's placement: test each one on hardware.

The Verilator test bench (`sim/`) runs the whole machine from the firmware's reset vector:

```bash
cd sim && make && ./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8
```

Notes: `docs/bringup_log.md` (what each OS needed), `docs/stubbed-hardware.md` (every device and how complete
it is), `docs/hardware_inventory.md`, `docs/firmware_analysis.md`, `docs/s3_design.md`, `docs/scsi_design.md`.

## License

The FM synthesiser is JTOPL by Jose Tejada (jotego), GPL v3. The rest of the core is GPL v2 or later, so the
whole core is distributed under the GPL v3.
