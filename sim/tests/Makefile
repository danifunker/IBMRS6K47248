# Test ROMs for the machine bench (512 KB images mapped at FFF00000).
#   make            build le_test.rom (data cache off) and le_test_dc.rom (on)
AS      := powerpc-linux-gnu-as
LD      := powerpc-linux-gnu-ld
OBJCOPY := powerpc-linux-gnu-objcopy
NM      := powerpc-linux-gnu-nm

all: le_test.rom le_test_dc.rom

# $(1): the variant's suffix; $(2): its assembler flags
define le_variant
le_be$(1).elf: le_be.S
	$(AS) -mregnames $(2) -o le_be$(1).o $$<
	$(LD) -Ttext=0xFFF00000 -o $$@ le_be$(1).o

# the little-endian half knows where the big-endian checks are
le_le$(1).elf: le_le.S le_be$(1).elf
	$(AS) -mregnames -mlittle $(2) --defsym CHECKS=0x$$$$($(NM) le_be$(1).elf | awk '$$$$3 == "checks" { print $$$$1 }') -o le_le$(1).o $$<
	$(LD) -EL -e _le -Ttext=0xFFF02000 -o $$@ le_le$(1).o

# the big-endian half, the little-endian half at 0x2000, padded with FF to 512 KB;
# at the alignment vector (0x600) a little-endian "ba align_handler"
le_test$(1).rom: le_be$(1).elf le_le$(1).elf
	$(OBJCOPY) -O binary le_be$(1).elf le_be$(1).bin
	$(OBJCOPY) -O binary le_le$(1).elf le_le$(1).bin
	python3 -I -c "import sys, struct; be=open('le_be$(1).bin','rb').read(); le=open('le_le$(1).bin','rb').read(); assert len(be) <= 0x2000, len(be); h=int(sys.argv[1], 16); img=bytearray(b'\xff'*0x80000); img[:len(be)]=be; img[0x2000:0x2000+len(le)]=le; img[0x600:0x604]=struct.pack('<I', 0x48000002 | (h & 0x03FFFFFC)); open('$$@','wb').write(img)" $$$$($(NM) le_le$(1).elf | awk '$$$$3 == "align_handler" { print $$$$1 }')
endef

$(eval $(call le_variant,,))
$(eval $(call le_variant,_dc,--defsym DCACHE=1))

clean:
	rm -f *.o *.elf *.bin *.rom

.PHONY: all clean
