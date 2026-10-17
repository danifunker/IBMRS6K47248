# Verilator bench of the whole machine (IBMRS6K7248_system: the CPU, the
# machine, the clock crossing) running a ROM image from the reset vector.
#
#   make            build $(BUILD)/machine_tb
#   make lint       Verilator lint of the machine
#   make clean
#
#   ./build/machine_tb --rom ../firmware/images/<rom>.bin [--ram 32] [--cycles N] ...
#   (machine_tb --help lists the options)

VERILATOR ?= verilator
BUILD     ?= build

HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CPU  := $(HERE)../rtl/DSPPC604
MACH := $(HERE)../rtl/machine

CPU_SRCS  := $(addprefix $(CPU)/,$(shell grep -o '[A-Za-z0-9_]*\.sv' $(CPU)/DSPPC604.qip))
# the SDRAM controller is the board's; the bench answers the crossing's far side itself
MACH_SRCS := $(addprefix $(MACH)/,$(filter-out IBMRS6K7248_sdram.sv,$(shell grep -o '[A-Za-z0-9_]*\.sv' $(MACH)/IBMRS6K7248_machine.qip)))

# (PROCASSINIT and MULTIDRIVEN: Verilator 5.04x's lint of registers given an initial value, the
#  UART's and the RTC's, which the FPGA honours; 5.028 did not flag them)
WARN   := -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY -Wno-SYMRSVDWORD -Wno-PROCASSINIT -Wno-MULTIDRIVEN
# The model is split into many small files (one 50 MB file took 10 minutes
# and 2.5 GB to compile), the start-up code (the __Slow files) unoptimised,
# and ccache keeps what an RTL change leaves the same. Two jobs: this 14 GB
# machine has been run out of memory twice by more. `make` runs the build in a
# systemd scope capped at MEM (no swap), so a build that grows too far is
# killed alone (5G was not enough once the S3 came: 2026-10-17); `make machine_tb` builds
# without the cap.
JOBS   ?= 2
# g++ collects its garbage more often (default: when the heap grows by 30-100 % over
# a base of up to 128 MB): a lower peak on the model's two 45-50 MB files, which
# needed about 2.5 GB each, for some compile time (2026-10-17, measured in
# scratch/work/build_*.txt)
GCC_MEM ?= --param ggc-min-expand=10 --param ggc-min-heapsize=32768
MEM    ?= 7G
# the optimisation of the model's C++ (OPT_FAST): -O2 builds in ~14 minutes and runs
# ~390,000 clocks a second; -O1 builds in ~8 and runs ~150,000 (make OPT=-O1 for
# a short test)
OPT    ?= -O2
# (Verilator is run to generate the C++ and exit: with --build it stays
# resident, 2.5 GB, through the whole compile.)
# (the bench's serial ports run at the clock / 16, UART_FAST: the firmware's 9600 baud console
# would cost 100,000 clocks a character)
VFLAGS := --cc --exe --savable $(WARN) --output-split 20000 --output-split-cfuncs 2000
# make TRACE=1: a build that can write waveforms (--fst), in its own directory
ifeq ($(TRACE),1)
BUILD  := build_trace
VFLAGS += --trace-fst --trace-structs
endif

all:
	systemd-run --user --scope -q -p MemoryMax=$(MEM) -p MemorySwapMax=0 $(MAKE) --no-print-directory machine_tb

machine_tb: $(BUILD)/machine_tb

$(BUILD)/VIBMRS6K7248_system.mk: $(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp $(CPU)/DSPPC604.qip $(MACH)/IBMRS6K7248_machine.qip $(HERE)Makefile
	@mkdir -p $(BUILD)
	@$(VERILATOR) $(VFLAGS) --top-module IBMRS6K7248_system -GUART_FAST=1 -GSTO_UNIT=2 -Mdir $(BUILD) -o machine_tb \
		-CFLAGS "-std=c++17 $(GCC_MEM)" \
		$(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp \
		> $(BUILD)/build.log 2>&1 || (cat $(BUILD)/build.log; false)
	@grep -E '^%Warning' $(BUILD)/build.log || true

# the C++ optimisation the objects were built with: a change of OPT rebuilds them
$(BUILD)/opt.stamp: FORCE
	@mkdir -p $(BUILD)
	@if [ "$$(cat $@ 2>/dev/null)" != "$(OPT)" ]; then echo "$(OPT)" > $@; rm -f $(BUILD)/*.o $(BUILD)/*.gch; fi

# (always handed to the model's own make, which knows every source's dependencies: Verilator
# leaves the .mk alone when only tb_main.cpp changed)
$(BUILD)/machine_tb: $(BUILD)/VIBMRS6K7248_system.mk $(BUILD)/opt.stamp FORCE
	@$(MAKE) -s -C $(BUILD) -f VIBMRS6K7248_system.mk -j $(JOBS) OPT_FAST=$(OPT) OPT_SLOW=-O0 OBJCACHE=$(shell command -v ccache) \
		> $(BUILD)/compile.log 2>&1 || (tail -40 $(BUILD)/compile.log; false)

# make machine_sd: the bench with the board's SDRAM controller in the loop (sim/sdsys_top.sv,
# the chip modelled in sim/sdram_chip.h, the ROM through the upload port; no snapshots). Its
# own directory and prefix; the same options otherwise.
SD_BUILD := $(BUILD)_sd
SD_SRCS  := $(CPU_SRCS) $(MACH_SRCS) $(MACH)/IBMRS6K7248_sdram.sv $(HERE)sdsys_top.sv

machine_sd: $(SD_BUILD)/machine_sd

$(SD_BUILD)/VIBMRS6K7248_sdsys.mk: $(SD_SRCS) $(HERE)tb_main.cpp $(HERE)sdram_chip.h $(HERE)Makefile
	@mkdir -p $(SD_BUILD)
	@$(VERILATOR) $(VFLAGS) --top-module IBMRS6K7248_sdsys -GUART_FAST=1 -GSTO_UNIT=2 -Mdir $(SD_BUILD) -o machine_sd 		-CFLAGS "-std=c++17 -DSDRAM_CHIP -I$(HERE) $(GCC_MEM)" 		$(SD_SRCS) $(HERE)tb_main.cpp 		> $(SD_BUILD)/build.log 2>&1 || (cat $(SD_BUILD)/build.log; false)
	@grep -E '^%Warning' $(SD_BUILD)/build.log || true

$(SD_BUILD)/machine_sd: $(SD_BUILD)/VIBMRS6K7248_sdsys.mk FORCE
	@$(MAKE) -s -C $(SD_BUILD) -f VIBMRS6K7248_sdsys.mk -j $(JOBS) OPT_FAST=$(OPT) OPT_SLOW=-O0 OBJCACHE=$(shell command -v ccache) 		> $(SD_BUILD)/compile.log 2>&1 || (tail -40 $(SD_BUILD)/compile.log; false)

# fst2vcd, to read a --fst waveform without a viewer
FSTAPI := $(dir $(shell command -v verilator))../share/verilator/include/gtkwave
tools/fst2vcd: tools/fst2vcd.c
	gcc -O2 -DFST_CONFIG_INCLUDE='"fst_config.h"' -I$(FSTAPI) -o $@ $< $(FSTAPI)/fstapi.c $(FSTAPI)/fastlz.c $(FSTAPI)/lz4.c -lz -lpthread

lint:
	$(VERILATOR) --lint-only $(WARN) --top-module IBMRS6K7248_system $(CPU_SRCS) $(MACH_SRCS)

clean:
	rm -rf $(BUILD)

.PHONY: all machine_tb lint clean FORCE
