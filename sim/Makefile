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
JOBS   ?= 2
VFLAGS := --cc --exe --build -j $(JOBS) $(WARN)

all: $(BUILD)/machine_tb

$(BUILD)/machine_tb: $(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp $(CPU)/DSPPC604.qip $(MACH)/IBMRS6K7248_machine.qip $(HERE)Makefile
	@mkdir -p $(BUILD)
	@$(VERILATOR) $(VFLAGS) --top-module IBMRS6K7248_system -Mdir $(BUILD) -o machine_tb \
		-CFLAGS "-O2 -std=c++17" \
		$(CPU_SRCS) $(MACH_SRCS) $(HERE)tb_main.cpp \
		> $(BUILD)/build.log 2>&1 || (cat $(BUILD)/build.log; false)
	@grep -E '^%Warning' $(BUILD)/build.log || true

lint:
	$(VERILATOR) --lint-only $(WARN) --top-module IBMRS6K7248_system $(CPU_SRCS) $(MACH_SRCS)

clean:
	rm -rf $(BUILD)

.PHONY: all lint clean
