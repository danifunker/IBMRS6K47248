# Handoff: try the floppy controller fixes on the MiSTer (.92)

## Result on the board (2026-10-25, Windows session)

Done. The floppy works on .92: F4 loads the text SMS from `sms128.img` with its full menu,
and a plain boot with the diskette in boots the graphical SMS from it. What was left after the
three controller fixes below was not the controller:

- **The ISA DMA wrapped at 64 KB.** The firmware DMAs each cylinder (36 sectors, 18 KB) straight
  into the file it loads, and some of those transfers cross a 64 KB boundary (ENGLISH.6XE's
  cylinder 7: 3AEAF0-3B32EF). `IBMRS6K7248_dma` stepped only the 16-bit address, as a PC's 8237
  does, so the rest went to the page's start: a hole at the transfer's end, ST0 normal, and an
  empty menu or a jump into zeros depending on where the buffers fell. The address now carries
  into the page (the 82378's, as QEMU's PReP DMA). `sim/floppy` test 12 failed on the old DMA
  and passes now; on the board the memory around 3B0000 matches the image byte for byte.
- **The track cache** (`rtl/IBMRS6K7248_fdimg.sv`): one hps_io request a track rather than a
  sector. Not the fix (ao486 asks a sector at a time and works), but kept: two Main round trips
  a cylinder instead of 36.
- **"Manage Configuration" still ends in ABEND 0001000A** (an instruction access at 80808080).
  That is the diskette, not the core: ENGLISH.6XE's `GetPCIInfo` calls entry 11 of the ROM's
  service table (pointer at 0xF89B4), and the 7248's v1.12 ROM has 7 entries. `sms128.img` is
  the 7020-40P's SMS 1.28; a 7248 needs its own SMS diskette.
- The resident monitor's `dir a:` lists the diskette: 32 files, every size as in the FAT,
  983762 bytes used, 465408 free. (With a readable diskette in, F4 loads SMS and `eatabug`
  never reaches the monitor: enter it with no diskette, then mount the image from the OSD.)
- The debug build's stream now logs the floppy (FIFO bytes, the DMA registers, each request to
  the Main); `sim/tools/fdboard.py` decodes it.

The original plan follows.

You are continuing work on the IBM RS/6000 43P 7248 MiSTer core
(https://github.com/danifunker/IBMRS6K47248). Build branch `floppy-fix` in Quartus, load it on the
MiSTer at 192.168.99.92, and check that the firmware reads a 1.44 MB FAT diskette.

## Background

On the board, `dir a:` in the firmware's resident monitor said "File system not a FAT type" for a
good 1.44 MB diskette. Three controller changes are on `floppy-fix`, all in
`rtl/machine/IBMRS6K7248_fdc.sv`:

1. **The data rate** (27e4e71). A CCR/DSR rate that doesn't match the medium now fails READ ID and
   the data commands (ST0 40, ST1 01, as QEMU does). The firmware probes at 1 Mbps first and took the
   1.44 MB disk for a 2.88 MB one.
2. **The interrupt** (27e4e71). Reading the first result byte now clears it, as on the 82077. READ ID's
   interrupt, left set, gave the next command (VERIFY) no edge, and the firmware gave up.
3. **H after a multi-track wrap** (1eea253). Past head 1's last sector with MT, the result's H is 0
   (C+1, R 1), as on the 82077 and in QEMU. VERIFY now answers `04 00 00 01 00 01 02`. This is cosmetic
   for the firmware, which only checks ST0.

## What the Verilator bench showed (macOS, firmware v1.12, `sms128.img` in drive A:)

- **The boot probe (`detmedia`):**
  - READ ID at 1 Mbps fails (`40 01 ...`); at 500 kbps it passes.
  - VERIFY `D6 00 00 00 12 02 12 1B FF` completes at once.
  - The drive stays type 2 (1.44 MB), then drive B is probed.
- **The pause after each command is normal.** The firmware polls status ~19,800 times (a 50 ms
  timeout) after each command's results, waiting for an 8th result byte that never comes.
- **F1 at the POST icons loads SMS from the diskette.** The firmware reads:
  - the boot record (sector 0), the FAT (1-9) and the root directory (19-32);
  - all of DIAGS.6XE (33-214) and SETDIAG.PPC (557-946), each exactly its cluster chain.

  Every READ DATA (C6) ends with ST0 00 or 04. These reads are the new evidence. The screen
  itself (the "insert a diskette" animation) is the same one the board always showed, so it
  proves nothing.
- **After SETDIAG.PPC is read**, the firmware stops the motor (clock 1.41G) and runs code at
  0x2xxxxx and in the firmware (progress FE) for 800M more clocks (~8 s at 100 MHz). It doesn't
  touch the floppy again or change the screen in that time, and ENGLISH.6XE is never read. Whether
  that is SMS starting slowly or a hang is unknown; the bench was stopped there.
- The controller's own bench `sim/floppy/run.sh` passes all 10 tests.

Not yet seen anywhere: the SMS menu itself, and the resident monitor's `dir a:`. Both need the
board.

## Steps on the Windows machine

1. Pull the branch: `git fetch && git checkout floppy-fix && git pull` (it should be at 1eea253 or later).
2. Build the core in Quartus as usual and check that timing is no worse than before. The fdc change
   is one extra assignment, but the floppy decode was already at -1.98 ns.
3. Copy the .rbf to .92 and load it. In the OSD, set Floppy image to
   `/media/fat/games/IBMRS6K7248/sms128.img` (MD5 `5e54d140277be6afaf1261d137fe8c42`).

## Tests on the board, in order

1. **SMS from diskette.** Reset, press F1 while the POST icons are drawn (keyboard … speaker).
   The diskette animation shows first, as it always has. The question is what comes after it:
   the System Management Services menu, an error code, or the animation forever. On the bench the
   firmware read DIAGS.6XE and SETDIAG.PPC and then went quiet. If the board stays on the
   animation, wait at least a minute, and note whether the floppy activity stops.
2. **The resident monitor.** Reset, press F4 at the icons, and type `eatabug` as soon as the
   diskette animation shows (it times out after ~20 s). Then:
   - `dir a:`: expect a listing including DIAGS.6XE (92968), ENGLISH.6XE (133312), FLASH.6XE
     (16900), SETDIAG.PPC (199454), SMSINST.BAT (2049), and about 30 entries in all; not
     "File system not a FAT type".
   - `read` from the floppy (drive 0): it failed earlier with error 0xA. Try it again.
3. **Regression.** Boot AIX from disk as before (CDE login, keyboard and mouse) to confirm that
   nothing else moved.

## If something fails

Run the bench on the Mac (Verilator 5.052 works there): `cd sim && make machine_tb VERILATOR=verilator BUILD=build GCC_MEM= JOBS=8`, then

```
./build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8 --lat 1 \
  --cycles 2400000000 --stall 0 --beat 50000000 --save snap.bin --floppy ../sms128.img \
  --io-range 800003F0:800003F7 --frame f.ppm --keys keys.fifo
```

Create the pipe first with `mkfifo keys.fifo`. Type into the run with `echo F1 > keys.fifo`, or with
a line of text, which is typed followed by Enter. `--frame` rewrites the screen as a PPM each frame.
Decode the floppy accesses with `python3 tools/fdtrace.py <log> 0 400`. From reset to the SMS load
takes about 40 minutes there.

## Report back

- whether SMS's menu comes up, and how long it takes;
- the `dir a:` output (a photo is fine);
- any monitor error codes;
- the Quartus timing summary (the CPU clock's worst slack).
