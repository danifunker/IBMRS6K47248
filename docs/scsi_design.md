# NCR 53C810: what the firmware uses, and an RTL design

The on-board SCSI of the 7248 (AIX `scsi0`): an NCR (later Symbios/LSI)
53C810, PCI 1000:0001, on bus 0 device 16 (IDSEL by device number), its
INTA# pin wired to the board's INTC#, routed like every PCI interrupt to
ISA IRQ 15, level-triggered (`hardware_inventory.md` Appendix B). The
Power Series 830/850 (planar IDs F0-F3) have no 53C810. This note is
milestone M5's groundwork (`plan.md`): what the firmware does with the
chip, what AIX will add, the reference models, the SCSI targets already
written for other cores, and a design in this repository's style.

Sources: the firmware's SCSI driver in the v1.12 RAM image
(`firmware/images/7248_v1.12_main_ram_image_at_00000000.bin`,
`firmware/disasm/v1.12_ram_image_00000000.annotated.s`,
`symbols_v1.12_ram.txt`), read with `firmware/tools/annotate_module.py`
(section 1.1). Section 1 is from the disassembly, with the PC given.
Section 2 is general knowledge and marked so. Sections 3 and 4 are from
the local clones (`/home/dani/repos/qemu` at 11.1.2, `/home/dani/repos/mame`,
the other cores' trees).

Contents:

1. The firmware's SCSI driver
2. What AIX 4.3.3 and 5.1 would need beyond it (general knowledge)
3. Reference models (QEMU, MAME, the HP 9000/715 core's 53C710)
4. SCSI target RTL to reuse
5. A proposed RTL design
6. The Main_MiSTer side
7. Size, roughly
8. Open questions

---

## 0. Summary

- The driver is a separately linked module in the RAM image, "R2/scsi_ctl.c,
  rosipl_601" (IBM's ROS IPL SCSI code, 1993), with its own TOC. It finds
  the chip by its PCI ID (and also accepts a 53C825, 1000:0003), sets
  **BAR0 (I/O) to 0x2000_0000** (CPU 0xA000_0000), the **command register
  to 0005 (I/O + bus master)**, the latency timer to 0x80 and the
  interrupt line to 15. It **never programs or enables BAR1 (memory)**.
  Every register access is an 8- or 32-bit I/O access at 0xA000_00xx.
- It drives the chip **entirely with SCRIPTS**, 267 words that run from
  the module's own data (patched once, then byte-swapped to little-endian
  in place): SELECT with ATN, block moves (direct and **table indirect**
  off DSA), WAIT DISCONNECT, **WAIT RESELECT**, SET/CLEAR ACK/ATN/TARGET,
  register read-modify-writes and a move to SFBR, JUMP and INT with phase,
  wait-for-phase and data (with mask) compares, **relative jumps**,
  **INTFLY**, and a **MEMORY MOVE** (diagnostics only). No CALL/RETURN,
  no LOAD/STORE, no indirect addressing, no CHMOV.
- The script **interrupts the CPU at each step** of a command (INT
  0xDDDD00nn before the identify message, the CDB, the data, after the
  status, after the message): the CPU looks, then restarts the chip by
  writing DSA and DSP. A plain READ is about seven interrupts, plus an
  interrupt on the fly after the data. Messages it understands: COMMAND
  COMPLETE, SAVE/RESTORE POINTERS, DISCONNECT (it then waits for the
  reselection in SCRIPTS), MESSAGE REJECT, IGNORE WIDE RESIDUE, and the
  extended SDTR, WDTR (825) and MODIFY DATA POINTER. On the first command
  to each target it sends **IDENTIFY + SDTR** (period 0x32, offset 0).
- It is **interrupt driven** (IRQ 15 through the firmware's registrar,
  `SCSI_int_hndlr` 0x9D5E4), with timeouts (1-10 s per command) as the
  safety net; on a timeout it aborts (ISTAT.ABRT) and resets the chip.
- Phase mismatch (SIST0.MA) is part of the normal path: a short data
  phase (INQUIRY, REQUEST SENSE) ends in one, and the driver reads DBC,
  DNAD, DFIFO and SSTAT0 to work out the residual.
- **Selection timeout (SIST1.STO) is part of the normal path too**: the
  bus scan selects every ID 7 down to 0, and when the adapter is opened
  the driver selects **its own ID (7)** and requires a selection timeout
  (an answer means an ID conflict, error 115).
- Commands: TEST UNIT READY, REQUEST SENSE (on CHECK CONDITION), INQUIRY,
  START STOP UNIT, READ CAPACITY, READ(10), WRITE(10), PREVENT/ALLOW
  MEDIUM REMOVAL, RESERVE/RELEASE(6), and for tapes REWIND, READ BLOCK
  LIMITS, MODE SELECT(6), READ(6), SPACE. No MODE SENSE, no READ TOC.
- DMA addresses are **PCI 0x8000_0000 + physical** (`sys_mem_address`
  0x9AA60 returns 0x8000_0000): the MPC105's window onto memory.
- Phase-1 RTL: the PCI header, the 53C810 register file, a SCRIPTS
  processor with a DMA port into memory through the CPU's snoop port (as
  MacPPC7300's `gdm`), an initiator on a signal-level SCSI bus shared with
  MacPPC7300's targets, the interrupt logic, and the machine's PCI I/O
  decode for 81000000-BF7FFFFF. The fastest route is a port of the HP
  9000/715 core's `ncr53c710.sv` (a working SCRIPTS engine, 2,145 ALMs
  there). Roughly 3-4.5 k ALMs for the chip and its glue, plus the
  targets (section 7).

---

## 1. The firmware's SCSI driver

### 1.1 Where it is and how to read it

Like the S3 driver (`s3_design.md` 1.1) it is a separately linked module
in the RAM image. The modules have one header form (offsets from the
header):

| +0 | +4 | +8 | +C | +10 | +14 |
|---|---|---|---|---|---|
| 0x200 (code) | TOC | 0xC | data | ... | end |

followed by "XXXXXXXX", FFs and " PPS Firmware Licensed Materials".
Sixteen headers are in the image (0x57B1C ... 0xA791C); the SCSI one:

| | address |
|---|---|
| module header | 0x96F1C |
| code | 0x9711C - 0x9E384 (`init_main` 0x97144, `main` 0x974B0, then 0x97624-0x9E384: `scsi_devio` ... `mem_test`) |
| data | 0x9E584 - 0x9FA0B |
| TOC (r2) | 0x9F790 = 0x96F1C + 0x8874 |
| driver source string | 0x9E904 "R2/scsi_ctl.c, rosipl_601, rosipl_13000 2/23/93 12:12:27" |

Pointers in the data are module offsets (relocated at load). To
reproduce the annotated listing:

```
python3 -I firmware/tools/annotate_module.py 96f1c 9f790 9711c 9e584
```

The I/O services are the firmware's table at 0xF83D8 (as for the S3):
324 `in8`, 332 `in32`, 344 `out8`, 348 `out16`, 352 `out32`, 412
`timeout`, 404 `get_timeout_value`, 448 `sleep`, 488 `ext_int_registrar`,
512 `checkpoint`, 668 platform byte, 672 `pci_config_query_slots`, 684
`pci_config_read_32`, 676 `pci_config_read_8`, 688/692/696
`pci_config_write_8/16/32`, 700 `pci_config_slot_2_dev`, 888
`pci_logical_2_physical_slot`. `in8(port)` is `lbz` from
`0x8000_0000 | port` (0x7350); `in32`/`out32` are a big-endian `lwz`/`stw`
of the four registers at once, the driver byte-swapping with `swap_word`
(0x9A578) to get the 53C810's little-endian value.

Data structures (all module data):

| where | what |
|---|---|
| D_9EA3C (`TOC+84`) "adapter" | +136 PCI address of memory 0 (0x8000_0000, from `sys_mem_address` 0x9AA60); +140 the chip's I/O base (every register access is `in8/out8(+140 + reg)`); +144 DMODE's burst bits (byte C0); +148 the next I/O base to hand out, **0x2000_0000** initially (+0x100 per card); +152 an internal command block (TEST UNIT READY); +180-+196 the saved data pointer and count; +197-+219 message buffers (below); +244 the **status byte**; +245 the **message-in byte**; +246 the first byte of an SDTR/WDTR answer; +248 extended-message arguments; +257 a message-out byte (07, MESSAGE REJECT); +260 MODIFY DATA POINTER's argument; +264/+268/+272 the bus-reset recovery timeout |
| D_9F924 (`TOC+92`) "run state" | +0 the SCRIPTS entry offset; +8 the kind (0x43 normal, 0x4E with negotiation, 0x54 diagnostics); +12 the result; +16 flags; +23 the SCNTL3 shadow (0x33); copies of DSTAT (+32), SSTAT0 (+33), SSTAT1 (+34), ISTAT (+40), DBC (+56), DNAD (+60), DSP (+64), DSPS (+68), SCRATCHA0 (+72), SIST0 (+86), SIST1 (+87); +116 an internal device record (own ID, LUN 0) |
| D_9F9B4 (`TOC+96`) | the table-indirect table DSA points at: entry 0 {count, address} the identify message, entry 8 the message-out with negotiation, entry 0x10 the negotiation answer |
| D_9EB84 (`TOC+100`) | **the SCRIPTS program**, 267 words (section 1.4) |
| D_9EFB0-D_9F018 | the patch lists (word indices into the program) |
| the "card" record (`find_scsi_card`'s r5) | +8 IRQ (15), +12 logical slot, +16 physical slot, +20 I/O base, +28 PCI device ID (1: 810, 3: 825), +30 highest LUN (7), +31 highest ID (7; 15 for the 825), +33.. own SCSI ID (7, or from the NVRAM variable `fw-scsicfg`, parsed at 0x9A77C), +41 state flags |

Message buffers in the adapter record (initial bytes): +197 `C0 01 03 01
32 00` (IDENTIFY + SDTR, period 0x32 = 200 ns, offset 0), +203 `C0 01 02 03
01` (IDENTIFY + WDTR 16-bit, 825 only), +208 `C0 0C` (IDENTIFY + BUS
DEVICE RESET), +210 `01 03 01 32 00` (the SDTR answer template), +215 `01
02 03 00` (the WDTR answer template), +257 `07`. ncr_fun_setup puts the
LUN in the identify bytes (0xC0 | LUN: disconnect privilege set).

### 1.2 The functions

| PC | function | what it does |
|---|---|---|
| 0x97144 | `init_main`, `main` (0x974B0) | module entry; `scsi_devio` (0x97624) is the device-I/O entry point |
| 0x97718 | `scsi_init` | progress 0x370094; finds the card (`find_scsi_card` twice), opens it (`scsi_cmd` 10), the bus scan (below), closes it (11) |
| 0x98938 | `scsi_io` | open, `prep_scsi_device`, READ CAPACITY, READ(10)/WRITE(10) (0x98C14: function 8 or 9), the controller diagnostics (15), RESERVE/RELEASE |
| 0x99308 / 0x993AC / 0x995FC / 0x996F4 | `scsi_tur`, `scsi_start_motor`, `prep_scsi_device`, `scsi_cap` | TEST UNIT READY with retries; START STOP UNIT (immediate, then not); the two plus READ CAPACITY (READ BLOCK LIMITS for a tape) |
| 0x9997C-0x99D20 | `position_tape`, `set_tape_block_size`, `read_tape` | tapes, through pass-through CDBs in D_9E6FC |
| 0x9ADC0 | `scsi_cmd` | builds the command block (flags, CDB length, data address and length, the CDB from the templates at D_9E904+186..), calls `ncr_cmd`; BUSY retried every 500 (us?) for 10 s; CHECK CONDITION followed by REQUEST SENSE (18 bytes) and `xlat_sense` |
| 0x9B590 | `ncr_cmd` | the chip functions (jump table D_9E40C+136): 3 adapter description (PCI revision byte, "NCR 53C810"), 10 open, 11 close, 12 bus reset, 15 diagnostics, 16 execute a command, 17 BUS DEVICE RESET |
| 0x9BA18 | `find_scsi_card` | PCI scan and configuration (1.3) |
| 0x9BC50 | `ncr_adapter_open` | reset, set-up, script self-test, the own-ID selection (1.6) |
| 0x9BE10 | `ncr_fun_setup` | patches the script for one command (1.5) |
| 0x9C27C | `ncr_execute` | starts the script, waits for interrupts, dispatches DSPS (1.7) |
| 0x9D2C0 | `ncr_cleanup_script` | recovery after an unexpected phase: residual from DBC, the move re-patched, CTEST3.CLF and STEST3.CSF, a new entry point chosen by SSTAT1's phase |
| 0x9D5E4 | `SCSI_int_hndlr` | the IRQ 15 handler (1.8) |
| 0x9D808 | `Reset_SCSI_Bus` | SCNTL1 \|= 08 (RST), sleep 32, SCNTL1 restored, sleep 5 |
| 0x9D8E4 | `ncr_default_setup` | the register set-up (1.6) |
| 0x9DC60 | `ncr_soft_reset` | SIEN0, SIEN1, DIEN = 0; ISTAT = 40 (SRST), sleep 125, ISTAT = 0, sleep 125 |
| 0x9DD6C | `get_script_and_patch` | relocates the program (once), swaps it to little-endian (1.4) |
| 0x9DF20 | `controller_diags` | SCID write/read 7, reset value check (SCID & 67 = 0), the script self-test, `mem_test`, the own-ID selection |
| 0x9E120 | `mem_test` | SCRIPTS memory-to-memory moves of 4096, 2048, ... 1 bytes between two malloc'd buffers, checked |
| 0x9A5D0 / 0x9A628 | `hf_led_on/off` | port 0808 = 1 / 0 (the disk light) around commands |

`sleep(n, -1000)` and `get_timeout_value(.., n, scale)` take a count and a
scale; from their uses (a 125 x reset delay, a 500 x BUSY retry with
scale -1,000,000, `n, 1` for command timeouts of 1-10) the reading is
-1000 = milliseconds, -1,000,000 = microseconds, 1 = seconds. Not
verified in `convert_to_rtc` (0x25F44).

### 1.3 PCI configuration

`find_scsi_card` (0x9BA18), for each slot from `pci_config_query_slots`:

1. Reads the ID (offset 0) and compares it with 0x0001_1000 (53C810) and
   0x0003_1000 (53C825) (0x9BA94).
2. A matching card that is not the one asked for gets its command
   register cleared (write16(4, 0), 0x9BAC0).
3. The one asked for: its logical-to-physical slot and device numbers
   recorded; **BAR0 (offset 0x10) = adapter+148 = 0x2000_0000** (0x9BB54;
   +148 then += 0x100); **write16(0x0C, 0x8000)**: cache line size 0,
   latency timer 0x80 (0x9BB74); **interrupt line (0x3C) = 15**
   (0x9BB90); card +31 = 7 (810) or 15 (825), +30 = 7.
4. `ncr_cmd` 10 (open, 0x9B71C): the I/O base into adapter+140,
   **command = 0005** (I/O space, bus master; 0x9B74C), the interrupt
   handler registered on the card's IRQ (`ext_int_registrar`(2, 15,
   `SCSI_int_hndlr`)), then `ncr_adapter_open`.
5. `ncr_cmd` 11 (close, 0x9B7D8): SIEN0, SIEN1, DIEN = 0, the handler
   unregistered, command = 0 (0x9B8D0).
6. After a bus fault (DSTAT.BF, 0x9CEBC): reads config 4 and writes it back
   masked with 0xF700_0147 (the status register's write-one-to-clear bits,
   the command's enables kept).
7. `ncr_cmd` 3 reads the revision byte (config 8, 0x9B6D8) for the adapter
   description.

BAR1 (memory) and the expansion ROM are never touched; the memory enable
is never set. Port 080C (equipment present) bit 6, "SCSI fuse good", must
read 1 for an on-board adapter (0x9BD44, 0x9E04C; error 131 otherwise).
The machine reads 080C as FF today, which passes.

### 1.4 The SCRIPTS program

`get_script_and_patch` (0x9DD6C) runs once (a flag at D_9EFF8 is 1, then
byte-swapped to 0x0100_0000): it adds the program's PCI address
(0x8000_0000 + 0x9EB84) to words 5 and 0xC7 (the SELECTs' alternate
addresses), writes the PCI addresses of the adapter's buffers into the
block moves' address words (word 0x2B the status byte +244; 0x31, 0x47,
0x51, 0x5D, 0x67, 0x73, 0x79, 0x83, 0xB5 the message-in byte +245; 0xDB
+246; 0x89 +248; 0x6D the message-out byte +257; 0x57 +260), then swaps
all 267 words to little-endian, in place. The chip fetches it from
memory, through DMA, at PCI 0x8009_EB84.

Per command `ncr_fun_setup` (0x9BE10) patches, in the little-endian
words: the two SELECTs' encoded target ID (words 4, 0xC6, bits 19-16), the
reselection compare value 0x80 | ID (word 0xB8, the SSID's valid bit and
ID), the CDB move (words 22-23: count = the CDB length, address = PCI
address of the command block + 16), the data move (words 32-33: count and
address), and the **data direction**: bit 0 of the phase field of words
28, 32 and 166 (DATA_IN for reads, DATA_OUT for writes: the program as
stored has only DATA_IN). It also fills the table at DSA: entry 0 = {1,
identify}, entry 8 = {6, IDENTIFY + SDTR} (or {5, IDENTIFY + WDTR}, or {2,
IDENTIFY + BUS DEVICE RESET}), entry 0x10 = {4 or 3, the answer buffer}.

The program as the chip sees it (offsets from its start; "REL" targets
resolved; the ID, counts and addresses as patched per command):

```
000  INT 0xDDDD0001                       ; ---- entry 0: a command, no negotiation
008  MOVE 0x00 TO SCRATCHA0               ; progress bits, read back at the end
010  SELECT ATN <id>, alt 0x268           ; (absolute alternate, relocated)
018  INT 0xEEEE0001 WHEN NOT MSG_OUT
020  INT 0xDDDD0002
028  MOVE SCRATCHA0 | 0x80 TO SCRATCHA0
030  MOVE FROM 0x0 WHEN MSG_OUT           ; table indirect: the identify byte
038  JUMP REL 0x270
040  INT 0xEEEE0002 WHEN NOT CMD          ; ---- command
048  INT 0xDDDD0003
050  MOVE SCRATCHA0 | 0x20 TO SCRATCHA0
058  MOVE <cdb len>, <cdb> WHEN CMD
060  JUMP REL 0x098 WHEN STATUS
068  JUMP REL 0x0B8 IF MSG_IN
070  INT 0xEEEE0003 WHEN NOT DATA_IN      ; (DATA_OUT for a write)
078  INT 0xDDDD0004
080  MOVE <len>, <buffer> WHEN DATA_IN    ; (DATA_OUT for a write)
088  INTFLY 0                             ; the handler counts the bytes
090  JUMP REL 0x0B8 WHEN MSG_IN
098  INT 0xEEEE0004 WHEN NOT STATUS       ; ---- status
0A0  MOVE SCRATCHA0 | 0x10 TO SCRATCHA0
0A8  MOVE 1, <status byte> WHEN STATUS
0B0  INT 0xDDDD0005
0B8  INT 0xEEEE0005 WHEN NOT MSG_IN       ; ---- message in
0C0  MOVE 1, <msg byte> WHEN MSG_IN       ; (ACK stays up)
0C8  INT 0xDDDD0006
0D0  JUMP REL 0x240 IF 0x00               ; COMMAND COMPLETE
0D8  INT 0x53 IF 0x02                     ; SAVE DATA POINTER
0E0  INT 0x54 IF 0x03                     ; RESTORE POINTERS
0E8  INT 0x56 IF 0x04                     ; DISCONNECT
0F0  JUMP REL 0x270 IF 0x07               ; MESSAGE REJECT
0F8  JUMP REL 0x168 IF 0x23               ; IGNORE WIDE RESIDUE
100  JUMP REL 0x180 IF NOT 0x01           ; not extended: reject it
108  CLEAR ACK                            ; ---- extended message
110  JUMP REL 0x1A8 WHEN NOT MSG_IN
118  MOVE 1, <msg byte> WHEN MSG_IN       ; its length
120  JUMP REL 0x1C0 IF 0x02
128  JUMP REL 0x200 IF 0x03
130  JUMP REL 0x180 IF NOT 0x05
138  CLEAR ACK                            ; length 5: MODIFY DATA POINTER
140  MOVE 1, <msg byte> WHEN MSG_IN
148  JUMP REL 0x180 IF NOT 0x00
150  CLEAR ACK
158  MOVE 4, <adapter+260> WHEN MSG_IN
160  INT 0x55
168  CLEAR ACK                            ; IGNORE WIDE RESIDUE's argument
170  MOVE 1, <msg byte> WHEN MSG_IN
178  INT 0x59
180  SET ATN                              ; ---- reject: eat the bytes, then
188  CLEAR ACK                            ;      MESSAGE REJECT out
190  JUMP REL 0x1A8 WHEN NOT MSG_IN
198  MOVE 1, <msg byte> WHEN MSG_IN
1A0  JUMP REL 0x188
1A8  INT 0xEEEE0001 WHEN NOT MSG_OUT
1B0  MOVE 1, <adapter+257 = 07> WHEN MSG_OUT
1B8  JUMP REL 0x270
1C0  CLEAR ACK                            ; ---- WDTR in (length 2)
1C8  MOVE 1, <msg byte> WHEN MSG_IN
1D0  JUMP REL 0x180 IF NOT 0x03
1D8  CLEAR ACK
1E0  MOVE 1, <msg byte> WHEN MSG_IN
1E8  SET ATN
1F0  CLEAR ACK
1F8  INT 0x58
200  CLEAR ACK                            ; ---- SDTR in (length 3)
208  MOVE 1, <msg byte> WHEN MSG_IN
210  JUMP REL 0x180 IF NOT 0x01
218  CLEAR ACK
220  MOVE 2, <adapter+248> WHEN MSG_IN
228  SET ATN
230  CLEAR ACK
238  INT 0x57
240  MOVE SCRATCHA0 | 0x08 TO SCRATCHA0   ; ---- command complete
248  MOVE SCNTL2 & 0x7F TO SCNTL2         ; SDU cleared: the disconnect is expected
250  CLEAR ACK
258  WAIT DISCONNECT
260  INT 0x50                             ; done
268  INT 0xEEEE0051                       ; the SELECTs' alternate (selected/reselected)
270  CLEAR ACK                            ; ---- phase dispatch
278  JUMP REL 0x098 WHEN STATUS
280  JUMP REL 0x0B8 IF MSG_IN
288  JUMP REL 0x018 IF MSG_OUT
290  JUMP REL 0x040 IF CMD
298  JUMP REL 0x070 IF DATA_IN            ; (DATA_OUT for a write)
2A0  INT 0xEEEE0052
2A8  MOVE SCID | 0x40 TO SCID             ; ---- after DISCONNECT: RRE on
2B0  MOVE SCNTL2 & 0x7F TO SCNTL2
2B8  CLEAR ACK
2C0  WAIT RESELECT REL 0x2A8
2C8  INT 0xEEEE0052 WHEN NOT MSG_IN
2D0  MOVE 1, <msg byte> WHEN MSG_IN       ; the reselector's IDENTIFY
2D8  MOVE SSID TO SFBR                    ; (encoded as MOVE SSID | 0 TO SFBR)
2E0  JUMP REL 0x2A8 IF NOT 0x80|<id>      ; not ours: wait again
2E8  INT 0xDDDD0013
2F0  MOVE SCID & 0xBF TO SCID
2F8  CLEAR TARGET
300  JUMP REL 0x270
308  INT 0xDDDD0007                       ; ---- entry 0x308: a command with negotiation
310  MOVE 0x00 TO SCRATCHA0
318  SELECT ATN <id>, alt 0x268
320  SET ATN
328  INT 0xEEEE0001 WHEN NOT MSG_OUT
330  INT 0xDDDD0008
338  MOVE SCRATCHA0 | 0x80 TO SCRATCHA0
340  MOVE FROM 0x8 WHEN MSG_OUT           ; IDENTIFY + SDTR (6 bytes)
348  CLEAR ATN
350  INT 0xEEEE0005 WHEN NOT MSG_IN
358  INT 0xDDDD0009
360  MOVE SCRATCHA0 | 0x40 TO SCRATCHA0
368  MOVE 1, <adapter+246> WHEN MSG_IN
370  INT 0xDDDD0010 IF 0x07               ; rejected
378  JUMP REL 0x270 IF 0x07
380  CLEAR ACK
388  INT 0xDDDD0011
390  MOVE FROM 0x10 WHEN MSG_IN           ; the rest of the answer
398  CLEAR ACK
3A0  INT 0xDDDD0012
3A8  JUMP REL 0x270
3B0  JUMP REL 0x350 IF MSG_IN             ; ---- resume table (ncr_cleanup_script)
3B8  JUMP REL 0x0B8 IF MSG_IN
3C0  JUMP REL 0x098 IF STATUS
3C8  JUMP REL 0x328 IF MSG_OUT
3D0  JUMP REL 0x040 IF CMD
3D8  JUMP REL 0x070 IF DATA_IN
3E0  INT 0xEEEE0052
3E8  JUMP REL 0x3F0 IF 0x98 AND MASK 0x08 ; ---- entry 0x3E8: self-test (a no-op jump)
3F0  MOVE 0xFF TO SCRATCHA0
3F8  INT 0x50
400  MEMORY MOVE <n>, <src>, <dst>        ; ---- entry 0x400: mem_test
40C  INTFLY 0
414  MOVE 0xFF TO SCRATCHA0
41C  INT 0x50
424  INT 0x50
```

Instruction encodings used (the word as the chip reads it): block moves
`09/0A/0B/0E/0F` (MOVE, initiator, phases 1, 2, 3, 6, 7) and `1E/1F`
(table indirect, MSG_OUT/MSG_IN); `41` SELECT ATN (absolute alternate);
`48` WAIT DISCONNECT; `54` WAIT RESELECT (relative alternate); `58`
SET, `60` CLEAR (ACK 0x40, ATN 0x08, TARGET 0x200); `78` MOVE data8 TO
reg, `7A` reg \| data8, `7C` reg & data8, `72` reg \| data8 TO SFBR
(registers SCRATCHA0 34, SCNTL2 02, SCID 04, SSID 0A); `80 8x` JUMP
(always relative: bit 23), with 0x88 always, 0x8A/0x8B phase IF/WHEN,
0x83 WHEN NOT, 0x8C/0x84 data IF/IF NOT; `98 xx` INT with the same
conditions, `98 18` INTFLY (bit 20); `C0` MEMORY MOVE.

The progress bits in SCRATCHA0, read at the end (0x9CF64): 0x80 identify
sent, 0x40 negotiation answered, 0x20 CDB sent, 0x10 status read, 0x08
command complete; a command that does not end with all of 0x98 is an
error (81). 0xFF from the two diagnostic entries.

### 1.5 One command, step by step

`ncr_cmd` 16 (0x9B8F4) sets DMODE = (DMODE & 3F) | C0 (burst 16), then
`ncr_fun_setup` and `ncr_execute`, retried while the result is 19 or 136.
`ncr_execute` (0x9C27C):

1. If a bus-reset recovery is pending (adapter+272, set by the handler
   on SIST0.RST), wait for its timeout (3 s).
2. `out8(SDID, ID)` (0x9C368); `out8(SCNTL3, shadow)` (0x33; \| 08, EWS,
   for a wide 825 target).
3. `out32(DSA, swap(PCI address of D_9F9B4))` (0x9C3F4);
   `out32(DSP, swap(PCI script base + entry))` (0x9C42C): the write of
   DSP starts the chip (DMODE.MAN = 0).
4. Wait for the handler's ISTAT copy (D_9F924+40) to be non-zero, with
   the command's timeout. On a timeout: `out8(ISTAT, copy | 80)` (ABRT),
   wait for DSTAT.ABRT (from the handler), `ncr_soft_reset`,
   `ncr_default_setup`, result 144.
5. Read SSTAT0 (0x9C57C), SSTAT1 (phase, 0x9C598), DSP and DSPS (in32,
   0x9C5B4, 0x9C5D8). Then by the ISTAT copy:
   - **DIP only**: DSTAT & 15 must be 04 (SIR); DSPS dispatched:
     - 0xDDDD00nn: the step points; the CPU only notes them and resumes
       at the next instruction (jump table D_9E40C+32: 0001 -> 0x008,
       0002 -> 0x028, 0003 -> 0x050, 0004 -> 0x080, 0005 -> 0x0B8, 0006 ->
       0x0D0, 0007 -> 0x310, 0008 -> 0x338, 0009 -> 0x360, 0010 -> 0x378
       (SDTR rejected: noted), 0011 -> 0x390, 0012 -> 0x3A8 (checks a WDTR
       answer, else 0x180 to reject), 0013 -> 0x2F0);
     - 0xEEEE00nn: an unexpected phase: `ncr_cleanup_script` (residual
       from DBC, the move re-patched, CTEST3 = 04, STEST3 = 82) picks an
       entry from SSTAT1's phase (0x270, 0x3B0, 0x3B8);
     - 0x50: done; the status byte: 00 good (the result is the residual),
       02 CHECK CONDITION (73, `scsi_cmd` then sends REQUEST SENSE), 08
       BUSY (100, retried), 18 RESERVATION CONFLICT (40), else 19;
     - 0x53-0x59 (D_9E40C+108): 53 save data pointer, 54 restore, 55
       modify data pointer (+260), 56 disconnect (resume at 0x2A8: wait for
       the reselection), 57 SDTR in (the answer built from +210 into
       D_9F924+220.., table entry 0 pointed at it, resume 0x270 so the
       MSG_OUT phase sends it), 58 WDTR in, 59 ignore wide residue.
     - DSTAT not SIR (0x9CEA8): BF: the PCI status cleared (1.3), then
       `ncr_cleanup_script`; ABRT: 144; anything else (IID):
       `ncr_cleanup_script`, 19 if it finds no way on.
   - **SIP only** (0x9C710): SIST0.MA (phase mismatch): if DSP points
     just past the data move (DSP - base - 8 = 0x80) and the phase is not
     a data phase, the residual is read: DBC (in32 at 24, DCMD masked off),
     DNAD (in32 at 28); for a write also DFIFO (20) & 7F minus DBC & 7F
     plus SSTAT0.OLF, with CTEST3 = 04 (CLF) and STEST3 = 82 (TE, CSF) if
     non-zero; the move re-patched with the remainder, resume at 0x270.
     Elsewhere: `ncr_cleanup_script`. SIST0.UDC or SIST1.STO: STO gives
     41 (no device; the target's record flagged), UDC gives 118 after
     CTEST3 \|= 04 and STEST3 \|= 02. SIST0.PAR: 136, resume 0x270. Other:
     DSTAT read, 19.
   - **DIP and SIP** (0x9C60C): up to 200 times: DSTAT, SIST0, SIST1,
     SSTAT0, ISTAT read with 10 ms sleeps until ISTAT shows neither; 81.
6. If the result is "continue" (71), check the command timeout and go
   back to 2 (SCNTL3, DSA, DSP rewritten each time).
7. At the end: SCRATCHA0 read (0x9CF64); ISTAT drained (DIP/SIP: SIST0,
   SIST1 read with 5 ms sleeps).

A READ(10) with no negotiation is therefore: start at 0, INT 0001, INT
0002 (after the selection and MSG_OUT seen), INT 0003 (CMD seen), INT
0004 (DATA_IN seen), the move, INTFLY, INT 0005 (status read), INT 0006
(message read), INT 0x50 (bus free): seven halts and restarts and one
interrupt on the fly. The chip must restart cleanly from a DSP write in
the middle of a connected bus with the target asserting REQ, and must
keep ACK asserted across an INT that follows a MSG_IN byte.

### 1.6 Open, set-up, self-tests

`ncr_adapter_open` (0x9BC50):

1. `ncr_soft_reset` (0x9DC60): SIEN0, SIEN1, DIEN = 0; **ISTAT = 40
   (SRST)**, 125 ms, ISTAT = 0, 125 ms.
2. `in8(SCNTL0)` kept (0x9BCA4).
3. `ncr_default_setup` (0x9D8E4), in this order:

   | PC | register | value | meaning |
   |---|---|---|---|
   | 0x9D914 | DCNTL (3B) | 01 | COM: 53C810 mode (not 53C700-compatible; reselection ID in SSID) |
   | 0x9D92C | SCNTL0 (00) | C8 | full arbitration, EPC (parity checking) |
   | 0x9D948 | SCNTL1 (01) | 00 | |
   | 0x9D964 | SCNTL3 (03) | 33 | SCF and CCF for a 40 MHz SCSI clock |
   | 0x9D980 | SIEN0 (40) | 8F | MA, SGE, UDC, RST, PAR |
   | 0x9D99C | SIEN1 (41) | 04 | STO |
   | 0x9D9B8 | DIEN (39) | 7D | MDPE, BF, ABRT, SSI, SIR, IID |
   | 0x9D9D4 | GPREG (07) | 00 | |
   | 0x9D9F0 | CTEST0 (18) | 00 | |
   | 0x9DA0C | CTEST4 (21) | 00 | |
   | 0x9DA28 | SXFER (05) | 00 | asynchronous |
   | 0x9DA48 | DMODE (38) | C0 | burst length 16, automatic start |
   | 0x9DA64 | STIME0 (48) | 0B | selection timeout code B (about 100-130 ms), no HTH |
   | 0x9DA80 | MACNTL (46) | 00 | |
   | 0x9DA9C | STEST2 (4E) | 00 | |
   | 0x9DAB8 | STEST3 (4F) | 80 | TE (TolerANT) |
   | 0x9DAD4 | CTEST3 (1B) | 04 | CLF: clear the DMA FIFO |
   | 0x9DAF4 | SCID (04) | 07 | own ID 7 (card +33 & F) |
   | 0x9DBF8 | RESPID (4A) | 80 | respond to ID 7 |

   (For a 53C825: RESPID0/1 as one `out16`, GPCNTL \|= 08, GPREG read, and
   STEST2 \|= 20 (DIF) if GPREG bit 3 is clear.) Then the run state is
   zeroed and its SCNTL3 shadow set to 0x33.
4. `get_script_and_patch`.
5. **Script self-test**, up to three tries: entry 0x3E8 (a JUMP, MOVE FF
   TO SCRATCHA0, INT 0x50), timeout 1 s; anything but 0 ends the open
   with 102.
6. Port 080C bit 6 (SCSI fuse), else 131.
7. **Own-ID selection**, up to four tries: the internal command block
   (TEST UNIT READY, adapter+152) to the adapter's own ID, timeout 4 s,
   through entry 0 (`ncr_fun_setup` with function 16). It must end in a
   **selection timeout (41)**: 0 means something answered at ID 7 (115);
   81 or 144 reset the bus (`Reset_SCSI_Bus`) and try again; four
   failures give 130.

`controller_diags` (0x9DF20, function 15, from `scsi_io`) adds: SCID = 7
read back 7 (128 if not); after `ncr_soft_reset` SCID & 67 must read 0
(129); SCRATCHA0 = 0, the self-test, SCRATCHA0 must read FF (102); then
`mem_test` (0x9E120): two 4 KB buffers from `malloc`, the destination
filled with a pattern byte, entry 0x400 with the MEMORY MOVE's count,
source and destination patched (words 0x100-0x102), timeout 5 s, the
destination compared, then again with the count halved (4096, 2048, ...,
2, 1; the pattern byte incremented); then the own-ID selection.

The bus scan (`scsi_init` 0x97CB4-0x98418): for each ID from card +31 (7)
down to 0, progress 0x0208_xx96 (xx the ID), LUN 0 to card +30 (7) while
devices answer; the very first step (ID 7, LUN 0) is **`scsi_cmd` 12, a
SCSI bus reset** (`Reset_SCSI_Bus`: RST for 32 ms). Each device record
gets flag 0x10 (byte 17) so its first command negotiates (entry 0x308,
IDENTIFY + SDTR period 0x32 offset 0); then INQUIRY (and for the boot
device TEST UNIT READY, START STOP UNIT, READ CAPACITY, READ(10)).

### 1.7 Messages, disconnects, phases, timeouts

- Every selection is with ATN; the first MSG_OUT byte is IDENTIFY with
  disconnect privilege (0xC0 | LUN). The negotiation entry sends IDENTIFY
  + SDTR(0x32, 0) as one 6-byte table-indirect move, then CLEAR ATN; the
  answer (01 03 01 pp oo) is read 1 + 4 bytes; a MESSAGE REJECT is
  accepted. The firmware never sets SXFER from the answer: transfers stay
  asynchronous.
- Disconnects are handled (DSPS 0x56 -> 0x2A8: SCID.RRE, SDU cleared,
  WAIT RESELECT, the reselector's IDENTIFY, SSID compared with 0x80 | ID,
  CLEAR TARGET, the phase dispatch), but nothing the core will connect ever
  needs them.
- The chip must **hold ACK after the last byte of a MSG_IN move** (every
  message byte is followed by IF tests on SFBR and then CLEAR ACK), and
  **load SFBR with the first byte of a move from the bus** (the message
  byte for the IF 0x00/0x02/... tests, and 0x07 for the reject test at
  0x370).
- ATN must drop before the last byte of a MSG_OUT move (the 53C8xx does
  this itself; the script's CLEAR ATN at 0x348 comes after the move), or a
  target keeps asking for message bytes.
- Phase checks: WHEN waits for REQ, then compares; IF compares the phase
  already latched (the script always does a WHEN first).
- Unexpected disconnect: a target dropping BSY outside WAIT DISCONNECT
  (SCNTL2.SDU set) is SIST0.UDC (118). `ncr_cmd` 17 (BUS DEVICE RESET)
  expects exactly that.
- Timeouts: per command 1 s (self-test), 4 s (own-ID selection), 5 s
  (`mem_test`), the caller's otherwise (2-3 s from `scsi_io`), 10 s for
  BUSY retries in `scsi_cmd`; selection by STIME0 (code B); the bus-reset
  recovery 3 s (`SCSI_int_hndlr` 0x9D774, on SIST0.RST).
- Return codes: 0 good, 19 error, 40 reservation conflict, 41 selection
  timeout, 73 check condition, 81 incomplete/reset, 100 busy, 102 script
  test failed, 115 ID conflict, 118 unexpected disconnect, 130/131 open
  failed / fuse, 133/134 IRQ registration, 136 parity, 144 timeout/abort.

### 1.8 The interrupt handler

`SCSI_int_hndlr` (0x9D5E4), on IRQ 15 (shared with the S3's vertical
interrupt):

1. `in8(ISTAT)`; nothing in bits 2-0: return.
2. INTF (04): `out8(ISTAT, 04)` (clears it) and the byte counter updated.
3. While DIP or SIP: OR ISTAT into the run state's copy; DIP: `in8(DSTAT)`
   (and if ABRT: `out8(ISTAT, 00)`); SIP: (2 ms if DIP too) `in8(SIST0)`,
   2 ms, `in8(SIST1)`; SIST0.RST: the 3 s recovery armed; 2 ms; `in8(ISTAT)`
   again.

So: **reading DSTAT clears it (and DIP); reading SIST0 and SIST1 clears
them (and SIP); writing ISTAT bit 2 clears INTF; the IRQ line follows the
enabled status bits**, level. The 2 ms sleeps are the data manual's
"wait between reads" for stacked interrupts.

### 1.9 The commands

`scsi_cmd`'s CDB templates (D_9E904 + 186..): function 1 TEST UNIT READY
`00`; 2 REQUEST SENSE `03 .. 0E` (18 bytes when sent automatically after
CHECK CONDITION); 4 INQUIRY `12 .. 05` (length patched; `wide_bus_check`
sends it too); 5/6 START STOP UNIT `1B .. 01` (immediate / not); 7 READ
CAPACITY `25`; 8 READ(10) `28`; 9 WRITE(10) `2A` (DATA_OUT); 13/14 PREVENT /
ALLOW MEDIUM REMOVAL `1E`; through function 16 (pass-through): RESERVE
`16` / RELEASE `17` (`scsi_io` 0x98FA4), and for tapes (D_9E6FC): REWIND
`01`, READ BLOCK LIMITS `05`, MODE SELECT(6) `15 10 .. 0C` (12 bytes out),
READ(6) `08 01` (fixed), `0A 01` (WRITE(6), fixed), SPACE `11`.

The disk path a boot needs: INQUIRY (peripheral type, removable bit),
TEST UNIT READY (NOT READY handled with START STOP UNIT), READ CAPACITY
(the block length, 512 or 2048), READ(10). No MODE SENSE, READ TOC or
MODE SELECT on disks or CD-ROMs.

### 1.10 What must read back right

- PCI: the ID (1000:0001), BAR0 as written (bits 31-8), the command
  register, the revision byte (any), the status register's W1C bits.
- SCID: 7 written reads 7; after SRST its RRE/SRE/ID bits (mask 67) read 0.
- SCRATCHA0: written by SCRIPTS (MOVE, OR) and read by the CPU.
- ISTAT (DIP, SIP, INTF; ABRT accepted; SRST), DSTAT (SIR, IID, ABRT, BF;
  read clears), SIST0 (MA, UDC, RST, PAR; read clears), SIST1 (STO).
- SSTAT1's phase bits after an interrupt (the latched SCSI phase).
- DSP (the next instruction, also after a phase mismatch), DSPS (the INT's
  second word), DBC (the bytes left; read as a 32-bit word with DCMD),
  DNAD (the next address), DFIFO's byte counter consistent with DBC (DFIFO
  & 7F - DBC & 7F = bytes stuck in the FIFO: 0 in a FIFO-less model),
  SSTAT0.OLF 0.
- CTEST3 (read-modify-written: any value), STEST3, DMODE (read-modify-
  written).

### 1.11 What the firmware does not use

The memory BAR; SCRIPTS RAM (the 810 has none); CALL, RETURN, LOAD,
STORE, indirect block moves, CHMOV, SELECT/JUMP from a table or with a
relative alternate (the SELECTs are absolute); target mode; low-level
mode (SOCL, SODL, SBCL writes); synchronous transfers (SXFER stays 0);
the general-purpose and handshake timers (STIME1, STIME0.HTH); single
step (DCNTL.SSM); DMA manual start (DMODE.MAN, DCNTL.STD); SIGP and the
semaphore; GPIO beyond writing GPREG = 0; CTEST6 FIFO access; parity
generation tricks; SCSI loopback (STEST2.SLB). The 53C825 paths (wide,
WDTR, differential) are dead code on a 7248.

---

## 2. AIX 4.3.3 and 5.1 (general knowledge, not verified here)

AIX names the 7248's controller `scsi0` (location 00-.., "SCSI I/O
Controller"); its driver is most likely `adapter/pci/ncr810` with the
kernel extension `ncr810dd` (the 53C8xx family on PCI RS/6000s). AIX gets
the device from the residual data (`build_scs` 0x222E0 makes a PnP entry
with the SCSI ID packet, `CreateSCSIIDPacket` 0x3FC94) and the PCI
configuration space; whether it keeps the firmware's BAR0 or reassigns is
to be seen. What such a driver typically adds:

- **Its own SCRIPTS**, resident and running: an idle loop in **WAIT
  RESELECT**, broken out of by **ISTAT.SIGP** (the alternate address taken
  when SIGP is set before or during the wait; CTEST2 read clears SIGP) to
  start a new command; per-target **SELECT FROM a table** (ID, SXFER and
  SCNTL3 from DSA + offset); **CALL/RETURN** (TEMP); **MEMORY MOVE**
  to save and restore pointers and to copy per-command tables;
  **scatter-gather** as runs of table-indirect moves (MOVE or CHMOV) with
  data pointers saved and restored; **INTFLY** for completion without
  stopping; JUMP with carry, register arithmetic (ADD, shifts) on
  SCRATCHA/SCRATCHB and DSA, MOVE to/from SFBR; possibly LOAD/STORE if it
  treats the chip as an 810A (to be checked: the original 53C810 may not
  have them).
- **Disconnect/reselect**: with several disks it expects targets to
  disconnect during long operations and reselect; the chip must answer a
  reselection (SCID.RRE, RESPID, SSID valid + ID, SIST0.RSL if enabled)
  while in WAIT RESELECT or while idle. Targets that never disconnect are
  legal; the driver then never sees a reselection, but its idle WAIT
  RESELECT and SIGP must still work.
- **Tagged queuing**: SIMPLE QUEUE TAG messages (0x20 tag) after IDENTIFY
  when INQUIRY reports CmdQue; a target that does not report it (or
  rejects the message) avoids the whole path. Our targets should not
  report CmdQue.
- **Negotiation**: SDTR (fast SCSI-2, 10 MB/s, offset 8) and its answer
  applied to SXFER/SCNTL3; with targets that answer offset 0 everything
  stays asynchronous. The 810 has no wide or Ultra; WDTR is never sent.
- **Error paths**: phase mismatch with the residual from DBC/DFIFO/SSTAT0-2
  (sync FIFO counts in SSTAT1 bits 7-4: 0 for us), parity (never),
  bus fault (master abort on PCI), IID, unexpected disconnect, selection
  and reselection timeouts, bus reset received (SIST0.RST) and the reset
  recovery, ABRT, SRST, and maybe the general-purpose timer (STIME1,
  SIST1.GEN) for its own timeouts.
- **Register details**: DCNTL.IRQD/IRQM, DMODE burst and read-line bits,
  CTEST4/5, MACNTL, ADDER, SCRATCHB, STEST0/1 for diagnostics; perhaps a
  diagnostic loopback (STEST2.SLB) at configuration (risky: report
  "unimplemented" and see whether AIX cares).
- **CD-ROM**: AIX's CD driver may switch the drive to 512-byte blocks with
  MODE SELECT (RS/6000 history: IBM's CD-ROM drives booted in 512-byte
  mode); the target should accept a block descriptor of 512 or 2048 and
  READ/READ CAPACITY in the current length (HP9K385's target already does,
  section 4). AIX also uses MODE SENSE, READ TOC, PREVENT/ALLOW, START
  STOP (eject).
- **Disks**: MODE SENSE pages (3, 4, 8, 0x3F), READ(6)/WRITE(6),
  READ(10)/WRITE(10) of up to 64-256 KB, REQUEST SENSE, possibly RESERVE,
  VERIFY, WRITE AND VERIFY, SYNCHRONIZE CACHE; INQUIRY strings matter only
  for the ODM type ("Other SCSI Disk Drive" for unknown vendors).

Windows NT 4.0 (little-endian, later) has a 53C810 miniport too; the
machine's byte-lane swap in little-endian mode applies to the chip's
registers like any PCI device; DMA needs no swap (section 5.6).

---

## 3. Reference models

### QEMU `hw/scsi/lsi53c895a.c` (2,454 lines; the `lsi53c810` type is the same code with device ID 0001)

- **SCRIPTS**: an interpreter (`lsi_execute_script` 1170) that fetches
  through `pci_dma_read` (little-endian words), decodes all five classes:
  block moves (direct, indirect, table indirect; MOVE and CHMOV treated
  alike), I/O (select, wait disconnect, wait reselect, set/clear), read/
  write with all eight operators (1450-1530), transfer control with
  phase/data/carry compares, relative addressing, INTFLY, memory move
  (`lsi_memcpy` 1130, 4 KB chunks), load/store. A watchdog (LSI_MAX_INSN,
  1192) yields to the host for scripts that spin.
- **DMA**: `lsi_do_dma` (625) copies between the SCSI request's buffer and
  guest memory with `pci_dma_read/write`; DBC/DNAD updated in one go.
- **The SCSI bus is not modelled**: commands go to QEMU's SCSI layer as
  requests; phases are faked from the request's state (`lsi_set_phase`),
  selection succeeds at once or fails with STO (`lsi_bad_selection` 617),
  disconnect/reselect come from its request queue (`lsi_reselect` 714,
  `lsi_wait_reselect` 1146), messages are parsed by `lsi_do_msgout` (994):
  IDENTIFY, ABORT, BUS DEVICE RESET, SIMPLE QUEUE TAG; SDTR/WDTR/PPR are
  *ignored* (no answer); anything else is answered with MESSAGE REJECT.
- **Interrupts**: DSTAT/SIST0/SIST1 with DIP/SIP derived (`lsi_update_irq`
  496); reading DSTAT, SIST0, SIST1 clears them; CTEST2's read clears SIGP.
  A "special hack": STO does not stop the script at once, only at the next
  bus instruction (541-560).
- **Skipped**: target mode (1421), low-level mode (2098), SCSI FIFO test
  (2105), the general-purpose timer (2080), START sequence (1915),
  immediate arbitration (1922), CTEST5 DMA increment (2014), HEAD/ORDERED
  tags, parity, all timing. Its own note: the 810 model has the later
  chips' features too.

### MAME `src/devices/machine/53c810.cpp` (819 lines; "LSI53C810A"; used by Sega Model 3 and the BeBox, which has the same MPC105 bridge)

A skeleton: the register file, SELECT, SET/CLEAR, JUMP/CALL/RETURN/INT
with phase tests, memory move. The rest is stubbed: **block moves log
"not actually implemented"** (92), WAIT DISCONNECT/RESELECT, move to/from
SFBR and read-modify-write are `fatalerror` (137, 155, 217-229), INTFLY
(38), carry tests (245), LOAD/STORE (361-368), and the data compare is
"not yet implemented" (277). Only useful as a register list; the BeBox's
SCSI does not work there.

### MAME `src/devices/machine/53c7xx.cpp` (1,799 lines; NCR 53C700)

A SCRIPTS processor on MAME's signal-level `nscsi` bus (arbitration,
selection, REQ/ACK per byte), which is the shape of the design here. Its
TODO: low-level registers, arbitrary delays, unimplemented opcodes.

### The HP 9000/715 core's `rtl/scsi/ncr53c710.sv` (684 lines; in this workspace, running HP-UX)

The closest thing to what is needed: synthesizable SCRIPTS for the 53C710
(the 810's predecessor, the same instruction set less the 810 additions):
block moves direct, indirect and table indirect, SELECT (ATN, relative,
table indirect), WAIT DISCONNECT, WAIT RESELECT (SIGP before or during),
SET/CLEAR ATN/ACK/TARGET/CARRY, register RMW and moves to/from SFBR (the
710's four operators), JUMP/CALL/RETURN/INT with phase, data and carry
compares and wait, memory moves (also to its own registers), ATN dropped
before the last MSG_OUT byte (543), ACK held after MSG_IN (ackhold). DMA
through a one-doubleword buffer, so the DMA FIFO is always empty when the
chip halts (DSTAT.DFE 1, DFIFO following DBC: residuals 0). Initiator
only, no low-level mode, no single step. Its bus is the byte-level one of
`scsi_targets.sv` (sel/sel_done/sel_fail, req/phase/tdata, ack/idata,
ackhold, atn, rst). Fitted: 2,145 ALMs, 1,737 registers, no M10K
(`output_files/HP9K715.fit.rpt`).

---

## 4. SCSI target RTL to reuse

| model | where | bus interface | commands | images and CD | notes |
|---|---|---|---|---|---|
| `MacPPC7300_scsidisk.sv` (1,268 lines) + `MacPPC7300_scsibus.sv` (61) | MacPPC7300_MiSTer `rtl/machine/` | **signal level**: t_bsy/req/msg/cd/io/db out, b_rst/bsy/sel/atn/ack/db in; REQ/ACK per byte; the phase set a clock before REQ, a new phase's first REQ PHASE_US (10 us) later; `scsibus` ORs initiator and target lines, each side seeing the other's a clock late | TUR, REZERO, REQUEST SENSE, FORMAT, READ/WRITE(6/10), SEEK, INQUIRY, MODE SELECT/SENSE(6) (pages 1, 3, 4, Apple's 30), RESERVE/RELEASE, START STOP, SEND DIAG, PREVENT, READ CAPACITY, VERIFY, SYNC CACHE, READ/WRITE BUFFER; LUN other than 0: INQUIRY 7F, else ILLEGAL REQUEST 5/25 | disks IDs 0 and 1 (slots 0, 1), CD ID 3 (slot 4) speaking the Main's **Mac CD layer** (response window 7E000000, command window 7D000000), CD audio (`MacPPC7300_cdaudio`), the BlueSCSI Toolbox; two 2-block buffers, hps_io 8-bit, clk_h side | MESSAGE OUT while ATN: IDENTIFY (LUN), SDTR answered with offset 0, WDTR 8-bit, ABORT/BDR free the bus; never disconnects; proven with Mac OS 7.6-9.1 through MESH. INQUIRY "MiSTer VIRTUAL DISKn" |
| `scsi_targets.sv` (726) + `cd_audio.sv` (214) | hp9000-715 `rtl/scsi/` | **byte level** (sel/sel_id/sel_atn -> sel_done/sel_fail, req/phase/tdata, ack/idata, ackhold, atn, brst); no timing, one device connected at a time, never disconnects | TUR, REZERO, REQUEST SENSE, FORMAT, READ/WRITE(6/10), SEEK, INQUIRY, MODE SELECT/SENSE(6/10) (1, 3, 4, 8), RESERVE/RELEASE, START STOP, SEND DIAG, PREVENT, READ CAPACITY, VERIFY, SYNC CACHE; CD: READ TOC (0, 1), PLAY AUDIO, PAUSE/RESUME, STOP, READ SUB-CHANNEL, MODE page 0E | IDs 6, 5 (disks) and 2 (CD) by parameter; hps_io 16-bit (WIDE); CD 2048-byte only, TOC and audio from the Main's **hp9k CD layer** windows | SDTR answered with the same period and offset; INQUIRY "SEAGATE ST32550N", "TOSHIBA CD-ROM XM-3301TA" (an IBM-era drive); 1,952 ALMs, 13 M10K with the CD audio |
| `scsi_target.sv` (784) | HP9K385 `rtl/scsi/` | **signal level** (scsi_*_o / scsi_*_i, all lines) | TUR, REZERO, REQUEST SENSE, FORMAT (no-op), READ/WRITE(6/10), SEEK(6/10), INQUIRY, MODE SELECT(6) (taken, dropped), RESERVE/RELEASE, MODE SENSE(6) (3, 4, 3F), START STOP, SEND DIAG, PREVENT, READ CAPACITY, VERIFY, SYNC CACHE; CD: READ TOC, READ SUB-CHANNEL, READ HEADER | units 0..UNITS-1 (IDs = unit numbers), CDROM bit per unit; **CD logical block 512 by default, MODE SELECT with a block descriptor switches 512/2048**; UNIT ATTENTION 28 on a mount; disk requests of up to MAXB (32) blocks; hps_io 16-bit; hp9k CD layer (512-byte requests) | IDENTIFY sets the LUN, **other MESSAGE OUT bytes ignored (no SDTR answer)**; never reselects |
| `scsi_targ.sv` (1,008) | Sun-2_MiSTer `rtl/vendor/wish5380/` | signal level, behind a 5380 fabric | SCSI-1 subset | disks | never disconnects |
| `scsi.v` (3,302) | sgiindy_MiSTer `rtl/scsi/` | signal level with host-read hooks for the WD33C93/HPC3 path | large, CD-heavy | | specific to its controller's pacing |

Fit with this firmware:

- The negotiation entry (1.6) needs **an SDTR answer** (or MESSAGE
  REJECT): MacPPC7300's and the 715's targets answer, HP9K385's ignores it
  (the firmware would then see COMMAND where it waits for MESSAGE IN and
  go through its recovery path; better to add the answer).
- Every target must handle ATN at selection, IDENTIFY with disconnect
  privilege, LUN probes 1-7 (INQUIRY peripheral 7F), a bus reset, and
  BUS DEVICE RESET (free the bus).
- AIX will want the CD's 512-byte mode and MODE SENSE (HP9K385's or the
  715's targets have the most).

Recommendation (section 5.5): keep the bus signal level, wire
**MacPPC7300_scsidisk for the two disks** (the plan's choice; it answers
SDTR and is proven), and for the CD take **HP9K385's `scsi_target` as a
CD-only unit** (512/2048 switching, the hp9k CD contract that the Main
side copies, section 6), adding an SDTR answer to it. Both sit on one
`MacPPC7300_scsibus`-style OR. If one model is preferred, HP9K385's with
the SDTR answer added and a base-ID parameter covers disks and CD.

---

## 5. A proposed RTL design

### 5.1 Where it sits

```
CPU port --> IBMRS6K7248_machine
               | PCI I/O 0x8000_0000+port (both windows), BAR0 match: 256 bytes
               | PCI memory 0xC000_0000+addr, BAR1 match (phase 2)
               | PCI configuration (CF8/CFC, device 16)
               v
             IBMRS6K7248_ncr810         PCI header, registers, interrupt,
               |      \                  the SCRIPTS processor
               |       DMA port (dm_*) --> machine's DMA arbiter --> CPU snoop
               |                                                 --> memory port
               | byte-level bus (sb_*: select, req/phase/data, ack, ackhold, atn, rst)
               v
             IBMRS6K7248_scsiphy        initiator lines: arbitration, selection,
               |                         REQ/ACK, reselection response, RST
               v
             MacPPC7300_scsibus          wired OR, a clock each way
               |            \
   MacPPC7300_scsidisk     scsi_target (CD unit, from HP9K385)
               |            |
               +-- hps_io block devices (clk_mem) --+
```

Files in this repository's style: `rtl/machine/IBMRS6K7248_ncr810.sv`
(registers, PCI header, SCRIPTS engine; ported from hp9000-715's
`ncr53c710.sv`), `rtl/machine/IBMRS6K7248_scsiphy.sv` (new, ~200 lines,
the initiator half of `MacPPC7300_mesh.sv`'s bus logic), and copies of
`MacPPC7300_scsibus.sv`, `MacPPC7300_scsidisk.sv` and HP9K385's
`scsi_target.sv` (renamed `IBMRS6K7248_*` or kept under their names, as
the CPU is).

### 5.2 Bus interface: changes needed in the machine

The S3 already made the device path take words with byte enables and an
`ack` (`s3_design.md` 4.2); the 53C810 uses the same path:

1. **Decode.** `s_isa` covers 8000_0000-807F_FFFF only; the firmware's
   BAR0 is 2000_0000, CPU **A000_0000**, in 8100_0000-BF7F_FFFF ("PCI I/O,
   reads FF" today). New: `s_pciio = p_a[31:30] == 2'b10 && !s_pcicf &&
   !s_iack`, port = `p_a[29:0]`; the 810's hit is `io_on && port[29:8] ==
   bar0[29:8]` in either window (AIX or Linux may assign a low port). A
   second hit for BAR1 in C000_0000-FEFF_FFFF (memory enable, phase 2).
2. **Words with byte enables.** The driver's `in32/out32` of DSA, DSP,
   DSPS, DBC/DCMD, DNAD are one 32-bit cycle each; the 810 takes
   `addr[7:2]`, `be[3:0]` (be[3] the lowest address), `wdata[31:0]` (the
   byte at A in bits 31-8(A&3)): register A in lane A&3. A 32-bit write
   of DSP (all four bytes) starts the processor (the 810 starts on the
   write of DSP's highest byte, 2F). Reads answer the cycle after, all
   lanes; side effects (DSTAT, SIST0/1 clear on read; CTEST2 clears SIGP)
   only for the enabled lanes.
3. **No wait states** are needed for registers. Register accesses during
   a running script are legal (ISTAT, ABRT, SIGP).
4. **PCI configuration**: device 16 in the CF8/CFC decode
   (`cfg_dev16`), as 11 and 14.
5. **IRQ 15**: `irq[15] = s3_irq | scsi_irq` (level; the ELCR already
   makes 15 level).
6. **The DMA port** (5.6) and the CPU's snoop port wired in
   `IBMRS6K7248_system.sv` (today `.snoop_req(1'b0)` at line 123).

### 5.3 The register file (`IBMRS6K7248_ncr810`)

PCI header (as `IBMRS6K7248_firecoral.sv`): 00 = 0001_1000; 04 command
(bits 0 I/O, 1 memory, 2 bus master, 6 parity, 8 SERR writable) and
status (0x0200 medium DEVSEL; bits 15-11 and 8 write-one-to-clear: 13 set
on a master abort, with DSTAT.BF); 08 = 0x0100_00rr (SCSI controller,
revision rr, section 8); 0C latency timer and cache line size writable;
10 BAR0 = {bits 31-8 writable, 8'h01}; 14 BAR1 = {bits 31-8 writable,
8'h00}; 3C interrupt line writable, pin 01, MIN_GNT/MAX_LAT constants.

The 53C810 registers (I/O offset = register address; little-endian
multi-byte registers):

| addr | register | phase 1 behaviour |
|---|---|---|
| 00 | SCNTL0 | stored (ARB, START, WATN, EPC, AAP, TRG) |
| 01 | SCNTL1 | stored; bit 3 RST drives the bus's RST; bit 4 CON reads "connected" |
| 02 | SCNTL2 | bit 7 SDU: set when connected, cleared by a write of 0; a BSY drop while set is UDC |
| 03 | SCNTL3 | stored |
| 04 | SCID | ID (2-0), SRE (5), RRE (6); 0 after SRST |
| 05 | SXFER | stored (offset ignored: asynchronous) |
| 06 | SDID | the encoded target ID for SELECT |
| 07 | GPREG | stored (pins read back as written) |
| 08 | SFBR | first byte of each move from the bus; MOVE to/from SFBR; the data compare's operand |
| 09 | SOCL | stored (low-level mode not modelled) |
| 0A | SSID | VAL (7) + encoded ID of the (re)selector |
| 0B | SBCL | live lines: REQ ACK BSY SEL ATN MSG C/D I/O |
| 0C | DSTAT | DFE (7) always 1, MDPE, BF, ABRT, SSI, SIR, IID; read clears 6-0 |
| 0D | SSTAT0 | ILF/ORF/OLF 0; bit 1 RST = the line |
| 0E | SSTAT1 | FF3-0 = 0; MSG C/D I/O latched at the last REQ |
| 0F | SSTAT2 | LDSC (bit 1) "last disconnect" |
| 10-13 | DSA | |
| 14 | ISTAT | ABRT (w), SRST (w), SIGP (r/w), SEM (r/w), CON, INTF (write 1 clears), SIP, DIP |
| 15-17 | reserved | 0 |
| 18 | CTEST0 | stored |
| 19 | CTEST1 | F0 (DMA FIFO lanes empty) |
| 1A | CTEST2 | SIGP copy (read clears ISTAT.SIGP), CM/DACK bits as QEMU |
| 1B | CTEST3 | revision nibble (7-4), CLF (2) self-clearing, FM, WRIE stored |
| 1C-1F | TEMP | CALL's return address |
| 20 | DFIFO | = DBC[6:0] (FIFO-less: residual 0) |
| 21 | CTEST4 | stored |
| 22 | CTEST5 | stored |
| 23 | CTEST6 | 0 |
| 24-26, 27 | DBC, DCMD | the current instruction's count and opcode |
| 28-2B | DNAD | the next data address |
| 2C-2F | DSP | write of 2F starts the processor (unless DMODE.MAN); reads the next instruction |
| 30-33 | DSPS | the instruction's second word |
| 34-37 | SCRATCHA | |
| 38 | DMODE | stored (BL, MAN) |
| 39 | DIEN | DMA interrupt enables |
| 3A | SBR | stored |
| 3B | DCNTL | stored; STD (start in manual mode), SSM (single step: SSI after each instruction, phase 2), IRQD (gates the pin), COM |
| 3C-3F | ADDER | DSA + the last table offset (informative) |
| 40, 41 | SIEN0, SIEN1 | SCSI interrupt enables |
| 42, 43 | SIST0, SIST1 | MA, CMP, SEL, RSL, SGE, UDC, RST, PAR / STO, GEN, HTH; read clears |
| 44 | SLPAR | stored |
| 46 | MACNTL | type nibble (7-4, read-only) + stored low nibble |
| 47 | GPCNTL | stored |
| 48, 49 | STIME0, STIME1 | SEL (3-0) times the selection; HTH and GEN not modelled in phase 1 |
| 4A | RESPID | stored (the IDs answered on reselection) |
| 4C-4F | STEST0-3 | STEST0 read 0 (or SSAID); STEST3 CSF (1) self-clearing; others stored |
| 50, 54, 58 | SIDL, SODL, SBDL | last byte in / out / the data lines |
| 5C-5F | SCRATCHB | |

`IRQ = ((DSTAT & DIEN & 7D) != 0 || (SIST0 & SIEN0) != 0 || (SIST1 &
SIEN1 & 07) != 0 || INTF) && !DCNTL.IRQD`. Stacking: one pending set of
each kind (DSTAT, SIST0/1) behind the visible one, as the 710 port does
(`dstat_pend`, `sstat0_pend`).

ISTAT.SRST resets the chip's registers (not the PCI header) and stops the
processor; SCNTL1.RST asserts the bus RST for as long as it is set and
raises SIST0.RST (section 8, question 2); a RST seen on the bus stops the
processor, drops the connection and raises SIST0.RST.

### 5.4 The SCRIPTS processor

Ported from `ncr53c710.sv`'s state machine (E_IDLE, E_FETCH, E_DECODE,
E_IND, E_BM_*, E_SEL, E_SEL_WAIT, E_STO, E_WDISC, E_WRESEL, E_TC_*,
E_MM_*, E_INT), with the 810's differences:

- Register addresses 7 bits (00-7F), the 810 map above (the 710's map
  differs throughout).
- Read/write instructions: the 3-bit operator field (26-24): =, SHL, OR,
  XOR, AND, SHR, ADD, ADC (the 710 has four); the three forms (to SFBR,
  from SFBR, read-modify-write).
- Transfer control: relative addressing (bit 23) and INTFLY (bit 20) on
  INT: sets ISTAT.INTF and continues.
- SELECT: encoded ID in bits 19-16; table form loads SCNTL3 (31-24), ID
  (19-16), SXFER (15-8).
- SIST0/SIST1 split from the 710's SSTAT0; STO in SIST1 with STIME0's
  timer (a parameter for the bench: `STO_CLKS`, and the code's scale).
- LOAD/STORE (phase 2): 1-4 bytes between memory and registers.
- MEMORY MOVE: as the 710 (the low two address bits of source and
  destination equal, else IID), counts of 1-4096 and above; to/from the
  chip's own registers when the address hits BAR1 (phase 2).
- Halting: after INT, IID, ABRT, a phase mismatch, STO, UDC, RST: DSP
  points at the next instruction (for a mismatch: past the interrupted
  move), DBC/DNAD hold the remainder, SSTAT1 the phase, CON as the bus is.
- Restart: a DSP write (with DMODE.MAN = 0) from any state but running.
  The bus state survives: a target still holding REQ is served by the next
  instruction; ACK held after MSG_IN stays held until CLEAR ACK or the
  next MSG_IN/out handshake.
- No prefetch (the 810A's; DCNTL.PFEN ignored): instructions are fetched
  each time, so the CPU's patching of the script between commands is
  always seen. The fetch may read one 32-byte line and keep it while DSP
  stays inside it, invalidated on every halt/restart and on any DMA
  write by the chip to that line.

The block move: the byte stream between the bus (sb_*) and a 32-byte
assembly buffer keyed by DNAD's line; writes leave as word writes with
byte enables (or a whole line when full and aligned); reads fetch the
line containing DNAD. SFBR takes the first byte of every move from the
bus (status, message, data); a MSG_OUT move drops ATN before its last
byte; a MSG_IN move's last byte leaves ACK asserted (ackhold).

Phase checks: block moves and WHEN wait for REQ, then compare the phase;
a mismatch on a move halts with SIST0.MA (enabled or not: MA is fatal on
the 810 in initiator mode). IF compares the phase latched at the last REQ.
A target dropping BSY while the processor waits for REQ and SCNTL2.SDU is
set gives SIST0.UDC.

### 5.5 The SCSI bus

`IBMRS6K7248_scsiphy` turns the engine's byte-level requests into lines,
as MESH's sequencer does in `MacPPC7300_mesh.sv` (its commands 1-9):

- Arbitration: bus free (no BSY, no SEL) for a few clocks, BSY + own ID
  bit, win at once (the only initiator), SEL.
- Selection: data lines = own ID bit | target ID bit, ATN if asked, BSY
  released; the target answers with BSY: SEL and the data lines released,
  `sel_done`; no answer within the STO time: everything released,
  `sel_fail` (SIST1.STO). Selecting the own ID gives the same timeout (the
  firmware's ID-conflict test needs exactly that).
- Information phases: wait REQ; in-phases latch the data lines, raise ACK,
  wait for REQ to fall, drop ACK (except under ackhold); out-phases drive
  the byte, raise ACK, wait for REQ to fall, drop ACK and the byte. ATN
  as the engine sets it.
- Bus free / disconnect: BSY falling while connected ends the connection
  (expected under WAIT DISCONNECT, else UDC).
- Reselection (phase 2, nothing reselects in phase 1): SEL + I/O + own ID
  bit with BSY free: when SCID.RRE, answer with BSY, latch the
  reselector's ID into SSID, `resel` to the engine.
- RST: SCNTL1.RST drives it; a received RST resets the PHY.

Timing: the targets' PHASE_US (10 us) phase delay costs 7-8 phase changes
a command, ~80 us; a byte's handshake is ~6-8 clocks through the wired OR
(≈12-16 MB/s at 100 MHz), faster than the SD card behind it.

Targets (section 4): `MacPPC7300_scsidisk` for disks at IDs 0 and 1 (its
hps side on clk_mem, which here is also clk_sys), and HP9K385's
`scsi_target` with UNITS = 1, CDROM = 1 at ID 3 (needs a base-ID
parameter and an SDTR answer), or `MacPPC7300_scsidisk`'s own CD (then
the Main needs the Mac CD layer instead of hp9k's). Their bus outputs ORed
in a `MacPPC7300_scsibus` with a third input.

### 5.6 DMA: memory through the CPU's snoop port

The machine gets MacPPC7300's DMA port (`MacPPC7300_machine.sv` 343-460,
`gdm_*`): one request at a time (`dm_req`, `dm_we`, `dm_line`,
`dm_addr[31:2]`, `dm_be`, `dm_wdata[255:0]` -> `dm_ack`, `dm_rdata`), and
for each access: the line to the CPU's snoop port (the caches write it
back if dirty, drop it on a write), then the memory port as soon as it is
free (before any new CPU access), then for a write a second snoop (drops
a copy fetched in between). Here, in front of `m_*` in
`IBMRS6K7248_machine.sv` (today `m_req = c_req & to_mem & ~dev_busy`):
the CPU's request and the DMA's share `m_*` with `own_cpu`/`own_dma` as
there.

Addresses: the 810 drives PCI addresses; **PCI 8000_0000-FFFF_FFFF is
memory 0000_0000-7FFF_FFFF** (the MPC105's map A window, and
`sys_mem_address`); the memory address then goes through the same bank
decode as the CPU's (`is_ram`, `ram_mb_at`). A PCI address below 8000_0000
or a memory address no bank holds is a master abort: DSTAT.BF, PCI status
bit 13, the processor halted (the firmware's bus-fault path).

Byte order: none to do. The MPC105 keeps bytes at their addresses, so the
810's byte at PCI address 8000_0000 + A is memory byte A, in big-endian
and in little-endian mode alike (in LE mode memory already holds what the
little-endian program meant: the bridge's swap is on the CPU's side). The
line in `dm_rdata` has byte A at bits 255-8(A&31); a SCRIPTS dword is
assembled little-endian from bytes A..A+3 (the firmware stores its program
byte-swapped for exactly this).

Throughput: a word DMA is snoop + SDRAM, ~20-30 clocks; a line ~30-40.
Lines for data, words or a line for fetches: tens of MB/s, far beyond
the SD card. The L2 model, when it comes (`plan.md`), must also be kept
coherent with DMA writes (MacPPC7300's `MacPPC7300_l2` sits between the
machine's memory port and the crossing: the DMA goes through it too).

### 5.7 Interrupt to the CPU

`scsi_irq` to `irq[15]` (ORed with the S3's): the firmware registers one
handler per source on IRQ 15 and calls them in turn; level, so the line
stays up until DSTAT/SIST are read and INTF cleared.

### 5.8 Phase 1: the minimum for the firmware

1. PCI header (device 16): ID, command, status W1C, revision, BAR0 (I/O,
   256 bytes), latency, interrupt line/pin.
2. The machine: PCI I/O decode in both windows against BAR0; words with
   byte enables; IRQ 15; the DMA port with snoop; the snoop port wired.
3. Registers as 5.3 (with DSTAT/SIST read-clear, ISTAT, SRST, ABRT,
   INTF, CTEST3.CLF, STEST3.CSF, DFIFO = DBC, SCID reset values).
4. SCRIPTS: fetch; block moves direct and table indirect in all six
   phases with SFBR, ATN drop and ACK hold; SELECT (absolute and relative
   alternate) with STO; WAIT DISCONNECT; WAIT RESELECT (waits; the
   relative alternate when selected); SET/CLEAR ACK/ATN/TARGET/CARRY;
   register MOVE/OR/AND (all eight operators are cheap) and moves to/from
   SFBR; JUMP/INT/INTFLY (CALL/RETURN cheap too) with phase IF/WHEN and
   data compare with mask, relative and absolute; MEMORY MOVE (1-4096,
   odd counts); phase mismatch, UDC, STO, RST, IID, BF, ABRT halts.
5. The initiator PHY; the bus; two disks and a CD-ROM on hps_io's slots.

That runs: the adapter open (self-test, own-ID STO), the bus reset and
scan (STO for absent IDs, INQUIRY with SDTR negotiation and LUN probes),
the boot device's TUR/START/READ CAPACITY/READ(10), REQUEST SENSE after
CHECK CONDITION, `controller_diags` and `mem_test`.

Bench checks (`sim/`): progress 0x370094 and the scan's 0x0208xx96
codes; the own-ID selection ending in STO (41, not 115); the scan finding
the disk image's INQUIRY; a `boot` of a PReP image from disk 0 (its first
blocks read through the data move); `mem_test` passing (function 15 from
the monitor). The bench needs a disk image server like MacPPC7300's
(`--disk0 FILE`), a short STO (the 810 STO code scaled down) and a way
past the 3 s bus-reset recovery (a snapshot after it, or a bench option).

### 5.9 Phase 2: AIX

- SIGP (ISTAT write, CTEST2 read), WAIT RESELECT's alternate on SIGP,
  reselection answered (RRE, RESPID, SSID, SIST0.RSL), SELECT/JUMP
  from tables, LOAD/STORE, MEMORY MOVE to/from the chip's own registers
  (BAR1 decode), BAR1 memory-mapped registers.
- STIME1/GEN, STIME0.HTH (or a documented "never fires"), DCNTL.SSM
  single step (SSI), DMODE.MAN/DCNTL.STD manual start, SEM.
- SSTAT0/1/2 FIFO flags kept consistent (0) for a residual code that
  reads them; SCSI parity never in error.
- Targets: MODE SENSE pages AIX asks for, the CD's 512/2048 switch, READ
  TOC, UNIT ATTENTION after a mount, CmdQue not reported, WRITE(6)/(10)
  with the Main's write buffer, multi-block hps requests (MAXB).
- Performance: line DMA for data; the disks' read-ahead (one request per
  block now in MacPPC7300's target: two-block buffers) and multi-block
  requests (HP9K385's MAXB 32) with the Main's tight service loop.

---

## 6. The Main_MiSTer side

A new branch cut from `master` (as `plan.md` decides), say
`ibmrs6k-family`, with a self-contained `support/ibmrs6k/` modelled on
`origin/hp9k-family:support/hp9k/` (commit `12b0f43` "support/hp9k,
self-contained", `5bd3995` the write buffer). Pieces to copy (read with
`git -C /home/dani/repos/Main_MiSTer show origin/hp9k-family:support/hp9k/<file>`):

| new file | from | what it does |
|---|---|---|
| `ibmrs6k.h`, `ibmrs6k.cpp` | `hp9k.h`, `hp9k.cpp` (41 + 122 lines) | the model table matched on the RBF name ("IBMRS6K7248": CD slot, write-buffered disk slots), `is_ibmrs6k_family()`, `ibmrs6k_mount_hook` (write-buffer flush on remount, the CD image translated: `*writable = 0`, `f->size` the virtual disc), `ibmrs6k_unmount`, `ibmrs6k_poll`, `ibmrs6k_sd_service` (the disk write buffer, then the CD's windows and translated sectors with `spi_w(UIO_SECTOR_RD | ack)` + `spi_block_write`) |
| `ibmrs6k_disk.cpp/.h` | `hp9k_disk.cpp/.h` (208 + 15; itself Sun's `support/sun/sun_disk.cpp`) | the hard-disk write buffer: 8 runs of up to 64 KB, a write acked at once and gathered, a run written in one `write()` when full, after 20 ms idle or 500 ms age, before an overlapping read and on remount |
| `ibmrs6k_cdrom.cpp/.h` | `hp9k_cdrom.cpp/.h` (476 + 30) | CUE/CHD/raw images served as a flat disc of 2048-byte sectors (512-byte LBAs to the core), the track table at block 0xC000_0000 (`HP9K_CDROM_TOC_BLK`) and audio frames at 0x8000_0000 + 5f; uses master's `support/chd` |
| (later, M7) `ibmrs6k_enet.cpp/.h` | `hp9k_enet.cpp/.h` (295 + 11) | the Ethernet mailbox, as the plan says |

Hooks (the whole of hp9k's `git diff master origin/hp9k-family -- user_io.cpp support.h`,
14 lines): `support.h` includes; in `user_io_file_mount` the mount hook
after Sun's and the unmount in the unmount path; `ibmrs6k_poll()` in
`user_io_poll` beside `sun_poll()`/`hp9k_poll()`; in the block-device
service loop an `else if (int op = ibmrs6k_sd_service(...))` before the
generic path; whether `rtc_is_utc()` should include the family (AIX keeps
the hardware clock in local time or UTC: section 8).

The tight service loop: `origin/fast-mac-scsi` commit `31688f7` ("Mac:
tight service loop for the Quadra 800 hard disks": after serving a
hard-disk request, poll SDSTAT for up to 250 us and serve while requests
keep coming, at most 2 ms a pass; `mac_disk_init/served/wait_next`, a
change of 8 lines in `user_io.cpp`'s loop). The branch's head (`98b4aa6`,
"behind the Mac hooks only") dropped the loop in favour of a change
confined to `support/mac`; for this family it would be
`ibmrs6k_disk_served()`/`ibmrs6k_disk_wait_next()` with the loop change
in `user_io.cpp` (the one hook outside `support/` beyond hp9k's), or left
out at first. Multi-block reads are the core's side (`sd_blk_cnt`):
the Main's generic path already serves up to `UIO_BUFFER_SIZE` (16 KB) a
request.

Do not reuse `support/hp9k` or `support/mac` from the new family (the
plan: self-contained); copy and rename.

The core's side: `CONF_STR` gets block-device slots, e.g. `S0,HDAIMGVHD,
Hard disk 0 (ID 0)`, `S1,..,Hard disk 1 (ID 1)`, `S2,ISOCUECHDBIN,CD-ROM
(ID 3)`, hps_io with `VDNUM(3)` (and the width the chosen targets use:
MacPPC7300's are 8-bit, HP9K385's 16-bit; one hps_io has one width, so
the CD unit or the disks need a width adapter if mixed), the slots in the
model table matching.

---

## 7. Size, roughly

| part | ALMs | M10K |
|---|---|---|
| 53C810 engine ported from `ncr53c710.sv` (2,145 ALMs, 1,737 registers there): + 810 registers (SIST/SIEN split, SCRATCHB, STIME, RESPID, STEST, MACNTL...), 8 operators, INTFLY, LOAD/STORE, 7-bit register space | 2,400-3,000 | 0 (MLAB for a FIFO if kept) |
| PCI header, I/O/memory decode, interrupt | 150-250 | 0 |
| DMA line buffer (32 bytes) and its control | 250-400 | 0 |
| initiator PHY | 150-300 | 0 |
| machine: DMA arbiter + snoop sequencing (MacPPC7300's `dq` machine), PCI I/O window | 150-250 | 0 |
| **chip and glue** | **≈3,100-4,200** | **0-1** |
| `MacPPC7300_scsidisk` (two disks; its CD/Toolbox parts removable) | 1,500-2,500 | 2-8 |
| CD unit (HP9K385's `scsi_target`, one unit), without audio | 1,000-1,500 | 1-2 |
| CD audio (as hp9000-715's `cd_audio`: 501 ALMs, 11 M10K) | +500 | +11 |
| **phase 1 total** | **≈5,500-8,000** | **≈3-12 (+11 with CD audio)** |
| phase 2: reselection, SIGP, timers, load/store, BAR1 | +300-600 | |

For scale: MacPPC7300 with the same CPU fits at about 37,000 ALMs (88 %
of 41,910); with the S3 (5-7 k) and this, the budget is to be watched.

---

## 8. Open questions

1. **Revision ID** of the 7248's 53C810 (PCI 08 and CTEST3's nibble), and
   MACNTL's type nibble: the firmware only prints the revision; AIX may
   choose errata workarounds or the 810A feature set by it. QEMU reports
   0. Read from a real 7248 (`lscfg -vl scsi0`, or the monitor's `in`).
2. **Does SIST0.RST rise when the 810 asserts RST itself** (SCNTL1.RST)?
   The firmware enables the interrupt and, on it, waits 3 s before the
   next command (`SCSI_int_hndlr` 0x9D76C); its scan starts with a bus
   reset. If yes (the reading here of the data manual), every boot pays
   3 s; the bench needs a way past it.
3. **STIME0's SEL code B**: 102.4 ms or 128 ms (the table's base, 100 or
   125 us, with a 40 MHz SCLK). Eight timeouts at boot (IDs 7 and the
   absent ones) are about 1 s; a shorter STO is harmless to the firmware.
4. **LOAD/STORE on the original 53C810** (versus the 810A): implement
   anyway (cheap); does AIX's driver use them, or prefetch (PFEN)?
5. **The planar's SCSI IDs**: which IDs the 7248's own disk and CD-ROM
   use (proposed 0, 1 disks, 3 CD; the firmware scans all, AIX does not
   care), and whether SCSI ID 7 is right for every NVRAM (`fw-scsicfg` can
   change it: card +33).
6. **AIX's CD block size**: does AIX 4.3.3's cd driver MODE SELECT 512-byte
   blocks? Decides whether the CD target must switch (HP9K385's does).
7. **I/O BAR 2000_0000**: confirm the MPC105 in map A forwards CPU
   A000_0000 to PCI I/O 2000_0000 (the PReP map says so) and that nothing
   else (Fire Coral's subtractive decode) claims it. And whether AIX
   keeps the firmware's BAR0 or reprograms it (the decode must follow
   BAR0 in both I/O windows anyway).
8. **GPIO**: what the planar wires to the 810's GPIO0/1 (activity LED,
   terminator power sense?), read by AIX's diagnostics perhaps; GPREG reads
   back what was written for now.
9. **The firmware's `sleep`/`get_timeout_value` scale**: the -1000 =
   ms reading (1.2) decides the bench's costs (the reset waits 2 x 125 ms,
   the handler's 2 ms sleeps between SIST reads) and should be confirmed
   in `convert_to_rtc`.
10. **Target model choice**: one model (HP9K385's, extended with an SDTR
    answer and a base ID) or two (MacPPC7300's disks + HP9K385's CD);
    hps_io's single data width makes mixing them cost an adapter.
11. **Disconnects**: never disconnecting is legal and simplest; does AIX
    perform acceptably with two disks that never disconnect (each command
    holds the bus for its SD-card latency)? Measure before considering a
    disconnecting target.
12. **RTC in UTC** for the family's Main (`rtc_is_utc`): does AIX keep the
    TOD clock in UTC (likely) or local time; the firmware's own clock
    display would then show UTC.
13. **The memory BAR's size and whether SCRIPTS RAM exists**: the 810 has
    none; BAR1 is 256 bytes of registers. Confirm against the data manual
    when phase 2 starts.
