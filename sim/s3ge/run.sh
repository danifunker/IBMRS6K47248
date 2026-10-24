#!/bin/bash
# build and run the S3 engine's bench (tb_s3ge.cpp) with Verilator, in sim/s3ge/build
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME \
	--top-module IBMRS6K7248_s3ge -Mdir build \
	../../rtl/machine/IBMRS6K7248_s3ge.sv tb_s3ge.cpp -o s3ge_tb > build.log 2>&1 || { tail -30 build.log; exit 1; }
./build/s3ge_tb
