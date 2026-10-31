// the IDE hard disk's bench top: IBMRS6K7248_idehd (device 1) beside IBMRS6K7248_atapi (device 0) on one task
// file, both initiators of IBMRS6K7248_scsitgt with the machine's arbitration (the CD-ROM first)
module idehdtb (
	input  logic        clk, clk_h, rst,
	input  logic        sel, cs1, we,
	input  logic [2:0]  reg_a,
	input  logic [3:0]  be,
	input  logic [31:0] wdata,
	output logic [31:0] rdata,
	output logic        irq,
	output logic [31:0] sd_lba [3],
	output logic [5:0]  sd_blk_cnt [3],
	output logic [2:0]  sd_rd, sd_wr,
	input  logic [2:0]  sd_ack,
	input  logic [13:0] sd_buff_addr,
	input  logic [7:0]  sd_buff_dout,
	input  logic        sd_buff_wr,
	output logic [7:0]  sd_buff_din [3],
	input  logic [31:0] img_blocks [3]
);
logic sb_sel, sel_done, sel_fail, bsy, req, sb_ack;
logic [2:0] sb_sel_id, phase;
logic [7:0] tdata, sb_idata;
logic at_want, at_sel, at_ack, at_own, hd_want, hd_sel, hd_ack, hd_own, hd_irq, at_irq, hd_selected;
logic [2:0] at_sel_id, hd_sel_id;
logic [7:0] at_idata, hd_idata;
logic [31:0] at_q, hd_q;
always_ff @(posedge clk) begin
	if (!at_own && !hd_own && at_want && !bsy) at_own <= 1'b1;
	else if (at_own && !at_want && !bsy) at_own <= 1'b0;
	if (!at_own && !hd_own && hd_want && !bsy) hd_own <= 1'b1;
	else if (hd_own && !hd_want && !bsy) hd_own <= 1'b0;
	if (rst) begin at_own <= 1'b0; hd_own <= 1'b0; end
end
IBMRS6K7248_atapi #(.CLK_HZ(1_000_000)) atapi (.clk, .reset(rst), .en(1'b1), .sel, .cs1, .we, .reg_a, .be, .wd8(wdata[31:24]), .wdata, .rdata(at_q), .irq(at_irq),
	.want(at_want), .grant(at_own), .i_sel(at_sel), .i_sel_id(at_sel_id), .sel_done(at_own & sel_done), .sel_fail(at_own & sel_fail),
	.bsy(at_own & bsy), .req(at_own & req), .phase, .tdata, .ack(at_ack), .idata(at_idata));
IBMRS6K7248_idehd #(.CLK_HZ(1_000_000)) hd (.clk, .reset(rst), .en(1'b1), .sel, .cs1, .we, .reg_a, .be, .wd8(wdata[31:24]), .wdata, .rdata(hd_q), .irq(hd_irq),
	.selected(hd_selected), .blocks(img_blocks[0]), .st_irq(), .st_blk(), .st_disk(), .st_host(),
	.want(hd_want), .grant(hd_own), .i_sel(hd_sel), .i_sel_id(hd_sel_id), .sel_done(hd_own & sel_done), .sel_fail(hd_own & sel_fail),
	.bsy(hd_own & bsy), .req(hd_own & req), .phase, .tdata, .ack(hd_ack), .idata(hd_idata));
assign sb_sel    = at_own ? at_sel    : hd_sel;
assign sb_sel_id = at_own ? at_sel_id : hd_sel_id;
assign sb_ack    = at_own ? at_ack    : hd_ack;
assign sb_idata  = at_own ? at_idata  : hd_idata;
assign rdata = at_q | hd_q;
assign irq   = at_irq | hd_irq;
IBMRS6K7248_scsitgt scsi (.clk, .rst, .clk_h, .sel(sb_sel), .sel_id(sb_sel_id), .sel_atn(1'b0), .sel_done, .sel_fail, .bsy, .req,
	.phase, .tdata, .ack(sb_ack), .idata(sb_idata), .ackhold(1'b0), .atn(1'b0), .brst(1'b0), .img_present(3'b111), .img_blocks,
	.sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack, .sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr,
	.cd_change(1'b0), .cd_l(), .cd_r(), .activity());
endmodule
