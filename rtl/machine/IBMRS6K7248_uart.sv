//============================================================================
//
//  IBMRS6K7248 - a 16550A-compatible UART (the Super I/O's serial ports)
//
//  The registers a PC/PReP firmware and AIX's serial driver use: RBR/THR,
//  IER, IIR/FCR, LCR, MCR, LSR, MSR, SCR, the divisor latch (DLAB), the
//  16-byte FIFOs (FCR[0]; IIR[7:6] = 11 while on, so the chip reads as a
//  16550A), the receive trigger levels and the character timeout, the
//  internal loopback (MCR[4]: the transmitter into the receiver, OUT1, OUT2,
//  RTS and DTR into the modem status), and the interrupt as the chip
//  prioritises it. The serial line runs at the divisor's rate from a
//  1.8432 MHz clock made from CLK_HZ by phase accumulation.
//
//  Left out: break, parity and framing errors (the receiver takes eight
//  data bits and a stop bit whatever LCR says; the transmitter sends the
//  word length LCR asks for, no parity), the DMA mode signals.
//
//  The bus: one access a cycle, a register by its three address bits, the
//  read value in rdata the cycle after sel (reads with side effects - RBR,
//  IIR, LSR, MSR - act at sel).
//
//============================================================================

module IBMRS6K7248_uart
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic       clk,
	input  logic       reset,

	input  logic       sel,
	input  logic       we,
	input  logic [2:0] addr,
	input  logic [7:0] wdata,
	output logic [7:0] rdata,
	output logic       irq,            // the chip's INTR (gated by OUT2 on a PC board: the caller decides)
	output logic       out2,           // MCR[3]

	output logic       txd,            // 1 when idle
	input  logic       rxd,
	input  logic       cts_n,          // the modem lines, active low as on the connector
	input  logic       dsr_n,
	input  logic       dcd_n,
	input  logic       ri_n,
	output logic       rts_n,
	output logic       dtr_n
);

// ---- the 1.8432 MHz clock, then the 16x clock from the divisor ----------------
localparam logic [31:0] XTAL_INC = 32'((64'd1_843_200 << 32) / 64'(CLK_HZ));
logic [31:0] xacc = '0;
logic        xtick;
always_ff @(posedge clk) {xtick, xacc} <= {1'b0, xacc} + {1'b0, XTAL_INC};

logic [15:0] dl;                        // the divisor latch
logic [15:0] bdiv = '0;
logic        tick16;                    // 16 x the baud rate
always_ff @(posedge clk) begin
	tick16 <= 1'b0;
	if (xtick) begin
		if (bdiv <= 16'd1) begin
			bdiv   <= dl;
			tick16 <= dl != 16'd0;
		end
		else bdiv <= bdiv - 16'd1;
	end
end

// ---- registers ----------------------------------------------------------------
logic [7:0] ier, lcr, mcr, scr;
logic       fifo_on;
logic [1:0] rx_trig;
wire        dlab = lcr[7];
wire        loop = mcr[4];

// FIFOs: 16 bytes each (one byte deep when FIFOs are off)
logic [7:0] txf [16];
logic [3:0] txf_r, txf_w;
logic [4:0] txf_n;
logic [7:0] rxf [16];
logic [3:0] rxf_r, rxf_w;
logic [4:0] rxf_n;
logic       oe;                         // overrun
logic       thre_int;                   // the THR-empty interrupt condition (cleared by an IIR read or a THR write)
logic [3:0] msr_d;                      // the delta bits
logic [3:0] msr_q;                      // CTS, DSR, RI, DCD as last seen (true = asserted)
logic [9:0] rx_idle;                    // 16x ticks with nothing received or read
logic       timeout;

// the modem inputs (or the loopback's)
wire  [3:0] msr_now = loop ? {mcr[2], mcr[3], mcr[0], mcr[1]} // DCD=OUT2, RI=OUT1, DSR=DTR, CTS=RTS
                           : {~dcd_n, ~ri_n, ~dsr_n, ~cts_n};
// order kept as MSR bits 7..4: DCD, RI, DSR, CTS
assign rts_n = ~mcr[1];
assign dtr_n = ~mcr[0];
assign out2  = mcr[3];

// ---- transmitter --------------------------------------------------------------
logic [3:0] tx_ph;                      // 16 ticks a bit
logic [3:0] tx_bit;                     // 0 idle; then start, data, stop
logic [9:0] tx_sh;
logic       tx_line = 1'b1;
wire  [3:0] tx_bits = 4'd7 + {2'd0, lcr[1:0]};   // start + 5..8 data + stop - 1
wire        tx_busy = tx_bit != 4'd0;

// ---- receiver -----------------------------------------------------------------
logic [2:0] rx_s = 3'b111;
wire        rx_in = loop ? tx_line : rx_s[2];
logic [3:0] rx_ph;
logic [3:0] rx_bit;                     // 0 hunting; 1 start; 2-9 data; 10 stop
logic [7:0] rx_sh;
logic       rx_put;
logic [7:0] rx_byte;

always_ff @(posedge clk) begin
	rx_s   <= {rx_s[1:0], rxd};
	rx_put <= 1'b0;
	if (tick16) begin
		if (rx_bit == 4'd0) begin
			if (!rx_in) begin rx_bit <= 4'd1; rx_ph <= 4'd0; end
		end
		else begin
			rx_ph <= rx_ph + 4'd1;
			if (rx_ph == 4'd7) begin                    // mid-bit
				if (rx_bit == 4'd1) begin
					if (rx_in) rx_bit <= 4'd0;          // a glitch, not a start bit
					else       rx_bit <= 4'd2;
				end
				else if (rx_bit < 4'd10) begin
					rx_sh  <= {rx_in, rx_sh[7:1]};
					rx_bit <= rx_bit + 4'd1;
				end
				else begin
					rx_byte <= rx_sh;
					rx_put  <= 1'b1;
					rx_bit  <= 4'd0;
				end
			end
		end
	end
	if (reset) rx_bit <= 4'd0;
end

// ---- the bus, the FIFOs, the transmitter ------------------------------------------
wire  rd_rbr = sel & ~we & addr == 3'd0 & ~dlab;
wire  wr_thr = sel &  we & addr == 3'd0 & ~dlab;
wire  rd_iir = sel & ~we & addr == 3'd2;
wire  rd_lsr = sel & ~we & addr == 3'd5;
wire  rd_msr = sel & ~we & addr == 3'd6;
wire  depth1 = ~fifo_on;
wire  [4:0] trig = !fifo_on ? 5'd1 : rx_trig == 2'd0 ? 5'd1 : rx_trig == 2'd1 ? 5'd4 : rx_trig == 2'd2 ? 5'd8 : 5'd14;
wire  rda  = rxf_n >= trig;
wire  rls  = oe;
logic [3:0] iir_id;
always_comb begin
	if      (ier[2] & rls)                 iir_id = 4'b0110;
	else if (ier[0] & rda)                 iir_id = 4'b0100;
	else if (ier[0] & timeout & fifo_on)   iir_id = 4'b1100;
	else if (ier[1] & thre_int)            iir_id = 4'b0010;
	else if (ier[3] & (msr_d != 4'd0))     iir_id = 4'b0000;
	else                                   iir_id = 4'b0001;
end
assign irq = ~iir_id[0];
wire [7:0] lsr = {1'b0, txf_n == 5'd0 && !tx_busy, txf_n == 5'd0, 1'b0, 1'b0, 1'b0, oe, rxf_n != 5'd0};

always_ff @(posedge clk) begin
	// receive into the FIFO
	if (rx_put) begin
		if (rxf_n == (depth1 ? 5'd1 : 5'd16)) oe <= 1'b1;
		else begin
			rxf[rxf_w] <= rx_byte;
			rxf_w      <= depth1 ? rxf_w : rxf_w + 4'd1;
		end
	end
	// the character timeout: four character times (40 bit times, 640 ticks)
	// with bytes waiting and none received or read
	if (rx_put | rd_rbr | rxf_n == 5'd0) begin rx_idle <= '0; timeout <= 1'b0; end
	else if (tick16) begin
		if (rx_idle != 10'd640) rx_idle <= rx_idle + 10'd1;
		else timeout <= 1'b1;
	end
	// the transmitter: one bit every 16 ticks
	if (tick16) begin
		if (tx_bit != 4'd0) begin
			tx_ph <= tx_ph + 4'd1;
			if (tx_ph == 4'd15) begin
				tx_line <= tx_sh[0];
				tx_sh   <= {1'b1, tx_sh[9:1]};
				tx_bit  <= (tx_bit == tx_bits + 4'd1) ? 4'd0 : tx_bit + 4'd1;
			end
		end
	end
	if (tx_bit == 4'd0 && txf_n != 5'd0) begin
		tx_sh   <= {1'b1, txf[txf_r], 1'b0};
		txf_r   <= txf_r + 4'd1;
		tx_bit  <= 4'd1;
		tx_ph   <= 4'd0;
		if (txf_n == 5'd1) thre_int <= 1'b1;
	end
	// modem status deltas
	msr_q <= msr_now;
	if (msr_now[0] != msr_q[0]) msr_d[0] <= 1'b1;               // DCTS
	if (msr_now[1] != msr_q[1]) msr_d[1] <= 1'b1;               // DDSR
	if (msr_q[2] & ~msr_now[2]) msr_d[2] <= 1'b1;               // TERI
	if (msr_now[3] != msr_q[3]) msr_d[3] <= 1'b1;               // DDCD

	if (sel) begin
		if (we) begin
			case (addr)
				3'd0: if (dlab) dl[7:0] <= wdata;
				      else if (txf_n != 5'd16) begin
					txf[txf_w] <= wdata;
					txf_w      <= txf_w + 4'd1;
					thre_int   <= 1'b0;
				end
				3'd1: if (dlab) dl[15:8] <= wdata;
				      else begin
					ier <= {4'd0, wdata[3:0]};
					if (wdata[1] && txf_n == 5'd0) thre_int <= 1'b1;
				end
				3'd2: begin
					fifo_on <= wdata[0];
					rx_trig <= wdata[7:6];
					if (wdata[1] || wdata[0] != fifo_on) begin rxf_r <= '0; rxf_w <= '0; end
					if (wdata[2] || wdata[0] != fifo_on) begin txf_r <= '0; txf_w <= '0; end
				end
				3'd3: lcr <= wdata;
				3'd4: mcr <= {3'd0, wdata[4:0]};
				3'd7: scr <= wdata;
				default: ;
			endcase
		end
		else begin
			case (addr)
				3'd0: rdata <= dlab ? dl[7:0] : rxf[rxf_r];
				3'd1: rdata <= dlab ? dl[15:8] : ier;
				3'd2: rdata <= {fifo_on, fifo_on, 2'b00, iir_id};
				3'd3: rdata <= lcr;
				3'd4: rdata <= mcr;
				3'd5: rdata <= lsr;
				3'd6: rdata <= {msr_now[3], msr_now[2], msr_now[1], msr_now[0], msr_d[3], msr_d[2], msr_d[1], msr_d[0]};
				default: rdata <= scr;
			endcase
			if (rd_rbr && rxf_n != 5'd0) rxf_r <= depth1 ? rxf_r : rxf_r + 4'd1;
			if (rd_iir && iir_id == 4'b0010) thre_int <= 1'b0;
			if (rd_lsr) oe <= 1'b0;
			if (rd_msr) msr_d <= 4'd0;
		end
	end
	if (reset) begin
		ier <= '0; lcr <= '0; mcr <= '0; scr <= '0; dl <= 16'd12;
		fifo_on <= 1'b0; rx_trig <= '0;
		txf_r <= '0; txf_w <= '0; rxf_r <= '0; rxf_w <= '0;
		oe <= 1'b0; thre_int <= 1'b0; msr_d <= '0;
		tx_bit <= '0; tx_ph <= '0; tx_line <= 1'b1;
		rx_idle <= '0; timeout <= 1'b0;
	end
end

// FIFO fill levels, from the pointers' moves this cycle
wire tx_push = wr_thr && txf_n != 5'd16;
wire tx_pop  = tx_bit == 4'd0 && txf_n != 5'd0;
wire rx_push = rx_put && rxf_n != (depth1 ? 5'd1 : 5'd16);
wire rx_pop  = rd_rbr && rxf_n != 5'd0;
wire fcr_wr  = sel & we & addr == 3'd2;
always_ff @(posedge clk) begin
	if (reset) begin txf_n <= '0; rxf_n <= '0; end
	else begin
		if (fcr_wr && (wdata[2] || wdata[0] != fifo_on)) txf_n <= '0;
		else txf_n <= txf_n + {4'd0, tx_push} - {4'd0, tx_pop};
		if (fcr_wr && (wdata[1] || wdata[0] != fifo_on)) rxf_n <= '0;
		else rxf_n <= rxf_n + {4'd0, rx_push} - {4'd0, rx_pop};
	end
end

assign txd = loop ? 1'b1 : tx_line;

endmodule
