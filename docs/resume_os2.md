# Resume: OS/2 Warp for PowerPC on the IBMRS6K7248 core (the Power Series 850 personality)

(Written 2026-10-31 at the end of the session that took OS/2 from an idle microkernel to its logo on the
display. Paste from "The task" down into a new session in this repository. The day's details are in
`docs/bringup_log.md`, sections 2026-10-29 to 2026-10-31.)

---

## The task

Get OS/2 Warp for PowerPC (the CD `OS2-Warp-PowerPC.iso`, the PReP loader "IBM Microkernel Bootloader") to its
**installation screen** on the display, and save a screenshot of it in `docs/images/`. Today the boot gets
as far as the Warp logo; the installer `insmain` then fails on the name space before drawing anything
("Where it stands", below). Work through blockers one at a time; commit to master locally; keep this file,
`docs/bringup_log.md` and `docs/stubbed-hardware.md` current.

## How to boot it on .92 (the board)

- OSD: **Model = Power Series 850** (planar ID F1, saved on .92). With the 7248 ID the loader's SCSI boot
  driver probes PCI device 12 instead of 16 and finds no CD. The OS/2 CD is mounted as the CD image (the
  OSD's `OS2-Warp-PowerPC.iso` entry), `blank144.img` as the diskette, `os2_warp_ppc.img` as the disk.
- UART mode **None** (saved): ttyS1 carries the core's debug stream at 115200. The debug build
  (`IBMRS6K7248_DEBUG`, `DBG_COM1TX` and `DBG_DEVLOG` on in `IBMRS6K7248.sv`) puts **COM1's transmitted text
  in that stream** (bytes with bit 7 set; COM2's after a 0x80 byte), so one run gives the OS's text, the
  device log and the alive marks. Do not use UART mode Console for a boot capture: a core load through the
  OSD re-applies the saved mode (memory `uart-mode-reset-on-core-load`).
- The loader talks on COM1 at 9600 and must be answered: Enter at "Press ENTER for manual boot", `cd3` at
  `[PN_BOOT_DEV="automatic"]`, `cdrom` at `[PN_BOOT_FS=...]`, Enter at each of the ~296 `boot.cfg` lines.
  `scratch/work/dbgauto.py` does it from the stream's text (its rules: `'PN_BOOT_DEV=>cd3' 'PN_BOOT_FS=>cdrom'`);
  it runs detached on the board. The whole procedure, from this PC:
  1. `scratch/work/stage_rbf.sh RBF TAG` (copies to `/media/fat/_Unstable/IBMRS6K7248.rbf`, takes `/tmp/board.lock`);
  2. the board side: `/sbin/uartmode 0`, kill agetty, `setsid nohup python3 -u /tmp/dbgauto.py 4200
     /tmp/os2_dbg.log 'PN_BOOT_DEV=>cd3' 'PN_BOOT_FS=>cdrom' &` (the session's `dbg_run.sh` did exactly this);
  3. load the core through the OSD with misterkvms-cli: F12, Right, Enter, Enter, 30 s apart (`kvstep.ps1`);
  4. ~25 minutes later the kernel is up; fetch `/tmp/os2_dbg.log` (raw, to `Y:\ibmrs6k-bench-logs\`) and
     `/tmp/os2_dbg.log.com1` (the transcript).
- Decoding the stream: the session's `devlog.py` (in its scratchpad; worth copying into `tools/`) prints the
  events in order: `Wnq`/`Rnq` the IDE, 0838, 8042 and 53C810 accesses (`b` the byte lanes, `aa` the port's
  low byte: F7 = 1F7, F6 = 1F6 or 3F6, 38 = 0838), `Ddv`/`ddv` every other ISA port and PCI memory page,
  `IACK vector vv` each interrupt the CPU takes, `PIC port 021/0A1/4D0/4D1 <= dd` the masks and the ELCR,
  `DEC n` the decrementer exceptions so far (every 64), `COM1 ...` the text, `...N alive marks (pc .. pc)`.
  `scratch/work/mksyms.sh ADDR...` names kernel addresses (MK_TEST.PPC has function symbols; no data
  symbols). `kdis.py MK_TEST.PPC VADDR LEN` disassembles it (capstone, in WSL); `kdis.py ... scan` lists
  its decrementer/timebase/PVR accesses.

## Where it stands (2026-10-31 03:15)

**The OS/2 Warp logo is on the display** (`docs/images/os2_warp_ppc_logo_20261031.png`, build os2k =
commit `fb3ea29`, `scratch/work/IBMRS6K7248_os2k.rbf`, staged in `_Unstable`): pagrinit mounts the CD
("Boot volume is a CD"), loads `os2/vpmisrv` (the video server: PCI walk, "adapter found" 88c05333 at
8000_7000, `s3_864.pmi` loaded, "PMIREQUEST_SETMODE mode id: 1", SETCLUT) and `os2/logovid` (the logo), then
`personal/insmain`, and polls "Waiting for PI to complete..." (200 times, then it stops polling; the
transcript `scratch/work/os2_com1_os2k.log`, the stream `Y:\ibmrs6k-bench-logs\board_os2k_dbg.raw`).

**The blocker now: `insmain` fails before drawing anything.** Its text on COM1:
`Error: RC = 23: NS Convert Error / Occurred in file filertns.c / Function NS_GetAttr Failed.`, then
"Searching for the boot device...", `GETPERS: NS_Resolve passed (0), handle = 2`, `ReadNode Passed,
node_contents = 19008`, `port_create: (?/?) unknown system code (error code=0x00000000)`,
`_GEN_XferData -> mach_msg_overwrite : ... (error code=0x10000003)` = MACH_SEND_INVALID_DEST: insmain
sends to a port it got from the name space and the port is dead or null. The likeliest cause is the
hand-made boot device: `set_boot devices/hd0` (below) adds node `boot_device` with only a `name`
attribute, while a real boot (the NVRAM path parsed by `GetNSBootDevice`) goes through `GetDevType` on
the device node first; insmain's GETPERS ("get personality"?) then resolves the boot device and wants an
attribute (a port, "device_type", "system_bvm_name"...) that is missing or of the wrong type (RC 23, a
conversion error). To find out: `OS2/INSMAIN` is not on the CD under that name (pagrinit loads
`file/system/personal/insmain` from the mounted volume: `PERSONAL/INSMAIN` on the ISO); extract it and
look at GETPERS and at the NS_GetAttr call in `filertns.c` (the strings say which attribute); compare
with what BVM/pagrinit put in the name space ("system_bvm_name", "system_partition_type" are attributes
pagrinit reads from the boot volume). A cheaper experiment first: make set_boot's own parser succeed so
the node is built its way: its string wants `.../<bridge>/<device>:...` with a ':' after the second
component; the loader prints the firmware string, and the core could carry a different `fw-boot-device`
in the NVRAM image (the firmware rewrites it at boot? check) or the 850 personality could answer the
firmware with an IDE path. Failing that, build the node as GetNSBootDevice would (read its code at
SET_BOOT+0x12A8-0x1350: GetDevType(devices/hd0) == 3 (cdrom), then AddBootDevice).

The path that works today, end to end: the loader (COM1, manual mode), the kernel, console0/ide0/floppy0,
conmgr/devmgr, ffpnserv, fs, set_boot (with `devices/hd0`), bvm, ade, initld, initldev, utilfs, pagrinit,
vpmisrv (mode 1 set on the S3 864), logovid (the logo drawn through the VGA window), insmain started.

**The fixes that got here (all on master):**

| Commit | What |
|---|---|
| `c65ae47` | FDC: RECALIBRATE of an absent drive ends ST0 71; COM1's text in the debug stream (`DBG_COM1TX`). |
| `dba46f6` | The stream's interrupt acknowledges, PIC masks, decrementer count, COM2 text. |
| `0a61ebf` | **FDC seeks take their step time** (the kernel idled: dd_flopp's wake-up lost to an instant interrupt). |
| `eb671bb` | **READ CD (BE)** in the CD target (BVM reads the disc with it); dbgauto's per-file prompt rules. |
| `8237b4c` | **ATAPI: a 2 ms command latency** (dd_ide's wake-up lost to an instant DRQ). |
| `b1b6067` | **ATAPI: a 4 KB buffer**, 4096-byte counts in one DRQ block (the 2 KB split left a phantom 0838 interrupt). |
| `197bda1` | **ATAPI: the interrupt stays pending through nIEN** (dd_ide waits for the completion interrupt after re-enabling). |
| `fb3ea29` | The device log off (the build did not fit with it). |

## Open issues and the next step

1. insmain's failure above: the boot_device node / GETPERS. Start with `PERSONAL/INSMAIN`'s strings and
   code (capstone through `kdis.py`/`strref.py`, which resolve a function's string references), and with
   what `GetNSBootDevice` would have added. Re-run with the same dbgauto rules (`dbg_run.sh` in the
   session's scratchpad; copy it and `devlog.py`, `kdis.py`, `strref.py`, `syms.py` into `tools/`).
2. `set_boot`'s parser and the firmware's `fw-boot-device` (a SCSI path on a machine whose OS/2 has only
   dd_ide): the clean fix is an IDE path with a ':'; see what the 850's firmware would write.
3. The FDC's seek time and the ATAPI changes are new: re-check the firmware's diskette boot, NT's ARC
   diskette, AIX's cd0 (the SCSI CD is untouched, but the target's READ CD is shared), and NT's CD (ATAPI
   under the 850 ID is OS/2-only so far).
4. dd_ide units 1-3 fail `io_ext_create` (rc 5): harmless.
5. The loader crashes after ~60 stray Enters at its device prompt (Program Exception at 0xCC14): answer
   prompts from the text, never blindly (dbgauto does).
6. The core is at 99 %: `DBG_DEVLOG` is off now (the device log; it hid the CDBs anyway once the data-port
   reads flooded its FIFO: exclude 1F0 reads from it before turning it on again). CD audio is still on.
7. The user plans two Quartus revisions (IBMRS6K7248, IBMPS850): not started.
