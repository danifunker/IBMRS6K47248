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

**Now: `set_boot` crashes on the firmware's boot path.** `set_boot` (no argument) reads the NVRAM's
`fw-boot-device` from the name space: ours is the 7248 firmware's SCSI CD path
`/pci@80000000/pci1000,1@10,0/cdrom@3,0`; `GetNSBootDevice` (set_boot+0xD58) counts the path's components,
looks for a ':' after the second one, finds none, and does `strlen(NULL)` + `lbz -1(0)`: KERN_INVALID_ADDRESS
at 0x02001130 ("Master Server exception handler (task=.../os2/set_boot)"). The device names it builds are
`devices/hd0`, `devices/hd2` ("Defaulting to IDE CDROM at HD2": the real 850 has its CD on the secondary
channel; ours is the primary master, hd0 in `logdev.stz`: `isa0/planar_ide_0:-8` unit 0, whose dev_subclass
dd_ide changes to `cdrom`). `set_boot` takes the device as a plain argument instead ("Boot device set to %s
as specified", then `AddBootDevice`: node `boot_device`, attribute `name`), so the run in progress at
hand-off types `devices/hd0` at set_boot's `[PN_FILE_ARGV=""]` prompt (dbgauto rule
`'set_boot@PN_FILE_ARGV=>devices/hd0'`; pagrinit `-d1` for its messages). Longer term the firmware's
`fw-boot-device` (what the 850's own firmware writes for an IDE CD: probably with a ':' partition suffix)
or a modelled NVRAM string would make the untouched boot.cfg work.

What should follow set_boot: `bvm`, `ade`, `initld`, `initldev`, `utilfs`, `pagrinit` (WAIT: mounts the system
volume through BVM, which reads the CD through dd_ide: the first PACKET commands to the ATAPI model on the
board; `sim/atapi` covers INQUIRY, READ, short byte counts), then `personal/insmain`, the install program,
which should finally touch the S3 (nothing has yet: the console driver's video init is lazy).
## Open issues and the next step

- The run with `devices/hd0` (log `Y:\ibmrs6k-bench-logsoard_os2g_dbg.raw`, transcript
  `scratch/work/os2_com1_os2g.log`): read its end; if BVM/pagrinit mount the CD, expect the first ATAPI
  PACKET commands (`Wnq F7:A0` in the decoded stream) and then video. If `set_boot` still fails, its
  messages are in `OS2/SET_BOOT` (strings base 0x02000138: `kdis.py`'s output with the anchor
  `fw-boot-device` at +0x1d8).
- The FDC's seek time is new: re-check the firmware's diskette boot (SMS from the configuration diskette)
  and NT's ARC diskette on the board; both polled or waited on the interrupt before, but never had to wait.
- `dd_ide` units 1-3 fail `io_ext_create` (rc 5) for the absent positions, printed as errors; harmless so far.
- The loader crashes (Program Exception at 0xCC14, dar A0000040) after some 60 stray Enters at its device
  prompt: answer prompts from the text, never blindly.
- The stream's DBG_DEVLOG/COM1TX probes cost ~250 ALMs; the core is at 99 %. CD audio is still on.
