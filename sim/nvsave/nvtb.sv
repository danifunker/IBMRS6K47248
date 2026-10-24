// the NVRAM keeper's bench: IBMRS6K7248_nvsave and the RTC it keeps, two clocks
module nvtb (
	input  logic        clk_s, clk_c,
	input  logic        sel, we,
	input  logic [2:0]  port,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,
	input  logic        img_mounted,
	input  logic [63:0] img_size,
	output logic [31:0] sd_lba,
	output logic        sd_rd, sd_wr,
	input  logic        sd_ack,
	input  logic [13:0] sd_buff_addr,
	input  logic [7:0]  sd_buff_dout,
	input  logic        sd_buff_wr,
	output logic [7:0]  sd_buff_din
);
logic [12:0] m_addr; logic m_we, m_ok; logic [7:0] m_wdata, m_q, wr_seq;
IBMRS6K7248_rtc #(.CLK_HZ(70_000_000)) rtc (
	.clk(clk_c), .reset(1'b0), .sel, .we, .port, .wdata, .rdata, .irq8(), .nmi_mask(),
	.set_time(1'b0), .time_bcd(56'd0), .m_addr, .m_we, .m_wdata, .m_q, .m_ok, .wr_seq);
IBMRS6K7248_nvsave #(.QUIET(2000)) nv (
	.clk_s, .clk_c, .img_mounted, .img_readonly(1'b0), .img_size, .sd_lba, .sd_blk_cnt(), .sd_rd, .sd_wr, .sd_ack,
	.sd_buff_addr, .sd_buff_dout, .sd_buff_wr, .sd_buff_din, .m_addr, .m_we, .m_wdata, .m_q, .m_ok, .wr_seq);
endmodule
