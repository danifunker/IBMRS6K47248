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

WARN   := -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY -Wno-SYMRSVDWORD
# The model is split into many small files (one 50 MB file took 10 minutes
# and 2.5 GB to compile), the start-up code (the __Slow files) unoptimised,
# and ccache keeps what an RTL change leaves the same. Two jobs: this 14 GB
# machine has been run out of memory twice by more. `make` runs the build in a
# systemd scope capped at MEM (no swap), so a build that grows too far is
# killed alone; `make machine_tb` builds without the cap.
JOBS   ?= 2
MEM    ?= 5G
# the optimisation of the model's C++ (OPT_FAST): -O1 builds faster than -O2
OPT    ?= -O1
# (Verilator is run to generate the C++ and exit: with --build it stays
# resident, 2.5 GB, through the whole compile.)
VFLAGS := --cc --exe $(WARN) --output-split 20000 --output-split-cfuncs 2000

all:
	systemd-run --user --scope -q -p MemoryMax=$(MEM) -p MemorySwapMax=0 $(MAKE) --no-print-directory machine_tb

machine_tb: $(BUILD)/machine_tb

$(BUILD)/VIBMRS6K7248_system.mk: $(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp $(CPU)/DSPPC604.qip $(MACH)/IBMRS6K7248_machine.qip $(HERE)Makefile
	@mkdir -p $(BUILD)
	@$(VERILATOR) $(VFLAGS) --top-module IBMRS6K7248_system -Mdir $(BUILD) -o machine_tb \
		-CFLAGS "-std=c++17" \
		$(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp \
		> $(BUILD)/build.log 2>&1 || (cat $(BUILD)/build.log; false)
	@grep -E '^%Warning' $(BUILD)/build.log || true

$(BUILD)/machine_tb: $(BUILD)/VIBMRS6K7248_system.mk
	@$(MAKE) -s -C $(BUILD) -f VIBMRS6K7248_system.mk -j $(JOBS) OPT_FAST=$(OPT) OPT_SLOW=-O0 OBJCACHE=$(shell command -v ccache) \
		> $(BUILD)/compile.log 2>&1 || (tail -40 $(BUILD)/compile.log; false)

lint:
	$(VERILATOR) --lint-only $(WARN) --top-module IBMRS6K7248_system $(CPU_SRCS) $(MACH_SRCS)

clean:
	rm -rf $(BUILD)

.PHONY: all machine_tb lint clean
