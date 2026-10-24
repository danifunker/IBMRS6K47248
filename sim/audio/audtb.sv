// the audio path's bench: IBMRS6K7248_dma, _cs4232, _sb, _mpu401, _joy and the top's _opl (the machine's
// wiring between them), at CLK_HZ 2 MHz
module audtb (
	input  logic        clk, reset,
	input  logic        sel, we, input logic [15:0] port, input logic [7:0] wdata, output logic [7:0] rdata,
	output logic        dm_req, dm_we, output logic [31:3] dm_addr, output logic [7:0] dm_be, output logic [63:0] dm_wdata,
	input  logic        dm_ack, input logic [63:0] dm_rdata,
	output logic        sg_irq, irq5, output logic [15:0] aud_l, aud_r,
	input  logic [5:0]  joy1, input logic [15:0] ana1,
	output logic        midi_tx, input logic midi_rx,
	output logic [15:0] fm_snd
);
logic aud_on, drq, cdrq, sdrq, srec, dack, tc, cirq, sirq, mirq; logic [15:4] sb_base; logic [15:2] wss_base;
logic [2:0] dack_ch; logic [15:0] dack_data; logic [7:0] rec_byte, fm_vol;
logic [7:0] dma_q, aud_q, sb_q, mpu_q, joy_q, fm_q;
logic [15:0] cl, cr, sl, sr;
wire cfg = port == 16'h0279;
wire win = aud_on && port[15:4] == sb_base;
wire sbf = port[3:2] == 2'b00 || port[3:1] == 3'b100;
wire sbh = win && !sbf;
wire fmh = (win && sbf) || (aud_on && port[15:2] == 14'h00E2);
wire wss = aud_on && port[15:2] == wss_base;
wire mph = aud_on && port[15:1] == 15'h0198;
wire jyh = aud_on && port[15:3] == 13'h0040;
wire dmh = port[15:4] == 12'h000 || port[15:4] == 12'h008 || port[15:5] == 11'h006 || port == 16'h040A || port == 16'h040B ||
           (port >= 16'h0410 && port <= 16'h043F) || port[15:4] == 12'h048 || port == 16'h04D4 || port == 16'h04D6;
logic [2:0] q;
always_ff @(posedge clk) if (sel) q <= wss ? 3'd1 : sbh ? 3'd2 : fmh ? 3'd3 : mph ? 3'd4 : jyh ? 3'd5 : 3'd0;
assign rdata = q == 3'd1 ? aud_q : q == 3'd2 ? sb_q : q == 3'd3 ? fm_q : q == 3'd4 ? mpu_q : q == 3'd5 ? joy_q : dma_q;
assign irq5 = cirq | sirq | mirq;
assign aud_l = cl + sl; assign aud_r = cr + sr;
IBMRS6K7248_cs4232 #(.CLK_HZ(2_000_000)) cs (.clk, .reset, .cfg_sel(sel & we & cfg), .sel(sel & wss), .we, 
	.off(port[3:0]), .wdata, .rdata(aud_q), .on(aud_on), .sb_base, .wss_base,
	.drq(cdrq), .dack, .dack_ch, .dack_data(dack_data[7:0]), .irq(cirq), .cap_drq(drq), .rec_byte, .aud_l(cl), .aud_r(cr));
IBMRS6K7248_sb #(.CLK_HZ(2_000_000)) sb (.clk, .reset, .sel(sel & sbh), .we, .off(port[3:0]), .wdata, .rdata(sb_q),
	.drq(sdrq), .rec(srec), .dack, .dack_ch, .dack_data(dack_data[7:0]), .irq(sirq), .aud_l(sl), .aud_r(sr), .fm_vol);
IBMRS6K7248_mpu401 #(.CLK_HZ(2_000_000)) mpu (.clk, .reset, .sel(sel & mph), .we, .a0(port[0]), .wdata, .rdata(mpu_q),
	.irq(mirq), .midi_tx, .midi_rx);
IBMRS6K7248_joy #(.CLK_HZ(2_000_000)) joy (.clk, .reset, .sel(sel & jyh), .we, .rdata(joy_q),
	.joy1, .joy2(6'd0), .ana1, .ana2(16'd0));
IBMRS6K7248_opl #(.CLK_HZ(2_000_000)) opl (.clk, .reset, .cs(sel & fmh), .we,
	.a((win && port[3]) ? {1'b0, port[0]} : port[1:0]), .wdata, .rdata(fm_q), .snd(fm_snd));
IBMRS6K7248_dma dma (.clk, .reset, .sel(sel & dmh), .we, .port, .wdata, .rdata(dma_q),
	.dreq({6'd0, cdrq | sdrq, drq}), .dack, .dack_ch, .dack_data, .dev_data(srec ? 16'h0080 : {8'h00, rec_byte}), .tc, .sg_irq,
	.dm_req, .dm_we, .dm_addr, .dm_be, .dm_wdata, .dm_ack, .dm_err(1'b0), .dm_rdata);
endmodule
