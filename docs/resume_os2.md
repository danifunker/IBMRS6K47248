# Resume: OS/2 Warp for PowerPC on the IBMRS6K7248 core (the Power Series 850 personality)

(Written 2026-10-30 at the end of the session that took OS/2 from the loader's prompt to an idle microkernel
and instrumented the core to see why it idles. Paste from "The task" down into a new session in this
repository. The day's details are in `docs/bringup_log.md`, sections 2026-10-29 to 2026-10-30.)

---

## The task

Get OS/2 Warp for PowerPC (the CD `OS2-Warp-PowerPC.iso`, the PReP loader "IBM Microkernel Bootloader") to its
installation screen on the display. The microkernel boots, its drivers initialise, and the system then idles
forever without touching video (below). Work through blockers one at a time; commit to master locally.

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

## What was done this session (all on master)

| Commit | What |
|---|---|
| `c65ae47` | FDC: RECALIBRATE of a drive other than 0 ends with equipment check (ST0 71), as the 82077 with no TRK0; SENSE DRIVE STATUS's TRK0 only for drive 0; `sim/floppy` case. COM1's text in the debug stream (`DBG_COM1TX`). |
| `dba46f6` | The stream's interrupt acknowledges, PIC mask and ELCR writes, decrementer-exception count, COM2 text. |

## Where it stands

**Fixed (commit `0a61ebf`): the idle kernel.** The floppy driver `dd_flopp` probes drive B at init: `start_drive`
(DOR, a 0.5 s motor wait, a timeout timer, "interrupt expected" = 1), `recal_start` (RECALIBRATE), then
`condition_wait` in `flop_device_init`. Our FDC finished the recalibrate in the clock the command was written,
so IRQ 6, the kernel-side ISR (SENSE INTERRUPT STATUS), the higher-priority interrupt thread and its
`int_step` (cancel the timer, `condition_signal`) all ran before the waiter waited; a cthreads signal with no
waiter is lost, so `flop_device_init` slept forever, `DriverReady` never reached the device manager, which
`condition_wait`s for it before exiting, and the bootstrap never started the servers after the drivers. A
real 82077 steps for milliseconds (79 steps for an absent drive). The FDC now takes SRT per step (the drive
busy in the MSR, SENSE INTERRUPT STATUS 80 meanwhile); ST0 71 for the absent drive B. With it the boot goes
on: "FS Server is up (multi-threaded mode)", then `set_boot`.

**Worked around: `set_boot` crashes on the firmware's boot path.** Without an argument it parses the NVRAM's
`fw-boot-device` (ours: the 7248 firmware's SCSI CD path `/pci@80000000/pci1000,1@10,0/cdrom@3,0`) and does
`strlen(NULL)` when the path has no ':' (`GetNSBootDevice`, SET_BOOT+0xD58, KERN_INVALID_ADDRESS at
0x02001130). Its device names are `devices/hd0`-`hd3` (the real 850's CD is `hd2`, the secondary master;
ours is the primary master, `hd0`). Typing `devices/hd0` at set_boot's `[PN_FILE_ARGV=""]` prompt makes it
take that as the boot device ("Boot device set to %s as specified"); dbgauto's rule
`'set_boot@PN_FILE_ARGV=>devices/hd0'` does it (and `'pagrinit@PN_FILE_ARGV="-s60"=>-d1'` for pagrinit's
messages). A proper fix would be the IDE path the 850's firmware writes (unknown; it needs a ':' after the
second component) or set_boot's input in a modelled NVRAM string.

**Fixed (commit `eb671bb`): BVM could not read the disc.** With the boot device set, pagrinit found the volume
and mounted `volumes/hd0.0` but as a HARD_DISK, could not load `os2/vpmisrv` or `os2/logovid` or open
`os2/swapper`, and died ("*** FATAL ERROR ***"). The stream's ATAPI traffic: BVM recognises the disc with
MODE SENSE(10) 3F, READ CAPACITY and then **READ CD (BE)** (LBA 0, 1 block, user data only, byte count
4096), which the CD target refused (sense 5/20, invalid opcode) forty times; it then fell back to the
CD's MBR (the PReP boot partition, type 41) as a hard disk. The target now serves READ CD's user-data
form like READ(10) (the raw forms: 5/24). `sim/atapi` covers it.

**Fixed (next commit): the ATAPI answer came too soon.** With READ CD served, run os2h read LBA 0 (one block,
then two, delivered as two 2 KB DRQ chunks, taken fine) and then hung on a later packet: its DRQ interrupt
came (IRQ 13, status 58, I/O, 2048 bytes) and the driver never read the data. The floppy's race again:
dd_ide's thread sends the packet, then waits for its interrupt thread's signal, and a block the target
already held answered within microseconds. `IBMRS6K7248_atapi` now holds a command's first DRQ or status
(and the interrupt) for 2 ms after the command or the packet's last byte, a CD-ROM's order of latency.
Build os2i carried it, and hung the same way; the stream then showed the real mechanism: dd_ide asks 4096
bytes a DRQ (1F4/1F5 = 1000) and the 2 KB buffer split BVM's two-block read into two DRQ blocks; the driver
polls the alternate status through the second block without waiting for its interrupt, whose 0838 latch
(set again by the completion interrupt after the ISR's clear) is then taken as the *next* packet's
interrupt before that packet's CDB exists, and the real DRQ's wake-up is lost. **Fixed (commit after
`8f605e9`): a 4 KB ATAPI buffer**, a 4096-byte count served in one DRQ block as a real drive does. Build
os2j carries it; its run is the first that can reach `insmain`.

What should follow: pagrinit "Boot volume is a CD", the CD mounted with its file system, `vpmisrv` (the
base video server) and `logovid` (the logo) loaded from it, the swapper, then `personal/insmain`: the
first video accesses (the S3 864 through its VGA ports and the linear frame buffer; NT's s3.dll path in
`docs/s3_nt_driver.md` is the reference for what the core's S3 can do).
## Open issues and the next step

- Build os2j (READ CD, the ATAPI latency, the 4 KB buffer) and its run: `scratch/work/IBMRS6K7248_os2j.rbf`
  if the build finished; logs `Y:\ibmrs6k-bench-logsoard_os2j_dbg.raw`, `scratch/work/os2_com1_os2j.log`
  if the run did. If BVM's reads go past 4096 bytes a packet, the chunking returns: raise the buffer or
  look at how dd_ide handles the second DRQ block (it polls the alternate status). The
  ATAPI packets in a decoded stream: `Wnq F7:A0` then the CDB as 16-bit writes to 1F0 (`Ddv 800001F0`),
  the data as reads; the session's extraction snippet is in the bringup log's method (a PACKET, its CDB,
  byte count, data words, status/error). BVM may ask for more than READ CD: watch for new 5/20 refusals
  (READ TOC, READ DISC INFO, GET CONFIGURATION, MODE SENSE pages).
- The earlier runs' logs: os2g holds the READ CD refusals and pagrinit's messages; os2h the hang after
  the third READ CD. The stream's device log (`DBG_DEVLOG`) stops after 16383 entries: a run with many
  data-port reads loses the later CDBs (raise `dv_n`'s width or exclude 1F0 reads to see them).
- The FDC's seek time is new: re-check the firmware's diskette boot (SMS from the configuration diskette)
  and NT's ARC diskette on the board; both polled or waited on the interrupt before, but never had to wait.
- `dd_ide` units 1-3 fail `io_ext_create` (rc 5) for the absent positions, printed as errors; harmless so far.
- The loader crashes (Program Exception at 0xCC14, dar A0000040) after some 60 stray Enters at its device
  prompt: answer prompts from the text, never blindly.
- The stream's DBG_DEVLOG/COM1TX probes cost ~250 ALMs; the core is at 99 %. CD audio is still on.
