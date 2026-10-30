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

The transcript always ends at dd_ide's four instances (unit 0 "IDE CDROM found", "IKDD: start_ikdd
service_port = 0xda"; unit 1 and the secondary channel "io_ext_create FAILED rc=0x00000005", the absent
positions); the floppy driver then probes drive B (CONFIGURE, DOR 2D, RECALIBRATE 1, its IRQ 6, SENSE
INTERRUPT: ST0 71) and reads the MSR once more; then the kernel idles (`idle_thread_continue`,
`processor_idle`) with nothing more printed, no video access, no PACKET command ever sent to the CD. The
whole kernel phase is about 1 s of instructions. Interrupts taken in all: three IRQ 13 (the identifies), one
IRQ 6. Masks at the end: 21 = B9, A1 = CF (IRQ 0 masked: the clock is the decrementer). The 8042 dialogue
(keyboard reset, scan set 1, mouse reset FA AA 00, E9 status) completes. The IDE identify data is read
correctly (256 words, twice).

What should follow: the bootstrap task starts, in boot.cfg's order, `ffpnserv`, `fs` ("FS Server is up" is
printed only in verbose mode), `set_boot` (WAIT; it looks for the NVRAM's `fw-boot-device` in the name
space: "SET_BOOT: Looking for IDE CDROM at %s", "Defaulting to IDE CDROM at HD2"), `bvm`, `ade`, `initld`,
`initldev`, `utilfs`, `pagrinit` (WAIT: mounts the system volume through BVM, which would read the CD
through dd_ide). Nothing of that is visible on COM1 by default.

## Open issues and the next step

- (filled in below from the os2d run)
