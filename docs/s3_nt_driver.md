# What NT 4's S3 driver asks of the Vision864 (2026-10-29)

How NT 4.0 PPC's S3 display driver (s3.dll) and miniport (s3.sys) use the chip,
and how that compares with the model (IBMRS6K7248_s3, _s3ge, _s3video). It
comes from disassembling both files (the CD's cabinets, unpacked) and from the
board's register log (the IBMRS6K7248_DEBUG logger, set to video register
writes, port and MMIO). Before this pass the model was fixed one failure at a
time; this is the whole list, so what is left can be done up front.

## How the driver reaches the chip

| path | what goes through it | model |
|---|---|---|
| I/O ports 3C0-3DF, 4AE8 (s3.sys) | the mode set: CR00-CR18, CR31=8D/8C, CR3A=15, CR50=00, CR51, CR58, CR59/5A=000A, CR5C, CR5D/5E, CR60-62, CR67, CR6D, SR, GR, the SDAC (CR55, 3C6-3C9) | already handled |
| six I/O writes to BEE8 | the scissors, before MMIO is turned on | already handled |
| **MMIO, CR53 bit 4**: A8000 + (port - 8000) | **every engine register** (82E8-BEE8): halfword `sthx` for CUR_X/Y, DESTX/Y, ERR_TERM, MAJ_AXIS, CMD, the mixes, MULTIFUNC; **32-bit `stwx`** for FRGD, BKGD, WRT_MASK, RD_MASK, COLOR_CMP; GP_STAT reads | **added 2026-10-29** (there was no MMIO before: the commands went into VRAM as pixels) |
| **MMIO A0000-A7FFF** (PIX_TRANS) | image and glyph data: **32-bit `stw`** with a 16-bit-bus command (53B1, 53B3), then a halfword `sth` for an odd tail | **split 2026-10-29**: a 32-bit write on a 16-bit bus is two transfers, lanes 0-1 first (before the fix the engine kept only the first half and waited forever) |
| **a 64 KB linear window at A0000**: CR58=50, CR59/5A=000A, the bank in **CR6A** | GDI's own drawing into the frame buffer (DIB engine), and the cursor's image (bank 1F, offset FC00: CR4C/4D=07FF); s3.dll switches to it with CR53=00, CR40=08, CR58=50, CR6A=bank, and back with CR58=40, CR40=01, CR53=10 | **banked 2026-10-29** (before that, every bank landed in the first 64 KB) |
| VGA window A0000 (GR6), CR31 bits 0 and 3 | the banked old-style window | banked too (CR31 bit 0, enhanced mapping by bit 3) |
| 3D4/3D5 from s3.dll | the hardware cursor: CR45 on, CR46/47 X, CR48/49 Y, CR4E/4F offsets, CR4A/4B colour stacks (written four times each) | handled |
| 3C8/3C9 from s3.dll | the palette | handled |

The mode for GUI setup: 640 x 480, 8 bits a pixel, 1024 bytes a line
(CR13=80, CR50=00: the display and the engine agree). The engine draws into
the off-screen area to the right of x 640 (brush cache) and below row 480.

## The engine commands s3.dll issues

| CMD | meaning | model |
|---|---|---|
| 40B3 | rectangle fill, foreground mix | yes |
| 53B3 | rectangle, CPU data selects the mix (glyphs; PIX_CNTL A080), 16-bit bus, BYTSEQ | yes (data now split, above) |
| 53B1 | rectangle from CPU image data, 16-bit bus, BYTSEQ | yes (split) |
| xxxx \| 0200 / 0400 | the same with a 16 or 32-bit bus chosen at run time | yes |
| E0B1 | 8 x 8 pattern fill (MIN_AXIS 7) | yes |
| 2017 \| direction << 5 | Bresenham lines (ERR_TERM, DESTX/DESTY steps) | yes |
| BitBLTs (C0xx, computed) | screen to screen | yes |

PIX_CNTL values: A000 (the foreground mix), A080 (CPU data selects), A0C0
(display memory selects). Mixes BAE8 21/27/47/67/02 and B6E8 1/3/7. Not used:
short-stroke vectors (9EE8), the I/O-port PIX_TRANS (E2E8), polygon fills.

GP_STAT polls: bit 9 (busy) before each command; bits 0-7 and 15 (FIFO slots,
read as free); bit 10 (FIFO empty, set since 2026-10-28).

## What is left

- **The colour registers' 32-bit write.** s3.dll writes FRGD, BKGD, the masks
  and COLOR_CMP with one 32-bit store; the model takes the low halfword and
  toggles RSF. At 8 bits a pixel that is the whole colour. **At 16 and 32 bits
  a pixel** the high half (A6EA-A6EB) has to set the colour's upper half (the
  864's MMIO takes the doubleword at once); not done.
- **Planar VGA (vga.sys / VgaSave).** If NT falls back to its VGA driver
  (640 x 480 x 16, the safe mode), the window decode has write mode 0 only,
  no set/reset, rotation, bit mask or latches, and the scan-out has no planar
  4-bit mode. Not used while s3.sys loads.
- **Read-back of what the engine moved** (CUR_X/Y after a command) and
  READ_SEL: s3.dll does not read them.
- Nothing else in s3.dll's register or command set is missing from the model.
