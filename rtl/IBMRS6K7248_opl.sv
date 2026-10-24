//============================================================================
//
//  IBMRS6K7248 - the CS4232's FM synthesiser (a YMF289B, an OPL3, on the
//  real board): JTOPL's OPL2 (rtl/jtopl, a YM3812) behind the OPL3's ports
//
//  The ports (the machine's fm_*: 388-38B, and the Sound Blaster's base + 0-3
//  and + 8-9): a0 the index (0) or data (1), a1 the OPL3's bank. Bank 0's
//  registers go to the OPL2: its nine 2-operator voices, the rhythm, the
//  timers; bank 1's (the OPL3's second nine voices, 4-operator pairs,
//  stereo) are taken and dropped. The status reads as an OPL3's (bits 2:1
//  clear), so software finds an OPL3 and uses its OPL2 subset.
//
//  The OPL2 runs at 3.579545 MHz (a clock enable of clk); its writes are
//  queued and handed on as the chip can take them (3.3 us after an index,
//  23 us after data), so software pacing them for a slower bus loses none.
//
//============================================================================

module IBMRS6K7248_opl
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        cs,              // an access, one clock
	input  logic        we,
	input  logic [1:0]  a,               // a0 data, a1 bank 1
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,           // the status, a clock after cs

	output logic [15:0] snd              // signed
);

// the chip's clock: 3,579,545 Hz as a clock enable
localparam logic [31:0] INC = 32'((64'd3_579_545 << 32) / 64'(CLK_HZ));
logic [31:0] acc;
logic        cen;
always_ff @(posedge clk) {cen, acc} <= {1'b0, acc} + {1'b0, INC};

// the writes, queued: {a0, byte}
logic [8:0]  q [64];
logic [5:0]  q_r, q_w;
logic [31:0] gap;
logic        w_go;
logic        w_a0;
logic [7:0]  w_d;
always_ff @(posedge clk) begin
	w_go <= 1'b0;
	if (cs && we && !a[1]) begin q[q_w] <= {a[0], wdata}; q_w <= q_w + 6'd1; end
	if (gap != 32'd0) gap <= gap - 32'd1;
	else if (q_r != q_w) begin
		{w_a0, w_d} <= q[q_r];
		q_r  <= q_r + 6'd1;
		w_go <= 1'b1;
		gap  <= q[q_r][8] ? 32'(CLK_HZ / 43_000) : 32'(CLK_HZ / 300_000);   // 23 us after data, 3.3 us after an index
	end
	if (reset) begin q_r <= 6'd0; q_w <= 6'd0; gap <= 32'd0; end
end

logic [7:0] dout;
wire signed [15:0] snd_s;
logic       rst_q;
always_ff @(posedge clk) rst_q <= reset;
jtopl2 opl (
	.rst(rst_q), .clk, .cen,
	.din(w_d), .addr(w_a0), .cs_n(~w_go), .wr_n(~w_go),
	.dout(dout), .irq_n(), .snd(snd_s), .sample()
);
assign snd = snd_s;

always_ff @(posedge clk) if (cs && !we) rdata <= a[0] ? 8'hFF : {dout[7:5], 5'd0};

endmodule
