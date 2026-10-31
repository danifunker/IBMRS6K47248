#!/bin/bash
# build and run the IDE hard disk's bench (tb_idehd.cpp: IBMRS6K7248_idehd beside the ATAPI CD-ROM on IBMRS6K7248_scsitgt, the
# host's register accesses as the CPU makes them, the disk and CD slots answered as hps_io does, writes included) with Verilator
set -e
cd "$(dirname "$0")"
M=../../rtl/machine
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-PINMISSING \
	--top-module idehdtb -Mdir build idehdtb.sv $M/IBMRS6K7248_idehd.sv $M/IBMRS6K7248_atapi.sv $M/IBMRS6K7248_scsitgt.sv tb_idehd.cpp \
	-o idehd_tb > build.log 2>&1 || { grep -i -B2 -A3 error build.log | head -60; exit 1; }
./build/idehd_tb
