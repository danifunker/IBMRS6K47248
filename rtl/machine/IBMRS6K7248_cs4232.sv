//============================================================================
//
//  IBMRS6K7248 - the Crystal CS4232 audio controller
//
//  The chip as the firmware finds, configures and moves it (audio_mute,
//  FFF0D9A4; init_4232, SendKey, ConfigDevice, configByDefault), and its
//  Windows Sound System codec playing: the firmware's startup tune
//  (audio_play: DMA channel 1, scatter/gather) and AIX's audio.
//
//  Configuration, at 0279 (write only): two zeros, then the 32-byte
//  Crystal key (96 35 9A CD ... 1A, as the firmware sends it: the first 96
//  after a 00 is taken as its start), then commands until 79:
//    15 n      select logical device n
//    47 hi lo  its I/O base 0 (device 0: the WSS codec, 534)
//    48 hi lo  its I/O base 1 (device 0: the FM synthesiser, 388)
//    42 hi lo  its I/O base 2 (device 0: the Sound Blaster, 220)
//    22 n, 27 n, 2A n, 25 n   interrupt and DMA settings (taken, unused)
//    33 n      activate (1) or deactivate (0)
//    79        leave configuration
//  Only logical device 0 is modelled. It is inactive at reset (the chip
//  with no EEPROM), so its ports float until the firmware places it; the
//  firmware checks that the Sound Blaster appears when activated and
//  disappears when deactivated (init_4232).
//
//  Device 0's ports while active (the Sound Blaster's at base 2 are
//  IBMRS6K7248_sb's):
//    base 0       WSS index: bit 7 INIT (reads clear: ready), 6 MCE, 4:0 the register
//    base 0 + 1   WSS indexed data: the CS4231's 32 registers (QEMU's cs4231a.c
//                 for their reset values): I8 the rate and format, I9 PEN and
//                 PPIO, I10 IEN, I12 MODE2 and the ID (8A), I14/I15 the
//                 playback count, I24 the PI flag, I25 the version (A2, a
//                 CS4232); I6/I7 the DACs' mute and attenuation
//    base 0 + 2   WSS status: bit 0 INT; a write clears it (and PI)
//
//  Playback (PEN, not PPIO): DMA channel 1 (as the firmware's audio_play
//  and the residual data have it) fills a 16-byte FIFO a byte a transfer
//  while it has room; at the rate I8 selects (the CS4231's table of two
//  crystals and eight divisors) a sample frame comes out of it: 8-bit
//  unsigned, mu-law, A-law, 16-bit little-endian (big-endian in mode 2),
//  mono or stereo, through the DAC's mute and attenuation (in steps of 6
//  dB) to the outputs; the playback count counts the frames down, and at its
//  end PI, INT and (with IEN) IRQ 5. An empty FIFO repeats the last frame.
//
//  Capture (CEN, not CPIO; the MiSTer has no audio input): at the same rate
//  a frame of silence in the capture format (I28 in mode 2, else I8) is
//  offered on DMA channel 0, the capture count (I30/I31 in mode 2, else
//  I14/I15) counting the frames down to CI and INT.
//
//  The Sound Blaster, the FM chip, the MPU-401 and the joystick port are
//  their own modules (IBMRS6K7248_sb, the top's OPL, _mpu401, _joy); this one
//  places them (on: device 0 active) and keeps their shared IRQ here.
//
//  The bus: the machine decodes 0279 and the two windows from the bases
//  brought out here; one byte access a cycle, the read value in rdata the
//  cycle after sel.
//
//============================================================================

module IBMRS6K7248_cs4232
(
	input  logic        clk,
	input  logic        reset,

	input  logic        cfg_sel,       // a write to 0279
	input  logic        sel,           // an access to device 0's WSS codec window
	input  logic        we,
	input  logic [3:0]  off,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	output logic        on,            // device 0 active
	output logic [15:4] sb_base,
	output logic [15:2] wss_base,

	// the codec's DMA (channel 1, 8-bit): a request while the FIFO has room; a transfer's byte
	output logic        drq,
	input  logic        dack,          // (dack_ch's transfer done, dack_data its byte)
	input  logic [2:0]  dack_ch,
	input  logic [7:0]  dack_data,
	output logic        irq,           // IRQ 5
	output logic        cap_drq,       // capture: DMA channel 0
	output logic [7:0]  rec_byte,      // ... the capture format's silence

	output logic [15:0] aud_l,         // signed
	output logic [15:0] aud_r
);
parameter int unsigned CLK_HZ = 100_000_000;
localparam logic [2:0] PLAY_CH = 3'd1;

// ---- configuration ----------------------------------------------------------------------
logic [7:0]  prev;
logic [5:0]  keyn;                       // key bytes still to come
logic        cfg;                        // in configuration
logic [7:0]  cmd;
logic [1:0]  argn;                       // arguments still to come
logic [7:0]  arg_hi;
logic [7:0]  ld;
logic [15:0] base0, base2;

always_ff @(posedge clk) begin
	if (cfg_sel) begin
		prev <= wdata;
		if (keyn != 6'd0) begin
			keyn <= keyn - 6'd1;
			if (keyn == 6'd1) cfg <= 1'b1;
		end
		else if (!cfg) begin
			if (prev == 8'h00 && wdata == 8'h96) keyn <= 6'd31;
		end
		else if (argn != 2'd0) begin
			argn <= argn - 2'd1;
			if (argn == 2'd2) arg_hi <= wdata;
			else case (cmd)
				8'h15: ld <= wdata;
				8'h47: if (ld == 8'd0) base0 <= {arg_hi, wdata};
				8'h42: if (ld == 8'd0) base2 <= {arg_hi, wdata};
				8'h33: if (ld == 8'd0) on <= wdata[0];
				default: ;
			endcase
		end
		else begin
			cmd <= wdata;
			case (wdata)
				8'h79:                      cfg  <= 1'b0;
				8'h47, 8'h48, 8'h42:        argn <= 2'd2;
				default:                    argn <= 2'd1;
			endcase
		end
	end
	if (reset) begin
		prev <= 8'hFF; keyn <= 6'd0; cfg <= 1'b0; argn <= 2'd0; ld <= 8'd0;
		on <= 1'b0; base0 <= 16'h0534; base2 <= 16'h0220;
	end
end

assign sb_base  = base2[15:4];
assign wss_base = base0[15:2];

// ---- device 0's WSS codec ---------------------------------------------------------------------
logic [7:0] idx;                          // R0: MCE, TRD, the register
logic [7:0] dr [32];                      // I0-I31
logic       int_st;                       // R2 bit 0
wire        mode2 = dr[12][6];
wire  [4:0] ia    = mode2 ? idx[4:0] : {1'b0, idx[3:0]};

// a register's read value
function automatic logic [7:0] dreg(input logic [4:0] n);
	case (n)
		5'd11:   dreg = 8'h00;                                   // no errors, no autocalibration running
		5'd12:   dreg = {1'b1, dr[12][6], 2'b00, 4'hA};          // MODE2, the codec's ID
		5'd25:   dreg = 8'hA2;                                   // the version: a CS4232
		default: dreg = dr[n];
	endcase
endfunction

// the playback and capture engines' (below): a frame taken (the count steps), the counts' ends
logic       pl_frame, pl_end, cp_end;

always_ff @(posedge clk) begin
	if (sel) begin
		if (we) begin
			case (off[1:0])
				2'd0: idx <= {1'b0, wdata[6:0]};
				2'd1: begin
					if (ia == 5'd12)      dr[12][6] <= wdata[6];
					else if (ia == 5'd24) begin
						dr[24] <= wdata;
						if (dr[24][4] && !wdata[4]) int_st <= 1'b0;     // PI cleared
					end
					else if (ia != 5'd11 && ia != 5'd25) dr[ia] <= wdata;
				end
				2'd2: begin int_st <= 1'b0; dr[24][6:4] <= 3'b000; end  // the status: INT, PI/CI/TI clear
				default: ;
			endcase
		end
		else case (off[1:0])
			2'd0:    rdata <= {1'b0, idx[6:0]};                 // INIT clear: ready
			2'd1:    rdata <= dreg(ia);
			2'd2:    rdata <= {7'd0, int_st};
			default: rdata <= 8'h00;
		endcase
	end
	if (pl_end) begin int_st <= 1'b1; dr[24][4] <= 1'b1; end      // PI
	if (cp_end) begin int_st <= 1'b1; dr[24][5] <= 1'b1; end      // CI
	if (reset) begin
		idx <= 8'h40; int_st <= 1'b0;
		for (int i = 0; i < 32; i++) dr[i] <= 8'h00;
		dr[2] <= 8'h88; dr[3] <= 8'h88; dr[4] <= 8'h88; dr[5] <= 8'h88;
		dr[6] <= 8'h80; dr[7] <= 8'h80;                         // the DACs muted
		dr[9] <= 8'h08; dr[12] <= 8'h8A; dr[18] <= 8'h88; dr[19] <= 8'h88; dr[26] <= 8'hA0;
	end
end
assign irq = int_st & dr[10][1];

// ---- playback ---------------------------------------------------------------------------------
wire        pen   = dr[9][0] & ~dr[9][6] & on;
wire [2:0]  fmt   = mode2 ? dr[8][7:5] : {1'b0, dr[8][6:5]};    // 0 8-bit, 1 mu-law, 2 16-bit LE, 3 A-law, 6 16-bit BE
wire        st    = dr[8][4];
wire        w16   = fmt == 3'd2 || fmt == 3'd6;
wire [2:0]  fbytes = {w16 & st, w16 ^ st, ~(w16 | st)};          // 1, 2 or 4

// the rate: the CS4231's two crystals and eight divisors
function automatic logic [16:0] rate(input logic [3:0] r);
	case (r)
		4'h0: rate = 17'd8000;   4'h2: rate = 17'd16000;  4'h4: rate = 17'd27420;  4'h6: rate = 17'd32000;
		4'h8: rate = 17'd8000;   4'hA: rate = 17'd8000;   4'hC: rate = 17'd48000;  4'hE: rate = 17'd9600;
		4'h1: rate = 17'd5512;   4'h3: rate = 17'd11025;  4'h5: rate = 17'd18900;  4'h7: rate = 17'd22050;
		4'h9: rate = 17'd37800;  4'hB: rate = 17'd44100;  4'hD: rate = 17'd33075;  default: rate = 17'd6615;
	endcase
endfunction
wire [16:0] fs = rate({dr[8][3:1], dr[8][0]});
logic [31:0] ph;
logic        tick;
always_ff @(posedge clk) begin
	tick <= 1'b0;
	if (!pen) ph <= 32'd0;
	else if (ph + {15'd0, fs} >= 32'(CLK_HZ)) begin ph <= ph + {15'd0, fs} - 32'(CLK_HZ); tick <= 1'b1; end
	else ph <= ph + {15'd0, fs};
end

// mu-law and A-law, as G.711 decodes them (to 16 bits)
function automatic logic [15:0] ulaw(input logic [7:0] b);
	logic [7:0]  u;
	logic [15:0] m;
	u = ~b;
	m = ((16'({u[3:0], 3'b000}) + 16'h0084) << u[6:4]) - 16'h0084;
	ulaw = u[7] ? 16'(-(m << 2)) : 16'(m << 2);
endfunction
function automatic logic [15:0] alaw(input logic [7:0] b);
	logic [7:0]  a;
	logic [15:0] m;
	a = b ^ 8'h55;
	if (a[6:4] == 3'd0) m = {8'd0, a[3:0], 4'h8};
	else                m = (16'({a[3:0], 4'h0}) + 16'h0108) << (a[6:4] - 3'd1);
	alaw = a[7] ? 16'(m << 3) : 16'(-(m << 3));
endfunction
function automatic logic [15:0] dec8(input logic [2:0] f, input logic [7:0] b);
	case (f)
		3'd1:    dec8 = ulaw(b);
		3'd3:    dec8 = alaw(b);
		default: dec8 = {~b[7], b[6:0], 8'h00};                  // 8-bit unsigned
	endcase
endfunction
// the DAC's mute and attenuation (I6/I7: bit 7 mute, 5:0 in 1.5 dB steps, here 6 dB at a time)
function automatic logic [15:0] att(input logic [15:0] v, input logic [7:0] c);
	att = c[7] ? 16'd0 : 16'($signed(v) >>> c[5:2]);
endfunction

// the FIFO, filled by DMA
logic [7:0]  fifo [16];
logic [3:0]  f_w, f_r;
logic [4:0]  f_n;
logic [15:0] cnt;                                                // the playback count, frames left
logic        pen_q;
logic [15:0] sl, sr;
assign drq = pen && f_n <= 5'd12;
wire   take = tick && f_n >= {2'b00, fbytes};
always_ff @(posedge clk) begin
	pl_frame <= 1'b0;
	pl_end   <= 1'b0;
	pen_q    <= pen;
	if (dack && dack_ch == PLAY_CH && pen) begin fifo[f_w] <= dack_data; f_w <= f_w + 4'd1; end
	if (take) begin
		// a frame: its bytes from the FIFO's head
		case (fbytes)
			3'd1: begin sl <= dec8(fmt, fifo[f_r]); sr <= dec8(fmt, fifo[f_r]); end
			3'd2: if (w16) begin
				sl <= fmt == 3'd6 ? {fifo[f_r], fifo[4'(f_r + 1)]} : {fifo[4'(f_r + 1)], fifo[f_r]};
				sr <= fmt == 3'd6 ? {fifo[f_r], fifo[4'(f_r + 1)]} : {fifo[4'(f_r + 1)], fifo[f_r]};
			end
			else begin sl <= dec8(fmt, fifo[f_r]); sr <= dec8(fmt, fifo[4'(f_r + 1)]); end
			default: begin
				sl <= fmt == 3'd6 ? {fifo[f_r], fifo[4'(f_r + 1)]} : {fifo[4'(f_r + 1)], fifo[f_r]};
				sr <= fmt == 3'd6 ? {fifo[4'(f_r + 2)], fifo[4'(f_r + 3)]} : {fifo[4'(f_r + 3)], fifo[4'(f_r + 2)]};
			end
		endcase
		f_r <= f_r + 4'(fbytes);
		// the count: at its end PI, and it starts again from the base
		if (cnt == 16'd0) begin pl_end <= 1'b1; cnt <= {dr[14], dr[15]}; end
		else cnt <= cnt - 16'd1;
	end
	f_n <= f_n + ((dack && dack_ch == PLAY_CH && pen) ? 5'd1 : 5'd0) - (take ? {2'b00, fbytes} : 5'd0);
	if (pen && !pen_q) cnt <= {dr[14], dr[15]};
	if (!pen || reset) begin f_w <= 4'd0; f_r <= 4'd0; f_n <= 5'd0; sl <= 16'd0; sr <= 16'd0; end
end
always_ff @(posedge clk) begin
	aud_l <= att(sl, dr[6]);
	aud_r <= att(sr, dr[7]);
end

// ---- capture: silence, a frame at the rate, offered to DMA channel 0 -------------------------------
localparam logic [2:0] CAP_CH = 3'd0;
wire        cen    = dr[9][1] & ~dr[9][7] & on;
wire [7:0]  cfmt_r = mode2 ? dr[28] : dr[8];
wire [2:0]  cfmt   = mode2 ? cfmt_r[7:5] : {1'b0, cfmt_r[6:5]};
wire        cw16   = cfmt == 3'd2 || cfmt == 3'd6;
wire [2:0]  cbytes = {cw16 & cfmt_r[4], cw16 ^ cfmt_r[4], ~(cw16 | cfmt_r[4])};
assign rec_byte = cfmt == 3'd0 ? 8'h80 : cfmt == 3'd1 ? 8'hFF : cfmt == 3'd3 ? 8'hD5 : 8'h00;
logic [31:0] cph;
logic [4:0]  c_pend;                                            // bytes offered, not yet taken
logic [15:0] ccnt;
logic        cen_q, ctick;
assign cap_drq = cen && c_pend != 5'd0;
wire   ctake = dack && dack_ch == CAP_CH && cen && c_pend != 5'd0;
always_ff @(posedge clk) begin
	ctick  <= 1'b0;
	cp_end <= 1'b0;
	cen_q  <= cen;
	if (!cen) cph <= 32'd0;
	else if (cph + {15'd0, fs} >= 32'(CLK_HZ)) begin cph <= cph + {15'd0, fs} - 32'(CLK_HZ); ctick <= 1'b1; end
	else cph <= cph + {15'd0, fs};
	if (ctick) begin
		if (ccnt == 16'd0) begin cp_end <= 1'b1; ccnt <= mode2 ? {dr[30], dr[31]} : {dr[14], dr[15]}; end
		else ccnt <= ccnt - 16'd1;
	end
	c_pend <= (ctick && c_pend <= 5'd12 ? c_pend + {2'b00, cbytes} : c_pend) - (ctake ? 5'd1 : 5'd0);
	if (cen && !cen_q) ccnt <= mode2 ? {dr[30], dr[31]} : {dr[14], dr[15]};
	if (!cen || reset) c_pend <= 5'd0;
end

endmodule
