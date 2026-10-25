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
	output logic [11:0] h_total, h_disp, h_ss, h_sl,     // in pixels
	output logic [10:0] v_total, v_disp, v_ss,
	output logic [4:0]  v_sl,
	output logic [2:0]  v_depth,       // 0 8 bits a pixel (the palette), 1 15 (5-5-5), 2 16 (5-6-5), 3 32 (8-8-8), 4 24
	output logic [20:0] v_start,
	output logic [11:0] v_pitch,
	output logic        v_screen_on,
	output logic [7:0]  v_pix_mask,
	output logic [6:0]  v_pll_m,
	output logic [7:0]  v_pll_n,       // N[4:0], and in 7:5 the post-divider's power of 2 (the pixel's)
	output logic        v_cur_on,
	output logic [10:0] v_cur_x, v_cur_y,
	output logic [10:0] v_cur_base,
	output logic        v_cur_x11,
	output logic [23:0] v_cur_fg, v_cur_bg,   // 8 bits a pixel: palette indexes; else pixel values
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
logic [2:0] sdac_magic;             // reads of 3C6 in a row: the fifth reaches the command register
logic [23:0] cur_fgs, cur_bgs;      // the cursor's colour stacks (CR4A, CR4B), at 15 bits a pixel and more
logic [1:0]  fgs_p, bgs_p;          // ... their next byte (a read of CR45 resets them)
logic [3:0] pll_widx, pll_ridx;
logic       pll_half;               // the next PLL data byte is N
logic [15:0] pll [16];              // {M, N}; index 0E one byte
logic [7:0] r46e8, r4ae8, r0102;
logic [15:0] ge_cy, ge_cx;          // CUR_Y and CUR_X as written, for reads (the 864's other 8514
                                    // registers but GP_STAT are write-only: they read 0)
logic       vint;                   // the vertical interrupt pending
logic       ge_rd_mode, ge_rd_valid;      // the engine's image read: running, a transfer waiting
logic [31:0] ge_rd_data;
logic       ge_bus32;                     // the engine's command takes 32-bit transfers
logic [31:0] pt_w;                        // a PIX_TRANS transfer for the engine, the bus's lanes
logic [15:0] pt_lo;                       // ... its first half (E2E8, E2E9) when it came alone

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
// the colour depth: the SDAC's command register (its input mode; 86Box's vid_ramdac_sdac.c). The 864's
// CRTC counts its clock, VCLK: 8 bits a pixel one pixel each, in the SDAC's 2:1 mode (command 1x, with
// CR67 1x) two; at 15 and 16 bits half a pixel, at 32 a quarter, VCLK twice the SDAC's clock (86Box's
// Vision864), which is the pixel's at 15 and 16 bits, twice it at 32; at 24 bits packed (4x, 9x, Ex)
// two thirds of a pixel, VCLK three quarters of the SDAC's clock, which is twice the pixel's
logic [2:0] depth;
always_comb begin
	case (sdac_cmd[7:4])
		4'h2, 4'h3, 4'h8, 4'hA: depth = 3'd1;
		4'h5, 4'h6, 4'hC:       depth = 3'd2;
		4'h7:                   depth = 3'd3;
		4'h4, 4'h9, 4'hE:       depth = 3'd4;
		default:                depth = 3'd0;
	endcase
end
assign v_depth = depth;
// characters (of 8 VCLKs) to pixels: x 16, 8, 4, 2; at 24 bits x 16 / 3
wire  [2:0] hsh = sdac_cmd[7:4] == 4'h1 || depth == 3'd4 ? 3'd4 : depth == 3'd0 ? 3'd3 : depth == 3'd3 ? 3'd1 : 3'd2;
// the CRTC in characters, with the S3's overflow bits (CR5D, CR5E)
wire  [9:0] ht_c = 10'(cr[7'h00]) + 10'd5 + {1'b0, cr[7'h5D][0], 8'd0};
wire  [9:0] hd_c = 10'(cr[7'h01]) + 10'd1 + {1'b0, cr[7'h5D][1], 8'd0};
wire  [9:0] hs_c = 10'(cr[7'h04]) + {1'b0, cr[7'h5D][4], 8'd0};
// (a sync end equal to its start is a whole count: 32 characters, 16 lines)
wire [4:0] hsl5 = 5'(cr[7'h05][4:0] - cr[7'h04][4:0]);
wire [3:0] vsl4 = 4'(cr[7'h11][3:0] - cr[7'h10][3:0]);
wire [9:0] hl_c = hsl5 == 5'd0 ? 10'd32 : 10'(hsl5);
// (quasi-static, so in three register stages: the shift, then the shift's value, then a third of it
// as (v x 21846) >> 16, exact for v below 2^14)
logic [2:0]  hsh_q;
logic        third_q, third_q2;
logic [13:0] hv [4];
always_ff @(posedge clk) begin
	hsh_q    <= hsh;
	third_q  <= depth == 3'd4;
	third_q2 <= third_q;
	hv[0] <= 14'({4'd0, ht_c} << hsh_q);
	hv[1] <= 14'({4'd0, hd_c} << hsh_q);
	hv[2] <= 14'({4'd0, hs_c} << hsh_q);
	hv[3] <= 14'({4'd0, hl_c} << hsh_q);
	h_total <= third_q2 ? 12'((30'(hv[0]) * 30'd21846) >> 16) : 12'(hv[0]);
	h_disp  <= third_q2 ? 12'((30'(hv[1]) * 30'd21846) >> 16) : 12'(hv[1]);
	h_ss    <= third_q2 ? 12'((30'(hv[2]) * 30'd21846) >> 16) : 12'(hv[2]);
	h_sl    <= third_q2 ? 12'((30'(hv[3]) * 30'd21846) >> 16) : 12'(hv[3]);
end
assign v_total = {cr[7'h5E][0], cr[7'h07][5], cr[7'h07][0], cr[7'h06]} + 11'd2;
assign v_disp  = {cr[7'h5E][1], cr[7'h07][6], cr[7'h07][1], cr[7'h12]} + 11'd1;
assign v_ss    = {cr[7'h5E][4], cr[7'h07][7], cr[7'h07][2], cr[7'h10]};
assign v_sl    = vsl4 == 4'd0 ? 5'd16 : {1'b0, vsl4};
assign v_start = 21'({cr[7'h51][1:0], cr[7'h31][5:4], cr[7'h0C], cr[7'h0D]}) << 2;
assign v_pitch = 12'({cr[7'h51][5:4], cr[7'h13], 3'b000});
assign v_screen_on = ~sr[1][5] & ar_idx[5];
assign v_pix_mask  = dac_mask;
// the dot clock: misc[3:2] 0 and 1 select f0 and f1, 3 the SDAC's f[CR42[2:0]]; or the SDAC's own
// select, PLL control (0E) bit 5 with its bits 2:0. At 24 and 32 bits a pixel the pixel's is half of it
wire  [3:0] clk_sel = pll[14][13]        ? {1'b0, pll[14][10:8]} :
                      misc[3:2] == 2'd3 ? {1'b0, cr[7'h42][2:0]} : {3'd0, misc[2]};
assign v_pll_m  = pll[clk_sel][14:8];
assign v_pll_n  = {3'({1'b0, pll[clk_sel][6:5]} + (depth == 3'd3 || depth == 3'd4 ? 3'd1 : 3'd0)), pll[clk_sel][4:0]};
assign v_cur_on = cr[7'h45][0];
// (at 32 bits a pixel the position is in half pixels: 86Box's 864)
wire  [10:0] cur_x_r = {cr[7'h46][2:0], cr[7'h47]};
assign v_cur_x  = depth == 3'd3 ? {1'b0, cur_x_r[10:1]} : cur_x_r;
assign v_cur_y  = {cr[7'h48][2:0], cr[7'h49]};
assign v_cur_base = {cr[7'h4C][2:0], cr[7'h4D]};
assign v_cur_x11  = cr[7'h55][4];
// the cursor's colours: at 8 bits a pixel CR0E the foreground, CR0F the background (the 801-864's; AIX's
// X server sets them so); deeper, the CR4A/CR4B stacks' pixel values
assign v_cur_fg   = depth == 3'd0 ? {16'd0, cr[7'h0E]} : cur_fgs;
assign v_cur_bg   = depth == 3'd0 ? {16'd0, cr[7'h0F]} : cur_bgs;

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
typedef enum logic [2:0] {A_IDLE, A_IO, A_MEM, A_PT, A_PR, A_DONE} ast_t;
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
	// (3C6 with RS2 the command register; without, the mask, or after four reads in a row of it 00 00 70
	// (the SDAC's ID) and then the command register: the ATT20C490 family's hidden access, 86Box's)
	else if (bp == 16'h03C6)            rb = cr[7'h55][0] ? sdac_cmd :
	                                         sdac_magic == 3'd0 ? dac_mask : sdac_magic == 3'd3 ? 8'h70 :
	                                         sdac_magic == 3'd4 ? sdac_cmd : 8'h00;
	else if (bp == 16'h03C7)            rb = cr[7'h55][0] ? {4'd0, pll_ridx} : {6'd0, dac_rstate, dac_rstate};
	else if (bp == 16'h03C8)            rb = cr[7'h55][2] ? {4'h0, monitor_id} : cr[7'h55][0] ? {4'd0, pll_widx} : dac_widx;
	else if (bp == 16'h03C9)            rb = cr[7'h55][0] ? (pll_half ? pll[pll_ridx][7:0] : pll[pll_ridx][15:8])
	                                       : {2'b00, dac_rc == 2'd0 ? pal_q[17:12] : dac_rc == 2'd1 ? pal_q[11:6] : pal_q[5:0]};
	else if (bp == 16'h03CC)            rb = misc;
	else if (bp == 16'h03CE)            rb = {4'd0, gr_idx};
	else if (bp == 16'h03CF)            rb = gr[gr_idx];
	else if (bp == crt_base + 16'h4)    rb = {1'b0, cr_idx};
	else if (bp == crt_base + 16'h5)    rb = cr_idx == 7'h30 ? 8'hC0 : cr[cr_idx];
	// input status 1; 3DB, not decoded, answers the same (the chip's one read byte on every lane): AIX's
	// X server polls the retrace with a halfword read of 3DA and tests the low byte, 3DB's
	else if (bp == crt_base + 16'hA ||
	         bp == crt_base + 16'hB)    rb = {4'h0, vsync, 2'b00, vblank};
	else if (bp == 16'h42E8)            rb = {7'd0, vint};
	else if (bp == 16'h42E9)            rb = 8'h00;
	else if (bp == 16'h46E8)            rb = r46e8;
	else if (bp == 16'h4AE8)            rb = r4ae8;
	else if (bp == 16'h0102)            rb = r0102;
	else if (bp == 16'h9AE8)            rb = 8'h00;                             // GP_STAT: the FIFO empty (no FIFO: the bus waits)
	else if (bp == 16'h9AE9)            rb = {6'd0, ge_busy, ge_rd_valid};      // ... bit 9 the engine busy, 8 read data waiting
	else if (bp == 16'h82E8)            rb = ge_cy[7:0];
	else if (bp == 16'h82E9)            rb = ge_cy[15:8];
	else if (bp == 16'h86E8)            rb = ge_cx[7:0];
	else if (bp == 16'h86E9)            rb = ge_cx[15:8];
	else if (bp[9:0] == 10'h2E8 || bp[9:0] == 10'h2E9) rb = 8'h00;
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
	.pt_valid(ast == A_PT), .pt_data({pt_w[7:0], pt_w[15:8], pt_w[23:16], pt_w[31:24]}), .pt_ready,
	.bus32(ge_bus32), .rd_mode(ge_rd_mode), .rd_valid(ge_rd_valid), .rd_data(ge_rd_data), .rd_take(ast == A_PR && ge_rd_valid),
	.busy(ge_busy), .pitch(ge_pitch[11:0]),
	.psz(cr[7'h50][5:4] == 2'b01 ? 2'd1 : cr[7'h50][5:4] == 2'b11 ? 2'd2 : 2'd0),   // CR50: bytes a pixel
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
				// (on a 32-bit bus a halfword write of E2E8 waits for E2EA's to complete the transfer)
				if (ge_bus32 && be == 4'b1100) begin
					pt_lo <= wdata[31:16];
					ast   <= A_DONE;
				end
				else begin
					pt_w <= (ge_bus32 && be == 4'b0011) ? {pt_lo, wdata[15:0]} : wdata;
					ast  <= A_PT;
				end
			end
			else if (port == 16'hE2E8 && ge_rd_mode) begin   // ... or from it, in an image read
				ast <= A_PR;
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
		A_PR: if (ge_rd_valid) begin                     // the engine's transfer (E2E8 in its bits 7:0) on the bus's lanes
			rq  <= {ge_rd_data[7:0], ge_rd_data[15:8], ge_rd_data[23:16], ge_rd_data[31:24]};
			ast <= A_DONE;
		end
		else if (!ge_busy) begin
			rq  <= 32'hFFFF_FFFF;
			ast <= A_DONE;
		end
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
					if (cr[7'h55][0] || sdac_magic == 3'd4) sdac_cmd <= bw; else dac_mask <= bw;
					if (sdac_magic == 3'd4) sdac_magic <= 3'd0;
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
						// (f0 and f1 are fixed; 8, 9, B-D, F do not exist)
						if ((pll_widx >= 4'h2 && pll_widx <= 4'h7) || pll_widx == 4'hA || pll_widx == 4'hE) begin
							if (!pll_half) pll[pll_widx][15:8] <= bw; else pll[pll_widx][7:0] <= bw;
						end
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
				if (bp == crt_base + 16'h5 && cr_idx == 7'h4A) begin
					if (fgs_p == 2'd0) cur_fgs[7:0] <= bw;
					if (fgs_p == 2'd1) cur_fgs[15:8] <= bw;
					if (fgs_p == 2'd2) cur_fgs[23:16] <= bw;
					fgs_p <= fgs_p + 2'd1;
				end
				if (bp == crt_base + 16'h5 && cr_idx == 7'h4B) begin
					if (bgs_p == 2'd0) cur_bgs[7:0] <= bw;
					if (bgs_p == 2'd1) cur_bgs[15:8] <= bw;
					if (bgs_p == 2'd2) cur_bgs[23:16] <= bw;
					bgs_p <= bgs_p + 2'd1;
				end
				if (bp == crt_base + 16'h5) begin
					// CR11 bit 7 protects CR00-CR07 (but CR07 bit 4)
					if (!(cr[7'h11][7] && cr_idx <= 7'h07)) cr[cr_idx] <= bw;
					else if (cr_idx == 7'h07) cr[7'h07][4] <= bw[4];
				end
				if (bp == 16'h42E8 && bw[0]) vint <= 1'b0;
				if (bp == 16'h46E8) r46e8 <= bw;
				if (bp == 16'h4AE8) r4ae8 <= bw;
				if (bp == 16'h0102) r0102 <= bw;
				if (bp == 16'h82E8) ge_cy[7:0]  <= bw;
				if (bp == 16'h82E9) ge_cy[15:8] <= bw;
				if (bp == 16'h86E8) ge_cx[7:0]  <= bw;
				if (bp == 16'h86E9) ge_cx[15:8] <= bw;
			end
			// a read of input status 1 resets the attribute flip-flop
			if (!we && bp == crt_base + 16'hA) ar_ff <= 1'b0;
			// a read of CR45 resets the cursor's colour stacks
			if (!we && bp == crt_base + 16'h5 && cr_idx == 7'h45) begin fgs_p <= 2'd0; bgs_p <= 2'd0; end
			// the SDAC's reads of 3C6 in a row; any other DAC access starts again
			if (bp >= 16'h03C6 && bp <= 16'h03C9) begin
				if (bp == 16'h03C6 && !cr[7'h55][0]) begin
					if (!we) sdac_magic <= sdac_magic == 3'd4 ? 3'd0 : sdac_magic + 3'd1;
				end
				else sdac_magic <= 3'd0;
			end
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
		sdac_cmd <= 8'h00; sdac_magic <= 3'd0; pll_widx <= '0; pll_ridx <= '0; pll_half <= 1'b0;
		fgs_p <= 2'd0; bgs_p <= 2'd0; cur_fgs <= 24'hFFFFFF; cur_bgs <= 24'h000000;
		r46e8 <= 8'h00; r4ae8 <= 8'h00; r0102 <= 8'h00; vint <= 1'b0;
		for (int i = 0; i < 128; i++) cr[i] <= 8'h00;
		cr[7'h36] <= 8'h8E;                      // the straps: 2 MB (an open question: docs/s3_design.md 5)
		pll[0] <= 16'h2861;                      // f0 25.06 MHz, f1 28.19 (the SDAC's fixed clocks, as XFree86 reads them)
		pll[1] <= 16'h3D62;
		pll[14] <= 16'h0000;                     // PLL control: the clock select from the pins
		cr[7'h37] <= 8'h0F;
	end
end

assign irq = vint & ~cr[7'h11][5] & cr[7'h32][4];

endmodule
