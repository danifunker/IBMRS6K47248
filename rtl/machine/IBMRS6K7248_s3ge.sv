//============================================================================
//
//  IBMRS6K7248 - the S3 Vision864's graphics engine (the 8514's), phase 1b
//
//  What the firmware's S3 driver draws with (docs/s3_design.md 1.9, 4.7):
//  rectangles (CMD 4000) and BitBLTs (C000) in any direction, the 16 mixes
//  on 8-bit pixels with the four sources (background colour, foreground
//  colour, CPU data through PIX_TRANS, display memory), the PIX_CNTL modes
//  "foreground mix always" and "CPU data selects the mix" (mono expansion,
//  MSB first), PIX_TRANS on an 8-, 16- or 32-bit bus (CMD bits 10:9) with
//  BYTSEQ (with BYTSEQ clear the highest byte is the first, E2E9 on a 16-bit
//  bus: the firmware's putbitmap relies on it; set, E2E8), each row starting
//  a new transfer, the write mask, the scissors, the pitch from the CRTC's
//  offset (CR13, CR51[5:4]). The other commands (lines, short strokes,
//  pattern fills, NOP) end at once: they draw nothing.
//
//  One pixel at a time over the VRAM port (32-bit words): a mix that needs
//  the destination, or a write mask other than FF, reads it first. There is
//  no FIFO: while a command runs the S3's port holds the bus for any
//  engine register write, and PIX_TRANS data waits for the engine to take
//  it (pt_valid / pt_ready); the firmware's own polling (GP_STAT) sees the
//  FIFO empty and the engine busy (bit 9) until it is done.
//
//  Not yet: lines, short-stroke vectors, pattern fills, image reads, colour
//  compare (MULT_MISC bit 8), 16/24/32 bpp, the register updates at the end
//  of a command (the firmware sets every register before each command).
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

	// PIX_TRANS: a transfer as the bus carried it, little-endian (E2E8 in bits 7:0, E2EB in 31:24)
	input  logic        pt_valid,
	input  logic [31:0] pt_data,
	output logic        pt_ready,

	output logic        busy,
	input  logic [11:0] pitch,         // bytes a row

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
logic [15:0] cur_y, cur_x, dest_y, dest_x, maj, cmd;
logic [7:0]  bkgd, frgd, wrt_mask;
logic [7:0]  bkgd_mix, frgd_mix;
logic [11:0] min_axis, sc_t, sc_l, sc_b, sc_r, pix_cntl, mult_misc;
logic [7:0]  lo [64];                 // each register's low byte, until its high byte comes

always_ff @(posedge clk) begin
	if (r_we & ~r_hi) lo[r_idx] <= r_data;
	if (r_we & r_hi) begin
		case (r_idx)
			6'h20: cur_y  <= {r_data, lo[r_idx]};
			6'h21: cur_x  <= {r_data, lo[r_idx]};
			6'h22: dest_y <= {r_data, lo[r_idx]};
			6'h23: dest_x <= {r_data, lo[r_idx]};
			6'h25: maj    <= {r_data, lo[r_idx]};
			6'h28: bkgd   <= lo[r_idx];
			6'h29: frgd   <= lo[r_idx];
			6'h2A: wrt_mask <= lo[r_idx];
			6'h2D: bkgd_mix <= lo[r_idx];
			6'h2E: frgd_mix <= lo[r_idx];
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
	end
	// (the single-byte registers also take a write of their low byte alone)
	if (r_we & ~r_hi) begin
		case (r_idx)
			6'h28: bkgd <= r_data;
			6'h29: frgd <= r_data;
			6'h2A: wrt_mask <= r_data;
			6'h2D: bkgd_mix <= r_data;
			6'h2E: frgd_mix <= r_data;
			default: ;
		endcase
	end
	if (reset) begin
		wrt_mask <= 8'hFF; pix_cntl <= 12'h0; mult_misc <= 12'h0;
		sc_t <= 12'h0; sc_l <= 12'h0; sc_b <= 12'hFFF; sc_r <= 12'hFFF;
	end
end
wire start = r_we & r_hi & (r_idx == 6'h26) & ~busy;   // 9AE9: the command

// ---- the command --------------------------------------------------------------------------
typedef enum logic [3:0] {G_IDLE, G_PIX, G_DATA, G_SRC_RD, G_SRC_W, G_DST_RD, G_DST_W, G_WR, G_WR_W, G_NEXT} gst_t;
gst_t        g;
logic [15:0] c;                       // the command running
logic [11:0] x, y, sx, sy;            // the destination and (BitBLT) the source pixel
logic [11:0] n_x, n_y;                // pixels left in the row, rows left
logic [11:0] w0;                      // the row's width
logic [11:0] x0, sx0;                 // the row's first x
logic [31:0] dbuf;                    // CPU data being used, the next bit or byte at the top
logic [5:0]  dbits;                   // ... bits (mono) or bytes x 8 (colour) left in it
logic [7:0]  src, dst;

wire is_blt   = c[15:13] == 3'b110;
wire pcdata   = c[8];
wire inc_x    = c[5];
wire inc_y    = c[7];
wire [1:0] bus = c[10:9];                        // 0 8 bits, 1 16, 2 32
wire bytseq   = c[12];
wire mono     = pix_cntl[7:6] == 2'b10;          // CPU data picks the mix
// the mix: the foreground mix unless mono expansion's bit is 0
logic        use_fg;
wire  [7:0]  mixr     = use_fg ? frgd_mix : bkgd_mix;
wire  [3:0]  fn       = mixr[3:0];
wire  [1:0]  srcsel   = mixr[6:5];
// functions that do not read the destination: 1 (0), 2 (1), 4 (~S), 7 (S)
wire         need_dst = !(fn == 4'h1 || fn == 4'h2 || fn == 4'h4 || fn == 4'h7) || wrt_mask != 8'hFF;
// the pixel's address
wire  [20:0] d_off    = 21'(y) * 21'(pitch) + 21'(x);
wire  [20:0] s_off    = 21'(sy) * 21'(pitch) + 21'(sx);
// clipped by the scissors
wire         in_clip   = x >= sc_l && x <= sc_r && y >= sc_t && y <= sc_b;

function automatic logic [7:0] mix(input logic [3:0] f, input logic [7:0] s, input logic [7:0] d);
	case (f)
		4'h0: mix = ~d;          4'h1: mix = 8'h00;       4'h2: mix = 8'hFF;       4'h3: mix = d;
		4'h4: mix = ~s;          4'h5: mix = s ^ d;       4'h6: mix = ~(s ^ d);    4'h7: mix = s;
		4'h8: mix = ~(s & d);    4'h9: mix = ~s | d;      4'hA: mix = s | ~d;      4'hB: mix = s | d;
		4'hC: mix = s & d;       4'hD: mix = s & ~d;      4'hE: mix = ~s & d;      default: mix = ~(s | d);
	endcase
endfunction

// a transfer's bytes in the order they are used, the first at the top: the highest address first,
// or with BYTSEQ the lowest; on an 8-bit bus the byte at E2E8
wire [31:0] pt_ord = bus == 2'd0 ? {pt_data[7:0], 24'd0} :
                     bus == 2'd1 ? (bytseq ? {pt_data[7:0], pt_data[15:8], 16'd0} : {pt_data[15:0], 16'd0}) :
                                   (bytseq ? {pt_data[7:0], pt_data[15:8], pt_data[23:16], pt_data[31:24]} : pt_data);
// the next CPU data for this pixel: mono a bit (MSB first), colour a byte
wire  [7:0] cpu_byte = dbuf[31:24];
wire        cpu_bit  = dbuf[31];
wire        need_data = pcdata & (dbits == 6'd0);
// the commands drawn: rectangles (010) and BitBLTs (110)
function automatic logic drawn(input logic [7:0] hi);
	drawn = hi[7:5] == 3'b010 || hi[7:5] == 3'b110;
endfunction

assign busy     = g != G_IDLE;
assign pt_ready = g == G_DATA;

wire [7:0] result = mix(fn, src, dst);
wire [7:0] wbyte  = (result & wrt_mask) | (dst & ~wrt_mask);
wire [1:0] lane   = d_off[1:0];

always_ff @(posedge clk) begin
	case (g)
		G_IDLE: if (start && drawn(r_data)) begin
			c     <= {r_data, lo[6'h26]};
			x     <= is_blt_cmd(r_data) ? dest_x[11:0] : cur_x[11:0];
			y     <= is_blt_cmd(r_data) ? dest_y[11:0] : cur_y[11:0];
			x0    <= is_blt_cmd(r_data) ? dest_x[11:0] : cur_x[11:0];
			sx    <= cur_x[11:0];
			sy    <= cur_y[11:0];
			sx0   <= cur_x[11:0];
			w0    <= maj[11:0];
			n_x   <= maj[11:0];
			n_y   <= min_axis;
			dbits <= 6'd0;
			g     <= G_PIX;
		end
		G_PIX: begin
			// CPU data first, if this pixel needs it
			if (need_data) g <= G_DATA;
			else begin
				use_fg <= mono ? cpu_bit : 1'b1;
				g      <= G_SRC_RD;
			end
		end
		G_DATA: if (pt_valid) begin
			dbuf  <= pt_ord;
			dbits <= bus == 2'd0 ? 6'd8 : bus == 2'd1 ? 6'd16 : 6'd32;
			g     <= G_PIX;
		end
		G_SRC_RD: begin
			// the source: a colour, CPU data, or display memory
			case (srcsel)
				2'b00: begin src <= bkgd; g <= G_DST_RD; end
				2'b01: begin src <= frgd; g <= G_DST_RD; end
				2'b10: begin src <= cpu_byte; g <= G_DST_RD; end
				default: begin
					v_req  <= 1'b1;
					v_we   <= 1'b0;
					v_addr <= s_off[20:2];
					g      <= G_SRC_W;
				end
			endcase
			// consume the CPU data: mono a bit, colour a byte
			if (pcdata) begin
				dbits <= mono ? dbits - 6'd1 : dbits - 6'd8;
				dbuf  <= mono ? dbuf << 1 : dbuf << 8;
			end
		end
		G_SRC_W: if (v_ack) begin
			v_req <= 1'b0;
			src   <= v_rdata[31 - 8 * s_off[1:0] -: 8];
			g     <= G_DST_RD;
		end
		G_DST_RD: begin
			if (!in_clip) g <= G_NEXT;
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
			dst   <= v_rdata[31 - 8 * lane -: 8];
			g     <= G_WR;
		end
		G_WR: begin
			v_req   <= 1'b1;
			v_we    <= 1'b1;
			v_addr  <= d_off[20:2];
			v_be    <= 4'b1000 >> lane;
			v_wdata <= {4{need_dst ? wbyte : result}};
			g       <= G_WR_W;
		end
		G_WR_W: if (v_ack) begin
			v_req <= 1'b0;
			g     <= G_NEXT;
		end
		default: begin                                   // G_NEXT
			if (n_x != 12'd0) begin
				n_x <= n_x - 12'd1;
				x   <= inc_x ? x + 12'd1 : x - 12'd1;
				sx  <= inc_x ? sx + 12'd1 : sx - 12'd1;
				g   <= G_PIX;
			end
			else if (n_y != 12'd0) begin
				n_y   <= n_y - 12'd1;
				n_x   <= w0;
				x     <= x0;
				sx    <= sx0;
				y     <= inc_y ? y + 12'd1 : y - 12'd1;
				sy    <= inc_y ? sy + 12'd1 : sy - 12'd1;
				dbits <= 6'd0;                              // each row starts a new transfer
				g     <= G_PIX;
			end
			else g <= G_IDLE;
		end
	endcase
	if (reset | r_abort) begin
		g     <= G_IDLE;
		v_req <= 1'b0;
	end
end

function automatic logic is_blt_cmd(input logic [7:0] hi);
	is_blt_cmd = hi[7:5] == 3'b110;
endfunction

endmodule
