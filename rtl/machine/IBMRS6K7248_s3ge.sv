//============================================================================
//
//  IBMRS6K7248 - the S3 Vision864's graphics engine (the 8514's), phase 2
//
//  The 8514 drawing engine as the 864 has it, at 8, 16 and 32 bits a pixel
//  (CR50 bits 5:4; docs/s3_design.md 1.9, 4.7; the command semantics from
//  MAME's ibm8514a.cpp and 86Box's vid_s3.c):
//
//    - CMD 2000, lines: Bresenham (ERR_TERM, the axial step in DESTY_AXSTP,
//      the diagonal in DESTX_DIASTP, MAJ_AXIS_PCNT + 1 pixels, INC_X, INC_Y,
//      YMAJAXIS) or, with DIR TYP (bit 3), radial (MAJ_AXIS_PCNT steps in
//      the direction in bits 7:5, 45 degrees each, counter-clockwise);
//    - short-stroke vectors: each byte written to SHORT_STROKE (9EE8), the
//      high byte first unless BYTSEQ: a radial vector of bits 3:0 steps in
//      the direction in bits 7:5, drawn if bit 4, with the flags of the last
//      command written (a NOP, CMD 0000);
//    - CMD 4000, rectangles; C000, BitBLTs (source CUR_X/CUR_Y, destination
//      DESTX/DESTY); E000, pattern fills (an 8 x 8 source at CUR_X/CUR_Y
//      repeated over the destination); in any direction;
//    - the 16 mixes with the four sources (background colour, foreground
//      colour, CPU data, display memory); PIX_CNTL: the foreground mix
//      always, CPU data selecting the mix (mono expansion, MSB first, with
//      across-plane mode, CMD bit 1), or display memory selecting it (the
//      source pixel and RD_MASK equal to RD_MASK);
//    - PIX_TRANS writes on an 8-, 16- or 32-bit bus (CMD bits 10:9) with
//      BYTSEQ (clear: the highest byte first, E2E9 on a 16-bit bus, which the
//      firmware's putbitmap relies on; set: E2E8 first), each row a new
//      transfer; a pixel of 2 or 4 bytes takes the next bytes in that order,
//      the first its low byte (so a pixel a transfer is the transfer's value
//      with BYTSEQ, and a big-endian CPU's store of it without), across
//      transfers if the bus is narrower; image reads (WAIT YES without
//      WRTDATA: the destination's pixels packed into PIX_TRANS reads the same
//      way, GP_STAT bit 8 while one waits; the bus at least a pixel wide);
//    - the colour registers (BKGD, FRGD, WRT_MASK, RD_MASK, COLOR_CMP) 32
//      bits: a 16-bit write sets the low half, or at 32 bits a pixel with
//      MULT_MISC bit 4 (RSF) the high half; each write toggles RSF (the
//      864's: two writes, low then high);
//    - colour compare (MULT_MISC bits 8:7: 10 writes only a source unequal
//      to COLOR_CMP, 11 only an equal one: the firmware's transparent
//      bitmaps), the write mask, the scissors, DRAW YES (clear: the position
//      moves, nothing is drawn), the last pixel off for lines and vectors;
//    - the position after a command: a line or vectors leave CUR_X/CUR_Y at
//      their end, a rectangle at its first x and the row after its last.
//
//  One pixel at a time over the VRAM port (32-bit words; a pixel of n bytes
//  at an address a multiple of n, its low byte the lowest address): a mix
//  that needs the destination, or a write mask not all ones, reads it
//  first. There is
//  no FIFO: while a command runs the S3's port holds the bus for any
//  engine register write, and PIX_TRANS data waits for the engine to take
//  it (pt_valid / pt_ready) or to have it (rd_valid / rd_take); GP_STAT
//  shows the FIFO empty and the engine busy (bit 9) until it is done.
//
//  Not drawn: polygon fills (the 8514's CMD 6000; the 864 has none), mono
//  image reads (PIX_CNTL's pack bit). 24 bits a pixel packed has no engine
//  mode on the 864 (CR50 bits 5:4 = 10 is taken as 8): drivers draw it at 8
//  bits, three bytes a pixel.
//
//============================================================================

module IBMRS6K7248_s3ge
(
	input  logic        clk,
	input  logic        reset,

	// register writes: an 8514 register (xxE8 by xx >> 2, 0x20-0x2F) and a byte of it
	input  logic        r_we,
	input  logic [5:0]  r_idx,
	input  logic        r_hi,          // the high byte (xxE9): a command or MULTIFUNC takes effect with it
	input  logic [7:0]  r_data,
	input  logic        r_abort,       // 42E8 bits 15:14 = 10: reset the engine

	// PIX_TRANS writes: a transfer as the bus carried it, little-endian (E2E8 in bits 7:0, E2EB in 31:24)
	input  logic        pt_valid,
	input  logic [31:0] pt_data,
	output logic        pt_ready,
	// ... and reads (an image read): the transfer waiting, the same order; rd_take a read took it
	output logic        bus32,         // a command runs on a 32-bit bus (its transfer may come as E2E8, then E2EA)
	output logic        rd_mode,       // an image read runs: PIX_TRANS reads wait for rd_valid
	output logic        rd_valid,
	output logic [31:0] rd_data,
	input  logic        rd_take,

	output logic        busy,
	input  logic [11:0] pitch,         // bytes a row
	input  logic [1:0]  psz,           // bytes a pixel: 0 one, 1 two, 2 four

	// VRAM (shared with the CPU's frame buffer access in IBMRS6K7248_s3)
	output logic        v_req,
	output logic        v_we,
	output logic [20:2] v_addr,
	output logic [3:0]  v_be,
	output logic [31:0] v_wdata,
	input  logic        v_ack,
	input  logic [31:0] v_rdata
);

// ---- registers ----------------------------------------------------------------------------
logic [15:0] cur_y, cur_x, dest_y, dest_x, maj, err_t;
logic [15:0] cmd_w;                   // the last command written (short strokes take its flags)
logic [31:0] bkgd, frgd, wrt_mask, rd_mask, color_cmp;
logic [7:0]  bkgd_mix, frgd_mix;
logic [11:0] min_axis, sc_t, sc_l, sc_b, sc_r, pix_cntl, mult_misc;
logic [7:0]  lo [64];                 // each register's low byte, until its high byte comes
// the position a command leaves (from the engine below)
logic        upd;
logic [11:0] upd_x, upd_y;

always_ff @(posedge clk) begin
	if (upd) begin cur_x <= {4'd0, upd_x}; cur_y <= {4'd0, upd_y}; end
	if (r_we & ~r_hi) lo[r_idx] <= r_data;
	if (r_we & r_hi) begin
		case (r_idx)
			6'h20: cur_y  <= {r_data, lo[r_idx]};
			6'h21: cur_x  <= {r_data, lo[r_idx]};
			6'h22: dest_y <= {r_data, lo[r_idx]};
			6'h23: dest_x <= {r_data, lo[r_idx]};
			6'h24: err_t  <= {r_data, lo[r_idx]};
			6'h25: maj    <= {r_data, lo[r_idx]};
			6'h26: cmd_w  <= {r_data, lo[r_idx]};
			6'h28: if (hi_half) bkgd[31:16] <= {r_data, lo[r_idx]};      else bkgd[15:0] <= {r_data, lo[r_idx]};
			6'h29: if (hi_half) frgd[31:16] <= {r_data, lo[r_idx]};      else frgd[15:0] <= {r_data, lo[r_idx]};
			6'h2A: if (hi_half) wrt_mask[31:16] <= {r_data, lo[r_idx]};  else wrt_mask[15:0] <= {r_data, lo[r_idx]};
			6'h2B: if (hi_half) rd_mask[31:16] <= {r_data, lo[r_idx]};   else rd_mask[15:0] <= {r_data, lo[r_idx]};
			6'h2C: if (hi_half) color_cmp[31:16] <= {r_data, lo[r_idx]}; else color_cmp[15:0] <= {r_data, lo[r_idx]};
			6'h2D: bkgd_mix  <= lo[r_idx];
			6'h2E: frgd_mix  <= lo[r_idx];
			6'h2F: case (r_data[7:4])               // MULTIFUNC: the index in 15:12
				4'h0: min_axis  <= {r_data[3:0], lo[r_idx]};
				4'h1: sc_t      <= {r_data[3:0], lo[r_idx]};
				4'h2: sc_l      <= {r_data[3:0], lo[r_idx]};
				4'h3: sc_b      <= {r_data[3:0], lo[r_idx]};
				4'h4: sc_r      <= {r_data[3:0], lo[r_idx]};
				4'hA: pix_cntl  <= {r_data[3:0], lo[r_idx]};
				4'hE: mult_misc <= {r_data[3:0], lo[r_idx]};
				default: ;
			endcase
			default: ;
		endcase
		// a colour register's write toggles RSF
		if (r_idx >= 6'h28 && r_idx <= 6'h2C) mult_misc[4] <= ~mult_misc[4];
	end
	// (the single-byte registers also take a write of their low byte alone)
	if (r_we & ~r_hi) begin
		case (r_idx)
			6'h28: if (hi_half) bkgd[23:16] <= r_data;      else bkgd[7:0] <= r_data;
			6'h29: if (hi_half) frgd[23:16] <= r_data;      else frgd[7:0] <= r_data;
			6'h2A: if (hi_half) wrt_mask[23:16] <= r_data;  else wrt_mask[7:0] <= r_data;
			6'h2B: if (hi_half) rd_mask[23:16] <= r_data;   else rd_mask[7:0] <= r_data;
			6'h2C: if (hi_half) color_cmp[23:16] <= r_data; else color_cmp[7:0] <= r_data;
			6'h2D: bkgd_mix  <= r_data;
			6'h2E: frgd_mix  <= r_data;
			default: ;
		endcase
	end
	if (reset) begin
		wrt_mask <= 32'hFFFF_FFFF; rd_mask <= 32'hFFFF_FFFF; pix_cntl <= 12'h0; mult_misc <= 12'h0; cmd_w <= 16'h0;
		sc_t <= 12'h0; sc_l <= 12'h0; sc_b <= 12'hFFF; sc_r <= 12'hFFF;
	end
end
// a colour register's write goes to its high half at 32 bits a pixel with RSF
wire hi_half   = psz == 2'd2 && mult_misc[4];
wire start_cmd = r_we & r_hi & (r_idx == 6'h26) & ~busy;    // 9AE9: a command
wire start_ssv = r_we & r_hi & (r_idx == 6'h27) & ~busy;    // 9EE9: two short-stroke vectors

// ---- the command --------------------------------------------------------------------------
typedef enum logic [4:0] {G_IDLE, G_SSV, G_PIX, G_DATA, G_MSRC, G_MSRC_W, G_SRC_RD, G_SRC_W, G_DST_RD, G_DST_W,
                          G_RDPACK, G_RDOUT, G_WR, G_WR_W, G_NEXT, G_END} gst_t;
typedef enum logic [2:0] {K_RECT, K_BLT, K_PAT, K_LINE, K_VEC} kind_t;
gst_t        g;
kind_t       kind;
logic [15:0] c;                       // the command's flags
logic        ssv;                     // vectors from SHORT_STROKE: more may follow
logic [15:0] ssv_q;                   // ... the next vector's byte in 15:8
logic [1:0]  ssv_n;                   // ... bytes left
logic [11:0] x, y, sx, sy;            // the destination and the source pixel
logic [11:0] n_x, n_y;                // pixels left in the row (a line's or vector's steps), rows left
logic [11:0] w0;                      // the row's width
logic [11:0] x0, sx0, sy0;            // the row's first x; the source's (BitBLT) or pattern's origin
logic [2:0]  px, py;                  // a pattern fill's place in its 8 x 8
logic [2:0]  vdir;                    // a vector's direction
logic        vdraw;                   // DRAW YES (a vector's bit 4)
logic [15:0] err;                     // a line's running error term
logic [31:0] dbuf;                    // CPU data being used, the next bit or byte at the top
logic [5:0]  dbits;                   // ... bits (mono) or bytes x 8 (colour) left in it
logic [31:0] rbuf;                    // an image read's pixels so far, the latest at the bottom
logic [2:0]  rcnt;                    // ... how many
logic [31:0] src, dst;                // pixels (their size's low bits)
logic        use_fg;

wire        pcdata   = c[8];
wire        wrt      = c[0];                     // WRTDATA: clear, nothing is written (with WAIT YES: an image read)
wire        rd_cmd   = pcdata & ~wrt;
wire        inc_x    = c[5];
wire        inc_y    = c[7];
wire        ymaj     = c[6];
wire        lpo      = c[2];
wire [1:0]  bus      = c[10:9];                  // 0 8 bits, 1 16, 2 32
wire        bytseq   = c[12];
wire [2:0]  bus_n    = bus == 2'd0 ? 3'd1 : bus == 2'd1 ? 3'd2 : 3'd4;   // bytes a transfer
wire [2:0]  ps       = psz == 2'd0 ? 3'd1 : psz == 2'd1 ? 3'd2 : 3'd4;   // bytes a pixel
wire [31:0] pmask    = psz == 2'd0 ? 32'h0000_00FF : psz == 2'd1 ? 32'h0000_FFFF : 32'hFFFF_FFFF;
wire        mono_cpu = pix_cntl[7:6] == 2'b10 && c[1];    // CPU data picks the mix (across-plane: a bit a pixel)
wire        mono_mem = pix_cntl[7:6] == 2'b11;            // display memory picks it
wire        sources  = kind == K_BLT || kind == K_PAT;     // the source pixel is (sx, sy), else the destination's
// the mix: the foreground mix unless the mono bit is 0
wire  [7:0] mixr     = use_fg ? frgd_mix : bkgd_mix;
wire  [3:0] fn       = mixr[3:0];
wire  [1:0] srcsel   = mixr[6:5];
// functions that do not read the destination: 1 (0), 2 (1), 4 (~S), 7 (S)
wire        need_dst = !(fn == 4'h1 || fn == 4'h2 || fn == 4'h4 || fn == 4'h7) || (wrt_mask & pmask) != pmask;
// the pixels' addresses
wire [20:0] d_off    = 21'(y) * 21'(pitch) + (21'(x) << psz);
wire [20:0] s_off    = 21'(sy) * 21'(pitch) + (21'(sx) << psz);
wire [20:0] m_off    = sources ? s_off : d_off;          // the display-memory source
// clipped by the scissors
wire        in_clip  = x >= sc_l && x <= sc_r && y >= sc_t && y <= sc_b;
// a line's or vector's last pixel with the last pixel off
wire        lpo_skip = (kind == K_LINE || kind == K_VEC) && lpo && n_x == 12'd0;
// colour compare: 10 writes a source unequal to COLOR_CMP, 11 an equal one
wire        cc_pass  = !mult_misc[8] || (mult_misc[7] ? (src & pmask) == (color_cmp & pmask) : (src & pmask) != (color_cmp & pmask));

function automatic logic [31:0] mix(input logic [3:0] f, input logic [31:0] s, input logic [31:0] d);
	case (f)
		4'h0: mix = ~d;          4'h1: mix = 32'h0;       4'h2: mix = '1;          4'h3: mix = d;
		4'h4: mix = ~s;          4'h5: mix = s ^ d;       4'h6: mix = ~(s ^ d);    4'h7: mix = s;
		4'h8: mix = ~(s & d);    4'h9: mix = ~s | d;      4'hA: mix = s | ~d;      4'hB: mix = s | d;
		4'hC: mix = s & d;       4'hD: mix = s & ~d;      4'hE: mix = ~s & d;      default: mix = ~(s | d);
	endcase
endfunction

// a line's steps and error term: 14 bits, signed
function automatic logic [15:0] sx14(input logic [15:0] v);
	sx14 = {{2{v[13]}}, v[13:0]};
endfunction

// a transfer's bytes in the order they are used, the first at the top: the highest address first,
// or with BYTSEQ the lowest; on an 8-bit bus the byte at E2E8
wire [31:0] pt_ord = bus == 2'd0 ? {pt_data[7:0], 24'd0} :
                     bus == 2'd1 ? (bytseq ? {pt_data[7:0], pt_data[15:8], 16'd0} : {pt_data[15:0], 16'd0}) :
                                   (bytseq ? {pt_data[7:0], pt_data[15:8], pt_data[23:16], pt_data[31:24]} : pt_data);
// a pixel's bytes in order (the low byte first, at the top) and back
function automatic logic [31:0] bswap(input logic [31:0] v);
	bswap = {v[7:0], v[15:8], v[23:16], v[31:24]};
endfunction
// the next CPU data for this pixel: mono a bit (MSB first), colour its size's bytes (the first its low byte)
wire [31:0] cpu_pix   = bswap(dbuf) & pmask;
wire        cpu_bit   = dbuf[31];
wire        need_data = pcdata & wrt & (mono_cpu ? dbits == 6'd0 : dbits < {ps, 3'b000});
// an image read's transfer: its pixels' bytes (the first the oldest) put where the same order of writes
// would have taken them from (rcnt bytes in rbuf, the newest at the bottom; dst not yet in it)
wire [31:0] r_new = psz == 2'd0 ? {rbuf[23:0], dst[7:0]} : psz == 2'd1 ? {rbuf[15:0], dst[7:0], dst[15:8]} : bswap(dst);
wire [3:0]  r_n   = {1'b0, rcnt} + {1'b0, ps};                                       // bytes with this pixel
wire [31:0] r_seq = r_new << (6'd8 * (6'(bus_n) - 6'(r_n)));                          // the first at the top of bus_n bytes
wire [31:0] r_out = bus == 2'd0 ? {24'd0, r_seq[7:0]} :
                    bus == 2'd1 ? (bytseq ? {16'd0, r_seq[7:0], r_seq[15:8]} : {16'd0, r_seq[15:0]}) :
                                  (bytseq ? {r_seq[7:0], r_seq[15:8], r_seq[23:16], r_seq[31:24]} : r_seq);

assign busy     = g != G_IDLE;
assign pt_ready = g == G_DATA;
assign rd_mode  = busy & rd_cmd;
assign bus32    = busy & (bus == 2'd2);
assign rd_valid = g == G_RDOUT;

wire [31:0] result = mix(fn, src, dst);
wire [31:0] wpix   = (result & wrt_mask) | (dst & ~wrt_mask);
wire [1:0]  lane   = d_off[1:0];
// a pixel at lane l of a VRAM word (the word's lowest address in bits 31:24)
function automatic logic [31:0] vpix(input logic [31:0] w, input logic [1:0] l, input logic [31:0] m);
	vpix = bswap(w << (6'd8 * l)) & m;
endfunction

// a step of a vector in direction d (45 degrees each, counter-clockwise from +x; y grows down)
function automatic logic [11:0] vstep_x(input logic [11:0] v, input logic [2:0] d);
	case (d)
		3'd0, 3'd1, 3'd7: vstep_x = v + 12'd1;
		3'd3, 3'd4, 3'd5: vstep_x = v - 12'd1;
		default:          vstep_x = v;
	endcase
endfunction
function automatic logic [11:0] vstep_y(input logic [11:0] v, input logic [2:0] d);
	case (d)
		3'd1, 3'd2, 3'd3: vstep_y = v - 12'd1;
		3'd5, 3'd6, 3'd7: vstep_y = v + 12'd1;
		default:          vstep_y = v;
	endcase
endfunction

always_ff @(posedge clk) begin
	upd <= 1'b0;
	case (g)
		G_IDLE: begin
			if (start_cmd) begin
				c     <= {r_data, lo[6'h26]};
				ssv   <= 1'b0;
				err   <= sx14(err_t);
				dbits <= 6'd0;
				rcnt  <= 3'd0;
				vdraw <= lo[6'h26][4];
				w0    <= maj[11:0];
				n_x   <= maj[11:0];
				n_y   <= min_axis;
				x     <= cur_x[11:0];
				y     <= cur_y[11:0];
				x0    <= cur_x[11:0];
				sx    <= cur_x[11:0];
				sy    <= cur_y[11:0];
				sx0   <= cur_x[11:0];
				sy0   <= cur_y[11:0];
				case (r_data[7:5])
					3'b001: begin                                    // a line
						kind <= lo[6'h26][3] ? K_VEC : K_LINE;
						vdir <= lo[6'h26][7:5];
						n_y  <= 12'd0;
						g    <= G_PIX;
					end
					3'b010: begin kind <= K_RECT; g <= G_PIX; end
					3'b110, 3'b111: begin                            // a BitBLT, a pattern fill: to DESTX/DESTY
						kind <= r_data[5] ? K_PAT : K_BLT;
						x    <= dest_x[11:0];
						y    <= dest_y[11:0];
						x0   <= dest_x[11:0];
						if (r_data[5]) begin                           // the pattern: from its corner by direction
							px <= lo[6'h26][5] ? 3'd0 : 3'd7;
							py <= lo[6'h26][7] ? 3'd0 : 3'd7;
							sx <= cur_x[11:0] + (lo[6'h26][5] ? 12'd0 : 12'd7);
							sy <= cur_y[11:0] + (lo[6'h26][7] ? 12'd0 : 12'd7);
						end
						g    <= G_PIX;
					end
					default: ;                                       // a NOP (the flags for short strokes), the rest
				endcase
			end
			else if (start_ssv) begin
				c     <= cmd_w;
				ssv   <= 1'b1;
				kind  <= K_VEC;
				ssv_q <= cmd_w[12] ? {lo[6'h27], r_data} : {r_data, lo[6'h27]};
				ssv_n <= 2'd2;
				x     <= cur_x[11:0];
				y     <= cur_y[11:0];
				dbits <= 6'd0;
				g     <= G_SSV;
			end
		end
		G_SSV: begin
			// the next vector: bits 3:0 its steps, 4 drawn, 7:5 its direction
			if (ssv_n == 2'd0) g <= G_END;
			else begin
				n_x   <= {8'd0, ssv_q[11:8]};
				vdraw <= ssv_q[12];
				vdir  <= ssv_q[15:13];
				ssv_q <= {ssv_q[7:0], 8'h00};
				ssv_n <= ssv_n - 2'd1;
				g     <= G_PIX;
			end
		end
		G_PIX: begin
			// CPU data first, if this pixel needs it (not for short strokes)
			if (need_data && !ssv) g <= G_DATA;
			else begin
				use_fg <= mono_cpu ? cpu_bit : 1'b1;
				g      <= mono_mem ? G_MSRC : G_SRC_RD;
			end
		end
		G_DATA: if (pt_valid) begin                      // after what is left of the last (a pixel across transfers)
			dbuf  <= (dbits == 6'd0 ? 32'd0 : dbuf) | (pt_ord >> dbits);
			dbits <= dbits + (bus == 2'd0 ? 6'd8 : bus == 2'd1 ? 6'd16 : 6'd32);
			g     <= G_PIX;
		end
		G_MSRC: begin                                    // display memory picks the mix: read its pixel
			v_req  <= 1'b1;
			v_we   <= 1'b0;
			v_addr <= m_off[20:2];
			g      <= G_MSRC_W;
		end
		G_MSRC_W: if (v_ack) begin
			v_req  <= 1'b0;
			use_fg <= (vpix(v_rdata, m_off[1:0], pmask) & rd_mask) == (rd_mask & pmask);
			g      <= G_SRC_RD;
		end
		G_SRC_RD: begin
			// the source: a colour, CPU data, or display memory
			case (srcsel)
				2'b00: begin src <= bkgd; g <= G_DST_RD; end
				2'b01: begin src <= frgd; g <= G_DST_RD; end
				2'b10: begin src <= cpu_pix; g <= G_DST_RD; end
				default: begin
					v_req  <= 1'b1;
					v_we   <= 1'b0;
					v_addr <= m_off[20:2];
					g      <= G_SRC_W;
				end
			endcase
			// consume the CPU data: mono a bit, colour a pixel
			if (pcdata && wrt && !ssv) begin
				dbits <= mono_cpu ? dbits - 6'd1 : dbits - {ps, 3'b000};
				dbuf  <= mono_cpu ? dbuf << 1 : dbuf << {ps, 3'b000};
			end
		end
		G_SRC_W: if (v_ack) begin
			v_req <= 1'b0;
			src   <= vpix(v_rdata, m_off[1:0], pmask);
			g     <= G_DST_RD;
		end
		G_DST_RD: begin
			if (rd_cmd) begin                            // an image read: every pixel, clipped or not
				v_req  <= 1'b1;
				v_we   <= 1'b0;
				v_addr <= d_off[20:2];
				g      <= G_DST_W;
			end
			else if (!in_clip || !vdraw || !wrt || lpo_skip || !cc_pass) g <= G_NEXT;
			else if (need_dst) begin
				v_req  <= 1'b1;
				v_we   <= 1'b0;
				v_addr <= d_off[20:2];
				g      <= G_DST_W;
			end
			else g <= G_WR;
		end
		G_DST_W: if (v_ack) begin
			v_req <= 1'b0;
			dst   <= vpix(v_rdata, lane, pmask);
			g     <= rd_cmd ? G_RDPACK : G_WR;
		end
		G_RDPACK: begin
			// a transfer is full, or the row ends: the CPU reads it
			rbuf <= r_new;
			if (r_n >= {1'b0, bus_n} || n_x == 12'd0) begin
				rd_data <= r_out;
				g       <= G_RDOUT;
			end
			else begin
				rcnt <= r_n[2:0];
				g    <= G_NEXT;
			end
		end
		G_RDOUT: if (rd_take) begin
			rcnt <= 3'd0;
			g    <= G_NEXT;
		end
		G_WR: begin
			v_req   <= 1'b1;
			v_we    <= 1'b1;
			v_addr  <= d_off[20:2];
			v_be    <= (psz == 2'd0 ? 4'b1000 : psz == 2'd1 ? 4'b1100 : 4'b1111) >> lane;
			v_wdata <= bswap(need_dst ? wpix : result) >> (6'd8 * lane);
			g       <= G_WR_W;
		end
		G_WR_W: if (v_ack) begin
			v_req <= 1'b0;
			g     <= G_NEXT;
		end
		G_NEXT: begin
			case (kind)
				K_LINE:
					// Bresenham: a diagonal step while the error term is not negative, else along the major axis
					if (n_x != 12'd0) begin
						n_x <= n_x - 12'd1;
						if (!err[15]) begin
							x   <= inc_x ? x + 12'd1 : x - 12'd1;
							y   <= inc_y ? y + 12'd1 : y - 12'd1;
							err <= err + sx14(dest_x);
						end
						else begin
							if (ymaj) y <= inc_y ? y + 12'd1 : y - 12'd1;
							else      x <= inc_x ? x + 12'd1 : x - 12'd1;
							err <= err + sx14(dest_y);
						end
						g <= G_PIX;
					end
					else g <= G_END;
				K_VEC:
					if (n_x != 12'd0) begin
						n_x <= n_x - 12'd1;
						x   <= vstep_x(x, vdir);
						y   <= vstep_y(y, vdir);
						g   <= G_PIX;
					end
					else g <= ssv ? G_SSV : G_END;
				default:                                 // rectangles, BitBLTs, pattern fills
					if (n_x != 12'd0) begin
						n_x <= n_x - 12'd1;
						x   <= inc_x ? x + 12'd1 : x - 12'd1;
						if (kind == K_PAT) begin
							px <= inc_x ? px + 3'd1 : px - 3'd1;
							sx <= sx0 + {9'd0, inc_x ? px + 3'd1 : px - 3'd1};
						end
						else sx <= inc_x ? sx + 12'd1 : sx - 12'd1;
						g   <= G_PIX;
					end
					else if (n_y != 12'd0) begin
						n_y   <= n_y - 12'd1;
						n_x   <= w0;
						x     <= x0;
						y     <= inc_y ? y + 12'd1 : y - 12'd1;
						if (kind == K_PAT) begin
							px <= inc_x ? 3'd0 : 3'd7;
							py <= inc_y ? py + 3'd1 : py - 3'd1;
							sx <= sx0 + (inc_x ? 12'd0 : 12'd7);
							sy <= sy0 + {9'd0, inc_y ? py + 3'd1 : py - 3'd1};
						end
						else begin
							sx <= sx0;
							sy <= inc_y ? sy + 12'd1 : sy - 12'd1;
						end
						dbits <= 6'd0;                       // each row starts a new transfer
						g     <= G_PIX;
					end
					else g <= G_END;
			endcase
		end
		default: begin                                   // G_END: the position a command leaves
			if (kind == K_LINE || kind == K_VEC) begin
				upd <= 1'b1; upd_x <= x; upd_y <= y;
			end
			else if (kind == K_RECT) begin
				upd <= 1'b1; upd_x <= x0; upd_y <= inc_y ? y + 12'd1 : y - 12'd1;
			end
			g <= G_IDLE;
		end
	endcase
	if (reset | r_abort) begin
		g     <= G_IDLE;
		v_req <= 1'b0;
	end
end

endmodule
