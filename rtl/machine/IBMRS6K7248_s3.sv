//============================================================================
//
//  IBMRS6K7248 - the S3 Vision864 and its SDAC: registers, phase 1a
//
//  The on-board video of the Carolina board, PCI bus 0 device 14
//  (5333:88C0), as the firmware's S3 driver uses it (docs/s3_design.md,
//  section 1; the design, section 4). Here: the PCI header, the VGA, S3
//  and SDAC registers, the palette, the monitor ID, the linear frame
//  buffer's decode and its path to VRAM, the vertical interrupt, and the
//  graphics engine (IBMRS6K7248_s3ge, phase 1b) sharing VRAM with the
//  frame buffer. The picture side (IBMRS6K7248_s3video, phase 1c, in the
//  video clock) takes the CRTC, pitch, start, cursor and clock values
//  from here, reads the palette through a second port, and sends the
//  retrace and display enable back (3DA, the vertical interrupt).
//
//  The bus (from IBMRS6K7248_machine): a word with byte enables, be[3] the
//  lowest address and bits 31-24 its byte (the PowerPC's lanes: the MPC105
//  keeps bytes at their addresses); the answer with ack, a cycle or more
//  after sel, sel held until then. I/O: the enabled bytes are taken one
//  at a time, lowest address first, as the ports' byte sequence (3C4 then
//  3C5 for a 16-bit index/data write; 9AE8 then 9AE9). Memory: the frame
//  buffer's window, a word to the VRAM port.
//
//  The VRAM port (v_*): words with byte enables by byte offset in the
//  2 MB VRAM, req held until ack, the bytes at their offsets (VRAM byte a
//  is lane a & 3 of word a >> 2, be[3] / bits 31-24 the lowest).
//
//  The configuration interface is IBMRS6K7248_mpc105's (little-endian).
//
//============================================================================

module IBMRS6K7248_s3
#(
	parameter int unsigned CLK_HZ  = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	// PCI configuration (device 14)
	input  logic        cfg_sel,
	input  logic        cfg_we,
	input  logic [7:2]  cfg_reg,
	input  logic [3:0]  cfg_be,        // little-endian
	input  logic [31:0] cfg_wdata,
	output logic [31:0] cfg_rdata,

	// the decode, for the machine: an ISA I/O port and a PCI memory address
	input  logic [15:0] port,          // the access's word address (bits 1:0 0)
	input  logic [31:0] pci_addr,      // CPU address - C0000000
	output logic        io_hit,
	output logic        mem_hit,

	// an access (io_hit or mem_hit decided it), held until ack
	input  logic        sel,
	input  logic        we,
	input  logic        is_mem,
	input  logic [3:0]  be,
	input  logic [31:0] wdata,
	output logic [31:0] rdata,
	output logic        ack,

	// VRAM
	output logic        v_req,
	output logic        v_we,
	output logic [20:2] v_addr,
	output logic [3:0]  v_be,
	output logic [31:0] v_wdata,
	input  logic        v_ack,
	input  logic [31:0] v_rdata,

	// to and from the picture side (IBMRS6K7248_s3video), which runs in clk_v
	input  logic        clk_v,
	output logic [10:0] h_total, h_disp, h_ss, h_sl, v_total, v_disp, v_ss,
	output logic [4:0]  v_sl,
	output logic [20:0] v_start,
	output logic [11:0] v_pitch,
	output logic        v_screen_on,
	output logic [7:0]  v_pix_mask,
	output logic [6:0]  v_pll_m, v_pll_n,
	output logic        v_cur_on,
	output logic [10:0] v_cur_x, v_cur_y,
	output logic [10:0] v_cur_base,
	input  logic [7:0]  pal_vaddr,
	output logic [17:0] pal_vq,
	input  logic        vretrace_v,
	input  logic        disp_en_v,

	output logic        irq,           // the vertical interrupt (to IRQ 15)
	input  logic [3:0]  monitor_id     // the monitor's ID lines (F: class 3, 72 Hz; 6: class 0, 60 Hz)
);

// ---- PCI header -------------------------------------------------------------------------
logic [15:0] pci_cmd;
logic [7:0]  pci_int_line;
always_ff @(posedge clk) begin
	if (cfg_sel & cfg_we) begin
		if (cfg_reg == 6'h01) begin
			if (cfg_be[0]) pci_cmd[7:0]  <= cfg_wdata[7:0];
			if (cfg_be[1]) pci_cmd[15:8] <= cfg_wdata[15:8];
		end
		if (cfg_reg == 6'h0F && cfg_be[0]) pci_int_line <= cfg_wdata[7:0];
	end
	if (cfg_sel & ~cfg_we) begin
		case (cfg_reg)
			6'h00:   cfg_rdata <= 32'h88C0_5333;
			6'h01:   cfg_rdata <= {16'h0200, pci_cmd};
			6'h02:   cfg_rdata <= 32'h0300_0000;          // display controller, VGA (an open question: docs/s3_design.md 5)
			6'h0F:   cfg_rdata <= {16'h0000, 8'h01, pci_int_line};
			default: cfg_rdata <= 32'h0;
		endcase
	end
	if (reset) begin pci_cmd <= 16'h0; pci_int_line <= 8'h0; end
end
wire io_on  = pci_cmd[0];
wire mem_on = pci_cmd[1];

// ---- registers --------------------------------------------------------------------------
logic [7:0] misc;                   // 3C2 / 3CC
logic [7:0] sr [32];
logic [4:0] sr_idx;
logic [7:0] cr [128];
logic [6:0] cr_idx;
logic [7:0] gr [16];
logic [3:0] gr_idx;
logic [7:0] ar [32];
logic [5:0] ar_idx;                 // bit 5: PAS
logic       ar_ff;                  // 0: the next 3C0 write is the index
logic [7:0] dac_mask;
logic [7:0] dac_widx, dac_ridx;
logic [1:0] dac_wc, dac_rc;         // the component counters
logic [5:0] dac_r, dac_g;           // a colour being written
logic [17:0] palette [256];
logic [17:0] pal_q;
logic       dac_rstate;             // 3C7 read: 0 the DAC is in write mode, 3 read mode
logic [7:0] sdac_cmd;
logic [3:0] pll_widx, pll_ridx;
logic       pll_half;               // the next PLL data byte is N
logic [15:0] pll [16];              // {M, N}; index 0E one byte
logic [7:0] r46e8, r4ae8, r0102;
logic [15:0] ge [64];               // the 8514 registers xxE8 by xx >> 2 (82E8 ... BEE8), little-endian
logic       vint;                   // the vertical interrupt pending

// the CRTC's port base follows misc bit 0 (3Dx colour, 3Bx mono)
wire  [15:0] crt_base = misc[0] ? 16'h03D0 : 16'h03B0;

// the CRTC's retrace and display enable, from the picture side (IBMRS6K7248_s3video), into this clock
logic [2:0] vr_s, de_s;
always_ff @(posedge clk) begin
	vr_s <= {vr_s[1:0], vretrace_v};
	de_s <= {de_s[1:0], disp_en_v};
end
wire  vsync   = vr_s[1];
wire  vsync_q = vr_s[2];
wire  vblank  = ~de_s[1];                       // 3DA bit 0: display disabled

// ---- what the picture side needs (quasi-static) -------------------------------------------
// the CRTC in characters of 8 dots, with the S3's overflow bits (CR5D, CR5E)
assign h_total = {(11'(cr[7'h00]) + 11'd5 + {2'd0, cr[7'h5D][0], 8'd0})} << 3;
assign h_disp  = {(11'(cr[7'h01]) + 11'd1 + {2'd0, cr[7'h5D][1], 8'd0})} << 3;
assign h_ss    = {(11'(cr[7'h04]) + {2'd0, cr[7'h5D][4], 8'd0})} << 3;
// (a sync end equal to its start is a whole count: 32 characters, 16 lines)
wire [4:0] hsl5 = 5'(cr[7'h05][4:0] - cr[7'h04][4:0]);
wire [3:0] vsl4 = 4'(cr[7'h11][3:0] - cr[7'h10][3:0]);
assign h_sl    = (hsl5 == 5'd0 ? 11'd32 : 11'(hsl5)) << 3;
assign v_total = {cr[7'h5E][0], cr[7'h07][5], cr[7'h07][0], cr[7'h06]} + 11'd2;
assign v_disp  = {cr[7'h5E][1], cr[7'h07][6], cr[7'h07][1], cr[7'h12]} + 11'd1;
assign v_ss    = {cr[7'h5E][4], cr[7'h07][7], cr[7'h07][2], cr[7'h10]};
assign v_sl    = vsl4 == 4'd0 ? 5'd16 : {1'b0, vsl4};
assign v_start = 21'({cr[7'h51][1:0], cr[7'h31][5:4], cr[7'h0C], cr[7'h0D]}) << 2;
assign v_pitch = 12'({cr[7'h51][5:4], cr[7'h13], 3'b000});
assign v_screen_on = ~sr[1][5] & ar_idx[5];
assign v_pix_mask  = dac_mask;
// the dot clock: misc[3:2] 0 and 1 select f0 and f1, 3 the SDAC's f[CR42[2:0]]
wire  [3:0] clk_sel = misc[3:2] == 2'd3 ? {1'b0, cr[7'h42][2:0]} : {3'd0, misc[2]};
assign v_pll_m  = pll[clk_sel][14:8];
assign v_pll_n  = pll[clk_sel][6:0];
assign v_cur_on = cr[7'h45][0];
assign v_cur_x  = {cr[7'h46][2:0], cr[7'h47]};
assign v_cur_y  = {cr[7'h48][2:0], cr[7'h49]};
assign v_cur_base = {cr[7'h4C][2:0], cr[7'h4D]};

// the palette's second read port, in the picture's clock
always_ff @(posedge clk_v) pal_vq <= palette[pal_vaddr];

// ---- decode -----------------------------------------------------------------------------
// the ports: VGA 3B0-3DF, 42E8, 46E8, 4AE8, 0102, the 8514 registers 82E8-BEE8 (every 400),
// PIX_TRANS E2E8-E2EB
wire [15:0] pw = port;
always_comb begin
	// (VGA: 3C0-3CF, and the CRTC's set misc bit 0 selects, 3D4/3D5/3DA or 3B4/3B5/3BA: not
	// 3BC-3BF, the parallel port the firmware's progress codes go to)
	io_hit = io_on && ((pw >= 16'h03C0 && pw <= 16'h03CC) ||
	                   pw == {crt_base[15:4], 4'h4} || pw == {crt_base[15:4], 4'h8} ||
	                   pw == 16'h42E8 || pw == 16'h46E8 || pw == 16'h4AE8 || pw == 16'h0100 ||
	                   (pw[9:0] == 10'h2E8 && pw[15] && pw[15:10] <= 6'h2F) ||
	                   pw == 16'hE2E8);
end
// the frame buffer: CR58 bit 4 on, the window CR58[1:0] (64 KB, 1, 2, 4 MB) at CR59/CR5A << 16,
// aligned to its size
wire  [1:0]  lfb_win  = cr[7'h58][1:0];
wire  [31:16] lfb_base = {cr[7'h59], cr[7'h5A]};
logic [31:16] lfb_mask;
always_comb begin
	case (lfb_win)
		2'd0:    lfb_mask = 16'hFFFF;     // 64 KB
		2'd1:    lfb_mask = 16'hFFF0;     // 1 MB
		2'd2:    lfb_mask = 16'hFFE0;     // 2 MB
		default: lfb_mask = 16'hFFC0;     // 4 MB
	endcase
end
assign mem_hit = mem_on && cr[7'h58][4] && ((pci_addr[31:16] & lfb_mask) == (lfb_base & lfb_mask));
wire [21:0] lfb_off = pci_addr[21:0] & {~lfb_mask[21:16], 16'hFFFF};

// ---- the access: I/O a byte at a time; memory to VRAM ------------------------------------
typedef enum logic [2:0] {A_IDLE, A_IO, A_MEM, A_PT, A_DONE} ast_t;
ast_t        ast;
logic [3:0]  left;                  // I/O: the lanes still to do (bit 3 the lowest address)
logic [31:0] rq;                    // the answer being gathered
wire  [1:0]  k   = left[3] ? 2'd0 : left[2] ? 2'd1 : left[1] ? 2'd2 : 2'd3;   // the next lane
wire  [15:0] bp  = {port[15:2], k};                                          // its port
wire  [7:0]  bw  = wdata[31 - 8 * k -: 8];                                  // its byte

// one byte register access
function automatic logic [7:0] lanebyte(input logic [31:0] w, input logic [1:0] l);
	lanebyte = w[31 - 8 * l -: 8];
endfunction

logic [7:0] rb;                     // the byte a read returns (combinational, from bp)
always_comb begin
	rb = 8'hFF;
	if (bp == 16'h03C0)                 rb = {2'b00, ar_idx};
	else if (bp == 16'h03C1)            rb = ar[ar_idx[4:0]];
	else if (bp == 16'h03C2)            rb = {vint, 7'h00};                    // input status 0
	else if (bp == 16'h03C3)            rb = 8'h01;
	else if (bp == 16'h03C4)            rb = {3'd0, sr_idx};
	else if (bp == 16'h03C5)            rb = sr[sr_idx];
	else if (bp == 16'h03C6)            rb = cr[7'h55][0] ? sdac_cmd : dac_mask;
	else if (bp == 16'h03C7)            rb = cr[7'h55][0] ? {4'd0, pll_ridx} : {6'd0, dac_rstate, dac_rstate};
	else if (bp == 16'h03C8)            rb = cr[7'h55][2] ? {4'h0, monitor_id} : cr[7'h55][0] ? {4'd0, pll_widx} : dac_widx;
	else if (bp == 16'h03C9)            rb = cr[7'h55][0] ? (pll_half ? pll[pll_ridx][7:0] : pll[pll_ridx][15:8])
	                                       : {2'b00, dac_rc == 2'd0 ? pal_q[17:12] : dac_rc == 2'd1 ? pal_q[11:6] : pal_q[5:0]};
	else if (bp == 16'h03CC)            rb = misc;
	else if (bp == 16'h03CE)            rb = {4'd0, gr_idx};
	else if (bp == 16'h03CF)            rb = gr[gr_idx];
	else if (bp == crt_base + 16'h4)    rb = {1'b0, cr_idx};
	else if (bp == crt_base + 16'h5)    rb = cr_idx == 7'h30 ? 8'hC0 : cr[cr_idx];
	else if (bp == crt_base + 16'hA)    rb = {4'h0, vsync, 2'b00, vblank};       // input status 1
	else if (bp == 16'h42E8)            rb = {7'd0, vint};
	else if (bp == 16'h42E9)            rb = 8'h00;
	else if (bp == 16'h46E8)            rb = r46e8;
	else if (bp == 16'h4AE8)            rb = r4ae8;
	else if (bp == 16'h0102)            rb = r0102;
	else if (bp == 16'h9AE8)            rb = 8'h00;                             // GP_STAT: the FIFO empty (no FIFO: the bus waits)
	else if (bp == 16'h9AE9)            rb = {6'd0, ge_busy, 1'b0};             // ... bit 9 the engine busy
	else if (bp[9:0] == 10'h2E8)        rb = ge[bp[15:10]][7:0];
	else if (bp[9:0] == 10'h2E9)        rb = ge[bp[15:10]][15:8];
end

// ---- the graphics engine, and VRAM shared by it and the CPU's frame buffer accesses ----------
wire        ge_reg_b = bp[15] && bp[15:10] <= 6'h2F && (bp[9:0] == 10'h2E8 || bp[9:0] == 10'h2E9);
logic       ge_busy, pt_ready;
logic       l_req, l_we, l_ack;
logic [20:2] l_addr;
logic [3:0] l_be;
logic [31:0] l_wdata;
logic       e_req, e_we, e_ack;
logic [20:2] e_addr;
logic [3:0] e_be;
logic [31:0] e_wdata;
wire  [12:0] ge_pitch = {cr[7'h51][5:4], cr[7'h13], 3'b000};   // the engine takes its low 12 bits (Quartus 17 cannot slice a concatenation)
IBMRS6K7248_s3ge engine (
	.clk, .reset,
	.r_we(ast == A_IO && we && ge_reg_b && !ge_busy), .r_idx(bp[15:10]), .r_hi(bp[0]), .r_data(bw),
	.r_abort(ast == A_IO && we && bp == 16'h42E9 && bw[7:6] == 2'b10),
	.pt_valid(ast == A_PT), .pt_data({wdata[23:16], wdata[31:24]}), .pt_ready,
	.busy(ge_busy), .pitch(ge_pitch[11:0]),
	.v_req(e_req), .v_we(e_we), .v_addr(e_addr), .v_be(e_be), .v_wdata(e_wdata), .v_ack(e_ack), .v_rdata
);
// the arbiter: whoever asks first keeps VRAM until answered; the CPU first if both
logic own_e, own_l;
wire  grant_l = ~own_e & ~own_l & l_req;
wire  grant_e = ~own_e & ~own_l & ~l_req & e_req;
always_ff @(posedge clk) begin
	if (grant_l) own_l <= 1'b1;
	if (grant_e) own_e <= 1'b1;
	if (v_ack) begin own_l <= 1'b0; own_e <= 1'b0; end
	if (reset) begin own_l <= 1'b0; own_e <= 1'b0; end
end
wire  sel_e  = own_e | grant_e;
assign v_req   = (own_l | grant_l) ? l_req : sel_e ? e_req : 1'b0;
assign v_we    = sel_e ? e_we : l_we;
assign v_addr  = sel_e ? e_addr : l_addr;
assign v_be    = sel_e ? e_be : l_be;
assign v_wdata = sel_e ? e_wdata : l_wdata;
assign l_ack   = v_ack & own_l;
assign e_ack   = v_ack & own_e;

// palette reads: the colour at the read index
always_ff @(posedge clk) pal_q <= palette[dac_ridx];

always_ff @(posedge clk) begin
	ack   <= 1'b0;

	// the vertical interrupt: set at the start of vertical sync while CR11 bit 4 is 1,
	// held clear while it is 0, cleared by a 42E8 write with bit 0
	if (!cr[7'h11][4]) vint <= 1'b0;
	else if (vsync & ~vsync_q) vint <= 1'b1;

	case (ast)
		A_IDLE: if (sel & ~ack) begin
			if (is_mem) begin
				if (lfb_off[21]) begin           // beyond the 2 MB: nothing (no aliasing)
					rq  <= 32'hFFFF_FFFF;
					ast <= A_DONE;
				end
				else begin
					l_req   <= 1'b1;
					l_we    <= we;
					l_addr  <= lfb_off[20:2];
					l_be    <= be;
					l_wdata <= wdata;
					ast     <= A_MEM;
				end
			end
			else if (port == 16'hE2E8 && we) begin   // PIX_TRANS: the transfer whole, to the engine
				ast <= A_PT;
			end
			else begin
				left <= be;
				rq   <= 32'hFFFF_FFFF;
				ast  <= (be == 4'd0) ? A_DONE : A_IO;
			end
		end
		A_MEM: if (l_ack) begin
			l_req <= 1'b0;
			rq    <= v_rdata;
			ast   <= A_DONE;
		end
		A_PT: if (pt_ready | ~ge_busy) ast <= A_DONE;    // taken by the engine, or dropped with none running
		A_IO: if (!(we && ge_reg_b && ge_busy)) begin     // an engine register waits for the engine
			left[3 - k] <= 1'b0;
			if (left == (4'b1000 >> k)) ast <= A_DONE;
			if (!we) rq[31 - 8 * k -: 8] <= rb;
			else begin
				// the writes
				if (bp == 16'h03C0) begin
					if (!ar_ff) ar_idx <= bw[5:0];
					else ar[ar_idx[4:0]] <= bw;
					ar_ff <= ~ar_ff;
				end
				if (bp == 16'h03C2) misc <= bw;
				if (bp == 16'h03C4) sr_idx <= bw[4:0];
				if (bp == 16'h03C5) sr[sr_idx] <= bw;
				if (bp == 16'h03C6) begin
					if (cr[7'h55][0]) sdac_cmd <= bw; else dac_mask <= bw;
				end
				if (bp == 16'h03C7) begin
					if (cr[7'h55][0]) begin pll_ridx <= bw[3:0]; pll_half <= 1'b0; end
					else begin dac_ridx <= bw; dac_rc <= 2'd0; dac_rstate <= 1'b1; end
				end
				if (bp == 16'h03C8) begin
					if (cr[7'h55][0]) begin pll_widx <= bw[3:0]; pll_half <= 1'b0; end
					else begin dac_widx <= bw; dac_wc <= 2'd0; dac_rstate <= 1'b0; end
				end
				if (bp == 16'h03C9) begin
					if (cr[7'h55][0]) begin
						if (!pll_half) pll[pll_widx][15:8] <= bw; else pll[pll_widx][7:0] <= bw;
						// index 0E takes one byte; the others M then N, then the next index
						if (pll_half || pll_widx == 4'hE) begin pll_half <= 1'b0; pll_widx <= pll_widx + 4'd1; end
						else pll_half <= 1'b1;
					end
					else begin
						case (dac_wc)
							2'd0: begin dac_r <= bw[5:0]; dac_wc <= 2'd1; end
							2'd1: begin dac_g <= bw[5:0]; dac_wc <= 2'd2; end
							default: begin
								palette[dac_widx] <= {dac_r, dac_g, bw[5:0]};
								dac_widx <= dac_widx + 8'd1;
								dac_wc   <= 2'd0;
							end
						endcase
					end
				end
				if (bp == 16'h03CE) gr_idx <= bw[3:0];
				if (bp == 16'h03CF) gr[gr_idx] <= bw;
				if (bp == crt_base + 16'h4) cr_idx <= bw[6:0];
				if (bp == crt_base + 16'h5) begin
					// CR11 bit 7 protects CR00-CR07 (but CR07 bit 4)
					if (!(cr[7'h11][7] && cr_idx <= 7'h07)) cr[cr_idx] <= bw;
					else if (cr_idx == 7'h07) cr[7'h07][4] <= bw[4];
				end
				if (bp == 16'h42E8 && bw[0]) vint <= 1'b0;
				if (bp == 16'h46E8) r46e8 <= bw;
				if (bp == 16'h4AE8) r4ae8 <= bw;
				if (bp == 16'h0102) r0102 <= bw;
				if (bp[9:0] == 10'h2E8) ge[bp[15:10]][7:0]  <= bw;
				if (bp[9:0] == 10'h2E9) ge[bp[15:10]][15:8] <= bw;
			end
			// a read of input status 1 resets the attribute flip-flop
			if (!we && bp == crt_base + 16'hA) ar_ff <= 1'b0;
			// palette reads advance the component, then the index
			if (!we && bp == 16'h03C9 && !cr[7'h55][0]) begin
				if (dac_rc == 2'd2) begin dac_rc <= 2'd0; dac_ridx <= dac_ridx + 8'd1; end
				else dac_rc <= dac_rc + 2'd1;
			end
			if (!we && bp == 16'h03C9 && cr[7'h55][0]) begin
				if (pll_half || pll_ridx == 4'hE) begin pll_half <= 1'b0; pll_ridx <= pll_ridx + 4'd1; end
				else pll_half <= 1'b1;
			end
		end
		default: begin                           // A_DONE
			rdata <= rq;
			ack   <= 1'b1;
			ast   <= A_IDLE;
		end
	endcase

	if (reset) begin
		ast <= A_IDLE; ack <= 1'b0; l_req <= 1'b0;
		misc <= 8'h00; sr_idx <= '0; cr_idx <= '0; gr_idx <= '0; ar_idx <= '0; ar_ff <= 1'b0;
		dac_mask <= 8'hFF; dac_widx <= '0; dac_ridx <= '0; dac_wc <= '0; dac_rc <= '0; dac_rstate <= 1'b0;
		sdac_cmd <= 8'h00; pll_widx <= '0; pll_ridx <= '0; pll_half <= 1'b0;
		r46e8 <= 8'h00; r4ae8 <= 8'h00; r0102 <= 8'h00; vint <= 1'b0;
		for (int i = 0; i < 128; i++) cr[i] <= 8'h00;
		cr[7'h36] <= 8'h8E;                      // the straps: 2 MB (an open question: docs/s3_design.md 5)
		pll[0] <= 16'h684D;                      // f0 about 25.175 MHz, f1 about 28.322 (the SDAC's power-on clocks)
		pll[1] <= 16'h5D4A;
		cr[7'h37] <= 8'h0F;
	end
end

assign irq = vint & ~cr[7'h11][5] & cr[7'h32][4];

endmodule
