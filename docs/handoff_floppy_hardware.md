# Handoff: try the floppy controller fixes on the MiSTer (.92)

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

  Every READ DATA (C6) ends with ST0 00 or 04. The SMS diskette animation shows, and SETDIAG.PPC
  runs from RAM. The bench was stopped there (at ~550,000 clocks a second it is too slow to wait
  for the SMS menu).
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
   Expect the diskette animation and then the System Management Services menu. Note how long it
   takes, and whether it hangs on the animation (the bench got as far as SETDIAG.PPC running).
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
