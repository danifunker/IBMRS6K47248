//============================================================================
//
//  IBMRS6K7248 - the machine around the CPU
//  The CPU, the machine and the clock crossing to memory, as one block
//
//    DSPPC604 --(memory port)--> IBMRS6K7248_machine --(RAM, ROM)--> DSPPC604_memcdc --> b_*
//
//  Everything left of the crossing runs in the CPU's clock; b_* is the same
//  port protocol in the memory's clock, addressed by SDRAM offset, for the
//  SDRAM controller (or the test bench's memory). The MiSTer top and the
//  test bench both instantiate this block, so the bench runs the machine
//  exactly as the FPGA does. (Both clocks are 100 MHz on the board; the
//  crossing stays, as in MacPPC7300, so the two may differ.)
//
//  The CPU's retirement trace is brought out for the test bench and the
//  heartbeat LED; the machine's device accesses (io_*) for the bench.
//
//============================================================================

module IBMRS6K7248_system
#(
	parameter int unsigned CPU_HZ = 100_000_000,
	parameter int unsigned TB_HZ  = 16_666_667,
	parameter int unsigned PERF   = 0             // 1: the CPU's performance counters
)
(
	input  logic         clk,             // the CPU's clock
	input  logic         reset,           // in the CPU's clock
	input  logic [31:0]  reset_pc,
	input  logic [8:0]   simm_cfg,        // the SIMM pairs (IBMRS6K7248_machine)
	input  logic [4:0]   rom_at,
	input  logic         rom_512k,
	input  logic [7:0]   planar_id,

	// memory, in the memory's clock, by SDRAM offset
	input  logic         clk_b,
	input  logic         reset_b,
	output logic         b_req,
	output logic         b_we,
	output logic         b_line,
	output logic [31:2]  b_addr,
	output logic [3:0]   b_be,
	output logic [255:0] b_wdata,
	input  logic         b_ack,
	input  logic [255:0] b_rdata,

	// the keyboard and mouse (hps_io's, in any clock: synchronised inside),
	// the RTC's starting time (rtc_set a pulse in this clock), the speaker,
	// the 8042's reset line (a pulse)
	input  logic [10:0]  ps2_key,
	input  logic [24:0]  ps2_mouse,
	input  logic         rtc_set,
	input  logic [55:0]  rtc_time,
	output logic         speaker,
	output logic         kbc_reset,

	// COM1, 1 when idle; asynchronous in
	output logic         com1_txd,
	input  logic         com1_rxd,
	input  logic         com1_cts_n,
	output logic         com1_rts_n,

	// the machine's device accesses (see IBMRS6K7248_machine)
	output logic         io_ev,
	output logic         io_we,
	output logic         io_stub,
	output logic [31:0]  io_addr,
	output logic [3:0]   io_be,
	output logic [31:0]  io_wdata,
	output logic [31:0]  io_rdata,

	// the CPU's retirement trace (see DSPPC604)
	output logic         trace_valid,
	output logic         trace_last,
	output logic [31:0]  trace_pc,
	output logic [31:0]  trace_insn,
	output logic [31:0]  trace_msr,
	output logic         trace_dreq,
	output logic         trace_dwe,
	output logic [31:2]  trace_daddr
);

logic         c_req, c_we, c_line, c_ack;
logic [31:2]  c_addr;
logic [3:0]   c_be;
logic [255:0] c_wdata, c_rdata;
logic         m_req, m_we, m_line, m_ack;
logic [31:2]  m_addr;
logic [3:0]   m_be;
logic [255:0] m_wdata, m_rdata;
logic         ext_irq, tb_tick;

// (from a register: it fans out to every register of the CPU)
logic         cpu_reset = 1'b1;
always_ff @(posedge clk) cpu_reset <= reset;

DSPPC604 #(.PERF(PERF)) cpu (
	.clk, .reset(cpu_reset), .reset_pc,
	.ext_irq, .tb_tick,
	.mem_req(c_req), .mem_we(c_we), .mem_line(c_line), .mem_addr(c_addr), .mem_be(c_be),
	.mem_wdata(c_wdata), .mem_ack(c_ack), .mem_rdata(c_rdata),
	.snoop_req(1'b0), .snoop_we(1'b0), .snoop_addr(27'd0), .snoop_ack(),
	.trace_valid, .trace_last, .trace_pc, .trace_insn, .trace_fold(), .trace_fold_insn(),
	.trace_reg2_we(), .trace_reg2_idx(), .trace_reg2_val(), .trace_reg_we(), .trace_reg_idx(), .trace_reg_val(),
	.trace_cr(), .trace_xer(), .trace_lr(), .trace_ctr(), .trace_fpscr(), .trace_msr,
	.trace_dreq, .trace_dwe, .trace_dkind(), .trace_daddr, .trace_dbe(), .trace_dwdata(),
	.perf_cnt(), .dbg_ev(), .dbg_rec()
);

IBMRS6K7248_machine #(.CPU_HZ(CPU_HZ), .TB_HZ(TB_HZ)) machine (
	.clk, .reset, .simm_cfg, .rom_at, .rom_512k, .planar_id,
	.c_req, .c_we, .c_line, .c_addr, .c_be, .c_wdata, .c_ack, .c_rdata,
	.m_req, .m_we, .m_line, .m_addr, .m_be, .m_wdata, .m_ack, .m_rdata,
	.ext_irq, .tb_tick, .kbc_reset, .speaker,
	.ps2_key, .ps2_mouse, .rtc_set, .rtc_time,
	.com1_txd, .com1_rxd, .com1_cts_n, .com1_rts_n,
	.io_ev, .io_we, .io_stub, .io_addr, .io_be, .io_wdata, .io_rdata
);

DSPPC604_memcdc cdc (
	.clk_a(clk), .reset_a(reset),
	.a_req(m_req), .a_we(m_we), .a_line(m_line), .a_addr(m_addr), .a_be(m_be), .a_wdata(m_wdata),
	.a_ack(m_ack), .a_rdata(m_rdata),
	.clk_b, .reset_b,
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata
);

endmodule
