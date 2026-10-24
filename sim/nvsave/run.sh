#!/bin/bash
# build and run the NVRAM keeper's bench (tb_nvsave.cpp) with Verilator, in sim/nvsave/build
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-MULTIDRIVEN \
	--top-module nvtb -Mdir build nvtb.sv ../../rtl/IBMRS6K7248_nvsave.sv ../../rtl/machine/IBMRS6K7248_rtc.sv \
	tb_nvsave.cpp -o nvsave_tb > build.log 2>&1 || { grep -i error build.log | head -30; exit 1; }
./build/nvsave_tb
