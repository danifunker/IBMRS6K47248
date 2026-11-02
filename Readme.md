# IBMRS6K7248 (IBM RS/6000 43P 7248) for MiSTer

A core for the [MiSTer](https://github.com/MiSTer-devel) FPGA platform
modelling the IBM RS/6000 43P model 7248, IBM's "Carolina" PReP workstation
(the board family of the IBM Power Series 830/850). The goal is the
machine's own firmware (SMS) running, then AIX 4.3.3 and AIX 5.1.

Work in progress: just started (2026-10-16).

## Status

| Operating system | State on the board |
|---|---|
| AIX 4.3.3 | installs and boots from disk to the CDE login; Ethernet (FTP, telnet) |
| AIX 5.1 | installs from volume 1 and boots from disk to the CDE desktop (2026-11-02) |
| Solaris 2.5.1 PPC | installs from the CD (with Sun's boot diskette in the floppy slot) and boots by itself to the CDE login; CDE, ODBC and Wabi from the Desktop 1.1 CD |
| OS/2 Warp for PowerPC | installs and boots to the desktop under Model `Power Series 850` (IDE disk and CD-ROM) |
| Windows NT 4.0 PPC | setup's text and GUI parts run; its S3 and CS4232 drivers work |

| Piece | State |
|---|---|
| CPU | `DSPPC604` from MacPPC7300_MiSTer (`rtl/DSPPC604/`), a 32-bit PowerPC 604-class core, plus little-endian mode (`docs/cpu_patches/`); 70 MHz |
| Machine | `rtl/machine/`: the PReP map, the MPC105 (RAM as SIMM pairs, up to 112 MB on a 128 MB board), Fire Coral, the 8259s, 8254, 8237 DMA with scatter/gather, the RTC and 4 KB NVRAM (kept on the SD card), the 8042 (PS/2 keyboard and mouse), the PC87312 (COM1 on the MiSTer's UART, COM2, the floppy, the parallel port as a log), the VPD EEPROM |
| Video | the S3 Vision864 with its SDAC: VGA, 8 to 32 bits a pixel, the 8514 engine, the hardware cursor (`docs/s3_design.md`) |
| Disks | the NCR 53C810 with SCSI disks at IDs 0 and 1 and a CD-ROM at ID 3 (its tray opens and closes); under the 850 model, an IDE disk and an ATAPI CD-ROM |
| Network, sound | the PCnet Ethernet bridged to the MiSTer's network; the CS4232 (WSS codec, Sound Blaster Pro, OPL2 FM, MPU-401 to an MT32-pi, joystick) |
| Open | `docs/stubbed-hardware.md`: the S3 back to text mode after X, the PCnet's duplicate frames, the OPL3's second bank, CD audio, IDE DMA, dot clocks over 100 MHz |

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

The core is `releases/IBMRS6K7248_<date>.rbf` (the newest date); copy it to `_Unstable/` (or
`_Computer/`) on the SD card.

Put the files in `games/IBMRS6K7248/`:

- `boot.rom`: the 7248's firmware (512 KB, v1.12, P93H7075; `releases/boot.rom`). It loads at every start.
- A disk image for AIX, made with `dd if=/dev/zero of=AIX.img bs=1M count=4096`.
- For Windows NT: a disk made with `python3 tools/mk_ntdisk.py rs6karc151.img NT4.img 2048` from IBM's ARC
  boot diskette (ARC 2.11 EC): ARC in a PReP boot partition (the machine boots it from the disk, no
  diskette), a 5 MB FAT16 system partition for NT's OS loader, the rest left for NT setup (NTFS). Boot it,
  then `Run a program`: `cd:\ppc\setupldr` with the NT 4.0 CD in; the computer type is "IBM Power Series
  6050,6070 and RS/6000 Model 7248", the SCSI driver Symbios Logic C810.
- `IBMRS6K7248.nvr`: the NVRAM image, made with `dd if=/dev/zero of=IBMRS6K7248.nvr bs=512 count=9`.
  The core fills it on first mount. Or start from `releases/IBMRS6K7248_default.nvr` (copy it to
  `IBMRS6K7248.nvr`): the boot sequence floppy, CD-ROM, the disk at ID 0, the disk the boot device,
  no BOOTP addresses, the error log empty. Copy it again to undo NVRAM changes (the boot list an AIX
  install CD leaves, SMS settings); the file is only read when it is mounted, so load the core again.
- The AIX install CD, as an ISO.
- For the System Management Services: `releases/7248_SMS_v1.07.img`, the 7248's SMS diskette,
  version 1.07 (a raw 1.44 MB FAT12 image, MD5 `77a5682c00c610c18341ea6dbb776a16`). Mount it as
  `Floppy`. F4 at the POST icons (after the keyboard icon, before the speaker) gives the text SMS;
  F1 at the icons, or a plain boot with the diskette in, the graphical SMS. It is `sms107.dd` from
  IBM's firmware 1.11 package for the 7248 (`7248100.bin`, mirrored at
  http://ps-2.kev009.com/rs6000-firmware/; the ZIP password is the one IBM published,
  `**RS/6000**`). Don't use the 7020-40P's SMS diskettes: SMS 1.28 calls ROM services the 7248's
  firmware (v1.12) lacks, and its configuration menus stop in the firmware's debugger (ABEND
  0001000A). The same package's `fw-111.dd` is a flash update diskette (firmware 1.11, older
  than the core's 1.12): don't boot it.

### The OSD

The OSD follows the computer cores' standard ([osd-standard.md](https://github.com/danifunker/hp9000-715_MiSTer/blob/master/docs/osd-standard.md)).
Mounted images are remembered and mounted again at every core load.

| Page | Row | Meaning |
|---|---|---|
| top | `Pri. disk (ID 0)` | the SCSI disk at ID 0, hdisk0 under AIX. "Pri." is the usual boot disk; the firmware's boot list (SMS) can boot another device |
| top | `Disk (ID 1)` | a second SCSI disk |
| top | `CD-ROM (ID 3)` | the CD image (the AIX install CD) |
| top | `Floppy` | drive A:'s diskette image (720 KB, 1.2 MB, 1.44 MB or 2.88 MB); a read-only image is write-protected; the 7248's SMS diskette is `releases/7248_SMS_v1.07.img` (above) |
| top | `Load ROM` | another firmware ROM for this session (a normal start loads `boot.rom`); it resets the machine |
| top | `Memory` | the RAM as SIMM pairs. AIX needs 32 MB at least. A size the SDRAM can't hold gives the most it can: 24, 56 or 112 MB on a 32, 64 or 128 MB module |
| top | `Apply and reset` | resets the machine with the OSD's settings. "Changes pending" shows while they differ from the running ones |
| P2 Video | `Aspect ratio` | Original (4:3), Full Screen, or the custom ratios |
| P2 Video | `Scale` | Normal, or integer scaling (V-Integer, Narrower or Wider HV-Integer: the framework's `video_freak`); at once |
| P3 Input | `Swap Alt/Win keys` | swaps the Alt and Win keys (acts at once) |
| P4 Audio | `Use MT32-pi`, `Synth`, `Munt ROM` / `SoundFont` | the MPU-401's MIDI to an MT32-pi on the user port, and its synth's settings (they act at once, like the Input page) |
| P5 Advanced | `Model` | the planar ID the firmware reads at 0852: `7248-100` (F5, with SCSI) or `Power Series 850` (F1); at the next reset. OS/2 for PowerPC was made for the 850 (`PPC_INFO.STZ` has no 7248). Under the 850 the IDE is a real 850's: the disk 0 image is the primary channel's master and the CD image the secondary's (the 53C810 sees neither): the firmware boots the OS/2 CD over IDE and its installer comes up with nothing typed; an installed OS/2 boots by itself from the disk when the NVRAM's boot list has the IDE disk, or has no list at all (a fresh NVRAM image: the firmware then finds the disk itself). A boot list left by the 7248 (floppy, SCSI CD-ROM, SCSI disk) ends at the SMS diskette prompt: use another NVRAM image for OS/2 |
| P5 Advanced | `NVRAM image` | the file holding the 4 KB PReP NVRAM and the CMOS: the boot list, the console choice, SMS settings. Loaded at the mount, saved two seconds after AIX or the firmware writes them |
| System page | `UART mode` | the framework's own setting. The MiSTer's UART is COM1: any mode (PPP, Console, MIDI, Modem) connects the MiSTer's Linux to it (watch it with `picocom -b 9600 /dev/ttyS1` over ssh) |

Memory and the aspect ratio take effect at the next reset; the UART mode at once. Media, Input, the MT32-pi rows and Network interface take effect at once.

CD audio (PLAY AUDIO, PAUSE/RESUME, STOP, READ SUB-CHANNEL, the volume page) is built in when the `.qsf`
sets `IBMRS6K7248_CDAUDIO`: the CD's audio tracks play into the core's sound output, mixed with the
CS4232. It needs the Main's track table and audio window (`support/ibmrs6k` in Main_MiSTer); without the
macro the CD answers as before (data only). Bench: `sim/cdaudio/run.sh`.

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
