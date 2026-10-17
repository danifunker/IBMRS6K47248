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
