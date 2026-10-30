#!/bin/bash
# build and run the CD player's bench (tb_cdaudio.cpp: IBMRS6K7248_scsitgt with IBMRS6K7248_CDAUDIO,
# its bus driven as the 53C810 does, the CD slot answered as the Main's support/ibmrs6k does) with Verilator
set -e
cd "$(dirname "$0")"
M=../../rtl/machine
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-PINMISSING \
	-DIBMRS6K7248_CDAUDIO -GCLK_HZ=2000000 --top-module IBMRS6K7248_scsitgt -Mdir build \
	$M/IBMRS6K7248_scsitgt.sv tb_cdaudio.cpp -o cdaudio_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
./build/cdaudio_tb
