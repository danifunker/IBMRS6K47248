#!/bin/bash
# build and run the ATAPI CD-ROM's bench (tb_atapi.cpp: IBMRS6K7248_atapi driving IBMRS6K7248_scsitgt's CD, the
# host's register accesses as the CPU makes them, the CD slot answered as hps_io does) with Verilator
set -e
cd "$(dirname "$0")"
M=../../rtl/machine
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-PINMISSING \
	--top-module atapitb -Mdir build atapitb.sv $M/IBMRS6K7248_atapi.sv $M/IBMRS6K7248_scsitgt.sv tb_atapi.cpp \
	-o atapi_tb > build.log 2>&1 || { grep -i -B2 -A3 error build.log | head -60; exit 1; }
./build/atapi_tb
