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
