# IBMRS6K7248 bench test: the floppy's ISA DMA in little-endian mode, the little-endian half (assembled
# for powerpcle; runs in real mode at 0x10000). It programs DMA channel 2 as Solaris 2.5.1's fd driver
# does (single mode, write to memory, 512 bytes, page 81 and high page 481 = 80: PCI 0x80020000, RAM
# 0x20000), reads C0 H0 R1 by DMA (SPECIFY with ND off), and checks the boot sector's bytes per sector
# (offsets 11-12, little-endian 0x0200) with little-endian loads: "FDMA OK" or "FDMA BAD" on COM1,
# then the two bytes, then 0x0B-0x0C of every doubleword-reversal candidate is left to --memdump.

#define r3 3
#define r4 4
#define r5 5
#define r6 6
#define r7 7
#define r8 8
#define r9 9
#define r10 10
#define r11 11
#define r31 31

	.set	IO, 0x80000000
	.set	BUF, 0x00020000

	.macro	li32 r, v
	lis	\r, (\v)@h
	ori	\r, \r, (\v)@l
	.endm

	# out \port, the byte in r4
	.macro	outb port
	li32	r9, IO + \port
	stb	r4, 0(r9)
	eieio
	.endm

	.macro	outi port, v
	li	r4, \v
	outb	\port
	.endm

	.text
	.globl	_start
_start:
	li	r4, 0x40
	outb	0x80			# progress 40: in little-endian code

	# the controller out of reset: motor A, DMA and interrupts on, drive 0
	outi	0x3F2, 0x00
	outi	0x3F2, 0x1C
	outi	0x3F7, 0x00		# 500 kbps
	li	r3, 4			# the reset's four SENSE INTERRUPT STATUS
1:	li	r4, 0x08
	bl	fput
	bl	fres
	addi	r3, r3, -1
	cmpwi	r3, 0
	bne	1b

	li	r4, 0x03		# SPECIFY: DMA mode (ND off)
	bl	fput
	li	r4, 0xDF
	bl	fput
	li	r4, 0x28
	bl	fput

	# the buffer filled with 5A (dirty in the data cache when it is on), then read back
	li32	r5, BUF
	li	r6, 512
	mtctr	r6
	li	r4, 0x5A
10:	stb	r4, 0(r5)
	addi	r5, r5, 1
	bdnz	10b
	li32	r5, BUF
	lbz	r6, 0x0B(r5)

	# DMA channel 2: Solaris's sequence
	outi	0x0A, 0x06		# mask 2
	outi	0x0B, 0x46		# single, write to memory, channel 2
	outi	0x0C, 0x00
	outi	0x04, 0x00		# the address 0x0000
	outi	0x04, 0x00
	outi	0x81, 0x02		# page: 0x020000
	outi	0x481, 0x80		# high page: PCI 0x80020000
	outi	0x0C, 0x00
	outi	0x05, 0xFF		# 512 bytes
	outi	0x05, 0x01
	outi	0x0A, 0x02		# unmask 2

	li	r4, 0xE6		# READ DATA (MT, MFM, SK): C0 H0 R1 N2 EOT 18
	bl	fput
	li	r4, 0x00
	bl	fput
	li	r4, 0x00
	bl	fput
	li	r4, 0x00
	bl	fput
	li	r4, 0x01
	bl	fput
	li	r4, 0x02
	bl	fput
	li	r4, 0x12
	bl	fput
	li	r4, 0x1B
	bl	fput
	li	r4, 0xFF
	bl	fput
	bl	irqwait
	bl	fres

	li	r4, 0x41
	outb	0x80			# progress 41: the read is done

	# the boot sector's bytes per sector, little-endian at 0x2000B
	li32	r5, BUF
	lbz	r6, 0x0B(r5)
	lbz	r7, 0x0C(r5)
	cmpwi	r6, 0x00
	bne	bad
	cmpwi	r7, 0x02
	bne	bad
	li32	r10, MSG_OK - _start + 0x10000
	b	say
bad:	li32	r10, MSG_BAD - _start + 0x10000
say:	lbz	r4, 0(r10)
	cmpwi	r4, 0
	beq	2f
	outb	0x3F8
	addi	r10, r10, 1
	b	say
2:	mr	r4, r6
	bl	hex
	mr	r4, r7
	bl	hex
	li	r4, 0x0A
	outb	0x3F8
	li	r4, 0xDD
	outb	0x80			# progress DD: the end
3:	b	3b

	# a command byte r4 to the FIFO when MSR says RQM and not DIO
fput:	li32	r9, IO + 0x3F4
4:	lbz	r8, 0(r9)
	andi.	r8, r8, 0xC0
	cmpwi	r8, 0x80
	bne	4b
	stb	r4, 1(r9)
	eieio
	blr

	# read the result bytes until the controller wants a command again
fres:	li32	r9, IO + 0x3F4
5:	lbz	r8, 0(r9)
	andi.	r8, r8, 0xD0
	cmpwi	r8, 0xD0
	bne	6f
	lbz	r8, 1(r9)
	b	5b
6:	cmpwi	r8, 0x80
	bne	5b
	blr

	# wait for the end of a command: MSR not busy with results, or RQM with DIO (the result phase)
irqwait:
	li32	r9, IO + 0x3F4
7:	lbz	r8, 0(r9)
	andi.	r8, r8, 0xD0
	cmpwi	r8, 0xD0
	bne	7b
	blr

	# r4 as two hex digits to COM1
hex:	mflr	r11
	mr	r31, r4
	rlwinm	r4, r31, 28, 28, 31
	bl	nyb
	rlwinm	r4, r31, 0, 28, 31
	bl	nyb
	li	r4, 0x20
	outb	0x3F8
	mtlr	r11
	blr
nyb:	cmpwi	r4, 10
	blt	8f
	addi	r4, r4, 0x37
	b	9f
8:	addi	r4, r4, 0x30
9:	li32	r9, IO + 0x3F8
	stb	r4, 0(r9)
	eieio
	blr

MSG_OK:	.asciz	"FDMA OK "
MSG_BAD: .asciz	"FDMA BAD "
