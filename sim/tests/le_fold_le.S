# IBMRS6K7248 bench test: the NT kernel's phantom trap, the little-endian blob (assembled for
# powerpcle; runs at VA 0x800A2000, physical 0xA2000). Offsets below are from the blob's start.
#   0x0000  the driver: for 4096 iterations, with the data varied by the iteration's low bits, runs
#           the kernel's code from entry A (0x800A3B54: the bdnz loop of 2 at 3B78 whose beq cr1 at
#           3B80 is the SRR0 of NT's phantom trap, then the list loop at 3C24) and from entry B
#           (0x800A3CAC: the bl at 3CC4, the copy 3CCC-3D00, the beq cr1 at 3D04 that LR named)
#   0x0800  S (r31's structure), 0x0E00 P, 0x0E80 Q, 0x0F00 R (list items), 0x1000 W (r27's)
#   0x1A80  the kernel's words 0x800A3A80-0x800A3D60, verbatim (le_fold_kernel.inc)
#   0x27A4  the exit at 0x800A47A4 (back to the driver), 0x2820 the error exit at 0x800A4820
#   0x2F08  the stub for 0x8006F688 (blr), 0x2F80 for 0x800B6A60 (r3 = Q; blr): copied there
# Prints "FOLD OK" on COM1 at the end, then the error-exit count as a progress word and DD to
# port 80; a program exception stops in the handler at 0x700 (EE to port 80).

#define r0 0
#define r2 2
#define r3 3
#define r4 4
#define r5 5
#define r6 6
#define r7 7
#define r20 20
#define r21 21
#define r22 22
#define r23 23
#define r24 24
#define r27 27
#define r29 29
#define r30 30
#define r31 31

	.set	BASE, 0x800A2000
	.set	S, BASE + 0x0800
	.set	P, BASE + 0x0E00
	.set	Q, BASE + 0x0E80
	.set	R, BASE + 0x0F00
	.set	W, BASE + 0x1000
	.set	TOC, 0x800A3800			# r2: the kernel's lwz r10,-0x7924(r2) at 3B5C reads 0x8009BEDC
	.set	IO, 0xC0000000
	.set	N, 4096
	.set	MSG, BASE + 0x180		# the message (a fixed place: no relocations survive objcopy)

	.macro	li32 r, v
	lis	\r, (\v)@h
	ori	\r, \r, (\v)@l
	.endm

	.text
	.globl	_start
_start:
	li32	r31, S
	li32	r2, TOC
	li32	r24, IO
	li	r20, 0			# the iteration
	li	r22, 0			# error exits taken
loop:
	# the data: R at 0x8009BEDC (3B5C/3B60 copy it to S+0x208, 3C14 reads it back as the list);
	# S+0x2f4 = 0 or P (bit 0): 3D04's beq cr1 taken or not; R+8 = R+0x18 = 0 or 1 (bit 1): the
	# list loop's beq cr1 at 3C30 taken or the call at 3C60; R+4 = R
	li32	r5, R
	li32	r6, 0x8009BEDC
	stw	r5, 0(r6)
	stw	r5, 4(r5)
	li	r7, 0
	stw	r7, 0x200(r31)
	stw	r7, 0x204(r31)
	andi.	r6, r20, 1
	beq	1f
	li32	r7, P
1:	stw	r7, 0x2f4(r31)
	li	r7, 0
	andi.	r6, r20, 2
	beq	2f
	li	r7, 1
2:	stw	r7, 8(r5)
	stw	r7, 0x18(r5)
	# every 256 iterations a progress word
	andi.	r6, r20, 0xFF
	bne	3f
	stw	r20, 0x680(r24)
3:
	# entry A
	li32	r27, W
	li	r30, 0x18
	li	r29, 0
	li32	r3, Q
	li	r21, 0
	li32	r7, 0x800A3B54
	mtctr	r7
	bctr
retA:
	# entry B
	li32	r27, W
	li	r30, 0x18
	li	r29, 0
	li32	r3, Q
	li	r21, 1
	li32	r7, 0x800A3CAC
	mtctr	r7
	bctr
retB:
	addi	r20, r20, 1
	cmplwi	r20, N
	blt	loop

	# done
	li32	r3, MSG
	li	r4, 0
4:	lbzx	r5, r3, r4
	cmpwi	r5, 0
	beq	5f
	stb	r5, 0x3F8(r24)
	addi	r4, r4, 1
	b	4b
5:	li	r5, 0x0A
	stb	r5, 0x3F8(r24)
	stw	r22, 0x680(r24)		# the error count as a progress word
	li	r5, 0xDD
	stb	r5, 0x80(r24)
6:	b	6b

ret_dispatch:
	cmpwi	r21, 0
	beq	retA
	b	retB

	.org	0x180
msg:	.asciz	"FOLD OK"

	.org	0x1A80
#include "le_fold_kernel.inc"

	.org	0x27A4			# 0x800A47A4: where both paths leave the function
	b	ret_dispatch

	.org	0x2820			# 0x800A4820: the kernel's error exit
	addi	r22, r22, 1
	b	ret_dispatch

	.org	0x2F08			# 0x8006F688 (the bl at 3C60)
	blr

	.org	0x2F80			# 0x800B6A60 (the bl at 3CC4): returns Q
	li32	r3, Q
	blr

	.org	0x2FF0
	.long	0
