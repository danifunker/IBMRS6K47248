# IBM RS/6000 43P 7248 ("Carolina"): emulators, firmware and OS media

Research date: 2026-10-16/17. Companion documents: `hardware_inventory.md` (chip list) and
`firmware_analysis.md` (ROM layout).

Short version:
- **QEMU's `40p` machine is the only working emulator of an IBM PReP box**, and it runs AIX
  4.3.3 and 5.1. It emulates the older 7020-40P ("Sandalfoot"), not the 7248, and it boots AIX
  through a third-party Open Firmware port, not IBM's ROM.
- **No emulator anywhere models the Carolina board (7248 / Power Series 830/850).**
- MAME has only skeletons. Nobody emulates the IBM 82660, and the 7248 does not use it (see A.0).

---

## Part A: Emulators and simulators

### A.0 Correction: the 7248 host bridge is the Motorola MPC105, not the IBM 82660

The brief assumed the IBM 82660 chipset. The evidence points the other way:

| Evidence | Says |
|---|---|
| IBM redbook *IBM PC and ThinkPad Power Series* (`scratch/IBMPowerPC/Pages/ibm_ppc_thinkpad_redbook.pdf`, sec. 3.1.1.3) | "The desktop system [Power Series 830/850 = Carolina] uses the **Motorola MPC105 Eagle** chip for the PCIB/MC function" |
| Hervé Poussineau's 2013 QEMU series "ppc/prep: add IBM RS/6000 43p machine" (7248) | Implemented an `mpc105-pcihost` for the 43p and tested IBM firmware **P93H1904.IMG** (a 7248 ROM). The series was never merged. |
| `hardware_inventory.md` (photo and redbook) | MPC105 marked XPC105ARX66CD on the Carolina planar |
| IBM 660 manual (downloaded, below) and NetBSD `ibm82660reg.h` | The IBM27-82660 ("Lanai/Kauai", PCI ID **1014:0037**) is a different IBM bridge. It is register-compatible with the earlier IBM27-82650 BCRs. MPC105 is **1057:0001**. |

Conclusions:
- No emulator implements the 82660, and the 7248 does not need one.
- The MPC105 is modelled in **MAME** (`src/devices/bus/lpci/mpc105.cpp`, used by the BeBox) and was modelled in Hervé's unmerged 2013 QEMU patch.
- Please confirm on real hardware: read PCI config space at bus 0, device 0 (vendor/device ID).

### A.1 Summary table

| Project | URL | Status | Machine(s) emulated | Firmware it runs | What boots | Useful device models |
|---|---|---|---|---|---|---|
| **QEMU `-M 40p`** (upstream; local clone `/home/dani/repos/qemu`, v11.1.2) | https://www.qemu.org, `hw/ppc/prep.c` | Maintained but niche. It was the only PReP machine left after the old `-M prep` was removed. | IBM RS/6000 **7020-40P** (Sandalfoot; planar ID 0xFC). Single 604 (default CPU), 128 MiB default RAM. | Default `openbios-ppc` (weak on PReP). In practice it uses **Artyom Tarasenko's Open Firmware port `q40pofw-serial.rom` / `q40pofw-vga.rom`** (Firmworks OFW, hard-codes 128 MiB). IBM **P12H0456.IMG** (40P ROM v1.29) runs and boots NetBSD; it is QEMU's own functional test (`tests/functional/test_ppc_40p.py`). | With q40pofw: **AIX 5.1** (CD and HD), **AIX 4.3.3** (install about 11 to 60 min). Reports also cover 4.1.5, 4.2.1 and 4.3.2 to the `ok`/boot stage. AIX 5.2 fails because its CD has no PReP partition. With the IBM ROM: NetBSD/prep and Linux/PReP. The IBM ROM **cannot boot AIX** under QEMU (Tarasenko, 2019). NT stops when it switches to little-endian, because LE mode is unimplemented. | Raven host bridge (PReP map, IACK, contiguous/non-contiguous I/O); i82378 SIO; prep-systemio (0x80x–0x85x); rs6000-mc (SIMM regs); pc87312; lsi53c810; pcnet; cs4231a; m48t59 NVRAM; mc146818 |
| **QEMU fork, Tarasenko** | https://github.com/artyom-tarasenko/qemu, branch `40p-20190406-aix-boots`. OFW: https://github.com/artyom-tarasenko/openfirmware/releases | 2019, frozen. Its 4 fixes (53c810 register hiding, PCI bus mastering, BAT invalidation speed, RTC base year 1900) are now upstream (`1dbe3d196d`, `aaef873b13`, `d16644ec4c` raven BM). | 40P | q40pofw (serial or VGA) | AIX 4.3.3 / 5.1 on a serial console. No usable AIX graphics: AIX cannot drive the emulated VGA. PCnet works after an ODM `busio=0x01000000` fix. | Same as upstream, plus the OFW source (device tree and residual data for AIX) |
| **QEMU 2013 "43p" series (Hervé Poussineau)**, unmerged | https://lists.libreplanet.org/archive/html/qemu-ppc/2013-05/msg00016.html (and lore.kernel.org thread "ppc/prep: add IBM RS/6000 43p machine") | Abandoned | **7248 43P**: MPC105 + i82378 at slot 11 + `ibm_43p.cfg` (i8042, pc87312 cfg 12, pcnet, m48t59 at 0x74, 2× IDE) | OpenBIOS (stalls) and **IBM P93H1904.IMG** | IBM ROM booted from an IDE PReP partition only. No CD, floppy or network boot; no video (an S3 was "expected"); MPC105 memory controller incomplete. | **The only 7248-specific emulator code ever written.** Worth retrieving from the list archive as a reference for the MPC105 + IBM ROM interplay. |
| **MAME** (local `/home/dani/repos/mame`, May 2026) | `src/mame/ibm/thinkpad8xx.cpp`, `src/mame/ibm/rs6000_type7xxx.cpp`, `src/mame/motorola/powerstack.cpp`, `src/mame/be/bebox.cpp` | Skeletons, `MACHINE_NOT_WORKING`. Nothing for the 43P, 7248, Power Series or 6050/6070. | `tpad850` ThinkPad 850 ("Dakota" ROM 91G0610/91G1671, MPC105, 603e). The driver comment says it "has no chance of running until MAME's PowerPC core supports little-endian". `rs6k7009` (MCA 601, skeleton). `powerstk` Motorola PowerStack II (no CPU even instantiated). `bebox` (dual 603, MPC105, *working*). | n/a | Nothing PReP boots | **`bus/lpci/mpc105.cpp`** (MPC105 bridge as used by BeBox). `video/pc_vga_s3.cpp` has **`S3_VISION864_VGA`**. `machine/53c810.cpp` (`LSI53C810`, simpler than QEMU's). `bus/pci/ncr53c825.cpp`. `pic8259`, `pit8253`, `am9517a`, `8042kbdc`, `mc146818`, `ds128x`, `upd765`/`pc_fdc`, `ad1848`. Softlists: `hash/thinkpad8xx.xml` (AIX 4.1.5, AIX 4 TP850, OS/2 Warp PPC, Solaris 2.5.1 PPC, NT 3.5 PPC with ARC 1.51 floppy) and `hash/generic_cdrom.xml` NT 3.51/4.0 entries tagged `prep`. These give SHA-1s for verifying media dumps. |
| **DingusPPC** (not cloned locally) | https://github.com/dingusdev/dingusppc | Active | **Apple only** (PM 6100/7200/7500/G3 Beige, Pippin, ...); no PReP | Apple ROMs | Mac OS. Rairii's fork boots NT 4 on Mac (ARC on Open Firmware). | Not useful for PReP devices. Its 604 interpreter is already the golden model for the local DSPPC604 core. |
| **Rairii / Wack0 "NT on PowerPC Mac"** | https://github.com/Wack0 (maciNTosh / arcfw) | 2024–26, active | Real PowerMac G3/G4, GameCube/Wii. No PReP. | Own ARC firmware | NT 4.0 PPC | Shows NT PPC's needs (LE mode, HAL). Not a PReP reference. |
| **prephv** (Stewart Smith) | https://github.com/stewartsmith/prephv | Hobby, incomplete | Fake **Power Series 440 (6015 "Sandalfoot")** as a POWER8 PowerNV guest | Fake OF client interface running ARC `VENEER.EXE` | Reaches NTOSKRNL, then dies on SDR1 | Little to borrow. Documents the NT PPC boot chain on PReP. |
| **PearPC** | https://pearpc.sourceforge.net | Dead | PowerMac (CHRP-ish OF) | own OF | Mac OS X / Linux | None for PReP |
| **SimOS-PPC / Mambo (IBM internal)** | — | Never public (simos-ppc AIX images were IBM-internal) | Generic PPC / later POWER (CHRP/PAPR) | — | AIX 4.3.x internally | None obtainable |
| **Open Hack'Ware** (old QEMU PReP BIOS) | historical QEMU `pc-bios/ppc_rom.bin` | Removed from QEMU | old `-M prep` | — | Linux/PReP | Shows what a minimal PReP firmware must provide (NVRAM layout, see `PPC_NVRAM_set_params` still in `prep.c`) |
| **OS/2 PPC / "Carolina" emulation** | — | **None found.** A WinWorld thread says neither OS/2 PPC nor NT PPC runs on QEMU. An OSNews commenter planned to extend the 40p fork for all PReP OSes; no follow-up found. | — | — | — | — |
| **Ghidra / IDA projects of IBM PReP ROMs** | — | **None public found.** A VOGONS thread discusses the 40p/43p ROMs (the 43P ROM has an interpreter and dictionary; the 40P ROM has no Forth). | — | — | — | Our own `firmware_analysis.md` is ahead of anything public |
| "ppcemu", "Darkstar", "Sandalfoot emulator" | — | Nothing relevant found under these names | | | | |

Non-emulator code that documents the Carolina hardware:

| Source | What it gives us |
|---|---|
| **Linux 2.6.26 `arch/ppc/platforms/prep_pci.c` and `prep_setup.c`** (copied to `scratch/downloads/linux-2.6.26-prep/`) | **Carolina-specific code.** Planar IDs at port 0x852: **0xF4–0xF7 = 7248 (SCSI)**; 0xF0–0xF3 = PS 830/850 (IDE); 0xFC = Sandalfoot 40P; 0xD1–0xD5 = Tiger1 43P-140. L2 enable (`port 0x81C \|= 0xC0`) and L2 info port 0x80D. Equipment register 0x80C bits. Power management (Signetics 87C750 behind the "Utah" ASIC, nibble protocol at 0x82A). PCI IDSEL→IRQ map: **slot 11 FireCoral (PCI-ISA), 12 Ethernet INTD, 14 S3 INTD, 16 NCR 53C810 INTC, 13/18/22 PCI slots**, all routed to ISA **IRQ 15**. 8259 ELCR: IRQ 10, 13 and 15 level-triggered (`0xA4` high mask). |
| **NetBSD/prep** (`sys/arch/prep`, `sys/dev/ic/ibm82660reg.h`) | Supports the 7248 and the 6050/6070 through **residual data** (`residual.c`). A good model of what an OS reads from the firmware. |
| PReP spec 1.1, `RESIDUAL.H`, `PNP.H`, PReP NVRAM spec (downloaded, Part B) | Residual-data and NVRAM formats AIX/NT/Linux consume |

### A.2 QEMU `40p` in detail (local source, QEMU 11.1.2)

**Device list (`ibm_40p_init`)**

| Device | QEMU type | Location / IRQ | 7248 equivalent |
|---|---|---|---|
| CPU | `604` (6xx bus only), TB 100 MHz (fw_cfg reports 1 GHz TB freq) | — | 604 @100/120/133 MHz (66 MHz bus) |
| ROM | 1 MiB at 0xFFF00000 (ELF or raw) | — | 512 KiB flash (two 512 KiB sockets per redbook) |
| Host bridge | `raven-pcihost` (Motorola Raven, **1057:4801**), PCI dev 0 | — | **MPC105 Eagle (1057:0001)**; different config registers, same PReP CPU map |
| PCI-ISA bridge | `i82378` (Intel SIO, 8086:0484 rev 3), devfn 11:0. Contains 2× i8259, i8254 PIT (+PC speaker), `i82374` DMA. | INTR → CPU INT | **IBM "FireCoral"** at IDSEL 11 (Intel-SIO-compatible per redbook) |
| System I/O | `prep-systemio`: 0x92 (soft reset, LE bit; LE → "not supported", VM paused), 0x808 HD LED, 0x80C equipment (=0xC0), 0x810/0x812 password protect, 0x814 L2 invalidate, 0x818 keylock, 0x81C system control, **0x850 I/O map type**, **0x852 planar ID (=0xFC)**. Parity register at 0xBFFFEFF0. | ISA | Same IBM register family (Linux confirms 0x803/0x804/0x80C/0x80D/0x82A/0x852/0x8C0). The 7248 needs planar ID **0xF4–0xF7**. |
| Memory controller | `rs6000-mc`: 6 SIMM sockets (8 or 32 MiB pairs), 0x803 SIMM ID, 0x804 presence, 0x820 size programming, 0x841 parity status | — | On Carolina the memory controller is inside the **MPC105** (its config registers 0x80–0xAF). The ISA SIMM ports may still exist (Linux comment: "present in the IBM reference design"). |
| RTC | `mc146818rtc`, base year 1900, CMOS checksum 0x6AA9 at 0x2E/0x3E | 0x70 | PC-compatible RTC on the X-bus |
| NVRAM | `isa-m48t59` (8 KiB) at **0x74** | 0x74/0x75/0x77 | 4 KiB NVSRAM via 0x74/0x75/0x76 |
| Audio | `cs4231a` at **0x830**, IRQ 10 | | **CS4232** at 0x830–0x833 (IRQ 10 is level in the Linux Carolina table) |
| Super I/O | `pc87312`, config 12, index port 0x398. FDC, 2× 16550, LPT, IDE, and an i8042 kbd/mouse from `isa-superio`. | | **PC87312**: the 7248 v1.12 ROM contains `NSC PC87312`, `ReadPC87312Regs`, `WritePC87312Regs`, `Default87312`. (`hardware_inventory.md` draws "PC87332"; the firmware strings favour the 87312.) |
| SCSI | `lsi53c810` devfn 1 | ISA IRQ 13 | **NCR 53C810 at IDSEL 16**, INTC → IRQ 15 |
| Video | std VGA (Bochs VBE). Comment: "XXX: s3-trio at PCI_DEVFN(2, 0)". | | **S3 Vision864 + SDAC, 2 MB** (IDSEL 14) |
| Ethernet | `pcnet` devfn 3 | | **AMD Am79C970 PCnet-PCI** (IDSEL 12) |
| PCI interrupts | All 4 PCI INTx are OR-ed into ISA **IRQ 15** (PReP 6.1.6). `raven_map_irq` swizzles by slot. | | Same: IRQ 15 for all on-board PCI |
| fw_cfg | 0xF0000510 (QEMU-only, for OpenBIOS) | | n/a |

**CPU physical memory map (raven.c + prep.c)**

| Range | Function |
|---|---|
| 0x0000_0000 – 0x7FFF_FFFF | DRAM (SIMMs placed by rs6000-mc) |
| 0x8000_0000 – 0xBF7F_FFFF | PCI/ISA I/O space. Default **non-contiguous** mode (port 0x850 bit 0 set at reset): the 8 MiB window maps each 4 KiB page to 32 bytes (`(a & 0x1F) \| ((a & 0x7FF000) >> 7)`). Contiguous mode: 64 KiB. The firmware hands the OS **contiguous** mode. |
| 0x8000_0CF8 / 0CFC | PCI config index/data (type 1) |
| 0x8080_0000 – 0x80BF_FFFF | PCI config, direct-IDSEL (type 0): the device number is the lowest set address bit ≥ 11 |
| 0xBFFF_EFF0 | parity/error status (reads 0) |
| 0xBFFF_FFF0 | **PCI interrupt acknowledge** (returns the 8259 vector) |
| 0xC000_0000 – 0xFEFF_FFFF | PCI memory (VGA framebuffer etc.) |
| 0xFFF0_0000 – 0xFFFF_FFFF | Boot ROM |
| PCI bus-master view | 0x8000_0000 → system RAM 0; 0 → PCI memory (DMA through Raven) |

This matches the IBM 660 manual's table 3-2 and PReP "map A", which the MPC105 also implements.
On a real MPC105 the contiguous/non-contiguous switch lives in the bridge, not the ISA port.

**Firmware and AIX status under QEMU**
- Tarasenko (blog, 2019-04): the IBM ROM P12H0456 "can not boot AIX". He used it only to tell
  QEMU bugs from OFW bugs. AIX needs the device tree/residual data built by his OFW.
- Working recipe: `qemu-system-ppc -M 40p -bios q40pofw-serial.rom -serial telnet::4441,server
  -hda aix.qcow2 -cdrom aix-5.1-cd1.iso -vga none -nographic`, then `boot cdrom:2` (sometimes
  `boot cdrom:2 -i`) at `ok`.
- tenox publishes a ready-made image, `os/aix/Virtual/aix433.qcow2.lz` (343 MB). Its launch
  script `aix433.ksh` uses `-M 40p -bios q40pofw-serial.rom`, 192 MB RAM and PCnet.
- Known problems:
  - lft0 respawn
  - PCnet `busio` ODM fix needed
  - no AIX graphics
  - more than 7 SCSI disks fails
  - 5.1 copy phase stalls around 93% for a long time
- Sources:
  - https://lists.nongnu.org/archive/html/qemu-ppc/2019-04/msg00120.html
  - https://tyom.blogspot.com/2019/04/aixprep-under-qemu-how-to.html
  - https://virtuallyfun.com/2019/04/22/installing-aix-on-qemu/
  - https://virtuallyfun.com/2022/11/08/revisiting-aix-4-3-on-qemu/
  - https://astr0baby.wordpress.com/2019/04/26/running-aix-5-1-on-qemu-system-ppc/
  - QEMU 2015/2017 40p series on qemu-ppc

### A.3 Relevant local repos (`/home/dani/repos`)

| Repo | Relevance |
|---|---|
| `qemu` (v11.1.2) | Reference for the PReP map, i82378/8259/8254/82374, prep-systemio, rs6000-mc, pc87312, **lsi53c895a (53C810 with SCRIPTS)**, pcnet, cs4231a, m48t59, mc146818, fdc, i8042, IDE |
| `mame` | **mpc105**, **S3 Vision864**, 53c810, 8259/8254/8237, 8042, mc146818, upd765, ad1848; tpad850/bebox drivers; PReP softlists with media SHA-1s |
| `MacPPC7300_MiSTer` | **DSPPC604**: a verified PowerPC 604 RTL core (integer, FPU, MMU/BAT/TLB, caches, exceptions), lockstepped against dingusppc and real-604 vectors. Directly reusable as the 7248 CPU. **Caveat:** MSR[LE]/[ILE] are "stored and ignored", which is fine for AIX but NT/OS/2/Solaris PPC need real little-endian mode. Also has the MiSTer SDRAM/DDR3 plumbing. |
| `ApplePippin_MiSTer` | PPC603 Pippin work and disassembler tools (ROM-analysis workflow) |
| `Template_MiSTer`, `Main_MiSTer`, `Linux-Kernel_MiSTer` | Framework. The MiSTer kernel has no PReP code (removed from Linux after 2.6.26). |
| `BlueSCSI-v2` | SCSI target behaviour reference (CD-ROM/disk emulation for the 53C810 side) |
| `ss_openbios` | OpenBIOS (SPARC-focused fork). OpenBIOS has PReP bits, but a weak base for AIX. |
| `MacQuadra800_MiSTer`, `MacLC_MiSTer`, `SGIIndy_MiSTer`, `HP9K385`, `Sun-2_MiSTer` | Sibling MiSTer machine cores (SCSI/video patterns) |
| `powerpc-ports`, `Retro68*`, `mrustc-ppc` | PPC toolchains (handy for writing test ROMs) |
| `scratch/IBMPowerPC/` (this project) | Already holds Power Series/ThinkPad firmware (`p8x0_10x.exe`, `ros104.exe`, `sms102/126/127`, `7248100.exe/.bin`), ARC loaders, and the PPC redbook. **Note:** `329080.pdf`, `380510-12.pdf` and "43p Service Manual.pdf" are for the **7043**-140 (a different machine), not the 7248. |

---

## Part B: Firmware and OS media

### B.1 Which AIX levels run on the 7248

| OS | 7248 support | Notes |
|---|---|---|
| AIX 4.1.x | Yes. Shipped with AIX 4.1 (announcement ZG95-0253, 1995-06-19, GA 1995-07-07). | 4.1 was the first AIX with PReP/PCI ("rspc"). The 4.1.x levels on the Power Series/ThinkPad CDs (AIX 4 for TP850) also apply. |
| AIX 4.2.x | Yes | |
| **AIX 4.3.3** | Yes, the best-documented level | 4.3.3 bonus packs and updates exist. Proven under QEMU 40p. |
| **AIX 5.1** | Yes; **the last release with PReP (rspc) support**, 32-bit kernel only | IBM's AIX 5.2 announcement excludes "RS/6000, Power Personal Systems, or OEM hardware based on the PReP architecture" and the 601/603. The 43P-150 (7043-150, CHRP) is the oldest 43P that runs 5.2. No source found requiring a specific 5.1 ML for the 7248. Base 5.1 boots on QEMU 40p. Final ML is 5100-09 (tenox has `aix51ml9.tar.lz`). |
| AIX 5.2+ | No | 5.2 CD lacks the PReP boot partition ("Can't open disk label package" on 40p) |
| Windows NT 3.51 / 4.0 (PPC) | Yes, via **ARC firmware floppy** (arc 1.46–1.51) | 7248 is on the NT 4.0 HCL. NT boots `\os\winnt\osloader.exe`. Needs CPU little-endian mode. |
| OS/2 Warp PPC | Officially Power Series 830/850 only (IDE). Not confirmed on the 7248 (M. Kraemer could not install it). | Needs a 2048-byte-sector CD drive; little-endian |
| Solaris 2.5.1 PPC | Yes, with IBM boot floppy "S596P_11" (VOF) | Graphics: on-board S3 864 only |
| Linux/PReP, NetBSD/prep | Yes (IBM7248-HOWTO; NetBSD lists 7248, 6050, 6070) | Small, open, and good for bring-up |

### B.2 fsck.technology: `software/IBM/AIX Install Media/RS6000/`

Sibling directories: AIX 3.2.0 (143 MB), 3.2.5 (1.27 GB), 4.1.3 (443 MB), 4.1.5 (694 MB),
4.2.1 (1.20 GB), 4.3 (380 MB), 4.3.2 (5.6 GB), **4.3.3 (12.8 GB)**, **5.1 (9.5 GB)**, 5.2 (13.3 GB),
5.3 (24.1 GB). Sizes are h5ai "KB" = 1000 bytes; this was checked against Content-Length.
Speed was about 15 MB/s.

**IBM AIX 4.3.3/**

| Path | Size | Status |
|---|---|---|
| `LCD4_0286_06/Disc01.iso` … `Disc04.iso` | 669.0 / 555.7 / 423.6 / 419.4 MB | listed only |
| `LCD4_0286_07 (ISO)/LCD4_0286_07_VOLUME1/LCD4_0286_07_VOLUME1.ISO` | 668,905,472 B | **downloaded** |
| `LCD4_0286_07 (ISO)/…VOLUME2…4` | 587.3 / 422.8 / 418.3 MB | listed only |
| `LCD4_0286_07 (MDF)/Volume 1..4 of 4/*.mdf` | 768.2 / 674.5 / 485.5 / 480.4 MB | listed only (MDF/MDS rips of the same set) |
| `LCD4_0286_07 (MDF)/Bonuspak/` 11-2001 vol 1–2 (597.0 / 407.8 MB), 12-2000 vol 1–2 (562.7 / 520.1 MB); DB2 7.1 starter kit vol 3–4 (739.7 / 723.5 MB); `Disc Scans/DISCS-1..5.png` (≈9 MB each) | | listed only |
| `LCD4_0291_13 (12-2000 Bonus Pack)/AIX_V4.3.3_Bonus_Pack_12.2000_{1..4}_of_4.iso` | 350.2 / 453.0 / 645.9 / 631.2 MB | listed only |
| `LCD4_0995_14 (4.3.3 Update)/aix-4.3.3-5765-c34-Update.iso` | 404.6 MB | listed only |
| `Misc/AIX_4.3.3.3_RS6000_standalone_diagnostics.iso` | 71,303,168 B | **downloaded** |
| `Misc/AIX_4.3.3_Extended_Documentation.iso` | 67.1 MB | listed only |

**IBM AIX 5.1/** (three pressings of the 5-CD set)

| Path | Size | Status |
|---|---|---|
| `LCD4_1061_04/LCD4_1061_04_VOLUME{1..5}.ISO` | 654.0 / 643.3 / 621.6 / 573.9 / 645.4 MB | listed only |
| `LCD4_1061_06/AIX-CD{1..5}.iso` | 640.8 / 643.5 / 630.8 / 586.8 / 671.8 MB | listed only |
| `LCD4_1061_08/Disc01.iso` | 644,055,040 B | **downloaded** (latest pressing) |
| `LCD4_1061_08/Disc02..05.iso` | 643.2 / 630.5 / 586.5 / 671.4 MB | listed only |

No firmware or diagnostics directories exist on fsck.technology apart from the 4.3.3 `Misc` diag CD.

### B.3 tenox.pdp-11.net

**`/os/aix/`** top level: 1.1rt, 1.2ps2, 1.3ps2, 2.1rt, 3.2, 4.1, 4.1ans, 4.1moto, **4.1tpps**,
4.2, 4.3, 4.3moto, **4.3ps**, 5.1, 5.1ia64, 5.2, 5.3, 6.1, 7.1, 7.2, 7.3, Documentation, Fixes,
Software, Sources, **Virtual**.

| Dir | Relevant contents (size) |
|---|---|
| `4.1/` | `AIX 4.1.5 CD1.rar` 382M, `CD2.rar` 44M; `aix415-inst1/2.rar` (same); `aix_4.1.5r2.img.lz` 218M; `AIX 4.1.4.toast.sitx` 262M; pexphigs415 62M, valueoption415 69M; swdevsol/ (4 rars, 160–302M); Documentation (4.1 install guide 6.6M, device-driver guide 1.1M); aixpds/ (hundreds of freeware `.tar.lz`) |
| **`4.1tpps/`** (AIX 4 for ThinkPad Power Series 850) | `aix-v4-cd1.rar` 407M, `aix-v4-cd2.rar` 146M (also `.dmg.lz`); `TP850.AIX.Ver4.pdf`; Program Pack 143M; Personal Conferencing 4.8M; VoiceType 16M. *Same PReP AIX 4.1 family as Carolina.* |
| `4.1moto/`, `4.3moto/`, `4.3ps/` | Motorola/Bull PReP AIX (4.1.4 Server 335M, 4.1.1r4 337M, AIX432 ARM04 310M, "Bull AIX 4.3.2 Estrella" 310M). These **do not boot on IBM PReP** and the reverse is also true. `4.3ps/` holds two sunhelp mail-archive pages on Motorola PowerStack. |
| `4.2/` | `IBM AIX 4.2.1.rar` 737M; `aix421-for-5765-c34.rar` 633M; `42 Update 5765-C34.rar` 610M; bonus pack 99M |
| `4.3/` | `AIX_433_LCD4_0286_06.rar` 2.3G; `IBM AIX 4.3.3 10-2000.rar` 945M; `AIX_V4.3.3_10.2000.rar` 1.0G; bonus packs (1.0G, 507M); `AIX_V4.3_11.2000_update_CD.rar` 214M; `AIX_4.3.3.3_RS6000_standalone_diagnostics.rar` 19M; docs 21M; `AIX 4.3.3 with BullFreeware Archive.zip` 2.9G; 50+ redbook PDFs |
| `5.1/` | `nrg/aix_5.1L_{1..5}_of_5.nrg*.lz` (322/259/215/150/376M); `updates/aix51ml9.tar.lz` 488M, `aixpost51ml9.tar.lz` 72M; `5100-04-2004-04.rar` 1.2G; Expansion Pack 11-2004 171M; docs incl. `51_base_relnotes.pdf`, `5107_base_relnotes.pdf` |
| **`Virtual/`** | **`aix433.qcow2.lz` 343M** (installed AIX 4.3.3 for QEMU 40p) and `aix433.ksh` (launch script, read) |
| `Fixes/` | `v4.rar` 21G, `v3.rar` 2.7G, `byCompID.rar` 34G |
| `Software/` | gcc, Java, Firefox, Toolbox 2002/2004, RPMs, Quake 1/2 for AIX, etc. |

**`/hw/ibm/rs6000/`** (the hardware archive; the osarchive.org links redirect here)

| Path | Contents |
|---|---|
| `7248_hardware_announcement.pdf` 208K | **downloaded** |
| `PREP/` | `arc148.exe`, **`arc151.dd.lz`** (NT ARC 1.51 floppy), `ARC151.IMG.lz`, `P12H0456.IMG.lz` (40P), `sms128.dd.lz`, **`fw.img.lz`** (unknown PReP ROM), `aix3cisa.dd.lz`, `sol_251_motorola.img.lz`, `firm_ppcbug_19.bin.lz` (Motorola), `rs6k7249.rar` |
| `PREP/ppcbbs/` (mirror of IBM's old PC BBS `ftp.pc.ibm.com/pub/pccbbs/powerpc`) | **`7248_110.exe.lz`** (7248 firmware 1.10), `p8x0_106..110` (Power Series 8x0 ROM updates), `p4x0_128` (PS 440), `ros104`, `sms102/126/127`, `arc146..151`, `nt40ppcs.exe`, `3comenet.exe`, `ientdd.bin` |
| `PREP/PRePSpecs/` | **PReP Spec 1.1**, **RESIDUAL.H/PDF**, PNP.H, **nvram_p.pdf**, endian.pdf, pcidma.pdf, L2 cache design, etc. (most downloaded) |
| `Firmware/` | **`43p-133.rar`** 1.0M (7248-133 firmware, downloaded), `40p.rar` 4.3M, `43p-140.rar`, 7043-140/150 firmware, GXT110P ROM, `ps-2.kev009.com-rs6000-firmware.rar` **5.2G** (to fetch if needed) |
| `ThinkPad_800_PoweSeries/` | `IBM_NTWKS351_PMZ_PPC_TP8x0.iso.lz` 51M (NT 3.51 PPC), ThinkPad 820 Program Pack 170M, redbooks, `tp800-files.rar` 16M |
| `Documentation/` | "43p Service Manual.pdf" (7043, not 7248), 7043 guides, Diagnostic Information for Multiple Bus Systems, LED code lists |

### B.4 IBM's own public FTP (`public.dhe.ibm.com`) is still online

| Path | Contents |
|---|---|
| `rs6000/firmware/7248-43p/` | `README.1st` (1.12beta, SMS 1.07), **`beta112.img`** 512K (= P93H7075 v1.12, byte-identical to `scratch/7248-43p_Firmware_update.img`), `flash.6xe` |
| `rs6000/firmware/7020-40p/` | `P12H0456.IMG` (40P v1.29, the QEMU test ROM), `sms128.dd` (SMS 1.28 floppy), `flash.6xe`, README with resident-monitor passwords |
| `rs6000/firmware/emulation/` | `IPLROM.image.9705071651` (NIM IPL-ROM emulation for AIX 4.x, MCA boxes) |
| `rs6000/firmware/NT_arc_image/` | README pointing to `ftp.pc.ibm.com/pub/pccbbs/powerpc/arc*` (mirrored on tenox) |
| `rs6000/PPC_support/660_bridge/` | **`660umf5.PDF`** (IBM27-82660 user manual, downloaded), `660umf6.ps` 13M, errata, FAQ timing diagrams, IBIS |
| `rs6000/PPC_support/reference_designs/` | harley, zapatos (schematics, gerbers), longtrail (CHRP) |
| `rs6000/PPC_support/misc`, `app_notes/` | Odyssey MCM/planar, AN001–AN012 (incl. `an011_660_FAQ`) |

The 7248 README procedure:
1. Boot with no SMS diskette and press F4 at the keyboard icon.
2. At the SMS-diskette animation, type the resident-monitor password `eatabug`.
3. Insert the image floppy and run `flash -a`.
4. To soft-load an image without flashing it, type `P*.IMG` at the `A:>` prompt.

The **7248 has no SMS in ROM**: the menus come from an SMS diskette (v1.07, or 1.26/1.27 found
locally). F1 gives graphical SMS, F4 text, F5/F6 forces floppy boot. The default boot order is
floppy → CD → SCSI disk (first PReP type-0x41 partition).

Other firmware levels named in sources:
- P93H1904.IMG (used in the 2013 QEMU 43p patch)
- P93H4940.IMG v1.11 (1996-11-14)
- P93H7075.IMG v1.12 (1997-03-31, the latest)
- SMS 1.07 (P/N 8133689)

### B.5 Files downloaded in this task

All files are under `/home/dani/repos/IBMRS6K42p/scratch/downloads/`. Nothing was extracted or
executed.

| File | Bytes | MD5 | Source URL |
|---|---|---|---|
| `fsck.technology/aix433/LCD4_0286_07_VOLUME1.ISO` | 668,905,472 | 452465c1d17772fc3bd35de9af93b6e4 | https://fsck.technology/software/IBM/AIX%20Install%20Media/RS6000/IBM%20AIX%204.3.3/LCD4_0286_07%20%28ISO%29/LCD4_0286_07_VOLUME1/LCD4_0286_07_VOLUME1.ISO |
| `fsck.technology/aix51/LCD4_1061_08_Disc01.iso` | 644,055,040 | 84eba74e309987d095c99a9e7afe6ff4 | https://fsck.technology/software/IBM/AIX%20Install%20Media/RS6000/IBM%20AIX%205.1/LCD4_1061_08/Disc01.iso |
| `fsck.technology/diag/AIX_4.3.3.3_RS6000_standalone_diagnostics.iso` | 71,303,168 | 6a0cca1afb99127ed093279149481880 | …/IBM%20AIX%204.3.3/Misc/AIX_4.3.3.3_RS6000_standalone_diagnostics.iso |
| `public.dhe.ibm.com/7248-43p/beta112.img` | 524,288 | a064f6f3116026ddc0836050f16bb0f8 | https://public.dhe.ibm.com/rs6000/firmware/7248-43p/beta112.img |
| `public.dhe.ibm.com/7248-43p/flash.6xe` | 17,244 | 8d27c6ca3f178eb58c3e4081638d78a7 | …/7248-43p/flash.6xe |
| `public.dhe.ibm.com/7248-43p/README.1st` | 1,778 | b950131ca6926f9824138b021323e47e | …/7248-43p/README.1st |
| `public.dhe.ibm.com/7020-40p/P12H0456.IMG` | 524,288 | 5b3e77924375e7a99784ed1edbd133b7 | https://public.dhe.ibm.com/rs6000/firmware/7020-40p/P12H0456.IMG |
| `public.dhe.ibm.com/7020-40p/sms128.dd` | 1,474,560 | 5e54d140277be6afaf1261d137fe8c42 | …/7020-40p/sms128.dd |
| `public.dhe.ibm.com/7020-40p/flash.6xe` | 16,900 | eabad8ebb9d6413ab5b0aa5caef4f344 | …/7020-40p/flash.6xe |
| `public.dhe.ibm.com/7020-40p/README.1st` | 2,679 | eb17551fd75a0def74089130cdb1d96b | …/7020-40p/README.1st |
| `public.dhe.ibm.com/emulation/IPLROM.image.9705071651` | 623,391 | 7c8b0fdaf3a72c9ede17d91317ccfb38 | https://public.dhe.ibm.com/rs6000/firmware/emulation/ |
| `public.dhe.ibm.com/emulation/READ.ME` | 930 | d8cd5e3ab81660291c07ae7bacb7dfe2 | same dir |
| `public.dhe.ibm.com/NT_arc_image/README` | 300 | c1586fd54ef7d72d800d433430026c9a | https://public.dhe.ibm.com/rs6000/firmware/NT_arc_image/README |
| `public.dhe.ibm.com/660_bridge/660umf5.PDF` | 2,207,506 | 14c91e3ac7bf8919768912c612c3827a | https://public.dhe.ibm.com/rs6000/PPC_support/660_bridge/660umf5.PDF |
| `tenox.pdp-11.net/firmware/43p-133.rar` | 1,034,033 | 5fdbcba9e08bc8ae6780d30b598ccb3f | https://tenox.pdp-11.net/hw/ibm/rs6000/Firmware/43p-133.rar |
| `tenox.pdp-11.net/firmware/7248_110.exe.lz` | 1,020,290 | d53534ef492534aea099de02f8f011d4 | https://tenox.pdp-11.net/hw/ibm/rs6000/PREP/ppcbbs/7248_110.exe.lz |
| `tenox.pdp-11.net/firmware/arc151.dd.lz` | 244,084 | 2295afbaa47874e27fc60e9f2bbd936a | https://tenox.pdp-11.net/hw/ibm/rs6000/PREP/arc151.dd.lz |
| `tenox.pdp-11.net/firmware/fw.img.lz` | 321,409 | 3db22c34f4320666040ffc5b4e53304b | https://tenox.pdp-11.net/hw/ibm/rs6000/PREP/fw.img.lz |
| `tenox.pdp-11.net/docs/7248_hardware_announcement.pdf` | 213,229 | f0baa5d2956636366532be7179be10de | https://tenox.pdp-11.net/hw/ibm/rs6000/7248_hardware_announcement.pdf |
| `tenox.pdp-11.net/PRePSpecs/PREP_Spec_1.1.pdf` | 6,926,532 | 150e88356792c8e4b8a9e6ad44b07d34 | https://tenox.pdp-11.net/hw/ibm/rs6000/PREP/PRePSpecs/PREP%20Spec%201.1.pdf |
| `tenox.pdp-11.net/PRePSpecs/RESIDUAL.H` | 14,072 | 40b5cd14c2bddcdfad53d460d295af4e | …/PRePSpecs/RESIDUAL.H |
| `tenox.pdp-11.net/PRePSpecs/RESIDUAL.PDF` | 193,197 | 89c528206decd5dae108b19d10975960 | …/PRePSpecs/RESIDUAL.PDF |
| `tenox.pdp-11.net/PRePSpecs/PNP.H` | 28,601 | 3a939138369aca57359ed41960901672 | …/PRePSpecs/PNP.H |
| `tenox.pdp-11.net/PRePSpecs/nvram_p.pdf` | 54,438 | 9840097da0cdaf6d4cfb9f3eba634747 | …/PRePSpecs/nvram_p.pdf |
| `tenox.pdp-11.net/PRePSpecs/endian.pdf` | 33,034 | 4fe7f9fb08254782905dd05792ae7c8f | …/PRePSpecs/endian.pdf |
| `tenox.pdp-11.net/PRePSpecs/pcidma.pdf` | 23,215 | 55910ee49de7b2c962887ddde4f587ab | …/PRePSpecs/pcidma.pdf |
| `tenox.pdp-11.net/PRePSpecs/README`, `README.1` | 4,507 / 4,715 | 0bb9df07… / c611572d… | …/PRePSpecs/ |
| `github-artyom-tarasenko-openfirmware/40p-20190413/q40pofw-serial.rom` | 630,644 | 6afab1e6ffb2af7abb7f3de566f2a2ac | https://github.com/artyom-tarasenko/openfirmware/releases/download/40p-20190413/q40pofw-serial.rom |
| `github-artyom-tarasenko-openfirmware/40p-20190413/q40pofw-vga.rom` | 630,628 | 4d2efda0fcb88190b809c147e3d3d5e2 | …/40p-20190413/q40pofw-vga.rom |
| `linux-2.6.26-prep/prep_pci.c` | — | 471eb650fce5d71bbe03abe261aec57e | https://raw.githubusercontent.com/torvalds/linux/v2.6.26/arch/ppc/platforms/prep_pci.c |
| `linux-2.6.26-prep/prep_setup.c` | — | d642b9447b87e625307ea7bd562c3912 | …/arch/ppc/platforms/prep_setup.c |

### B.6 To fetch later (not downloaded)

- AIX 4.3.3 volumes 2–4 (fsck `LCD4_0286_07 (ISO)`, ≈1.43 GB total). Needed only to install
  more than BOS (volume 1 holds the BOS install).
- AIX 5.1 `LCD4_1061_08/Disc02..05` (≈2.53 GB).
- 4.3.3 update CD (405 MB) and bonus packs.
- tenox `os/aix/Virtual/aix433.qcow2.lz` (343 MB): a pre-installed AIX 4.3.3 disk for QEMU 40p.
  The quickest way to get AIX traces out of QEMU.
- tenox `4.1tpps/aix-v4-cd1.rar` (407 MB) and `4.1/AIX 4.1.5 CD1.rar` (382 MB), for 4.1-era testing.
- tenox `Firmware/ps-2.kev009.com-rs6000-firmware.rar` (5.2 GB), a large RS/6000 firmware dump.
  Exceeds the size limit.
- SMS diskette 1.07 for the 7248 (P/N 8133689; Kraemer's list). The local `sms126/127.exe` are
  Power Series SMS; check whether they accept a 7248 planar.
- P93H4940.IMG (v1.11). The 1.12 image is already in hand.
- NT 4.0 PPC, OS/2 Warp PPC and Solaris 2.5.1 PPC CDs: WinWorldPC (OS/2 PPC; NT) and the
  macintoshrepository OS/2 PPC entry. Verify dumps against the MAME softlist SHA-1s in
  `hash/thinkpad8xx.xml` and `hash/generic_cdrom.xml` (`prep` filter).

---

## Recommendations

### Best reference per device

| 7248 block | Best reference | Second source / spec |
|---|---|---|
| CPU (PPC604) | **Local DSPPC604** (`MacPPC7300_MiSTer/rtl/DSPPC604`). Add MSR[LE]/[ILE] little-endian address munging before NT/OS/2. | dingusppc / QEMU `target/ppc` (604 BATs, TB) |
| Host bridge + memory controller + L2 (MPC105 "Eagle") | **MAME `bus/lpci/mpc105.cpp`** (registers), **QEMU `raven.c`** (PReP CPU map, IACK at 0xBFFFFFF0, contiguous/non-contiguous I/O, bus-master window 0x80000000) | Motorola MPC105 user's manual (not yet downloaded; NXP datasheet mirrors exist). Hervé's 2013 `mpc105` QEMU patch. The 660 manual only if real hardware shows 1014:0037. |
| PCI-ISA bridge ("FireCoral", SIO-compatible): 2×8259, 8254, DMA | **QEMU `i82378.c`, `i8259`, `i8254`, `i82374`** | MAME pic8259/pit8253/am9517a. Intel 82378ZB datasheet. Linux Carolina ELCR (IRQ 10/13/15 level). |
| IBM system registers (0x92, 0x800–0x8FF, planar ID 0x852 = 0xF4–0xF7) | **QEMU `prep_systemio.c` + `rs6000_mc.c`** | **Linux `prep_setup.c`** (L2 0x80D, PM 0x82A / 87C750, equipment bits). The ROM itself (`firmware_analysis.md`). |
| Super I/O (PC87312: FDC, 2×UART, LPT, IDE) and 8042 | **QEMU `pc87312.c` + `isa-superio`** (config 12 is the PReP default) | MAME `upd765`/`pc_fdc`, `8042kbdc`, `ins8250` |
| SCSI NCR 53C810 | **QEMU `lsi53c895a.c`** (full SCRIPTS engine; AIX 4.3.3/5.1 proven against it) | MAME `machine/53c810.cpp`. `BlueSCSI-v2` for the target side. |
| Video S3 Vision864 + SDAC (E15) | **MAME `video/pc_vga_s3.cpp` (`S3_VISION864_VGA`)** | QEMU has no S3 (std VGA only), and AIX cannot use QEMU's VGA. AIX's 7248 driver expects the real E15/864. |
| Ethernet Am79C970 PCnet-PCI | **QEMU `pcnet.c`/`pcnet-pci.c`** (AIX `ent` driver works) | MAME has none for PCI |
| Audio CS4232 | **QEMU `cs4231a.c`** (WSS core at 0x830, IRQ 10) | MAME `ad1848`. Low priority. |
| RTC + 4 KB NVRAM (0x70, 0x74/0x75/0x76) | **QEMU `mc146818rtc` + `m48t59-isa`** (index ports at 0x74). Carolina uses 0x76 as data. | PReP NVRAM spec (`nvram_p.pdf`), `RESIDUAL.H` |
| Interrupt routing | PReP: all PCI INTx → ISA IRQ 15 via 8259, vector by IACK read at 0xBFFFFFF0 (QEMU raven) | Linux `ibm8xx_pci_IRQ_map` (Carolina) |
| Firmware/OS interface (residual data, device tree) | **IBM ROM P93H7075 (v1.12)** run unmodified from reset | Tarasenko OFW (q40pofw) as a known-good alternative that boots AIX; RESIDUAL.H, NetBSD `residual.c` |

### Most promising first bring-up path

1. **Golden traces first, in QEMU.** Run upstream `qemu-system-ppc -M 40p -bios q40pofw-serial.rom`
   with the downloaded AIX 4.3.3 volume 1 (or tenox's `aix433.qcow2`). Record AIX's
   rspc-kernel accesses to the 0x80000xxx ports, the 53C810 and the PCnet. Also run the IBM 40P ROM
   `P12H0456.IMG` (NetBSD floppy) to watch how IBM firmware probes a PReP board. This costs nothing
   and the AIX side is directly reusable; only the bridge and planar IDs differ.
2. **FPGA, stage 1: the IBM 7248 ROM from reset.** Use DSPPC604 + MPC105 + FireCoral (8259/8254/DMA)
   + system ports (planar 0xF4) + PC87312 + RTC/NVRAM + 8042 + S3 Vision864 text mode. The goal is
   the POST icon row (keyboard → … → audio). The ROM is self-decompressing (see `firmware_analysis.md`)
   and has no SMS, so it needs a floppy (SMS 1.07 diskette) for menus. Its resident monitor
   (F4 + `eatabug`) is a very early, useful milestone.
3. **Stage 2: add the 53C810 + SCSI CD.** Boot the **AIX 4.3.3 standalone diagnostics CD** (71 MB,
   downloaded) first. It is a small AIX kernel + RAM filesystem boot that exercises residual data,
   SCSI, console and interrupts without an install.
4. **Stage 3: AIX 4.3.3 volume 1 (LCD4-0286-07) BOS install** onto a SCSI disk image. Firmware
   default boot order is floppy → CD → disk, so no SMS is needed if the CD is present. Use the S3
   console or a serial tty0. Expect the same lft0/PCnet quirks seen in QEMU. AIX 5.1
   (LCD4-1061-08 Disc01) is the second target: it was proven first under QEMU, but it is heavier.
5. Optional cheaper intermediate targets: NetBSD/prep or Linux/PReP boot floppies (the 7248 is
   explicitly supported and the source is open). Defer NT 4.0 (ARC 1.51 floppy), OS/2 PPC and
   Solaris 2.5.1 until little-endian mode works in DSPPC604.
