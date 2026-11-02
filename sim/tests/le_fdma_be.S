# IBMRS6K7248 bench test: the floppy's ISA DMA in little-endian mode (Solaris 2.5.1's fd driver,
# 2026-11-01). The big-endian half: sets the MPC105 up (8 MB), copies the little-endian half
# (le_fdma_le.S) from the ROM into RAM at 0x10000, turns the instruction cache on and the data cache
# off (as ARC does), sets ILE, port 92 bit 1, and rfi's into it with MSR LE (real mode).
# DCACHE (le_fdma_dc.rom): the data cache on, and the buffer dirty in it before the read.
# Built by sim/tests/Makefile into le_fdma.rom; run with the diskette as the floppy:
#   machine_tb --rom tests/le_fdma.rom --ram 8 --floppy <a FAT diskette> --hang 4000000 --memdump m.bin

#define r2 2
#define r3 3
#define r4 4
#define r5 5
#define r6 6
#define r7 7
#define r8 8
#define r9 9
#define r13 13
#define r20 20
#define r21 21

	.set	CF8, 0x80000CF8
	.set	CFC, 0x80000CFC
	.set	BLOB_ROM, 0xFFF10000	# the little-endian half in the ROM image
	.set	BLOB_RAM, 0x00010000	# ... and where it runs
	.set	BLOB_LEN, 0x1000

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

	li32	r5, BLOB_ROM
	li32	r6, BLOB_RAM
	li	r7, BLOB_LEN / 4
	mtctr	r7
1:	lwz	r3, 0(r5)
	stw	r3, 0(r6)
	addi	r5, r5, 4
	addi	r6, r6, 4
	bdnz	1b
	sync

	mfspr	r2, 1008
	ori	r9, r2, 0x0800		# ICFI
	ori	r2, r2, 0x8000		# ICE
#ifdef DCACHE
	ori	r2, r2, 0x4000		# DCE (the variant: the data cache on, as Solaris runs)
#else
	rlwinm	r2, r2, 0, 18, 16	# not DCE
#endif
	mtspr	1008, r9
	sync
	mtspr	1008, r2
	isync

#ifdef DCACHE
	# translation on, as an OS runs: RAM (8 MB at 0) cached and coherent, the I/O at 0x80000000
	# (256 MB) cache-inhibited and guarded; in real mode the 604 caches every address
	li32	r3, 0x000000FF
	mtspr	528, r3			# IBAT0U: 0, 8 MB
	mtspr	536, r3			# DBAT0U
	li32	r3, 0x00000012
	mtspr	529, r3			# IBAT0L: M, read/write
	mtspr	537, r3			# DBAT0L
	li32	r3, 0x80001FFF
	mtspr	538, r3			# DBAT1U: 0x80000000, 256 MB
	li32	r3, 0x8000002A
	mtspr	539, r3			# DBAT1L: I, G, read/write
	isync
#endif
#ifdef DCACHE
	li32	r3, 0x00011050		# ILE first, and DR: port 92 through DBAT1
#else
	li32	r3, 0x00011040		# ILE first
#endif
	mtmsr	r3
	isync
	li32	r3, BLOB_RAM
	mtsrr0	r3
#ifdef DCACHE
	li32	r3, 0x00011031		# ILE, ME, IR, DR, LE
#else
	li32	r3, 0x00011001		# ILE, ME, LE
#endif
	mtsrr1	r3
	li32	r13, 0x80000092
	li	r5, 2
	sync
	stb	r5, 0(r13)
	sync
	li	r8, 0x100
	mtctr	r8
2:	bdnz	2b
	rfi
