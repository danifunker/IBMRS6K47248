# IBM RS/6000 7248 ("Carolina") boot firmware: analysis

Goal: learn which hardware the 7248-43P boot ROM touches, for a MiSTer FPGA core.

Everything below comes from static analysis of the images in `firmware/images/`:
* Disassembly listings and traces are in `firmware/disasm/`. The annotated reset path is `firmware/disasm/reset_path.md`.
* Tools are in `firmware/tools/`. All are Python 3 and run with `python3 -I`; they also use `powerpc-linux-gnu-objdump`.

Addresses are CPU physical addresses. "Port 0xNNN" means ISA I/O, which the CPU reaches at `0x80000000 + 0xNNN`.

---

## 0. Quick facts for the simulator / core

| item | value |
|---|---|
| Canonical ROM | `firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin`, 512 KiB, md5 `a064f6f3116026ddc0836050f16bb0f8` |
| Where it maps | **file offset 0 = 0xFFF00000**, through 0xFFF7FFFF. The reset vector 0xFFF00100 is file offset 0x100. |
| Upper half | 0xFFF80000-0xFFFFFFFF is the optional second 512 KiB flash socket (empty on stock boards). `7248_v1.12_P93H7075_fff00000_1m_ffpad.bin` is the same image padded with 0xFF to 1 MiB, covering the full 0xFFF00000-0xFFFFFFFF window. The firmware never needs the upper half: the code tests `(base+0x80000) & 0xFFF00000 == 0xFFF00000` to decide that it is running from ROM at 0xFFF00000. |
| Byte order | **big-endian**. MSR[LE] is never set; see section 2. |
| CPU | PowerPC 604 / 604e; a 601 path also exists. Speed comes from the planar ID: 0xF0/F4 = 120 MHz, 0xF1/F5 = 100 MHz, 0xF2/F3/F6/F7 = 133 MHz. Bus is 66 MHz (60 MHz for the 120 MHz part); PCI is half the bus clock. |
| Compression | **Yes.** The main block holds a 0x7C28-byte uncompressed loader followed by a Unix `compress` (LZW, 9..16 bit, block mode, no magic header) stream at ROM offsets 0x17C28..0x7A02E. It unpacks to **RAM 0x7C28..0x105EAC**; the firmware is linked to run at **RAM 0x00000000**, with TOC r2 = 0x105980 and C entry `main_control` at RAM 0x8398. A ready-made RAM image is `firmware/images/7248_v1.12_main_ram_image_at_00000000.bin`. |
| Host bridge | **Motorola MPC105 "Eagle"** (PCI 1057:0001, bus 0 dev 0), configured in PReP address map A. PCI config is reached only through **0x80000CF8/0x80000CFC** (type-1 style). |
| ISA bridge | **IBM "Fire Coral"** (PCI 1014:000A, dev 11). It contains the ISA bridge, 8237/8259/8254 functions and the IDE controller. Its BAR0 is set to I/O 0x1000, which gives an index/data pair at 0x1000/0x1004. |
| Checkpoint/POST output | Every boot step writes a code to **port 0x3BC** (parallel-port data latch) and does a 32-bit little-endian write `0x0001_00nn` or `0x0000_00nn` to **port 0x680**. The early assembly also writes 0x8F to **0x8C1** and the code to **0x8C0**. A simulator should log all three. |

---

## 1. Images inventory

Each archive was extracted into its own directory under `scratch/extracted/<archive>/`. Floppy images were read with `mtools` and the compressed `.trz` with `uncompress`. No DOS executables were run.

### 1.1 System ROM images (512 KiB flash images)

`P/N` is the IBM part number in the header. The block headers are the ASCII strings at offsets 0x0000 (recovery block) and 0x10000 (main block). The stamp is at offset +0x108 of each block.

| file (as extracted) | copy in `firmware/images/` | md5 | machine | version | build stamp (main block) |
|---|---|---|---|---|---|
| `scratch/7248-43p_Firmware_update.img` | `7248_v1.12_P93H7075_fff00000_512k.bin` | a064f6f3116026ddc0836050f16bb0f8 | **7248** (RS/6000 header) | **1.12** (version string `" 1.12test"` at RAM 0xF7F30) | 02/26/1997 14:27:11 |
| `ros104.exe` → `P40H4388.IMG` | `7248_v1.04_P40H4388_fff00000_512k.bin` | 3eab1a274b7cd8e005cdf9aee21c918c | 7248/OEM (README: "Carolina model 7248/OEM") | 1.04 | 06/08/1995 |
| `sms102.exe` → `P40H4139.IMG` | `7248_v1.02_P40H4139_fff00000_512k.bin` | e13a67649f76219bf2c393205dfac4b9 | 7248/OEM | 1.02 | 05/23/1995 |
| `ros104.exe` → `p40H4386.img` | `other/6050-6070_v1.04_P40H4386.bin` | dc96e8e279c519f25403b74f41056125 | Power Series 830/850 (6050/6070) | 1.04 | 06/08/1995 |
| `sms102.exe` → `p40H4137.img` | `other/6050-6070_v1.02_P40H4137.bin` | 1b29eb908e703826b3c9b6e127426348 | 6050/6070 | 1.02 | 05/23/1995 |
| `p8x0_106.trz` → `P40H5090.dd` (FAT floppy) → `P40H5090.IMG` | `other/6050-6070_v1.06_P40H5090.bin` | 48ed4db77dada4589705a65122959d08 | 6050/6070 | 1.06 | 08/18/1995 |
| `p8x0_107.exe` → `P40H5174.IMG` | `other/6050-6070_v1.07_P40H5174.bin` | 628fdad108854b2d00acd63f3c9b2bfb | 6050/6070 | 1.07 | 11/02/1995 |
| `p8x0_108.exe` → `P40H5218.IMG` | `other/6050-6070_v1.08_P40H5218.bin` | ad502dd3af2f222677c642dfbfb778e1 | 6050/6070 | 1.08 | 11/30/1995 |
| `p8x0_110.exe` → `P93H1904.IMG` | `other/6050-6070_v1.10_P93H1904.bin` | 4734b71f805ada57235e08d3bebf3310 | 6050/6070 | 1.10 | 08/12/1996 |
| `sms126.exe` → `P12H0354.IMG`; same bytes in `sms126.dd` | `other/sandalfoot_P12H0354.bin` | c85effc52351a4436c92bd56a1756994 | "Sandalfoot" family (6015 Power Series 440 / 7020-40P): different board | ? | 01/27/1995 |
| `sms127.exe` → `P52G0686.IMG` (header says 11H6483) | `other/sandalfoot_P52G0686.bin` | ea5b201fff53a7c2f60adf6391811633 | Sandalfoot/Sandalbow (README: "Sandalfoot DVT-8B") | ? | 06/14/1995 |

Images that are present but were not obtained:

* **`7248100.exe`** and **`7248100.bin`** are the official 7248 firmware 1.11 package (`43p-133/p93h4940.img`, `fw-111.dd`, `sms107.*`). Both archives are **ZipCrypto-encrypted**; the password came from IBM's web licence page, and no attempt was made to break it. The central directory records the CRC-32 of `p93h4940.img` as **0x7C987E45** (524288 bytes), so a copy from elsewhere can be verified.
* **`7249_6042_firmware.zip`** contains `think850.exe` (`p91g1671.img`, `precover.img`: ThinkPad 850, type 6042) and `think850.bin` (`aix/WPET22WW.DDBIN`). Both are **encrypted** too, so they could not be compared.
* The `ppc_arc_*bootloader.zip` archives hold ARC (Windows NT) firmware loaded **from disk or diskette**, version 2.10/2.11 ("Carolina", "IBM-6050/IBM-6070" strings). They are PReP boot images in a type-0x41 partition, not ROM images.
* `Pages/firmware/NTPROM.RAW` and `RISCOS.RAW` are MIPS Magnum/Jazz PROMs, unrelated to this machine.

The 1.12 main-block header reads "93x7075" (sic), which matches P93H7075. The web notes in `scratch/IBMPowerPC/Pages` list "Firmware 43P-7248 V1.12, 03/31/1997, P93H7075.IMG". Our image is built 02/26/1997 and carries the version string `" 1.12test"`, so it is **probably a late test build of 1.12** rather than the final 03/31 release. It is still the newest 7248 image available. Its recovery block reuses the part-number header "40H5218" of the 6050/6070 1.08 recovery block.

### 1.2 Diskette-side software (not needed for ROM bring-up)

`sms1xx.exe`, `sms1xx.dd`, `SMS10x.EXE` and `ENGLISH.6XE`/`DIAGS.6XE` contain the System Management Services and diagnostics: `*.6DG`, `*.6XE`, PowerPC XCOFF-like executables that the resident firmware loads from diskette.

The **7248 has no SMS menus in ROM**. Pressing F1 or F4 loads SMS from diskette. The ROM only contains the boot-sequence menu, the network (RIPL) setup and the resident monitor.

### 1.3 How the update files wrap the flash image

* **The `.IMG` file is the raw 512 KiB flash content**, with no extra wrapper. `FLASH.6XE` (run from SMS or the resident monitor: `flash -a`) writes it.
* The resident monitor can also "soft-load" a `.IMG`: it loads at RAM 0x400000 and jumps to 0x400100 (help text at RAM 0xF9D58). The ROM code is position independent, so it runs from RAM.
* Inside the image there are two **blocks**, each with this structure (parser: `firmware/tools/romimg.py`):

| block offset | content |
|---|---|
| +0x000 | ASCII header "`<PN> RS/6000 Microcode - Property of IBM ...`" (older images say "`PPS Firmware Licensed Materials ...`"), NUL-terminated |
| +0x0E8 | u32. In 1.12 it is 0x000A1D6F; in older images this offset still falls inside the header text. Not covered by the CRC. |
| +0x100 | `b entry` (reset vector), +0x104 `b entry+4` |
| +0x108 | build stamp "MMDDYYYY HHMMSS" |
| +0x200..+0x1700 | exception vectors |
| +0xFF0 | u32 offset of the **block descriptor** |
| descriptor | `{1, 0x3C, ptr, compressed?, next/len, 0x108, 0x117, 0x100 (entry), end_of_data, lzw_start(=stub size), ram_image_end, TOC, 0, 0xEC, 0x100, 0x10, planar IDs F0,F1,F2...}` |
| +end_of_data | **CRC-16, stored big-endian**. Algorithm: reflected CCITT (poly 0x8408), init 0xFFFF, no final XOR, computed over `block[0x100 : end_of_data]`. Implemented by `romcrc16` and checked by `chk_image_CRC`. Verified for both blocks of 1.12: 0xE5CE at 0x0F05C and 0x94E7 at 0x7A02E. |

* **Recovery block**: 0x00000-0x0FFFF, 64 KiB, uncompressed. data end 0xF05C, TOC 0xEFD0.
* **Main block**: 0x10000-0x7FFFF. In 1.12:
  * the stub runs to 0x17C28
  * the LZW data runs to 0x7A02E
  * the CRC is at 0x7A02E
  * 0x7A030-0x7FFFF is 0xFF
* The recovery block checks the main block's CRC at every reset. If the CRC is bad, it stays in **recovery mode**: it loads an image from the "Firmware Recovery Diskette" (`PRECOVER.IMG`) with its own floppy driver and reflashes.
* The flash is AMD-style, 512 KiB at 0xFFF00000: `write_autoselect`, `program_byte` and `erase_sectors` use command addresses 0xFFF05555/0xFFF02AAA, and `lock_flash` writes port 0x98 <- 1.

---

## 2. Load address and endianness

* The reset vector at file offset 0x100 is `48 00 3F 20`, which is `b +0x3F20` in big-endian encoding. Read little-endian, it is not a valid branch.
* Bulk opcode statistics (`firmware/tools/endian_score.py`) count words that are blr, mflr, mtlr, stwu r1, r1-relative load/store, b/bl, addi, ori, rlwinm or cmp:

| region | BE hits | LE hits | blr (BE / LE) |
|---|---|---|---|
| recovery block 0x4000-0xFFFF | 5137 | 1250 | 320 / 0 |
| main stub 0x14000-0x17C28 | 1903 | 307 | 103 / 0 |
| decompressed RAM image (1 MiB) | 63986 | 22257 | 2021 / 0 |

* Load address: 0xFFF00000, as established in section 0. The code is position independent: every function finds its base with `bl .+4 ; mflr` and adds offsets. The same blocks run from ROM at 0xFFF00000/0xFFF10000, from RAM 0 after copying, and from RAM 0x400000 when soft-loaded.
* The firmware is compiled C (IBM xlc, XCOFF traceback tables) plus hand-written assembly for the reset path. **The traceback tables still contain function names.** `firmware/tools/tbtab.py` recovers 189 names from the ROM blocks and 1334 from the RAM image; see `firmware/disasm/symbols_v1.12_*.txt`.
* Build-tree what-strings: `rom/i8042.c, esw_keyboard, carol100, car.mvt110`, `rom/net_mgr.c ...`. "carol100" is the Carolina tree.

---

## 3. Boot flow

Section 2-7 of `firmware/disasm/reset_path.md` has the details. In summary:

1. **0xFFF00100** branches to 0xFFF04020. The CPU check uses code replicated 8x per 32-byte cache line.
   * 601: segment registers SR0-15 = 0x87F0000n (T=1, BUID 0x7F, memory-forced identity mapping); MSR = 0x1070.
   * 603/604: HID0 = EMCP | (old NHR bit), caches off; MSR = 0x1040 (ME|IP); all IBAT/DBAT and SRs cleared.
2. **Fire Coral (PCI dev 11)** through CF8/CFC: Command = 7, BAR0 = I/O 0x1000. Then about 30 internal registers are written through index 0x1000 / data 0x1004, including a delay of about 45 ms (750,000 timebase ticks) between two writes of register 0x03.
3. **Legacy ISA setup**: DMA master clear and cascade, 82378-style DMA S/G registers 0x410-0x417 = 0x42, PIT counter 1 = 18 (refresh). Port 0x81C is cleared.
4. Step **8**: **MPC105 memory controller**: PCI command, PICR1, MCCR1-4 (MEMGO), bank sizing from a SIMM presence-detect table, bank start/end/enable registers. Then L2 detection and enable: ports 0x80C/0x80D/0x814/0x81C, PICR1/PICR2. **Planar ID** is read from port 0x852. The early stack is at RAM 0xBC0.
5. Steps **9-16**: `audio_mute` (CS4232), caches/MMU, **CRC check of the main block**.
6. If the CRC is good, step **17** jumps to the **main block reset vector 0xFFF10100**, which goes to 0xFFF14020. The main block repeats steps 1-4 (checkpoints 0x33, 0x04, 0x19...), then:
   * copies its stub to **RAM 0** and continues there (0x1A)
   * **LZW-decompresses** the payload to RAM 0x7C28 (0x1D)
   * sets r2 = 0x105980 and jumps to **`main_control` @ RAM 0x8398** (0x1F)
   * installs a DSI handler that loads **DBAT3** on demand for the faulting 256 MiB segment, so the C code reaches I/O and PCI through a single remapped BAT.
7. If the CRC is bad, the recovery block copies itself to RAM 0 and runs `recovery_control` (diskette reflash).
8. `main_control` (C) does the rest:
   * runs `AUTOEXEC.6MD` from an **internal RAM-disk ("DAKOTA VDSK")** compiled into the image. It holds drivers `KEYBD/MOUSE/ETHER/PCI_C970/TKRING/TRPCI/TCPIP/SCSI/BBL/RUBY.6XS`, `BOOT.6XE`, `SEL_IPBT.6XE`, `PW.PPC`, and bitmaps `*.PIC`/`*.BMP`.
   * shows the boot logo and icons (keyboard, memory, network, disk, audio)
   * tests memory
   * checks the power-on and privileged passwords (EEPROM at ports 0x78-0x7C)
   * builds **PReP residual data** (`build_residual`) and boots per the boot list. F1/F4 load SMS from diskette; the resident monitor password is `eatabug`.

---

## 4. I/O address map as used by the firmware

Sources:
* constant-address accesses in the assembly paths: `io_trace_recovery_block.txt`, `io_trace_main_stub.txt`
* constant-argument calls of `in8/out8/in16/out16(le)/in32/out32(le)` in the C code: `io_helper_calls_ram.txt`
* the residual-data builders (`build_*`, the packets the firmware reports to the OS)

The "n" column counts static sites: assembly direct accesses plus C helper calls with a constant port. Many more C accesses use computed ports.

### 4.1 Memory map (CPU physical)

| range | what | evidence |
|---|---|---|
| 0x00000000-... | DRAM. Firmware runs at 0; early stack at 0xBC0; later stack 0x17FFC0, SPRG1 0x1AFFF0, SDR1 0x180000; soft-load buffer 0x400000. | reset path |
| 0x80000000-0x8000FFFF | ISA/PCI I/O space (PReP map A) | everything below |
| 0x80000CF8 / 0x80000CFC | MPC105 CONFIG_ADDR / CONFIG_DATA (little-endian on the bus) | dozens of sites |
| 0xBFFFFFF0 | PCI interrupt-acknowledge (8259 vector read) | `ext_int_handler` in8(0xBFFFFFF0) |
| 0xC0000000-... | PCI memory: video framebuffers etc. P9100: 0xC1000000/0xC1800000 in `init_P9100_base`. | |
| 0xFFF00000-0xFFF7FFFF | 512 KiB boot flash (AMD 29F040-style command set at +0x5555/+0x2AAA) | `program_byte`, `reset_flash` |
| 0xFFF80000-0xFFFFFFFF | optional second flash socket | redbook: 1 MiB max, 512 KiB soldered |

### 4.2 PCI configuration accesses (bus 0)

| dev | ID | registers touched early | values (LE) |
|---|---|---|---|
| 0 | MPC105 1057:0001 | 0x04 | FFFF0006, later FFFF0106 |
|   | | 0xA8 PICR1 | 9F071208 → 9F071E08/09/0A, 9F011E08 |
|   | | 0xAC PICR2 | C29B438B |
|   | | 0xB0 | 00005B00 |
|   | | 0xC0/0xC4 error enable/detect | 0xC4 ← 0 |
|   | | 0xF0 MCCR1 | FFC30000 → FFCB0000 (MEMGO) |
|   | | 0xF4 MCCR2 | 00000FA2 |
|   | | 0xF8 MCCR3 | 0002B2DC / 0002B2DB |
|   | | 0xFC MCCR4 | 0 |
|   | | 0x80/0x84/0x90/0x94/0xA0 | bank start/end/enable (computed) |
|   | | 0xB8 | in `extended_memory` |
| 11 | Fire Coral 1014:000A | 0x00 (read) | |
|    | | 0x04 | 00000007 |
|    | | 0x10 BAR0 | 00001000 |
|    | | 0x50 (read) | |
| 16 (0x10) | NCR 53C810 1000:0001 (7248 only); `find_scsi_card` also accepts 53C825 1000:0003 | | path `/pci@80000000/pci1000,1@10` in Solaris notes |

Device numbering: `init_pci_stuff` maps "logical slot n" to `CF8 = 0x80000000 | ((n+10)<<11)`, so slot 1 is dev 11. For a Sandalfoot-type platform it uses the direct-mapped 0x80800000+(0x400<<n) mechanism instead. The device numbers of the on-board S3 and AMD Ethernet were not pinned down in this pass; they are next steps.

### 4.3 I/O ports (ISA side; CPU address = 0x80000000 + port)

| port(s) | n | owner | usage seen in firmware |
|---|---|---|---|
| 0x000-0x00F, 0x081-0x08F, 0x0C0-0x0DF | ~25 | 8237 DMA, inside Fire Coral | master clear (0x0D, 0xDA), command (0x08, 0xD0), mode 0xD6=0xC0, `dma_setup` (0x04, 0x05, 0x0A, 0x0B, 0x0C, 0x81, 0xD4), `QuiesceMisc` (0x08, 0x0F, 0xD0, 0xDE); residual: DMA at 0x00/0x80/0xC0 |
| 0x40A, 0x40B, 0x410-0x417, 0x481, 0x4D6 | 14 | 82378-compatible DMA extensions (Fire Coral) | 0x410-0x417 ← 0x42 at reset; 0x40B/0x411 in audio and DMA code; residual lists them |
| 0x020/0x021, 0x0A0/0x0A1 | ~20 | 8259 PIC pair | `init_8259s` ICW 0x11, vectors 0/8, cascade 4/2, ICW4 1; masks |
| 0x4D0/0x4D1 | 2 | ELCR edge/level | 0x4D0 ← 0x00, 0x4D1 ← 0xA0 (IRQ13 and IRQ15 level) |
| 0x040-0x043, 0x061 | 9 | 8254 PIT + port B / speaker | ctr1 refresh (0x43=0x74, 0x41=0x12,0x00); `beep` (0x43=0xB6, 0x42, 0x61) |
| 0x060/0x064 | 4 | 8042 keyboard/mouse controller | `i8042_*`, `read_8042_output_buffer`; residual IRQ1 (kbd), IRQ12 (mouse) |
| 0x070/0x071 | 20 | RTC/CMOS (MC146818-compatible), NMI mask in bit 7 of 0x70 | `CMOS_read/write_byte`, `get/set_NMI`; residual IRQ8 |
| **0x074/0x075/0x076** | 8 | **PReP NVRAM** (4 KiB NVSRAM): 0x74 = address low, 0x75 = address high, **0x76 = data** (Carolina uses 0x76, not 0x77) | `NVRAM_read/write_byte`; residual lists 0x74 and 0x76. (Sandalfoot uses 0x77.) |
| 0x078-0x07C | 20 | security/VPD **EEPROM** interface (serial EEPROM: passwords, VPD) | `EEPROM_*` (base and alternate ports) |
| 0x098 | 1 | flash write-lock | `lock_flash` out8(0x98,1) |
| 0x170-0x177/0x376, 0x1F0-0x1F7/0x3F6 | 6 | IDE (Fire Coral) | `ide_*`, `setup_coral_ide` (0x376/0x3F6 ← 0x0A); residual: two channels |
| 0x220, 0x240, 0x388, 0x200, 0x330, **0x534/0x535** | ~60 | **Crystal CS4232** audio: SB at 0x220/0x240, OPL3 0x388, joystick 0x200, MPU-401 0x330, **WSS codec index/data 0x534/0x535** | `audio_init_setup`, `audio_play`, `audio_mute`; residual IRQ5, DMA0/1 |
| 0x279 / 0xA79 | | ISA PnP address / write-data | residual (`build_isa`) |
| **0x398/0x399** | 10 | **National PC87312** Super I/O config index/data | `ReadPC87312Regs`/`WritePC87312Regs`/`PC87312Init` (0x398 ← 0x04 ...) |
| 0x3F0-0x3F7 | ~25 | floppy (PC87312) | `reset_fdc`, `specify`, `seek`, `dma_setup` ...; residual IRQ6 DMA2 |
| 0x3F8 / 0x2F8 | | COM1/COM2 16550 (PC87312) | `InitSerial`, `txchar`, `rxchar` (computed base); residual IRQ4/IRQ3. **The firmware console can be the async port** ("IBM Async console driver for VT100 compatible terminals", mode A). |
| **0x3BC** (0x3BD/0x3BE) | 26 | parallel port LPT (PC87312); **checkpoint output** | every boot step writes its code to 0x3BC; `CheckSerialPort`, `InitParallel`; 0x3FF ← 0x55 |
| **0x680** | 18 | **32-bit checkpoint register** (unidentified, probably a debug latch) | `checkpoint()` writes `out32le(0x680, code)`; the asm path writes `0x0001_00nn`/`0x0000_00nn` |
| 0x800 | | IBM system registers base (residual: ISA bridge) | |
| 0x808 | 11 | "op"/IDE control (residual `build_op`, chip id 0x8FF0) | early 0x808 ← 1; IDE routines toggle 0x808 = 0/1 around commands |
| **0x80C / 0x80D** | 14 | **equipment/L2 status** (L2 present/size, speed bits) | read in memory and L2 init, `build_l2`, `extended_memory`, `yo_eeprom` |
| 0x810, 0x812 | 2 | CMOS/NVRAM protect? | `yo_cmos` writes 0 |
| **0x814** | 5 | **L2 cache control** | early 0x814 ← 0xAA (test), reads |
| **0x81C** | 33 | **system/L2 control** (bit 7, bit 4 used for L2 invalidate; ECP DMA) | many in reset path; `ECPDMASetup` |
| 0x82A / 0x82B | 26 | power-management / LED control (HDD LED `toggle_hf_led`) | `main_control` 0x82A ← 0x10, 0x11, 0x13, 0x14, 0x1D, 0x1E; residual `build_pm` |
| 0x838, 0x83C | 4 | PM / interrupt control | `ext_int_handler` writes 0; `QuiesceMisc`; residual `build_pm` (0x838) |
| **0x852** | 1 | **planar ID** | 0xF0..0xF7, see 4.4 |
| 0x860, 0x862 | | power management | residual `build_pm` |
| 0x880 | | system register block | residual (`build_isa`) |
| 0x8A0 | 3 | security / tamper switch | `security`, `yo_eeprom` |
| **0x8C0 / 0x8C1** | 18 | early **checkpoint display**: 0x8C1 ← 0x8F, then 0x8C0 ← code. Probably the IBM PReP LED/operator-panel latch; the 7248 has no LED. | reset-path assembly only |
| **0x1000 / 0x1004** | 85 | **Fire Coral internal register index (16-bit, LE) / data (8-bit)**, via BAR0 | reset path; `coral_pci_config_read/write`; `setup_coral_ide` (index 0x25) |
| 0x4690 / 0x4691 | 7 | unknown | used by `monitor_serial_port` and `async_interrupt_handler` |

### 4.4 Planar ID (port 0x852) table (ROM 0xFFF04EE4)

| ID | CPU / bus / PCI MHz | flags | note |
|---|---|---|---|
| F0 | 120 / 60 / 30 | 5 | IDE planar (6050/6070) |
| F1 | 100 / 66 / 33 | 5 | IDE planar |
| F2 | 133 / 66 / 33 | 1 | IDE planar |
| F3 | 133 / 66 / 33 | 5 | IDE planar |
| F4 | 120 / 60 / 30 | 7 | **SCSI planar (7248)**, flag bit 1 set |
| F5 | 100 / 66 / 33 | 7 | **7248-100** |
| F6 | 133 / 66 / 33 | 3 | 7248-132 |
| F7 | 133 / 66 / 33 | 7 | 7248-132 |

Every entry also carries 0x01F00000 and a 0x1000 field. There are spare clock rows for 166/66 and 200/66 MHz (604e upgrades). On a 604e (PVR 9) the code also checks HID1 PLL bits. The string table has "IBM PPS Model 6050/6070 (E)" and "IBM PPS Model 7248 (E)", chosen at run time.

### 4.5 Interrupts and DMA as reported in residual data

From the `build_*` functions:

| device | IRQ | DMA | I/O |
|---|---|---|---|
| PIT | 0 | | 0x40, 0x61 |
| keyboard | 1 | | 0x60, 0x64 |
| cascade | 2 | | 0x20, 0xA0, 0x4D0 |
| COM | 4 / 3 | | |
| parallel | 7 or 5 | (ECP DMA) | |
| audio CS4232 | 5 | 0 / 1 | 0x534, 0x240/0x220, 0x388, 0x200, 0x330 |
| floppy | 6 | 2 | |
| RTC | 8 | | 0x70 |
| mouse | 12 | | |
| IDE | | DMA (mask 0x40/0x80) | 0x1F0/0x3F6, 0x170/0x376 |

PCI interrupts are steered to level-triggered IRQ 13/15 (ELCR 0x4D1 = 0xA0).

---

## 5. PCI vendor/device IDs referenced

These are constants built in code as `(device<<16)|vendor` (`firmware/tools/find_pci_ids.py`) plus driver strings:

| ID | device | where |
|---|---|---|
| 1057:0001 | Motorola MPC105 host bridge | `pci_reset_slots` (skips it) |
| 1014:000A | IBM Fire Coral ISA bridge/IDE | `pci_reset_slots`, early asm (dev 11) |
| 1000:0001 | NCR/Symbios 53C810 SCSI (on-board on 7248) | `find_scsi_card`, `allocate_buffers` |
| 1000:0003 | NCR 53C825 | `find_scsi_card` |
| 5333:88C0 | S3 Vision864 (on-board, "IBM Power Series S15 864") | `build_s3`, `s3_Found` |
| 5333:88B0, 5333:8880 (and device 0x8810 in `s3_Found`) | S3 928, S3 868/Trio-class ("S15 928/964 PCI Adapter") | `build_s3` |
| 100E:9100 | Weitek P9100 ("IBM Power Series H10 Graphics", RGB525 DAC) | `build_p9`, `weitek_init` |
| 1014:0013, 1014:0113 | IBM P9100-based card variants | `build_p9` |
| 1014:001B | IBM GXT150P ("Baby Blue") | `bblue_*` |
| 1014:0020 | IBM GXT1000P ("Ruby") | `build_ruby` |
| 1022:2000 | AMD PCnet Am79C970 (on-board Ethernet) | driver `PCI_C970.6XS` / `pci_79c970_*` (ID test not via constant) |
| (IBM PCI token ring) | | `TRPCI.6XS`, `find_pci_adapter` |

The ROM also has drivers for ISA Ethernet and token ring, a TCP/IP stack with BOOTP/TFTP, and "GXT250P/GXT255P".

PnP IDs used in residual data: IBM0005/0007/0008/000A/000B/000F/0010/0012/0013/0016/0017/001B/001C/001D, PNP0000/0100/0200/0303/0400/0401/0501/0600/0700/0909/090E/0A00/0A03/0B00/0F03/80CC/8327.

**Minimum device set the firmware expects:**
* MPC105
* Fire Coral (ISA + IDE + DMA/PIC/PIT)
* PC87312 Super I/O (FDC, 2x UART, LPT)
* 8042 keyboard controller
* MC146818-style RTC with NVRAM at 0x74-0x76
* the 0x78-0x7C EEPROM
* the IBM system registers 0x800-0x8FF
* CS4232 audio
* S3 864 VGA (console)
* AMD 79C970
* NCR 53C810 (7248)

A serial-console boot path exists (VT100 async console), which can avoid S3 emulation early on.

---

## 6. Strings of interest

The full lists are in `firmware/disasm/strings_v1.12_{rom,ram}.txt`.

* Version and banner:
  * " 1.12test"
  * "Power Personal System Firmware built on %c%c%c%c%c%c%c%c at %s%c%s%c%s"
  * "(C)Copyright IBM Corporation, 1994."
  * "IBM PPS Model 7248 (E)"
  * "IBM Manager Manager ROM V1.00"
* Boot menu (in ROM):
  * "Press F1 for System Management Programs"
  * "Boot Sequence Selection": 1. Display Current Settings, 2. Restore Default Settings, 3.-6. Configure 1st..4th Boot Device, 7. Boot Other Device
  * "Boot Device Selection": Diskette Drive / SCSI CDROM Cntlr / SCSI Disk Cntlr / Network Device
  * "11. Remote Initial Program Load Setup": IP parameters, adapter parameters, ping, in 6 languages
* Errors:
  * "System firmware corrupted. Press Enter to update the system firmware."
  * "Version Error": SMS level does not match the firmware level
  * "Insert the Systems Management Services diskette or CD-ROM"
  * "The 8042 controller failed an internal self-test"
  * "CMOS Error!!"
  * "EEPROM locked during cold boot!"
  * "Primary Access Switch jumper is not in WRITE ENABLE position"
  * "The NVRAM CRC is invalid"
  * "Memory error occurred.", "Memory Initialization in progress..."
  * "PANIC: All banks disable"
  * SCSI: "SCSI Bus terminator power not driven by the computer."
* Resident monitor (password `eatabug`): help, date, time, mode, font, fdisk, vdisk, dir, copy, erase, cd, mkdir, rmdir, **in, out** ("Performs an I/O read to **Dakota** I/O Space (0x80000000 is added to the address)"), fill, dump, search, call, load, read, write, boot, reboot, debug, break, monitor, regs, sregs, go, step, pstep, disasm, rem, echo, goto, sleep.
  * `reboot` "Transfers control to the reset vector in high memory 0xfff00100".
  * `mode A` selects the async (serial) console.
* Open Firmware-style device paths:
  * `/pci@80000000/pci%x,%x@%x,%x/%s@%x:%x,%x`
  * `/pci@80000000/pci1000,%x@%x,%x:%x;`
  * NVRAM variables such as `fw-boot-path=` (6050 image)
* Internal VDISK "DAKOTA VDSK": `PW.PPC`, `AUTOEXEC.6MD`, `BBL/RUBY/KEYBD/MOUSE/ETHER/PCI_C970/TKRING/TRPCI/TCPIP/SCSI.6XS`, `SEL_IPBT.6XE`, `BMP.6XE`, `BOOT.6XE`, `AUDIO/NETWORK/OEM/KEYBRD/RAMCHIP/DASD.BMP`, `POWERONL/SUPERL/CURRENT/KEY/FRAME1-4/KEYERROR/SUPER/DRV_DSK/SMSDSK/WARNING/PAPERCUT.PIC`.
* `AUTOEXEC.6MD` (at RAM 0x5736E):
  * step 1: load console drivers
  * step 2: `mode` 640x480
  * step 3: show the OEM bitmap
  * step 4: keyboard and mouse
  * step 5: IAT_* internal commands, memory test, network, DASD, audio
  * "WARNING: No audio can play during memory test ... parity check halts PCI Bus Activity"
* Checkpoint codes:
  * assembly path, in order: recovery block 04, 04, 24, 22, 23, DD, BA, BB, BC, then steps 08-18 (hex) on 0x3BC/0x680; main block 33, 04, 19-1F, DD, 24, 22, 23, BA, BB, BC
  * C code: `checkpoint(code)` (58 call sites) and `exitcheckpoint()`; codes 0xFC/0xFD mark failure.
  * No numeric error-code table such as E1xx was found in ROM. The diskette diagnostics carry the SRN/error texts.

---

## 7. Comparison with other images: can one core run "both models"?

* **7248 and Power Series 830/850 (6050/6070) run the same firmware.**
  * The 1.04 images P40H4388 (7248/OEM) and P40H4386 (6050/6070) have **identical recovery blocks**.
  * After decompression, their main RAM images differ only in the part number, the build stamp and the internal RAM-disk content: OEM.BMP vs EVO.BMP, AUTOEXEC.6MD, and an extra program plus `fw-boot-path` strings in the 6050 image. **No code differs.**
  * The machine type is chosen at run time from the planar ID (0xF0-F3 IDE board, 0xF4-F7 SCSI board) and the model strings.
  * The 6050/6070 line continued to 1.10 (P93H1904, 08/1996) and the 7248 line to 1.11/1.12. They have the same structure, recovery-block layout and reset path (traces are identical apart from checkpoint codes).
  * So **one core with a planar-ID input (0xF5 = 7248-100, 0xF4 = 120 MHz, 0xF6/F7 = 133 MHz; 0xF0-F3 = Power Series without SCSI)** covers both. Population differs: the 7248 has a 53C810 on the planar.
* **Sandalfoot images** (P12H0354, P52G0686: 6015 / 7020-40P) share the code base: the same block format, descriptor, LZW payload, xlc C runtime and checkpoint scheme. Their reset path is different:
  * They use an **IBM 660-style bridge** with direct-mapped config at **0x80800800** (dev-0 register 0x4C), and read 0x80000841, 0x80000820/0x803/0x804.
  * They read **0xBFFFEFF0**, and NVRAM data is at **0x77**.
  * There is no Fire Coral.
  * They are not hardware-compatible with Carolina.
* **ThinkPad 850 (7249/6042)** firmware could not be compared because it is encrypted. It is a different board (603e, 660-family bridge, extended I/O controller per the redbook).

---

## 8. Next steps

1. **Ghidra project: recommended.** The RAM image has 1334 named functions and a single TOC, so it is very tractable.
   * Load `7248_v1.12_main_ram_image_at_00000000.bin` as PowerPC:BE:32:default at 0x0. Load the ROM at 0xFFF00000 as a second program or overlay.
   * Import `symbols_v1.12_ram.txt` as labels and set r2 = 0x105980.
   * Each loadable driver (`*.6XS` in the VDISK) is a separate module with its own `init_main/main` and TOC. The `fw_call_vector` table (indirect calls via `lwzu r11,N(r4)`) is the firmware service table; recover it to get named PCI-config, console and timer services.
2. Recover the **on-board PCI device numbers** for S3, AMD and NCR. Candidates: the platform table that `init_pci_stuff` gets from 0x4C80, and the `pci_logical_2_physical_slot` table. Also recover the PCI interrupt routing (Fire Coral register indices 0x41-0x47 = 0x10..0x16 look like IRQ-routing or slot tables).
3. Decode the Fire Coral index registers (0x02-0x47), PICR1/PICR2/MCCR values against the MPC105 manual, and the SIMM presence-detect table at 0xFFF05BA4. Together these give a minimal MPC105 + Fire Coral model sufficient to pass memory init.
4. Identify ports 0x680, 0x8C0/0x8C1 and 0x4690. In the core, implement 0x3BC/0x680/0x8C0 as **POST-code sinks** from the start; they show boot progress without video.
5. Emulator bring-up path:
   * the reset path needs the CPU (604 with BATs, DSI exception and decrementer), MPC105 config space with RAM behind it, and Fire Coral index/data registers
   * then PIT/PIC/DMA, RTC + NVRAM (0x74/0x75/0x76), the 8042, PC87312 and a 16550 at 0x3F8 (`mode A` serial console)
   * then S3 864 VGA for the GUI
6. Try to obtain the official v1.11 P93H4940.IMG (CRC-32 0x7C987E45) and the final v1.12 for diffing.

### Tools written (`firmware/tools/`)

| tool | purpose |
|---|---|
| `entropy_map.py` | per-block entropy; locates the compressed region |
| `cmp_blocks.py` | blockwise binary compare |
| `endian_score.py` | BE vs LE opcode plausibility |
| `ppctrace.py` | constant-propagating sweep over objdump output: lists every constant-address load/store, decodes CF8 PCI config, and with `--syms` lists constant arguments to I/O helper calls |
| `tbtab.py` | recovers function names from XCOFF traceback tables |
| `annotate.py` | objdump listing with function labels and symbolic branch targets |
| `unlzw_rom.py` | ROM LZW (compress 4.x) decompressor |
| `romimg.py` | parses image blocks and descriptors and builds the RAM image (`--ram`) |
| `find_pci_ids.py` | finds `(dev<<16)\|ven` constants built with lis/addi |
