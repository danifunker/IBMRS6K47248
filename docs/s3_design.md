# S3 Vision864 + SDAC: what the firmware uses, and an RTL design

The on-board video of the 7248 ("E15", AIX `iga0`): an S3 86C864
(PCI 5333:88C0), an S3 SDAC (86C716 class: RAMDAC and clock synthesizer)
and 2 MB of DRAM. It is PCI bus 0 device 14, interrupt pin INTD#, routed
to ISA IRQ 15 (`hardware_inventory.md`). This note is milestone M4's
groundwork (`plan.md`).

Sources: the firmware's S3 driver in the v1.12 RAM image
(`firmware/images/7248_v1.12_main_ram_image_at_00000000.bin`,
`firmware/disasm/v1.12_ram_image_00000000.annotated.s`,
`symbols_v1.12_ram.txt`), read for this note with a small annotator that
resolves the driver's TOC and its firmware-service calls (section 1.1).
Everything in section 1 is from the disassembly, with the PC given.
Sections 2 and 3 mark what is general knowledge and was not checked here.

Contents:

1. The firmware's S3 driver
2. What AIX 4.3.3 and Windows NT would need beyond it (general knowledge)
3. Reference models (MAME, QEMU)
4. A proposed RTL design
5. Open questions

---

## 0. Summary

- The firmware sets one mode at start-up and on `mode 0 -1 0`: **640 x 480
  at 8 bits a pixel, packed (S3 "enhanced" mode), pitch 640 bytes**, with
  a **linear frame buffer at PCI 0x0280_0000 (CPU 0xC280_0000)** that it
  sets itself through CR59/CR5A (it never writes a PCI BAR). Its mode
  table also has 1024 x 768, 1280 x 1024, 1600 x 1200 at 8 bits and some
  16/32-bit modes (`mode 1`, `mode 2`, ...), all packed.
- It **never uses VGA text mode, planar modes or the A0000 window**. Text
  is drawn by the **S3 graphics engine**: monochrome colour expansion of
  the font through the pixel-transfer port (E2E8). Clearing is a
  **rectangle fill**, scrolling a **screen-to-screen BitBLT**, icons and
  `bmp` pictures are **colour image transfers through E2E8** (16-bit,
  bottom-up). Only the hardware cursor's image (1 KB at 2 MB - 2 KB) and
  `s3_getbitmap`'s reads touch the frame buffer directly.
- It uses the **S3 hardware cursor** (64 x 64, AND/XOR, an 8-pixel-wide
  inverting bar) and moves it **from the vertical-retrace interrupt** (CR11
  / CR32, IRQ 15, status in 42E8 bit 0). Without that interrupt the cursor
  never moves.
- It programs the **SDAC** through CR55's RS2 bit: command register 00
  (8-bit pseudo-colour), video PLL f2-f7 all to the dot clock (31.5 MHz,
  640x480 at 72 Hz, for monitor class 3, which `main` passes and an
  unknown monitor ID gives; 25.26 MHz, 60 Hz, for class 0), MCLK 60 MHz,
  PLL control 22.
  The palette is 6-bit.
- Read-backs that must be right: the PCI ID (5333:88Cx), CR36 (written
  0x8E = 2 MB, read back for the cursor address), CR59/CR5A, the 3DA
  vertical-retrace bit, 9AE8's FIFO and busy bits, 42E8 bit 0, the
  monitor ID nibble at 3C8 (with CR55 bit 2), 3CC, and the memory-size
  probe: **writes above 2 MB must not alias into the first 2 MB**. It
  never reads CR30 (the chip ID) or a DAC ID.
- Phase-1 RTL: PCI configuration, the VGA/S3 register file, the SDAC
  registers, a CRTC in packed 8 bpp with the S3 overflow bits, scan-out
  from VRAM in the HPS DDR3 through the palette with the hardware cursor,
  the LFB, the vertical-retrace interrupt, and a graphics engine doing
  rectangle fill, BitBLT, mono expansion and colour image transfer from
  the CPU with all 16 mixes, scissors and write mask. Roughly 5-7 k ALMs
  and 8-20 M10K (section 4.10).

---

## 1. The firmware's S3 driver

### 1.1 Where it is and how to read it

The driver is a separately linked module inside the RAM image (its own
header, `init_main`/`main` and TOC, like the RAM disk's `.6XS` drivers),
"IBM Power Series S15 Video Driver for 928, 864, and 964 PCI" (string at
0x6026A). Where it lies:

| | address |
|---|---|
| module header | 0x58F1C (offsets inside the module are from here) |
| code | 0x5911C - 0x5EF1C (entry 0x5911C calls `init_main` 0x59144) |
| data (tables, state) | 0x5F000 - 0x60480 |
| TOC (r2) | 0x60410 = 0x58F1C + 0x74F4 |
| function descriptors | 0x60320 ... (`{entry, TOC 0x74F4, 0}`, module-relative) |
| driver vtable registered with the console manager | 0x60224 (14 entries) |

The image is unrelocated: a TOC entry or a pointer in the data holds a
module offset; the address in the RAM image is 0x58F1C + offset.

All I/O goes through the **firmware service table** at 0xF83D8 (main TOC
entry 64): `lwz rX,4(r2)` gives the table pointer, `lwzu r11,N(rX)` the
service, `bl 0x59490` the glue. The services the driver uses:

| N | service | | N | service |
|---|---|---|---|---|
| 324 | `in8(port)` | | 412 | `timeout` |
| 336 | `in16le(port)` (`lhz` + swap) | | 404 | `get_timeout_value` |
| 344 | `out8(port, v)` | | 448 | `sleep` |
| 348 | `out16(port, v)`: `sth`, big-endian | | 488 | `ext_int_registrar` |
| 352 | `out32(port, v)`: `stw`, big-endian | | 512 | `checkpoint` (progress code) |
| 356 | `out16le(port, v)`: swap + `sth` | | 668 | platform-table byte 1 (0xF0 on every Carolina planar ID; table at 0x4D18) |
| 672/684/696/700/888 | PCI: slot count, config read32, config write32, slot-to-device, logical-to-physical slot | | 892-984 | residual-data packets |

A port is CPU address 0x8000_0000 + port. `out16le(0x3C4, 0x4912)` is one
16-bit store: 0x12 to 3C4 (the index) and 0x49 to 3C5 (the data) in one
bus cycle.

Driver state: a structure at **D_5F014** (`TOC+44`): +3520 a reentrancy
flag, +3780/+3784 the text foreground/background colours, +3792 the
monitor class (0-3), +3804 the VRAM size in MB, +3808 the current mode
descriptor, +3812 "vertical interrupt registered", +3816/+3820/+3824 the
cursor update state and position, +3832 a flag whose initial value is 1
(selects the 3C3/CR66 path below). D_5F00C is the DAC type (0 Bt485, 1
RGB525, 2 SDAC, 3 Trio-internal) and D_5F010 the chip family (0: 928, 2:
864/868/Trio), both set by `s3_Found`.

### 1.2 The functions

| PC | function | what it does |
|---|---|---|
| 0x59144 | `init_main` | module entry; reads its arguments, calls `main` |
| 0x594B0 | `main` | checkpoint 0x533300A7; `s3_query`; `s3_Found(1)`; `s3_init(0x201, 3)`; registers the console driver (vtable 0x60224); checkpoint 0x533300A8 |
| 0x595BC / 0x595EC | `s3_query`, `s3_query_device` | strings ("IBM Power Series S15 864 PCI Adapter") |
| 0x59668 | `s3_diags_hook` | returns tables to the diagnostics |
| 0x5971C | `build_s3` | residual data for the OS (section 1.4) |
| 0x59E38 | `S3_Unlock` | CR38=48, CR39=A5, CR11 &= 7F, CR40 \|= 01; SR8=06 only for the Trio |
| 0x59FAC | `s3_Found` | PCI scan for 5333:88B0/88C0/8880/8810, sets family/DAC type, PCI command = 3 |
| 0x5A104 | `s3_POS` | wake-up and engine reset (section 1.5) |
| 0x5A5A0 | `Async_Reset` | sequencer synchronous reset (SR1 screen off, SR0 00 then 03) |
| 0x5A6DC | `dac_init` | DAC set-up per DAC type; for the SDAC: command reg, PLL |
| 0x5AD24 / 0x5ADF4 | `s3_bt485_read/write` | Bt485 through CR55 RS2/RS3 (928 only) |
| 0x5AEC4 | `s3_sdac_write` | CR55 \|= 1 (RS2), `out8(port, v)`, CR55 restored |
| 0x5AF90 | `s3_sdac_write2` | CR55 \|= 1; 3C8 = PLL index; 3C9 = M; 3C9 = N (if index < 0x0E); CR55 restored |
| 0x5B098 / 0x5B198 | `s3_rgb525_read/write` | RGB525 (964 only) |
| 0x5B29C | `s3_load_palette` | 768 bytes to 3C9, shifted right 2 for the SDAC |
| 0x5B3E4 | `s3_video_int_handler` | the vertical-retrace interrupt: moves the cursor (section 1.10) |
| 0x5B608 | `s3_get_base_address` | `0xC000_0000 \| CR59 << 24 \| CR5A << 16` |
| 0x5B6C4 | `s3_memory_size` | VRAM sizing through the LFB (section 1.8) |
| 0x5B944 | `s3_init(mode, monitor)` | `s3_init_2`; registers the interrupt; enables it |
| 0x5BB64 | `s3_init_2(mode, monitor)` | the mode set (section 1.5) |
| 0x5C9B8 | `vsync_wait` | polls 3DA bit 3: waits for the end, then the start, of vertical retrace (timeout) |
| 0x5CB20 | `fifo_wait(n)` | polls 9AE8 until bit (8 - n) is 0; on timeout `out8(0x680, 0x69)` |
| 0x5CC68 | `ge_wait` | polls 9AE8 until bit 9 (busy) is 0; on timeout `out8(0x680, 0x69)` |
| 0x5CDA4 | `s3_clear_screen` | scissors, masks, then `s3_rect_fill` of the screen |
| 0x5CF30 | `s3_rect_fill(x0,y0,x1,y1,c)` | engine rectangle fill |
| 0x5D090 | `s3_scroll_window` | engine BitBLT, then two fills |
| 0x5D3A4 | `color_xform` | colour index to pixel value (identity at 8 bpp) |
| 0x5D424 | `s3_putchar` | engine mono expansion of one glyph through E2E8 |
| 0x5D6D8 | `nearest` | nearest palette entry (software) |
| 0x5D7F4 | `compute_pad` | BMP row padding |
| 0x5D900 | `s3_getbitmap` | `memcpy` rows out of the LFB |
| 0x5DAC4 | `s3_putbitmap` | engine colour image transfer through E2E8 |
| 0x5E464 | `s3dac_goto_xy` | stores x, y, arms the interrupt that moves the cursor |
| 0x5E600 | `s3_set_colors` | text colours |
| 0x5ECE8 | `init_cursor_s3dac(size)` | writes the cursor image through the LFB, CR45 bit 0 |
| 0x5EEC8 | `s3_cursor_size` | calls the above |

Call order at load (`autoexec`'s `s3`): `init_main` -> `main` ->
`s3_Found(1)` -> `s3_init(0x201, 3)` -> `s3_init_2` -> `s3_POS` (inside it
`s3_Found` again) -> ... -> `dac_init` -> `s3_load_palette` ->
`s3_cursor_size(0)` -> `s3_clear_screen`; back in `s3_init` the interrupt.
`mode 0 -1 0` (`mode_cmd` 0x135A8 -> `console_init` 0x1BD54) calls the
vtable's init again: mode index 0 is VESA number 0x201 (index 1 0x205
1024x768, 2 0x107 1280x1024, 3 0x274 1600x1200, 7 0x211 640x480x16, 8
0x117 1024x768x16, 9 0x21A, 11 0x275, 12 0x103 800x600 (not supported by
this driver: `s3_init_2` returns 0), 0x220, 0x222, 0x21B), monitor -1
(detect).

### 1.3 PCI configuration

- `s3_Found` (0x59FAC): for each logical slot, `pci_config_read_32(slot,
  0)` (0x5A02C); the ID is compared after masking the device ID's low
  nibble (`rlwinm r0,r3,0,16,11`), so **5333:88C0 or 88C1 both match**.
  For 88C0 it sets family = 2 and DAC type = 2 (SDAC) (0x5A074). For the
  first device found it writes **`pci_config_write_32(slot, 4, 3)`**
  (0x5A0B0): command = I/O space + memory space, status 0; any other S3
  found gets 0.
- `pci_reset_slots` (0x26C80, main firmware) earlier wrote command = 0 to
  every device except the MPC105 and Fire Coral: the S3 is disabled until
  the driver loads.
- **No BAR is written or sized.** The LFB address comes from CR59/CR5A,
  written from a table (0x02/0x80, section 1.5). The firmware has no
  generic BAR allocator; the P9100 driver likewise hard-codes 0xC100_0000.
- `build_s3` (0x5971C) re-reads the IDs (0x59784) and builds the residual
  data AIX reads: I/O ranges (0x599C8-0x59D4C) 0102 (1), 03B4 (2), 03B8
  (4), 03BF (12, to 3CA), 03CC (1), 03CE (2), 03D4 (2), 03D8 (5), 42E8,
  46E8, 4AE8, 82E8, 86E8, ... BEE8 (every 0x400), E2E8, E2EA; memory
  0x0280_0000 length 2 MB (0x59D6C); a display packet with the CPU address
  **0xC280_0000**, 2 MB, width, height, pitch (0x59D98); IRQ mask 0x8000
  = **IRQ 15** (0x599A8).

### 1.4 What the residual data says the OS gets

As above: the S3 at its legacy VGA ports plus the 8514 register ports,
the 2 MB LFB at PCI 0x0280_0000, IRQ 15. AIX takes the frame buffer from
the display packet.

### 1.5 The mode set, in order (mode 0x201, the 864 with the SDAC)

`s3_init_2` (0x5BB64). Every CRx write below is `out8(3D4, x)`, `out8(3D5,
v)`; SRx through 3C4/3C5; ARx through 3C0; GRx through 3CE/3CF; some are
`out16le` pairs (one 16-bit cycle).

| PC | access | notes |
|---|---|---|
| 0x5BB64-0x5BC2C | mode -> descriptor (state+3808): 0x201 -> D_5F30C | modes other than 0x201/0x205/0x211 need VRAM >= 2 MB (state+3804) |
| 0x5BC38 | `s3_POS`: | |
| 0x5A118 | `s3_Found(1)` | PCI ID read, command = 3 |
| 0x5A200 | out 3C3 = 01 | video subsystem enable (flag +3832 = 1; the 46E8 = 1E / 0102 = 01 / 4AE8 = 0 / 46E8 = 0E wake-up at 0x5A3DC-0x5A428 is not taken) |
| 0x5A214-0x5A234 | in 3CC; out 3C2 = misc \| 0D | |
| 0x5A23C | `S3_Unlock`: CR38 = 48, CR39 = A5, CR11 &= 7F (read back), CR40 \|= 01 (read back) | |
| 0x5A250-0x5A3D0 | SR12 = 49, SR13 = 55, SR10 = 42, SR11 = 41 (out16le); out 3C4 = (misc \| 0D) (a stray index); SR14 = 03, sleep, SR14 = 00, sleep; CR36 read; SR10 = 44 and SR11 = 41 if CR36[3:2] = 0; SR18 = 40; SR15 = 00; SR15 = 03 | Trio-style PLL programming, **executed on the 864 too**: SR10-SR18 do not exist on an 864 and must be harmless |
| 0x5A478 | out16le 42E8 = 8000 | graphics engine reset |
| 0x5A480 | `ge_wait` | reads 9AE8, bit 9 must clear |
| 0x5A494 | out16le 42E8 = 4000 | engine enabled |
| 0x5A49C | `ge_wait` | |
| 0x5A4B0 | CR40 = 00 | |
| 0x5BCAC-0x5BE48 | monitor ID: CR55 \|= 04; in 3C8; in 3CC (misc); 3C2 = misc & 3F; 256 x in 3C8, AND of bits 3-0; 3C2 = (misc & 3F) \| C0; 256 x in 3C8, OR of bits 3-0; 3C2 = misc; CR55 &= ~04 | the index into a 256-byte table at 0x5FDD8 is AND + 16 x (AND ^ OR); every entry is 3 except AND 6 or B with XOR 0, and AND 2 with XOR 8 (0). Used only when the monitor argument is -1 |
| 0x5BF20 | SR0D = (SR0D & 0F) \| 50 | syncs off during the change (read back) |
| 0x5BF68 | `vsync_wait` | 3DA bit 3 must toggle (else ~20 ticks of timeout) |
| 0x5BF78 / 0x5BF90 | in 3DA; out 3C0 = 00 | attribute flip-flop reset; palette address source off (blank) |
| 0x5BF98 | `Async_Reset`: SR1 = 20; SR0 = 00; SR0 = 03; SR1 = SR1 & DF (read back) | |
| 0x5BFAC-0x5C024 | SR2 = 03, SR3 = 00, SR4 = 02 | |
| 0x5C038-0x5C094 | 38 CR pairs from D_5F082 (below) | |
| 0x5C1D8-0x5C220 | **CR36 = 8E, CR37 = 0F** | 864 with SDAC (the 928 gets 9F/FF, the Trio 82/0F + CR68 = 88) |
| 0x5C228-0x5C294 | CR60 ... CR6E = 00 (15 writes, D_5F0CE) | |
| 0x5C2A8-0x5C2D0 | SR1-SR4 = 01 0F 00 0E | from the mode's VGA table P (D_5F13C) |
| 0x5C304 | 3C2 = EF | P[8 + monitor] |
| 0x5C31C / 0x5C34C | SR0 = 03; SR9 = 02 | |
| 0x5C378-0x5C3D4 | in 3DA; AR00-AR14 = 00 01 02 03 04 05 06 07 10 11 12 13 14 15 16 17 41 00 0F 00 00 | index written without bit 5 |
| 0x5C3DC-0x5C414 | GR0-GR8 = 00 00 00 00 00 40 05 0F FF | |
| 0x5C428 | SR4 = 0E | descriptor byte 8: chain 4 |
| 0x5C464 | **CR66 = 01** | descriptor byte 11 (flag +3832 = 1; else 4AE8 would get it) |
| 0x5C4E4-0x5C544 | CR00-CR18 (25 values, table below) | |
| 0x5C57C-0x5C5B4 | 21 extended CRs (list at state+271) | |
| 0x5C5D8-0x5C640 | the mode's extra pairs: CR54 = E0, CR60 = FF, CR61 = 80, CR62 = 50, CR68 = AC | |
| 0x5C6B0 | `s3_memory_size` -> state+3804 | section 1.8 |
| 0x5C6C8-0x5C808 | CR36 read; only if CR36[7:5] = 110 (1 MB): CR54, CR61/CR62 halved/doubled | not on a 2 MB board |
| 0x5C834 | `dac_init` (0x5A6DC): 3C6 = FF; **SDAC command = 00** (CR55 \|= 1, 3C6 = 00, CR55 restored); **PLL f2..f7 = (M, N)** (the same pair six times); **PLL 0A = (41, 42)**; **PLL 0E = 22** | each through 3C8/3C9 with RS2 |
| 0x5C8C0-0x5C92C | SR8 = 06; SR0D &= 0F | unlock, syncs on |
| 0x5C93C | `s3_load_palette(0)`: in 3DA; 3C0 = 00; 3C8 = 00; 768 x 3C9 (value >> 2); in 3DA; 3C0 = 20 | default palette at D_5FF24: an RGB 3-3-2 cube (8 x 8 x 4) with a 32-step grey ramp in entries 112-143 |
| 0x5C944 | `s3_cursor_size(0)` -> `init_cursor_s3dac(0)` | 1 KB of cursor image through the LFB; CR45 &= ~01 |
| 0x5C958 / 0x5C970 | in 3DA; 3C0 = 20 | screen on |
| 0x5C97C | `s3_clear_screen` | section 1.9 |
| then in `s3_init` | | |
| 0x5B9E0 | platform byte (0xF0 on Carolina): not FE/F0/C0 would mean `out8(0x839, 6)` | not on Carolina |
| 0x5BA30 | `ext_int_registrar(2, 15, s3_video_int_handler)` | |
| 0x5BA6C-0x5BB24 | CR11 \|= 30; CR32 \|= 10; state+3816 = 1; CR11 &= ~20 | vertical interrupt on (section 1.10) |

The 38 pairs of D_5F082 (0x5C038), in order:
CR31=85 CR50=00 CR51=00 CR53=00 CR54=38 **CR59=02 CR5A=80** **CR58=13**
CR5C=00 CR5D=00 CR5E=00 CR60=07 CR61=80 CR62=A1 CR32=00 CR33=00 CR34=00
CR35=00 CR3A=05 CR3B=5A CR3C=10 CR40=09 CR43=00 CR45=00 CR46=00 CR47=00
CR48=00 CR49=00 CR4A=00 CR4B=00 **CR4C=07 CR4D=FE** CR4E=00 CR4F=00 CR55=00
CR63=00 CR64=00 CR65=00.

The 21 extended CRs (indices at state+271: 42 3B 3C 31 3A 40 50 54 5D 60
61 62 58 33 43 13 5E 51 5C 34 55), values for 0x201:

| | CR42 | 3B | 3C | 31 | 3A | 40 | 50 | 54 | 5D | 60 | 61 | 62 | 58 | 33 | 43 | 13 | 5E | 51 | 5C | 34 | 55 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| monitor 0-2 | 00 | 5A | 91 | 88 | 15 | 01 | 40 | 38 | 00 | 07 | 81 | 01 | 12 | 00 | 00 | 50 | 00 | 00 | 00 | 00 | 00 |
| monitor 3 | 0B | 5E | 40 | 89 | 15 | 01 | 40 | 00 | 00 | 0F | 80 | A1 | 12 | 00 | 00 | 50 | 00 | 00 | 00 | 00 | 00 |

CR00-CR18 for 0x201:

| | 00 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 0A-0D | 0E 0F | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| monitor 0-2 | 5F | 4F | 50 | 82 | 54 | 80 | 0B | 3E | 00 | 40 | 00 | FF 00 | EA | 0C | DF | 80 | 60 | E7 | 04 | AB | FF |
| monitor 3 | 63 | 4F | 50 | 86 | 53 | 98 | 07 | 3E | 00 | 40 | 00 | FF 00 | E8 | 0B | DF | 80 | 60 | DF | 07 | AB | FF |

(CR13 = 80 here is overwritten by the extended list's CR13 = 50.)

What that gives:

| | monitor 0-2 | monitor 3 (the table's default) |
|---|---|---|
| SDAC PLL (M, N) | 7D, 67: 25.26 MHz | 56, 63: 31.50 MHz |
| horizontal | 800 total, 640 shown, sync 672-768 | 832 total, 640 shown, sync 664-704 |
| vertical | 525 total, 480 shown, sync 490-492 | 521 total, 480 shown, sync 488-491 |
| refresh | 60 Hz (VGA) | 72.7 Hz (VESA 640x480@72 timing, one line more) |
| syncs | misc EF: both negative | same |

The SDAC PLL: f = 14.31818 MHz x (M[6:0] + 2) / ((N[4:0] + 2) x
2^N[6:5]). MCLK (0A: 41, 42) = 60.0 MHz.

Pitch: CR13 = 0x50 with CR31 bit 3 (enhanced mapping) set counts in 8
bytes: **640 bytes**; CR51[5:4] = 0, CR43 bit 2 = 0. Start address 0
(CR0C/CR0D = 0, CR31[5:4] = 0, CR51[1:0] = 0). The engine's pitch: CR50 =
0x40 (bits 7:6 = 01: 640 wide; bits 5:4 = 00: 1 byte a pixel). LFB: CR58 =
0x12 (bit 4 enable, bits 1:0 = 10: a 2 MB window) at CR59/CR5A =
0x0280_0000.

The other modes, decoded the same way (D_5F014 + offset; table pointer at
descriptor + 48 + monitor x 4 for the 864):

| mode | descriptor | size, bpp | CR50 | monitors: dot clock |
|---|---|---|---|---|
| 0x201 | +760 | 640x480x8 | 40 | 0-2: 25.26; 3: 31.50 |
| 0x205 | +1528 | 1024x768x8 | 00 | 0-1: 45.0 (interlaced, CR42 bit 5); 2: 65.0; 3: 79.9 |
| 0x211 | +932 | 640x480x16 | 50 | (no SDAC entry in its tables) |
| 0x107 | +2660 | 1280x1024x8 | C0 | SDAC command 10 (2:1 pixel mux), CR67 = 10; 0-1: 75.2 (interlaced); 2: 110.1; 3: 130.1 |
| 0x274 | +3392 | 1600x1200x8 | 81 | |
| 0x117 | +1808 | 1024x768x16 | 10 | |
| 0x220 | +1104 | 640x480x32 | 30 | |
| 0x222 | +1980 | 1024x768x32 | 30 | the code allows it with 2 MB |
| 0x21A/0x21B/0x275 | +2940/+3004/+3456 | 1280x1024x16/24, 1600x1200x16 | | need 4 MB |

For the monitor classes: CR42[2:0] selects the SDAC clock (0 for
monitors 0-2 of 0x201, 3 for monitor 3; 5 and 2 at 1024x768); f2-f7 are
all programmed with the mode's clock, f0/f1 presumably keep their
power-on 25.175 / 28.322 MHz (an assumption from the ICS5342-class
parts), so either reading of the SDAC's clock select (the CS pins
from CR42, or the PLL control register's internal select) gives the right
clock.

### 1.6 The SDAC

All SDAC access is with **CR55 bit 0 (RS2) set** (`s3_sdac_write`
0x5AEC4, `s3_sdac_write2` 0x5AF90), restored after each access:

| port with RS2 = 1 | SDAC register | written |
|---|---|---|
| 3C6 | command register | 00 (8-bit pseudo-colour) for every 8-bpp mode except 0x107 (10) |
| 3C8 | PLL write index | 02-07, 0A, 0E |
| 3C9 | PLL data: M then N (one byte only for index 0E) | f2-f7 = mode clock, 0A = 41 42, 0E = 22 |

The DAC itself (RS2 = 0): 3C6 pixel mask = FF, 3C8 write index, 3C9 data
(6-bit values; the driver shifts its 8-bit palette right by 2 for the SDAC,
0x5B354). Nothing is read back from the SDAC (no ID, no PLL read-back).

### 1.7 The monitor ID

With CR55 bit 2 set, 3C8 reads the monitor ID in bits 3-0 (general
input port; the 864's use of CR55 bit 2 is inferred from the code and
general knowledge). The driver reads it 256 times with both sync
polarity bits of the misc register clear and 256 times with both set
(0x5BD48, 0x5BD94) and indexes the table at 0x5FDD8. Only classes 0
(IDs 6 and B static, or 2 toggling with bit 3) and 3 (everything else)
come out. A constant ID nibble other than 6, B or 2 gives class 3. The
result is used only when the monitor argument is -1 (`mode 0 -1 0`);
`main`'s own call passes 3.

### 1.8 VRAM sizing (`s3_memory_size`, 0x5B6C4)

For k = 4, 3, 2, 1 (MB):

1. CR36 = (CR36 & 1F) \| (4 - k) << 6 (bits 7:6 = 00, 01, 10, 11: 4, 3,
   2, 1 MB) (0x5B800); CR58 = (CR58 & FC) \| window (k = 4, 3: 11 = 4 MB;
   2: 10; 1: 01) (0x5B84C).
2. Four words at the LFB base: 55AA55AA AAAA5555 AA55AA55 5555AAAA
   (0x5B854).
3. A dummy read of 3D5, then four words 5A5A5A5A AA5555AA A5A5A5A5 55AA5A5A
   at **base + (k - 1) MB** (base + 64 for k = 1) (0x5B888).
4. All eight words read back; if all match, the size is k.

On a 2 MB board k = 4 writes at base + 3 MB and k = 3 at base + 2 MB.
**Those must neither land in the first 2 MB nor read back as written**;
otherwise the driver decides 4 MB, leaves CR36 at 4 MB, and puts the
cursor image at 4 MB - 2 KB. Then k = 2 succeeds and leaves CR36 = 8E,
CR58 window 2 MB. The LFB must decode at least 4 MB at the base while
CR58[1:0] = 11.

### 1.9 Drawing: the graphics engine

All engine registers are written with `out16le` (one 16-bit cycle), and
`fifo_wait(n)` / `ge_wait` poll 9AE8 first. Mix encodings are the 8514's
(bits 6:5 source: 00 background colour, 01 foreground colour, 10 CPU data,
11 display memory; bits 3:0 the function, 7 = source).

**Clear screen** (`s3_clear_screen` 0x5CDA4): `fifo_wait(5)`; BEE8 =
1000 (scissors top 0), 2000 (left 0), 3000 \| (H - 1) (bottom), 4000 \|
(W - 1) (right), E000 (MULT_MISC = 0); `fifo_wait(3)`; AAE8 = FFFF (write
mask), AEE8 = 0001 (read mask), B2E8 = 0000 (colour compare); then
`s3_rect_fill(0, 0, W - 1, H - 1, background)`.

**Rectangle fill** (`s3_rect_fill` 0x5CF30): `fifo_wait(3)`; BAE8 = 0027
(FRGD_MIX: foreground colour, new); A6E8 = colour (FRGD_COLOR); BEE8 = A000
(PIX_CNTL: foreground mix always); `fifo_wait(6)`; 86E8 = x0 (CUR_X);
82E8 = y0 (CUR_Y); 96E8 = x1 - x0 (MAJ_AXIS_PCNT); BEE8 = 0000 \| (y1 -
y0) (MIN_AXIS_PCNT); **9AE8 = 40F3** (CMD: rectangle, INC_Y, YMAJAXIS,
INC_X, DRAW, PLANAR, WRTDATA).

**Scroll** (`s3_scroll_window` 0x5D090): BEE8 = A000; BAE8 = 0067
(display memory, new); `fifo_wait(7)`; 86E8/82E8 = source x, y; 8EE8 =
destination x (DESTX_DIASTP); 8AE8 = destination y (DESTY_AXSTP); 96E8 =
w - 1; BEE8 = h - 1; **9AE8 = C0B3** (CMD: BitBLT, INC_Y, INC_X, DRAW,
PLANAR, WRTDATA). Always increasing x and y: the source is below/right of
the destination. Then BAE8 = 0027, A6E8 = background, BEE8 = A000 and two
40F3 rectangle fills for the uncovered strips.

**Text** (`s3_putchar` 0x5D424), one glyph a call: `fifo_wait(5)`; BAE8 =
0027; A6E8 = foreground; B6E8 = 0007 (BKGD_MIX: background colour, new);
A2E8 = background (BKGD_COLOR); BEE8 = A080 (PIX_CNTL: CPU data selects
the mix); `fifo_wait(5)`; 86E8 = x; 82E8 = y; 96E8 = w - 1; BEE8 = h - 1;
`ge_wait`; **9AE8 = 51B3** (CMD: rectangle, BYTSEQ, 8-bit bus, PCDATA,
INC_Y, INC_X, DRAW, PLANAR (across-plane: mono expansion), WRTDATA); then
**h x ceil(w / 8) bytes, each `out16le(E2E8, byte)`** (the byte at E2E8,
E2E9 = 0) **with no FIFO polling between them** (0x5D660-0x5D680). Bit 7
is the leftmost pixel; each row starts a new byte.

**Pictures** (`s3_putbitmap` 0x5DAC4): `fifo_wait(3)`; BAE8 = 0047 (CPU
data, new); BEE8 = A000; BEE8 = E100 if the bitmap has a transparency
flag (bitmap + 8), else E000 (MULT_MISC bit 8, with B2E8 = 0 from the
clear: colour compare, probably transparency of colour 0); `fifo_wait(6)`;
86E8 = x; 82E8 = y (the **bottom** row); 96E8 = w - 1; BEE8 = h - 1;
`ge_wait`; **9AE8 = 4331** (CMD: rectangle, **16-bit bus**, PCDATA, INC_X,
DRAW, WRTDATA; no INC_Y: rows go **up**; through-plane: colour data);
then per row ceil(w / 2) **`out16(E2E8, v)` big-endian stores**, v =
(pixel1 << 8) \| pixel0, so **E2E8 gets pixel 1 and E2E9 pixel 0**: with
BYTSEQ = 0 (high byte first) pixel 0 is drawn first. Each row starts a new
16-bit transfer (odd widths send a half-filled last word, 0x5E00C). 4-bit
and 8-bit BMPs are mapped through a palette table; 24-bit BMPs through
`nearest` (software). At 16/24/32 bpp the driver uses `out16`/`out32`
(E2E8 then E2EA); not used at 8 bpp. At the end BEE8 = E000.

**Reads**: GP_STAT (9AE8, `in16le`): bits 7:0 FIFO (bit 8 - n set means
fewer than n free slots), bit 9 busy. Nothing reads pixels through E2E8.
`s3_getbitmap` (0x5D900) reads rows straight from the LFB (`memcpy` from
0xC280_0000 + y x W + x).

### 1.10 The hardware cursor and the vertical interrupt

The cursor (SDAC, so the S3's own cursor): `init_cursor_s3dac(size)`
(0x5ECE8) computes the image address as LFB + (4 - CR36[7:6]) MB - 2 KB =
**VRAM 0x1F_F800** (CR36 = 8E; agrees with CR4C/CR4D = 07FE x 1 KB),
`ge_wait`, then writes 256 groups of 4 bytes with byte stores through the
LFB: {FF, FF, x, 00}, x = FF for the cursor's rows (size 3: rows 0-15, 2:
rows 7-15, 1: rows 14-15) else 00. In the S3 format (16 pixels per 4
bytes, AND plane bytes 0-1, XOR plane bytes 2-3, MSB first) that is
transparent everywhere except an **8-pixel-wide inverted bar** (AND = 1,
XOR = 1: invert, CR55 bit 4 = 0 "Windows" mode). Then CR45 bit 0 = (size
!= 0). CR4A/CR4B (colour stacks) stay 0, CR4E/CR4F = 0.

The position: `s3dac_goto_xy` (0x5E464) does nothing unless the interrupt
was registered (state+3812); it clears CR11 bit 4, stores x, y, sets the
state to 1, sets CR11 bit 4. The handler (0x5B3E4):

1. `in16le(42E8)`; if bit 0 is clear, return (shared IRQ 15).
2. `out16le(42E8, 0001)` (clear the vertical-sync interrupt; bits 15:14 =
   00, no engine change); save the 3D4 index (`in8(3D4)`).
3. CR11 &= ~10 (clear the latch).
4. State 1: state = 2, CR11 \|= 10 (re-arm for the next frame). State 2:
   CR47 = x[7:0], CR46 = x[10:8], CR49 = y[7:0], CR48 = y[15:8]
   (0x5B4DC-0x5B5A0), state = 0, latch left cleared.
5. Restore the 3D4 index.

So: the cursor moves one to two frames after `goto_xy`. In between, no
interrupts.

`s3_init` enables it (0x5BA6C): CR11 \|= 30, CR32 \|= 10 (interrupt
enable), CR11 &= ~20 (bit 5: disable = 0). IRQ 15 is level-triggered
(ELCR), so the request must drop when the handler clears it.

### 1.11 What must read back right

| register | read at | expects |
|---|---|---|
| PCI 00 | 0x5A02C, 0x59784 | 5333:88Cx |
| 3CC (misc) | 0x5A210, 0x5BD14, ... | what was written to 3C2 |
| 3C5 SR1, SR0D | 0x5A668, 0x5BF44 | as written |
| 3D4 (CRTC index) | 0x5B438, 0x5D474 | as written |
| CR11, CR32, CR40, CR45, CR55, CR58 | read-modify-write everywhere | as written |
| CR36 | 0x5A340, 0x5C6E8, 0x5ED34 | as written (8E after the mode set); bits 7:6 give the cursor address |
| CR59, CR5A | 0x5B640, 0x5B674 | 02, 80 (the LFB base) |
| 3C8 with CR55 bit 2 | 0x5BD54, 0x5BDA0 | monitor ID nibble |
| 3DA bit 3 | `vsync_wait` | vertical retrace, toggling |
| 9AE8 bits 7:0, 9 | `fifo_wait`, `ge_wait` | free slots / busy; a stuck bit costs a timeout and progress code 69 at port 680 |
| 42E8 bit 0 | the handler | vertical-sync interrupt pending |
| LFB | `s3_memory_size` | no aliasing above 2 MB |

Never read: CR30 (chip ID), CR2D-CR2F, CR37, CR68, any DAC/SDAC
register, the PLL, 3C2 (input status 0), E2E8, 46E8, 4AE8.

### 1.12 What the firmware does not use

VGA text and planar modes, the A0000-BFFFF window (no access anywhere in
the RAM image outside the S3 module, which uses only the LFB), the
attribute controller beyond its mode values, line drawing (CMD 2000),
short-stroke vectors (9EE8), pattern fills (E000), image reads, the
memory-mapped engine registers (CR53 = 00), the 46E8/0102 wake-up (path
not taken on the 864), 16/24/32 bpp unless a `mode` command asks, the
2:1 pixel mux (1280x1024 only), interlace (only monitor classes 0-1 at
1024x768 and above).

---

## 2. AIX 4.3.3 and Windows NT (general knowledge, not verified here)

Both are what plan.md aims at after the firmware. Their 864 drivers do
their own mode sets from their own tables and go well past the firmware:

AIX 4.3.3 (the S3 864 device support, `iga0`; the fileset naming would be
`devices.pci.3353c088`, from the byte-reversed PCI ID, unverified):

- Mode set by the LFT/X driver: 1024x768 and 1280x1024 at 8 bpp likely
  defaults; the 1280x1024 modes need the SDAC's 2:1 pixel mux (command 10,
  CR67 = 10) and dot clocks of 110-135 MHz.
- X server acceleration: rectangle fills, BitBLT in all four directions
  (overlapping copies right-to-left/bottom-up: CMD bits 5 and 7 clear),
  mono expansion for text, lines (CMD 2000, Bresenham error term 92E8,
  DESTX/DESTY as axial/diagonal steps), possibly short-stroke vectors
  (9EE8), possibly pattern fills, image reads through E2E8 (CMD with
  WRTDATA = 0), colour compare, plane masks; the hardware cursor including
  its colour stacks (CR4A/CR4B in "X11" mode, CR55 bit 4) and CR4E/CR4F
  offsets; palette loads every frame or on colormap install, maybe through
  the vertical interrupt.
- Detection: probably the PCI ID and CR30 (0xC0/0xC1 for the 864), CR36
  for memory size, maybe DAC identification.
- Endianness: at 8 bpp none. At 16/32 bpp the BE CPU's stores put pixel
  bytes in the wrong order; the 864 has no aperture byte-swap (868/968
  do, CR53), so AIX either stays at 8 bpp or swaps in software (open).

Windows NT 3.51/4.0 for PowerPC (little-endian; the MPC105 swaps lanes):

- The HAL's boot display for PReP (the PPC HAL's S3 display support,
  file names like `pxs3.c` in the NT HAL sources: unverified) sets a
  640x480 8-bpp mode from register tables and draws its 8x16 font in
  software into the LFB; no VGA text mode is expected.
- The S3 miniport/display driver: detection through CR30 and CR2D/2E
  (absent on 864: reads 0 or FF), CR36, SDAC detection and PLL
  programming (it may read the PLL back through 3C7 with RS2, which this
  firmware never does), the full engine (fills, BitBLTs both directions,
  mono and colour expansion, lines, pattern fills through 8x8 BitBLT
  patterns, colour compare), the hardware pointer with colour stacks,
  maybe the "old" memory-mapped engine registers at A0000-AFFFF (CR53 bit
  4: PIX_TRANS at A0000-A7FFF, the 8xE8 registers at A8000+) where the
  driver enables them, 15/16/24 bpp modes (SDAC commands 2x-7x, CR67).
- Little-endian 16/32 bpp pixels are natural.

Others (Solaris 2.5.1 PPC, which requires the on-board S3; OS/2 PPC;
NetBSD/Linux PReP with XFree86's S3 server): similar subsets. If any of
them uses VGA text mode or the A0000 planar window, phase 2 needs the VGA
core proper.

---

## 3. Reference models

### MAME (`/home/dani/repos/mame/src/devices/`)

`bus/pci/vision.cpp` (S3 Vision864/964/868/968 PCI cards):

- IDs: 864 as 5333:88C1, class 000100 ("VGA compatible, pre-2.0 class
  code", line 52); command reset 0020, mask 23.
- Legacy I/O 3B0-3DF and A0000-BFFFF installed only while the command
  register's I/O / memory bits are set (`map_extra`, line 120).
- **No LFB BAR on the 864** (`add_map` commented out, line 84); the 968
  has a 64 MB BAR with the LFB and new MMIO.
- A Phoenix x86 BIOS ROM (not usable here).

`video/pc_vga_s3.cpp` (the 864's registers on top of the VGA core):

- CR2D/2E/2F IDs (0 on the 864), CR30 = C1 (line 72), CR31 memory
  configuration (start address bits, enhanced mapping), CR35 bank with
  the CR38 = 48 lock, CR36/CR37 strapping writable when CR39 = A5 (the
  firmware does unlock both), CR40 bit 0 (8514 registers on), CR42, CR43,
  CR45-CR4F cursor (colour stacks with the pointer reset on CR45 read),
  CR51 (offset bits 9:8 in 5:4), CR53 (MMIO), CR55, CR5C-CR5E, CR67
  (pixel format), CR68/CR69/CR6A.
- SR10-SR15 as Trio-style MCLK/DCLK PLL (the 864 has none: on this board
  the clock is in the SDAC). **No SDAC model**: no RS2/RS3, no command
  register, no PLL at 3C8/3C9.
- `mem_r/mem_w`: A0000 window in chain-4 and planar, CR53 MMIO aliasing
  of PIX_TRANS and the engine registers (lines 756-1000).
- The hardware cursor drawing (line 1032): the AND/XOR bit layout (bytes
  0-1 AND, 2-3 XOR per 16 pixels, MSB first), Windows vs X11 mode
  (CR55 bit 4) and the colour stacks at 8/16/24 bpp. This is the best
  reference for the cursor.
- No vertical interrupt beyond the VGA core's.

`video/ibm8514a.cpp` (the drawing engine shared with the 8514 and ATI):

- CMD decode: NOP/SSV, line (2000), rectangle (4000), BitBLT (C000),
  pattern fill (E000); bus size (CMD bits 10:9) and BYTSEQ (bit 12: MAME
  swaps bytes when set, for mono data only); PIX_CNTL mix selection (FG
  always / pattern / CPU data / display memory); the 16 mixes; scissors;
  GP_STAT (busy, data available; FIFO bits always 0); SUBSYS_CNTL/STAT
  (42E8; vblank status faked from the VGA's vblank).
- Pitch: the CRTC offset (`IBM8514_LINE_LENGTH` = the VGA offset), not
  CR50 (the same 640 for the firmware's mode).
- Colour from CPU data takes byte (x - start) & 3 of PIX_TRANS low first
  and ignores BYTSEQ for colour data; colour compare and write mask are
  incomplete. Useful for the command semantics, not as an exact model.

`video/pc_vga.cpp` (the VGA core): sequencer, CRTC, graphics controller,
attribute controller, DAC, planar memory with latches and write modes,
text mode, the CR11 vertical interrupt (`irq_latch` set at vblank when
not disabled, cleared by CR11 bit 4 = 0; status in 3C2 bit 7; lines 870,
1841).

### QEMU (`/home/dani/repos/qemu/hw/display/`)

No S3. Useful for the VGA core:

- `vga.c`, `vga_regs.h`, `vga_int.h`: every standard VGA register,
  planar write modes 0-3 and read modes, latches, chain-4 and odd/even,
  the text renderer (font in plane 2, attributes, blink, cursor), the line
  offset/start address/line compare computation, and two models of 3DA
  retrace (`vga_dumb_retrace` toggles; `vga_precise_retrace` computes it
  from the CRTC timing, line 286).
- `vga-pci.c`: a PCI VGA with an LFB BAR and the Bochs VBE extension
  (irrelevant registers, but a clean LFB/legacy split).
- `cirrus_vga.c`: a Cirrus GD5446 with a 2D blitter (ROPs, colour
  expansion from the CPU through a window, transparency, pattern fills,
  hardware cursor): the closest architectural cousin of the S3 engine in
  QEMU, good for edge cases of CPU-to-screen expansion and ROP tables.

---

## 4. A proposed RTL design

### 4.1 Where it sits

```
CPU port --> IBMRS6K7248_machine
               | S3 I/O (VGA 3B0-3DF, 46E8, 4AE8, 42E8, 8xE8-BEE8, E2E8/EA, 0102)
               | S3 memory (LFB at CR59/5A, later A0000-BFFFF)
               | PCI config (CF8/CFC, device 14)
               v
             IBMRS6K7248_s3          registers: PCI header, VGA, S3 CRs, SDAC, cursor
               |   \
               |    IBMRS6K7248_s3ge   the graphics engine (FIFO, PIX_TRANS, mixes)
               |         |
               v         v
             VRAM port (CPU LFB + engine), write-combined (MacPPC7300_vramwc)
               |
               v   clock crossing (DSPPC604_memcdc, as MacPPC7300's VRAM path)
             IBMRS6K7248_s3video     in the video/memory clock: DDR3 arbiter,
                                     scan-out, CRTC timing, palette, cursor,
                                     dot clock -> CLK_VIDEO / CE_PIXEL / VGA_*
```

Files in this repository's style: `rtl/machine/IBMRS6K7248_s3.sv`
(registers, decode, interrupt; the configuration header like
`IBMRS6K7248_firecoral.sv`), `IBMRS6K7248_s3ge.sv` (engine),
`IBMRS6K7248_s3video.sv` (derived from `MacPPC7300_video.sv`: its DDR3
front end, line buffers, dot-clock accumulator and output stages kept,
Swatch replaced by a VGA/S3 CRTC), reusing `MacPPC7300_vramwc.sv` and the
`DSPPC604_memcdc` crossing.

### 4.2 Bus interface: changes needed in the machine

The machine's device path today answers every access the cycle after and
hands byte-wide devices the byte at the first enabled lane. The S3 needs
more:

1. **Whole words with byte enables.** `out16le(3C4, ...)` is one 16-bit
   cycle carrying an index and its data; `out16le(xxE8)` is one engine
   register; `out32(E2E8)` (16/32 bpp pictures) is two 16-bit transfers.
   The S3 takes `addr[15:2]`, `be[3:0]` (be[3] the lowest address),
   `wdata[31:0]` (byte at address A in bits 31-8(A&3)) and handles the
   enabled bytes in address order: VGA ports as consecutive byte writes
   (3C4 then 3C5, 3D4 then 3D5, 3CE then 3CF, 3C0 then 3C1 (the flip-flop
   advances once per byte)); an engine register pair xxE8/xxE9 as one
   16-bit write (a byte-only write updates its half; a command or
   multifunction write takes effect with its high byte, as MAME does for
   9AE9/BEE9); E2E8-E2EB as
   PIX_TRANS data of the width CMD sets.
2. **Wait states.** `s3_putchar` streams PIX_TRANS writes without polling
   the FIFO (0x5D660), as real hardware relies on the bus being held
   while the FIFO is full. The S3's I/O port needs `ack` (or `busy`), and
   the machine's `dev_ack` for S3 hits must wait for it. Simplest: an S3
   hit in the device state machine waits for `s3_ack` instead of
   `d_sel_q`.
3. **Memory.** C000_0000-FEFF_FFFF currently reads FF. The S3 exports
   `lfb_on` (PCI command bit 1 & CR58 bit 4), `lfb_base` (CR59, CR5A) and
   the window size (CR58[1:0], 64 KB-4 MB); the machine sends hits
   (CPU address - C000_0000 inside the window) to the VRAM port, word or
   line, with variable latency (the CPU port's req/ack protocol). Phase 2
   adds A0000-BFFFF (CPU C00A_0000) per GR6[3:2].
4. **PCI configuration**: device 14 in the machine's CF8/CFC decode, as
   device 11 is.
5. **IRQ 15**: `irq[15]` (OR with other PCI devices later); the 8259's
   ELCR already makes 15 level.

### 4.3 Byte order

The MPC105 in big-endian mode keeps bytes at their addresses: the CPU's
byte at address A is the PCI byte at A (lanes by address). So:

- VRAM is byte-addressed exactly as the S3 sees it: the CPU's word at LFB
  offset A puts bits 31:24 at VRAM A, 23:16 at A + 1 and so on. That is
  MacPPC7300's "VRAM's order": byte a in DDR3 word a >> 3, lane a & 7;
  its `c_word64`/`line_beat` conversions apply unchanged.
- Engine registers are little-endian 16-bit: xxE8 is bits 7:0, xxE9 bits
  15:8. The firmware writes them with `out16le`, so a register value v
  arrives as wdata = {v[7:0], v[15:8]} on lanes 0/1.
- PIX_TRANS order: with a 16-bit bus and **BYTSEQ = 0, the byte at E2E9
  (high byte) is the first pixel**; with BYTSEQ = 1 the byte at E2E8. The
  firmware's `s3_putbitmap` relies on BYTSEQ = 0 with big-endian `sth`
  (section 1.9). For mono expansion with the 8-bit bus only E2E8's byte is
  used, MSB the first pixel.
- 16/32-bpp pixels are little-endian in VRAM (S3 convention). Big-endian
  software must swap; that is software's business (the 864 has no
  aperture swap).
- In little-endian mode (NT) the machine's existing lane swap applies to
  the S3's I/O and memory like everything else; the S3 sees the PC byte
  order.

### 4.4 Registers (`IBMRS6K7248_s3`)

Phase 1, all stored and read back unless noted:

- **PCI header** (device 14): 00 = 88C0_5333 (or 88C1); 04 command bits 0
  (I/O), 1 (memory), 5 (palette snoop, stored), status 0200 (medium
  DEVSEL); 08 = revision 00, class 03_0000 (or MAME's 00_0100: what the
  real chip reports is an open question; the firmware does not look); 10
  BAR0: see section 5; 3C interrupt line stored, 3D pin = 01 (INTA# of
  the chip; the board wires it to INTD#).
- **VGA**: misc (3C2 w, 3CC r; bit 0 selects 3Bx/3Dx), 3C3 bit 0, SR0-SR4,
  SR8 (unlock), SR9, SR0D, SR10-SR18 (stored, no effect: the 864 has no
  PLL), GR0-GR8 (stored; phase 1 needs only GR5/GR6 as values), AR00-AR14
  with the index/data flip-flop and PAS (bit 5), 3DA (bit 3 vertical
  retrace, bit 0 display disabled; read resets the flip-flop), 3C2 read
  (input status 0: bit 7 = the vertical interrupt pending), CR00-CR18
  with the CR11 bit 7 protect of CR00-CR07, the CRTC index readable at
  3D4.
- **S3 CRs** CR2D-CR6F: CR30 = C0 (read only), CR36 reset 8E, CR37 reset
  0F (the board's straps: 2 MB; check against a real board), CR38/CR39
  locks (stored; enforce the CR35/CR36/CR40-CR4F locks only if a driver
  needs it), the rest stored. Used by phase-1 hardware: CR31, CR32 bit 4,
  CR3A, CR40 bit 0 (engine ports on), CR42[2:0] + bit 5, CR43 bit 2, CR45
  bit 0, CR46-CR49, CR4A/CR4B (stacks, phase 2), CR4C-CR4F, CR50, CR51,
  CR55 bits 0 (RS2), 2 (monitor ID at 3C8), 4 (cursor mode), CR58 bit 4 +
  [1:0], CR59/CR5A, CR5D/CR5E overflows, CR66 bit 0, CR67 (phase 2).
- **DAC/SDAC**: pixel mask 3C6, write index 3C8, read index 3C7, data 3C9
  (three 6-bit components, the palette in an M10K, 256 x 18, read port to
  the scan-out), 3C7 read = DAC state. With CR55 bit 0: 3C6 = command
  register, 3C8/3C7 = PLL write/read index, 3C9 = PLL data (M, N pairs;
  index 0E single byte), f0 = 25.175 and f1 = 28.322 MHz at reset.
- **Monitor ID**: with CR55 bit 2, 3C8 reads {4'h?, id[3:0]}; id from a
  status-menu option (default F: class 3, 72 Hz at 640x480; 6: class 0,
  60 Hz).
- **46E8, 4AE8, 0102**: stored (4AE8 bit 0 = enhanced mode, OR-ed with
  CR66 bit 0).
- **The vertical interrupt**: `pending` is set at the start of vertical
  sync while CR11 bit 4 = 1; held clear while CR11 bit 4 = 0; cleared by
  a 42E8 write with bit 0 set. `irq = pending & ~CR11[5] & CR32[4]` (and
  PCI command bit 10, interrupt disable, if modelled). Readable in 42E8
  bit 0 and 3C2 bit 7.

The register values the scan-out needs (timing, pitch, start, depth,
cursor, palette) cross to the video clock as quasi-static signals, as
MacPPC7300's video registers do (they change between frames, the driver
blanks while it writes them).

### 4.5 VRAM

**In the HPS DDR3**, as MacPPC7300 and plan.md M4 have it: the DDRAM
port is unused in this core, the SDRAM carries the CPU's RAM and ROM (a
second master there would cost the CPU), and 2 MB does not fit in M10K
(553 x 1.25 KB). Region: DDR3 byte 0x3000_0000 (`DDR_BASE` 29'h0600_0000
in 64-bit words), 4 MB reserved (2 MB used; the rest for a 4 MB option).

Three clients on one DDR3 port, an arbiter like `MacPPC7300_ddrarb`
(scan-out first, then CPU and engine alternately):

- **scan-out**: per line, the line's bytes (and the cursor's 16 bytes
  when the cursor is on that line) in bursts of up to 32 words into
  one of two line buffers;
- **CPU** (LFB, later A0000): words and lines through `vramwc` (stores
  gathered into 32-byte lines with byte masks; a load drains it). The
  firmware's LFB traffic is small (1 KB cursor image, the 32-byte sizing
  test, `getbitmap`), but AIX/NT software rendering needs the combiner;
- **engine**: reads and writes of 64-bit words with byte enables.

Accesses at or above 2 MB: writes dropped, reads FFFF_FFFF (no aliasing:
section 1.8).

### 4.6 Scan-out and timing (`IBMRS6K7248_s3video`)

- **Dot clock**: CE_PIXEL by phase accumulation of the video clock
  (MacPPC7300_video's `numer/denom` accumulator), at f_sel =
  SDAC f[CR42[2:0]] when misc[3:2] = 11, else f0/f1 per misc[3:2];
  f = 14.31818 MHz x (M + 2) / ((N1 + 2) << N2). CLK_VIDEO = clk_mem (100
  MHz). Phase 1 needs 25.2-31.5 MHz (and 65/80 MHz for 1024x768).
  Clocks above 100 MHz (1280x1024 at 110-130 MHz, phase 2): either clamp
  to one pixel a clock (the frame rate drops; the MiSTer scaler does not
  care, analog VGA out would be off-standard) or add a faster video clock.
- **CRTC** in character clocks of 8 dots (SR1 bit 0 = 1): horizontal total
  (CR00 + 5) x 8 with CR5D bit 0 as bit 8, display end CR01 (+ CR5D bit
  1), blank start/end CR02/CR03 (+ CR5D bits 2, 3), sync start CR04 (+
  CR5D bit 4), sync end CR05[4:0]; vertical total CR06 + CR07 bits 0, 5 +
  CR5E bit 0, display end CR12 + CR07 bits 1, 6 + CR5E bit 1, blank
  start CR15 + CR07 bit 3 + CR09 bit 5 + CR5E bit 2, blank end CR16,
  retrace start CR10 + CR07 bits 2, 7 + CR5E bit 4, retrace end
  CR11[3:0]; sync polarities misc bits 6, 7 (the framework wants them
  active high: convert). Interlace (CR42 bit 5) and line compare (CR18,
  CR07 bit 4, CR09 bit 6, CR5E bit 6) in phase 2.
- **Pixels**: packed 8 bpp when CR31 bit 3 or CR3A bit 4 or CR66/4AE8
  bit 0 says enhanced (phase 1 can take "enhanced" as given). Line y
  starts at start + y x pitch, start = {CR51[1:0], CR31[5:4], CR0C,
  CR0D} x 4 bytes, pitch = {CR51[5:4] or CR43[2], CR13} x 8 bytes. Then
  pixel mask (3C6), palette (6-bit, widened {c, c[5:4]}), blanking (SR1
  bit 5 screen off, AR PAS = 0, SR0D sync control optional): black.
- **Cursor** (CR45 bit 0): 64 x 64 at (CR46-CR47, CR48-CR49) with CR4E/CR4F
  offsets, image at {CR4C, CR4D} x 1 KB, 16 bytes a line fetched with the
  line; AND/XOR as in section 1.10 (MAME's layout); Windows mode (CR55
  bit 4 = 0): 00 background stack colour, 01 foreground, 10 screen, 11
  inverted screen (the firmware uses only 10/11); the stacks CR4A/CR4B in
  phase 2. Inverting a pixel: the index XOR FF before the palette (what
  the S3 does in 8 bpp: verify) or the RGB inverted.
- **Status to the register side**: vertical retrace (3DA bit 3), display
  enable (3DA bit 0), the start of vertical sync (for the interrupt), as
  toggles crossing back like MacPPC7300's `vbl_start_tog`.

### 4.7 The graphics engine (`IBMRS6K7248_s3ge`)

Registers (16-bit, little-endian pairs): CUR_Y 82E8, CUR_X 86E8, DESTY
8AE8, DESTX 8EE8, ERR_TERM 92E8, MAJ_AXIS 96E8, CMD/GP_STAT 9AE8, SSV 9EE8,
BKGD_COLOR A2E8, FRGD_COLOR A6E8, WRT_MASK AAE8, RD_MASK AEE8, COLOR_CMP
B2E8, BKGD_MIX B6E8, FRGD_MIX BAE8, MULTIFUNC BEE8 (index in 15:12: 0
MIN_AXIS, 1-4 scissors T/L/B/R, A PIX_CNTL, E MULT_MISC, F READ_SEL),
PIX_TRANS E2E8/E2EA, SUBSYS 42E8. Decoded only while PCI I/O is on and
CR40 bit 0 is set (else they read FF; the firmware reads 9AE8 only with
CR40 bit 0 set).

A command FIFO of 8 entries in front (GP_STAT bits 7:0 a thermometer of
used slots, bit 9 busy, bit 10 empty), PIX_TRANS data entering the same
queue; the I/O port holds `ack` while the queue is full.

Phase-1 operations:

- **Rectangle** (CMD 4000) with INC_X/INC_Y (both directions, for the
  bottom-up `putbitmap`), DRAW, WRTDATA; sources per mix: FG colour, BG
  colour, CPU data (PCDATA, bus 8/16/32, BYTSEQ, rows starting on a new
  transfer), and PIX_CNTL[7:6] = 00 (FG always) or 10 (CPU data bits pick
  FG/BG: mono expansion, MSB first).
- **BitBLT** (CMD C000), display-memory source, all four directions
  (choose the copy order from INC_X/INC_Y; the firmware only uses +x, +y).
- **Mixes**: all 16 functions on 8-bit pixels; WRT_MASK; scissors (clip
  per pixel); pitch from CR50 (640/800/1024/1152/1280/1600 by bits 7:6 and
  0; pixel length bits 5:4); colour compare (MULT_MISC bit 8, COLOR_CMP)
  for the firmware's transparent bitmaps once its exact meaning is known.
- **42E8**: bits 15:14 = 10 reset the engine (empty the FIFO, abort), 01
  run; bit 0 written 1 clears the vertical interrupt.

Data path: the engine works on 64-bit DDR3 words. A fill writes whole
words with byte enables (8 pixels a beat); a mono-expansion row is at most
a few words; a BitBLT row is read into a row buffer (one M10K pair, 1600
bytes) and written back shifted to the destination alignment; mixes that
read the destination (anything but 1, 2, 4, 7 with a full write mask) need
the destination row too. At 8 bpp the firmware's operations then take a
few DDR3 transactions a row: a full-screen scroll is about 600 KB of DDR3
traffic, a few milliseconds.

### 4.8 Phase 1: the minimum for the firmware

1. PCI header (device 14), command bits gating I/O and memory.
2. VGA/S3/SDAC registers as section 4.4, 16-bit I/O cycles split, wait
   states for the engine ports, the monitor ID.
3. LFB at CR59/CR5A with CR58's enable and window, no aliasing above 2 MB.
4. VRAM in DDR3 with the three-client arbiter and `vramwc`.
5. CRTC + scan-out: packed 8 bpp, 6-bit palette with pixel mask, blanking,
   3DA bits, the S3 hardware cursor (AND/XOR, invert), CLK_VIDEO/CE_PIXEL
   from the SDAC PLL (up to 100 MHz).
6. The vertical interrupt to IRQ 15 (CR11/CR32/42E8).
7. The engine: rectangle fill, BitBLT (four directions), mono expansion and
   colour image transfer through PIX_TRANS (8/16-bit bus, BYTSEQ),
   16 mixes, scissors, write mask, colour compare, GP_STAT, 42E8 reset.

That runs the driver's whole path: the mode set, the palette, the clear,
text, scrolling, the cursor, the `bmp oem.bmp` picture, `mode 1` (1024 x
768) as well.

Bench checks (`sim/`): no progress code 69 at port 680 (engine status
right); `s3_memory_size` returns 2 (state+3804; CR36 = 8E after the mode
set); the IRQ 15 handler runs and the cursor registers CR46-CR49 change;
a VRAM dump (PPM through the palette) of the firmware's screen after the
logo and the menu.

### 4.9 Phase 2: AIX and NT

- Line drawing (CMD 2000, Bresenham with ERR_TERM, axial/diagonal
  steps), short-stroke vectors (9EE8), pattern fill (E000), image reads
  through PIX_TRANS (CPU reads of E2E8, GP_STAT bit 8), READ_SEL (BEE8 F)
  read-back of the engine registers.
- 16/24/32 bpp scan-out (SDAC command 2x-7x, CR67), the 2:1 pixel mux
  (SDAC 10/CR67 10) and dot clocks above 100 MHz, interlace, line compare,
  the cursor colour stacks and X11 mode, 16/32-bit engine pixels (mixes
  and masks 16/32 bits wide, CR50 pixel length).
- CR53 bit 4 old MMIO (PIX_TRANS at A0000-A7FFF, engine registers at
  A8000-AFFFF) if a driver uses it.
- The VGA core proper if any OS needs it: A0000-BFFFF in planar and
  odd/even modes with latches, write/read modes, set/reset, rotate, bit
  mask; text mode (font in plane 2, attributes, blink, text cursor); 16
  colours through the attribute palette. QEMU's `vga.c` is the reference.
- SDAC PLL read-back (3C7 with RS2) and anything a driver's detection
  reads (CR30, CR2D-2F, CR37 strap bits, the DAC's command register).
- BAR0 if AIX or NT's PCI code programs it (section 5).

### 4.10 Size, roughly

| part | ALMs | M10K |
|---|---|---|
| registers, decode, PCI header, interrupt (≈1,200 flops) | 1,000-1,500 | 0 |
| palette 256 x 18, two ports | small | 1-2 |
| CRTC timing, dot-clock accumulator | 300-500 | 0 |
| scan-out fetch, line buffers (2 x 2 KB at 8 bpp; 2 x 6.4 KB for 32 bpp), cursor | 500-800 | 4 (8 bpp) to 12 |
| DDR3 arbiter, CPU VRAM port, `vramwc` (4 lines), crossing | 1,200-1,600 | 0-2 |
| engine phase 1: registers, FIFO, rect/BitBLT/expansion state machine, 64-bit mix unit, row buffer | 1,800-2,800 | 2-4 |
| **phase 1 total** | **≈5,000-7,000** | **≈8-20** |
| phase 2: lines/SSV/patterns/image read | +800-1,200 | |
| phase 2: 16/24/32 bpp, pixel mux, cursor colours | +400-700 | +4-8 |
| phase 2: VGA planar + text core | +1,500-2,500 | +1 (font cache optional) |

For scale: MacPPC7300 with the same CPU fits at about 37,000 ALMs (88-89 %
of the 41,910); this core has fewer devices so far, but the budget is to
be watched (a fit before phase 2).

---

## 5. Open questions

1. **BAR0 of the 864.** Does the real 864 have a memory BAR that mirrors
   CR59/CR5A (8 MB? 64 MB?), or none (MAME has none)? The firmware never
   writes one; AIX/NT might. Until known: no BAR (reads 0), the LFB from
   CR59/CR5A only.
2. **The class code and revision** the 864 reports at PCI 08 (MAME:
   000100; a PCI 2.0 part would say 030000), and whether AIX's
   configuration cares.
3. **CR55 bit 2 and the monitor ID**: is 3C8's general-input read the
   right mechanism on the 864 (inferred from the firmware), and which ID
   does IBM's monitor of the 7248 return? Default proposed: F (class 3).
4. **SDAC clock select**: CS pins from CR42[2:0] vs the PLL control
   register (0E = 22). The firmware makes both readings equivalent; NT/AIX
   may not. Needs the 86C716 data sheet (also: its command-register bits
   for 15/16/24-bit modes and the 6/8-bit DAC switch).
5. **MULT_MISC bit 8 / colour compare** semantics on the 864 (destination
   vs source compare, the sense of bit 7), used by the firmware's
   transparent bitmaps (`s3_putbitmap` 0x5DB64).
6. **The cursor's invert in 8 bpp**: index XOR FF before the palette or
   RGB inverted after it.
7. **Engine behaviour with an empty/locked CR40**: what the 864 returns
   for 9AE8 with CR40 bit 0 = 0; the firmware never tries.
8. **The vertical interrupt source**: is 42E8 bit 0 on the 864 set by the
   VGA CR11 mechanism (as the firmware's handler assumes), and does 42E8
   bit 8 (8514's vblank enable) matter? The handler writes 42E8 = 0001,
   which clears bit 8, so it cannot be required.
9. **Dot clocks above 100 MHz** (1280x1024 at 60-75 Hz): clamp or a
   separate video clock. Only relevant past phase 1.
10. **AIX's and NT's actual use** (section 2 is general knowledge): which
    modes, whether 16/32 bpp with big-endian pixel order, whether the
    old MMIO window, VGA text mode or the A0000 window are used. To be
    answered by tracing them on the bench once phase 1 runs.
11. **VRAM size strap**: 2 MB (CR36 = 8E written by the firmware anyway);
    should a 4 MB option exist for NT's 4 MB-only modes? The real board
    has 2 MB.
12. **CR37 strap value** (the firmware writes 0F) and **CR68** (AC):
    harmless to store; what they read before the driver runs is unknown.
