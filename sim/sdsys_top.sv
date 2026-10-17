//============================================================================
//
//  IBMRS6K7248 - the bench's top with the board's SDRAM controller in the loop
//  (sim/Makefile machine_sd): IBMRS6K7248_system's memory side into
//  IBMRS6K7248_sdram, whose pins go to the C++ chip model (sim/sdram_chip.h,
//  from MacPPC7300's SDRAM bench); the ROM comes in through the upload port.
//
//============================================================================

module IBMRS6K7248_sdsys
#(

	parameter int unsigned CPU_HZ = 100_000_000,
	parameter int unsigned TB_HZ  = 16_666_667,
	parameter int unsigned PERF   = 0,            // 1: the CPU's performance counters
	parameter int unsigned LE_MODE = 1,           // 1: little-endian mode, the CPU's munging and the MPC105's swap
	parameter int unsigned UART_FAST = 0,         // 1 (the bench only): the serial ports at CLK_HZ / 16
	parameter int unsigned STO_UNIT = CPU_HZ / 16000   // the 53C810's selection timeout unit (the bench: shorter)

)
(

	input  logic         clk,  // the CPU's clock
	input  logic         reset,  // in the CPU's clock
	input  logic [31:0]  reset_pc,
	input  logic [8:0]   simm_cfg,  // the SIMM pairs (IBMRS6K7248_machine)
	input  logic [4:0]   rom_at,
	input  logic         rom_512k,
	input  logic [7:0]   planar_id,

	// memory, in the memory's clock, by SDRAM offset
	input  logic         clk_b,
	input  logic         reset_b,

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

	// the S3's VRAM in DDR3 (the framework's DDRAM port) and its picture, in the memory's clock
	input  logic         ddr_busy,
	output logic [7:0]   ddr_burstcnt,
	output logic [28:0]  ddr_addr,
	input  logic [63:0]  ddr_dout,
	input  logic         ddr_dout_ready,
	output logic         ddr_rd,
	output logic [63:0]  ddr_din,
	output logic [7:0]   ddr_be,
	output logic         ddr_we,
	output logic         vid_ce,
	output logic [7:0]   vid_r,
	output logic [7:0]   vid_g,
	output logic [7:0]   vid_b,
	output logic         vid_hs,
	output logic         vid_vs,
	output logic         vid_hblank,
	output logic         vid_vblank,

	// the SCSI devices' images (hps_io block devices 0-2: disk ID 0, disk ID 1,
	// CD-ROM ID 3), 8-bit; img_* quasi-static, sd_* in the memory's clock
	input  logic [2:0]   img_present,
	input  logic [31:0]  img_blocks [3],
	output logic [31:0]  sd_lba [3],
	output logic [5:0]   sd_blk_cnt [3],
	output logic [2:0]   sd_rd,
	output logic [2:0]   sd_wr,
	input  logic [2:0]   sd_ack,
	input  logic [13:0]  sd_buff_addr,
	input  logic [7:0]   sd_buff_dout,
	output logic [7:0]   sd_buff_din [3],
	input  logic         sd_buff_wr,
	input  logic         cd_change,
	output logic         scsi_activity,

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
	output logic [31:2]  trace_daddr,
	// the SDRAM controller: its power-up and the ROM upload (in clk_b)
	input  logic         init,
	output logic         ready,
	input  logic         up_wr,
	input  logic [26:0]  up_addr,
	input  logic [7:0]   up_data,
	output logic         up_busy,
	// the chip
	output logic [12:0]  SDRAM_A,
	output logic [1:0]   SDRAM_BA,
	output logic         SDRAM_nCS,
	output logic         SDRAM_nRAS,
	output logic         SDRAM_nCAS,
	output logic         SDRAM_nWE,
	output logic         SDRAM_DQML,
	output logic         SDRAM_DQMH,
	output logic         SDRAM_CKE,
	output logic [15:0]  dq_out,
	output logic         dq_oe,
	input  logic [15:0]  dq_in
);

logic         b_req, b_we, b_line, b_ack;
logic [31:2]  b_addr;
logic [3:0]   b_be;
logic [255:0] b_wdata, b_rdata;

IBMRS6K7248_system #(.CPU_HZ(CPU_HZ), .TB_HZ(TB_HZ), .PERF(PERF), .LE_MODE(LE_MODE), .UART_FAST(UART_FAST), .STO_UNIT(STO_UNIT)) system (
	.clk, .reset, .reset_pc, .simm_cfg, .rom_at, .rom_512k, .planar_id, .clk_b, .reset_b, .ps2_key, .ps2_mouse, .rtc_set, .rtc_time, .speaker, .kbc_reset, .com1_txd, .com1_rxd, .com1_cts_n, .com1_rts_n, .ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready, .ddr_rd, .ddr_din, .ddr_be, .ddr_we, .vid_ce, .vid_r, .vid_g, .vid_b, .vid_hs, .vid_vs, .vid_hblank, .vid_vblank, .img_present, .img_blocks, .sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack, .sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr, .cd_change, .scsi_activity, .io_ev, .io_we, .io_stub, .io_addr, .io_be, .io_wdata, .io_rdata, .trace_valid, .trace_last, .trace_pc, .trace_insn, .trace_msr, .trace_dreq, .trace_dwe, .trace_daddr,
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata
);

IBMRS6K7248_sdram #(.CLK_MHZ(100)) sdram (
	.clk(clk_b), .init, .ready,
	.req(b_req), .we(b_we), .line(b_line), .addr(b_addr[26:2]), .be(b_be), .wdata(b_wdata),
	.ack(b_ack), .rdata(b_rdata),
	.up_wr, .up_addr, .up_data, .up_busy,
	.SDRAM_A, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_nWE,
	.SDRAM_DQML, .SDRAM_DQMH, .SDRAM_CKE, .dq_out, .dq_oe, .dq_in
);

endmodule
