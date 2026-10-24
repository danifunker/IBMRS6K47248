#!/bin/bash
# build and run the S3 picture side's bench (tb_s3video.cpp) with Verilator, in sim/s3video/build
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
	--top-module IBMRS6K7248_s3video -Mdir build \
	../../rtl/machine/IBMRS6K7248_s3video.sv tb_s3video.cpp -o s3video_tb > build.log 2>&1 || { tail -30 build.log; exit 1; }
./build/s3video_tb
