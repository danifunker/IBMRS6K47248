# Resume prompt: the little-endian hang (Windows NT's ARC diskette on the board)

(Written 2026-10-25 by the Windows session that fixed the floppy. Paste everything below the
line into a new session started in this repository.)

---

## The task

Find out why IBM's ARC diskette (the Windows NT boot loader for PReP) stops right after it
switches the machine to little-endian mode on the MiSTer, and fix the core. NT 3.51/4.0, OS/2
Warp PPC and Solaris 2.5.1 all run little-endian, so this path gates all of them. AIX and the
firmware are big-endian and work.

## Where things stand

- **Branch:** `master` (the floppy fix 5b80286, then the 7248 SMS diskette in `releases/`, 15ace16).
  The floppy works on the board: SMS 1.07 (`releases/7248_SMS_v1.07.img`) loads and runs, and
  diskettes boot. The ISA DMA's 64 KB page carry (`rtl/machine/IBMRS6K7248_dma.sv`) was the
  floppy's last bug; see `docs/bringup_log.md`, 2026-10-25 later.
- **Board:** .92 (MiSTer-SS1). The core is in `/media/fat/_Unstable/IBMRS6K7248.rbf`, a full
  DEBUG build (debug UART stream with the System page's UART mode None). Take `/tmp/board.lock`
  in WSL (noclobber) before driving it; the user also uses it.
- **Media on .92** (`/media/fat/games/IBMRS6K7248/`): `rs6karc151.img` (the ARC diskette, MD5
  `3e1de7e753e24073eeca27f3c4298566`), `winnt40wks_sp1_en.iso`, `NT351_PPC_Disc01.iso`,
  `NT4_ppc.img` / `NT351_ppc.img` (2 GB disks), `OS2-Warp-PowerPC.iso` / `OS2_warp_ppc.img`.
  The OSD's Memory is 112 MB (OS/2 is said to be unstable above 64 MB).

## The ARC diskette

`rs6karc151.img` is a PReP boot diskette: an MBR with one type-0x41 partition (start sector 1,
1855 sectors); the boot header at byte 0x400 gives entry 0x400, length 0xE7C00 (949,248 bytes).
Strings: "Version 2.11 EC, compiled Oct 15 1996", "Copyright (c) 1993-96 IBM Corp., Microsoft
Corp., Motorola"; it names IBM-6015/6020/6030/6040/6042/6050, 6070, 7248, Woodfield, Carolina,
Sandalfoot, Polo. A copy is in `scratch/downloads/arc/` on the Windows machine (untracked);
otherwise fetch it from .92. The project notes (`docs/emulators_and_software.md`) also list
tenox's `arc151.dd.lz` (MD5 of the .lz `2295afbaa47874e27fc60e9f2bbd936a`).

## What the board showed (2026-10-25, 60 s of the debug stream)

Booted with the ARC diskette as Floppy, nothing pressed (the diskette is ahead of the disk in
the boot list):

1. The firmware reads the diskette, hands off (progress 2F: the stream's post-hand-off logging is on), and the ARC code runs big-endian:
   external interrupts are taken (`P...-500` tokens), it polls the 8042 (`[0x64=10]` reads),
   sets up COM1 (`13F8=00000003`, `43F8`, `83FC`), disables the DMA controller (`cmd=04`,
   `allmask=0F`).
2. Its progress codes on port 80: 31 34 32 A0 A1 46, then 47.
3. Port 92 written 00 (`K=00`), then **02** (`K=02`): the switch to little-endian.
4. Progress 48. Then the alive marks (the PC every 2^24 instructions) cycle forever through the
   same 13 addresses, translated, in the 0x80700000 region:
   `807011B8 806F8918 806F8874 806F97D8 806F8948 807011B8 806F8898 806F97C0 806F8958 806F8930
   806F88A8 806F8864 806F97C8`. No exceptions, external interrupts or logged I/O after that.
   The screen stays on the white PowerPC logo (the POST icons gone); ARC never draws.

So: not a crash; a wait for something that never comes, right after the LE switch. Suspects, in
no order (none checked):
- an interrupt it waits for (no `-500` after the switch: the 8259's acknowledge, `BFFFFFF0`,
  read through the LE lane swap? the decrementer, which the stream doesn't log (vector 900)?);
- a device register read with its bytes in the wrong lanes in LE mode (the PIT's latched count,
  the RTC's update-in-progress bit, the 8042 status, a PCI configuration read through
  CF8/CFC, the MPC105's own registers);
- the bridge's LE mode itself: `rtl/machine/IBMRS6K7248_machine.sv` "the bridge's byte-lane swap"
  (`le_bus` = PICR1 bit 5, `x_addr`, `x_be`, `x_wdata`), and the header comment's open question
  "To be checked against the MPC105 manual"; port 92 is only stored (machine.sv's address map);
- the CPU's LE mode (`docs/cpu_patches/0001-DSPPC604-little-endian-mode.patch`; `docs/plan.md`
  "Little-endian mode (separate track)", including the alignment-exception gaps it lists).

## Suggested approach

1. **Disassemble the loop.** Find where the firmware put the 0xE7C00-byte image and how ARC
   maps 0x80xxxxxx (BATs/page table), so the 13 PCs can be read from the diskette image. ARC's
   code after the switch is little-endian: each instruction word is byte-reversed in the image.
   `capstone` (Python, installed on Windows) disassembles PowerPC in both endians.
2. **Run it on the bench** if the loop's target isn't obvious: `sim/` `machine_tb` takes
   `--floppy FILE`, `--io-range`, `--save/--restore`, `--keys FIFO`, `--frame`
   (`docs/handoff_floppy_hardware.md` has a full command line). Boot to the hand-off, snapshot,
   then trace what the loop reads. One simulation at a time on the machine.
3. **Widen the board's stream** if needed (`IBMRS6K7248.sv`, "THE DEBUG UART"): the external
   interrupt and decrementer vectors, CF8/CFC, the PIT/RTC/8259 ports, and the PICR1 LE bit.
   `IBMRS6K7248_lite.qsf` builds without the PCnet, audio card and FM chip in ~19 min
   (restore `IBMRS6K7248.qpf` with `git checkout` afterwards: Quartus makes lite the default).
4. Check each fix in `sim/` first, then on .92, then that AIX and the firmware (big-endian)
   still boot.

## Board procedure

- Stage: `scp` the .rbf to `/media/fat/_Unstable/IBMRS6K7248.rbf`; load with F12, Right
  (System page), Enter on Core, Enter on IBMRS6K7248 (`scratch/work/kv92.sh key ...`,
  `screenshot --full <abs path>`).
- Debug stream: UART mode None; `scratch/work/com1rec92.sh SECS 115200` records
  `/tmp/c1boot.raw` on .92; `python sim/tools/fdboard.py <raw>` decodes the floppy/DMA tokens
  and passes the rest through (`.pppppppp` alive marks, `P<from>-<vec>` exceptions, `K=` port 92,
  `W880=` port 80, `NN@pc` progress codes).
- Boot from floppy once: F5 at the POST icons (the default boot list; not yet tried on the core), or the SMS boot order.
