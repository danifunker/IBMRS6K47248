# IBMRS6K7248 bench test: the ARC diskette's switch to little-endian (rs6karc151.img, 2.11 EC)
# Big-endian, it copies a block into RAM, turns the instruction cache on and the data cache off
# (as ARC does), sets port 92 bit 1, waits, and rfi's into the block with MSR[LE] and ILE set.
# The block starts with a "sled" of 38010138 words, the same addi in either byte order (ARC's own
# trick), crossing doublewords and a cache line, then little-endian code that writes progress 38 to
# port 80 and "LE OK" to COM1, and loops. Built by sim/tests/Makefile into le_sled.rom; run with:
# machine_tb --rom tests/le_sled.rom --ram 8 --hang 2000000

#ifdef __clang__
/* (clang's assembler, where binutils for PowerPC is missing: registers by number) */
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
#define r14 14
#define r15 15
#define r16 16
#define r17 17
#define r18 18
#define r19 19
#define r20 20
#define r21 21
#define r22 22
#define r23 23
#define r24 24
#define r25 25
#define r26 26
#define r27 27
#define r28 28
#define r29 29
#define r30 30
#define r31 31
#endif

	.set	CF8, 0x80000CF8
	.set	CFC, 0x80000CFC
	.set	BLOCK, 0x10000		# where the block runs, in RAM

	.macro	li32 r, v
	lis	\r, (\v)@h
	ori	\r, \r, (\v)@l
	.endm

	# an MPC105 configuration write: register \reg (bus 0 device 0), value in r4
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
	# RAM: bank 0 at 0-8 MB (the bench's --ram 8)
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

	.ifdef	DIRTY
	# (variant: the data cache on for the copy, so the block sits dirty in it when ARC's HID0
	# write turns the cache off without a flush)
	mfspr	r3, 1008
	ori	r3, r3, 0x4400		# DCE, DCFI
	mtspr	1008, r3
	isync
	rlwinm	r3, r3, 0, 22, 20	# DCFI off
	mtspr	1008, r3
	isync
	.endif
	# the block into RAM (the data cache is off, unless DIRTY)
	li32	r5, 0xFFF00000 + (block - _start)
	li32	r6, BLOCK
	li	r7, (block_end - block) / 4
	mtctr	r7
1:	lwz	r3, 0(r5)
	stw	r3, 0(r6)
	addi	r5, r5, 4
	addi	r6, r6, 4
	bdnz	1b
	sync

	# HID0 as ARC sets it: the instruction cache invalidated and on, the data cache off
	mfspr	r2, 1008
	ori	r9, r2, 0x0800		# ICFI
	ori	r2, r2, 0x8000		# ICE
	rlwinm	r2, r2, 0, 18, 16	# not DCE
	mtspr	1008, r9
	sync
	mtspr	1008, r2
	isync

	# ILE first (rfi does not set it), then port 92 bit 1, ARC's delay, and the rfi
	li32	r3, 0x00011040
	mtmsr	r3
	isync
	li32	r3, BLOCK
	mtsrr0	r3
	li32	r3, 0x00011001		# ILE, ME, LE
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

	# the block: the sled, then little-endian code, stored as ARC stores it: in RAM each doubleword
	# reversed (the bridge does not swap memory; the CPU's munging finds each word at the other half)
	.balign	32
block:
	.rept	42
	.long	0x38010138
	.endr
	.long	0x3F008000		# +4: lis r24, 0x8000
	.long	0x60000000		# +0: nop
	.long	0x3AE00038		# +4: li r23, 0x38
	.long	0x63180080		# +0: ori r24, r24, 0x80
	.long	0x3C608000		# +4: lis r3, 0x8000
	.long	0x9AF80000		# +0: stb r23, 0(r24): progress 38
	.long	0x3880004C		# +4: li r4, 'L'
	.long	0x606303F8		# +0: ori r3, r3, 0x3F8
	.long	0x38800045		# +4: li r4, 'E'
	.long	0x98830000		# +0: stb r4, 0(r3)
	.long	0x38800020		# +4: li r4, ' '
	.long	0x98830000		# +0: stb r4, 0(r3)
	.long	0x3880004F		# +4: li r4, 'O'
	.long	0x98830000		# +0: stb r4, 0(r3)
	.long	0x3880004B		# +4: li r4, 'K'
	.long	0x98830000		# +0: stb r4, 0(r3)
	.long	0x3880000A		# +4: li r4, '\n'
	.long	0x98830000		# +0: stb r4, 0(r3)
	.long	0x48000000		# +4: b .
	.long	0x98830000		# +0: stb r4, 0(r3)
	.balign	32
block_end:
