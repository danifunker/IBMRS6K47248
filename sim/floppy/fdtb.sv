// the floppy's bench: IBMRS6K7248_fdc, IBMRS6K7248_fdimg and IBMRS6K7248_dma (the machine's wiring between them)
module fdtb (
	input  logic        clk, clk_s, reset,
	input  logic        sel, we, input logic [15:0] port, input logic [7:0] wdata, output logic [7:0] rdata,
	output logic        irq6,
	output logic        dm_req, dm_we, output logic [31:3] dm_addr, output logic [7:0] dm_be, output logic [63:0] dm_wdata,
	input  logic        dm_ack, input logic [63:0] dm_rdata,
	input  logic        img_mounted, img_readonly, input logic [63:0] img_size,
	output logic [31:0] sd_lba, output logic [5:0] sd_blk_cnt, output logic sd_rd, sd_wr, input logic sd_ack,
	input  logic [13:0] sd_buff_addr, input logic [7:0] sd_buff_dout, input logic sd_buff_wr, output logic [7:0] sd_buff_din
);
logic fdrq, dack, tc, sg; logic [2:0] dack_ch, dev_ch; logic [15:0] dack_data; logic [7:0] fdc_q, dma_q, fdc_byte;
logic in, ro, mnt, req, fwe, ack, bwe; logic [12:0] blocks, lba; logic [8:0] ba; logic [7:0] bq, bd;
wire fdh = port[15:3] == 13'h007E && port[2:0] != 3'd6;
logic q; always_ff @(posedge clk) if (sel) q <= fdh;
assign rdata = q ? fdc_q : dma_q;
IBMRS6K7248_fdc fdc (.clk, .reset, .sel(sel & fdh), .we, .off(port[2:0]), .wdata, .rdata(fdc_q), .irq6,
	.drq(fdrq), .dack, .dack_ch, .dack_data(dack_data[7:0]), .tc, .dev_byte(fdc_byte),
	.img_in(in), .img_ro(ro), .img_blocks(blocks), .img_mounted(mnt), .sec_req(req), .sec_we(fwe), .sec_lba(lba), .sec_ack(ack),
	.buf_a(ba), .buf_q(bq), .buf_we(bwe), .buf_d(bd));
IBMRS6K7248_fdimg fdimg (.clk_s, .clk_c(clk), .img_mounted, .img_readonly, .img_size, .sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr,
	.sd_ack, .sd_buff_addr, .sd_buff_dout, .sd_buff_wr, .sd_buff_din,
	.img_in(in), .img_ro(ro), .img_blocks(blocks), .mounted(mnt), .sec_req(req), .sec_we(fwe), .sec_lba(lba), .sec_ack(ack),
	.buf_a(ba), .buf_q(bq), .buf_we(bwe), .buf_d(bd));
IBMRS6K7248_dma dma (.clk, .reset, .sel(sel & !fdh), .we, .port, .wdata, .rdata(dma_q),
	.dreq({5'd0, fdrq, 2'b00}), .dack, .dack_ch, .dack_data, .dev_data({8'h00, fdc_byte}), .dev_ch, .tc, .sg_irq(sg),
	.dm_req, .dm_we, .dm_addr, .dm_be, .dm_wdata, .dm_ack, .dm_err(1'b0), .dm_rdata);
endmodule
