# Bring-up log

## 2026-10-17: first run of the 7248 ROM on DSPPC604 (bench)

`sim/build/machine_tb --rom ../firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin --ram 8 --cycles 30000000`

The machine: `IBMRS6K7248_system` with the first-form machine (PReP map,
RAM, ROM at FFF00000 with the second socket empty, COM1, planar ID F5 at
port 0852; everything else a stub reading FF / FFFFFFFF).

What the ROM does on our CPU, in order (PCs are in the recovery block,
`firmware/disasm/v1.12_rom_fff00000_fff18000.annotated.s`):

1. Reset vector FFF00100 -> FFF04020: the CPU check (PVR), HID0, MSR =
   00001040, BATs and segment registers cleared. Runs as
   `firmware/disasm/reset_path.md` describes.
2. PCI configuration through CF8/CFC (mechanism 1, not the PReP direct
   window at 80800000): every read returns FFFFFFFF, no device found.
3. Fire Coral's internal registers through 1000/1004 (39 writes), the
   8237's extension registers 0410-0417, DMA 0008/000D/00D0/00D6/00DA,
   the 8254 (0043, 0041), system control 081C.
4. Progress codes start (8C1 = 8F then the code to 8C0; the same code to
   3BC; 0002xxxx byte-reversed to 0680): 04, 23, 24.
5. Memory sizing: AA5508AA and FFFFFFFF patterns at 8 MB steps
   (00800000, 01000000, ... 02800000), the MPC105's configuration
   registers read and written through CF8/CFC (A0 = memory bank enable),
   the SIMM presence ports 0880-0882 read. With no MPC105 model the
   registers read FFFFFFFF and it repeats its bank loop (progress 23 every
   ~65,000 instructions). Its fatal-memory path is the endless loop at
   FFF05734 (progress 22, the disk light at 0808 on).

Speed: 18-22 clocks an instruction here, the caches being off (HID0) and
every fetch going to the bench's memory (6 clocks plus the crossing).
The bench runs about 400,000 clocks a second.

### Next

- The MPC105 (bus 0 device 0, 1057:0001) behind CF8/CFC: its ID, PICR1/2,
  MCCR1-4, the memory start/end/extended and bank enable registers, with
  the banks mapping onto our RAM so the sizing finds what the OSD set; the
  SIMM presence ports 0880-0882 to match. References: MAME
  `src/devices/bus/lpci/mpc105.cpp`, the firmware's sizing code from
  FFF05400 (`firmware/disasm/`).
- Fire Coral (1014:000A, device 11) answering its ID and BAR, its
  internal registers stored.
- Then the 8259s, the 8254, the RTC/NVRAM (70/71, 74/75/76), the
  keyboard controller, the PC87312, as the firmware reaches them.

## 2026-10-17: the MPC105 (M1, first form)

The MPC105's configuration space (`IBMRS6K7248_mpc105.sv`), Fire Coral's
(`IBMRS6K7248_firecoral.sv`), CF8/CFC, the banks decoding RAM onto the
SDRAM, the floating memory bus, the SIMM presence detect (32 MB: one pair
of 16 MB SIMMs, `AA`).

`machine_tb --ram 32 --cycles 40000000`: memory sizing passes. The probe
writes AA5508AA at each 8 MB block and reads FFFFFFFF back from every
block but the first (no DRAM: the bus floats to the last value written),
reads the presence detect, places the 32 MB bank at 0, pattern-tests it
(progress 23 four times) and goes on: progress 08, then 09 (`audio_mute`:
ISA plug-and-play at 0279, the Sound Blaster's 022C), then a decrementer
delay (FFF050E4: the time base runs at 16.67 MHz, so a 0.4 s wait is
40 million clocks of the bench). Port 080C (equipment present) reads FF
(a stub); FFF04E84 tests its bit 1 and takes the branch at FFF04E8C (what
the bit means is still to be found).

The bench: 390,000 clocks a second, 140 MB; the build 14 minutes
(the CPU's logic lands in two 45-50 MB C++ files whatever the split).

`--cycles 300000000` (770 s): still in step 09 after 3 s of machine
time. Not a hang: `audio_mute` (FFF0D9A4) calls `init_4232`, which sends
the CS4232's Crystal key and configuration bytes to 0279 (`SendKey`,
`ConfigDevice`: every byte followed by a 1 ms delay; the delay routine
FFF05060 takes nanoseconds and the bus MHz from the planar table, so the
time base rate is right) and then reads the Sound Blaster DSP's write
status at 022C, retrying up to 199 times, twice, until it reads anything
but FF. A board always has the chip, so the firmware never expects it
missing; giving up would take ~16 s of machine time (~70 minutes of the
bench). Hence `IBMRS6K7248_cs4232.sv`: the DSP's status and reset
handshake and the WSS codec's registers, present and silent.

## 2026-10-17: the ISA core (M2, first form)

`main_control`'s order (the decompressed firmware, RAM 8398) sets what
comes next: CMOS (`yo_cmos`: an MC146818 at 70/71), `pci_reset_slots`,
`init_uart`, `init_interrupts` (8259s), `rtc_clock` and `init_rtc_int`
(the RTC's periodic interrupt: the first real use of ext_irq),
`i8042_init`, `debugger_init`, `manager_init`, the password EEPROM,
`monitor_serial_port`. Written: the 8259 pair with ELCR and the
interrupt acknowledge (`_pic`), the 8254 and port 61 (`_pit`), the
MC146818 and the 4 KB NVRAM (`_rtc`), the 8042 with a PS/2 keyboard and
mouse from hps_io (`_kbc`; set 2 to set 1 translation from QEMU's table),
port 92, the error status registers 0840-0844 reading 0.

## 2026-10-17: through the recovery block into the main block

With the CS4232 following its Crystal-key configuration (its Sound Blaster
appearing at 220 when activated and gone when deactivated, as `init_4232`
checks), `--ram 32`: progress 09, 0A, 0B, 0C, 0D (`chk_image_CRC` of the
main block from ROM, uncached: about 100 million clocks), 0E-11, and at
clock 125.6 million the jump to the main block's reset vector, FFF10100.
The main block repeats the early set-up (progress 33, 04, 19, the memory
sizing, 23) and then tests the RAM from a copy of its code at RAM 200,
caches still off: 22 clocks an instruction, about two hours of the bench
for 32 MB on the -O1 binary. Stopped there; the next run with `--ram 8`,
`--lat 1` and the -O2 binary.

## 2026-10-17: little-endian mode

`DSPPC604` with `LE_MODE = 1` (fetch addresses munged by XOR 4; data
addresses by XOR 7/6/4/0 by size; an alignment exception for an access
that cannot be munged) and the machine's byte-lane swap while the MPC105's
PICR1 bit 5 is set. `sim/tests` (`make`, then
`machine_tb --rom tests/le_test.rom --ram 8`):

- `le_test.rom`, caches: instruction only. Big-endian set-up (a RAM bank,
  patterns), the switch into little-endian mode (PICR1 and MSR[LE] by rfi,
  from a cache-resident block run twice: once the bridge swaps, a
  big-endian fetch from the bus is scrambled, so the switch must not fetch
  from the bus, as on the real board), little-endian code fetched from ROM
  doing byte/halfword/word loads, stores, lwbrx, a call and return, an FP
  doubleword (lfd/stfd), and a misaligned lwz taking the alignment
  exception through a little-endian vector (ILE set by mtmsr: rfi does not
  restore it) with DAR the unmunged 00001001; the switch back; the
  big-endian checks: **LE PASS**, 13 checks.
- `le_test_dc.rom`: the same with the data cache on (and so data
  translation: in real mode the 604 caches every data access, CF8/CFC
  included; DBATs map RAM and ROM cacheable, 80000000 cache-inhibited):
  line fills and castouts through the swap. **LE PASS**.

The first runs found two test bugs, no CPU bug: the switch fetched from the
bus after setting PICR1 (and so ran scrambled code), and ILE set through
SRR1 (rfi ignores it). A waveform build (`make TRACE=1`, `--fst`,
`tools/fst2vcd`, `tools/vcdq.py`) showed the exception taken with MSR 1040.

MacPPC7300's real-604 golden vectors (`verilator/run.py`, run from a
scratch copy of MacPPC7300 `21ba191` with this core's `rtl/DSPPC604`,
`LE_MODE = 0`): 11,444 integer and 25,598 FP vectors, all pass.

MacPPC7300's pipeline suite (`run_core.py`, with dingusppc `3f070249`
fetched for its lockstep reference), same scratch copy, `LE_MODE = 0`:
**RESULT: PASS** (every directed test; 1,071,506 random instructions in
lockstep). Both logs: `docs/cpu_patches/0001-verification-*.txt`. The
resume prompt for MacPPC7300: `../MacPPC7300_MiSTer/RESUME_le_mode.md`.

## 2026-10-17: main_control, and the serial console

`machine_tb --ram 8 --lat 1` on the -O2 binary (LE_MODE = 1, the CPU in
big-endian mode throughout: this is also the big-endian regression of the
LE change): the recovery block (CRC passed), the main block at clock
103.7 million, its 8 MB RAM test, progress 1A-1D (the loader copied to
RAM 0, caches and MMU, the LZW decompression of the firmware into RAM),
1E, 1F, and **`main_control` (RAM 8398) at clock 520 million** (81.4
million instructions). M1's goal.

Then `main_control`'s checkpoints, mapped to its calls (its code at
8398-8E10):

| code | step | |
|---|---|---|
| 20 | `yo_cmos` | the MC146818's CMOS |
| 30 | `setup_early_malloc` | |
| 3A (7B) | `init_uart` | |
| 40 | `init_interrupts` | the 8259s |
| 50 | `rtc_clock`, `init_rtc_int` | the RTC's periodic interrupt |
| 60 | `i8042_init` | self test 55; AE then a 500 ms wait for a byte no 8042 sends; keyboard reset FA AA |
| 70, 71 | `debugger_init` | |
| 80, 82 | `manager_init` | |
| 90, 91 | `f_init`, `password_init` | the RAM disk's file system |
| A0-AC, DE | `monitor_serial_port`, the console | 4690/4691 (an unknown device, stubbed) |
| B0, C0, D0... | `out32`s, `cursor_size`, `spawn`: the console, the GUI, the boot | |

During A0-AC **the firmware writes its ASCII terminal console to COM1**:
VT100 sequences (reverse video, cursor positioning) and "Command..." a
character at a time. At the firmware's 9600 baud a character costs the
bench 100,000 clocks, so the bench now runs its serial ports at the
clock / 16 (`UART_FAST`, the bench only); `--com1 FILE` keeps the bytes and
`tools/vt.py FILE` draws the terminal's screen.

## 2026-10-17: snapshots; the console drivers; the floppy

The bench now saves the machine at `main_control` (`--save`, 520 million
clocks) and starts from there (`--restore`): checked, the restored run
retires the same progress codes at the same instruction counts.

After A0-AC, the start-up script (`autoexec.6md`, built into the RAM
disk) loads the console drivers in turn: `as` (the serial terminal),
`s3`, `p9`, `bbl`, `ruby`, `mint` ("Command mint not found.": not a
command in this build). On the serial console the firmware writes a
character, then a new line and the cursor home, as if the terminal were
one column wide (its geometry is probably the NVRAM's, blank here).

Progress B1 is `diskette_init` (RAM 14FB8): DMA reset, the FDC's TDR
(3F3), IRQ 6 registered, then the drive with timeouts. With nothing at
3F0-3F7 it waited out every timeout (still in B1 after 300 million
clocks). Hence `IBMRS6K7248_fdc.sv`: an 82077AA's command and result
phases as QEMU's fdc.c, the drive present and empty.

M4 phases 1a (`IBMRS6K7248_s3.sv`: the registers, the frame buffer to a
VRAM port, the vertical interrupt) and 1b (`IBMRS6K7248_s3ge.sv`: the
engine) are written, from `docs/s3_design.md`; the bench answers the VRAM
port from a 2 MB array (`--vram FILE`, `tools/vram.py`). Not yet seen
running: the S3 driver loads after B1.

## 2026-10-17: the first picture; POST to the end of its icons

With the S3 (phases 1a-1c: registers, engine, scan-out with VRAM in DDR3)
and the floppy controller, the firmware runs from reset to its idle state
on the bench (`run_s3c`, 8 MB, from reset):

| clock | instructions | progress | the screen |
|---|---|---|---|
| 520 M | 81.4 M | `main_control` | (snapshot `snap_mc2.bin`) |
| ~560 M | 96 M | A0-AC, DE | the S3 driver sets 640x480x8, clears to white, a text cursor |
| ~700 M | 128-137 M | 4C-4E, 61 | the PowerPC logo (`oem.bmp`), the keyboard and memory icons; the memory test (`test_next_meg`, `rwc_pattern`) |
| ~790 M | 174-176 M | **B1, B2, B3** | `diskette_init` now passes in 1.3 M instructions (the FDC, drive empty) |
| ~800 M | 181 M | 94, 9F, 4C-4E | the network and drives icons |
| ~850 M | 189 M | A4, B0 | |
| ~900 M | 223 M | 91, 71, 72, C0, 26 | |
| ~945 M | 242-247 M | 27, D0, F0, F6, CD, **7B** | the speaker icon; the error triangle with **00017006**; then idle (7B) |

![the start-up screen](images/first_screen_powerpc_logo.png)

The order is the `autoexec.6md` sequence of `hardware_inventory.md` 4.1.
COM1 stays silent in this run: with the S3 found, the console is the
screen.

**00017006** comes from `check_tamper_or_init_path` (RAM BDA4): it walks
the consoles (`console_query`) for the one named in the configuration
(NVRAM, blank here) and, finding none, reports 00017006 through
`text_errormsg_tr` (the triangle, the code, then on to the boot). Expected
with a blank NVRAM; to check against a configured one.

The error code's box is drawn by `put_erroricon` (RAM 38964):
`rect_fill(x, y, x + 14 * strlen, y + 15, 255)` then `put_text(code, x, y,
1, 0, 0)`. It shows black with the digits dark blue (0,0,85): to check
whether VRAM holds 255 there (the palette) or the fill went wrong.

Two bench faults on the way: the frame capture (`--frame`) ran past its
buffer when no vertical sync came (1.8 M lines, the CRTC still at its
reset values: the bench crashed in `fwrite`), now clipped; and the
CRTC's sync widths now count a zero difference as a whole count (CR11 -
CR10 = 0 is 16 lines, CR05 - CR04 = 0 is 32 characters), as a VGA's do.
The bench now also ends cleanly on SIGINT/SIGTERM (the VRAM dump, the
stub list).

## 2026-10-17: the 53C810's first run; the SCSI scan

Run from `snap_mc3.bin` (the current build's `main_control` snapshot, clock
520 M) with `--cd` = the AIX 4.3.3.3 standalone diagnostics ISO at ID 3
(`scratch/work/run_scsi.txt`, picture `docs/images/scsi_scan_00017006.png`).

- The driver finds and opens the adapter. Seen with `--io-range
  A0000000:A00000FF` (`scratch/work/run_scsi_io.txt`, which died at clock
  1,050 M with the session): the reset (ISTAT 40/00), SCNTL0-3, SCID 0x47,
  DMODE/DIEN/SIEN, then the SCRIPTS self-test: DSP writes, DSTAT 84 (SIR),
  DSPS 0100DDDD and 0700DDDD (the script's own interrupt codes), then a
  selection: SIST1 04 (STO, the selection timeout) with DSPS B0F13F80. So
  the SCRIPTS engine, its interrupts and the timeout work.
- POST draws the drives icon; progress 94, 7B, then 96 (the scan, word
  0208xx96). The bus-reset recovery waits about 3 s of firmware time
  (clock 800 M to 1,050 M, ~25 min on the bench), then the scan steps
  through the IDs (~14,000 instructions each). One step gives progress
  98 (new: probably the CD at ID 3 answering INQUIRY), then 9F (the scan
  done; without the chip the firmware went 94 to 9F directly).
- After it: 4C/4D/4E, A4, B0, 91, 71, 72, C0, 26, 27, D0, F0, F6, CD, CD,
  **CB** (new), then 7B idle at clock ~1,250 M. The screen has all five
  icons (the speaker added) and the same error triangle, 00017006.
- **The image server read no blocks** from the CD: either the firmware does
  not try to boot it (the blank NVRAM's boot list; 00017006 is the console
  not found), or something after INQUIRY fails.

Next: rerun from `snap_mc3.bin` with `--io-range A0000000:A00000FF` to
clock ~1,300 M (~75 min) and read the CDBs sent to ID 3 (the DSA tables in
RAM, `--watch` on 9C27C ncr_execute); find what 98 and CB mean
(`docs/firmware_analysis.md`); then try the boot with a boot list in
NVRAM or from the firmware's menus (`docs/scsi_design.md` 1.5-1.10).

## 2026-10-17: a second machine; what 98 and CB are

The work moved to a Windows 11 machine (32 GB, 20 cores): the bench builds
in WSL Ubuntu-24.04 (oss-cad-suite's Verilator 5.049: the distro's 5.020
rejects `cr[i] <= 0` in a loop; the 5.04x lints PROCASSINIT and MULTIDRIVEN
are off in the Makefile), Quartus 17.0 Lite runs natively. A MiSTer is on the
network (192.168.99.143). The first Quartus synthesis found what the bench
let through: `for (genvar ...)` needs `genvar c;` + `generate` in Quartus
17, a concatenation cannot be sliced (`{...}[11:0]`), and `regs[6'(34 + n/4)]`
is read as index -30 (the cast taken as signed): all three fixed.

The scan's two new codes, from the disassembly:

- **98** (`0x0208_xx98`, `scsi_init` 0x98038): issued when a step's result
  (r29) is 0, i.e. **a device answered INQUIRY**; then its peripheral type
  is checked and `get_fru_id` called. So the CD at ID 3 was found.
- **CB** (`0x0209_xxCB`, `build_boot_table` 0x1DFC8): for each device type
  in a table, `get_occurance_count` (which asks `dasd_devio` about every
  DASD device) is non-zero: **the type is added to the boot table**, xx the
  entries so far. **CD** (`0x0006_xxCD`, 0x1DD24) is the same table's entry
  for the diskette path (`dasd_devio` on the first device).

So the CD-ROM was found and entered in the boot table; what did not happen
is the boot itself: the firmware idles at 7B after 00017006. To find out
why, the next run watches `build_boot_table` (1DBB8), `get_boot_seq` (1FBD4),
`boot_cmd` (133A0), `ParallelBoot` (232EC) and `cold_boot_path` (BC58).

## 2026-10-17: the first fit; the first load on a MiSTer

The first Quartus 17.0 compile of the whole top (commit 2260e82, after the
syntax fixes above): 34,272 ALMs (82 %), 249 M10Ks (45 %), 45 DSPs, 16
minutes. At 100 MHz the CPU clock misses by 6.2 ns (every failing path in
the CPU: the writeback result into CR and the completion queue, the FPU's
result mux, the BTB's write), as MacPPC7300's does; its PLL already offers 70
MHz on counter 1, so the top now runs the CPU and the machine at 70 MHz
(`CPU_MHZ`), memory and video at 100. That fit: 33,655 ALMs (80 %), slack
-2.34 ns (MacPPC7300 runs on the board at 70 with -1.1; its CPU has since
had a dozen timing cuts this copy lacks: `docs/cpu_patches/` is the way to
bring them over).

| block | ALMs |
|---|---|
| CPU (FPU 3,884; caches 2,411; MMU 1,003) | 15,892 |
| the framework (scaler, OSD, audio, hps_io) | ~6,900 |
| 53C810 + targets | 3,075 |
| S3 (registers 1,602; engine 244; scan-out 440) | 2,286 |
| Fire Coral + MPC105 (their configuration spaces as flops) | 1,759 |
| 8042 (its queues as flops) | 772 |
| the rest | ~1,600 |

Loaded on the MiSTer at 192.168.99.143 (`/media/fat/_Computer/IBMRS6K7248.rbf`,
`games/IBMRS6K7248/boot.rom` = the v1.12 512 KB image, the diagnostics ISO
beside it; the screen captured through the MiSTerKVMS capture server's
preview, `scratch/work/grab.py`; keys through mrext at port 8182). The OSD
comes up with the core's menu. The picture is a white band (DE active) on
black, 540 of 1,920 columns, full height, from the first second after the
load and unchanged after minutes: `docs/images/board_first_load.jpg`.
Nothing on the UART (ttyS1 on the board) at 9600: but the bench's COM1 is
also empty throughout (the S3 found, the console is the screen), so COM1
says nothing either way. So no sign yet whether the CPU runs on the board.
Hence the POST-code sender in the top (commit c261917): the port 680 codes
on the MiSTer UART at 115200 (the OSD's "UART" option, default), "R" at the
end of reset, "." every 2^24 instructions.

## 2026-10-17: the board speaks: POST codes on the UART

The user's board for this core is now the MiSTer at 192.168.99.92 (capture
stream `MiSTer-SS1`; the .143 one belongs to the PPC_Mac sessions). With the
POST-code build loaded there and `/dev/ttyS1` read at 115200 on the board
(`scratch/work/post1.raw`), the CPU runs:

```
R 04 04 08 23 23 09 0A 0B 0C 0D . 0E 0F 10 11 33 04 19 23 23 24 23 24 23 24 23 24 23 22 22 22 22 ...
```

(the bench from reset with 8 MB: `04 04 08 23 23 23 23 09 0A 0B 0C 0D 0D 0D
0E 0F 10 11 33 04 19 23 x10 1A 1B 1C 1D 1D 1D 1E 1F 20 30 3A 7B 40 50 60`).
So the recovery block runs to its end (the main block's CRC over the whole
ROM in SDRAM: the SDRAM reads right), the main block starts (33 04 19), and
its memory sizing ends in the firmware's halt loop at FFF15AD0, which
writes 22 to port 680 forever (hence the flood, which also overruns the
sender's 64-byte queue: the lone "2"s). The loop is entered from FFF159C4
(no SIMM pair recognised: the presence-detect bytes at 880-882 looked up in
the table at FFF15F40, whose keys are 88/8C/C8/CC, BB/BF/FB/FF, AA/AE/EA/EE,
99/9D/D9/DD) or from FFF15A48 (the MPC105's register A0 read back through
CF8/CFC without its high bits). The OSD's RAM at 16 MB instead of Most
(112 MB on this 128 MB board: `/dev/mem` 1FFFFF00 holds 12 57 00 03) halts
the same way. The bench had only ever run with 8 MB: runs with 16 and 112
from reset are the check (below).

The screen on this board is a 4:3 area of coloured stripes from the first
second: the S3's scan-out at its reset state showing what the DDR3 held;
on the .143 board it was a white band. Neither changes, as the firmware
never reaches the S3 driver.

## 2026-10-17 evening: the CD answers; the "idle" is a 3 s sleep; the CPU is MacPPC7300's

- **The CD is found.** A restored run had lost its images (the snapshot's
  inputs came back over this run's: fixed in `tb_main.cpp`); with the CD
  present at ID 3, the scan's INQUIRY goes through selection, the SDTR
  negotiation (script steps 07, 08, 09, 11, 12), command, data in (INTFLY,
  step 04), status and message to a good status (DSPS 50): progress 98,
  then LUN 1. 53C810 and target are sound through the scan.
- **The idle at 7B is `sleep(3, 1)`.** `check_tamper_or_init_path` finds no
  console named in the (blank) configuration, reports 00017006 through
  `text_errormsg_tr`, which calls `put_erroricon` and then **sleeps 3
  seconds** (RAM 3409C), polling the CMOS clock (`get_CMOS_time`): the "no
  new PC" idle. Every run so far stopped inside it (118 M clocks after
  `cold_boot_path`; the sleep is 300 M). A run through it is in progress;
  the bench now has `RTC_FAST` (the RTC's seconds 64 x faster, on by
  default) so such waits cost 5 M clocks.
- A snapshot at `cold_boot_path` (`--save-pc BC58`) and `--pcs` with an
  absolute instruction count (it compares the run's total) give the call
  path in minutes: `scratch/work/pcs_path.py` maps a trace to the
  firmware's symbols.
- **The CPU is MacPPC7300's master as it stands** (f946a6b, 2026-10-16):
  ignoring line endings, only DSPPC604.sv differs, by the little-endian
  patch. So the -2.6 ns at 70 MHz is this core's fit (82 % full, the
  machine's paths), not an older CPU; MacPPC7300's own notes say its
  committed state runs at 70 (10 of 10) and not at 100 (0 of 5).
- **The SDRAM-in-the-loop bench** (`make machine_sd`: `sim/sdsys_top.sv`,
  the controller, MacPPC7300's chip model in `sim/sdram_chip.h`, the ROM
  through the upload port) runs the firmware from reset; the model's six
  "protocol errors" are the pins read as a command at clock 0 before init.
  To 130 M clocks with 16 and 112 MB the sizing goes as on the plain bench
  (no 24, no 22); the long run through the memory phase is in progress.

## 2026-10-17 night: not timing; the two clocks

- **The 16 MB SDRAM-in-the-loop run went through the whole memory phase**
  to `main_control` and the console drivers (1A-1F, 20, 30, 3A, 7B, ... A2):
  the controller, the crossing and the ROM path are clean with the chip
  model, one clock.
- **A 50 MHz build** (the PLL's counter 14 of the 700 MHz VCO; slack +3.6 ns)
  **halts on the board exactly as the 70 MHz one**: `19 23 23 24 23 24 23 24
  23 24 23 22 22 ...` (`/tmp/post50.raw` on the board). So the CPU's -2.6 ns
  at 70 is not the cause. The top is back at 70.
- What the bench had never done: run the CPU and memory clocks at their own
  rates (every run ticks `clk` and `clk_b` together). `--cpu-mhz 70
  --mem-mhz 100` now schedules the memory clock's edges between the CPU
  clock's (the SDRAM model on the memory clock's falling edges); the
  two-clock SDRAM-bench run of the sizing is the next check.
- The boot screen's wait (`rxchar`) polls COM1's LSR (3FD, 13,588 reads
  in 25 M clocks; nothing at 60/64): a byte on COM1 should answer it; a
  PS/2 key may too (through IRQ 1).

## 2026-10-17 late night: the main block's sizing read from its code

- **The queue fix worked** (the queue keeps its first 4 KB): the board's
  trace (`scratch/work/cfg2.raw`) now holds the main block's whole sizing.
- **The disassembly corrects what the codes were taken to mean**
  (`scratch/work/ppcdis.py ADDR ADDR`, capstone):
  - **23** (FFF15BF0, in FFF15B40) is "this SIMM slot's presence code looks
    up as empty" (the table at FFF15F40; the codes come from ports 880-882
    and an aliasing test at 8 MB steps, FFF1582C, into SPRG2).
  - **24** (FFF15A00) is "an error was seen: switch off the lowest enabled
    bank" (A0, the memory bank enable register, bit by bit from bit 24 of
    the CPU's word), and **22** is "no bank left": halt.
  - So `23 24 23 24 23 24 23 24 23 22` is one empty slot per pass and the
    banks switched off one at a time: A0 goes 37, 36, 34, 30, 20, then 00.
  - The trace's order of progress codes against configuration accesses
    is loose (the queue serves pending events by priority).
- **The main block's sizing is FFF15490, not FFF15E04** (that is the
  recovery block's). It probes only RAM 0-3FC (so no access to 7FC
  appears), clears the error flag (C0) and checks it: **C0 reads 0, the
  check passes**. Then it copies FFF1554C-FFF15828 to RAM 0 and runs it
  from there: a clear of C0 (seen), then FFF155E0's tests (walking ones at
  word 0; byte stores at 0-3 read back as a word; the five patterns over
  0x400-0x2FFFFC, 3 MB), then the C0 check, which **never comes**: one of
  the RAM tests fails, and the firmware returns to FFF1558C, calls the bank
  switch-off and loops (FFF1559C to FFF154A0).
- So the failure is a RAM test run from RAM, and the first one to reach
  past the data cache (0-3FC fits in it): the 3 MB fill and check means
  line write-backs and line fills through the SDRAM, which the shadow
  detector (single-word reads only) never saw.
- **In flight**: a build whose debug UART logs the RAM copy's entry (PC 0)
  and its failure exits (RAM 1E0 = FFF1572C, the walking-ones and byte
  tests; 22C = FFF15778, a pattern mismatch; 1E4 = FFF15730) with the PC
  retired before, `Ppppppppp-xxx` (commit "the debug UART logs the main
  block's RAM test", `scratch/work/quartus_pc.log`).
- The bench's boot-screen wait: over several RTC minutes (with `RTC_FAST`)
  the loop reads the RTC's seconds, status A and C about four times a
  second and rereads NVRAM bytes 0x0C4-0xBDB (index at 74/75, data at 76)
  each time; it is a timed loop, not a short timeout.

## 2026-10-17 late night: the sizing halt found and fixed (the byte masks)

- **The PC trace named the failing test**: `PFFF15548-000` (the RAM copy
  entered) then `P000000E4-1E0` on every pass: RAM E4 is FFF15630, the
  byte-store test (a zero word at 0, 0xFF stored to bytes 3 and 1, read
  back as a word, expected 00FF00FF). The walking ones before it pass.
- **The cause**: the MiSTer SDRAM boards wire the chip's DQMH and DQML to
  the address lines A12 and A11 (Sorgelig's sdram.sv drives them so:
  `assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11]`). This controller
  (MacPPC7300's) drives the separate DQM pins and put zeros on A12-A11 in
  its WRITE commands, so on the board **every single-word write stored all
  four bytes**. The bench's chip model read the DQM pins, so it never saw it.
- **The fix** (`IBMRS6K7248_sdram.sv`): a WRITE carries its byte masks on
  A12-A11 too (a column command does not use them). The SDRAM bench now
  takes DQM from A12-A11 like the board, and **reproduces the halt with the
  old controller** (`19 23 ... 24 23 23 23 22 22 ...`, halted at FFF15AE8)
  and passes it with the new one.
- **On the board** the fixed build goes through the memory phase, the
  console drivers and `main_control` to the boot screen (the drive icon and
  the System Management Services diskette), as the bench does: `19 23 23
  1A 1B ... 20 30 3A 7B 40 50 60 71 70 80 82 ... 90 91 A0 A1 (DE A2 A3)...
  B0 91 91 71 72 C0 26 27 D0 F0 F6 DE CD` in 60 s.
- **MacPPC7300 has the same controller and the same omission**
  (`rtl/machine/MacPPC7300_sdram.sv`, the WRITE's `SDRAM_A <= {2'b00, ...}`):
  `docs/cpu_patches/sdram_dqm_on_a12_a11.patch` applies to it cleanly (checked,
  not applied: that repository is the PPC_Mac sessions').
