# IBM RS/6000 43P 7248 ("Carolina") – Hardware Inventory

Target: a MiSTer FPGA core for the IBM RS/6000 43P type 7248 (PReP / "RSPC"), with a PowerPC 604-class CPU at 100 MHz.
This inventory was built from the local material in `scratch/IBMPowerPC/` only. Facts that come from general background knowledge rather than these documents are labelled **[background]**. Inferences are labelled **[inferred]**. Anything else uncertain is marked **(?)**.

---

## 0. Sources and how they are cited

| Tag | File | What it actually is |
|---|---|---|
| **[RB p.N]** | `Pages/ibm_ppc_thinkpad_redbook.pdf` | IBM Redbook **SG24-4592-00**, *The IBM Personal Computer and ThinkPad Power Series* (Jan 1996). **This is the main technical source.** It describes the Power Series 830/850 Carolina planar, which the 7248 shares. `p.N` is the **PDF** page; the printed book page is PDF − 22. |
| **[N7248]** | `Pages/IBM RS_6000 7248 specific notes.html` | Collector notes on a real 7248 (M. Kraemer, 2012): RAM, PSU, SMS, OS installs, firmware floppies. |
| **[MCBX]** | `Pages/IBM Power Series 850 - PC - MCbx.html` (+ `_files/010_AMMO.jpg`) | Collector page about a Power Series 850: boot sequence, firmware files, upgrades. |
| **[CAR]** | `Pages/The Carolina Mystery _ OS_2 Museum.html` (+ photos `PA209429`, `PA209468`) | OS/2 Museum: the shared Carolina planar, CPU and L2 per model, chip photos. |
| **[OS2]** | `Pages/OS_2 Warp, PowerPC Edition _ OS_2 Museum.html` | OS/2 PPC article: Power Series hardware summary. |
| **[GXT]** | `Pages/VGA Legacy MKIII - IBM POWER GXT150P.html`, `VideoCard Images/258_gxt150p_{top,bottom}_hq.jpg` | GXT150P card data and photos. |
| **[SH p.N]** | `Pages/RS6000_Systems_Handbook.pdf` | SG24-5120-01, *RS/6000 Systems Handbook 2000 Edition*. It has **no** 7248 chapter, only a few mentions. |
| **[GH p.N]** | `Pages/RS6000_Graphics_Handbook.pdf` | *RS/6000 Graphics Handbook*. |
| **[DIAG p.N]** | `Pages/Diagnostic_Information_for_Multiple_Bus_Systems.pdf` | SA38-0509-14 (2002). This is generic RSPC/CHRP diagnostics material. The only 7248-specific entry is the CSU table. |
| **[SG7043 p.N] / [UG7043 p.N] / [SI7043]** | `380512.pdf` / `380511.pdf` / `380510.pdf` | **7043** 43P Series Service Guide SA38-0512-03, User's Guide SA38-0511-03, and Setup SA38-0510-02. **These describe the 7043-140/150/240, not the 7248.** |
| **[SUP]** | `329080.pdf` (identical to `Pages/43p Service Manual.pdf`) | SN32-9080-01, a **7043-140/150** fansink and 7043-150 feature supplement. **It does not cover the 7248.** |
| **[FW:file]** | README/listing inside the firmware archives in `scratch/IBMPowerPC/` | Firmware release notes. |

> **Important caveat about the "service manuals".** None of the IBM service PDFs in the folder (329080, 380510, 380511, 380512) cover the 7248. They cover its successor, the 7043 43P (604e, 166–375 MHz, DIMMs, Open-Firmware-style SMS in ROM). The 7248's own User's/Service Guide is **not** in the folder. 7043 material is used below only as clearly-labelled comparison material.

**Unrelated material, one line each:**
- `Pages/firmware/` (NTPROM.RAW, RISCOS.RAW, SETUP.EXE, README.1ST): EEPROM images (NT ARC or RISC/os) for a MIPS ARCS machine.
- `mips4000*.jpg`, `G6XJ*.jpg`, `IMG_9226.jpg`, `s-l1600-*.webp`: photos of a MIPS Magnum 4000PC-50 ARCS system and its video boards. There are no Carolina chips in them.
- `Pages/page1.json`, `page2.json`: Reddit thread dumps about the CEMCORP/Unisys ICON school computer. They contain no PowerPC content.

---

## 1. Machine family and model variants

### 1.1 The Carolina planar family

The **Carolina** planar is shared by the RS/6000 43P **7248** and the IBM Personal Computer Power Series **830 (type 6050)** and **850 (type 6070)**. The only significant difference between them is that the **RS/6000 boards include a SCSI controller** and the Power Series boards do not [CAR] [OS2] [N7248].

- The planar silkscreen reads **"CAROLINA 7.0 MVT"** [CAR photo PA209429].
- The firmware ROM images are distinct for **"Carolina model 6050/6070"** and **"Carolina model 7248/OEM"** [FW:ros104.exe README, FW:sms102.exe README].
- The CPU is soldered. The 100, 120 and 133 MHz boards were **separate part numbers**, and the CPU frequency is not user-changeable [CAR].
- The 7248 has no onboard SMS. SMS runs from a floppy disk [N7248].

### 1.2 7248 models

The local docs give only the model names "7248-100/120/132" [GH p.66] and the 7248 speed range "100 to 133 MHz" [SH p.36]. **The per-model rows below are [inferred]** by mapping onto the Power Series configurations, which use the identical planar.

| Model | CPU | Core MHz | System (60x) bus | PCI | ISA | L2 (std) | Source |
|---|---|---|---|---|---|---|---|
| 7248-100 | PowerPC 604 | 100 | 66 MHz | 33 MHz | 8.33 MHz | 256 KB async | [inferred] from [RB p.37–38, p.93] |
| 7248-120 | PowerPC 604 | 120 | **60 MHz** | **30 MHz** | 7.5 MHz | 256 KB async | [inferred] from [RB p.93] |
| 7248-132 | PowerPC 604 | 133 | 66 MHz | 33 MHz | 8.33 MHz | 512 KB sync | [inferred] from [RB p.38, p.93] |

- The 7248100 firmware archive banner says *"IBM RS/6000 43P Model 120/133 (type 7248)"* [FW:7248100.exe]. Whether a "-100" model actually shipped as a 7248 is **(?)**, although [GH p.66] lists "7248-100/120/132".
- A board sold as 100 MHz was found to carry a **PPC604FD1332PQ** (133 MHz-rated) part [CAR photo PA209468]. The frequency is set by the board, not by the chip marking.
- CPU:bus ratio: 1.5:1 at 100 MHz, 2:1 at 120 MHz and 133 MHz [inferred from RB p.93].
- **FPGA note:** a 100 MHz 604 with a 66 MHz bus and a 33 MHz PCI bus matches the 7248-100 / 6050 / 6070-100 configuration.

### 1.3 Memory (all Carolina models)

| Item | Value | Source |
|---|---|---|
| Sockets | 6 × 72-pin SIMM | [RB p.69, p.98], [N7248] |
| Type | 70 ns **parity** FPM SIMMs, 36 bits each; must be installed in **pairs** (one 72-bit bank = 64 data + 8 parity bits) | [RB p.69, p.98] |
| SIMM sizes | 4, 8, 16, 32 MB. Mixed sizes are allowed if both SIMMs of a pair match. | [RB p.98] |
| Min / max | 8 MB min, **192 MB** max | [RB p.98]; also [MCBX], [OS2]. [N7248] guessed "(64MB?)" — superseded. |
| Interleave / ECC | Non-interleaved; no ECC (parity only) | [RB p.69, p.97] |
| Std. shipped | 16–48 MB depending on model | [RB p.155–160] |
| Option P/Ns (US) | 4 MB 92G7201, 8 MB 92G7520, 16 MB 92G7204, 32 MB 92G7206 | [RB p.179] |
| Presence detect | ISA I/O 0x0880/0x0881/0x0882 = SIMM 1&2 / 3&4 / 5&6 presence registers | [RB p.189–190] |

### 1.4 Related machines

| Type | Name | CPU | Key differences | Source |
|---|---|---|---|---|
| **6050** | Personal Computer Power Series **830** | 604 @100 MHz, 256 KB L2 | 3 slots / 3 bays; IDE (540 MB–1 GB), 4× IDE CD; same planar, no SCSI | [RB p.37, p.45, p.155] |
| **6070** | Personal Computer Power Series **850** | 604 @100/120 (256 KB L2) or 133 MHz (512 KB L2) | 5 slots / 5 bays; IDE up to 3 GB; some models ship with S15 or GXT150P instead of onboard E15 | [RB p.37, p.156–158] |
| 6040 | ThinkPad Power Series 820 | 603e @100 MHz | Notebook. Different board: 256 KB L2, SODIMMs (max 48 MB), WD90C24A2 "G10" video, NCR 53C810 SCSI, Intel SIO 82378ZB, Ricoh RF53C366L PCMCIA, IBM "IDAHO" host bridge | [RB p.41, p.74–78, p.94–95, p.116] |
| **6042** | ThinkPad Power Series 850 | 603e @100 MHz | As 6040, plus a 64-bit memory bus (max 80/96 MB) and motion video | [RB p.43–44, p.45] |
| **7249** | RS/6000-branded ThinkPad 850 (models **851**, **860**) | 603e | Shares microcode with 6042 ("7249/6042 Series of ThinkPad Power Series"); microcode 1.01 notes an "MPC105 REV2.4 errata workaround" **(?)** — this conflicts with RB's "IDAHO" bridge | [FW:7249_6042_firmware.zip/woodfield_prime_microcode.pdf], [SH p.331] |
| Sandalfoot / Sandalbow | Earlier PReP boards (SMS 1.21 builds) | 601/603 **(?)** | Older firmware family; `sms127.exe` is explicitly "Sandalfoot/Sandalbow/OEM" | [FW:sms127.exe READ.ME] |
| 7043-140/150/240 | Successor "43P" | 604e 166–375 MHz | Different planar: DIMMs (ECC), integrated SCSI-2 F/W, operator-panel LED display, Fxx/E1xx checkpoints | [SH p.60–64], [SG7043], [SUP p.7] |

---

## 2. Planar chip inventory

The primary source is the Power Series 830/850 planar description and board drawing (Figure 13) [RB p.64–73, p.68], cross-checked against photos [CAR]. On the 7248, the SCSI controller is additionally populated.

### 2.1 Chip table

| Function | Part | Bus / attachment | Notes | Source |
|---|---|---|---|---|
| **CPU** | IBM PowerPC 604, 304-pin CQFP, soldered (e.g. **PPC604FD1332PQ**) | 60x bus: 32-bit address + 4 parity, 64-bit data + 8 parity | L1 = 16 KB I + 16 KB D, 4-way, 32-byte lines | [RB p.68, p.92], [CAR photo] |
| CPU upgrade socket | 288-pin PGA ZIF socket for the future "604+"; +2.5 V VRM daughter-card header ("CPU Upgrade 2.5V/PLLCFG/OSC") | 60x bus | Socket wired with an upgrade presence-detect signal. Normally empty. | [RB p.67, p.73, p.68 fig] |
| **Host bridge / memory controller / L2 controller** ("PCIB/MC") | **Motorola MPC105 "Eagle"**, marked **XPC105ARX66CD** | 60x ↔ PCI 2.0 32-bit | 66 MHz, BGA, 3.3 V, 0.5 µm. Contains system bus arbitration, memory controller, L2 controller (no tag), PCI bridge. **Not** the IBM 27-82660 ("Lanai/Kauai") that was expected. | [RB p.70, p.92], [CAR photo PA209468] |
| L2 tag RAM | **IDT 71216** (16K × 15: 12 tag + valid/dirty/write-through bits), marked "71216 S10PF" | MPC105 | Supports up to 512 KB copy-back L2 | [RB p.69], [CAR photo] |
| L2 data | 136-position "Cache Data SIMM" socket: 256 KB async SRAM module (32K×64, 15 ns) **or** 512 KB sync module (64K×72, 66 MHz) | MPC105 | Cache jumpers select 256 KB or 512 KB. Option P/N 40H4144 = 512 KB L2. | [RB p.69, p.68 fig, p.180] |
| Memory buffers | Unidentified "Memory Buffers ADDR/DATA/CTRL" logic | DRAM | Generic buffers | [RB p.68 fig] |
| **PCI-ISA bridge** | **IBM "FireCoral"** | PCI ↔ ISA (24-bit address, 8/16-bit data) | PCI arbiter, PCI→ISA translation, PCI config registers, ISA DMA, interrupts, timers. Decodes the X-bus devices (keyboard controller, flash, NVRAM), external RTC, and 2 general-purpose I/O decodes. Runs at 14.318 MHz ISA reference. The DMA table says "Cascade **in SIO**", suggesting an Intel SIO-compatible core **(?)**. The Intel **82378ZB SIO** is used on the ThinkPads, not on Carolina. | [RB p.71, p.92, p.188, p.95] |
| **IDE (EIDE)** | Integrated with, or attached to, the PCI-ISA bridge ("PCI-attached IDE interface") | PCI, 30/33 MHz | 2 channels, 4 devices, ATA modes 0–3, ATA rev 3.2. Bootable. Legacy ports 0x1F0–0x1F7 / 0x3F6–0x3F7. Shares IRQ13 (with PM and scatter/gather); ISA DMA ch 6/7. | [RB p.71, p.116, p.109, p.187–188] |
| **Super I/O** ("Native/Common I/O controller") | **National PC87332** | ISA | FDC (one 3.5" 1.44 MB drive), 2 × FIFO UARTs (can decode 4 COM addresses), 1 IEEE-1284 parallel port, IDE decode support. 24 MHz clock from ICS 9154. A separate box labelled "Native I/O" also appears on the drawing and is unidentified **(?)**. | [RB p.72, p.127, p.68 fig] |
| **Keyboard/mouse controller** | **8042**-type (text also allows an "80CC51SL") | X-bus | 12 MHz clock. Ports 0x60/0x64. | [RB p.71–72, p.68 fig, p.189] |
| **Flash ROM** | **AMD 29F040** (512 KB) soldered, plus an empty socket for a second 512 KB (max 1 MB; architecture allows 16 MB) | X-bus | Holds POST/boot code, VPD (planar speed, serial number), compressed firmware and a "virtual disk". All Carolina images are exactly **524,288 bytes** [FW listings]. | [RB p.70, p.98, p.134, p.68 fig] |
| **RTC / NVRAM** | Labelled "RTC/NVRM"; part number not given (expected Dallas/Benchmarq-type **(?)**); coin-cell "RTC battery" | X-bus | PC-compatible RTC: 64 bytes user NVRAM including 14 clock bytes, plus **4 KB NVSRAM** (PReP NVRAM). Ports 0x70 and 0x74/0x75/0x76. | [RB p.72, p.189, p.68 fig] |
| **Graphics ("E15")** | **S3 Vision864 (86C864 "DXP"/"DXP-2")** + **16-bit 135 MHz S3 SDAC** (part number not given; 86C716 [background]) + **2 MB DRAM** (4 chips, 70 ns, 64-bit path) | PCI | VGA-compatible plus linear framebuffer. Modes up to 1280×1024×8 (1600×1200 interlaced). The board drawing label is low-resolution ("86C86x"); the text says 86C864. AIX location **iga0, "C0"**. | [RB p.48, p.70, p.123–124], [GH p.30, p.81] |
| **Ethernet** | **AMD Am79C970 PCnet-PCI** | PCI bus master | 10BaseT RJ45 only; PCI 2.0; scatter/gather. Both 830/850 and 7248 carry it [inferred from shared planar; MCBX "On-board RJ45-based LAN"]. | [RB p.71], [OS2] |
| **Audio ("Business Audio")** | **Crystal CS4232** + **Yamaha YMF289B** (OPL3) + **YAC516E** DAC | ISA | Sound Blaster / SB Pro compatible, MPU-401, joystick, 16-bit stereo 5.5–48 kHz, separate record/playback DMA. Timer-2 speaker output is mixed with audio into the speaker amp. Ports 0x830–0x833 = audio index/data registers. | [RB p.56, p.72–73, p.189] |
| **SCSI (7248 only)** | **NCR 53C810** [inferred] | PCI | Evidence: the Solaris path on a 7248 is `/pci/pci1000,1@10/...` [N7248]; PCI ID 1000:0001 = NCR 53C810 [background]. The 53C810 is also the ThinkPad part [RB p.116]. The NCR 53C825 in [MCBX] is an **add-in card** in a Power Series 850. | [N7248] |
| Interrupt controllers | Two cascaded 8259-style PICs (IRQ2 = cascade) in the PCI-ISA bridge | ISA | **All PCI interrupts are funnelled to IRQ15.** | [RB p.71, p.187–188] |
| DMA | 8237-style, 8 channels, ch 4 = cascade | ISA | See §3.4 | [RB p.188] |
| Timers | 8254-style interval timer (IRQ0); Timer 2 drives the speaker | ISA | | [RB p.72–73, p.187] |
| Clock generation | **AMCC 3506**: 66 MHz in → 10 × 66 MHz (CPU, L2) + 10 × 33 MHz (PCI). **ICS 9154**: 14.31818 MHz (video, riser, PCI-ISA bridge), 12 MHz (KBC), 24 MHz (SIO). Plus "CPU OSC" and a **40 MHz OSC** whose use is not stated (SCSI clock? **(?)**). | — | | [RB p.72, p.68 fig] |
| Power management | "Power Management" block on the X-bus; soft power switch, remote power-on jumper, +5 V aux | X-bus | Shares IRQ13 | [RB p.64 fig, p.68 fig, p.187] |
| PCI/ISA riser | Riser card connector | PCI + ISA | 830: 2 PCI + 3 ISA; 850: 2 further ISA slots shared with PCI. **The 7248's slot count is not documented (?).** | [RB p.92–93] |

### 2.2 Planar block diagram (summary of [RB p.64, Fig. 11])

```
 PPC604 ── 60x bus ──┬── Upgrade socket (604+)
                     ├── L2 (data SIMM + IDT71216 tag)
                     └── MPC105 Eagle ── DRAM (6 SIMMs, via buffers)
                              │
                       32-bit PCI bus (33/30 MHz)
   ┌──────────┬───────────┬─────────┬─────────┬──────────────┬─────────────┐
 S3 864+SDAC  Am79C970   PCI slot1 PCI slot2  [7248: NCR 53C810] PCI-ISA bridge (FireCoral) + EIDE
                                                                     │
                                         16-bit ISA bus (8.33/7.5 MHz)
            ┌──────────────┬───────────────┬───────────────┬────────────────┐
        ISA slots     CS4232 audio     PC87332 SIO     buffer → X-bus (8-bit)
                                                          ├── 512 KB flash (29F040)
                                                          ├── RTC/NVRAM (4 KB)
                                                          ├── 8042 KBC
                                                          └── Power management
```

### 2.3 External ports and internal bays

| Item | Detail | Source |
|---|---|---|
| Rear ports (planar edge, left to right) | Video DB-15, PS/2 keyboard, PS/2 mouse, Ethernet RJ45, Serial 1 (DB-9), Serial 2 (DB-9), earphone, microphone, line-out, line-in (3.5 mm); parallel DB-25 via internal cable | [RB p.68 fig, p.127] |
| Serial | RS-232, up to 115.2 kbaud, 9-pin | [RB p.127, p.193] |
| Parallel | IEEE 1284; ECP using DMA | [RB p.127, p.188] |
| Video connector | DB-15 with monitor ID 0–3 pins | [RB p.195] |
| Internal connectors | Floppy, IDE primary, IDE secondary, CD-audio, MIDI/joystick header, speaker | [RB p.68 fig] |
| 7248 bays | **Not documented locally (?)**. The 7248 "looks like other 43P series" members [N7248]; a 4× CD and a floppy are standard on Power Series machines [RB p.38] | [N7248] |
| PSU (7248) | API-3186S, IBM P/N 06H8617, FRU 06H8619: +5 V/20 A, +3.3 V/20 A, +12 V/8 A, −5 V/0.5 A, −12 V/0.5 A, +5 VS/0.02 A; connectors P1/P2/P10/P11 | [N7248] |
| PSU (830/850) | 830: 100 W-class table (18 A on +5 / +3.3); 850: 200 W; soft on/off signal and power-good | [RB p.175–177] |

---

## 3. Address map, I/O map, IRQ/DMA, PCI

### 3.1 CPU physical memory map

**No local document gives the Carolina/MPC105 memory map.** The redbook says only that the firmware hands over to the OS with "the I/O space … configured as **contiguous**", the CPU in big-endian mode, and residual data in memory [RB p.139]. It also says the architecture reserves up to 16 MB of ROM space [RB p.70].

The following is the **PReP / MPC105 "address map A" from [background]** and must be verified against the MPC105 user's manual and firmware disassembly:

| CPU address | Size | Target | Status |
|---|---|---|---|
| 0x0000_0000–0x7FFF_FFFF | 2 GB | System DRAM (192 MB max populated) | [background] |
| 0x8000_0000–0x807F_FFFF | 8 MB | PCI/ISA I/O space (ISA ports at 0x8000_0000 + port). "Contiguous" vs "discontiguous" mode is selectable — see I/O 0x0850. | [background] + [RB p.139, p.190] |
| 0x8080_0000–0x80FF_FFFF | 8 MB | PReP direct-mapped PCI configuration space (IDSEL-select by address bit) | [background] |
| 0x8100_0000–0xBF7F_FFFF | — | PCI I/O | [background] |
| 0xBFFF_FFF0 | — | PCI interrupt-acknowledge (8259 vector read) | [background] |
| 0xC000_0000–0xFEFF_FFFF | ~1 GB | PCI memory; ISA memory at 0xC000_0000 (VGA aperture at 0xC00A_0000) | [background] |
| 0xFF00_0000–0xFFFF_FFFF | 16 MB | ROM space; 512 KB flash at 0xFFF8_0000 or mirrored to 0xFFF0_0000 **(?)**; reset vector 0xFFF0_0100 | [background], [RB p.70] |

### 3.2 IBM / PReP system registers (ISA I/O ports) — documented

Source: Table 40 [RB p.189–190], Power Series 830/850. These must be modelled; the firmware reads the planar ID to choose its personality.

| Port | Register |
|---|---|
| 0x0060 | Keyboard controller data |
| 0x0061 | NMI status and control |
| 0x0064 | Keyboard command/status |
| 0x0070 | RTC address + NMI enable |
| 0x0071 | Listed as "L2-cache error read and clear". On a PC-compatible RTC this would be the RTC data port, so this entry is probably a doc error **(?)** |
| 0x0074 | NVRAM address strobe 0 (low byte) |
| 0x0075 | NVRAM address strobe 1 (high byte) |
| 0x0076 | NVRAM data |
| 0x0092 | System special register (PReP: reset / endian control [background]) |
| 0x0808 | Hard-drive light |
| 0x080C | Equipment present |
| 0x0810 | TOD NVRAM protect 1 |
| 0x0812 | TOD NVRAM protect 2 |
| 0x0814 | L2 flush |
| 0x081C | System control |
| 0x0820 | Memory controller programming |
| 0x0821 | Memory controller timing |
| 0x0830 | Audio index register 1 |
| 0x0831 | Audio index data |
| 0x0832 | Audio index register 2 |
| 0x0833 | Audio PIO data |
| 0x0838 | IRQ13 interrupt-request-active (demultiplexes IDE / PM / scatter-gather on IRQ13) |
| 0x083C | Reserved |
| 0x0840 | Memory parity error status |
| 0x0841 | Reserved |
| 0x0842 | L2-cache error status |
| 0x0843 | L2-cache error read and clear |
| 0x0844 | Illegal transfer error |
| 0x0850 | **I/O map type** (contiguous/discontiguous) |
| 0x0852 | **Planar ID** |
| 0x0880 | Memory modules 1 & 2 presence |
| 0x0881 | Memory modules 3 & 4 presence |
| 0x0882 | Memory modules 5 & 6 presence |

The standard PC ports are also present: IDE 0x1F0–0x1F7 and 0x3F6/0x3F7 [RB p.109], plus the usual 8259/8237/8254/SIO addresses [background].

### 3.3 IRQ assignments (Power Series 830/850) [RB p.187–188]

| IRQ | Use |
|---|---|
| 0 | Interval timer |
| 1 | Keyboard |
| 2 | Cascade from PIC 2 |
| 3 | Serial port 2 |
| 4 | Serial port 1 |
| 5 | Parallel port 2, or audio IRQA |
| 6 | Diskette |
| 7 | Parallel port 1, or audio IRQB |
| 8 | RTC |
| 9 | Unassigned, or audio IRQC |
| 10 | Unassigned |
| 11 | Unassigned, or audio IRQD |
| 12 | Mouse, or audio IRQE |
| 13 | **EIDE (primary + secondary), power management, scatter/gather** (shared; see port 0x838) |
| 14 | Unassigned, or audio IRQF |
| 15 | **All PCI devices and adapters** |

ISA cards may use IRQ 9, 11 and 14 (plus 5 or 7 if the parallel port does not use them). The 7248 SCSI and Ethernet would then share IRQ15 [inferred]. Compare the 7043-140, where IRQ13 is scatter/gather only and IRQ15 is the tablet port [UG7043 p.307].

### 3.4 DMA channels [RB p.188]

| Ch | Use |
|---|---|
| 0 | Audio 2 or ECP |
| 1 | Audio 1 or ECP |
| 2 | Floppy |
| 3 | Audio 2 or ECP |
| 4 | Cascade (in SIO) |
| 5 | ECP |
| 6 | **Primary EIDE** |
| 7 | **Secondary EIDE** |

DMA is possible only between ISA or planar devices and ISA, PCI or system memory.

### 3.5 PCI devices / IDSEL — sparse evidence

| Device | Evidence | Source |
|---|---|---|
| Onboard SCSI (7248) | Open Firmware (VOF) unit address **@10** → PCI device 0x10 (16) | [N7248] |
| Onboard E15 (S3) | AIX location code **04-C0** (`iga0`, slot "C0"). On RSPC the letter follows the residual-data order of integrated devices; it is not an IDSEL. | [GH p.81], [DIAG p.247] |
| RSPC location-code scheme | 04-A0 = ISA bridge, 04-B0/C0 = integrated PCI devices, 01-A0…F0 = integrated ISA devices (diskette, parallel, serial 1/2, keyboard, mouse) | [DIAG p.247–248] |

The IDSEL wiring and the device numbers of the MPC105 (host bridge, normally device 0), FireCoral, S3, PCnet and the 2 slots are **not documented locally (?)**.

### 3.6 Residual data

- The firmware passes **residual data structures** to the loaded image [RB p.139].
- AIX derives integrated-device location codes from the residual data order [DIAG p.247].
- The boot record is a PC-style MBR with a PReP partition (type 0x41 [background]). The firmware loads the "load image" from the partition's RBA, checks it, disables external interrupts, and jumps to the entry point in big-endian mode with position-independent code [RB p.137–139].

---

## 4. Front panel, boot UI, error codes

### 4.1 No LED operator panel on the 7248

- The 7248 has **no LED display** (missing compared with the other 43Ps) [N7248].
- Progress is shown **graphically**: a PowerPC logo plus a row of icons [RB p.35–36], [MCBX photo 010_AMMO.jpg].
- Errors are shown as an **8-digit code** at the top-left with a warning triangle; the photo shows `00031200`, "keyboard not attached" [MCBX].
- 7043-style Fxx/E1xx checkpoints do **not** apply to the 7248 (see Appendix A).

**Boot sequence** (from the firmware virtual disk's `AUTOEXEC.6MD`, read via the in-ROM shell [MCBX]):

1. Load the console driver for the present video.
2. Set 640×480.
3. Draw `oem.bmp` (logo).
4. Old versions play a sound here.
5. Draw the keyboard icon.
6. Load the keyboard and mouse drivers.
7. Three quick beeps.
8. Draw the memory icon.
9. Run the memory test (`iat_mem`).
10. Draw the network icon.
11. Load `iat_dskt`.
12. Draw the drives icon.
13. Run the `scsi` probe.
14. Draw the speaker icon.
15. Load the network drivers and TCP/IP.
16. Some versions play a "ready" sound.
17. Beep before boot.

**Firmware structure** [RB p.133–136]:
- A boot block, used only for recovery after a failed flash.
- A firmware core that decompresses the main image from flash into RAM.
- A virtual disk of pluggable modules.
- The firmware runs from RAM, with user, interrupt and debugger stacks.

### 4.2 Hot keys (press after the keyboard icon, before the last icon)

| Key | Action | Source |
|---|---|---|
| F1 | Graphical SMS (needs the SMS diskette; otherwise a "insert diskette" animation appears) | [RB p.152, p.166], [N7248], [FW READMEs] |
| F4 | Text-mode SMS ("Extended SMS"); also starts the flash utility from a firmware diskette | [RB p.154], [FW:sms102 README] |
| F2 | Network-based SMS / R-IPL [RB p.154]; [MCBX] reports a boot-device menu **(?)** | [RB p.154], [MCBX] |
| F5 | Use the factory-default boot sequence once | [RB p.59, p.152] |
| F8 | OK prompt on systems that support it (generic RSPC note) **(?)** | [DIAG p.170] |
| Type `eatabug` at the SMS-diskette prompt | **Resident monitor** (DOS-like `A:>` shell over the ROM virtual disk). Commands include `flash -a` and soft-loading `P*.IMG` by name. | [FW:ros104/sms102 README], [MCBX] |

### 4.3 Error codes — Personal Computer Power Series (Carolina firmware) [RB p.166–173]

This is the best available table for the 7248, because it is the same firmware family. "x" = any digit.

| Code | Meaning |
|---|---|
| 00010000 | Microprocessor problem |
| 00015xxx, 00016000, 00016002 | System board problem |
| 00016003 | Unattended start mode is locked |
| 00016004, 00016005 | Supervisor password locked |
| 00017001 | NVRAM error, low battery |
| 00017002 | NVRAM data gone |
| 00017003 | Power lost while updating the startup sequence |
| 0001700x | Too many password attempts |
| 00017013 | Power-on password (POP) required for unattended start |
| 00018000 | System board problem (run memory tests) |
| 00020000 | Memory error |
| 000210x0 | Memory error in SIMM slot x (1–6) |
| 000300xx | Keyboard problem |
| 00030050 | Key pressed during test |
| 00031100 | Keyboard in the wrong port |
| 00031200 | Keyboard not attached |
| 00031300 | Keyboard interrupt not registered |
| 0006xxx0 | Diskette drive or media |
| 0011xxxx | Serial port |
| 0014xxxx | Parallel port |
| 00370830 | SCSI breaker (wait 15 min) |
| 0037xxxx | SCSI problem |
| 008600xx | Mouse (xx = 50: input during test) |
| 0129xxxx | L2 cache |
| 0166xxxx | Token-ring adapter |
| 0208xxxx–0219xxxx | SCSI subsystem: 0209/0211 media, 0212 printer, 0214 WORM, 0215/0218 CD-ROM, 0216 scanner, 0217 optical, 0219 communications |
| 0243xxxx | Graphics adapter |
| 0250100x | Audio |
| 0265xxxx | Ethernet adapter |
| 0267xxxx | **Integrated Ethernet** |
| 0849xxxx | X.25 |
| 0942xxxx | Graphics adapter |
| 5333000x | Graphics adapter (S3; "5333" is S3's PCI vendor ID [background]) |
| 50001100 | Firmware level differs from SMS |
| 80001100–80002800 | Firmware-update errors: not found, recovery write failed, same level, wrong system, unreliable file, multiple files, write-protected module, wrong utility, missing diskettes |
| 90001100–90001600 | Diagnostic-file copy errors |
| 91001100–91002200 | Insufficient memory; bad client/server/gateway/netmask IP; NVRAM write error; Ethernet not found; EEPROM update failed; token ring not found; no network adapter; `ping.6xe` missing; ping failed |

SCSI FRU letters used in the SCSI codes [RB p.172–173]:

| Letter | Device |
|---|---|
| B | Rewritable optical |
| C, D | CD-ROM 1, 2 |
| E, F, H | Enhanced CD-ROM |
| M | 2 GB 68-pin HDD |
| N, Q, W | 540 MB HDD |
| O | 1 GB HDD |
| P | 2 GB HDD |
| b | 728 MB HDD |
| U | Unknown |

The ThinkPad POST and diagnostic tables are also given [RB p.161–165] but are less relevant.

### 4.4 AIX-side codes

- AIX configuration "LED" codes (3-digit, e.g. 79c = "ISA bus configuration executing") and SRNs are listed in [DIAG p.229–242].
- On RSPC these appear as Yxx [DIAG p.51].
- SRN group **7C1-xxx = CS4232 audio** (7C1-102 "CS4232 failed", 7C1-109 "CODEC ID invalid") [DIAG p.425].
- How AIX shows LED codes on a 7248 that has no LED is **(?)**.

---

## 5. Operating systems and firmware

### 5.1 OS support (as stated in the docs)

| OS | Statement | Source |
|---|---|---|
| AIX | Preload option "AIX Version 4 for Clients" on Power Series. Power Series and 7248 were "supported until version 5.1". [GH] shows 7248 ("43P-133") runs with AIX 4.1.5 and 4.2.1. | [RB p.37, p.61], [OS2], [GH p.152, p.239] |
| Windows NT | NT 3.51 PowerPC (Build 1057 power-managed). NT 4.0 runs ([MCBX]). Needs the ARC loader diskette; local ARC 1.46–1.51 archives are present. | [RB p.59], [MCBX] |
| OS/2 Warp PowerPC Edition | Targeted at 830/850. Needs a CD-ROM with native 2048-byte sectors to boot. Unstable above 64 MB. Not successfully installed on a 7248 by [N7248]. | [OS2], [MCBX], [N7248] |
| Solaris 2.5.1 PPC | Works on the 7248 with the IBM boot floppy "S596P_11" (Virtual Open Firmware). The 7248 must use onboard S3 graphics, not the GXT150P. Boot path `boot /pci/pci1000,1@10/cdrom@3,0:,\solaris.elf` | [N7248], [MCBX] |
| Linux/PPC | "Supported to some extent" | [N7248], [OS2] |

### 5.2 Firmware and SMS levels

| File in folder | What it is (per docs/README) | Source |
|---|---|---|
| `7248100.exe` / `7248100.bin` | 7248 firmware **v1.11** + SMS **1.07**. Contains `p93h4940.img` (512 KB), `flash.6xe`, `sms107.exe`/`sms107.dd`, `fw-111.dd`, ASCII-terminal notes (`asciterm.txt` / `ascii_terminal.doc`). The archive is **password-protected**. [N7248] lists 1.11 = P93H4940.IMG (11/14/1996) and **1.12 = P93H7075.IMG (03/31/1997)**; 1.12 is **not** in the folder. | [FW:7248100.exe banner/listing], [N7248] |
| `ros104.exe` | Carolina ROS **v1.04** (06/1995). `P40H4386.IMG` = 6050/6070 image; **`P40H4388.IMG` = 7248/OEM image**. Use with SMS 1.02. | [FW:ros104 README] |
| `sms102.exe` | Carolina **v1.02** (05/1995). `P40H4137.IMG` = 6050/6070; **`P40H4139.IMG` = 7248/OEM**. Includes SMS 1.02 diag modules: AUD, BBL (Baby Blue = GXT150-family video), C1X (X.25), DSKT, ENET, I970 (Am79C970), IDE, JOY, KEY, L2, MEM, MOU, P9VDGS (P9000/P9100), PAR, S3VDGS, SCSI, SER, SYSDGS (processor, interrupts), TRS (token ring), plus network-SMS files. | [FW:sms102 README] |
| `p8x0_106.trz` | Power Series 830/850 firmware **1.06** (Aug 1995) for AIX hosts: `P40H5090.dd`, `sms106.dd`. Includes a security advisory that also names the 43P. | [FW:README_8x0] |
| `p8x0_107/108/110.exe` | Power Series 830/850 firmware **1.07 / 1.08 / 1.10**: `P40H5174.IMG`, `P40H5218.IMG`, `P93H1904.IMG`, plus SMS 1.07/1.08/1.10. [MCBX] says the 1.10 SMS differs from 1.07 only by Audio Solo card drivers, and that `7248100` (1.11) flashes successfully on an 850. | [FW listings], [MCBX] |
| `sms126.exe` / `sms126.dd` | SMS plus `P12H0354.IMG` (Jan–Feb 1995). It has the same module set as sms127, i.e. **probably Sandalfoot-era, not Carolina (?)** | [FW listing] |
| `sms127.exe` | **Sandalfoot/Sandalbow/OEM** DVT-8B build, SMS 1.21 (9/1994). Not Carolina. | [FW:sms127 READ.ME] |
| SMS diskettes (7248) | SMS v1.0? (05/1995, 30H2090); SMS 1.07 "6050/6070/7248" (11/1995, 8133689) | [N7248] |
| `7249_6042_firmware.zip` | ThinkPad 850 (7249/6042) microcode 1.01 (`think850.bin/.exe`). Not Carolina. | [FW] |
| `ppc_arc_*`, `nt_beta_sound_driver.zip` | ARC loaders 1.46–1.51 and an NT 4.0 PPC sound driver | listings |

**Flash/recovery procedure:**
- Boot with F4 and the firmware diskette; the flash utility saves a recovery image (`PRECOVER.IMG`) to a second diskette [N7248], [FW:p8x0_110 README].
- A partially corrupted flash shows no video while the floppy LED stays lit or blinks, and the boot block recovers from diskette [FW:p8x0_110 README], [RB p.134].

---

## 6. Option adapters an emulator might need first

| Adapter | Bus | Key chips / facts | Source |
|---|---|---|---|
| **POWER GXT150P** (2D, 8-bit, 1024×768 / 1280×1024, 3 MB VRAM, 4 WID bits, 3 HW colormaps, 13W3) | PCI | Photos show:<br>• **IBM 88G2734** graphics processor<br>• **IBM 37RGB530CF17** "Palette DAC" (P/N 8187135)<br>• Toshiba **TC160G54AF** gate array (IBM 8184196)<br>• 12 × 256K×8 VRAM (6 Toshiba TC528267, 6 NEC)<br>• 50 MHz oscillator, 4-position DIP switch<br>• FRU 8184190<br>Codename family "Baby Blue": AIX fileset `OpenGL...dev.common.bbl` covers GXT150L/155L/150P; SMS `BBL.6DG`. P/N 8185425 (US), 85G5270 (JP). | [RB p.49, p.179, p.182], [GXT photos], [GH p.157], [FW:sms102 README] |
| S15 (2 MB VRAM) / H10 (4 MB VRAM, NT only) | PCI | Weitek P9100 + IBM RGB525 (170 MHz) + Weitek 9130 video coprocessor + ICD2061A. Supported by SMS `P9VDGS.6DG`. Shows as `gga0`. | [RB p.50–52], [GH p.30, p.81] |
| GXT250P / GXT255P | PCI | Run on "43P-133" with AIX 4.2.1 / 4.1.5 (PCI IDs 1014:103c [background, from fileset name 14103c00]) | [GH p.48, p.152, p.239] |
| GXT1000 via FC 2856 (7250 attach adapter) | PCI | Listed as an SSR-install feature for the 7248 | [SH p.788], [DIAG p.12] |
| PCI SCSI-2 Fast/Wide adapter | PCI | 85G5271 (JP); [MCBX] used an NCR 53C825 card | [RB p.183], [MCBX] |
| ISA Ethernet 48G7169; ISA 4/16 Token Ring 92G7632; ISA 8-port async 11H5966; X.25 co-processor | ISA | | [RB p.179–180] |
| Video Capture Enhancement | ISA (power only) | Daughter card for S15/H10 | [RB p.52, p.181] |

---

## 7. Implications for the FPGA core

### 7.1 Devices to model, in priority order

The aim is to reach the firmware icon screen and SMS, and then boot AIX.

1. **PowerPC 604 core** at 100 MHz with a 64-bit 60x bus model clocked at 66 MHz equivalent. Requirements:
   - Big-endian, with little-endian mode support for NT/OS/2 later.
   - BATs and the hash-table MMU.
   - 604 SPRs (PVR = 604; HID0 cache controls).
   - L1 cache behaviour visible to firmware (dcbz/dcbf/icbi).
2. **MPC105 "Eagle" model.** Requirements:
   - Address map A decode.
   - PCI configuration mechanism.
   - Memory-controller configuration registers, so firmware can size the 6 SIMM banks (together with presence registers 0x880–0x882).
   - Error/parity status registers.
   - **L2 controller and tag behaviour.** Either emulate "L2 present and passes" or report no L2; firmware has an L2 test (error 0129xxxx) and flush register 0x814.
3. **Flash ROM**: 512 KB at the top of memory with the reset vector. Read-only first; add the AMD 29F040 command set later for `flash -a`. A real 7248 image is available: `P40H4388.IMG` / `P40H4139.IMG`, and `p93h4940.img` once the archive is opened.
4. **IBM system registers** 0x0808–0x0882 (§3.2): especially **planar ID 0x852**, equipment present 0x80C, I/O map type 0x850, system control 0x81C, memory-controller programming 0x820/0x821, IRQ13-active 0x838, and the error registers.
5. **PCI-ISA bridge (FireCoral)**:
   - 2 × 8259 with PCI interrupts on IRQ15.
   - 8254 PIT, including Timer 2 to the speaker.
   - 2 × 8237 DMA.
   - Ports 0x61 and 0x92, NMI.
   - PCI interrupt-acknowledge cycle.
   - Its PCI config header (ID unknown).
6. **RTC + 4 KB NVRAM** (ports 0x70/0x71 and 0x74/0x75/0x76), battery-backed through MiSTer storage. The firmware reports 00017001/2 if the NVRAM is bad.
7. **8042 KBC + PS/2 keyboard/mouse**, because the keyboard icon is checked (0003xxxx / 00031200).
8. **S3 Vision864 + SDAC** (VGA plus a linear 640×480×8 framebuffer is the minimum for icons). The firmware loads its console driver according to the video it detects [MCBX].
   - Alternative to investigate: the 7248 v1.11 package includes **ASCII-terminal console** documentation (`asciterm.txt`), so a serial console might allow headless bring-up first **(?)**.
9. **PC87332 Super I/O**:
   - **FDC** is mandatory, because SMS, flash updates and the Solaris/NT loaders all come from diskette.
   - UART 1/2 for an early debug console.
   - Parallel port as a stub.
10. **NCR 53C810** (SCRIPTS engine, PCI bus-master). This is the 7248's disk and CD path for AIX installation and boot. The firmware's `scsi` probe step and SCSI error codes 0208–0219 / 0037xxxx exercise it.
11. **EIDE** in the bridge (IRQ13 via 0x838, DMA 6/7). This is the alternative boot path the Power Series uses, and is probably simpler than SCSI for a first disk.
12. **Am79C970 PCnet**: the firmware loads network drivers at the network icon. A minimal stub must at least pass presence and self-test (0267xxxx). It is needed for network SMS and R-IPL.
13. **CS4232 + OPL3**: a stub sufficient for the speaker-icon step and audio diagnostics (0250100x; AIX SRN 7C1).
14. GXT150P (later, for AIX graphics) and power-management registers (soft-off).

### 7.2 Open questions

1. **Real memory map and MPC105 configuration as used by Carolina.** Is it map A? Where is the 512 KB flash aliased? Does the firmware use contiguous ISA I/O, and what does register 0x0850 do? Answer by disassembling `P40H4388.IMG` together with the MPC105 manual.
2. **FireCoral**: its PCI vendor/device ID, register set, and how SIO-compatible it is. Does the EIDE function sit inside it or alongside it? [RB p.71] and [RB p.116] differ on this.
3. **PCI IDSEL/device numbers and interrupt routing** for MPC105, FireCoral, S3, PCnet, 53C810 (dev 0x10 per [N7248]) and the slots. Confirm that every PCI INTx really goes to IRQ15.
4. **Planar ID values** (0x852) that distinguish 7248 from 6050/6070 and 100/120/133 MHz boards. Also the value and bit layout of equipment-present (0x80C).
5. Exact **RTC/NVRAM part** and the meaning of the "0x71 = L2 error" table entry.
6. **S3 SDAC part number** (86C716?) and the true 864 revision (the drawing label is unclear).
7. **7248 physical configuration**: slot count (PCI/ISA riser), bays, whether IDE, audio and Ethernet connectors are fitted on the 7248 variant, and its standard disk/CD. The 7248 User's/Service Guide (SA38-04xx?) is **missing** from the folder.
8. Minimum **AIX level** for the 7248 (4.1.x?). How AIX reports configuration codes without an LED panel.
9. Whether firmware **1.12 (P93H7075.IMG)** can be found. The `7248100` archive is encrypted, so its README has not been read.
10. Whether any 7248 really shipped as a "-100" (the archive banner says Model 120/133).
11. Use of the **40 MHz oscillator** (53C810 SCLK?) and the separate "Native I/O" block on the board drawing.
12. The **7249** ThinkPad 850 microcode mentions MPC105 errata while [RB] says IBM IDAHO. This is only relevant if 6042/7249 code is used as a reference.

---

## Appendix A. 7043 (successor 43P) codes — **for comparison only, not 7248**

The 7043-140/240 firmware uses an operator-panel display [SG7043 p.38–39, p.92–112]. It is a different, Open-Firmware-based firmware and is listed here only so it is not confused with the 7248.

**POST codes (M-prefix) [SG7043 p.92–93]:**

| Code | Meaning |
|---|---|
| M0CON000 | Hang during POST |
| M0CPU000 / 001 | CPU POST failed / checkstop |
| M0FD0000 | Diskette POST hang |
| M0GA0000 | Graphics adapter POST failed |
| M0HD0000 | Boot POST hang |
| M0KBD000–003 | Keyboard |
| M0MC0001 | Machine check |
| M0MEM000–002 | Memory |
| M0PS0000 | Power |
| M0SCSI00 / 01 | Unable to load diagnostics |
| M0SPK000 / 001 | Speaker |
| M0BT0000 | Audio |
| M0NET000 | Network |

**Firmware error codes (2xxxxxxx) [SG7043 p.94–102]:**

| Code | Meaning |
|---|---|
| 20100xxx | Power supply |
| 20A80xxx | RIPL |
| 20D00xxx | Unknown device |
| 20E00xxx | Security / EEPROM / battery |
| 20EE0xxx | SMS informational |
| 21A00xxx | SCSI disk |
| 21E/21ED/21EE/21F0/21F2 | SCSI tape / changer / other / CD-ROM / optical |
| 25010xxx | Flash |
| 25A0xxy0 / 25A1xxy0 | L2 controller / L2 SRAM |
| 25A80xxx | NVRAM |
| 25AA0xxx | EEPROM |
| 25Cyyxxx | DIMM |
| 28030xxx | RTC |
| 29000002 / 29A00003 / 29B00004 | KBC / keyboard / mouse |
| 2B2xxyrr | Processor and cache type |

**Checkpoints (Fxx) [SG7043 p.104–108]:**

| Code | Meaning |
|---|---|
| F01 | Memory test |
| F05 | Transfer control to OS |
| F22 | No memory |
| F2C | Processor card mismatch |
| F4D | Loading boot image |
| F4F | NVRAM init |
| F51 / F52 / F55 / F5F | PCI probe |
| F5B | Service-mode boot |
| F74 / F75 | Network / BOOTP |
| F88 | Fan EPOW |
| F9E | RTC init |
| FDC | Console selection |
| FDD / FDE | Processor exception |
| FEA / FEB | Flash corrupt, load from diskette |
| FF2 / FF3 | Passwords |
| FFB | SCSI init |
| FFD | Alternates with the failing Fxx |

The 7043-150 uses E1xx checkpoints [SG7043 ch.4, p.113+]. The 7043 location codes follow the same RSPC AB-CD-EF-GH scheme as §3.5 [SG7043 p.111–112].

## Appendix B. From Linux 2.6.26's PReP code (Carolina)

`arch/ppc/platforms/prep_pci.c` and `prep_setup.c` (saved in
`scratch/downloads/linux-2.6.26-prep/`), written partly from IBM's
"Carolina Technical Specification":

PCI devices on bus 0 (the IDSEL by device number) and their interrupt pins
(`ibm8xx_pci_IRQ_map`); every PCI interrupt line is routed to **IRQ 15**
(`ibm8xx_pci_IRQ_routes`), level-triggered (the edge mask: IRQs 10, 13
and 15 level):

| device | what | pin |
|---|---|---|
| 11 | Fire Coral (the PCI-ISA bridge) | - |
| 12 | Ethernet (Am79C970) | INTD# |
| 13 | PCI slot | (2) |
| 14 | S3 video | INTD# |
| 15 | on-board SCSI ("INDI"), unused | - |
| 16 | NCR 53C810, the 7248 only | INTC# |
| 18 | PCI slot 2 | INTx# |

The planar IDs (port 0852): F0-F3 Carolina with IDE (Power Series
830/850), F4-F7 Carolina with SCSI (the 7248; F7 "missing from the
Carolina Tech Spec").

IBM system registers:

| port | | bits |
|---|---|---|
| 0803 | SIMM ID | SIMM size, 32 or 8 MB |
| 0804 | SIMM presence | |
| 080C | equipment present | 01 L2 absent (0: present), 02 upgrade CPU absent, 04 L2 256 KB, 08 L2 copy-back, 40 SCSI fuse good, 80 reserved |
| 080D | L2 information | 60: size (00 256 KB, 20 512 KB), 03: type (0 async, 1 sync) |
| 081C | system control | C0: L2 enable (`prep_carolina_enable_l2` sets both) |
| 082A | power management 1 | |
| 0852 | planar ID | |
| 08C0 | the 4-digit LED display | (the firmware's early progress codes; the 7248 has no display) |
