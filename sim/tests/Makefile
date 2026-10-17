# Test ROMs for the machine bench (512 KB images mapped at FFF00000).
#   make            build le_test.rom
AS      := powerpc-linux-gnu-as
LD      := powerpc-linux-gnu-ld
OBJCOPY := powerpc-linux-gnu-objcopy

all: le_test.rom

le_be.bin: le_be.S
	$(AS) -mregnames -o le_be.o $<
	$(LD) -Ttext=0xFFF00000 -o le_be.elf le_be.o
	$(OBJCOPY) -O binary le_be.elf $@

le_le.bin: le_le.S
	$(AS) -mregnames -mlittle -o le_le.o $<
	$(LD) -EL -e _le -Ttext=0xFFF02000 -o le_le.elf le_le.o
	$(OBJCOPY) -O binary le_le.elf $@

# the big-endian half, the little-endian half at 0x2000, padded with FF to 512 KB
le_test.rom: le_be.bin le_le.bin
	python3 -I -c "import sys; be=open('le_be.bin','rb').read(); le=open('le_le.bin','rb').read(); assert len(be) <= 0x2000, len(be); img=bytearray(b'\xff'*0x80000); img[:len(be)]=be; img[0x2000:0x2000+len(le)]=le; open('$@','wb').write(img)"

clean:
	rm -f *.o *.elf *.bin *.rom

.PHONY: all clean
