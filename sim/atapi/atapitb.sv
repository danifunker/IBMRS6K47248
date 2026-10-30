// the ATAPI CD-ROM's bench top: IBMRS6K7248_atapi as the only initiator of IBMRS6K7248_scsitgt
module atapitb (
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
	input  logic [31:0] img_blocks [3]
);
logic i_sel, sel_done, sel_fail, bsy, req, ack, want;
logic [2:0] sel_id, phase;
logic [7:0] tdata, idata;
logic [7:0] din [3];
IBMRS6K7248_atapi atapi (.clk, .reset(rst), .en(1'b1), .sel, .cs1, .we, .reg_a, .be, .wd8(wdata[31:24]), .wdata, .rdata, .irq,
	.want, .grant(1'b1), .i_sel, .i_sel_id(sel_id), .sel_done, .sel_fail, .bsy, .req, .phase, .tdata, .ack, .idata);
IBMRS6K7248_scsitgt scsi (.clk, .rst, .clk_h, .sel(i_sel), .sel_id, .sel_atn(1'b0), .sel_done, .sel_fail, .bsy, .req,
	.phase, .tdata, .ack, .idata, .ackhold(1'b0), .atn(1'b0), .brst(1'b0), .img_present(3'b111), .img_blocks,
	.sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack, .sd_buff_addr, .sd_buff_dout, .sd_buff_din(din), .sd_buff_wr,
	.cd_change(1'b0), .cd_l(), .cd_r(), .activity());
endmodule
