//============================================================================
//
//  IBMRS6K7248 - the IBM RS/6000 43P model 7248 for MiSTer
//  The top: the framework's ports, the clocks, the ROM upload, the SDRAM,
//  the machine (IBMRS6K7248_system), COM1 on the MiSTer's UART
//
//  Clocks from one PLL (rtl/pll.v, MacPPC7300's: counter 1 at 70 or 100 MHz by CPU_MHZ):
//    clk_cpu   70 MHz  the CPU and the machine (IBMRS6K7248_system)
//    clk_mem  100 MHz  the SDRAM controller, hps_io, the ROM upload, the picture
//  (at CPU_MHZ = 100 the two are one PLL counter; the clock crossing between
//  them is DSPPC604_memcdc's, as in MacPPC7300.) outclk_0 (20 MHz) is unused.
//
//  The picture is the S3 Vision864's (IBMRS6K7248_s3video: its VRAM in the
//  HPS's DDR3); the firmware's serial console is COM1, the MiSTer's UART.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

localparam int CPU_MHZ = 70;                // the PLL's 70 or 100: the first fit at 100 missed by 6.2 ns (the CPU's paths, as MacPPC7300's, which runs at 70)
localparam int TB_HZ   = 16_666_667;        // the 604's time base: a quarter of a 66 MHz bus

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
wire   speaker;                         // the 8254's counter 2 through port 61, in the CPU's clock
assign AUDIO_L = speaker ? 16'h1000 : 16'h0000;
assign AUDIO_R = speaker ? 16'h1000 : 16'h0000;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"IBMRS6K7248;UART115200:57600:38400:19200:9600;",
	"-;",
	"F1,ROMBINIMG,Load firmware ROM;",
	"-;",
	"S0,IMGHDAVHD,SCSI disk ID 0;",
	"S1,IMGHDAVHD,SCSI disk ID 1;",
	"S2,ISOBINCUECHD,SCSI CD-ROM ID 3;",
	"-;",
	// the RAM as the board's SIMM pairs, beside the ROM (the SDRAM's top 4 MB): the most the
	// SDRAM holds (24, 56 or 112 MB), or less
	"O[3:1],RAM (on reset),Most,16 MB,32 MB,48 MB,64 MB,96 MB;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"O[4],UART,POST codes,COM1;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_cpu, clk_mem, pll_locked;
wire [63:0] reconfig_to_pll, reconfig_from_pll;
pll #(.CPU_MHZ(CPU_MHZ)) pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(),
	.outclk_1(clk_cpu),
	.outclk_2(clk_mem),
	.locked(pll_locked),
	.reconfig_to_pll,
	.reconfig_from_pll
);

// the PLL is built reconfigurable (MacPPC7300's); here nothing rewrites it
pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll,
	.reconfig_from_pll
);

wire clk_sys = clk_mem;

///////////////////////   HPS   ///////////////////////////////

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;
wire [15:0] sdram_sz;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire [64:0] rtc;                      // BCD: seconds, minutes, hours, date, month, year, weekday; [64] toggles                 // the Main's SDRAM board: [15] known, [1:0] 1 32 MB, 2 64 MB, 3 128 MB
reg   [1:0] sdram_mod = 2'd1;         // the board the ROM went into (an unknown one taken as 32 MB)

// the SCSI devices' images: hps_io block devices 0-2 (8-bit, 512-byte blocks)
wire  [2:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[3];
wire  [5:0] sd_blk_cnt[3];
wire  [2:0] sd_rd, sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[3];
wire        sd_buff_wr;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(3), .BLKSZ(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.sdram_sz(sdram_sz),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.RTC(rtc),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

wire        scsi_act;
assign LED_DISK = {1'b1, scsi_act};      // the core drives the disk LED: SCSI busy

// each slot's image: there or not, its size in 512-byte blocks (quasi-static for the
// machine: set as an image is mounted); a CD change stretched for the CPU's clock
reg   [2:0] img_present = 3'd0;
reg  [31:0] img_blocks[3];
reg   [3:0] cd_change_s = 4'd0;
always @(posedge clk_mem) begin
	cd_change_s <= {cd_change_s[2:0], 1'b0};
	for (int n = 0; n < 3; n++)
		if (img_mounted[n]) begin
			img_present[n] <= img_size != 64'd0;
			img_blocks[n]  <= img_size[40:9];
			if (n == 2) cd_change_s <= 4'hF;
		end
end

///////////////////////   OPTIONS, ROM AND RESET (memory clock)   ///////////////////////////////

// the RAM: the OSD's size as SIMM pairs (3 bits a pair, pair 0 lowest: 1 8 MB, 2 16, 3 32,
// 4 64; IBMRS6K7248_machine), no more than the SDRAM holds beside the ROM: 24 MB on a
// 32 MB board, 56 on a 64 MB one, 112 on a 128 MB one
localparam [8:0] SIMM_16 = 9'o002, SIMM_24 = 9'o012, SIMM_32 = 9'o003, SIMM_48 = 9'o023,
                 SIMM_56 = 9'o123, SIMM_64 = 9'o004, SIMM_96 = 9'o034, SIMM_112 = 9'o234;
wire [8:0] simm_max = sdram_mod == 2'd3 ? SIMM_112 : sdram_mod == 2'd2 ? SIMM_56 : SIMM_24;
wire [1:0] mod_rank = sdram_mod == 2'd3 ? 2'd2 : sdram_mod == 2'd2 ? 2'd1 : 2'd0;
reg  [8:0] simm_sel;
reg  [1:0] sel_rank;                       // the smallest board the choice fits
always @(*) begin
	case (status[3:1])
		3'd1:    begin simm_sel = SIMM_16; sel_rank = 2'd0; end
		3'd2:    begin simm_sel = SIMM_32; sel_rank = 2'd1; end
		3'd3:    begin simm_sel = SIMM_48; sel_rank = 2'd1; end
		3'd4:    begin simm_sel = SIMM_64; sel_rank = 2'd2; end
		3'd5:    begin simm_sel = SIMM_96; sel_rank = 2'd2; end
		default: begin simm_sel = simm_max; sel_rank = 2'd0; end
	endcase
end
reg [8:0] simm_opt;
always @(posedge clk_mem) simm_opt <= sel_rank > mod_rank ? simm_max : simm_sel;

// the ROM upload: index 0 a boot.rom loaded at start, index 1 from the OSD; into the
// board's top 4 MB. Its length decides the second socket: with 512 KB, FFF80000-FFFFFFFF reads empty.
wire rom_index = ioctl_index[7:0] == 8'd0 || ioctl_index[7:0] == 8'd1;
wire rom_wr    = ioctl_download & rom_index & ioctl_wr;
reg  rom_loaded = 0, dl_q = 0, rom_dl = 0;
reg  rom_big = 0;                           // a byte beyond 512 KB came
wire [4:0] rom_at = {sdram_mod == 2'd3, sdram_mod[1], 3'b111};   // 4 MB units: 7, 15 or 31
always @(posedge clk_mem) begin
	dl_q <= ioctl_download;
	if (ioctl_download & ~dl_q & rom_index) begin
		rom_dl     <= 1;
		rom_loaded <= 0;
		rom_big    <= 0;
		sdram_mod  <= (sdram_sz[15] && sdram_sz[1:0] != 2'd0) ? sdram_sz[1:0] : 2'd1;
	end
	if (rom_wr && ioctl_addr[26:19] != 8'd0) rom_big <= 1;
	if (~ioctl_download & dl_q & rom_dl) begin rom_dl <= 0; rom_loaded <= 1; end
end
wire sd_up_busy;
assign ioctl_wait = sd_up_busy;

reg  [1:0] locked_m = 0;
always @(posedge clk_mem) locked_m <= {locked_m[0], pll_locked};
wire sdram_init = ~locked_m[1];
wire sdram_ready;

reg  [2:0] reset_in;
// the 8042's reset line (a pulse in the CPU's clock) resets the whole machine: held for
// 256 CPU clocks there, then into this clock
wire       kbc_reset;
reg  [7:0] kbc_rst_hold = 0;
always @(posedge clk_cpu) begin
	if (kbc_reset) kbc_rst_hold <= 8'hFF;
	else if (kbc_rst_hold != 0) kbc_rst_hold <= kbc_rst_hold - 1'd1;
end
reg  [1:0] kbc_rst_s;
always @(posedge clk_mem) kbc_rst_s <= {kbc_rst_s[0], kbc_rst_hold != 0};
always @(posedge clk_mem) reset_in <= {reset_in[1:0], RESET | status[0] | buttons[1] | kbc_rst_s[1]};

reg cpu_reset_m = 1;
always @(posedge clk_mem) cpu_reset_m <= reset_in[2] | ~sdram_ready | rom_dl | ~rom_loaded;

// the options taken under reset
reg [8:0] simm_cfg = SIMM_16;
reg       rom_512k = 1;
always @(posedge clk_mem) if (cpu_reset_m) begin
	simm_cfg <= simm_opt;
	rom_512k <= ~rom_big;
end

// into the CPU's clock (quasi-static: they change only with the reset held)
reg [2:0] cpu_reset_s = 3'b111;
reg [8:0] simm_c [2];
reg [4:0] rom_at_c [2];
reg [1:0] rom_512k_c;
always @(posedge clk_cpu) begin
	cpu_reset_s <= {cpu_reset_s[1:0], cpu_reset_m};
	simm_c[0]   <= simm_cfg;
	simm_c[1]   <= simm_c[0];
	rom_at_c[0] <= rom_at;
	rom_at_c[1] <= rom_at_c[0];
	rom_512k_c  <= {rom_512k_c[0], rom_512k};
end
wire cpu_reset = cpu_reset_s[2];

// the RTC set from the MiSTer's clock each time hps_io sends it (its toggle crossed into
// the CPU's clock; the time is steady well before the toggle moves)
reg [2:0] rtc_tog_s;
reg       rtc_set_c = 0;
always @(posedge clk_cpu) begin
	rtc_tog_s <= {rtc_tog_s[1:0], rtc[64]};
	rtc_set_c <= rtc_tog_s[2] != rtc_tog_s[1];
end

///////////////////////   THE MACHINE   ///////////////////////////////

wire         b_req, b_we, b_line, b_ack;
wire [31:2]  b_addr;
wire  [3:0]  b_be;
wire [255:0] b_wdata, b_rdata;
wire         trace_valid, trace_last;
wire [31:0]  trace_pc, trace_msr, trace_lr, trace_ctr;
wire         trace_reg_we;
wire [6:0]   trace_reg_idx;
wire [63:0]  trace_reg_val;
wire        com1_txd;
wire        io_ev, io_we;
wire [31:0] io_addr, io_wdata, io_rdata;
wire [3:0]  io_be;
wire         vid_ce, vid_hs, vid_vs, vid_hblank, vid_vblank;
wire   [7:0] vid_r, vid_g, vid_b;
assign DDRAM_CLK = clk_mem;

IBMRS6K7248_system #(.CPU_HZ(CPU_MHZ * 1_000_000), .TB_HZ(TB_HZ)) system
(
	.clk(clk_cpu),
	.reset(cpu_reset),
	.reset_pc(32'hFFF00100),
	.simm_cfg(simm_c[1]),
	.rom_at(rom_at_c[1]),
	.rom_512k(rom_512k_c[1]),
	.planar_id(8'hF5),                      // a 7248-100 (the OSD's model choice to come)

	.clk_b(clk_mem),
	.reset_b(cpu_reset_m),
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata,

	.ps2_key, .ps2_mouse,
	.rtc_set(rtc_set_c),
	.rtc_time(rtc[55:0]),
	.speaker, .kbc_reset,

	// the S3's VRAM in DDR3 and its picture, in the memory clock
	.ddr_busy(DDRAM_BUSY), .ddr_burstcnt(DDRAM_BURSTCNT), .ddr_addr(DDRAM_ADDR), .ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY), .ddr_rd(DDRAM_RD), .ddr_din(DDRAM_DIN), .ddr_be(DDRAM_BE), .ddr_we(DDRAM_WE),
	.vid_ce, .vid_r, .vid_g, .vid_b, .vid_hs, .vid_vs, .vid_hblank, .vid_vblank,

	.com1_txd(com1_txd),
	.com1_rxd(UART_RXD),
	.com1_cts_n(~UART_CTS),
	.com1_rts_n(),

	.img_present, .img_blocks, .sd_lba, .sd_blk_cnt, .sd_rd, .sd_wr, .sd_ack,
	.sd_buff_addr, .sd_buff_dout, .sd_buff_din, .sd_buff_wr,
	.cd_change(|cd_change_s), .scsi_activity(scsi_act),

	.io_ev, .io_we, .io_stub(), .io_addr, .io_be, .io_wdata, .io_rdata,
	.trace_valid, .trace_last, .trace_pc, .trace_insn(), .trace_msr, .trace_lr, .trace_ctr,
	.trace_reg_we, .trace_reg_idx, .trace_reg_val,
	.trace_dreq(), .trace_dwe(), .trace_daddr()
);
assign UART_RTS = 0;
assign UART_DTR = UART_DSR;

///////////////////////   SDRAM   ///////////////////////////////

wire [15:0] sd_dq_out;
wire        sd_dq_oe;
assign SDRAM_DQ = sd_dq_oe ? sd_dq_out : 16'hZZZZ;

IBMRS6K7248_sdram #(.CLK_MHZ(100)) sdram
(
	.clk(clk_mem),
	.init(sdram_init),
	.ready(sdram_ready),

	.req(b_req), .we(b_we), .line(b_line), .addr(b_addr[26:2]), .be(b_be), .wdata(b_wdata),
	.ack(b_ack), .rdata(b_rdata),

	.up_wr(rom_wr),
	.up_addr({rom_at, ioctl_addr[21:0]}),    // the board's top 4 MB
	.up_data(ioctl_dout),
	.up_busy(sd_up_busy),

	.SDRAM_A, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nRAS, .SDRAM_nCAS, .SDRAM_nWE,
	.SDRAM_DQML, .SDRAM_DQMH, .SDRAM_CKE,
	.dq_out(sd_dq_out), .dq_oe(sd_dq_oe), .dq_in(SDRAM_DQ)
);

// SDRAM_CLK is the memory clock inverted, from a DDR output register, as in
// Sorgelig's sdram.sv
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_mem),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

///////////////////////   THE DEBUG UART   ///////////////////////////////

// The MiSTer's UART carries either COM1 (the firmware's serial console) or, for
// bring-up (OSD "UART", the default), a debug stream at 115200 baud, in the
// CPU's clock: "R" when the CPU leaves reset; every write of a word to port
// 680 (the firmware's progress codes, the code in the first byte, as the bench
// prints them) as two hex digits and a space; "." every 2^24 instructions
// retired (the CPU is alive), with the PC then (".pppppppp "); the PCI configuration accesses ("C8=xxxxxxxx "
// a write of CF8, "cW=" and "cR=" a write and a read of CFC, the data as the
// CPU's); and, from the memory clock, the CPU's word accesses to RAM 7FC
// ("W7=xxxxxxxx ", "R7=xxxxxxxx ") and any word read of RAM 0-7FC that differs
// from the CPU's own last write there ("!aaa=expected/got "). A 4 KB queue in RAM.
wire        post_ev = io_ev & io_we & (io_addr == 32'h8000_0680) & (io_be == 4'hF);
wire        cf8_ev  = io_ev & io_we & (io_addr == 32'h8000_0CF8);
wire        cfc_ev  = io_ev & (io_addr == 32'h8000_0CFC);
wire [31:0] io_d    = io_we ? io_wdata : io_rdata;
reg         cpu_reset_q = 1;
reg  [23:0] alive = 0;
reg  [31:0] alive_pc = 0;                 // the PC at the last alive mark
wire        reset_ev = cpu_reset_q & ~cpu_reset;
wire        alive_ev = trace_valid & trace_last & (&alive);
always @(posedge clk_cpu) begin
	cpu_reset_q <= cpu_reset;
	if (trace_valid & trace_last) alive <= alive + 1'd1;
	if (alive_ev) alive_pc <= trace_pc;
end
// the exceptions other than the external interrupt and the decrementer: a vector (100-400,
// 600-800, F00; not 1000 up, where code runs) reached other than from the instruction before it, at 0 or at FFF00000,
// "Ppppppppp-xxx " ("Q" for FFF00000) with the PC retired before
reg  [31:0] pc_prev = 0;
reg  [31:0] pc_from;
reg  [11:0] pc_to;
reg         pc_rom;
reg         pc_pend = 0;
wire        vec_at = trace_pc[7:0] == 8'h00 && (trace_pc[31:12] == 20'd0 || trace_pc[31:12] == 20'hFFF00) &&
                     trace_pc[11:8] != 4'h0 && trace_pc[11:8] != 4'h5 && trace_pc[11:8] != 4'h9 &&
                     (trace_pc[11:8] <= 4'h8 || trace_pc[11:8] == 4'hF);
wire        pc_hit = trace_valid & trace_last & vec_at & (pc_prev != trace_pc - 32'd4);
always @(posedge clk_cpu) begin
	if (trace_valid & trace_last) pc_prev <= trace_pc;
	if (pc_hit) begin pc_from <= pc_prev; pc_to <= trace_pc[11:0]; pc_rom <= trace_pc[31]; end
end
// an exception after the boot hand-off (progress 2F), once, the one from the PC below: LR, CTR and MSR as its vector
// retires ("IL=... C=... M=..."), then that and the next 39 instructions retired,
// "pppp=vvvvvvvv " (the PC's low half and the GPR each wrote, "--------" none)
reg         isi_armed = 0, isi_done = 0;
reg  [5:0]  isi_n = 0, isi_w = 0, isi_r = 0;
reg  [15:0] isi_pc [40];
reg  [31:0] isi_v [40];
reg  [39:0] isi_vw = 0;
reg  [31:0] isi_lr, isi_ctr, isi_msr;
reg  [1:0]  isi_hdr = 0;                  // header parts left to send (3: all)
// once user code runs after the hand-off (a PC in segments 1-7): the next 250 device accesses,
// "waaaa=dddddddd " ("r"/"w" for ISA I/O at 8000xxxx, "R"/"W" otherwise; the address's low half)
reg         usr_on = 0;
reg  [7:0]  usr_n = 8'd250;
reg         usr_pend = 0, usr_we, usr_isa;
reg  [15:0] usr_a;
reg  [31:0] usr_d;
wire        isi_go = pc_hit & isi_armed & ~isi_done & (pc_prev == 32'h0025616C);   // (the AIX kernel's page copy: DSI there over and over)
always @(posedge clk_cpu) begin
	if (post_ev && io_wdata[31:24] == 8'h2F) isi_armed <= 1'b1;
	if (trace_valid && trace_last && (isi_go || isi_n != 6'd0)) begin
		isi_pc[isi_w]  <= trace_pc[15:0];
		isi_v[isi_w]   <= trace_reg_val[31:0];
		isi_vw[isi_w]  <= trace_reg_we & ~trace_reg_idx[6] & ~trace_reg_idx[5];
		isi_w          <= isi_w + 6'd1;
		isi_n          <= isi_go ? 6'd39 : isi_n - 6'd1;
	end
	if (isi_go) begin isi_done <= 1'b1; isi_lr <= trace_lr; isi_ctr <= trace_ctr; isi_msr <= trace_msr; end
	if (isi_armed && trace_valid && trace_last && trace_pc[31] == 1'b0 && trace_pc[30:28] != 3'd0) usr_on <= 1'b1;
end

// the memory port (the memory clock): the word accesses to 7FC, and the shadow of the
// CPU's word writes to 0-7FC compared with every word read there
wire        mem_ev = b_req & b_ack & ~b_line & (b_addr[31:2] == 30'h1FF);
wire        low_w  = b_req & b_ack & ~b_line & b_we & (b_addr[31:11] == 21'd0);
wire        low_r  = b_req & b_ack & ~b_line & ~b_we & (b_addr[31:11] == 21'd0);
reg  [31:0] shadow [512];
reg  [31:0] shadow_q;
reg         cmp_pend = 0;
reg  [31:0] cmp_got;
reg  [10:2] cmp_addr;
reg         m_tog = 0;                    // flips with every event carried over
reg         m_mis = 0, m_we = 0;          // the event: a mismatch, else an access to 7FC (write or read)
reg  [31:0] m_d, m_exp;
reg  [10:2] m_addr;
always @(posedge clk_mem) begin
	if (low_w) shadow[b_addr[10:2]] <= b_wdata[31:0];
	shadow_q <= shadow[b_addr[10:2]];
	cmp_pend <= low_r;
	cmp_got  <= b_rdata[31:0];
	cmp_addr <= b_addr[10:2];
	if (cmp_pend && cmp_got != shadow_q) begin
		m_tog <= ~m_tog; m_mis <= 1'b1; m_d <= cmp_got; m_exp <= shadow_q; m_addr <= cmp_addr;
	end
	else if (mem_ev) begin
		m_tog <= ~m_tog; m_mis <= 1'b0; m_we <= b_we; m_d <= b_we ? b_wdata[31:0] : b_rdata[31:0];
	end
end
reg  [2:0]  m_s = 0;
always @(posedge clk_cpu) m_s <= {m_s[1:0], m_tog};
wire        m_ev = m_s[2] ^ m_s[1];       // (the latched data stands still long enough: one event in 512)

function automatic [7:0] hex(input [3:0] n);
	hex = n < 4'd10 ? 8'h30 + {4'd0, n} : 8'h37 + {4'd0, n};
endfunction
function automatic [63:0] hex8(input [31:0] v);
	hex8 = {hex(v[31:28]), hex(v[27:24]), hex(v[23:20]), hex(v[19:16]), hex(v[15:12]), hex(v[11:8]), hex(v[7:4]), hex(v[3:0])};
endfunction

localparam logic [15:0] UART_DIV1 = 16'(CPU_MHZ * 1_000_000 / 115_200 - 1);   // clocks per bit, less one
reg  [7:0]   dq [4096];                   // the byte queue (a RAM: one byte in a clock)
reg  [11:0]  dq_w = 0, dq_r = 0;
reg  [111:0] stage;                       // the bytes being queued, the first in the top byte
reg  [3:0]   stage_n = 0;                 // ... how many are left
reg  [31:0]  mis_got;                     // a mismatch's second half, queued after its first
reg          mis_half = 0;
reg          post_pend = 0, reset_pend = 0, alive_pend = 0, m_pend = 0;   // events seen while the stage was busy
reg  [7:0]   post_code;
reg  [31:0]  post_pc;                     // the PC before a code written from outside 7000-7FFF (else 0)
reg          k92_pend = 0;
reg  [7:0]   k92_d;
wire         k92_ev = io_ev & io_we & (io_addr[31:2] == 30'h2000_0024) & io_be[1];   // port 92 (the byte in bits 15-8)
always @(posedge clk_cpu) begin
	if (post_ev) begin post_code <= io_wdata[31:24]; post_pc <= pc_prev[31:12] == 20'h00007 ? 32'd0 : pc_prev; end
	if (k92_ev) k92_d <= io_wdata[15:8];
	k92_pend   <= k92_pend | k92_ev;
	if (isi_go) isi_hdr <= 2'd3;
	if (usr_on && usr_n != 8'd0 && io_ev && !post_ev && !usr_pend) begin
		usr_pend <= 1'b1; usr_we <= io_we; usr_isa <= io_addr[31:16] == 16'h8000; usr_a <= io_addr[15:0];
		usr_d <= io_we ? io_wdata : io_rdata; usr_n <= usr_n - 8'd1;
	end
	post_pend  <= post_pend  | post_ev;
	reset_pend <= reset_pend | reset_ev;
	alive_pend <= alive_pend | alive_ev;
	m_pend     <= m_pend     | m_ev;
	pc_pend    <= pc_pend    | pc_hit;
	if (stage_n != 4'd0) begin             // (a full queue holds the stage: the first 4 KB win, later events are dropped)
		if (dq_w + 12'd1 != dq_r) begin
			dq[dq_w] <= stage[111:104];
			dq_w     <= dq_w + 12'd1;
			stage    <= {stage[103:0], 8'h00};
			stage_n  <= stage_n - 4'd1;
		end
	end
	else if (mis_half) begin
		stage_n  <= 4'd9;
		stage    <= {hex8(mis_got), 8'h20, 40'h0};
		mis_half <= 1'b0;
	end
	else if (cf8_ev | cfc_ev) begin        // (a configuration access during a drain is lost)
		stage_n <= 4'd12;
		stage   <= {cf8_ev ? 8'h43 : 8'h63, cf8_ev ? 8'h38 : io_we ? 8'h57 : 8'h52, 8'h3D, hex8(io_d), 8'h20, 16'h0};
	end
	else if (m_pend | m_ev) begin
		m_pend <= 1'b0;
		if (m_mis) begin
			stage_n  <= 4'd14;
			stage    <= {8'h21, hex({1'b0, m_addr[10:8]}), hex(m_addr[7:4]), hex({m_addr[3:2], 2'b00}), 8'h3D, hex8(m_exp), 8'h2F};
			mis_got  <= m_d;
			mis_half <= 1'b1;
		end else begin
			stage_n <= 4'd12;
			stage   <= {m_we ? 8'h57 : 8'h52, 8'h37, 8'h3D, hex8(m_d), 8'h20, 16'h0};
		end
	end
	else if (isi_hdr != 2'd0) begin
		stage_n <= 4'd12;
		stage   <= {isi_hdr == 2'd3 ? 16'h494C : isi_hdr == 2'd2 ? 16'h2043 : 16'h204D, 8'h3D,
		            hex8(isi_hdr == 2'd3 ? isi_lr : isi_hdr == 2'd2 ? isi_ctr : isi_msr), 8'h20, 16'h0};
		isi_hdr <= isi_hdr - 2'd1;
	end
	else if (isi_done && isi_n == 6'd0 && isi_r != isi_w) begin
		stage_n <= 4'd14;
		stage   <= {hex(isi_pc[isi_r][15:12]), hex(isi_pc[isi_r][11:8]), hex(isi_pc[isi_r][7:4]), hex(isi_pc[isi_r][3:0]), 8'h3D,
		            isi_vw[isi_r] ? hex8(isi_v[isi_r]) : {8{8'h2D}}, 8'h20};
		isi_r   <= isi_r + 6'd1;
	end
	else if (usr_pend) begin
		stage_n  <= 4'd14;
		stage    <= {usr_isa ? (usr_we ? 8'h77 : 8'h72) : (usr_we ? 8'h57 : 8'h52), hex(usr_a[15:12]), hex(usr_a[11:8]),
		             hex(usr_a[7:4]), hex(usr_a[3:0]), 8'h3D, hex8(usr_d), 8'h20};
		usr_pend <= 1'b0;
	end
	else if (pc_pend) begin
		pc_pend <= 1'b0;
		stage_n <= 4'd14;
		stage   <= {pc_rom ? 8'h51 : 8'h50, hex8(pc_from), 8'h2D, hex(pc_to[11:8]), hex(pc_to[7:4]), hex(pc_to[3:0]), 8'h20};
	end
	else if (k92_pend) begin stage_n <= 4'd5; stage <= {8'h4B, 8'h3D, hex(k92_d[7:4]), hex(k92_d[3:0]), 8'h20, 72'h0}; k92_pend <= 1'b0; end
	else if ((post_pend | post_ev) && post_pc != 32'd0) begin
		stage_n <= 4'd12; stage <= {hex(post_code[7:4]), hex(post_code[3:0]), 8'h40, hex8(post_pc), 8'h20, 16'h0}; post_pend <= 1'b0;
	end
	else if (post_pend | post_ev)   begin stage_n <= 4'd3; stage <= {hex(post_code[7:4]), hex(post_code[3:0]), 8'h20, 88'h0}; post_pend <= 1'b0; end
	else if (reset_pend | reset_ev) begin stage_n <= 4'd3; stage <= {8'h0D, 8'h0A, 8'h52, 88'h0}; reset_pend <= 1'b0; end
	else if (alive_pend | alive_ev) begin stage_n <= 4'd10; stage <= {8'h2E, hex8(alive_pc), 8'h20, 24'h0}; alive_pend <= 1'b0; end
end
// the transmitter: a byte fetched from the RAM a clock ahead
reg  [9:0]  tx_sh = 10'h3FF;              // start, 8 data, stop
reg  [3:0]  tx_n = 0;                     // bits left
reg  [15:0] tx_div = 0;
reg  [7:0]  tx_byte;
reg         tx_have = 0;
reg         post_txd = 1;
always @(posedge clk_cpu) begin
	if (!tx_have && dq_r != dq_w) begin tx_byte <= dq[dq_r]; dq_r <= dq_r + 12'd1; tx_have <= 1'b1; end
	if (tx_n == 4'd0) begin
		post_txd <= 1'b1;
		if (tx_have) begin
			tx_sh   <= {1'b1, tx_byte, 1'b0};
			tx_n    <= 4'd10;
			tx_div  <= 16'd0;
			tx_have <= 1'b0;
		end
	end else if (tx_div == UART_DIV1) begin
		tx_div   <= 16'd0;
		post_txd <= tx_sh[0];
		tx_sh    <= {1'b1, tx_sh[9:1]};
		tx_n     <= tx_n - 4'd1;
	end else tx_div <= tx_div + 16'd1;
end
assign UART_TXD = status[4] ? com1_txd : post_txd;

///////////////////////   THE LED   ///////////////////////////////

// the CPU's heartbeat: it toggles every 2^20 instructions retired
reg [20:0] retired = 0;
always @(posedge clk_cpu) begin
	if (trace_valid & trace_last) retired <= retired + 1'd1;
	if (cpu_reset) retired <= 0;
end
assign LED_USER = retired[20];

///////////////////////   THE PICTURE   ///////////////////////////////

// the S3's scan-out (IBMRS6K7248_s3video), in the memory clock; the framework's scaler takes it
assign CLK_VIDEO = clk_mem;
assign CE_PIXEL  = vid_ce;
assign VGA_DE    = ~(vid_hblank | vid_vblank);
assign VGA_HS    = vid_hs;
assign VGA_VS    = vid_vs;
assign VGA_R     = vid_r;
assign VGA_G     = vid_g;
assign VGA_B     = vid_b;

endmodule
