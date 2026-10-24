//============================================================================
//
//  IBMRS6K7248 - the framework's DDRAM port shared: the S3's picture side
//  first, the Ethernet mailbox's words in its gaps
//
//  Port A is IBMRS6K7248_s3video's (a burst read, or a word write, held
//  while ddr_busy); port B the mailbox's (IBMRS6K7248_enetbox: one 64-bit
//  word at MBOX + nb_addr, held until nb_ack). Whoever is granted keeps the
//  port until its access is done (a read: its last word back); A wins a
//  tie. A not granted sees the port busy, so it holds its request.
//
//============================================================================

module IBMRS6K7248_ddrarb
#(
	parameter logic [28:0] MBOX = 29'h03FE_0000           // ARM physical 1FF0_0000, in 64-bit words
)
(
	input  logic        clk,
	input  logic        reset,

	// A: the picture side
	output logic        a_busy,
	input  logic [7:0]  a_burstcnt,
	input  logic [28:0] a_addr,
	output logic [63:0] a_dout,
	output logic        a_dout_ready,
	input  logic        a_rd,
	input  logic [63:0] a_din,
	input  logic [7:0]  a_be,
	input  logic        a_we,

	// B: the mailbox
	input  logic        nb_req,
	input  logic        nb_we,
	input  logic [12:0] nb_addr,
	input  logic [63:0] nb_wdata,
	output logic        nb_ack,
	output logic [63:0] nb_rdata,

	// the DDRAM port
	input  logic        ddr_busy,
	output logic [7:0]  ddr_burstcnt,
	output logic [28:0] ddr_addr,
	input  logic [63:0] ddr_dout,
	input  logic        ddr_dout_ready,
	output logic        ddr_rd,
	output logic [63:0] ddr_din,
	output logic [7:0]  ddr_be,
	output logic        ddr_we
);

typedef enum logic [2:0] {R_IDLE, R_A, R_A_RD, R_B, R_B_RD} rst_t;
rst_t       r;
logic [7:0] left;                                       // a read's words still to come

wire own_a = r == R_A || r == R_A_RD;
wire own_b = r == R_B;

assign ddr_burstcnt = own_a ? a_burstcnt : 8'd1;
assign ddr_addr     = own_a ? a_addr : MBOX + {16'd0, nb_addr};
assign ddr_din      = own_a ? a_din : nb_wdata;
assign ddr_be       = own_a ? a_be : 8'hFF;
assign ddr_rd       = (r == R_A && a_rd) || (own_b && !nb_we);
assign ddr_we       = (r == R_A && a_we) || (own_b && nb_we);
assign a_busy       = r != R_A || ddr_busy;
assign a_dout       = ddr_dout;
assign a_dout_ready = r == R_A_RD && ddr_dout_ready;
assign nb_rdata     = ddr_dout;

always_ff @(posedge clk) begin
	nb_ack <= 1'b0;
	case (r)
		R_IDLE: begin
			if (a_rd || a_we) r <= R_A;
			else if (nb_req && !nb_ack) r <= R_B;
		end
		R_A: if (!ddr_busy) begin
			if (a_rd) begin left <= a_burstcnt; r <= R_A_RD; end   // taken: its words come back
			else if (a_we) r <= R_IDLE;
			else r <= R_IDLE;                                     // (nothing asked after all)
		end
		R_A_RD: if (ddr_dout_ready) begin
			left <= left - 8'd1;
			if (left == 8'd1) r <= R_IDLE;
		end
		R_B: if (!ddr_busy) begin
			if (nb_we) begin nb_ack <= 1'b1; r <= R_IDLE; end
			else r <= R_B_RD;
		end
		R_B_RD: if (ddr_dout_ready) begin nb_ack <= 1'b1; r <= R_IDLE; end
		default: r <= R_IDLE;
	endcase
	if (reset) r <= R_IDLE;
end

endmodule
