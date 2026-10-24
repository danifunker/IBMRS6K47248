//============================================================================
//
//  IBMRS6K7248 - the machine around the CPU
//  The CPU, the machine and the clock crossing to memory, as one block
//
//    DSPPC604 --(memory port)--> IBMRS6K7248_machine --(RAM, ROM)--> DSPPC604_memcdc --> b_*
//                  ^ snoop                 | the 53C810's SCSI bus
//                  +-- (the 810's DMA) ----+--> IBMRS6K7248_scsitgt --(clk_b)--> sd_* (hps_io)
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
	parameter int unsigned PERF   = 0,            // 1: the CPU's performance counters
	parameter int unsigned LE_MODE = 1,           // 1: little-endian mode, the CPU's munging and the MPC105's swap
	parameter int unsigned UART_FAST = 0,         // 1 (the bench only): the serial ports at CLK_HZ / 16
	parameter int unsigned RTC_FAST  = 0,         // 1 (the bench only): the RTC's seconds 64 x faster
	parameter int unsigned STO_UNIT = CPU_HZ / 16000   // the 53C810's selection timeout unit (the bench: shorter)
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
	// the RTC's maintenance port (IBMRS6K7248_nvsave), in clk
	input  logic [12:0]  nv_m_addr,
	input  logic         nv_m_we,
	input  logic [7:0]   nv_m_wdata,
	output logic [7:0]   nv_m_q,
	output logic         nv_m_ok,
	output logic [7:0]   nv_wr_seq,
	output logic         speaker,
	output logic [15:0]  aud_l,                   // the CS4232's codec and Sound Blaster, signed, in clk
	output logic [15:0]  aud_r,
	// its FM chip's ports (the top's), the joystick port's sticks, the MPU-401's MIDI (see IBMRS6K7248_machine)
	output logic         fm_cs,
	output logic         fm_we,
	output logic [1:0]   fm_a,
	output logic [7:0]   fm_wdata,
	input  logic [7:0]   fm_rdata,
	output logic [7:0]   fm_vol,
	input  logic [5:0]   joy1,
	input  logic [5:0]   joy2,
	input  logic [15:0]  ana1,
	input  logic [15:0]  ana2,
	output logic         midi_tx,
	input  logic         midi_rx,
	// the floppy image (IBMRS6K7248_fdimg): present, read-only, its sectors, mounted; a sector asked and answered
	input  logic         fd_in,
	input  logic         fd_ro,
	input  logic [12:0]  fd_blocks,
	input  logic         fd_mounted,
	output logic         fd_req,
	output logic         fd_we,
	output logic [12:0]  fd_lba,
	input  logic         fd_ack,
	output logic [8:0]   fd_buf_a,
	input  logic [7:0]   fd_buf_q,
	output logic         fd_buf_we,
	output logic [7:0]   fd_buf_d,
	output logic         kbc_reset,

	// COM1, 1 when idle; asynchronous in
	output logic         com1_txd,
	input  logic         com1_rxd,
	input  logic         com1_cts_n,
	output logic         com1_rts_n,

	// the S3's VRAM in DDR3 (the framework's DDRAM port) and its picture, in the memory's clock
	// (shared: the S3's picture side, and the Ethernet mailbox at ARM physical 1FF0_0000;
	// net_on, the OSD's network not None, asynchronous)
	input  logic         net_on,
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
	output logic [31:0]  trace_lr,
	output logic [31:0]  trace_ctr,
	output logic         trace_reg_we,
	output logic [6:0]   trace_reg_idx,
	output logic [63:0]  trace_reg_val,
	output logic         trace_dreq,
	output logic         trace_dwe,
	output logic [31:2]  trace_daddr
);

// the PCnet's wire side (IBMRS6K7248_machine to IBMRS6K7248_enetbox), and the picture side's DDRAM port (va_*)
logic         en_tx_pend, en_tx_done, en_rx_free, en_rx_we, en_rx_post, en_padr_ok;
logic [10:0]  en_tx_len, en_tx_a, en_rx_a, en_rx_len;
logic [7:0]   en_tx_q, en_rx_d;
logic [5:0]   en_rx_hash;
logic [47:0]  en_aprom_mac, en_padr;
logic         va_busy, va_dout_ready, va_rd, va_we;
logic [7:0]   va_burstcnt, va_be;
logic [28:0]  va_addr;
logic [63:0]  va_dout, va_din;
logic         c_req, c_we, c_line, c_ack;
logic [31:2]  c_addr;
logic [3:0]   c_be;
logic [255:0] c_wdata, c_rdata;
logic         m_req, m_we, m_line, m_ack;
logic [31:2]  m_addr;
logic [3:0]   m_be;
logic [255:0] m_wdata, m_rdata;
logic         ext_irq, tb_tick;
logic         snoop_req, snoop_we, snoop_ack;
logic [31:5]  snoop_addr;
// the 53C810's SCSI bus
logic         sb_sel, sb_sel_atn, sb_sel_done, sb_sel_fail, sb_bsy, sb_req, sb_ack, sb_ackhold, sb_atn, sb_rst;
logic [2:0]   sb_sel_id, sb_phase;
logic [7:0]   sb_tdata, sb_idata;

// (from a register: it fans out to every register of the CPU)
logic         cpu_reset = 1'b1;
always_ff @(posedge clk) cpu_reset <= reset;

DSPPC604 #(.PERF(PERF), .LE_MODE(LE_MODE)) cpu (
	.clk, .reset(cpu_reset), .reset_pc,
	.ext_irq, .tb_tick,
	.mem_req(c_req), .mem_we(c_we), .mem_line(c_line), .mem_addr(c_addr), .mem_be(c_be),
	.mem_wdata(c_wdata), .mem_ack(c_ack), .mem_rdata(c_rdata),
	.snoop_req, .snoop_we, .snoop_addr, .snoop_ack,
	.trace_valid, .trace_last, .trace_pc, .trace_insn, .trace_fold(), .trace_fold_insn(),
	.trace_reg2_we(), .trace_reg2_idx(), .trace_reg2_val(), .trace_reg_we, .trace_reg_idx, .trace_reg_val,
	.trace_cr(), .trace_xer(), .trace_lr, .trace_ctr, .trace_fpscr(), .trace_msr,
	.trace_dreq, .trace_dwe, .trace_dkind(), .trace_daddr, .trace_dbe(), .trace_dwdata(),
	.perf_cnt(), .dbg_ev(), .dbg_rec()
);

// the S3's VRAM port and its picture side's values (below)
logic         v_req, v_we, v_ack;
logic [20:2]  v_addr;
logic [3:0]   v_be;
logic [31:0]  v_wdata, v_rdata;
logic [10:0]  h_total, h_disp, h_ss, h_sl, v_total, v_disp, v_ss, v_cur_x, v_cur_y, v_cur_base;
logic [4:0]   v_sl;
logic [20:0]  v_start;
logic [11:0]  v_pitch;
logic         v_screen_on, v_cur_on, vretrace_v, disp_en_v, v_cur_x11;
logic [7:0]   v_cur_fg, v_cur_bg;
logic [7:0]   v_pix_mask, pal_vaddr;
logic [6:0]   v_pll_m, v_pll_n;
logic [17:0]  pal_vq;
logic         vb_req, vb_we, vb_line, vb_ack;
logic [31:2]  vb_addr;
logic [3:0]   vb_be;
logic [255:0] vb_wdata, vb_rdata;
logic [255:0] v_rdata_w;

IBMRS6K7248_machine #(.CPU_HZ(CPU_HZ), .TB_HZ(TB_HZ), .LE_MODE(LE_MODE), .UART_FAST(UART_FAST), .RTC_FAST(RTC_FAST), .STO_UNIT(STO_UNIT)) machine (
	.clk, .reset, .simm_cfg, .rom_at, .rom_512k, .planar_id,
	.c_req, .c_we, .c_line, .c_addr, .c_be, .c_wdata, .c_ack, .c_rdata,
	.m_req, .m_we, .m_line, .m_addr, .m_be, .m_wdata, .m_ack, .m_rdata,
	.snoop_req, .snoop_we, .snoop_addr, .snoop_ack,
	.sb_sel, .sb_sel_id, .sb_sel_atn, .sb_sel_done, .sb_sel_fail, .sb_bsy, .sb_req, .sb_phase, .sb_tdata,
	.sb_ack, .sb_idata, .sb_ackhold, .sb_atn, .sb_rst,
	.ext_irq, .tb_tick, .kbc_reset, .speaker, .aud_l, .aud_r,
	.fm_cs, .fm_we, .fm_a, .fm_wdata, .fm_rdata, .fm_vol, .joy1, .joy2, .ana1, .ana2, .midi_tx, .midi_rx,
	.fd_in, .fd_ro, .fd_blocks, .fd_mounted, .fd_req, .fd_we, .fd_lba, .fd_ack, .fd_buf_a, .fd_buf_q, .fd_buf_we, .fd_buf_d,
	.ps2_key, .ps2_mouse, .rtc_set, .rtc_time,
	.nv_m_addr, .nv_m_we, .nv_m_wdata, .nv_m_q, .nv_m_ok, .nv_wr_seq,
	.v_req, .v_we, .v_addr, .v_be, .v_wdata, .v_ack, .v_rdata,
	.clk_v(clk_b), .h_total, .h_disp, .h_ss, .h_sl, .v_total, .v_disp, .v_ss, .v_sl, .v_start, .v_pitch,
	.v_screen_on, .v_pix_mask, .v_pll_m, .v_pll_n, .v_cur_on, .v_cur_x, .v_cur_y, .v_cur_base, .v_cur_x11, .v_cur_fg, .v_cur_bg,
	.pal_vaddr, .pal_vq, .vretrace_v, .disp_en_v,
	.en_tx_pend, .en_tx_len, .en_tx_a, .en_tx_q, .en_tx_done, .en_rx_free, .en_rx_we, .en_rx_a, .en_rx_d,
	.en_rx_post, .en_rx_len, .en_rx_hash, .en_aprom_mac, .en_padr, .en_padr_ok,
	.com1_txd, .com1_rxd, .com1_cts_n, .com1_rts_n,
	.io_ev, .io_we, .io_stub, .io_addr, .io_be, .io_wdata, .io_rdata
);

// ---- the SCSI devices ----------------------------------------------------------------------
IBMRS6K7248_scsitgt scsi (
	.clk, .rst(reset), .clk_h(clk_b),
	.sel(sb_sel), .sel_id(sb_sel_id), .sel_atn(sb_sel_atn), .sel_done(sb_sel_done), .sel_fail(sb_sel_fail),
	.bsy(sb_bsy), .req(sb_req), .phase(sb_phase), .tdata(sb_tdata),
	.ack(sb_ack), .idata(sb_idata), .ackhold(sb_ackhold), .atn(sb_atn), .brst(sb_rst),
	.img_present, .img_blocks, .sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack,
	.sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr,
	.cd_change, .cd_l(), .cd_r(), .activity(scsi_activity)
);

// ---- the S3's VRAM: its port across to the memory's clock, then DDR3 and the scan-out ----
assign v_rdata = v_rdata_w[31:0];

DSPPC604_memcdc vcdc (
	.clk_a(clk), .reset_a(reset),
	.a_req(v_req), .a_we(v_we), .a_line(1'b0), .a_addr({11'd0, v_addr}), .a_be(v_be), .a_wdata({224'd0, v_wdata}),
	.a_ack(v_ack), .a_rdata(v_rdata_w),
	.clk_b, .reset_b,
	.b_req(vb_req), .b_we(vb_we), .b_line(vb_line), .b_addr(vb_addr), .b_be(vb_be), .b_wdata(vb_wdata),
	.b_ack(vb_ack), .b_rdata(vb_rdata)
);

logic [31:0]  vb_rdata32;
assign vb_rdata = {224'd0, vb_rdata32};
IBMRS6K7248_s3video s3video (
	.clk(clk_b), .reset(reset_b),
	.c_req(vb_req), .c_we(vb_we), .c_addr(vb_addr[20:2]), .c_be(vb_be), .c_wdata(vb_wdata[31:0]),
	.c_ack(vb_ack), .c_rdata(vb_rdata32),
	.ddr_busy(va_busy), .ddr_burstcnt(va_burstcnt), .ddr_addr(va_addr), .ddr_dout(va_dout), .ddr_dout_ready(va_dout_ready),
	.ddr_rd(va_rd), .ddr_din(va_din), .ddr_be(va_be), .ddr_we(va_we),
	.h_total, .h_disp, .h_ss, .h_sl, .v_total, .v_disp, .v_ss, .v_sl,
	.start(v_start), .pitch(v_pitch), .screen_on(v_screen_on), .pix_mask(v_pix_mask),
	.pll_m(v_pll_m), .pll_n(v_pll_n), .cur_on(v_cur_on), .cur_x(v_cur_x), .cur_y(v_cur_y), .cur_base(v_cur_base),
	.cur_x11(v_cur_x11), .cur_fg(v_cur_fg), .cur_bg(v_cur_bg),
	.pal_addr(pal_vaddr), .pal_q(pal_vq), .vretrace(vretrace_v), .disp_en(disp_en_v),
	.ce_pix(vid_ce), .r(vid_r), .g(vid_g), .b(vid_b), .hs(vid_hs), .vs(vid_vs), .hblank(vid_hblank), .vblank(vid_vblank)
);

DSPPC604_memcdc cdc (
	.clk_a(clk), .reset_a(reset),
	.a_req(m_req), .a_we(m_we), .a_line(m_line), .a_addr(m_addr), .a_be(m_be), .a_wdata(m_wdata),
	.a_ack(m_ack), .a_rdata(m_rdata),
	.clk_b, .reset_b,
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata
);

// ---- the PCnet's wire: the Ethernet mailbox in DDR3, beside the picture side on the DDRAM port ----
logic         nb_req, nb_we, nb_ack;
logic [12:0]  nb_addr;
logic [63:0]  nb_wdata, nb_rdata;
logic [1:0]   net_on_s;
always_ff @(posedge clk_b) net_on_s <= {net_on_s[0], net_on};
IBMRS6K7248_enetbox enetbox (
	.clk(clk_b), .reset(reset_b), .ena(net_on_s[1]),
	.tx_pend(en_tx_pend), .tx_len(en_tx_len), .m_tx_a(en_tx_a), .m_tx_q(en_tx_q), .m_tx_done(en_tx_done),
	.rx_free(en_rx_free), .m_rx_we(en_rx_we), .m_rx_a(en_rx_a), .m_rx_d(en_rx_d), .m_rx_post(en_rx_post),
	.m_rx_len(en_rx_len), .m_rx_hash(en_rx_hash), .aprom_mac(en_aprom_mac), .padr(en_padr), .padr_ok(en_padr_ok),
	.nb_req, .nb_we, .nb_addr, .nb_wdata, .nb_ack, .nb_rdata
);
// the picture side's port (va_*) and the mailbox's on the DDRAM port
IBMRS6K7248_ddrarb ddrarb (
	.clk(clk_b), .reset(reset_b),
	.a_busy(va_busy), .a_burstcnt(va_burstcnt), .a_addr(va_addr), .a_dout(va_dout), .a_dout_ready(va_dout_ready),
	.a_rd(va_rd), .a_din(va_din), .a_be(va_be), .a_we(va_we),
	.nb_req, .nb_we, .nb_addr, .nb_wdata, .nb_ack, .nb_rdata,
	.ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready, .ddr_rd, .ddr_din, .ddr_be, .ddr_we
);

endmodule
