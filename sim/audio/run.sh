#!/bin/bash
# build and run the audio path's bench (tb_audio.cpp: the DMA controller, the CS4232's codec, Sound Blaster,
# MPU-401, joystick port and FM chip) with Verilator
set -e
cd "$(dirname "$0")"
J=$(grep '^set_global' ../../rtl/jtopl/jtopl.qip | grep -o 'jtopl[a-z0-9_]*\.v' | sed 's|^|../../rtl/jtopl/|')
M=../../rtl/machine
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-PINMISSING \
	--top-module audtb -Mdir build $J ../../rtl/IBMRS6K7248_opl.sv audtb.sv $M/IBMRS6K7248_dma.sv $M/IBMRS6K7248_cs4232.sv \
	$M/IBMRS6K7248_sb.sv $M/IBMRS6K7248_mpu401.sv $M/IBMRS6K7248_joy.sv \
	tb_audio.cpp -o audio_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
./build/audio_tb
