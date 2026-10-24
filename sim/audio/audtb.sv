// the audio path's bench: IBMRS6K7248_dma and IBMRS6K7248_cs4232 (the machine's wiring between them)
module audtb (
	input  logic        clk, reset,
	input  logic        sel, we, input logic [15:0] port, input logic [7:0] wdata, output logic [7:0] rdata,
	output logic        dm_req, dm_we, output logic [31:3] dm_addr, output logic [7:0] dm_be, output logic [63:0] dm_wdata,
	input  logic        dm_ack, input logic [63:0] dm_rdata,
	output logic        sg_irq, aud_irq, output logic [15:0] aud_l, aud_r
);
logic aud_on, drq, dack, tc; logic [15:4] sb_base; logic [15:2] wss_base; logic [2:0] dack_ch; logic [15:0] dack_data;
logic [7:0] dma_q, aud_q;
wire cfg = port == 16'h0279;
wire sb  = aud_on && port[15:4] == sb_base;
wire wss = aud_on && port[15:2] == wss_base;
wire dmh = port[15:4] == 12'h000 || port[15:4] == 12'h008 || port[15:5] == 11'h006 || port == 16'h040A || port == 16'h040B ||
           (port >= 16'h0410 && port <= 16'h043F) || port[15:4] == 12'h048 || port == 16'h04D4 || port == 16'h04D6;
logic q_aud;
always_ff @(posedge clk) if (sel) q_aud <= sb | wss;
assign rdata = q_aud ? aud_q : dma_q;
IBMRS6K7248_cs4232 #(.CLK_HZ(2_000_000)) cs (.clk, .reset, .cfg_sel(sel & we & cfg), .sel(sel & (sb | wss)), .we, .wss,
	.off(port[3:0]), .wdata, .rdata(aud_q), .on(aud_on), .sb_base, .wss_base,
	.drq, .dack, .dack_ch, .dack_data(dack_data[7:0]), .irq(aud_irq), .aud_l, .aud_r);
IBMRS6K7248_dma dma (.clk, .reset, .sel(sel & dmh), .we, .port, .wdata, .rdata(dma_q),
	.dreq({6'd0, drq, 1'b0}), .dack, .dack_ch, .dack_data, .dev_data(16'h0), .tc, .sg_irq,
	.dm_req, .dm_we, .dm_addr, .dm_be, .dm_wdata, .dm_ack, .dm_err(1'b0), .dm_rdata);
endmodule
