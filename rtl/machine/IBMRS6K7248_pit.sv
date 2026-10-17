//============================================================================
//
//  IBMRS6K7248 - the 8254 interval timer (in Fire Coral) and port 61
//
//  Three counters at 40-42, the control word at 43, clocked at
//  1,193,182 Hz (14.31818 MHz / 12) made from CLK_HZ by phase
//  accumulation. Counter 0 is IRQ0, counter 1 the refresh request (port
//  61 bit 4 toggles with it), counter 2 the speaker (gated by port 61 bit
//  0, its output read at bit 5 and sent out ANDed with bit 1).
//
//  Every mode: 0 (interrupt on terminal count), 1 (retriggerable one-shot),
//  2 (rate generator), 3 (square wave), 4 and 5 (strobes); binary counting
//  (BCD counting is taken as binary); the read/load orders LSB, MSB and
//  both; the counter latch command and the read-back command (count and
//  status). Counters 0 and 1 have their gates tied high, as on the AT.
//
//  The bus: one byte access a cycle by port, the read value in rdata the
//  cycle after sel.
//
//============================================================================

module IBMRS6K7248_pit
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic       clk,
	input  logic       reset,

	input  logic       sel,
	input  logic       we,
	input  logic       p61,            // port 61 (else 40-43 by a)
	input  logic [1:0] a,
	input  logic [7:0] wdata,
	output logic [7:0] rdata,

	output logic       irq0,           // counter 0's output
	output logic       spk             // the speaker: counter 2's output AND port 61 bit 1
);

localparam logic [31:0] INC = 32'((64'd1_193_182 << 32) / 64'(CLK_HZ));
logic [31:0] acc = '0;
logic        tick;
always_ff @(posedge clk) {tick, acc} <= {1'b0, acc} + {1'b0, INC};

logic [1:0] p61_r;                     // port 61 bits 1 and 0: speaker data, counter 2's gate
logic       refresh;

logic [15:0] cnt [3], reload [3], latch [3];
logic [5:0]  ctl [3];                  // {rw[1:0], mode[2:0], bcd}
logic        out [3];
logic        latched [3];              // the count latched, not yet read entirely
logic        st_latched [3];
logic [7:0]  status [3];
logic        rd_hi [3], wr_hi [3];     // the next byte of a two-byte read or write is the MSB
logic        armed [3];                // a count has been written (null count cleared when loaded)
logic        load [3];                 // load the reload value at the next tick
logic        gate_prev [3];
logic        running [3];
logic [7:0]  rq [3], rq61;             // each source's read value
logic [1:0]  rsrc;                     // ... and which one the last read was

wire  [2:0]  gate = {p61_r[0], 1'b1, 1'b1};

genvar c;
generate
for (c = 0; c < 3; c++) begin : g_ctr
	wire [2:0] mode   = ctl[c][3:1] == 3'd6 ? 3'd2 : ctl[c][3:1] == 3'd7 ? 3'd3 : ctl[c][3:1];
	wire       ctl_w  = sel & we & ~p61 & a == 2'd3 & wdata[7:6] == 2'(c);
	wire       rb_w   = sel & we & ~p61 & a == 2'd3 & wdata[7:6] == 2'd3 & wdata[1 + c];
	wire       dat_w  = sel & we & ~p61 & a == 2'(c);
	wire       dat_r  = sel & ~we & ~p61 & a == 2'(c);
	wire       g      = gate[c];
	wire       g_rise = g & ~gate_prev[c];
	wire [15:0] rl    = reload[c];

	always_ff @(posedge clk) begin
		if (tick) gate_prev[c] <= g;

		// the control word
		if (ctl_w) begin
			if (wdata[5:4] == 2'b00) begin                       // counter latch
				if (!latched[c]) begin latch[c] <= cnt[c]; latched[c] <= 1'b1; end
			end
			else begin
				ctl[c]     <= wdata[5:0];
				wr_hi[c]   <= 1'b0;
				rd_hi[c]   <= 1'b0;
				latched[c] <= 1'b0;
				armed[c]   <= 1'b0;
				running[c] <= 1'b0;
				out[c]     <= wdata[3:1] != 3'd0;                 // mode 0 starts low, the others high
			end
		end
		if (rb_w) begin
			if (!wdata[5] && !latched[c]) begin latch[c] <= cnt[c]; latched[c] <= 1'b1; end
			if (!wdata[4] && !st_latched[c]) begin
				status[c]     <= {out[c], ~armed[c], ctl[c]};
				st_latched[c] <= 1'b1;
			end
		end

		// the count
		if (dat_w) begin
			case (ctl[c][5:4])
				2'b01: begin reload[c][7:0] <= wdata; reload[c][15:8] <= 8'd0; load[c] <= 1'b1; armed[c] <= 1'b1; end
				2'b10: begin reload[c][15:8] <= wdata; reload[c][7:0] <= 8'd0; load[c] <= 1'b1; armed[c] <= 1'b1; end
				default: begin
					if (!wr_hi[c]) begin
						reload[c][7:0] <= wdata;
						wr_hi[c] <= 1'b1;
						if (mode == 3'd0) begin out[c] <= 1'b0; running[c] <= 1'b0; end   // mode 0 stops on the LSB
					end
					else begin
						reload[c][15:8] <= wdata;
						wr_hi[c] <= 1'b0;
						load[c]  <= 1'b1;
						armed[c] <= 1'b1;
					end
				end
			endcase
			if (mode == 3'd0) out[c] <= 1'b0;
		end

		// reads
		if (dat_r) begin
			if (st_latched[c]) begin
				rq[c] <= status[c];
				st_latched[c] <= 1'b0;
			end
			else begin
				case (ctl[c][5:4])
					2'b01: begin rq[c] <= latched[c] ? latch[c][7:0] : cnt[c][7:0]; latched[c] <= 1'b0; end
					2'b10: begin rq[c] <= latched[c] ? latch[c][15:8] : cnt[c][15:8]; latched[c] <= 1'b0; end
					default: begin
						rq[c] <= rd_hi[c] ? (latched[c] ? latch[c][15:8] : cnt[c][15:8])
						                  : (latched[c] ? latch[c][7:0] : cnt[c][7:0]);
						if (rd_hi[c]) latched[c] <= 1'b0;
						rd_hi[c] <= ~rd_hi[c];
					end
				endcase
			end
		end

		// counting, at 1.19 MHz
		if (tick) begin
			if (load[c] && (mode != 3'd1 && mode != 3'd5 || g_rise)) begin
				// a new count: modes 0, 2, 3, 4 take it at once (2 and 3 at the end of
				// the current period when already running: simplified to at once); 1 and 5 on the gate's rise
				cnt[c]     <= rl;
				load[c]    <= 1'b0;
				running[c] <= 1'b1;
				if (mode == 3'd1) out[c] <= 1'b0;
			end
			else if (running[c]) begin
				case (mode)
					3'd0, 3'd4: if (g) begin
						cnt[c] <= cnt[c] - 16'd1;
						if (cnt[c] == 16'd1) out[c] <= mode == 3'd0;     // 0: rises and stays; 4: a strobe
						else if (mode == 3'd4) out[c] <= 1'b1;
					end
					3'd1, 3'd5: begin
						if (g_rise) begin cnt[c] <= rl; out[c] <= mode == 3'd5; end
						else begin
							cnt[c] <= cnt[c] - 16'd1;
							if (cnt[c] == 16'd1) out[c] <= mode == 3'd1;
							else if (mode == 3'd5) out[c] <= 1'b1;
						end
					end
					3'd2: if (g) begin
						if (cnt[c] == 16'd2) begin cnt[c] <= cnt[c] - 16'd1; out[c] <= 1'b0; end
						else if (cnt[c] == 16'd1) begin cnt[c] <= rl; out[c] <= 1'b1; end
						else cnt[c] <= cnt[c] - 16'd1;
					end
					else out[c] <= 1'b1;
					3'd3: if (g) begin
						// counts down by two, the output toggling each half period (an odd count
						// is taken as the even one below it)
						if (cnt[c] <= 16'd2 && cnt[c] != 16'd0) begin
							cnt[c] <= {rl[15:1], 1'b0};
							out[c] <= ~out[c];
						end
						else cnt[c] <= cnt[c] - 16'd2;
					end
					else out[c] <= 1'b1;
					default: ;
				endcase
			end
		end

		if (reset) begin
			ctl[c] <= 6'b110110; out[c] <= 1'b1; latched[c] <= 1'b0; st_latched[c] <= 1'b0;
			rd_hi[c] <= 1'b0; wr_hi[c] <= 1'b0; armed[c] <= 1'b0; load[c] <= 1'b0; running[c] <= 1'b0;
			cnt[c] <= '0; reload[c] <= '0;
		end
	end
end
endgenerate

// port 61
always_ff @(posedge clk) begin
	if (tick && out[1] && cnt[1] == 16'd1) refresh <= ~refresh;
	if (sel & p61) begin
		if (we) p61_r <= wdata[1:0];
		else    rq61  <= {2'b00, out[2], refresh, 2'b00, p61_r};
	end
	if (sel & ~we) rsrc <= p61 ? 2'd3 : a;
	if (reset) begin p61_r <= 2'b00; refresh <= 1'b0; end
end

assign rdata = rsrc == 2'd3 ? rq61 : rq[rsrc];
assign irq0 = out[0];
assign spk  = out[2] & p61_r[1];

endmodule
