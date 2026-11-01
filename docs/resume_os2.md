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

## insmain's failure, read from the binaries (2026-10-31, afternoon)

`PERSONAL/INSMAIN` (extracted from the ISO with `isoinfo -x`; stripped, GOT-relative code: the session's
`scratch/work/idis.py` disassembles it with the strings resolved, `xref6.py` finds a string's users,
`callers.py` a function's callers, `grepdis.py` an instruction pattern) and `PERSONAL/PAGRINIT` (the one
the CD boots; `OS2/PAGRINIT` differs) say:

- **GETPERS** (`Ins_GetBootDevice`, 020093D0): `NS_Resolve("file/system", flags 4)` → `NS_ReadNode` →
  `NS_GetAttr(node, L"name")` → on success "Setting boot volume to volumes/<name>" (gated by the same
  flag that printed the banner, so it would have shown); on failure it prints "GETPERS: Failed to get
  attribute" into a buffer that is never flushed and calls `Ins_Exit(15)` (02009000: `port_create`, then
  a message to a port it does not hold → the `MACH_SEND_INVALID_DEST` line). So **the `name` attribute
  was not found on `file/system`**. `NS_GetAttr` is libns's (ns_attrs_get_attr: name length halfword at
  +4 of the 20-byte record must equal, then memcmp): no IPC, a local search of the ReadNode buffer
  (count at +0xA, records at +0xC).
- The earlier `RC = 23 ... filertns.c ... NS_GetAttr` is `Ins_GetInstallType` opening a response file on
  the boot volume *before* GETPERS has set it (the buffer at 020BABD8 is still empty): `format_type` is
  looked up on whatever "" resolves to. Benign.
- **Who puts `name` on `file/system`: pagrinit** (020047C8, after `FS_Mount`): `name_FindFromRoot
  ("volumes/hd0.0", flags 0x24)`, `name_GetNodeInfo` (NS_ReadNode: count, attribute records), then
  `name_AddDirNode("file")` and `name_AddLeafNode("system", count, records, FS port)` (02009494 /
  020092F0): the leaf is a type-2 node carrying **the volume node's 16 attributes copied as they are**.
  BVM's `RNSInsertEntry` (02002DA8) gives every volume node these 16: device_path, device_flags,
  device_type, reference_record, start_record, volmgr_flags, volmgr_label, volume_type, volume_size,
  volume_flags, format_type, format_id, format_label, format_serial, format_flags, **name** (`SetName`:
  "hd0" + "." + partition → "hd0.0"); names stored with length strlen+1, as insmain asks for them.
  Both adds tolerate rc 24008001/8002/8004/8006/8007 silently ("name_AddLeafNode() failed" prints only
  for other codes). pagrinit's hard-disk-boot path (02004D28, "file/system" → `name`) and insmain2's
  `GetSourceVolume` rely on the same attribute, so this is the design, not an accident.
- **The FS server does not create `file/system`**: `LFS_Mount` → `fs_Mount_Mgr_Add` → `CreateLeafNode`
  makes `filesets/<fileset>` (the "filesets/bootstrap_fs" of the log), with zero attributes.
- `NS_Resolve` flag 4 means *no forwarding* (`NS_ResolveForward` returns at once when bit 4 is set), so
  insmain gets the `file/system` node itself, as pagrinit does. The name server is `RNS.dyn` on
  `LIBCNA.SO` (SOM classes; `nsd_ReadNode` → `get_attrs`, which returns the stored records when asked
  for 0xFFFF of them, as both programs do).
- Nobody else names `file`/`file/system` (all binaries on the CD scanned, ASCII and UTF-16), so pagrinit's
  node is the one insmain reads, and statically it must carry `name`. **Statically everything is
  right; at run time the attribute is not there.** Suspects: pagrinit's leaf add failing with a
  tolerated code (then `file/system` would not exist — but the loader did load
  `file/system/os2/vpmisrv` through it), or the 16-attribute node (a ~1.2 KB IPC reply, out-of-line
  memory, where the one-attribute `boot_device` node that pagrinit does read correctly is inline) being
  read back wrong: a VM/MMU/cache problem of the core rather than OS/2's.
- Also learned: the CD boots `/BOOT.CFG` (root), whose pagrinit line is `-s60 -mdummy -odummy -rdummy
  -ipersonal/insmain -kpersonal/insmain2`; `/BOOT/BOOT.CFG` is the installed system's. dbgauto's
  `pagrinit@PN_FILE_ARGV="-s60"=>-d1` *replaces* `-s60` by `-d1` (the pager size falls back to its
  default, 60: harmless). `-d1` only gates prints; the step it seems to skip (`RunChkDsk`) is gated by a
  boot-volume field, not by the debug level.
- **The probe (build os2l):** nine (PC, instruction-word) watch points in the debug stream, each hit a
  "~c" token: insmain's lookup (`G` the NS_GetAttr call, `a` per attribute compared, `A` found, `x` not
  found, `g` GETPERS's check) and pagrinit's AddLeafNode return code (`p` reached, `q` not 24008002, `r`
  none of the tolerated codes, `s` not 0). `G a×16 x g` means the attributes are there but none is
  `name` (data); `G a x g` means one attribute (the `file` directory's: a partial resolve); `G x g`
  means an empty list; `p` alone means the leaf already existed; `p q r` and no `s` means the add
  succeeded. `scratch/work/run_os2l.sh TAG` stages, starts dbgauto, presses the OSD keys and fetches
  the stream (`Y:\ibmrs6k-bench-logs\board_TAG_dbg.raw`) and prints the token sequence.

**Run os2l (the probe) answered it:** the token sequence was `pqr` then
`GaaA GaA GaaA GaA GaaA GaA Gx Ga×12A Ga×17Ag Ga×12A`: pagrinit's leaf add returned 0, and insmain's
GETPERS lookup **found** `name` (17 attributes compared, hit, `g`) — the "Setting boot volume to" line
simply does not reach COM1. The `Gx` with no attribute compared is the benign response-file check. So the
name space is fine, and the fatal step is the one *after* GETPERS and the two message catalogs: insmain's
`format_and_send_msg` / `GetPercentage` ("Sending to UFS Port = %d") talk to the **UFS server** (utilfs:
the fdisk/format/chkdsk service, `servers/utilfs`, registered by utilfs's `RegSrvPort`), and the send in
`GEN_XferData` fails with `MACH_SEND_INVALID_DEST`: the port name insmain holds for the UFS is dead or null
(MACH_PORT_NULL gives the same code). insmain's messages ("Partitions Found", "Drive Not Found", "Hard
drive not Large Enough for system") say what comes next: the installer looks for the **hard disk** to
partition and format through utilfs — and the 850 personality gives OS/2 no hard disk at all (only the IDE
CD; the disk image is on the SCSI bus this OS/2 has no driver for). Whether the dead port is utilfs having
exited, or a lookup that never happened, the os2m probe (`u` utilfs serving, `t` its loop ended, `U` a
request handled, `R`/`n` its registration and failure, `f`/`F` insmain's two "couldn't find UFS" sites,
`k` GetPercentage's send, `e` Ins_Exit, `X` GEN_XferData's send) tells; an **IDE hard disk model** on the
850's primary channel (unit 1, or the secondary channel: OS/2's dd_ide probes 1F0 units 0-1 and 170
units 0-1, "io_ext_create FAILED rc=5" for the absent ones) will be needed for the install screen's
target in any case.

**Run os2m:** `R u e U X` — utilfs registers and serves; insmain's "Running Media Preparation..." send
(02009000: `port_create` + a UFS message) is handled by utilfs (`U`), then insmain's `GEN_XferData` send
fails; no "couldn't find UFS", `GetPercentage` never reached, utilfs never exits. The hard disk is the
thing to give it: build os2n (`IBMRS6K7248_idehd`, the OSD's disk 0 image as the IDE slave).

## Where it stands (2026-10-31 12:30): the installation screen

**"Welcome to the OS/2 Warp (PowerPC Edition) Installation Program"** is on the display
(`docs/images/os2_warp_ppc_install_20261031.png`; build os2n = commit `c463242`, `scratch/work/
IBMRS6K7248_os2n.rbf`, staged in `_Unstable`; the transcript `scratch/work/os2_com1_os2n.log`, the stream
`Y:\ibmrs6k-bench-logsoard_os2n_dbg.raw`). With the IDE hard disk (the OSD's disk 0 image,
`OS2_warp_ppc.img`) insmain's media preparation goes through: `fd_sys.c: Prepared to read the IDE boot
loader record`, `GetSystemPartitionData returned 0 (144049 bytes)`, vpmisrv sets mode 1 again and the
installer's first panel is drawn (F1 Help, F3 Exit, Enter Continue). dd_ide still prints nothing for
unit 1 (its "io_ext_create FAILED rc=5" lines are the secondary channel's two units); the disk is
reached, so the slave was found.

The boot procedure is the one above (`scratch/work/run_os2l.sh TAG` does all of it from this PC: stage,
dbgauto with the four rules, the OSD keys, the wait, the logs). The keyboard has not been tried on the
installer yet (the 8042 works for the firmware and NT). The next steps are the installer's own: Enter
through its panels (partitioning through utilfs's fdisk/format on the IDE disk, then the file copy
from the CD), with the COM1 transcript watching for the next complaint.

## The installation runs (2026-10-31, afternoon): the format, the file copy, and where the time goes

Build os2o (commit `aba4cdd`: the disk side in chunks of 32 sectors, one READ/WRITE(10) a chunk, the
host still seeing ATA's per-sector blocks) took the installer through Easy Installation (a 340 MB FAT
primary partition, formatted) and into the file copy: "File 1178 of 2045" at 15:23, 1260 at 15:33
(`OS2/DLL/...`), so ~8 files a minute and the copy about two hours in all. The format of 340 MB had
taken about an hour. The user's verdict: "disk writes are still horrendously slow".

What the debug stream says (`/tmp/os2_dbg.log` on the board; the `W/R` tokens parsed by the scripts in
the session's scratchpad: `tok2.sh`, `tok3.sh`): the stream was saturated (every IDE register access
was a 14-byte token at 115200 baud, 820 a second at most, the 64-entry FIFO dropping the rest), so
counts are samples, but the per-sector protocol of OS/2's dd_ide is plain in the complete bursts right
after a command: READ/WRITE SECTORS only (no SET MULTIPLE ever; A0 = 160-sector writes, 256-sector
reads), and for each sector an interrupt, then `R1F7 W3F6=0A R3F6 R1F7 R3F6 R3F6 W3F6=08` (status,
nIEN on, the data, alt status, status, nIEN off) and the 0838 latch read and cleared. An apparent
interrupt storm (six 0838 acknowledges a status read) is the FIFO's sampling of those bursts, not the
core (the latch is edge-set from `ipend`, which only a 1F7 read or a command clears).

So a sector costs the OS's interrupt path (the Mach interrupt, the driver thread's wake-up, 256 PIO
reads) plus, per 32-sector chunk, the Main's round trip; the format's rate (680K sectors in ~55 min if
it writes them all) puts the sum near 5 ms a sector, and the stream cannot say how it splits. Two
things found on the board meanwhile: the ARM is at 0 % idle (Main 30 %, an `sftp-server` 25 % that has
read `/sys` continuously since 2026-10-27 - the kvm tooling's USB/IP watch, it seems - and the stream
reader 11 %; load average 4.4 on two cores), which stretches every Main round trip; and `/media/fat` is
mounted `sync,dirsync`, a 16 KB write costing 8.4 ms median (0.26 ms a sector: not the problem).

Build os2p (uncommitted while it compiles) measures instead of guessing: the machine logs only the IDE
commands (1F7 writes) to the stream, and the top emits, each second the disk moved anything,
`Hiiiibbbb ` (interrupts raised, host blocks done) and `Mddddhhhh ` (milliseconds on the disk side -
the SCSI target and the Main - and on the host's: its interrupt latency and PIO). If the disk side
dominates, double-buffer `IBMRS6K7248_idehd` (fetch the next chunk while the host drains this one,
write the last while the host fills the next: the "write cache" the user asked about); if the host's
does, the per-sector interrupt is the driver's and only a DMA path (the Carolina's scatter/gather, which
shares IRQ 13 with the IDE: unknown registers) would change it.

Boot time (the user's "35 minutes"): the run's 5-minute settle in `run_os2l.sh` and dbgauto's 2 s quiet
time (now 0.8 s) are the PC side; the OS's own boot from CD is ~12 minutes of the rest.

## Booting the installed system (2026-10-31, evening)

"Installation Complete, remove the CD-ROM and restart the PowerPC" came at 16:06 (the copy's second
half ran three times faster once the stream reader on the board was stopped: the ARM's contention
again). The restart, with the CD still mounted (the firmware boots the loader from it) and dbgauto's
disk rules (`RULES` in `run_os2l.sh`; mind its sed delimiter, now `%`), found three things:

1. **The firmware booted the disk's PReP partition.** The installer wrote a type-41 partition at
   sector 63 (the "IDE boot loader record") and the firmware, which sees the same image as SCSI disk 0,
   loaded it instead of the CD and spun at 6F50 with nothing on COM1. Workaround on the image: its type
   byte (offset 450) set to 40 so the firmware skips it (put 41 back if OS/2's own boot path is ever
   wanted). The core's fix (`IBMRS6K7248_machine`, build os2r): under the 850 personality with a disk
   image mounted, the 53C810 finds nobody at ID 0 (its selection is dropped and answered with a
   selection failure); the IDE disk still reaches the image as its own initiator.
2. **The loader takes `ide_hd1` and `FAT_HARDDISK`** at its device and file-system prompts (first try)
   and walks the installed `BOOT.CFG` (the full driver set: pcmciabm, dd_pp, dd_seria, dd_trs, midi,
   audio, the i*.so kernel extensions, kernel symbols and the dump name), then `set_boot`'s argument
   (`devices/hd1`, offered twice: the installed config comments its argument out and leaves an empty
   one) and pagrinit's `-d1`.
3. **dd_ide gave up the whole channel: `io_ext_create FAILED rc=5` for all four units**, and PAGRINIT
   ended with `BVM_GetNextEntry() failed, rc = 0xC` / `BOOT VOLUME NOT FOUND` / FATAL. Not the extra
   drivers (a boot with the CD's driver set, BOOT.CFG patched and restored, failed the same way) and
   not the binaries (every `mk/` file on the disk matches the CD's). The stream shows the probe:
   device 0 selected, nIEN set, a NOP (command 00), the status read. The CD boot read 51 (DRDY, ERR)
   and went on to IDENTIFY both units; the disk boot read 11 (no DRDY) and stopped. The ATAPI model
   keeps DRDY clear from reset until a command sets it, and the CD boot's loader had used the CD; the
   disk boot's had not. Fix (`IBMRS6K7248_atapi`): the aborted-command path sets DRDY too, as a drive
   out of reset would (sim/atapi and sim/idehd pass). Build os2s carries it with os2r's changes.
4. **With both (builds os2s, os2t: the PReP type back at 41, the 53C810 kept off ID 0 - verified), dd_ide
   starts the CD and the disk** ("IDE CDROM found", service ports 87 and BB) and PAGRINIT reaches
   `LD_InitPhysical: Before AddNodes`, then waits for good. The CD's registers (logged for device 0
   alone, build os2t) show the kernel's probe packets completing by polling the alternate status - no
   status-register read, no interrupt - and the second READ CAPACITY waiting after its packet. In the
   CD boot the same packets went through the 0838 latch (read, acknowledged, status read). The loader
   had left the disk's interrupt pending; the kernel's first nIEN toggle re-raised it into the latch
   while nothing listened, and dd_ide never clears 0838 first: IRQ 13, edge-triggered at the PIC, stayed
   high. The installed BOOT.CFG's extra drivers are innocent (the CD's driver set hangs the same way;
   the config was patched and restored twice, `/tmp/os2hd` loop-mounted on the board at offset
   3024*512). Fix (build os2u): 0838 bit 0 is the IDE request as it stands (`ide_irq`, the Carolina's
   "request-active" register), not a latch; the acknowledging writes clear nothing.
5. **Build os2u boots the installed system** (commit after `0b2ec3c`; `scratch/work/IBMRS6K7248_os2u.rbf`,
   staged in `_Unstable`): PAGRINIT finds the boot volume, dsi sets it to `hd1.1`, `os2/rs` writes
   `\boot.dat` and `\registry.dat`, `os2srv -V hd1.1` comes up ("OS/2 Server Initialization Complete"),
   PMWIN creates the desktop, STARTUP.CMD runs, the Workplace Shell comes up with the "Introducing OS/2"
   tutorial, which F3 from the kvm closes (the keyboard works under PM): the OS/2 System folder, the
   LaunchPad, STARTUP.CMD's window at `C:\MVM` (`docs/images/os2_warp_ppc_desktop_20261031.png`, 19:00).
   The boot takes ~13 minutes from the core load (firmware, the loader walking the config at 9600 baud
   with dbgauto's Enters, the kernel), the desktop ~6 more. The counters over the whole boot
   (`Y:\ibmrs6k-bench-logs\board_os2u_dbg.raw`, `hm.py`): 67,310 host blocks, 0.67 ms a block on the
   disk side against 6.23 ms on the host's. So the Main's round trip is a tenth of the disk's time; the
   rest is OS/2's own per-block interrupt path (dd_ide's thread wake-up and PIO on the 70 MHz CPU).
   Double-buffering the disk would gain that tenth at most; the user's "fast write cache" question has
   this answer. The exception tracer (`DBG_PC`) and the COM1 bit timing are off for room; the fit is at
   the device's edge (4191 LABs).

## The desktop's trails (2026-10-31, night)

Dragged windows left outline trails: the S3 engine's pattern fill started its 8 x 8 at each rectangle's
corner, while the chip (86Box) aligns it to the screen, and 864gradd fills a brush one clip rectangle at a
time. Fixed in `IBMRS6K7248_s3ge` (build os2v, `scratch/work/IBMRS6K7248_os2v.rbf`); see the bring-up log.

## Open issues and the next step

1. (closed: the install screen is up) insmain's failure was the missing hard disk; the name space was fine. Start with `PERSONAL/INSMAIN`'s strings and
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
