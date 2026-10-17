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
//      bursts of up to 32 words, into one of two line buffers;
//    - the CPU's and the graphics engine's words (IBMRS6K7248_s3's VRAM
//      port, through their clock crossing): one beat with byte enables.
//
//  A VRAM byte at address a sits in DDR3 word a >> 3, lane a & 7; the port's
//  words have the lowest address in bits 31-24 (the PowerPC's order: the
//  MPC105 keeps bytes at their addresses).
//
//  The timing: the VGA CRTC in character clocks of 8 dots (the registers in
//  `crtc`, decoded in IBMRS6K7248_s3), the dot clock the SDAC's PLL
//  (14.31818 MHz x (M + 2) / ((N[4:0] + 2) x 2^N[6:5])) as a clock enable of
//  the video clock by phase accumulation. 8 bits a pixel, packed (the S3's
//  enhanced mode: the only one the firmware uses); line y starts at
//  start + y x pitch. Then the pixel mask, the palette (6 bits a component,
//  widened), and the cursor: 64 x 64, each line 16 bytes of four groups of
//  an AND word and an XOR word (MSB first); in Windows mode 00 the
//  background colour (the stack's: black here), 01 the foreground (white
//  here), 10 the screen, 11 the screen inverted.
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
	input  logic [10:0]  h_total,         // dots
	input  logic [10:0]  h_disp,
	input  logic [10:0]  h_ss,            // horizontal sync start, dots
	input  logic [10:0]  h_sl,            // ... its length
	input  logic [10:0]  v_total,         // lines
	input  logic [10:0]  v_disp,
	input  logic [10:0]  v_ss,
	input  logic [3:0]   v_sl,
	input  logic [20:0]  start,           // the first line's first byte
	input  logic [11:0]  pitch,           // bytes a line
	input  logic         screen_on,       // SR1 bit 5 clear and the attribute controller's PAS set
	input  logic [7:0]   pix_mask,
	input  logic [6:0]   pll_m,           // the selected clock's PLL
	input  logic [6:0]   pll_n,
	input  logic         cur_on,
	input  logic [10:0]  cur_x,
	input  logic [10:0]  cur_y,
	input  logic [20:10] cur_base,        // the cursor's image, in KB

	// the palette's read port (IBMRS6K7248_s3, read in this clock): the colour a clock later
	output logic [7:0]   pal_addr,
	input  logic [17:0]  pal_q,

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

// ---- the dot clock ---------------------------------------------------------------------------
localparam longint unsigned REF = 14_318_180;
logic [39:0] numer, denom, acc;
logic        ce_dot;
wire  [40:0] acc_n = {1'b0, acc} + {1'b0, numer};
always_ff @(posedge clk) begin
	numer  <= (40'(pll_m) + 40'd2) * 40'(REF);
	denom  <= ((40'(pll_n[4:0]) + 40'd2) * 40'(CLKV_HZ)) << pll_n[6:5];
	ce_dot <= 1'b0;
	if (numer >= denom) begin acc <= 40'd0; ce_dot <= 1'b1; end            // at or above the video clock: every clock
	else if (acc_n >= {1'b0, denom}) begin acc <= 40'(acc_n - {1'b0, denom}); ce_dot <= 1'b1; end
	else acc <= acc_n[39:0];
	if (reset) begin acc <= 40'd0; ce_dot <= 1'b0; end
end

// ---- the CRTC -------------------------------------------------------------------------------
logic [10:0] hc, vc;
wire  h_end   = hc == h_total - 11'd1;
wire  v_end   = vc == v_total - 11'd1;
wire  h_act   = hc < h_disp;
wire  v_act   = vc < v_disp;
wire  hs_on   = hc >= h_ss && hc < h_ss + h_sl;
wire  vs_on   = vc >= v_ss && vc < v_ss + 11'(v_sl);
always_ff @(posedge clk) begin
	if (ce_dot) begin
		hc <= h_end ? 11'd0 : hc + 11'd1;
		if (h_end) vc <= v_end ? 11'd0 : vc + 11'd1;
	end
	if (reset) begin hc <= 11'd0; vc <= 11'd0; end
end
assign vretrace = vs_on;
assign disp_en  = h_act & v_act;

// the next line's fetch: asked for as the line before it starts (line v_total - 1 fetches line 0)
logic        fetch;
logic [10:0] fetch_y;
always_ff @(posedge clk) begin
	fetch <= 1'b0;
	if (ce_dot && hc == 11'd0) begin
		fetch_y <= v_end ? 11'd0 : vc + 11'd1;
		fetch   <= (v_end || vc + 11'd1 < v_disp);
	end
end

// ---- the line fetch ----------------------------------------------------------------------------
// the cursor: on the fetched line if cur_on and cur_y <= y < cur_y + 64; its row's 16 bytes (two words)
wire  [11:0] c_row  = 12'(fetch_y) - 12'(cur_y);
wire         c_line = cur_on && !c_row[11] && c_row < 12'd64;
// the pixels: h_disp bytes from start + y x pitch, in 64-bit words (rounded out to whole words)

typedef enum logic [2:0] {D_IDLE, D_FREAD, D_FWAIT, D_CREAD, D_CWAIT, D_CWRITE} ds_t;
ds_t         ds;
logic        f_pend, f_calc, f_calc2;
logic [20:0] f_line;                   // the line's first byte
logic [20:0] f_addr;                   // the next byte to ask for
logic [11:0] f_left;                   // words still to ask for
logic [11:0] f_put;                    // where the next word goes
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
		f_line  <= start + 21'(fetch_y) * 21'(pitch);
		f_curad <= {cur_base, 10'd0} + {11'd0, c_row[5:0], 4'd0};
		f_bank  <= fetch_y[0];
		f_cur   <= c_line;
		f_calc  <= 1'b1;
	end
	if (f_calc) begin
		f_addr  <= {f_line[20:3], 3'b000};
		f_off   <= f_line[2:0];
		f_left  <= 12'((12'(h_disp) + 12'(f_line[2:0]) + 12'd7) >> 3);
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

// ---- the line buffers: two lines of up to 256 words (2048 pixels); the cursor's row in registers ----
logic [63:0]  lbuf [0:511];
logic [63:0]  lb_q;
logic [8:0]   lb_ra;
logic [127:0] cur0, cur1;
logic         cw;                      // the cursor's word being received
logic         cur_has0, cur_has1;      // the line has the cursor
logic [2:0]   off0, off1;              // each line's first lane
always_ff @(posedge clk) begin
	if (f_word && !f_curw) lbuf[{f_bank, f_put[7:0]}] <= ddr_dout;
	lb_q <= lbuf[lb_ra];
	if (f_word && f_curw) begin
		if (!f_bank) begin if (!cw) cur0[63:0] <= ddr_dout; else cur0[127:64] <= ddr_dout; end
		else         begin if (!cw) cur1[63:0] <= ddr_dout; else cur1[127:64] <= ddr_dout; end
		cw <= ~cw;
	end
	if (f_calc) begin
		cw <= 1'b0;
		if (!f_bank) begin cur_has0 <= f_cur; off0 <= f_line[2:0]; end
		else         begin cur_has1 <= f_cur; off1 <= f_line[2:0]; end
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
// stage 0: the CRTC's dot: its byte in the line buffer (the line's first lane added)
wire [11:0] p_byte = 12'(hc) + {9'd0, vc[0] ? off1 : off0};
assign lb_ra = {vc[0], p_byte[10:3]};

// stage 1: the word comes out of the line buffer; the pixel goes to the palette
logic        p1_ce, p1_de, p1_hs, p1_vs, p1_hb, p1_vb, p1_ch;
logic [2:0]  p1_lane;
logic [10:0] p1_x;
logic [5:0]  p1_cr;                    // the cursor's row, low bits
wire  [7:0]  pix8 = lb_q[8 * p1_lane +: 8];
assign pal_addr = pix8 & pix_mask;

// the cursor's pixel: (x - cur_x) in its 64, group g = rel >> 4, bit 15 - (rel & 15) of its AND and XOR words
wire [127:0] cur_w = vc[0] ? cur1 : cur0;
wire [11:0]  c_rel = 12'(p1_x) - 12'(cur_x);
wire         c_in  = p1_ch && !c_rel[11] && c_rel < 12'd64;
wire [3:0]   c_bit = 4'd15 - c_rel[3:0];
wire [15:0]  c_and = {cur_w[8 * (4 * c_rel[5:4])     +: 8], cur_w[8 * (4 * c_rel[5:4] + 1) +: 8]};
wire [15:0]  c_xor = {cur_w[8 * (4 * c_rel[5:4] + 2) +: 8], cur_w[8 * (4 * c_rel[5:4] + 3) +: 8]};

// stage 2: the palette answers
logic        p2_ce, p2_de, p2_hs, p2_vs, p2_hb, p2_vb;
logic [1:0]  p2_cur;                   // {in the cursor, AND, XOR}: 0 none
logic        p2_cin;
logic [23:0] p2_c, p2_out;
always_comb begin
	p2_c = {pal_q[17:12], pal_q[17:16], pal_q[11:6], pal_q[11:10], pal_q[5:0], pal_q[5:4]};
	if (!p2_cin)                 p2_out = p2_c;
	else case (p2_cur)
		2'b00:   p2_out = 24'h000000;          // the background stack colour (CR4B: black here)
		2'b01:   p2_out = 24'hFFFFFF;          // the foreground (CR4A: white here)
		2'b10:   p2_out = p2_c;                // the screen
		default: p2_out = ~p2_c;               // the screen inverted
	endcase
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
	p1_x    <= hc;
	p1_ch   <= vc[0] ? cur_has1 : cur_has0;

	p2_ce  <= p1_ce;
	p2_de  <= p1_de;
	p2_hs  <= p1_hs;
	p2_vs  <= p1_vs;
	p2_hb  <= p1_hb;
	p2_vb  <= p1_vb;
	p2_cin <= c_in;
	p2_cur <= {c_and[c_bit], c_xor[c_bit]};

	{r, g, b} <= p2_out;
	ce_pix    <= p2_ce;
	hs        <= p2_hs;
	vs        <= p2_vs;
	hblank    <= p2_hb;
	vblank    <= p2_vb;
end

endmodule
