//============================================================================
//
//  IBMRS6K7248 - the NVRAM and CMOS kept on the SD card
//
//  hps_io's block device 3 (the OSD's "NVRAM file", an SC entry: the Main
//  remembers it and mounts it at every core load) holds nine 512-byte
//  blocks: 0-7 the 4 KB PReP NVRAM, 8 a marker ("IBMRS6K1", bytes 0-7)
//  and the CMOS (bytes 128-255, as the RTC's index 00-7F).
//
//  At a mount the nine blocks come into an image buffer; with the marker
//  there they go into the RTC (the NVRAM, CMOS 0E-7F: the time is the
//  Main's), else the file is new and the RTC's contents are written to it
//  at once. After that, once the CPU has written the NVRAM or the CMOS and
//  then left them alone for about two seconds, the RTC's contents are
//  copied into the buffer and the nine blocks written back.
//
//  Two clocks: the SD side in hps_io's (clk_s), the copy between the
//  buffers and the RTC's maintenance port in the CPU's (clk_c); the buffers
//  dual-clock RAMs between them, requests and answers as toggles.
//
//============================================================================

module IBMRS6K7248_nvsave
#(
	parameter int unsigned QUIET = 200_000_000     // clk_s clocks with no write before a save (2 s at 100 MHz)
)
(
	input  logic        clk_s,
	input  logic        clk_c,

	// hps_io's block device 3 (512-byte blocks, 8-bit buffer)
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

	// the RTC's maintenance port (IBMRS6K7248_rtc), in clk_c
	output logic [12:0] m_addr,
	output logic        m_we,
	output logic [7:0]  m_wdata,
	input  logic [7:0]  m_q,
	input  logic        m_ok,
	input  logic [7:0]  wr_seq
);

localparam logic [63:0] MARKER = "IBMRS6K1";

// ---- the image buffers, 9 x 512 bytes each: one the SD side fills and the copy reads (a load), one the
// copy fills and the SD side reads (a save): two simple dual-port RAMs, one writer each
logic [7:0]  ibuf_in  [4608];
logic [7:0]  ibuf_out [4608];
logic [12:0] s_a, c_a;
logic        s_we, c_we;
logic [7:0]  s_d, c_d, s_q, c_q;
always_ff @(posedge clk_s) begin
	if (s_we) ibuf_in[s_a] <= s_d;
	s_q <= ibuf_out[s_a];
end
always_ff @(posedge clk_c) begin
	if (c_we) ibuf_out[c_a] <= c_d;
	c_q <= ibuf_in[c_a];
end

// ---- the SD side ---------------------------------------------------------------------------
typedef enum logic [2:0] {S_IDLE, S_REQ, S_XFER, S_COPY, S_SNAP} sst_t;
sst_t        st = S_IDLE;
logic        present = 1'b0, writable = 1'b0;
logic        loading = 1'b0;               // the blocks are coming in (else going out)
logic [3:0]  blk;
logic        marker_ok;
logic        ack_q;
logic [7:0]  seq_s1 = 8'd0, seq_s2 = 8'd0, saved = 8'd0;
logic [27:0] quiet = 28'd0;
logic        dirty = 1'b0;
logic        load_t = 1'b0, snap_t = 1'b0;             // requests to the copy (toggles)
logic [2:0]  load_d_s, snap_d_s;                       // its answers, synchronised
logic        load_d, snap_d;                           // (in clk_c)

assign sd_blk_cnt  = 6'd0;
assign sd_lba      = {28'd0, blk};
assign s_a         = {blk, sd_buff_addr[8:0]};
assign s_we        = loading && sd_ack && sd_buff_wr;
assign s_d         = sd_buff_dout;
assign sd_buff_din = s_q;

always_ff @(posedge clk_s) begin
	seq_s1   <= wr_seq;
	seq_s2   <= seq_s1;
	load_d_s <= {load_d_s[1:0], load_d};
	snap_d_s <= {snap_d_s[1:0], snap_d};
	ack_q    <= sd_ack;

	// a write since the last save: wait for two quiet seconds
	if (seq_s2 != saved) begin
		if (!dirty || seq_s2 != seq_s1) quiet <= 28'd0;
		else if (quiet != 28'hFFFFFFF) quiet <= quiet + 28'd1;
		dirty <= 1'b1;
	end

	// the marker, as block 8's first bytes come in
	if (s_we && blk == 4'd8 && sd_buff_addr[8:3] == 6'd0 && sd_buff_dout != MARKER[63 - 8 * sd_buff_addr[2:0] -: 8])
		marker_ok <= 1'b0;

	case (st)
		S_IDLE: begin
			if (img_mounted) begin
				present  <= img_size >= 64'd4608;
				writable <= !img_readonly;
				if (img_size >= 64'd4608) begin
					loading   <= 1'b1;
					blk       <= 4'd0;
					marker_ok <= 1'b1;
					st        <= S_REQ;
				end
			end
			else if (present && writable && dirty && quiet >= 28'(QUIET)) begin
				saved  <= seq_s2;                      // (writes from here on start another round)
				dirty  <= 1'b0;
				quiet  <= 28'd0;
				snap_t <= ~snap_t;
				st     <= S_SNAP;
			end
		end
		S_REQ: begin                                   // a block: asked until hps_io takes it
			if (loading) sd_rd <= 1'b1; else sd_wr <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				sd_wr <= 1'b0;
				st    <= S_XFER;
			end
		end
		S_XFER: if (ack_q && !sd_ack) begin            // the block's done
			if (blk != 4'd8) begin
				blk <= blk + 4'd1;
				st  <= S_REQ;
			end
			else if (loading) begin
				loading <= 1'b0;
				if (marker_ok) begin                   // a kept image: into the RTC
					load_t <= ~load_t;
					st     <= S_COPY;
				end
				else if (writable) begin               // a new file: the RTC's contents into it
					saved  <= seq_s2;
					dirty  <= 1'b0;
					snap_t <= ~snap_t;
					st     <= S_SNAP;
				end
				else st <= S_IDLE;
			end
			else st <= S_IDLE;
		end
		S_COPY: if (load_d_s[2] == load_t) begin       // the copy into the RTC is done
			saved <= seq_s2;
			dirty <= 1'b0;
			st    <= S_IDLE;
		end
		S_SNAP: if (snap_d_s[2] == snap_t) begin       // the RTC's contents are in the buffer: write them
			blk <= 4'd0;
			st  <= S_REQ;
		end
		default: st <= S_IDLE;
	endcase
end

// ---- the copy, in the CPU's clock -------------------------------------------------------------
// load: buffer 0-FFF to the NVRAM, buffer 1080 + i to CMOS i (0E-7F); snapshot: the reverse, and the
// marker into buffer 1000-1007. A byte: its address, then (two clocks later) its data, written when the RTC lets it
typedef enum logic [2:0] {C_IDLE, C_ADDR, C_WAIT, C_DATA, C_HOLD, C_NEXT, C_MARK} cst_t;
cst_t        cs = C_IDLE;
logic        c_load;                       // the copy's direction: into the RTC
logic [12:0] ci;                           // 0-FFF the NVRAM, 1000-107F the CMOS
logic [2:0]  load_t_c, snap_t_c;
logic        load_seen = 1'b0, snap_seen = 1'b0;
logic [3:0]  mi;
initial begin load_d = 1'b0; snap_d = 1'b0; end

// the buffer's place for RTC address i: the NVRAM at i, CMOS byte n at 1080 + n
wire [12:0] buf_of = ci[12] ? {6'b100001, ci[6:0]} : ci;
// the CMOS's time (00-0D) is the Main's: not loaded
wire        c_skip = ci[12] && ci[6:0] < 7'h0E;

always_ff @(posedge clk_c) begin
	load_t_c <= {load_t_c[1:0], load_t};
	snap_t_c <= {snap_t_c[1:0], snap_t};
	c_we     <= 1'b0;
	m_we     <= 1'b0;

	case (cs)
		C_IDLE: begin
			ci <= 13'd0;
			mi <= 4'd0;
			if (load_t_c[2] != load_seen) begin
				load_seen <= load_t_c[2];
				c_load    <= 1'b1;
				cs        <= C_ADDR;
			end
			else if (snap_t_c[2] != snap_seen) begin
				snap_seen <= snap_t_c[2];
				c_load    <= 1'b0;
				cs        <= C_ADDR;
			end
		end
		C_ADDR: begin
			c_a    <= buf_of;
			m_addr <= ci;
			cs     <= C_WAIT;
		end
		C_WAIT: cs <= C_DATA;                      // (the RAMs take the address)
		C_DATA: begin                              // c_q and m_q have the byte now
			if (!c_load) begin
				c_d  <= m_q;
				c_we <= 1'b1;
				cs   <= C_NEXT;
			end
			else if (c_skip) cs <= C_NEXT;
			else begin
				m_wdata <= c_q;
				m_we    <= 1'b1;
				cs      <= C_HOLD;
			end
		end
		C_HOLD: begin                              // the write is held until the RTC takes it (a cycle without the CPU)
			if (m_ok) cs <= C_NEXT;
			else      m_we <= 1'b1;
		end
		C_NEXT: begin
			if (ci != 13'h107F) begin
				ci <= ci + 13'd1;
				cs <= C_ADDR;
			end
			else if (c_load) begin
				load_d <= load_seen;
				cs     <= C_IDLE;
			end
			else cs <= C_MARK;
		end
		default: begin                             // C_MARK: the marker into buffer 1000-1007, then done
			if (mi != 4'd8) begin
				c_a  <= {10'b1000000000, mi[2:0]};
				c_d  <= MARKER[63 - 8 * mi[2:0] -: 8];
				c_we <= 1'b1;
				mi   <= mi + 4'd1;
			end
			else begin
				snap_d <= snap_seen;               // (the last write lands this cycle, long before the SD side reads it)
				cs     <= C_IDLE;
			end
		end
	endcase
end

endmodule
