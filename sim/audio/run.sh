#!/bin/bash
# build and run the audio path's bench (tb_audio.cpp: the DMA controller and the CS4232) with Verilator
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ \
	--top-module audtb -Mdir build audtb.sv ../../rtl/machine/IBMRS6K7248_dma.sv ../../rtl/machine/IBMRS6K7248_cs4232.sv \
	tb_audio.cpp -o audio_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
./build/audio_tb
