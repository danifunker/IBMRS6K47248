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
logic [7:0] b_in  [512];                  // the SD side writes (a read), the controller reads
logic [7:0] b_out [512];                  // the controller writes, the SD side reads (a write)
logic       s_rd_on;
always_ff @(posedge clk_s) begin
	if (s_rd_on && sd_ack && sd_buff_wr) b_in[sd_buff_addr[8:0]] <= sd_buff_dout;
	sd_buff_din <= b_out[sd_buff_addr[8:0]];
end
always_ff @(posedge clk_c) begin
	if (buf_we) b_out[buf_a] <= buf_d;
	buf_q <= b_in[buf_a];
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

// ---- a sector ---------------------------------------------------------------------------------
typedef enum logic [1:0] {S_IDLE, S_REQ, S_XFER} sst_t;
sst_t       st = S_IDLE;
logic [2:0] req_s;
logic       seen = 1'b0;
logic       ack_t = 1'b0;
logic       ack_q;
assign sd_blk_cnt = 6'd0;
always_ff @(posedge clk_s) begin
	req_s <= {req_s[1:0], sec_req};
	ack_q <= sd_ack;
	case (st)
		S_IDLE: if (req_s[2] != seen) begin
			seen    <= req_s[2];
			sd_lba  <= {19'd0, sec_lba};
			s_rd_on <= !sec_we;
			st      <= S_REQ;
		end
		S_REQ: begin
			if (s_rd_on) sd_rd <= 1'b1; else sd_wr <= 1'b1;
			if (sd_ack) begin sd_rd <= 1'b0; sd_wr <= 1'b0; st <= S_XFER; end
		end
		default: if (ack_q && !sd_ack) begin ack_t <= ~ack_t; st <= S_IDLE; end
	endcase
end
logic [1:0] ack_c;
always_ff @(posedge clk_c) begin
	ack_c   <= {ack_c[0], ack_t};
	sec_ack <= ack_c[1];
end

endmodule
