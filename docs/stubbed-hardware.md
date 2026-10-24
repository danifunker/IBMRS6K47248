# Stubbed hardware: what the 7248 has, what the core answers, what the software needs

(Started 2026-10-18. The running inventory of every device the firmware and
the operating systems touch, with the core's state of each: **real** (modelled
to the register level the software uses), **partial** (some registers real,
the rest stubbed), **stub** (reads return zero, writes are dropped; the bench
logs them as `stub`, the top's debug UART reports device accesses after user
code starts), or **absent** (no decode at all). Keep it current: every new
stub found in a bench run or a board capture goes here with the run that found
it, and every device that gets modelled moves up. The hardware itself is in
`hardware_inventory.md`; the firmware's use of each port in
`firmware_analysis.md` §4; this file is about the gap.)

## How to find a new one

- The bench: every run ends with `stubbed device addresses (N)` (address,
  reads, writes, last data, first PC); `--io` prints each access as it
  happens, `--io-range LO:HI` only a window. `scratch/work/stubs_all.sh`
  aggregates every run's table.
- The board: the debug UART logs the first 250 device accesses after user code
  starts (`rWWWW=dddddddd`, `r`/`w` ISA, `R`/`W` other), the PCI configuration
  accesses (`C8=`, `cR=`, `cW=`), and port 92.
- The software's side: the diagnostics CD's `rc.boot` (`scratch/work/aix/rc.boot.sh`,
  from the RAM disk `scratch/work/aix/ramfs.img`; `ramfs_boot.py` inflates it
  from the boot image) and its config methods (`/usr/lib/methods/cfg*`) say
  which devices each boot phase needs; `docs/firmware_analysis.md` §4 lists
  the firmware's.

## The blocker today: the machine's identity (2026-10-18) -- resolved: the CD rejects a real 7248 too

The AIX 4.3.3 diagnostics CD boots, runs `cfgmgr -f`, then `bootinfo -M`,
and unless that returns 101 or 103 ("this machine supports diagnostics") it
ejects the CD, sleeps 3 s and calls `reboot(0)`; the firmware re-boots the CD
and the cycle repeats every ~3 minutes (`bringup_log.md`, 2026-10-18 afternoon).
`bootinfo -M` turns `sys0`'s ODM attribute `modelcode` into 100-103 (101/103
need bits 2-3 of the code set); `cfgsys_rspc` sets `modelcode` from the
firmware's data (`/dev/nvram` ioctls: the residual data, the IPL control
block, the NVRAM). Our residual data differs from a real 7248's in exactly
the places fed by stubbed hardware:

| field | ours | a real 7248 | fed by |
|---|---|---|---|
| VPD.Serial | `ffffffffffffffff` | the planar's serial | the VPD/security EEPROM at ports 78-7C (stub) or the NVRAM (blank) |
| VPD.NvramSize | -1 (`nvram_good` false) | 4096 | the 4 KB NVRAM has no valid PReP header (byte 2 = 1, byte 3 = 4, area sizes, CRC): the firmware never initialised ours |
| model code (AIX) | 0 -> `bootinfo -M` = 100 | 101/103 | not yet pinned down: the firmware's VPD/NVRAM/EEPROM data |

**Resolved (evening):** `modelcode` comes from the CD's PReP loader, which
derives it from the residual's PrintableModel string; the firmware's fixed
"IBM PPS Model 7248 (E)" gives 0x0803004C and `bootinfo -M` = 100 on a real
7248 as well: this diagnostics CD does not support the 7248. The NVRAM and
EEPROM below are still right to have (the VPD serial, the boot list); the
boot medium moves to the AIX 4.3.3 install CD.

## What AIX needs, in boot order (the diagnostics CD)

The CD's config methods (`/usr/lib/methods` on the ISO and in the RAM disk)
and `rc.boot` give the order in which the core's gaps will be hit:

1. **`cfgsys_rspc`, `bootinfo`**: the machine's identity from the residual
   data, the IPL control block and the NVRAM (`modelcode`, `modelname`,
   `systemid`, `fwversion`, the memory size). **Stops here today.** Hardware:
   the VPD EEPROM (78-7C), the PReP NVRAM (74-76).
2. **`cfgbus_pci`, `cfgbus_isa`, `cfgpal_rspc`**: PCI configuration space
   (CF8/CFC: devices 0, 11, 14, 16 answer; the rest must read as absent) and
   the planar PAL (`planar_pal_rspc`: LEDs and reboot through the system
   registers 82A-83C and the ROM reset vector). Real/harmless today.
3. **`cfgncr_scsi` (`ncr810dd`), `cfgsccd`**: the 53C810 under AIX's driver
   (SCRIPTS, interrupts on IRQ15, DMA into kernel buffers, message phases),
   then the CD as `cd0`; `rc.boot` mounts `/SPOT` from it (`mount -v cdrfs`,
   retried every 5 s with LED A70 until it works). The firmware's boot already
   uses the chip, so this is "more of the same" plus interrupts.
4. **`cfgsio`, `cfgasync_rspc` (`rsdd_rspc`), `cfgtty`, `cfgcon`**: the
   PC87312's serial ports and the tty on S1: COM1 is real; expect AIX to
   program the 16550 more fully (FIFOs, modem status, interrupts) than the
   firmware does.
5. **`cfgkbd_std`, `cfgmouse_std` (`kbddd`, `mousedd`)**: the 8042 and PS/2
   devices, real.
6. **`cfgfda_isa`** (floppy): `process_diskette` returns at once without a
   drive; keep the floppy absent for now.
7. **`startlft`/`cfglft`**: no S3 driver on this CD: the display stays the
   firmware's. AIX 4.3.3 proper would need the S15 (S3 864) driver's view of
   the chip: the next big display item.
8. **Audio, parallel, Ethernet**: later (the PCnet needs the Main_MiSTer branch).

## Sizing the open jobs

| Job | Size | What it takes |
|---|---|---|
| VPD EEPROM at 78-7C | medium, and blind on contents | a command/status register interface, not a bit-banged serial: `EEPROM_Send_Command` writes 79, then the command byte to 78, reads 7C and sets its bit 7; `EEPROM_Read_Size` reads 78 expecting 9 or 11 (a size code); `EEPROM_Use_Base_Ports`/`Alternate_Ports` toggle bit 3 of 7C; `talk_to_eeprom` CRC-checks bytes 0x29-0x3F against a stored CRC (`calc_non_lockable_crc`). No dump of a real 7248's EEPROM: the image must be made to satisfy the firmware's readers (`GetEEPROMSerialNumber`, the VPD, the passwords) |
| PReP NVRAM image | small | the firmware never formats a bad NVRAM at boot (`nvraminit` is the resident monitor's command; `initfwNVRAM` only rewrites the firmware's own area), and the core's 4 KB array is reset on every load. So: preload an image the firmware accepts (`nvram_good`: byte 2 = 1, byte 3 = 4, the area table it reads at 0xC4/0xC8/0xD4/0xD8, the CRC-16 at bytes 4-5 over the header; `initfwNVRAM`'s contents for the firmware area; the boot list and console choice as SMS would set them), loaded like `boot.rom` or built into the RTL as `init_cmos`'s image is; later, persistence through the Main_MiSTer branch |
| 8237 DMA | done | with scatter/gather; the floppy and ECP still have no DREQ |
| 53C810 under AIX | medium | interrupts (IRQ15 level), DMA to arbitrary kernel buffers, the message and status phases the driver uses; the firmware's boot path already covers reads |
| 16550 under AIX | small | FIFO control, modem status, interrupts; already real for the firmware |
| Floppy | large | a full 82077 with DMA; only if a configuration diskette is ever wanted |
| S3 for AIX (S15 driver) | large | the accelerator and the driver's register expectations; see `s3_design.md` |
| PCnet Ethernet | done | the core's side; the Main's bridge to merge (`mister/README.md`) |

## The inventory

Ordered by when the boot needs them. "Needed by" names the first software
that cannot proceed without it.

### Planar core

| Device | Ports / addresses | State | Needed by | Notes, plan |
|---|---|---|---|---|
| MPC105 host bridge, RAM banks | PCI dev 0 config; `80`-`A0` bank regs | **real** (sizing, LE swap, config) | firmware memory sizing | the byte masks go on A12-A11 (the sizing halt) |
| Fire Coral PCI-ISA bridge, config | PCI dev 11 config; internal index/data `1000`/`1004` | **partial**: config space and the few internal registers the firmware uses (IDE setup index 0x25); the rest stubbed | firmware reset path | AIX's `pci_busdd`/`isa_busdd` read config space; more internal registers will surface |
| 8259 PICs, ELCR | `20`/`21`, `A0`/`A1`, `4D0`/`4D1` | **real** | firmware, AIX interrupts | all PCI interrupts on IRQ15 |
| 8254 PIT, port 61 | `40`-`43`, `61` | **real** | firmware (refresh counter, beep) | |
| 8237 DMA + 82378 extensions | `00`-`0F`, `80`-`8F`, `C0`-`DF`, `40A`/`40B`, `410`-`43F`, `480`-`48F`, `4D4`/`4D6` | **real** (`IBMRS6K7248_dma`: both 8237s, page and high page registers, the 82378's scatter/gather with IRQ 13; a bus master beside the 810 and the PCnet; `sim/audio/run.sh`) | firmware floppy/audio; AIX floppy, audio, ECP | only the codec asks for DMA today (channel 1); the floppy and ECP have no DREQ |
| 8042 keyboard/mouse | `60`/`64` | **real** (PS/2 keyboard and mouse) | firmware SMS, AIX `kbddd`/`mousedd` | |
| RTC/CMOS (MC146818) | `70`/`71` | **real**; starts with `init_cmos`'s image (valid CRCs, reset bit clear) | the firmware's "boot 0" (BOOT.6XE); AIX's `planar_pal_init_ds1285` (waits for UIP with interrupts off) | UIP is the last 8 ticks before each second, also under the bench's `RTC_FAST` (`09ba71a`) |
| **PReP NVRAM 4 KB** | `74`/`75`/`76` | **real**: starts with the image the firmware's own formatter makes (`firmware/tools/nvram_image.py`: valid header and CRCs, blank areas), **verified**: the residual's NvramSize is 0x1000 (`run20`); **kept on the SD card** with the CMOS (`IBMRS6K7248_nvsave`: the OSD's NVRAM file, mounted again at every load; loaded at the mount, saved two seconds after the CPU's last write) | AIX: boot list, console choice; the firmware's SMS settings | the Serial in the residual comes from this header (now the EEPROM image's), not from the EEPROM |
| **VPD / security EEPROM** | `78`-`7C` | **modelled, contents inferred** (`IBMRS6K7248_eeprom.sv`: the controller with two register sets, a 93C46-class 64-word EEPROM; `firmware/tools/eeprom_image.py`: the CRC word, a 16-digit serial, no passwords) | the firmware's VPD (`build_vpd`, `GetEEPROMSerialNumber`), passwords; AIX's `systemid`, maybe `modelcode` | **to verify** on the bench: the firmware's EEPROM_init and reads succeed (no `EEPROM locked`/password path), the residual's Serial becomes the image's; adjust the image as the firmware's readers show what else they expect |
| Flash lock, system registers | `98`, `800`, `808`, `80C`/`80D`, `810`/`812`, `814`, `81C`, `82A`/`82B`, `838`/`83C`, `860`/`862`, `880`-`882` (SIMM presence), `8A0`, `8C0`/`8C1` | **partial**: planar ID `852`, the SIMM presence `880`-`882` and the L2 status bits the firmware reads are real; the rest stubbed | firmware (L2 init, power management, LEDs, security) | AIX's `planar_pal_rspc` touches `82A`-`83C` (power, LEDs) and the reboot path (`Q014288DC-100`: PCI scan then the ROM reset vector); harmless as stubs so far |
| Checkpoint ports | `680` (32-bit), `3BC` (LPT data), `8C0` | **real as logs** (the bench prints `680`; the UART logs it) | debugging | |
| Port 92 | `92` | logged | firmware A20/reset | the kernel's reboot does not use it (it jumps to FFF00100) |

### Super I/O (PC87312) and ISA devices

| Device | Ports | State | Needed by | Notes, plan |
|---|---|---|---|---|
| PC87312 configuration | `398`/`399` | **real** (the index/data pairs the firmware writes) | firmware `PC87312Init` | |
| COM1, COM2 (16550) | `3F8`/`2F8` | **real** (COM1 on the MiSTer's UART; the bench's `--com1`) | the firmware's async console; **AIX's console on S1** (`consdef`: the prompt goes to S1) | the diagnostics CD has no S3 driver: S1 is its only console. Not reached yet (the identity check reboots first) |
| Parallel port | `3BC`-`3BE` (LPT1), ECP DMA | logged (checkpoints) | AIX `ppdd` | |
| Floppy (PC87312) | `3F0`-`3F7` | **partial**: the firmware's probe sequence (`fd` reads `3F4`/`3F5`... 65 K status polls in the SCSI runs) is stubbed; no drive | firmware (configuration diskette), AIX `fdisa` | rc.boot's `process_diskette` returns at once if no diskette drive is configured: fine without |
| CS4232 audio | `220`/`240`, `388`, `200`, `330`, `534`/`535` | **real** for the WSS codec's playback (CS4231 registers, the rates and formats, DMA channel 1, IRQ 5, the DAC volume; mixed with the speaker); the Sound Blaster only answers its reset, no OPL3, no capture | firmware `audio_play` (the POST tune: its scatter/gather sequence is the bench's), AIX `cs4232` | the Plug-and-Play IRQ/DMA choices are taken as the residual's (5, DMA 1 play, 0 capture) |
| IDE (Fire Coral) | `1F0`-`1F7`/`3F6`, `170`-`177`/`376` | **stub**: the firmware's probe (`3F6`/`376` reads, 65 K each) finds nothing | none on the 7248 (SCSI planar) | the 7248 has no IDE drive; keep as "no device" (reads FF would end the probe faster) |
| ISA PnP | `279`/`A79` | **stub** | firmware `build_isa` | |
| Unknown | `4690`/`4691` (`monitor_serial_port`) | **stub** | firmware | |

### PCI devices

| Device | Config / BARs | State | Needed by | Notes, plan |
|---|---|---|---|---|
| S3 Vision864 + SDAC, 2 MB VRAM | dev 14 (5333:88C0), VGA I/O `3B4`-`3DF`, S3 enhanced `42E8`-`E2E8`, LFB at CPU `C2800000` | **real** for the firmware and AIX 4.3.3's X server (1024 x 768 x 8; the hardware cursor in Windows and X11 modes, its colours CR0E/CR0F; 3DB reads as 3DA; the whole 8514 engine at 8 bpp: Bresenham and radial lines, short-stroke vectors, rectangles, BitBLTs, pattern fills, the three mix selections, colour compare, image reads, PIX_TRANS on an 8-, 16- or 32-bit bus (a 32-bit transfer whole or as E2E8 then E2EA), the position after a command; `sim/s3ge/run.sh` checks each against a C++ model); **not done**: 16/24 bpp, mono image reads, register read-back of what the engine moved (CUR_X/Y), READ_SEL | the firmware's screen; AIX's desktop | the error-icon palette (dark blue on black) is open |
| NCR 53C810 SCSI, the CD at ID 3 | dev 16 (1000:0001), I/O and memory BARs | **real** enough for the firmware's boot (SCRIPTS, the CD's reads) | the firmware's CD boot; AIX `ncr810dd` (`cfgncr_scsi`) | **the install CD's blocker (2026-10-23)**: under AIX's `ncr810dd` the bus scan (`cfgncr_scsi`, `find_sc_dev`) finds no device at ID 3, so no `cd0`, `bootinfo -b` is empty and `rc.boot` stops at LED 0x518 (`bringup_log.md` 2026-10-23); next: what the driver asks of the chip (interrupts, DMA to kernel buffers, message phases) |
| AMD Am79C970 PCnet | dev 12 (1022:2000, rev 10), BAR0 32 bytes of I/O, INTA to IRQ 15 | **real**: `IBMRS6K7248_pcnet` (QEMU's semantics: WIO/DWIO, the PROM, CSR/BCR, 16- and 32-bit init blocks and descriptors, chained RX, loopback with FCS, TX poll; `sim/pcnet/run.sh`, and `run.sh net` with the mailbox); the wire is `IBMRS6K7248_enetbox`'s DDR3 mailbox (`RS6ETH01`) to the Main | the firmware's network boot and SMS (I970); AIX `ent0` | the Main's bridge is `mister/Main_MiSTer/support/ibmrs6k/` (to merge: `mister/README.md`); not run on the board yet |
| PCI configuration mechanism | `CF8`/`CFC` | **real** (devices 0, 11, 14, 16; others absent) | everything | AIX's reboot path scans devices 0-31 (`Q014288DC`) |

### Memory-mapped and other

| What | Address | State | Notes |
|---|---|---|---|
| Firmware ROM | `FFF00000`, 512 KB (the second socket empty) | **real** | |
| ISA memory window | `C0000000`+ (PCI memory), ISA `A0000`-`FFFFF` in it | **partial** (VGA memory real) | |
| Stray kernel lock read | physical `100277C0`-`FC` | **stub** (one line read by `simple_lock` at A8C0 with a bogus pointer, every run) | logged; not a device |
| Residual data (what the firmware tells AIX) | built by the firmware from the above | depends on the stubs above (Serial, NvramSize, model code) | see "The blocker today" |

## Log of stubs found, by date

- 2026-10-17: the IDE/floppy probes (`3F6`/`376`, `3F4`/`3F5`: 65 K reads each), ports `80`-`8F`/`D0`-`DE` DMA, `410`-`415`, `3BC` checkpoints, `22C`/`23A`/`2E2`/`33A`/`3EA` (serial port probes), `278`/`378`/`3BC` (parallel probes), `78`/`7B`/`7C` EEPROM (2135 reads of `7C` per boot), `98`, `D0`, `DA`, `174`-`177`/`1F4`-`1F7` IDE (bench runs `run5`-`run7`, `run_scsi*`, `run_cbp*`).
- 2026-10-18: the bank-register writes `0800000`-`2800008` from the sizing (`FFF054B4`, every run); the kernel's `100277C0` line read; **no device access at all in the first 0.7 G instructions of AIX user space** (`run11`), so the identity check, not a device, is what stops the diagnostics boot.
- 2026-10-18 evening: the NVRAM image (the firmware's own format: header, CRCs
  skipping bytes 4-7, GE area F8-9FF, empty config area, OS area A00-BFF) is
  built into `_rtc.sv`; the VPD EEPROM's controller is modelled from the
  firmware's `EEPROM_*` routines (command word hi/lo at 79/78, start bit 7 of
  7C, status bits 7-4 polled, data at 7B:7A, the alternate register set by bit
  3 of 7C with the size code at 78); both await the bench (build8). The RTC's
  time already comes from Main (hps_io's rtc); NVRAM/CMOS persistence is for
  the Main_MiSTer branch.
- 2026-10-23: no new stubs under AIX's `cfgmgr` on the bench (`run24`/`run25`: the 8237's `0D`/`D4`/`D6`/`DA`, `808`, `CFC` reads); the 53C810's gap under `ncr810dd` (no `cd0`) is the install CD's blocker.
- 2026-10-23 evening: the 53C810 under `ncr810dd`: the 80-FF alias in the special register cases and the SIOM/DIOM memory moves to our own registers are fixed (`2df9a08`, `1440701`); on the board the scan now runs but ends in a SELECT that never completes and a bus fault (`bringup_log.md`).
