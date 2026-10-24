//============================================================================
//
//  IBMRS6K7248 - the CS4232's joystick port at 200-207
//
//  A write starts the four axes' one-shots; a read gives them in bits 3:0
//  (1 while timing: joystick 1 X, Y, joystick 2 X, Y) and the buttons in
//  7:4 (low while pressed: 1 A, 1 B, 2 A, 2 B). An axis times for 24 us plus
//  up to 1.1 ms by its position: the MiSTer's analog stick when it is off
//  centre, else the d-pad's (all one way, the middle, all the other way).
//
//============================================================================

module IBMRS6K7248_joy
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	output logic [7:0]  rdata,

	// hps_io's: joystick_N bits 0 right, 1 left, 2 down, 3 up, 4 and 5 the first two buttons;
	// joystick_l_analog_N {Y, X}, signed
	input  logic [5:0]  joy1,
	input  logic [5:0]  joy2,
	input  logic [15:0] ana1,
	input  logic [15:0] ana2
);

localparam int unsigned US = CLK_HZ / 1_000_000;

// an axis's position, 0-255 (the left or top 0)
function automatic logic [7:0] pos(input logic [7:0] a, input logic neg, input logic plus);
	if (a != 8'h00) pos = a ^ 8'h80;                       // the analog stick, signed to 0-255
	else if (neg)   pos = 8'h00;
	else if (plus)  pos = 8'hFF;
	else            pos = 8'h80;
endfunction
wire [7:0] p [4];
assign p[0] = pos(ana1[7:0],  joy1[1], joy1[0]);
assign p[1] = pos(ana1[15:8], joy1[3], joy1[2]);
assign p[2] = pos(ana2[7:0],  joy2[1], joy2[0]);
assign p[3] = pos(ana2[15:8], joy2[3], joy2[2]);

logic [31:0] t [4];
logic [3:0]  timing;
always_ff @(posedge clk) begin
	for (int i = 0; i < 4; i++) begin
		if (sel && we) begin
			// 24 us plus 0-1.1 ms (about 4.3 us a step)
			t[i] <= 32'(24 * US) + 32'(p[i]) * 32'((1100 * US) / 256);
			timing[i] <= 1'b1;
		end
		else if (t[i] != 32'd0) t[i] <= t[i] - 32'd1;
		else timing[i] <= 1'b0;
	end
	if (sel && !we) rdata <= {~joy2[5], ~joy2[4], ~joy1[5], ~joy1[4], timing};
	if (reset) timing <= 4'h0;
end

endmodule
