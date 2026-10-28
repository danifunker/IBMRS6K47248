# IBMRS6K7248 bench test: the NT kernel's phantom trap (2026-10-28). The big-endian half: sets the
# MPC105 up, copies the little-endian blob (le_fold_le.S: a driver and the kernel's own words from
# 0x800A3A80-0x800A3D60, verbatim) from the ROM into RAM at the kernel's physical addresses, maps
# 0x80000000 (8 MB) to RAM 0 with BAT0 and the I/O at 0xC0000000 with DBAT1, writes a little-endian
# program-exception handler at RAM 0x700, turns both caches on, and rfi's into the blob with the
# kernel's MSR (00013031: ILE FP ME IR DR LE; IP clear, so the vectors are in RAM).
# Built by sim/tests/Makefile into le_fold.rom; see scratch/work/run_fold.sh.

#ifdef __clang__
#define r0 0
#define r1 1
#define r2 2
#define r3 3
#define r4 4
#define r5 5
#define r6 6
#define r7 7
#define r8 8
#define r9 9
#define r10 10
#define r11 11
#define r12 12
#define r13 13
#define r20 20
#define r21 21
#define r31 31
#endif

	.set	CF8, 0x80000CF8
	.set	CFC, 0x80000CFC
	.set	BLOB_ROM, 0xFFF10000	# the blob in the ROM image
	.set	BLOB_RAM, 0x000A2000	# ... and where it runs (VA 0x800A2000)
	.set	BLOB_LEN, 0x3000

	.macro	li32 r, v
	lis	\r, (\v)@h
	ori	\r, \r, (\v)@l
	.endm

	.macro	cfgw reg
	li32	r20, CF8
	li32	r21, 0x80000000 + \reg
	stwbrx	r21, 0, r20
	li32	r20, CFC
	stwbrx	r4, 0, r20
	eieio
	.endm

	# copy \len bytes from ROM offset \src (in the blob) to RAM \dst, words, data cache off
	.macro	copy src, dst, len
	li32	r5, BLOB_ROM + \src
	li32	r6, \dst
	li	r7, (\len) / 4
	mtctr	r7
1:	lwz	r3, 0(r5)
	stw	r3, 0(r6)
	addi	r5, r5, 4
	addi	r6, r6, 4
	bdnz	1b
	.endm

	# a little-endian instruction word \w stored at RAM \addr: in this mode (port 92, no bridge swap)
	# the CPU's munging reads the word for PC addr from the other half of its doubleword, big-endian
	.macro	lew addr, w
	li32	r6, (\addr) ^ 4
	li32	r3, \w
	stw	r3, 0(r6)
	.endm

	.text
	.globl	_start
_start:
	.org	0x100
	b	setup

	.org	0x1000
setup:
	li	r4, 0
	cfgw	0x80
	cfgw	0x88
	cfgw	0x98
	li	r4, 0x07
	cfgw	0x90
	li	r4, 0x01
	cfgw	0xA0
	li32	r3, 0x00001040		# ME, IP
	mtmsr	r3
	isync

	# the blob and the two call stubs
	copy	0x0000, BLOB_RAM, BLOB_LEN
	copy	0x2F00, 0x0006F680, 0x40		# the stub for the kernel's bl at 3C60 (0x8006F688)
	copy	0x2F80, 0x000B6A60, 0x40		# ... and at 3CC4 (0x800B6A60)

	# the program-exception handler at 0x700, little-endian (IR/DR off there): SRR0 then SRR1 shown
	# as LR on the bench's io trace of two port-80 writes (E0, E1), then a stop (the stall limit)
	lew	0x700, 0x7C70FAA6		# mfspr r3, HID0
	lew	0x704, 0x5463045E		# rlwinm r3, r3, 0, 17, 15: DCE off (real mode would cache the ports)
	lew	0x708, 0x7C70FBA6		# mtspr HID0, r3
	lew	0x70C, 0x7C0004AC		# sync
	lew	0x710, 0x3C608000		# lis r3, 0x8000
	lew	0x714, 0x7CBA02A6		# mfsrr0 r5
	lew	0x718, 0x7CA803A6		# mtlr r5
	lew	0x71C, 0x388000E0		# li r4, 0xE0
	lew	0x720, 0x98830080		# stb r4, 0x80(r3)
	lew	0x724, 0x7C0004AC		# sync
	lew	0x728, 0x7CBB02A6		# mfsrr1 r5
	lew	0x72C, 0x7CA803A6		# mtlr r5
	lew	0x730, 0x388000E1		# li r4, 0xE1
	lew	0x734, 0x98830080		# stb r4, 0x80(r3)
	lew	0x738, 0x7C0004AC		# sync
	lew	0x73C, 0x48000000		# b .
	sync

	# BATs: 0x80000000 (8 MB) to RAM 0, instructions and data; the I/O at 0xC0000000 (256 MB)
	li32	r3, 0x800000FE
	mtspr	528, r3			# IBAT0U: 8 MB
	li	r3, 0x0002
	mtspr	529, r3			# IBAT0L
	li32	r3, 0x800000FE
	mtspr	536, r3			# DBAT0U: 8 MB
	li	r3, 0x0002
	mtspr	537, r3			# DBAT0L
	li32	r3, 0xC0001FFE
	mtspr	538, r3			# DBAT1U
	li32	r3, 0x8000002A
	mtspr	539, r3			# DBAT1L: I, G
	isync

	# ILE first, port 92 bit 1 (the bridge into little-endian mode), ARC's delay
	li32	r3, 0x00011040
	mtmsr	r3
	isync
	li32	r3, 0x80000000 + BLOB_RAM
	mtsrr0	r3
	li32	r3, 0x00013031		# ILE, FP, ME, IR, DR, LE
	mtsrr1	r3
	li32	r13, 0x80000092
	li	r5, 2
	sync
	stb	r5, 0(r13)
	sync
	li	r8, 0x100
	mtctr	r8
2:	bdnz	2b

	# both caches on, flash-invalidated (after the port-92 write: in real mode the 604 caches every store)
	mfspr	r3, 1008
	ori	r3, r3, 0xCC00		# ICE, DCE, ICFI, DCFI
	mtspr	1008, r3
	isync
	rlwinm	r3, r3, 0, 22, 19
	mtspr	1008, r3
	isync

	rfi
