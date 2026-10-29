//============================================================================
//
//  IBMRS6K7248 - the S3 Vision864's picture side, in the video clock (the
//  memory clock): its VRAM in DDR3, the dot clock, the CRTC, the scan-out
//  (M4 phase 1c; docs/s3_design.md 4.5, 4.6)
//
//  Derived from MacPPC7300_video (its DDR3 front end, its line buffers and
//  its dot-clock accumulator; MacPPC7300_MiSTer 21ba191), Swatch's timing
//  replaced by the VGA CRTC's, RaDACal's colour table by the S3's palette,
//  Control's cursor by the S3's.
//
//  The VRAM (2 MB) is DDR3 at DDR_BASE, through the framework's DDRAM port.
//  Two users, the scan-out first:
//
//    - the scan-out: during each line, the next line: the hardware cursor's
//      16 bytes of that line (when the cursor is on it), then its pixels, in
//      bursts of up to 32 words, into one of two line buffers (4 KB each:
//      800 pixels at 32 bits, 1024 at 24, 1152 at 16, 2048 at 8; each
//      split in even and odd words, so that a pixel across two words, at
//      24 bits, comes out whole);
//    - the CPU's and the graphics engine's words (IBMRS6K7248_s3's VRAM
//      port, through their clock crossing): one beat with byte enables.
//
//  A VRAM byte at address a sits in DDR3 word a >> 3, lane a & 7; the port's
//  words have the lowest address in bits 31-24 (the PowerPC's order: the
//  MPC105 keeps bytes at their addresses).
//
//  The timing: the VGA CRTC in pixels (the registers decoded in
//  IBMRS6K7248_s3, scaled there by the depth), the pixel clock the SDAC's
//  PLL (14.31818 MHz x (M + 2) / ((N[4:0] + 2) x 2^post), post from the
//  register side) as a clock enable of the video clock by phase
//  accumulation. Packed pixels (the S3's enhanced mode) of 8, 16, 24 or 32
//  bits (depth), little-endian; line y starts at start + y x pitch. At 8
//  bits the pixel mask and the palette (6 bits a component, widened); at
//  15, 16, 24 and 32 the SDAC's direct colour (5-5-5, 5-6-5, 8-8-8, 8-8-8
//  in the low 24 bits; each widened by its top bits), not through the
//  palette. The cursor: 64 x
//  64, each line 16 bytes of four groups of an AND word and an XOR word
//  (MSB first); in Windows mode 00 the background colour, 01 the
//  foreground, 10 the screen, 11 the screen inverted; in X11 mode (CR55 bit
//  4) 0x the screen, 10 the background, 11 the foreground; the colours at
//  8 bits palette indexes (CR0E, CR0F), deeper pixel values (the CR4A and
//  CR4B stacks).
//
//  The VGA's text mode (txt, from IBMRS6K7248_s3): character k of a row is
//  the VRAM word (8 bytes) at the row's start + 8k, its character byte 0
//  and its attribute byte 1 (planes 0 and 1, odd/even); a row of characters
//  is CR09 + 1 lines; each line fetches its row's characters as the packed
//  modes fetch pixels, and each character's line of dots comes from the
//  font's copy (font_addr / font_q, plane 2 as written); 8 or 9 dots (the
//  ninth repeats the eighth for C0-DF with AR10 bit 2), the foreground the
//  attribute's low nibble, the background its high (bit 7 the blink with
//  AR10 bit 3), the cursor's lines (CR0A-CR0B) at its address (CR0E-CR0F),
//  then the attribute controller's palette (AR00-0F, AR10 bit 7 and AR14)
//  and the DAC's. Two stages more than the packed pixels' (the font, the
//  attribute palette). Not here: double scanning, panning, split screen,
//  the second character set.
//
//============================================================================

module IBMRS6K7248_s3video
#(
	parameter int unsigned CLKV_HZ  = 100_000_000,
	parameter logic [28:0] DDR_BASE = 29'h0600_0000     // byte 3000_0000, in 64-bit words
)
(
	input  logic         clk,             // the video clock: the memory clock
	input  logic         reset,

	// the CPU's and the engine's VRAM words, from their clock crossing (the CPU port's protocol)
	input  logic         c_req,
	input  logic         c_we,
	input  logic [20:2]  c_addr,          // VRAM byte address
	input  logic [3:0]   c_be,            // be[3] the lowest address
	input  logic [31:0]  c_wdata,
	output logic         c_ack,
	output logic [31:0]  c_rdata,

	// DDR3, the framework's DDRAM port
	input  logic         ddr_busy,
	output logic [7:0]   ddr_burstcnt,
	output logic [28:0]  ddr_addr,
	input  logic [63:0]  ddr_dout,
	input  logic         ddr_dout_ready,
	output logic         ddr_rd,
	output logic [63:0]  ddr_din,
	output logic [7:0]   ddr_be,
	output logic         ddr_we,

	// the S3's registers (quasi-static: they change between frames), from IBMRS6K7248_s3
	input  logic [11:0]  h_total,         // pixels
	input  logic [11:0]  h_disp,
	input  logic [11:0]  h_ss,            // horizontal sync start, pixels
	input  logic [11:0]  h_sl,            // ... its length
	input  logic [2:0]   depth,           // 0 8 bits a pixel, 1 15 (5-5-5), 2 16 (5-6-5), 3 32 (8-8-8), 4 24 (8-8-8)
	input  logic [10:0]  v_total,         // lines
	input  logic [10:0]  v_disp,
	input  logic [10:0]  v_ss,
	input  logic [4:0]   v_sl,
	input  logic [20:0]  start,           // the first line's first byte
	input  logic [11:0]  pitch,           // bytes a line
	input  logic         screen_on,       // SR1 bit 5 clear and the attribute controller's PAS set
	input  logic [7:0]   pix_mask,
	input  logic [6:0]   pll_m,           // the selected clock's PLL
	input  logic [7:0]   pll_n,           // N[4:0]; 7:5 the post-divider's power of 2
	input  logic         cur_on,
	input  logic [10:0]  cur_x,
	input  logic [10:0]  cur_y,
	input  logic [20:10] cur_base,        // the cursor's image, in KB
	input  logic         cur_x11,         // CR55 bit 4: X11 mode
	input  logic [23:0]  cur_fg,          // the colours: palette indexes at 8 bits, else pixel values
	input  logic [23:0]  cur_bg,

	// the palette's read port (IBMRS6K7248_s3, read in this clock): the colour a clock later
	output logic [7:0]   pal_addr,
	input  logic [17:0]  pal_q,

	// the text mode's values (IBMRS6K7248_s3's v_txt, quasi-static), and the font's read port (a clock later)
	input  logic [151:0] txt,
	output logic [12:0]  font_addr,
	input  logic [7:0]   font_q,

	// to the register side: the retrace and the display enable (levels)
	output logic         vretrace,
	output logic         disp_en,

	// the picture
	output logic         ce_pix,
	output logic [7:0]   r,
	output logic [7:0]   g,
	output logic [7:0]   b,
	output logic         hs,
	output logic         vs,
	output logic         hblank,
	output logic         vblank
);

// ---- the text mode's values ------------------------------------------------------------------
logic [151:0] tq;
always_ff @(posedge clk) tq <= txt;
wire         t_on   = tq[151];
wire         t_9    = tq[150];
wire  [4:0]  t_chm1 = tq[149:145];         // the character's lines, less one
wire  [4:0]  t_cs   = tq[144:140];         // the cursor's first line
wire  [4:0]  t_ce   = tq[139:135];         // ... its last
wire         t_coff = tq[134];
wire  [15:0] t_cloc = tq[133:118];         // ... its character address
wire  [7:0]  t_ar10 = tq[117:110];
wire  [3:0]  t_ar14 = tq[109:106];
wire  [9:0]  t_cols = tq[105:96];
wire  [95:0] t_pal  = tq[95:0];

// ---- the dot clock ---------------------------------------------------------------------------
localparam longint unsigned REF = 14_318_180;
logic [39:0] numer, denom, acc;
logic        ce_dot;
wire  [40:0] acc_n = {1'b0, acc} + {1'b0, numer};
always_ff @(posedge clk) begin
	numer  <= (40'(pll_m) + 40'd2) * 40'(REF);
	denom  <= ((40'(pll_n[4:0]) + 40'd2) * 40'(CLKV_HZ)) << pll_n[7:5];
	ce_dot <= 1'b0;
	if (numer >= denom) begin acc <= 40'd0; ce_dot <= 1'b1; end            // at or above the video clock: every clock
	else if (acc_n >= {1'b0, denom}) begin acc <= 40'(acc_n - {1'b0, denom}); ce_dot <= 1'b1; end
	else acc <= acc_n[39:0];
	if (reset) begin acc <= 40'd0; ce_dot <= 1'b0; end
end

// ---- the CRTC -------------------------------------------------------------------------------
logic [11:0] hc;
logic [10:0] vc;
wire  h_end   = hc == h_total - 12'd1;
wire  v_end   = vc == v_total - 11'd1;
wire  h_act   = hc < h_disp;
wire  v_act   = vc < v_disp;
wire  hs_on   = hc >= h_ss && hc < h_ss + h_sl;
wire  vs_on   = vc >= v_ss && vc < v_ss + 11'(v_sl);
always_ff @(posedge clk) begin
	if (ce_dot) begin
		hc <= h_end ? 12'd0 : hc + 12'd1;
		if (h_end) vc <= v_end ? 11'd0 : vc + 11'd1;
	end
	if (reset) begin hc <= 12'd0; vc <= 11'd0; end
end
// a pixel's first byte in its line: x times 1, 2, 3 or 4
function automatic logic [13:0] xbytes(input logic [2:0] d, input logic [11:0] x);
	case (d)
		3'd0:    xbytes = {2'd0, x};
		3'd3:    xbytes = {x, 2'b00};
		3'd4:    xbytes = {1'b0, x, 1'b0} + {2'd0, x};
		default: xbytes = {1'b0, x, 1'b0};
	endcase
endfunction
assign vretrace = vs_on;
assign disp_en  = h_act & v_act;

// the text mode's column and dot (they follow hc), and the frames for the blinking
logic [9:0] tcol;
logic [3:0] tdot;
logic [5:0] frames;
always_ff @(posedge clk) begin
	if (ce_dot) begin
		if (h_end) begin tcol <= 10'd0; tdot <= 4'd0; end
		else if (tdot == (t_9 ? 4'd8 : 4'd7)) begin tdot <= 4'd0; tcol <= tcol + 10'd1; end
		else tdot <= tdot + 4'd1;
		if (h_end && v_end) frames <= frames + 6'd1;
	end
	if (reset) begin tcol <= 10'd0; tdot <= 4'd0; end
end

// the next line's fetch: asked for as the line before it starts (line v_total - 1 fetches line 0)
logic        fetch;
logic [10:0] fetch_y;
always_ff @(posedge clk) begin
	fetch <= 1'b0;
	if (ce_dot && hc == 12'd0) begin
		fetch_y <= v_end ? 11'd0 : vc + 11'd1;
		fetch   <= (v_end || vc + 11'd1 < v_disp);
	end
end

// ---- the line fetch ----------------------------------------------------------------------------
// the cursor: on the fetched line if cur_on and cur_y <= y < cur_y + 64; its row's 16 bytes (two words)
wire  [11:0] c_row  = 12'(fetch_y) - 12'(cur_y);
wire         c_line = cur_on && !c_row[11] && c_row < 12'd64;
// the pixels: h_disp pixels' bytes from start + y x pitch, in 64-bit words (rounded out to whole words);
// in the text mode the line's character row from its start, one word a character
logic [20:0] t_row;                    // the fetched line's row's first byte
logic [4:0]  t_line;                   // ... the line in its row
logic [15:0] t_ma;                     // ... its first character's address
wire         t_new   = fetch_y == 11'd0;
wire         t_wrap  = t_line == t_chm1;
wire  [20:0] t_row_n = t_new ? start : t_wrap ? t_row + 21'(pitch) : t_row;
wire  [15:0] t_ma_n  = t_new ? start[18:3] : t_wrap ? t_ma + 16'(pitch[11:3]) : t_ma;
wire  [4:0]  t_line_n = (t_new || t_wrap) ? 5'd0 : t_line + 5'd1;

typedef enum logic [2:0] {D_IDLE, D_FREAD, D_FWAIT, D_CREAD, D_CWAIT, D_CWRITE} ds_t;
ds_t         ds;
logic        f_pend, f_calc, f_calc2;
logic [20:0] f_line;                   // the line's first byte
logic [20:0] f_addr;                   // the next byte to ask for
logic [11:0] f_left;                   // words still to ask for
logic [11:0] f_put;                    // where the next word goes (up to 512)
logic [2:0]  f_off;                    // the line's first pixel's lane in its first word
logic        f_bank;
logic [7:0]  f_burst, f_due;
logic        f_issue, f_last;
logic        f_cur;                    // the cursor's two words are wanted first
logic        f_curw;                   // the burst being fetched is the cursor's
logic [20:0] f_curad;
wire         f_word = (ds == D_FWAIT) && ddr_dout_ready;
wire  [7:0]  f_next = f_cur ? 8'd2 : (f_left > 12'd32) ? 8'd32 : 8'(f_left);

always_ff @(posedge clk) begin
	f_calc  <= 1'b0;
	f_calc2 <= 1'b0;
	if (fetch) begin
		f_line  <= t_on ? t_row_n : start + 21'(fetch_y) * 21'(pitch);
		f_curad <= {cur_base, 10'd0} + {11'd0, c_row[5:0], 4'd0};
		f_bank  <= fetch_y[0];
		f_cur   <= c_line && !t_on;
		f_calc  <= 1'b1;
		if (t_on) begin t_row <= t_row_n; t_line <= t_line_n; t_ma <= t_ma_n; end
	end
	if (f_calc) begin
		f_addr  <= {f_line[20:3], 3'b000};
		f_off   <= f_line[2:0];
		f_left  <= t_on ? 12'(t_cols) : 12'((xbytes(depth, h_disp) + 14'(f_line[2:0]) + 14'd7) >> 3);
		f_put   <= 12'd0;
		f_calc2 <= 1'b1;
	end
	if (f_calc2) f_pend <= 1'b1;
	else if (f_issue) begin
		if (f_curw) f_cur <= 1'b0;
		else begin
			f_addr <= f_addr + {10'd0, f_burst, 3'b000};
			f_left <= f_left - {4'd0, f_burst};
			if (f_left == {4'd0, f_burst}) f_pend <= 1'b0;
		end
	end
	if (f_word && !f_curw) f_put <= f_put + 12'd1;
	if (reset) begin f_pend <= 1'b0; f_cur <= 1'b0; end
end

// ---- the line buffers: two lines of up to 512 words (4 KB); the cursor's row in registers ----
logic [63:0]  lbuf_e [0:511];          // the even words of both lines, {line, word >> 1}
logic [63:0]  lbuf_o [0:511];          // ... the odd
logic [63:0]  lbe_q, lbo_q;
logic [8:0]   lbe_ra, lbo_ra;
logic [127:0] cur0, cur1;
logic         cw;                      // the cursor's word being received
logic         cur_has0, cur_has1;      // the line has the cursor
logic [2:0]   off0, off1;              // each line's first lane
logic [4:0]   tline0, tline1;          // the text mode: each line's line in its row
logic [15:0]  tma0, tma1;              // ... and its row's first character's address
always_ff @(posedge clk) begin
	if (f_word && !f_curw && !f_put[0]) lbuf_e[{f_bank, f_put[8:1]}] <= ddr_dout;
	if (f_word && !f_curw &&  f_put[0]) lbuf_o[{f_bank, f_put[8:1]}] <= ddr_dout;
	lbe_q <= lbuf_e[lbe_ra];
	lbo_q <= lbuf_o[lbo_ra];
	if (f_word && f_curw) begin
		if (!f_bank) begin if (!cw) cur0[63:0] <= ddr_dout; else cur0[127:64] <= ddr_dout; end
		else         begin if (!cw) cur1[63:0] <= ddr_dout; else cur1[127:64] <= ddr_dout; end
		cw <= ~cw;
	end
	if (f_calc) begin
		cw <= 1'b0;
		if (!f_bank) begin cur_has0 <= f_cur; off0 <= f_line[2:0]; tline0 <= t_line; tma0 <= t_ma; end
		else         begin cur_has1 <= f_cur; off1 <= f_line[2:0]; tline1 <= t_line; tma1 <= t_ma; end
	end
end

// ---- DDR3: the scan-out and the CPU in turn -----------------------------------------------------
logic [63:0] c_got;
wire  [63:0] c_word64 = c_addr[2] ? {c_wdata[7:0], c_wdata[15:8], c_wdata[23:16], c_wdata[31:24], 32'h0}
                                  : {32'h0, c_wdata[7:0], c_wdata[15:8], c_wdata[23:16], c_wdata[31:24]};
wire  [7:0]  c_be8    = c_addr[2] ? {c_be[0], c_be[1], c_be[2], c_be[3], 4'h0} : {4'h0, c_be[0], c_be[1], c_be[2], c_be[3]};

always_ff @(posedge clk) begin
	f_issue <= 1'b0;
	c_ack   <= 1'b0;
	case (ds)
		D_IDLE: begin
			ddr_rd <= 1'b0;
			ddr_we <= 1'b0;
			if (f_pend && !f_issue && !f_calc2 && !(c_req && !c_ack && f_last)) begin
				f_last       <= 1'b1;
				f_burst      <= f_next;
				f_curw       <= f_cur;
				ddr_addr     <= DDR_BASE + {11'd0, f_cur ? f_curad[20:3] : f_addr[20:3]};
				ddr_burstcnt <= f_next;
				ddr_rd       <= 1'b1;
				ds           <= D_FREAD;
			end
			else if (c_req && !c_ack) begin
				f_last       <= 1'b0;
				ddr_addr     <= DDR_BASE + {11'd0, c_addr[20:3]};
				ddr_burstcnt <= 8'd1;
				if (c_we) begin
					ddr_we  <= 1'b1;
					ddr_din <= c_word64;
					ddr_be  <= c_be8;
					ds      <= D_CWRITE;
				end
				else begin
					ddr_rd <= 1'b1;
					ds     <= D_CREAD;
				end
			end
		end
		D_FREAD: if (!ddr_busy) begin
			ddr_rd  <= 1'b0;
			f_issue <= 1'b1;
			f_due   <= f_burst;
			ds      <= D_FWAIT;
		end
		D_FWAIT: if (ddr_dout_ready) begin
			f_due <= f_due - 8'd1;
			if (f_due == 8'd1) ds <= D_IDLE;
		end
		D_CREAD: if (!ddr_busy) begin
			ddr_rd <= 1'b0;
			ds     <= D_CWAIT;
		end
		D_CWAIT: if (ddr_dout_ready) begin
			c_got <= ddr_dout;
			c_ack <= 1'b1;
			ds    <= D_IDLE;
		end
		D_CWRITE: if (!ddr_busy) begin
			ddr_we <= 1'b0;
			c_ack  <= 1'b1;
			ds     <= D_IDLE;
		end
		default: ds <= D_IDLE;
	endcase
	if (reset) begin
		ds     <= D_IDLE;
		ddr_rd <= 1'b0;
		ddr_we <= 1'b0;
		f_last <= 1'b0;
	end
end
// a word read back: its bytes in the port's order
assign c_rdata = c_addr[2] ? {c_got[39:32], c_got[47:40], c_got[55:48], c_got[63:56]}
                           : {c_got[7:0], c_got[15:8], c_got[23:16], c_got[31:24]};

// ---- the pixels ----------------------------------------------------------------------------------
// stage 0: the CRTC's pixel: its first byte in the line buffer (the line's first lane added)
// (its word w and the next: the even one of the two at (w + 1) >> 1, the odd at w >> 1)
wire [13:0] p_byte = t_on ? {1'b0, tcol, 3'b000} : xbytes(depth, hc) + {11'd0, vc[0] ? off1 : off0};
wire [8:0]  p_word = p_byte[11:3];
wire [8:0]  p_wn   = p_word + 9'd1;
assign lbe_ra = {vc[0], p_wn[8:1]};
assign lbo_ra = {vc[0], p_word[8:1]};

// stage 1: the word comes out of the line buffer; the pixel goes to the palette, or is the colour
logic        p1_ce, p1_de, p1_hs, p1_vs, p1_hb, p1_vb, p1_ch;
logic [2:0]  p1_lane;
logic        p1_odd;                   // the pixel's first word is the odd bank's
logic [11:0] p1_x;
logic [5:0]  p1_cr;                    // the cursor's row, low bits
wire [127:0] p1_ww = p1_odd ? {lbe_q, lbo_q} : {lbo_q, lbe_q};    // the word and the next
wire  [63:0] p1_w  = 64'(p1_ww >> {p1_lane, 3'b000});
wire  [7:0]  pix8  = p1_w[7:0];
wire  [31:0] pix32 = p1_w[31:0];
// a direct colour's 24 bits (each component widened by its top bits)
function automatic logic [23:0] dcol(input logic [2:0] d, input logic [31:0] p);
	case (d)
		3'd1:    dcol = {p[14:10], p[14:12], p[9:5], p[9:7], p[4:0], p[4:2]};
		3'd2:    dcol = {p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2]};
		default: dcol = p[23:0];
	endcase
endfunction

// the cursor's pixel: (x - cur_x) in its 64, group g = rel >> 4, bit 15 - (rel & 15) of its AND and XOR words
wire [127:0] cur_w = vc[0] ? cur1 : cur0;
wire [11:0]  c_rel = p1_x - 12'(cur_x);
wire         c_in  = p1_ch && !c_rel[11] && c_rel < 12'd64;
wire [3:0]   c_bit = 4'd15 - c_rel[3:0];
wire [15:0]  c_and = {cur_w[8 * (4 * c_rel[5:4])     +: 8], cur_w[8 * (4 * c_rel[5:4] + 1) +: 8]};
wire [15:0]  c_xor = {cur_w[8 * (4 * c_rel[5:4] + 2) +: 8], cur_w[8 * (4 * c_rel[5:4] + 3) +: 8]};
wire         c_a   = c_and[c_bit];
wire         c_x   = c_xor[c_bit];
// a colour of the stacks (the foreground if c_fg), or the screen (inverted if c_inv)
wire         c_col = c_in && (cur_x11 ? c_a : !c_a);
wire         c_fg  = c_x;
wire         c_inv = c_in && !cur_x11 && c_a && c_x;
assign pal_addr = t_on ? t_pal8 & pix_mask : c_col ? (c_fg ? cur_fg[7:0] : cur_bg[7:0]) : pix8 & pix_mask;

// the text mode, from stage 1: the character and attribute out of the word, the font's line asked for (A); the
// dots and the colour's index (B); the attribute palette to the DAC's palette, whose answer stage 2 takes
logic [3:0]  p1_tdot;
logic [9:0]  p1_tcol;
wire  [4:0]  p1_tline = vc[0] ? tline1 : tline0;
wire  [15:0] p1_tma   = vc[0] ? tma1 : tma0;
assign font_addr = {p1_w[7:0], p1_tline};
logic        ta_ce, ta_de, ta_hs, ta_vs, ta_hb, ta_vb, ta_cur;
logic [7:0]  ta_ch, ta_at;
logic [3:0]  ta_dot;
logic        tb_ce, tb_de, tb_hs, tb_vs, tb_hb, tb_vb;
logic [3:0]  tb_idx;
wire         ta_dl  = ta_dot[3] ? (t_ar10[2] && ta_ch[7:5] == 3'b110 && font_q[0]) : font_q[3'd7 - ta_dot[2:0]];
wire         ta_bl  = t_ar10[3] & ta_at[7];                        // a blinking character
wire         ta_fg  = (ta_dl | ta_cur) & ~(ta_bl & frames[5]);
wire  [3:0]  ta_idx = ta_fg ? ta_at[3:0] : {ta_at[7] & ~t_ar10[3], ta_at[6:4]};
wire  [5:0]  tb_v   = t_pal[6 * tb_idx +: 6];
wire  [7:0]  t_pal8 = {t_ar14[3:2], t_ar10[7] ? t_ar14[1:0] : tb_v[5:4], tb_v[3:0]};
always_ff @(posedge clk) begin
	p1_tdot <= tdot;
	p1_tcol <= tcol;
	ta_ce  <= p1_ce;  ta_de <= p1_de;  ta_hs <= p1_hs;  ta_vs <= p1_vs;  ta_hb <= p1_hb;  ta_vb <= p1_vb;
	ta_ch  <= p1_w[7:0];
	ta_at  <= p1_w[15:8];
	ta_dot <= p1_tdot;
	ta_cur <= !t_coff && !frames[4] && p1_tma + 16'(p1_tcol) == t_cloc && p1_tline >= t_cs && p1_tline <= t_ce;
	tb_ce  <= ta_ce;  tb_de <= ta_de;  tb_hs <= ta_hs;  tb_vs <= ta_vs;  tb_hb <= ta_hb;  tb_vb <= ta_vb;
	tb_idx <= ta_idx;
end

// stage 2: the palette answers (or the direct colour, a clock on)
logic        p2_ce, p2_de, p2_hs, p2_vs, p2_hb, p2_vb;
logic        p2_inv;                   // the cursor inverts the screen here
logic        p2_dir;                   // a direct colour
logic [23:0] p2_d;
logic [23:0] p2_c, p2_out;
always_comb begin
	p2_c   = p2_dir ? p2_d : {pal_q[17:12], pal_q[17:16], pal_q[11:6], pal_q[11:10], pal_q[5:0], pal_q[5:4]};
	p2_out = p2_inv ? ~p2_c : p2_c;      // (the stacks' colours came through the palette)
	if (!p2_de || !screen_on) p2_out = 24'h0;
end

always_ff @(posedge clk) begin
	p1_ce   <= ce_dot;
	p1_de   <= h_act & v_act;
	p1_hs   <= hs_on;                      // the framework takes them active high, whatever misc says
	p1_vs   <= vs_on;
	p1_hb   <= ~h_act;
	p1_vb   <= ~v_act;
	p1_lane <= p_byte[2:0];
	p1_odd  <= p_word[0];
	p1_x    <= hc;
	p1_ch   <= vc[0] ? cur_has1 : cur_has0;

	p2_ce  <= t_on ? tb_ce : p1_ce;
	p2_de  <= t_on ? tb_de : p1_de;
	p2_hs  <= t_on ? tb_hs : p1_hs;
	p2_vs  <= t_on ? tb_vs : p1_vs;
	p2_hb  <= t_on ? tb_hb : p1_hb;
	p2_vb  <= t_on ? tb_vb : p1_vb;
	p2_inv <= c_inv && !t_on;
	p2_dir <= depth != 3'd0 && !t_on;
	p2_d   <= dcol(depth, c_col ? {8'd0, c_fg ? cur_fg : cur_bg} : pix32);

	{r, g, b} <= p2_out;
	ce_pix    <= p2_ce;
	hs        <= p2_hs;
	vs        <= p2_vs;
	hblank    <= p2_hb;
	vblank    <= p2_vb;
end

endmodule
