# Test ROMs for the machine bench (512 KB images mapped at FFF00000).
#   make            build le_test.rom
AS      := powerpc-linux-gnu-as
LD      := powerpc-linux-gnu-ld
OBJCOPY := powerpc-linux-gnu-objcopy
NM      := powerpc-linux-gnu-nm

all: le_test.rom

le_be.elf: le_be.S
	$(AS) -mregnames -o le_be.o $<
	$(LD) -Ttext=0xFFF00000 -o $@ le_be.o

# the little-endian half knows where the big-endian checks are
le_le.elf: le_le.S le_be.elf
	$(AS) -mregnames -mlittle --defsym CHECKS=0x$$($(NM) le_be.elf | awk '$$3 == "checks" { print $$1 }') -o le_le.o $<
	$(LD) -EL -e _le -Ttext=0xFFF02000 -o $@ le_le.o

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

# the big-endian half, the little-endian half at 0x2000, padded with FF to 512 KB;
# at the alignment vector (0x600) a little-endian "ba align_handler"
le_test.rom: le_be.bin le_le.bin le_le.elf
	python3 -I -c "import sys, struct; be=open('le_be.bin','rb').read(); le=open('le_le.bin','rb').read(); assert len(be) <= 0x2000, len(be); h=int(sys.argv[1], 16); img=bytearray(b'\xff'*0x80000); img[:len(be)]=be; img[0x2000:0x2000+len(le)]=le; img[0x600:0x604]=struct.pack('<I', 0x48000002 | (h & 0x03FFFFFC)); open('$@','wb').write(img)" $$($(NM) le_le.elf | awk '$$3 == "align_handler" { print $$1 }')

clean:
	rm -f *.o *.elf *.bin *.rom

.PHONY: all clean
