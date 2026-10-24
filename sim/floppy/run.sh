#!/bin/bash
# build and run the floppy's bench (tb_floppy.cpp: the controller, the image bridge, the DMA) with Verilator
set -e
cd "$(dirname "$0")"
M=../../rtl/machine
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-PINMISSING \
	--top-module fdtb -Mdir build fdtb.sv $M/IBMRS6K7248_fdc.sv ../../rtl/IBMRS6K7248_fdimg.sv $M/IBMRS6K7248_dma.sv \
	tb_floppy.cpp -o floppy_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
./build/floppy_tb
