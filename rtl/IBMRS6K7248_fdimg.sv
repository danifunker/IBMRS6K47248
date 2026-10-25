//============================================================================
//
//  IBMRS6K7248 - the floppy image: hps_io's block device 4 (the OSD's
//  Floppy, an SC entry) as sectors for the floppy controller
//
//  The controller (IBMRS6K7248_fdc, in the CPU's clock, clk_c) asks for a
//  sector by toggling sec_req with sec_we and sec_lba; a read lands in the
//  in buffer (its byte at buf_a, a clock later buf_q), a write takes the out
//  buffer (written at buf_a while buf_we); sec_ack toggles when it is done.
//  The image's presence, read-only flag and size come over as quasi-static
//  levels, a mount as a pulse (the disk change line).
//
//  Reads come a track at a time: a sector not in the track held is fetched
//  with its whole track (or, on a 2.88 MB disk, the 18-sector half of it) in
//  one request of hps_io, and the track's other sectors are answered from
//  the buffer at once. One request a sector cost the Main's turnaround each
//  time: a cylinder's read (36 sectors) outlasted the firmware's timeout, and
//  the rest of it never reached memory (SMS's ENGLISH.6XE with 20 sectors
//  of zeros). A write goes to the image at once and drops the track held, as
//  does a mount.
//
//  Two clocks: the SD side in hps_io's (clk_s), the buffers dual-clock
//  RAMs with one writer each.
//
//============================================================================

module IBMRS6K7248_fdimg
(
	input  logic        clk_s,
	input  logic        clk_c,

	// hps_io's block device 4 (512-byte blocks, 8-bit buffer)
	input  logic        img_mounted,
	input  logic        img_readonly,
	input  logic [63:0] img_size,
	output logic [31:0] sd_lba,
	output logic [5:0]  sd_blk_cnt,
	output logic        sd_rd,
	output logic        sd_wr,
	input  logic        sd_ack,
	input  logic [13:0] sd_buff_addr,
	input  logic [7:0]  sd_buff_dout,
	input  logic        sd_buff_wr,
	output logic [7:0]  sd_buff_din,

	// the controller's side, in clk_c
	output logic        img_in,
	output logic        img_ro,
	output logic [12:0] img_blocks,
	output logic        mounted,          // a pulse
	input  logic        sec_req,
	input  logic        sec_we,
	input  logic [12:0] sec_lba,
	output logic        sec_ack,
	input  logic [8:0]  buf_a,
	output logic [7:0]  buf_q,
	input  logic        buf_we,
	input  logic [7:0]  buf_d
);

// ---- the buffers ---------------------------------------------------------------------------
logic [7:0] b_in  [16384];                // the SD side writes (a track: sector k at k x 512), the controller reads
logic [7:0] b_out [512];                  // the controller writes, the SD side reads (a write)
logic       s_rd_on;
logic [4:0] s_slot;                       // the sector asked for: its place in the track held
logic [4:0] c_slot;                       // ... in the controller's clock, taken with the answer
always_ff @(posedge clk_s) begin
	if (s_rd_on && sd_ack && sd_buff_wr) b_in[sd_buff_addr] <= sd_buff_dout;
	sd_buff_din <= b_out[sd_buff_addr[8:0]];
end
always_ff @(posedge clk_c) begin
	if (buf_we) b_out[buf_a] <= buf_d;
	buf_q <= b_in[{c_slot, buf_a}];
end

// ---- the image -----------------------------------------------------------------------------
logic        s_in = 1'b0, s_ro = 1'b0, s_mnt_t = 1'b0;
logic [12:0] s_blocks = 13'd0;
always_ff @(posedge clk_s) if (img_mounted) begin
	s_in     <= img_size != 64'd0;
	s_ro     <= img_readonly;
	s_blocks <= img_size[63:22] != 42'd0 ? 13'h1FFF : img_size[21:9];
	s_mnt_t  <= ~s_mnt_t;
end
logic [2:0] c_mnt;
always_ff @(posedge clk_c) begin
	img_in     <= s_in;
	img_ro     <= s_ro;
	img_blocks <= s_blocks;
	c_mnt      <= {c_mnt[1:0], s_mnt_t};
	mounted    <= c_mnt[2] != c_mnt[1];
end
// sectors a track (as the controller has them, IBMRS6K7248_fdc), and a request's: the track, or half of a 36-sector one
// (registered: the image's size holds still while a sector is asked for)
logic [5:0] spt;
logic [4:0] grp;
always_ff @(posedge clk_s) begin
	spt <= s_blocks >= 13'd5760 ? 6'd36 : s_blocks >= 13'd2880 ? 6'd18 : s_blocks >= 13'd2400 ? 6'd15 : 6'd9;
	grp <= spt == 6'd36 ? 5'd18 : spt[4:0];
end

// ---- a sector ---------------------------------------------------------------------------------
typedef enum logic [2:0] {S_IDLE, S_DIV, S_GRP, S_LOOK, S_REQ, S_XFER} sst_t;
sst_t        st = S_IDLE;
logic [2:0]  req_s;
logic        seen = 1'b0;
logic        ack_t = 1'b0;
logic        ack_q;
logic        t_ok = 1'b0;                 // a track is held: its first sector's LBA t_lba
logic [12:0] t_lba;
logic [12:0] q_lba;                       // the sector asked for
logic [12:0] d_rem;                       // the division: q_lba by spt
logic [3:0]  d_n;
logic [12:0] dd;
always_comb dd = {d_rem[11:0], q_lba[d_n]};    // (a shift-subtract step, q_lba's bit d_n brought down)
logic [12:0] g_lba;                       // the track (half) the sector is in: its first LBA
always_ff @(posedge clk_s) begin
	req_s <= {req_s[1:0], sec_req};
	ack_q <= sd_ack;
	case (st)
		S_IDLE: if (req_s[2] != seen) begin
			seen    <= req_s[2];
			q_lba   <= sec_lba;
			if (sec_we) begin                                        // a write: its sector alone, the track dropped
				t_ok    <= 1'b0;
				sd_lba  <= {19'd0, sec_lba};
				sd_blk_cnt <= 6'd0;
				s_rd_on <= 1'b0;
				st      <= S_REQ;
			end
			else begin
				d_rem <= 13'd0;
				d_n   <= 4'd12;
				st    <= S_DIV;
			end
		end
		S_DIV: begin                                                 // q_lba mod spt, a bit a clock
			d_rem <= dd >= {7'd0, spt} ? dd - {7'd0, spt} : dd;
			d_n   <= d_n - 4'd1;
			if (d_n == 4'd0) st <= S_GRP;
		end
		S_GRP: begin                                                 // the track's first LBA (+ 18 for a 36-sector track's second half)
			if (spt == 6'd36 && d_rem >= 13'd18) begin g_lba <= q_lba - d_rem + 13'd18; s_slot <= 5'(d_rem - 13'd18); end
			else                                 begin g_lba <= q_lba - d_rem;          s_slot <= 5'(d_rem); end
			st <= S_LOOK;
		end
		S_LOOK: begin
			if (t_ok && t_lba == g_lba) begin ack_t <= ~ack_t; st <= S_IDLE; end   // held: at once
			else begin
				t_ok       <= 1'b0;
				t_lba      <= g_lba;
				sd_lba     <= {19'd0, g_lba};
				sd_blk_cnt <= 6'(grp - 5'd1);
				s_rd_on    <= 1'b1;
				st         <= S_REQ;
			end
		end
		S_REQ: begin
			if (s_rd_on) sd_rd <= 1'b1; else sd_wr <= 1'b1;
			if (sd_ack) begin sd_rd <= 1'b0; sd_wr <= 1'b0; st <= S_XFER; end
		end
		default: if (ack_q && !sd_ack) begin                         // S_XFER: hps_io is done
			if (s_rd_on) t_ok <= 1'b1;
			if (!s_rd_on) s_slot <= 5'd0;
			ack_t <= ~ack_t;
			st    <= S_IDLE;
		end
	endcase
	if (img_mounted) t_ok <= 1'b0;                                   // another image (or the same, changed)
end
logic [1:0] ack_c;
always_ff @(posedge clk_c) begin
	ack_c   <= {ack_c[0], ack_t};
	sec_ack <= ack_c[1];
	if (ack_c[1] != ack_c[0]) c_slot <= s_slot;                       // (steady since before the toggle)
end

endmodule
