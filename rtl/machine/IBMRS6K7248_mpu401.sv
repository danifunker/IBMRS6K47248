//============================================================================
//
//  IBMRS6K7248 - the CS4232's MPU-401 (UART mode) at 330 / 331
//
//  331 read: the status (bit 7 clear: a byte waits at 330; bit 6 clear: a
//  byte may be written); 331 write: a command (FF reset, 3F UART mode: each
//  answered with FE at 330); 330 write: a MIDI byte out, 330 read: the next
//  byte in (or the command's FE). MIDI goes out and comes in as serial
//  bytes at 31,250 baud (the MiSTer's user port, through sys/mt32pi.sv, to
//  an MT32-pi). Bytes in raise the IRQ (the WSS's, 5) while UART mode is on.
//
//============================================================================

module IBMRS6K7248_mpu401
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic        a0,             // 331 (else 330)
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,
	output logic        irq,

	output logic        midi_tx,        // idle high
	input  logic        midi_rx
);

localparam int unsigned BIT = CLK_HZ / 31_250;

// bytes waiting to be read: the commands' FEs and the bytes in
logic [7:0] in_q [8];
logic [2:0] in_r, in_w;
logic [3:0] in_n;
logic       uart;                       // UART mode
// bytes waiting to go out
logic [7:0] out_q [16];
logic [3:0] out_r, out_w;
logic [4:0] out_n;

// the receiver
logic [2:0]  rx_s;
logic [15:0] rx_t;
logic [3:0]  rx_k;                      // 0 idle; 1-8 data bits; 9 the stop bit
logic [7:0]  rx_sh;
logic        rx_got;
logic [7:0]  rx_b;
always_ff @(posedge clk) begin
	rx_s   <= {rx_s[1:0], midi_rx};
	rx_got <= 1'b0;
	if (rx_k == 4'd0) begin
		if (!rx_s[2]) begin rx_k <= 4'd1; rx_t <= 16'(BIT + BIT / 2); end        // the start bit: to the first bit's middle
	end
	else if (rx_t != 16'd0) rx_t <= rx_t - 16'd1;
	else if (rx_k != 4'd9) begin rx_sh <= {rx_s[2], rx_sh[7:1]}; rx_k <= rx_k + 4'd1; rx_t <= 16'(BIT); end
	else begin rx_k <= 4'd0; if (rx_s[2]) begin rx_got <= 1'b1; rx_b <= rx_sh; end end
	if (reset) rx_k <= 4'd0;
end

// the transmitter
logic [9:0]  tx_sh;
logic [3:0]  tx_k;                      // bits left
logic [15:0] tx_t;
logic        tx_pop;
always_ff @(posedge clk) begin
	tx_pop <= 1'b0;
	if (tx_k == 4'd0) begin
		midi_tx <= 1'b1;
		if (out_n != 5'd0 && !tx_pop) begin tx_sh <= {1'b1, out_q[out_r], 1'b0}; tx_k <= 4'd10; tx_t <= 16'd0; tx_pop <= 1'b1; end
	end
	else if (tx_t != 16'd0) tx_t <= tx_t - 16'd1;
	else begin midi_tx <= tx_sh[0]; tx_sh <= {1'b1, tx_sh[9:1]}; tx_k <= tx_k - 4'd1; tx_t <= 16'(BIT - 1); end
	if (reset) begin tx_k <= 4'd0; midi_tx <= 1'b1; end
end

always_ff @(posedge clk) begin
	if (tx_pop) begin out_r <= out_r + 4'd1; end
	if (sel) begin
		if (we) begin
			if (a0) begin
				// a command: FF resets (and leaves UART mode), 3F enters it; both answered FE
				if (wdata == 8'hFF || wdata == 8'h3F) begin
					uart <= wdata == 8'h3F;
					in_q[in_w] <= 8'hFE; in_w <= in_w + 3'd1;
				end
			end
			else if (out_n != 5'd16) begin out_q[out_w] <= wdata; out_w <= out_w + 4'd1; end
		end
		else begin
			if (a0) rdata <= {in_n == 4'd0, out_n == 5'd16, 6'h3F};
			else begin
				rdata <= in_n != 4'd0 ? in_q[in_r] : 8'hFF;
				if (in_n != 4'd0) in_r <= in_r + 3'd1;
			end
		end
	end
	if (rx_got && uart && in_n != 4'd8) begin in_q[in_w] <= rx_b; in_w <= in_w + 3'd1; end
	in_n  <= in_n + ((sel && we && a0 && (wdata == 8'hFF || wdata == 8'h3F)) || (rx_got && uart && in_n != 4'd8) ? 4'd1 : 4'd0)
	             - ((sel && !we && !a0 && in_n != 4'd0) ? 4'd1 : 4'd0);
	out_n <= out_n + ((sel && we && !a0 && out_n != 5'd16) ? 5'd1 : 5'd0) - (tx_pop ? 5'd1 : 5'd0);
	if (reset) begin in_r <= 3'd0; in_w <= 3'd0; in_n <= 4'd0; out_r <= 4'd0; out_w <= 4'd0; out_n <= 5'd0; uart <= 1'b0; end
end
assign irq = uart && in_n != 4'd0;

endmodule
