//============================================================================
//
//  IBMRS6K7248 - the CS4232's Sound Blaster Pro: its DSP (version 3.02) and
//  mixer, playing 8-bit sound
//
//  At the CS4232's Sound Blaster base (220, as the firmware places it):
//    + 4 / + 5  the mixer's index and data (the CT1345's registers kept: 04
//               voice, 22 master, 26 FM, 0E bit 1 stereo; 00 resets them)
//    + 6        the DSP's reset: 1 then 0 queues AA
//    + A        the DSP's read data
//    + C        write: a command or its parameters; read: ready (bit 7 clear)
//    + E        read: bit 7 a byte waits at + A; the read acknowledges the IRQ
//  (+ 0-3 and + 8-9, the FM chip's, are the machine's to route elsewhere.)
//
//  The DSP's commands: 10 (one sample out), 14 / 1C (8-bit DMA out, single
//  cycle / auto-initialise), 91 / 90 (high-speed, the same), 24 / 2C / 99 /
//  98 (8-bit DMA in: silence, 80), 20 (one sample in: 80), 40 (the time
//  constant: the rate 1,000,000 / (256 - tc), stereo frames at half), 41 (a
//  rate in Hz, as the SB16's), 48 (the block size), D0 / D4 (pause,
//  continue), DA (leave auto-initialise), D1 / D3 / D8 (the speaker on, off,
//  its state), E0 (the identification: the byte inverted), E1 (the
//  version: 3.02), E4 / E8 (the test register), F2 (an IRQ now); the rest
//  are taken and ignored. A block's last byte moved by DMA raises the IRQ
//  (IRQ 5, as the WSS's); a single-cycle block then stops, an auto-
//  initialise one starts again.
//
//  Playback: DMA channel 1 (the codec's, which does not run at the same
//  time) fills a 16-byte FIFO; at the rate a frame (one byte, two in stereo)
//  comes out, 8-bit unsigned, through the speaker switch and the mixer's
//  master and voice volumes.
//
//============================================================================

module IBMRS6K7248_sb
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,           // an access to base + off (off 4, 5, 6, A, C, E)
	input  logic        we,
	input  logic [3:0]  off,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	// DMA channel 1
	output logic        drq,
	output logic        rec,           // recording: a write transfer wants 80
	input  logic        dack,
	input  logic [2:0]  dack_ch,
	input  logic [7:0]  dack_data,
	output logic        irq,

	output logic [15:0] aud_l,         // signed
	output logic [15:0] aud_r,
	output logic [7:0]  fm_vol         // the mixer's FM volume (26): left in 7:4, right in 3:0
);

localparam logic [2:0] CH = 3'd1;

// ---- the mixer -------------------------------------------------------------------------------
logic [7:0] mix_idx;
logic [7:0] mix [256];
assign fm_vol = mix[8'h26];
wire stereo = mix[8'h0E][1];

// ---- the DSP -------------------------------------------------------------------------------
logic        rst_hi;
logic [7:0]  out_q [4];                  // bytes waiting at + A
logic [1:0]  out_r, out_w;
logic [2:0]  out_n;
logic [7:0]  cmd;
logic [1:0]  need;                       // parameter bytes still to come
logic [7:0]  p0;
logic [7:0]  test;
logic        spk;                        // the speaker (D1 / D3)
logic [7:0]  tc;                         // the time constant
logic [16:0] hz;                         // a rate set in Hz (41), else 0
logic [15:0] blk;                        // the block size, less 1
logic [7:0]  direct;                     // the last sample out by 10
logic        irq8;
// DMA
logic        dma_on, dma_auto, dma_in, dma_pause, dma_last;
logic [15:0] dma_left;                   // bytes left in the block, less 1
logic [16:0] rate;
// the time constant's rate, 1,000,000 / (256 - tc), by a divider a bit a clock (when tc changes)
logic [19:0] dq, dr;
logic [8:0]  dd;
logic [4:0]  dn;
logic [7:0]  tc_q;
logic [16:0] tc_rate;
always_ff @(posedge clk) begin
	tc_q <= tc;
	if (tc != tc_q) begin dq <= 20'd1_000_000; dr <= 20'd0; dd <= 9'd256 - {1'b0, tc}; dn <= 5'd20; end
	else if (dn != 5'd0) begin
		// restoring division: the next bit of the quotient into dq's bottom
		if ({dr[18:0], dq[19]} >= {11'd0, dd}) begin dr <= {dr[18:0], dq[19]} - {11'd0, dd}; dq <= {dq[18:0], 1'b1}; end
		else begin dr <= {dr[18:0], dq[19]}; dq <= {dq[18:0], 1'b0}; end
		dn <= dn - 5'd1;
		if (dn == 5'd1) tc_rate <= 17'(({dr[18:0], dq[19]} >= {11'd0, dd}) ? {dq[18:0], 1'b1} : {dq[18:0], 1'b0});
	end
end
assign rate = hz != 17'd0 ? hz : tc_rate;

task automatic put(input logic [7:0] b);
	out_q[out_w] <= b; out_w <= out_w + 2'd1; out_n <= out_n + 3'd1;
endtask

// the FIFO (playback) and the frame clock
logic [7:0]  fifo [16];
logic [3:0]  f_w, f_r;
logic [4:0]  f_n;
logic [31:0] ph;
logic        tick;
logic [7:0]  sl, sr;
wire  [1:0]  fbytes = stereo ? 2'd2 : 2'd1;
wire         xfer   = dack && dack_ch == CH && dma_on && !dma_pause;
wire         take   = tick && !dma_in && f_n >= {3'd0, fbytes};
assign drq = dma_on && !dma_pause && (dma_in || f_n <= 5'd12);
assign rec = dma_on && dma_in;

always_ff @(posedge clk) begin
	tick <= 1'b0;
	if (!(dma_on && !dma_pause)) ph <= 32'd0;
	else if (ph + {15'd0, rate} >= 32'(CLK_HZ)) begin ph <= ph + {15'd0, rate} - 32'(CLK_HZ); tick <= 1'b1; end
	else ph <= ph + {15'd0, rate};
end

always_ff @(posedge clk) begin
	if (sel) begin
		if (we) begin
			case (off)
				4'h4: mix_idx <= wdata;
				4'h5: begin
					mix[mix_idx] <= wdata;
					if (mix_idx == 8'h00) begin                    // the mixer reset
						mix[8'h04] <= 8'h99; mix[8'h22] <= 8'h99; mix[8'h26] <= 8'h99; mix[8'h0E] <= 8'h00;
					end
				end
				4'h6: begin
					if (wdata[0]) rst_hi <= 1'b1;
					else if (rst_hi) begin
						// the DSP reset: AA waits, the DMA stops, the speaker off
						rst_hi <= 1'b0;
						out_r <= 2'd0; out_w <= 2'd1; out_n <= 3'd1; out_q[0] <= 8'hAA;
						need <= 2'd0; dma_on <= 1'b0; spk <= 1'b0; irq8 <= 1'b0; hz <= 17'd0;
					end
				end
				4'hC: begin
					if (need != 2'd0) begin
						// a parameter
						need <= need - 2'd1;
						if (need == 2'd2) p0 <= wdata;
						else case (cmd)
							8'h10: direct <= wdata;
							8'h40: begin tc <= wdata; hz <= 17'd0; end
							8'hE0: put(~wdata);
							8'hE4: test <= wdata;
							8'h14, 8'h24: begin                    // single-cycle DMA out / in
								dma_left <= {wdata, p0}; dma_on <= 1'b1; dma_auto <= 1'b0;
								dma_in <= cmd == 8'h24; dma_pause <= 1'b0; dma_last <= 1'b0;
							end
							8'h48: blk <= {wdata, p0};
							8'h41, 8'h42: hz <= {1'b0, p0, wdata};
							default: ;
						endcase
					end
					else begin
						cmd <= wdata;
						case (wdata)
							8'h10, 8'h40, 8'hE0, 8'hE4: need <= 2'd1;
							8'h14, 8'h24, 8'h48, 8'h41, 8'h42: need <= 2'd2;
							8'h1C, 8'h90, 8'h2C, 8'h98: begin           // auto-initialise DMA out / in
								dma_left <= blk; dma_on <= 1'b1; dma_auto <= 1'b1;
								dma_in <= wdata == 8'h2C || wdata == 8'h98; dma_pause <= 1'b0; dma_last <= 1'b0;
							end
							8'h91, 8'h99: begin                         // high-speed single-cycle
								dma_left <= blk; dma_on <= 1'b1; dma_auto <= 1'b0;
								dma_in <= wdata == 8'h99; dma_pause <= 1'b0; dma_last <= 1'b0;
							end
							8'h20: put(8'h80);
							8'hD0: dma_pause <= 1'b1;
							8'hD4: dma_pause <= 1'b0;
							8'hDA: dma_last <= 1'b1;
							8'hD1: spk <= 1'b1;
							8'hD3: spk <= 1'b0;
							8'hD8: put(spk ? 8'hFF : 8'h00);
							8'hE1: begin put(8'h03); out_q[out_w + 2'd1] <= 8'h02; out_w <= out_w + 2'd2; out_n <= out_n + 3'd2; end
							8'hE8: put(test);
							8'hF2: irq8 <= 1'b1;
							default: ;
						endcase
					end
				end
				default: ;
			endcase
		end
		else begin
			case (off)
				4'h5: rdata <= mix[mix_idx];
				4'hA: begin
					rdata <= out_n != 3'd0 ? out_q[out_r] : 8'hFF;
					if (out_n != 3'd0) begin out_r <= out_r + 2'd1; out_n <= out_n - 3'd1; end
				end
				4'hC: rdata <= 8'h7F;                              // ready to take a byte
				4'hE: begin rdata <= {out_n != 3'd0, 7'h7F}; irq8 <= 1'b0; end
				default: rdata <= 8'hFF;
			endcase
		end
	end

	// a DMA byte moved: the block's count; at its last, the IRQ
	if (xfer) begin
		if (dma_left == 16'd0) begin
			irq8 <= 1'b1;
			if (dma_auto && !dma_last) dma_left <= blk;
			else dma_on <= 1'b0;
		end
		else dma_left <= dma_left - 16'd1;
	end

	if (reset) begin
		rst_hi <= 1'b0; out_n <= 3'd0; out_r <= 2'd0; out_w <= 2'd0; need <= 2'd0; spk <= 1'b0; irq8 <= 1'b0;
		dma_on <= 1'b0; dma_pause <= 1'b0; tc <= 8'h00; hz <= 17'd0; blk <= 16'h07FF; direct <= 8'h80;
		mix_idx <= 8'h00;
		mix[8'h04] <= 8'h99; mix[8'h22] <= 8'h99; mix[8'h26] <= 8'h99; mix[8'h0E] <= 8'h00;
	end
end
assign irq = irq8;

// ---- playback: the FIFO filled by DMA, a frame out at the rate ----------------------------------
always_ff @(posedge clk) begin
	if (xfer && !dma_in) begin fifo[f_w] <= dack_data; f_w <= f_w + 4'd1; end
	if (take) begin
		sl  <= fifo[f_r];
		sr  <= stereo ? fifo[4'(f_r + 1)] : fifo[f_r];
		f_r <= f_r + 4'(fbytes);
	end
	f_n <= f_n + ((xfer && !dma_in) ? 5'd1 : 5'd0) - (take ? {3'd0, fbytes} : 5'd0);
	if (!dma_on) begin f_w <= 4'd0; f_r <= 4'd0; f_n <= 5'd0; sl <= direct; sr <= direct; end
	if (reset) begin sl <= 8'h80; sr <= 8'h80; end
end

// out: unsigned to signed, the speaker switch, the master and voice volumes (4 bits each side, 15 the most)
function automatic logic [15:0] vol(input logic [7:0] s, input logic [3:0] m, input logic [3:0] v);
	logic signed [24:0] x;                                     // (wide enough for the product)
	logic [7:0] g;
	x = 25'($signed({~s[7], s[6:0], 8'h00}));
	g = {4'd0, m} * {4'd0, v};                                  // 0-225
	vol = 16'((x * $signed({1'b0, g})) >>> 8);
endfunction
always_ff @(posedge clk) begin
	aud_l <= spk ? vol(sl, mix[8'h22][7:4], mix[8'h04][7:4]) : 16'd0;
	aud_r <= spk ? vol(sr, mix[8'h22][3:0], mix[8'h04][3:0]) : 16'd0;
end

endmodule
