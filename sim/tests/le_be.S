# IBMRS6K7248 bench test: little-endian mode (the CPU's munging, the MPC105's swap)
# The big-endian half: the vectors, the set-up, the checks. Built with le_le.S into
# le_test.rom (sim/tests/Makefile); run with: machine_tb --rom tests/le_test.rom --ram 8
# Prints on COM1 one line per check ("ok" or "FAIL got X want Y") and a last line,
# "LE PASS" or "LE FAIL".

	.set	CF8, 0x80000CF8
	.set	CFC, 0x80000CFC
	.set	THR, 0x800003F8
	.set	RES, 0x2000		# results the little-endian code leaves

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

	.org	0x600			# alignment: taken in little-endian mode with ILE set, so the
	.long	0			# vector runs little-endian: the Makefile puts a little-endian
					# "ba" to the handler in le_le.S here

	.org	0xC00			# system call: back from the little-endian code
	b	checks

	.org	0x1000
setup:
	# RAM: bank 0 at 0-8 MB (the bench's --ram 8, one pair of 4 MB SIMMs)
	li	r4, 0
	cfgw	0x80			# starting addresses: bank 0 at 0
	cfgw	0x88
	cfgw	0x98
	li	r4, 0x07
	cfgw	0x90			# ending address: bank 0's last MB, 7
	li	r4, 0x01
	cfgw	0xA0			# bank 0 enabled

	# the patterns, stored big-endian: 11 22 33 44 55 66 77 88 at 0x1000
	li	r4, 0x1000
	li32	r3, 0x11223344
	stw	r3, 0(r4)
	li32	r3, 0x55667788
	stw	r3, 4(r4)
	# the result area cleared
	li	r6, RES
	li	r3, 0
	li	r5, 16
1:	stw	r3, 0(r6)
	addi	r6, r6, 4
	addic.	r5, r5, -1
	bne	1b

	# The instruction cache on: once the bridge swaps, a big-endian fetch from the bus
	# is scrambled, so the switch below runs from the cache (as real code must).
	mfspr	r3, 1008		# HID0
	ori	r3, r3, 0x8800		# ICE, ICFI
	mtspr	1008, r3
	isync
	rlwinm	r3, r3, 0, 21, 19	# ICFI off
	mtspr	1008, r3
	isync

	# the bridge into little-endian mode (PICR1 bit 5) and the CPU with it, by rfi;
	# the block runs twice, the first time only to bring it into the cache
	li32	r3, 0x00011040		# ILE first, by mtmsr (rfi does not restore it), still big-endian
	mtmsr	r3
	isync
	li32	r3, 0xFFF02000
	mtsrr0	r3
	li	r3, 0x1041		# ME, IP, LE
	mtsrr1	r3
	li32	r20, CF8
	li32	r21, 0x800000A8
	stwbrx	r21, 0, r20
	li32	r20, CFC
	li	r4, 0x20
	li	r31, 0
	b	switch
	.balign	32
switch:	cmpwi	r31, 0
	beq	11f
	stwbrx	r4, 0, r20
	rfi
11:	li	r31, 1
	b	switch

checks:
	# the bridge back to big-endian
	li	r4, 0
	cfgw	0xA8
	li	r29, 0			# failures
	li	r6, RES
	lis	r7, table@h
	ori	r7, r7, table@l
2:	lwz	r8, 0(r7)		# offset in the result area, or -1 at the end
	cmpwi	r8, -1
	beq	3f
	lwz	r9, 4(r7)		# the value wanted
	lwzx	r10, r6, r8
	mr	r3, r8
	bl	puthex
	li	r3, ' '
	bl	putc
	cmpw	r10, r9
	bne	4f
	li	r3, 'o'
	bl	putc
	li	r3, 'k'
	bl	putc
	b	5f
4:	addi	r29, r29, 1
	li	r3, 'F'
	bl	putc
	li	r3, ' '
	bl	putc
	mr	r3, r10
	bl	puthex
	li	r3, '/'
	bl	putc
	mr	r3, r9
	bl	puthex
5:	li	r3, '\n'
	bl	putc
	addi	r7, r7, 8
	b	2b
3:	li	r3, 'L'
	bl	putc
	li	r3, 'E'
	bl	putc
	li	r3, ' '
	bl	putc
	cmpwi	r29, 0
	bne	6f
	li	r3, 'P'
	bl	putc
	li	r3, 'A'
	bl	putc
	li	r3, 'S'
	bl	putc
	bl	putc
	b	7f
6:	li	r3, 'F'
	bl	putc
	li	r3, 'A'
	bl	putc
	li	r3, 'I'
	bl	putc
	li	r3, 'L'
	bl	putc
7:	li	r3, '\n'
	bl	putc
8:	b	8b

putc:	li32	r20, THR
	stb	r3, 0(r20)
	eieio
	blr

puthex:	mflr	r25
	mr	r24, r3
	li	r23, 8
9:	rlwinm	r24, r24, 4, 0, 31
	andi.	r3, r24, 15
	cmpwi	r3, 10
	blt	10f
	addi	r3, r3, 'A' - '0' - 10
10:	addi	r3, r3, '0'
	bl	putc
	addic.	r23, r23, -1
	bne	9b
	mtlr	r25
	blr

	# offset, value wanted (big-endian reads of what the little-endian code stored)
	.align	2
table:
	.long	0x00, 0x11223344	# lwz 1000 (44332211), stored back
	.long	0x04, 0x22000000	# lbz 1001 (22)
	.long	0x08, 0x33440000	# lhz 1002 (4433)
	.long	0x0C, 0x55667788	# lwz 1004 (88776655)
	.long	0x10, 0xAB003412	# stb AB at 2010, sth 1234 at 2012
	.long	0x14, 0xBEBAFECA	# stw CAFEBABE at 2014
	.long	0x18, 0x44332211	# lwbrx 1000 (11223344)
	.long	0x1C, 0x00000000	# the little-endian code's own compares: no mismatch
	.long	0x20, 0x8820F0FF	# the misaligned load's address, SRR0 FFF02088 (stored little-endian)
	.long	0x24, 0x01100000	# its effective address, DAR 00001001, unmunged (likewise)
	.long	0x2C, 0xDEC00D60	# the little-endian code ran to its end: 600DC0DE (likewise)
	.long	-1, 0
