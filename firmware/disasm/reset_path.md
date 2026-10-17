# 7248 v1.12 ROM reset path, annotated

Image: `firmware/images/7248_v1.12_P93H7075_fff00000_512k.bin`, mapped at 0xFFF00000.
The code is big-endian.
Full listings:
* `v1.12_rom_fff00000_fff18000.annotated.s` covers the ROM, both blocks up to the start of the LZW stream.
* `v1.12_ram_image_00000000.annotated.s` covers the decompressed firmware as linked at RAM 0.

The machine-generated access traces are:
* `io_trace_recovery_block.txt` and `io_trace_main_stub.txt`: every load or store whose address is a constant, with the value as seen on the little-endian bus.
* `io_helper_calls_ram.txt`: calls to `in8/out8/...` with constant arguments.

Notes on conventions:

* I/O ports are written as the ISA port. The CPU address is `0x80000000 + port`.
* For 32-bit PCI config cycles, the firmware stores **pre-byte-swapped** constants with a plain big-endian `stw`. For example, `stw 0x00580080 -> 0x80000CF8` puts bytes `00 58 00 80` on the bus, which the little-endian PCI side reads as **0x80005800**. The tables below give the little-endian value.
* Hand-written assembly (the reset path) builds every address with `li rX,lo ; oris rX,rX,hi`, or with `xor rX,rX,rX ; oris ; ori`, and puts `eieio` before each access.
* The compiled C (xlc) uses `out8(port,val)` / `in8(port)` helpers. These OR in 0x80000000.

## 1. Vectors (block at 0xFFF00000)

| addr | code | meaning |
|---|---|---|
| FFF00000 | ASCII "40H5218 RS/6000 Microcode - Property of IBM ..." | block header (not code) |
| FFF000E8 | `000A1D6F` | header word (not covered by the CRC) |
| FFF00100 | `b 0xFFF04020` | **system reset vector** |
| FFF00104 | `b 0xFFF04024` | |
| FFF00108 | "02261997 142638" | build stamp |
| FFF00200..FFF01700 | `bl 0xFFF05E58`... | exception vectors. They report a checkpoint and halt. They are only meaningful while MSR[IP]=1. |
| FFF00FF0 | `00005DAC` | offset of the block descriptor (see the doc) |
| FFF04000 | `bl 0xFFF05E58` | |

## 2. FFF04020: CPU identification (cache-line replicated code)

Every instruction from 0xFFF04020 to 0xFFF0415F appears **8 times in a row**, filling a whole 32-byte line. Any word that the CPU or bridge returns from that line therefore decodes to the same instruction. This makes the code robust against how the MPC105 assembles 64-bit beats from the 8-bit flash before it is configured.

```
FFF04020  mfpvr r3                 ; x8
FFF04040  srwi  r0,r3,16           ; x8
FFF04060  cmpwi r0,1               ; 601 ?
FFF04080  bne   FFF0421C(+n)       ; not 601 -> 603/604 path
--- 601 path ---
FFF040C0  li r1,0x000F ; oris r1,0x87F0 ; mtsr 15,r1   ; SR15 = 0x87F0000F
FFF04100  li r1,0      ; oris r1,0x87F0 ; mtsr 0,r1    ; SR0  = 0x87F00000
FFF04140  li r1,0x1070 ; mtmsr r1                      ; MSR = ME|IP|IR|DR
FFF041A0  SR1..SR14 = 0x87F00001..0x87F0000E ; isync ; b FFF042A8
```
On the 601, the code uses T=1 segments with BUID 0x07F ("memory-forced I/O"). Each segment maps 1:1 to physical memory, so translation can be enabled without BATs.

```
--- 603/604 path ---
FFF0421C  mfspr r1,HID0 ; andis. r1,r1,0x0001 ; oris r1,r1,0x8000
FFF0422C  mtspr HID0,r1          ; HID0 = EMCP | (old bit15 = NHR soft-reset flag)
                                 ; caches stay off (ICE/DCE = 0)
FFF04234  li r1,0x1040 ; mtmsr r1  ; MSR = ME|IP (translation off)
FFF04244  IBAT0-3U/L = 0, DBAT0-3U/L = 0
FFF04288  SR0..SR15 = 0 (mtsrin loop) ; sync ; isync
```

## 3. FFF042A8: Fire Coral ISA bridge (PCI dev 11) bring-up

This step runs before memory exists, so there is no stack.

| addr | access | LE value | meaning |
|---|---|---|---|
| FFF042C0 | W32 CF8 | 80005800 | bus0 dev11 fn0 reg 0x00 |
| FFF042D0 | R32 CFC | (VID/DID, discarded) | IBM 1014:000A "Fire Coral" |
| FFF042FC/430C | CF8=80005804, W32 CFC | 00000007 | Command = IO+MEM+Bus master |
| FFF04364/4374 | CF8=80005810, W32 CFC | 00001000 | **BAR0 = I/O 0x1000** |
| FFF04390/43A0 | CF8=80005850, R32 CFC | | reg 0x50, read and discarded |

The Fire Coral internal registers are then written through an **index/data pair at I/O 0x1000/0x1004**. The index is a 16-bit write to 0x1000, little-endian (`sth 0x0200` puts index 0x0002 on the bus). The data is an 8-bit write to 0x1004. These are the same registers that `coral_pci_config_read/write` and `setup_coral_ide` (index 0x25) use later.

| index | value | index | value | index | value |
|---|---|---|---|---|---|
| 0x02 | 0x0B (x2) | 0x0A | 0xFA | 0x0B | 0x74 |
| 0x0C | 0x00 | 0x0D | 0x08 | 0x0E | 0x7F |
| 0x0F | 0x00 | 0x03 | 0x6E, then a **decrementer wait of 750,000 ticks** (DEC=0x000B71B0, about 45 ms at a 16.7 MHz timebase), then 0x77 | 0x06 | 0x7F |
| 0x07 | 0x56 | 0x08 | 0xC0 | 0x09 | 0x40 |
| 0x0A..0x0F | rewritten with the same values | 0x24 | 0x73 | 0x25 | 0x00 |
| 0x26 | 0xFE | 0x41..0x47 | 0x10..0x16 | 0x32 | 0x05 |
| 0x33 | 0x04 | 0x3E | 0x02 | 0x3F | 0x04 |
| 0x2A | 0x14 | 0x3C | 0x00 | 0x3D | 0x06 |
| 0x31 | 0x10 | 0x30 | 0x00 | | |

The main block's copy of this code (FFF14xxx) skips the first group (indices 0x02..0x03, with the delay).

## 4. FFF04B10: legacy ISA/DMA/PIT defaults

```
0x000D <- 00    DMA1 master clear          0x00DA <- 00   DMA2 master clear
0x0008 <- 00    DMA1 command               0x00D0 <- 00   DMA2 command
0x00D6 <- C0    DMA2 mode: ch4 cascade
0x0410..0x0417 <- 42   82378-compatible DMA scatter/gather command regs (ch0-7)
checkpoint 0x04  (0x08C1<-8F, 0x08C0<-04, 0x03BC<-04, out32le 0x0680<-00010004)
0x0043 <- 74 ; 0x0041 <- 12 ; 0x0041 <- 00   PIT ctr1 = 18 (DRAM refresh, ~15 us)
0x081C <- 00    system/L2 control register cleared
checkpoint 0x04 (0x0680 <- 00000004)
b FFF06B58
```

## 5. FFF06B58: the recovery block "step" sequence

`FFF06B30 step(n)`: writes n to the parallel-port data latch **0x3BC** and does `stwbrx 0x0001_00nn -> 0x80000680`. Steps 8..24 follow:

| step | action |
|---|---|
| 8 | `base = where_am_i()` (FFF06A40). If `(base+0x80000) & 0xFFF00000 == 0xFFF00000`, the code is running from ROM, so call **memory init FFF05A68**. Otherwise it was soft-loaded, so restore r27 from RAM 0xF8. |
| (any) | FFF04D54: early stack r1 = 0x0BC0 |
| 9 | FFF0D9A4 `audio_mute`, FFF07504 `transfer_chk_code` |
| 10 | FFF06F48 |
| 12..14 | **`chk_image_CRC(base, 1)`**: CRC-16 of the next block (main block at 0xFFF10000) |
| 15/16 | FFF06E54: HID0 &= ~(ICE\|DCE), MSR \|= ME\|IP (601: SRs + MSR=0x1070) |
| 17 | **CRC good:** `get_comp_img_entry()` returns 0xFFF10000+0x100, then `mtlr; blr`, which **jumps to the main block's reset vector 0xFFF10100**. |
| 18..24 | **CRC bad, so recovery mode.** If the block is running from ROM (base+0x80000 >= 0x300000), FFF050F4 (memory) runs. Then FFF04D10 sets SPRG1=0x001AFFF0, SDR1=0x00180000, r1=0x0017FFC0. `transfer_uncompressed_image` copies this 64 KiB block to **RAM 0x00000000** and jumps into the copy (`FFF06A6C` adds -ROMbase to LR). Then `transfer_compressed_image`, cache flush (FFF06CF8, 06DD0), r2 = TOC 0xEFD0, and `b FFF0B82C recovery_control`. That routine reads `PRECOVER.IMG`/`P*.IMG` from diskette (an FDC driver is in the block) and reflashes. |

## 6. FFF05A68: MPC105 (dev 0) memory-controller init (runs from ROM, no RAM)

All accesses use CF8/CFC with bus 0 dev 0. Values are the little-endian register values.

| addr | reg | value | meaning (MPC105 register map) |
|---|---|---|---|
| FFF05C0C | 0x04 | FFFF0006 | PCI command = MEM+master; clear all status bits |
| FFF05C40 | 0xA8 | 9F071208 | PICR1 (processor interface config 1) |
| FFF05C70 | 0xC4 | 00000000 | error enable 2 / error detect 2 cleared |
| FFF05CA4 | 0xF0 | FFC30000 | MCCR1 (ROM timing, bank config), MEMGO=0 |
| FFF05CD8 | 0xF4 | 00000FA2 | MCCR2 (refresh interval) |
| FFF05D0C | 0xF8 | 0002B2DC | MCCR3 (DRAM timing) |
| FFF05D3C | 0xFC | 00000000 | MCCR4 |
| FFF05D70 | 0xF0 | FFCB0000 | MCCR1 with **MEMGO** (bit 19) set |

After that, the code probes the banks with patterns at RAM 0x0 and 0x7FC: 0x08AA_AA55, 0x5501_AA55, 0x5508_02AA, all-ones, and zero. It reads MPC105 reg 0xC0 bit 0x00040000 (FFF0544C) to detect errors.

FFF05490/055B4/057A4 program:
* bank start/end: regs 0x80 (start), 0x84 (ext start), 0x90 (end), 0x94 (ext end)
* the bank-enable register 0xA0
* MCCR1 row/column geometry, from a table at **FFF05BA4** keyed by the SIMM presence-detect byte (0x88, 0x8C, 0xC8, 0xCC, 0xBB, ... 0xDD).

FFF05554/059FC write MCCR3 = 0x0002B2DC / 0x0002B2DB.

Later code (FFF06134..FFF06520), with checkpoints 0xBA, 0xBB, 0xBC:
* reads **0x080C, 0x080D, 0x081C, 0x0814** (L2 presence/size and control)
* writes PICR2 (reg 0xAC) = C29B438B
* steps PICR1 through 9F071E08, 9F071E09, 9F071E0A, 9F011E08 (L2 enable/size bits)
* sets reg 0xB0 = 00005B00
* toggles 0x081C bits 0x80/0x10 to invalidate the L2.

Also:
* FFF06808 reads the **planar ID at 0x0852**.
* FFF04E4C looks the planar ID up in the table at FFF04EE4 (IDs 0xF0..0xF7) to get CPU/bus/PCI clocks and option flags.
* FFF0579C writes 0x0808 <- 01.

## 7. Main block (0xFFF10000)

Its reset vector at 0xFFF10100 branches to 0xFFF14020. The main block repeats steps 2-6 with its own copy of the code, using checkpoint codes 0x33, 0x04, 0x19..0x1F, 0xDD, 0x24, 0x22, 0x23, 0xBA..0xBC. Then:

| step | action |
|---|---|
| 0x19 | memory init (FFF15490) if running from ROM |
| 0x1A | `transfer_uncompressed_image` copies the 0x7C28-byte stub to **RAM 0** and continues execution there |
| 0x1B/0x1C | cache and MMU setup |
| 0x1D | `transfer_compressed_image`, which uses `decompress()` (LZW). It unpacks ROM 0xFFF17C28..0xFFF7A02E to **RAM 0x7C28..0x105EAC**. |
| 0x1E | r2 = TOC 0x105980; caches on |
| 0x1F | `b 0x8398`, which is **`main_control`**, the C entry point of the firmware |

The RAM copy of the stub also installs a DSI handler (RAM 0x51F0). On a data-storage fault, it loads **DBAT3** with the 256 MiB segment of the faulting DAR and does `rfi`. With MSR[DR]=1, the firmware therefore reaches I/O and PCI space through one BAT that it remaps on demand, so a simulator needs working BAT translation and the DSI exception.
