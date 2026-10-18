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

## The blocker today: the machine's identity (2026-10-18)

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

The exact source of `modelcode` is still being traced in `cfgsys_rspc`
(`scratch/work/aix/ramfs.img` at 0x63C000); whichever it is, the fix is on
this list: a real EEPROM with a 7248's VPD, and an NVRAM the firmware accepts
(or pre-initialised with a 7248's contents).

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
| 8237 DMA + 82378 extensions | `00`-`0F`, `80`-`8F`, `C0`-`DF`, `40A`/`40B`, `410`-`417`, `481`, `4D6` | **stub** (writes logged) | firmware floppy/audio; AIX floppy, audio, ECP | the firmware's `dma_setup` writes are dropped harmlessly today; a floppy or audio DMA needs the channel logic |
| 8042 keyboard/mouse | `60`/`64` | **real** (PS/2 keyboard and mouse) | firmware SMS, AIX `kbddd`/`mousedd` | |
| RTC/CMOS (MC146818) | `70`/`71` | **real**; starts with `init_cmos`'s image (valid CRCs, reset bit clear) | the firmware's "boot 0" (BOOT.6XE) | |
| **PReP NVRAM 4 KB** | `74`/`75`/`76` | **partial**: the RAM is there, but blank; `nvram_good` fails (no header), NvramSize -1 | AIX: boot list, console choice, `modelcode`?; the firmware's SMS settings | **plan**: initialise it as the firmware's `init_nvram`/SMS would (header: size, version 1, revision 4, area table, CRC), or save/restore it like the CMOS |
| **VPD / security EEPROM** | `78`-`7C` (base and alternate ports) | **stub** (reads 0: the serial becomes `ffff...`) | the firmware's VPD (`build_vpd`, `GetEEPROMSerialNumber`), passwords; AIX's `modelcode`/`systemid` | **plan**: a serial command EEPROM (`EEPROM_Create_Command`/`Send_Command`: command, address, data bits through 78-7C) with a 7248-100's VPD image; first find the real layout from the firmware's reader |
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
| CS4232 audio | `220`/`240`, `388`, `200`, `330`, `534`/`535` | **partial** (silent: the codec registers answer, no sound) | firmware `audio_play` (the POST tune), AIX `cs4232` | low priority |
| IDE (Fire Coral) | `1F0`-`1F7`/`3F6`, `170`-`177`/`376` | **stub**: the firmware's probe (`3F6`/`376` reads, 65 K each) finds nothing | none on the 7248 (SCSI planar) | the 7248 has no IDE drive; keep as "no device" (reads FF would end the probe faster) |
| ISA PnP | `279`/`A79` | **stub** | firmware `build_isa` | |
| Unknown | `4690`/`4691` (`monitor_serial_port`) | **stub** | firmware | |

### PCI devices

| Device | Config / BARs | State | Needed by | Notes, plan |
|---|---|---|---|---|
| S3 Vision864 + SDAC, 2 MB VRAM | dev 14 (5333:88C0), VGA I/O `3B4`-`3DF`, S3 enhanced `42E8`-`E2E8`, LFB at CPU `C2800000` | **real** for the firmware's use (text, logo, icons, cursor, SDAC) | the firmware's screen | AIX has no driver for it on the diagnostics CD (only GXT adapters); AIX 4.3.3 proper needs the "S15" driver; the error-icon palette (dark blue on black) is open |
| NCR 53C810 SCSI, the CD at ID 3 | dev 16 (1000:0001), I/O and memory BARs | **real** enough for the firmware's boot (SCRIPTS, the CD's reads) | the firmware's CD boot; AIX `ncr810dd` (`cfgncr_scsi`) | AIX's driver will exercise more of the chip (interrupts, DMA to kernel buffers, SCSI message phases): expect gaps once the identity check passes |
| AMD Am79C970 PCnet | dev (planar Ethernet) | **absent** (config reads return no device) | AIX networking (M7) | needs the Main_MiSTer branch for the Ethernet mailbox |
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
