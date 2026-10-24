#!/bin/bash
# build and run the PCnet's benches with Verilator: tb_pcnet.cpp (the chip alone), and with "net"
# tb_net.cpp (the chip, IBMRS6K7248_enetbox and IBMRS6K7248_ddrarb on a DDR3 model, the Main's side here)
set -e
cd "$(dirname "$0")"
W="-Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-BLKSEQ"
M=../../rtl/machine
if [ "$1" = net ]; then
	verilator --cc --exe --build -O2 $W --top-module nettb -Mdir build_net nettb.sv $M/IBMRS6K7248_pcnet.sv \
		$M/IBMRS6K7248_enetbox.sv $M/IBMRS6K7248_ddrarb.sv tb_net.cpp -o net_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
	./build_net/net_tb
else
	verilator --cc --exe --build -O2 $W --top-module IBMRS6K7248_pcnet -Mdir build $M/IBMRS6K7248_pcnet.sv tb_pcnet.cpp \
		-o pcnet_tb > build.log 2>&1 || { grep -i -A3 error build.log | head -40; exit 1; }
	./build/pcnet_tb
fi
