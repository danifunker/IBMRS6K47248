# IBMRS6K7248 bench test: little-endian mode, the little-endian half (linked at
# FFF02000, assembled with -mlittle; see le_be.S). Runs with MSR[LE] and the
# MPC105's LE_MODE set: loads the big-endian patterns at 0x1000, stores what it
# reads to 0x2000 (the big-endian half checks the bytes), compares its loads
# itself (r30: a bit for each mismatch), takes one alignment exception, and
# returns with sc.

	.set	RES, 0x2000

	.macro	li32 r, v
	lis	\r, (\v)@h
	ori	\r, \r, (\v)@l
	.endm

	.text
	.globl	_le
_le:
	li	r4, 0x1000
	li	r6, RES
	li	r30, 0

	lwz	r5, 0(r4)		# memory 11 22 33 44: 0x44332211
	stw	r5, 0x00(r6)
	li32	r7, 0x44332211
	cmpw	r5, r7
	beq	1f
	ori	r30, r30, 1
1:	lbz	r5, 1(r4)		# 0x22
	stw	r5, 0x04(r6)
	cmpwi	r5, 0x22
	beq	2f
	ori	r30, r30, 2
2:	lhz	r5, 2(r4)		# 0x4433
	stw	r5, 0x08(r6)
	cmpwi	r5, 0x4433
	beq	3f
	ori	r30, r30, 4
3:	lwz	r5, 4(r4)		# 0x88776655
	stw	r5, 0x0C(r6)
	bl	sub			# a call and a return in little-endian mode
	li	r5, 0xAB
	stb	r5, 0x10(r6)
	li	r5, 0x1234
	sth	r5, 0x12(r6)
	li32	r5, 0xCAFEBABE
	stw	r5, 0x14(r6)
	lwbrx	r5, 0, r4		# 0x11223344
	stw	r5, 0x18(r6)
	stw	r30, 0x1C(r6)
	nop
	lwz	r5, 1(r4)		# misaligned: an alignment exception (at FFF02088)
	li32	r5, 0x600DC0DE
	stw	r5, 0x2C(r6)
	sc

sub:	li32	r7, 0x88776655
	cmpw	r5, r7
	beqlr
	ori	r30, r30, 8
	blr
