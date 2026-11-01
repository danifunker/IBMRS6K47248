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

`ifdef IBMRS6K7248_CPU58
localparam int CPU_MHZ = 58;                // (a debugging build: the PLL's 58.3, the CPU's paths with room to spare)
`else
localparam int CPU_MHZ = 70;                // the PLL's 70 or 100: the first fit at 100 missed by 6.2 ns (the CPU's paths, as MacPPC7300's, which runs at 70)
`endif
localparam int TB_HZ   = 16_666_667;        // the 604's time base: a quarter of a 66 MHz bus

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
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
wire [15:0] aud_l, aud_r;                // the CS4232's codec and Sound Blaster, signed, in the CPU's clock
wire [15:0] fm_snd;                      // its FM chip (IBMRS6K7248_opl, below)
wire  [7:0] fm_vol;                      // ... at the SB mixer's FM volume (left 7:4, right 3:0)
wire [15:0] mt32_i2s_l, mt32_i2s_r;      // an MT32-pi's synth (CLK_AUDIO)
wire        mt32_use;
// the mix, in the audio clock: the codec and Sound Blaster, the FM chip, the speaker (as the planar's
// amplifier mixes it), the MT32-pi; clipped
reg  [15:0] a_cs_l, a_cs_r, a_fm, a_cs_l2, a_cs_r2, a_fm2;
reg   [7:0] a_fv, a_fv2;
reg         a_spk, a_spk2;
always @(posedge CLK_AUDIO) begin
	{a_cs_l, a_cs_l2} <= {a_cs_l2, aud_l};
	{a_cs_r, a_cs_r2} <= {a_cs_r2, aud_r};
	{a_fm, a_fm2}     <= {a_fm2, fm_snd};
	{a_fv, a_fv2}     <= {a_fv2, fm_vol};
	{a_spk, a_spk2}   <= {a_spk2, speaker};
end
wire signed [15:0] fm_l = 16'(($signed(a_fm) * $signed({1'b0, a_fv[7:4], 4'h0})) >>> 8);
wire signed [15:0] fm_r = 16'(($signed(a_fm) * $signed({1'b0, a_fv[3:0], 4'h0})) >>> 8);
wire signed [17:0] mix_l = $signed(a_cs_l) + fm_l + (a_spk ? 18'sh00800 : 18'sh0) + (mt32_use ? $signed(mt32_i2s_l) : 18'sh0);
wire signed [17:0] mix_r = $signed(a_cs_r) + fm_r + (a_spk ? 18'sh00800 : 18'sh0) + (mt32_use ? $signed(mt32_i2s_r) : 18'sh0);
reg  [15:0] out_l, out_r;
always @(posedge CLK_AUDIO) begin
	out_l <= mix_l > 18'sd32767 ? 16'h7FFF : mix_l < -18'sd32768 ? 16'h8000 : mix_l[15:0];
	out_r <= mix_r > 18'sd32767 ? 16'h7FFF : mix_r < -18'sd32768 ? 16'h8000 : mix_r[15:0];
end
assign AUDIO_L = out_l;
assign AUDIO_R = out_r;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////


`include "build_id.v"
// The OSD as the computer cores' standard has it (hp9000-715_MiSTer docs/osd-standard.md): the media and
// Load ROM, Memory, the submenus by their fixed pages (P2 Video, P3 Input, P5 Advanced, P9 Debug in a
// debug build), "Changes pending" and Apply and reset. Media and Input act at once; the rest waits for
// a reset. The status bits are the earlier OSD's, so saved settings carry over.
localparam CONF_STR = {
	"IBMRS6K7248;UART115200:57600:38400:19200:9600;",
	"-;",
	// (SC: the Main remembers each image and mounts it again at the next core load)
	"SC0,IMGHDAVHD,Pri. disk (ID 0);",
	"SC1,IMGHDAVHD,Disk (ID 1);",
	"SC2,ISOBINCUECHD,CD-ROM (ID 3);",
	"SC4,IMGIMAVFD,Floppy;",
	"F1,ROMBINIMG,Load ROM;",
	"-;",
	// the RAM as the board's SIMM pairs, beside the ROM (the SDRAM's top 4 MB); a size the
	// SDRAM cannot hold gives the most it can (24, 56 or 112 MB). 32 MB first: AIX's least
	"O[3:1],Memory,32MB,48MB,56MB,64MB,96MB,112MB,16MB,24MB;",
	// the Main's Ethernet bridge reads it itself (support/ibmrs6k: "[8:6]"), so it acts at once
	"O[8:6],Network interface,eth0,None,eth1,macvlan,tap0;",
	"-;",
	"P2,Video;",
	"P3,Input;",
	"P4,Audio;",
	"P5,Advanced;",
	"-;",
	"h0-,Changes pending;",
	"R[0],Apply and reset;",

	"P2O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[124:123],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",

	"P3O[5],Swap Alt/Win keys,No,Yes;",

	// the MPU-401's MIDI to an MT32-pi on the user port (sys/mt32pi.sv; these act at once)
	"P4O[9],Use MT32-pi,Yes,No;",
	"P4O[10],Synth,Munt,FluidSynth;",
	"P4H1O[12:11],Munt ROM,MT-32 v1,MT-32 v2,CM-32L;",
	"P4h1O[15:13],SoundFont,0,1,2,3,4,5,6,7;",

	"P5SC3,NVR,NVRAM image;",
	// the planar ID (port 0852): the same firmware is a 7248 (F5) or a Power Series 850 (F1, the IDE planar:
	// "IBM PPS Model 6050/6070"), which OS/2 PPC knows by name; the 53C810 stays either way
	"P5O[16],Model,7248-100,Power Series 850;",

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
wire   [7:0] uart_mode;                  // the System page's UART mode: 0 None, 1 PPP, 2 Console, 3 MIDI, 4 Modem
// the settings the machine runs with (taken at reset: below), and "Changes pending"
reg  [127:0] cfg = 128'd0;
// (status bit 4 was the UART's source: now the System page's UART mode, below)
wire         pending = {status[16], status[3:1], status[122:121]} != {cfg[16], cfg[3:1], cfg[122:121]};

wire [1:0] ar = cfg[122:121];
// (the ratio is the framework's video_freak's input, beside the picture below)
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;
wire [15:0] sdram_sz;
wire [31:0] joystick_0, joystick_1;   // the CS4232's joystick port's sticks
wire [15:0] joystick_l_analog_0, joystick_l_analog_1;
wire [10:0] ps2_key;                  // {toggle, pressed, extended, set 2 code}, from the Main
wire [10:0] ps2_key_m;                // ... to the machine: Swap Alt/Win keys applied
wire [24:0] ps2_mouse;
wire [64:0] rtc;                      // BCD: seconds, minutes, hours, date, month, year, weekday; [64] toggles                 // the Main's SDRAM board: [15] known, [1:0] 1 32 MB, 2 64 MB, 3 128 MB
reg   [1:0] sdram_mod = 2'd1;         // the board the ROM went into (an unknown one taken as 32 MB)

// hps_io's block devices (8-bit, 512-byte blocks): 0-2 the SCSI devices' images, 3 the NVRAM file, 4 the floppy
wire  [4:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba[5];
wire  [5:0] sd_blk_cnt[5];
wire  [4:0] sd_rd, sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[5];
wire        sd_buff_wr;
// the RTC's maintenance port, to the NVRAM file's keeper (IBMRS6K7248_nvsave, below)
wire [12:0] nv_m_addr;
wire        nv_m_we, nv_m_ok;
wire  [7:0] nv_m_wdata, nv_m_q, nv_wr_seq;
// the SCSI's three (the machine's)
wire [31:0] scsi_lba[3];
wire  [5:0] scsi_blk_cnt[3];
wire  [7:0] scsi_buff_din[3];
genvar gi;
generate for (gi = 0; gi < 3; gi++) begin : sd_scsi
	assign sd_lba[gi]      = scsi_lba[gi];
	assign sd_blk_cnt[gi]  = scsi_blk_cnt[gi];
	assign sd_buff_din[gi] = scsi_buff_din[gi];
end endgenerate

hps_io #(.CONF_STR(CONF_STR), .VDNUM(5), .BLKSZ(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.uart_mode(uart_mode),
	.status_menumask({14'd0, status[10], pending}),   // bit 0: "Changes pending"; bit 1: FluidSynth (SoundFont, not Munt ROM)
	.joystick_0, .joystick_1, .joystick_l_analog_0, .joystick_l_analog_1,
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

// the RAM: the OSD's size (taken at reset below: simm_cfg) as SIMM pairs (3 bits a pair, pair 0 lowest: 1 8 MB, 2 16, 3 32,
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
		3'd0:    begin simm_sel = SIMM_32;  sel_rank = 2'd1; end
		3'd1:    begin simm_sel = SIMM_48;  sel_rank = 2'd1; end
		3'd2:    begin simm_sel = SIMM_56;  sel_rank = 2'd1; end
		3'd3:    begin simm_sel = SIMM_64;  sel_rank = 2'd2; end
		3'd4:    begin simm_sel = SIMM_96;  sel_rank = 2'd2; end
		3'd5:    begin simm_sel = SIMM_112; sel_rank = 2'd2; end
		3'd6:    begin simm_sel = SIMM_16;  sel_rank = 2'd0; end
		default: begin simm_sel = SIMM_24;  sel_rank = 2'd0; end
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

// the settings the machine runs with: the OSD's, taken while the machine is in reset (Apply and
// reset, the board's reset, a core load, a ROM load). "Changes pending" while an OSD setting differs:
// Memory, Aspect ratio (not Swap Alt/Win keys, an Input setting: it acts at once)
always @(posedge clk_mem) if (cpu_reset_m) cfg <= status;

// Swap Alt/Win keys (live): left Alt (11) and left Win (E0 1F), right Alt (E0 11) and right Win (E0 27)
wire       alt_l = ps2_key[8:0] == 9'h011, win_l = ps2_key[8:0] == 9'h11F;
wire       alt_r = ps2_key[8:0] == 9'h111, win_r = ps2_key[8:0] == 9'h127;
assign ps2_key_m = !status[5] ? ps2_key :
                   alt_l ? {ps2_key[10:9], 9'h11F} : win_l ? {ps2_key[10:9], 9'h011} :
                   alt_r ? {ps2_key[10:9], 9'h127} : win_r ? {ps2_key[10:9], 9'h111} : ps2_key;

// the options taken under reset
reg [8:0] simm_cfg = SIMM_16;
reg       rom_512k = 1;
reg [7:0] planar = 8'hF5;
always @(posedge clk_mem) if (cpu_reset_m) begin
	simm_cfg <= simm_opt;
	rom_512k <= ~rom_big;
	planar   <= status[16] ? 8'hF1 : 8'hF5;
end

// into the CPU's clock (quasi-static: they change only with the reset held)
reg [2:0] cpu_reset_s = 3'b111;
reg [8:0] simm_c [2];
reg [4:0] rom_at_c [2];
reg [1:0] rom_512k_c;
reg [7:0] planar_c [2];
always @(posedge clk_cpu) begin
	cpu_reset_s <= {cpu_reset_s[1:0], cpu_reset_m};
	simm_c[0]   <= simm_cfg;
	simm_c[1]   <= simm_c[0];
	rom_at_c[0] <= rom_at;
	rom_at_c[1] <= rom_at_c[0];
	rom_512k_c  <= {rom_512k_c[0], rom_512k};
	planar_c[0] <= planar;
	planar_c[1] <= planar_c[0];
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
wire [31:0]  trace_pc, trace_insn, trace_msr, trace_lr, trace_ctr;
wire         trace_reg_we;
wire [6:0]   trace_reg_idx;
wire [63:0]  trace_reg_val;
wire         t_dreq, t_dwe;
wire [31:2]  t_daddr;
wire        com1_txd;
wire        io_ev, io_we, io_ncr;
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
	.planar_id(planar_c[1]),                // the OSD's Model: F5 a 7248-100, F1 a Power Series 850

	.clk_b(clk_mem),
	.reset_b(cpu_reset_m),
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata,

	.ps2_key(ps2_key_m), .ps2_mouse,
	.rtc_set(rtc_set_c),
	.rtc_time(rtc[55:0]),
	.speaker, .aud_l, .aud_r, .kbc_reset,
	.fm_cs, .fm_we, .fm_a, .fm_wdata, .fm_rdata, .fm_vol,
	.joy1(joystick_0[5:0]), .joy2(joystick_1[5:0]), .ana1(joystick_l_analog_0), .ana2(joystick_l_analog_1),
	.midi_tx, .midi_rx,
	.fd_in, .fd_ro, .fd_blocks, .fd_mounted, .fd_req, .fd_we, .fd_lba, .fd_ack, .fd_buf_a, .fd_buf_q, .fd_buf_we, .fd_buf_d,

	// the S3's VRAM in DDR3 and its picture, in the memory clock
	.net_on(status[8:6] != 3'd1),
	.ddr_busy(DDRAM_BUSY), .ddr_burstcnt(DDRAM_BURSTCNT), .ddr_addr(DDRAM_ADDR), .ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY), .ddr_rd(DDRAM_RD), .ddr_din(DDRAM_DIN), .ddr_be(DDRAM_BE), .ddr_we(DDRAM_WE),
	.vid_ce, .vid_r, .vid_g, .vid_b, .vid_hs, .vid_vs, .vid_hblank, .vid_vblank,

	.com1_txd(com1_txd),
	.com1_rxd(UART_RXD),
	.com1_cts_n(~UART_CTS),
	.com1_rts_n(),

	.img_present, .img_blocks, .sd_lba(scsi_lba), .sd_blk_cnt(scsi_blk_cnt), .sd_rd(sd_rd[2:0]), .sd_wr(sd_wr[2:0]),
	.sd_ack(sd_ack[2:0]), .sd_buff_addr, .sd_buff_dout, .sd_buff_din(scsi_buff_din), .sd_buff_wr,
	.nv_m_addr, .nv_m_we, .nv_m_wdata, .nv_m_q, .nv_m_ok, .nv_wr_seq,
	.cd_change(|cd_change_s), .scsi_activity(scsi_act),
	.hd_st_irq, .hd_st_blk, .hd_st_disk, .hd_st_host,

	.io_ev, .io_we, .io_stub(), .io_ncr, .io_addr, .io_be, .io_wdata, .io_rdata,
	.trace_valid, .trace_last, .trace_pc, .trace_insn, .trace_msr, .trace_lr, .trace_ctr,
	.trace_reg_we, .trace_reg_idx, .trace_reg_val,
	.trace_dreq(t_dreq), .trace_dwe(t_dwe), .trace_daddr(t_daddr)
);
assign UART_RTS = 0;
assign UART_DTR = UART_DSR;

// the CS4232's FM chip: JTOPL's OPL2 behind the OPL3's ports (rtl/IBMRS6K7248_opl.sv), in the CPU's clock
wire        fm_cs, fm_we;
wire  [1:0] fm_a;
wire  [7:0] fm_wdata, fm_rdata;
`ifndef IBMRS6K7248_LITE
IBMRS6K7248_opl #(.CLK_HZ(CPU_MHZ * 1_000_000)) opl (
	.clk(clk_cpu), .reset(cpu_reset), .cs(fm_cs), .we(fm_we), .a(fm_a), .wdata(fm_wdata), .rdata(fm_rdata), .snd(fm_snd)
);
`else
// (a LITE build: no FM chip)
assign fm_rdata = 8'hFF;
assign fm_snd   = '0;
`endif

// the MPU-401's MIDI to an MT32-pi on the user port (the framework's sys/mt32pi.sv), its synth back
wire        midi_tx, midi_rx, mt32_available;
assign      mt32_use = mt32_available & ~status[9];
mt32pi mt32pi (
	.CLK_AUDIO(CLK_AUDIO), .CLK_VIDEO(clk_mem), .CE_PIXEL(vid_ce), .VGA_VS(vid_vs), .VGA_DE(~(vid_hblank | vid_vblank)),
	.USER_IN(USER_IN), .USER_OUT(USER_OUT),
	.reset(cpu_reset_m), .midi_tx(midi_tx | ~mt32_use), .midi_rx(midi_rx),
	.mt32_i2s_r(mt32_i2s_r), .mt32_i2s_l(mt32_i2s_l), .mt32_available(mt32_available),
	.mt32_mode_req(status[10]), .mt32_rom_req(status[12:11]), .mt32_sf_req({5'd0, status[15:13]}),
	.mt32_mode(), .mt32_rom(), .mt32_sf(), .mt32_newmode(), .mt32_lcd_en(), .mt32_lcd_pix(), .mt32_lcd_update()
);

// the floppy image (block device 4): sectors for the floppy controller
wire        fd_in, fd_ro, fd_mounted, fd_req, fd_we, fd_ack, fd_buf_we;
wire [12:0] fd_blocks, fd_lba;
wire  [8:0] fd_buf_a;
wire  [7:0] fd_buf_q, fd_buf_d;
IBMRS6K7248_fdimg fdimg (
	.clk_s(clk_sys), .clk_c(clk_cpu),
	.img_mounted(img_mounted[4]), .img_readonly, .img_size,
	.sd_lba(sd_lba[4]), .sd_blk_cnt(sd_blk_cnt[4]), .sd_rd(sd_rd[4]), .sd_wr(sd_wr[4]), .sd_ack(sd_ack[4]),
	.sd_buff_addr, .sd_buff_dout, .sd_buff_wr, .sd_buff_din(sd_buff_din[4]),
	.img_in(fd_in), .img_ro(fd_ro), .img_blocks(fd_blocks), .mounted(fd_mounted),
	.sec_req(fd_req), .sec_we(fd_we), .sec_lba(fd_lba), .sec_ack(fd_ack),
	.buf_a(fd_buf_a), .buf_q(fd_buf_q), .buf_we(fd_buf_we), .buf_d(fd_buf_d)
);

// the NVRAM and CMOS kept in the NVRAM file (block device 3)
IBMRS6K7248_nvsave nvsave (
	.clk_s(clk_sys), .clk_c(clk_cpu),
	.img_mounted(img_mounted[3]), .img_readonly, .img_size,
	.sd_lba(sd_lba[3]), .sd_blk_cnt(sd_blk_cnt[3]), .sd_rd(sd_rd[3]), .sd_wr(sd_wr[3]), .sd_ack(sd_ack[3]),
	.sd_buff_addr, .sd_buff_dout, .sd_buff_wr, .sd_buff_din(sd_buff_din[3]),
	.m_addr(nv_m_addr), .m_we(nv_m_we), .m_wdata(nv_m_wdata), .m_q(nv_m_q), .m_ok(nv_m_ok), .wr_seq(nv_wr_seq)
);

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
// bring-up (the System page's UART mode None, in a debug build), a debug stream at 115200 baud, in the
// CPU's clock: "R" when the CPU leaves reset; every write of a word to port
// 680 (the firmware's progress codes, the code in the first byte, as the bench
// prints them) as two hex digits and a space; "." every 2^24 instructions
// retired (the CPU is alive), with the PC then (".pppppppp "); the PCI configuration accesses ("C8=xxxxxxxx "
// a write of CF8, "cW=" and "cR=" a write and a read of CFC, the data as the
// CPU's); and, from the memory clock, the CPU's word accesses to RAM 7FC
// ("W7=xxxxxxxx ", "R7=xxxxxxxx ") and any word read of RAM 0-7FC that differs
// from the CPU's own last write there ("!aaa=expected/got "). A 4 KB queue in RAM.
// the stream's optional parts (1 to build them; off for room, 2026-10-29: the floppy and NT's audio are done)
localparam bit DBG_DEVLOG = 1'b0;           // the whole-address device log (NT's audio and video bring-up)
localparam bit DBG_COM1TX = 1'b1;           // COM1's transmitted text in the stream (OS/2's boot talks on COM1)
localparam bit DBG_FLOPPY = 1'b0;           // the floppy's controller, DMA ports and requests to the Main
localparam bit DBG_GPR    = 1'b0;           // the 40 instructions and the GPRs they wrote after the first program exception
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
reg         isi_armed = 0;                // past the boot hand-off (progress 2F)
reg  [31:0] pc_prev = 0;
reg  [31:0] pc_from;
reg  [11:0] pc_to;
reg         pc_rom;
reg         pc_pend = 0;
// (the SCSI build: the external interrupt, 500, too once the boot hand-off is past, to see IRQ 15 taken)
wire        vec_at = trace_pc[7:0] == 8'h00 && (trace_pc[31:12] == 20'd0 || trace_pc[31:12] == 20'hFFF00) &&
                     trace_pc[11:8] != 4'h0 && (trace_pc[11:8] != 4'h5 || isi_armed) && trace_pc[11:8] != 4'h9 &&
                     (trace_pc[11:8] <= 4'h8 || trace_pc[11:8] == 4'hF);
// (not the firmware's DSIs from 7364, its I/O routine's probes: hundreds of them filled the stream)
localparam bit DBG_PC = 1'b0;             // (off in the OS/2 build, for room: COM1 tells; 2026-10-31)
wire        pc_hit = DBG_PC & trace_valid & trace_last & vec_at & (pc_prev != trace_pc - 32'd4) &
                     ~(pc_prev == 32'h0000_7364 && trace_pc[11:0] == 12'h300);
always @(posedge clk_cpu) begin
	if (trace_valid & trace_last) pc_prev <= trace_pc;
	if (pc_hit) begin pc_from <= pc_prev; pc_to <= trace_pc[11:0]; pc_rom <= trace_pc[31]; end
end
// after the boot hand-off (progress 2F), once, when the PC below retires (the first of the AIX kernel's reboot
// syscall 3D830, mdreboot 148E24 and p_slih 3587C, the panic handler: the PCs logged tell which; LR the caller): LR, CTR and MSR as it
// retires ("IL=... C=... M=..."), then that and the next 39 instructions retired,
// "pppp=vvvvvvvv " (the PC's low half and the GPR each wrote, "--------" none)
reg         isi_done = 0;
reg  [5:0]  isi_n = 0, isi_w = 0, isi_r = 0;
reg  [15:0] isi_pc [40];
reg  [31:0] isi_v [40];
reg  [39:0] isi_vw = 0;
reg  [31:0] isi_lr, isi_ctr, isi_msr;
reg  [1:0]  isi_hdr = 0;                  // header parts left to send (3: all)
// (the COM1-rate build) from the hand-off (progress 2F) on, every write to COM1's registers (3F8-3FF):
// "wbaaa=dddddddd " (b the byte lanes, aaa the port, the data as on the bus; the firmware's and AIX's divisor,
// LCR, FCR and THR writes), and the shortest low and high pulses of com1_txd seen so far, in CPU clocks
// ("L=cccccccc ", "H=cccccccc ": a lone bit is one bit time, 7292 clocks at 9600 baud and 70 MHz)
reg         usr_on = 0;
reg  [7:0]  usr_n = 8'd250;
reg         usr_pend = 0, usr_we, usr_isa;
reg  [15:0] usr_a;
reg  [31:0] usr_d;
reg         c1_q = 1'b1;
reg  [31:0] c1_len = 32'd0, c1_minl = 32'hFFFFFFFF, c1_minh = 32'hFFFFFFFF;
reg         c1_evl = 1'b0, c1_evh = 1'b0, c1_pendl = 1'b0, c1_pendh = 1'b0;
// (the OS/2 build) the IDE disk's second, when it moved anything: "Hiiiibbbb " its interrupts and the host's
// blocks, "Mddddhhhh " the milliseconds on the disk side (the SCSI target and the Main's image access) and on
// the host's (its interrupt latency and PIO): where a transfer's time goes (2026-10-31: the install's writes)
wire        hd_st_irq, hd_st_blk, hd_st_disk, hd_st_host;
reg  [16:0] hs_cnt = 17'd0;
reg  [9:0]  hs_ms = 10'd0;
reg  [15:0] hs_irq = 16'd0, hs_blk = 16'd0;
reg  [9:0]  hs_disk = 10'd0, hs_host = 10'd0;
// (the counters stand still from the second's end until the stage has them, a few microseconds: no copies)
wire [31:0] hs_a = {hs_irq, hs_blk}, hs_b = {6'd0, hs_disk, 6'd0, hs_host};
reg         hs_pend = 1'b0, hs_half = 1'b0, hs_take = 1'b0;
always @(posedge clk_cpu) begin
	hs_cnt <= hs_cnt + 17'd1;
	if (hd_st_irq && !hs_pend) hs_irq <= hs_irq + 16'd1;
	if (hd_st_blk && !hs_pend) hs_blk <= hs_blk + 16'd1;
	if (hs_cnt == 17'(CPU_MHZ * 1000 - 1)) begin            // a millisecond: the sides sampled
		hs_cnt <= 17'd0;
		hs_ms  <= hs_ms + 10'd1;
		if (hd_st_disk && !hs_pend) hs_disk <= hs_disk + 10'd1;
		if (hd_st_host && !hs_pend) hs_host <= hs_host + 10'd1;
		if (hs_ms == 10'd999) begin
			hs_ms <= 10'd0;
			if (hs_irq != 16'd0 || hs_blk != 16'd0 || hs_disk != 10'd0) hs_pend <= 1'b1;
		end
	end
	if (hs_take) begin hs_pend <= 1'b0; hs_irq <= 16'd0; hs_blk <= 16'd0; hs_disk <= 10'd0; hs_host <= 10'd0; end
end
always @(posedge clk_cpu) begin
	c1_q   <= com1_txd;
	c1_evl <= 1'b0;
	c1_evh <= 1'b0;
	if (1'b0 && com1_txd != c1_q) begin   // (off in the NT video build, for room: the COM1 bit timing)
		c1_len <= 32'd1;
		if (!c1_q && c1_len < c1_minl) begin c1_minl <= c1_len; c1_evl <= 1'b1; end
		if ( c1_q && c1_len < c1_minh) begin c1_minh <= c1_len; c1_evh <= 1'b1; end
	end
	else if (1'b0 && ~&c1_len) c1_len <= c1_len + 32'd1;   // (off with it: the counter alone was a dozen LABs, 2026-10-31)
end
// (the SCSI and keyboard build) from the hand-off on, through a 64-entry FIFO so a burst is kept,
// "Wbaa=dddddddd " / "Rbaa=dddddddd " (b the byte lanes, aa the offset, the data as on the bus):
// every access to the 53C810's registers where AIX puts them (PCI I/O 0100_0000, CPU 8100_0000-8100_00FF:
// aa 80-FF), to the 8042 (ports 60 and 64: aa 60, 64), and each key event from the Main (hps_io's ps2_key:
// "W000=00000kkk", b 0, kkk its 11 bits: [9] pressed, [8] extended, [7:0] the set 2 code);
// and (the S3 build) the S3's registers, in lower case "wbaa=" / "rbaa=": the VGA ports 3C0-3DF (aa C0-DC)
// and the enhanced registers xxE8 (aa the port's high byte: 42 46 4A 82 ... 9A ... E2; 9AE8 the busy status)
reg  [45:0] nq [64];                      // {s3, we, be, offset, data}
reg  [5:0]  nq_w = 0, nq_r = 0;
// (and, for ARC and NT, any access to the 53C810's I/O BAR wherever they place it: io_ncr)
// (DBG_IDEFW: from reset on, the firmware's IDE writes: 170-177, 1F0-1F7 and 370-377, 3F0-3F7, as "Wbaa=",
// to see its ATAPI boot of the CD-ROM; the reads are its polls and would fill the FIFO)
localparam bit DBG_IDEFW = 1'b0;             // (on in build os2z/os2aa, 2026-11-01)
wire        idefw_ev = DBG_IDEFW & io_ev & io_we & (io_addr[31:3] == 29'h1000_002E || io_addr[31:3] == 29'h1000_003E ||
                                                    io_addr[31:3] == 29'h1000_006E || io_addr[31:3] == 29'h1000_007E);
wire        ncr_ev = (isi_armed & io_ev & (io_ncr || io_addr[31:8] == 24'h810000 ||
                                         (io_addr[31:3] == 29'h1000_000C && (io_we || !io_addr[2])))) |   // (not the 8042's status polls)
                     idefw_ev;
// (not the reads of 3DA, input status 1: AIX's X server polls it without end and they filled the FIFO)
wire        s3v_ev = isi_armed & io_ev & (io_addr[31:5] == 27'h400_001E) & ~(~io_we & io_addr[7:0] == 8'hD8);   // 8000_03C0-8000_03DF
wire        s3e_ev = isi_armed & io_ev & io_addr[31:16] == 16'h8000 && io_addr[9:2] == 8'hBA;   // 8000_xxE8
reg  [2:0]  pk_s = 0;                     // ps2_key[10] (it toggles once a key event) into this clock
always @(posedge clk_cpu) pk_s <= {pk_s[1:0], ps2_key[10]};
wire        pk_ev = isi_armed & (pk_s[2] ^ pk_s[1]);   // (the other bits stand still long before the toggle)
// and, from the start, the floppy: the controller's FIFO (3F5, "W4F4=00cc0000" / "R4F4=00rr0000": the
// command and result bytes), the writes of the DMA controller's ports 00-0F, 80-83 and 480-483 ("W800=",
// "W480=" ...; 480's as offset 48), and each request of the image to the Main ("W0FD=", the data
// {write, 12'd0, blocks less one (6 bits), the LBA (13 bits)})
// (and 3F7 both ways, the DIR's disk change line and the CCR, and the reads of the DMA controller's
// ports 00-0F too: its status and current counts)
wire        fdp_ev = DBG_FLOPPY & io_ev & ((io_addr == 32'h8000_03F4 && (io_be == 4'b0100 || io_be == 4'b0001)) ||
                              (io_addr[31:4] == 28'h8000_000) ||
                              (io_we && (io_addr == 32'h8000_0080 || io_addr == 32'h8000_0480)));
reg         fds_t = 1'b0, fds_q = 1'b0;
reg  [31:0] fds_d;
always @(posedge clk_sys) begin
	fds_q <= sd_rd[4] | sd_wr[4];
	if ((sd_rd[4] | sd_wr[4]) & ~fds_q) begin fds_t <= ~fds_t; fds_d <= {sd_wr[4], 12'd0, sd_blk_cnt[4], sd_lba[4][12:0]}; end
end
reg  [2:0]  fds_s = 0;
reg         fds_pend = 1'b0;
always @(posedge clk_cpu) fds_s <= {fds_s[1:0], fds_t};
wire        nq_io = ncr_ev | s3v_ev | s3e_ev | fdp_ev;
always @(posedge clk_cpu) begin
	if ((nq_io || pk_ev || fds_pend) && nq_w + 6'd1 != nq_r) begin
		nq[nq_w] <= (ncr_ev | s3v_ev) ? {s3v_ev, io_we, io_be, io_addr[7:0], io_we ? io_wdata : io_rdata} :
		            s3e_ev            ? {1'b1, io_we, io_be, io_addr[15:8], io_we ? io_wdata : io_rdata} :
		            fdp_ev            ? {1'b0, io_we, io_be, io_addr[10] ? 8'h48 : io_addr[7:0], io_we ? io_wdata : io_rdata} :
		            pk_ev             ? {1'b0, 1'b1, 4'h0, 8'h00, 21'd0, ps2_key} :
		                                {1'b0, 1'b1, 4'h0, 8'hFD, fds_d};
		nq_w     <= nq_w + 6'd1;
		if (!nq_io && !pk_ev) fds_pend <= 1'b0;
	end
	if (DBG_FLOPPY && (fds_s[2] ^ fds_s[1])) fds_pend <= 1'b1;
end
// (the OS/2 build) every byte the machine writes to COM1's transmit holding register (3F8, DLAB or not: the
// divisor's low byte comes through too, rarely), as that byte with bit 7 set: the rest of the stream is
// 7-bit, so a reader splits COM1's text off (dbgauto.py keeps it in its own file); a 64-entry FIFO
// (and COM2's, 2F8, as a 0x80 byte then the byte with bit 7 set: OS/2's logger may talk there)
reg  [8:0]  cq [64];                      // {com2, the byte}
reg  [5:0]  cq_w = 0, cq_r = 0, cq_wq = 0;
reg  [8:0]  cq_e;
wire        cq_ev1 = io_we & (io_addr[31:2] == 30'h2000_00FE) & io_be[3];
wire        cq_ev2 = io_we & (io_addr[31:2] == 30'h2000_00BE) & io_be[3];
wire        cq_ev  = DBG_COM1TX & isi_armed & io_ev & (cq_ev1 | cq_ev2);
always @(posedge clk_cpu) begin
	if (cq_ev && cq_w + 6'd1 != cq_r) begin cq[cq_w] <= {cq_ev2, io_wdata[31:24]}; cq_w <= cq_w + 6'd1; end
	cq_e  <= cq[cq_r];
	cq_wq <= cq_w;
end
// (the OS/2 build) the decrementer exceptions taken (vector 900) from the hand-off: "T=cccc " every 64 of them,
// cccc the count so far (the kernel's clock: 100 a second expected)
reg  [15:0] dec_n = 0;
reg         dec_pend = 0;
wire        dec_ev = DBG_COM1TX & isi_armed & trace_valid & trace_last & (trace_pc == 32'h0000_0900);
always @(posedge clk_cpu) if (dec_ev) dec_n <= dec_n + 16'd1;
wire        dec_hit = dec_ev & (dec_n[5:0] == 6'd63);
// (the OS/2 build) nine (PC, instruction) watch points in OS/2's user programs, each hit queued as "~c" (c a
// letter): insmain's NS_GetAttr (G the call, a each attribute compared, A found, x not found, g GETPERS's
// check of the result) and pagrinit's AddLeafNode return code (p reached, q not "exists", r not tolerated,
// s not 0); the instruction word tells the program's copy of the code from another's at the same address
// (every server is linked at 02000000); a 64-entry FIFO
localparam bit DBG_WATCH = 1'b0;         // the watch points (off: they answered, and the disk build needs the room)
reg  [3:0]  wq [64];
reg  [5:0]  wq_w = 0, wq_r = 0, wq_wq = 0;
reg  [3:0]  wq_e;
logic [3:0] w_hit;
logic       w_any;
logic [7:0] w_ch;
always_comb begin
	w_any = 1'b1;
	// (the os2l set, insmain's attribute lookup and pagrinit's leaf add, answered its question: see
	// docs/resume_os2.md; the os2m set below watches utilfs and insmain's UFS traffic)
	case ({trace_pc, trace_insn})
		{32'h0200_4FE0, 32'h4807_3591}: w_hit = 4'd0;   // utilfs ufs_service_loop: bl mk_msg_server (serving)
		{32'h0200_4FE8, 32'h4800_1565}: w_hit = 4'd1;   // utilfs: cthread_exit after the loop (the server ended)
		{32'h0200_4884, 32'h7C08_02A6}: w_hit = 4'd2;   // utilfs do_UFS_HandleRequest (a request taken)
		{32'h0200_5D0C, 32'h4806_4D4D}: w_hit = 4'd3;   // utilfs RegSrvPort: bl NS_AddNode (servers/utilfs)
		{32'h0200_5D34, 32'h4800_0008}: w_hit = 4'd4;   // ... its rc was not 0
		{32'h0206_8934, 32'h386C_0764}: w_hit = 4'd5;   // insmain UFS_PNS_Service_Entry: "couldn't find UFS"
		{32'h0206_756C, 32'h386C_0314}: w_hit = 4'd6;   // insmain format_and_send_msg: "(GetPort) couldn't find UFS"
		{32'h0201_33B4, 32'h4803_865D}: w_hit = 4'd7;   // insmain GetPercentage: the send
		{32'h0200_9000, 32'h7C08_02A6}: w_hit = 4'd8;   // insmain Ins_Exit
		{32'h0206_9828, 32'h4BFE_5F35}: w_hit = 4'd9;   // insmain GEN_XferData: the send (mach_msg_overwrite)
		default: begin w_hit = 4'd0; w_any = 1'b0; end
	endcase
	case (wq_e)
		4'd0: w_ch = 8'h75; 4'd1: w_ch = 8'h74; 4'd2: w_ch = 8'h55; 4'd3: w_ch = 8'h52; 4'd4: w_ch = 8'h6E;
		4'd5: w_ch = 8'h66; 4'd6: w_ch = 8'h46; 4'd7: w_ch = 8'h6B; 4'd8: w_ch = 8'h65; default: w_ch = 8'h58;
	endcase
end
wire        wq_ev = DBG_WATCH & DBG_COM1TX & isi_armed & trace_valid & trace_last & w_any;
always @(posedge clk_cpu) begin
	if (wq_ev && wq_w + 6'd1 != wq_r) begin wq[wq_w] <= w_hit; wq_w <= wq_w + 6'd1; end
	wq_e  <= wq[wq_r];
	wq_wq <= wq_w;
end
// (the OS/2 build) the interrupts the CPU takes: each interrupt acknowledge (a read of BFFFFxxx) as "I=vv "
// (vv the 8259s' vector, on every lane), and the writes of the 8259s' masks and the ELCR (21, A1, 4D0, 4D1)
// as "Paaa=dd "; a 64-entry FIFO (a storm fills it; the first 64 win)
reg  [20:0] iq [64];                      // {pic, port[11:0], data}
reg  [5:0]  iq_w = 0, iq_r = 0, iq_wq = 0;
reg  [20:0] iq_e;
wire        iq_ack = ~io_we & (io_addr[31:12] == 20'hBFFFF);
wire        iq_p21 = io_we & (io_addr[31:2] == 30'h2000_0008) & io_be[2];
wire        iq_pa1 = io_we & (io_addr[31:2] == 30'h2000_0028) & io_be[2];
wire        iq_e0  = io_we & (io_addr[31:2] == 30'h2000_0134) & io_be[3];
wire        iq_e1  = io_we & (io_addr[31:2] == 30'h2000_0134) & io_be[2];
localparam bit DBG_IQ = 1'b0;            // the interrupt acknowledges and PIC writes (off for the disk build's room)
wire        iq_ev  = DBG_IQ & DBG_COM1TX & isi_armed & io_ev & (iq_ack | iq_p21 | iq_pa1 | iq_e0 | iq_e1);
always @(posedge clk_cpu) begin
	if (iq_ev && iq_w + 6'd1 != iq_r) begin
		iq[iq_w] <= iq_ack ? {1'b0, 12'h000, io_rdata[7:0]} :
		            iq_p21 ? {1'b1, 12'h021, io_wdata[23:16]} :
		            iq_pa1 ? {1'b1, 12'h0A1, io_wdata[23:16]} :
		            iq_e0  ? {1'b1, 12'h4D0, io_wdata[31:24]} :
		                     {1'b1, 12'h4D1, io_wdata[23:16]};
		iq_w     <= iq_w + 6'd1;
	end
	iq_e  <= iq[iq_r];
	iq_wq <= iq_w;
end
// (read a clock behind: a block RAM; the drain looks at the write pointer a clock late, so an entry is
// read before it is taken, and after a take the stage is busy for 14 clocks)
reg  [45:0] nq_e;
reg  [5:0]  nq_wq = 0;
always @(posedge clk_cpu) begin
	nq_e  <= nq[nq_r];
	nq_wq <= nq_w;
end
// (the NT video build) from the first program exception after the switch to little-endian (isi_done: the NT
// kernel's first DbgLoadImageSymbols) on, every other device access by its whole address, through a 64-entry
// FIFO, in two parts: "Daaaaaaaab" (D a write, d a read; b the byte lanes) then "=dddddddd ": not COM1
// (3F8-3FF), not the 8042 (60-67), not what the FIFO above takes (the 53C810); PCI memory (C000_0000 up) only when the
// 4 KB page differs from the last one logged, so a frame buffer's writes show where they go, not each one;
// at most 16383 entries; not the 8259s' ports (20-21, A0-A1), 808 or the interrupt acknowledge (BFFF_FFF0),
// which an interrupt storm filled the FIFO with
reg  [66:0] dv [256];                     // {we, addr[31:2], be, data}
reg  [7:0]  dv_w = 0, dv_r = 0, dv_wq = 0;
reg  [66:0] dv_e;
reg  [13:0] dv_n = 0;
reg  [31:12] dv_page = 0;
reg         dv_half = 0;
reg  [31:0] dv_d;
wire        dv_mem = io_addr[31:30] == 2'b11;
// (for now the ISA ports an audio driver may use, reads and writes: 100-13F (the CS4232's control), 200-23F,
// 279, 300-38F, 530-53F, 604-60F, A79, E80-F4F (the WSS's other bases), and the PnP read port wherever it is
// (203-3FF reads not named elsewhere); not the 8259s, the PIT, the 8042, the RTC, the video, COM1, the floppy)
wire [15:0] dv_p   = io_addr[15:0];
// (the OS/2 build: from the boot hand-off, every ISA port (io_addr is the port after the I/O map) but the busy
// ones: the 8259s, the PIT and port 61, the 8042, COM1, the ELCR, 080C; and PCI memory by 4 KB page)
wire        dv_isa = io_addr[31:16] == 16'h8000 &&
                     !(dv_p[15:1] == 15'h0010 || dv_p[15:1] == 15'h0050 || dv_p[15:2] == 14'h0010 || dv_p == 16'h0061 ||
                       dv_p == 16'h0060 || dv_p == 16'h0064 || dv_p[15:3] == 13'h007F || dv_p[15:1] == 15'h0268 ||
                       dv_p == 16'h080C);
wire        dv_ev  = DBG_DEVLOG & isi_armed & io_ev & ~ncr_ev & ~(&dv_n) &
                     (dv_isa || (dv_mem && io_addr[31:12] != dv_page));
always @(posedge clk_cpu) begin
	if (dv_ev && dv_w + 8'd1 != dv_r) begin
		dv[dv_w] <= {io_we, io_addr[31:2], io_be, io_we ? io_wdata : io_rdata};
		dv_w     <= dv_w + 8'd1;
		dv_n     <= dv_n + 14'd1;
		if (dv_mem) dv_page <= io_addr[31:12];
	end
	dv_e  <= dv[dv_r];
	dv_wq <= dv_w;
end
// (the desktop build: no PC trigger; instead, once, when nothing has retired for 2^24 clocks (0.24 s) after
// the hand-off, the header alone: "IL=" the last PC retired, " C=" the data address the CPU's access is at,
// " M=" bit 31 a data access pending, bit 30 a write: where a stalled bus access hangs the core)
wire        isi_go;                       // (assigned below: the first program exception after the switch to little-endian)
// (little-endian bring-up) from the switch to little-endian (a port 92 write with bit 1 set) on, the last 64
// instructions retired, PC and word, in a ring; at the stall they follow its header, the oldest first,
// "pppppppp:iiiiiiii ". The stall's " M=" then also carries the MSR in bits 29-0.
reg         le_arm = 1'b0;
reg  [31:0] le_pc [64];
reg  [31:0] le_in [64];
reg  [5:0]  le_w = 0, le_r = 0;
reg  [6:0]  le_left = 0;
reg  [31:0] le_pc_q, le_in_q, le_hold;
reg         le_half = 1'b0;
always @(posedge clk_cpu) begin
	if (io_ev & io_we & (io_addr[31:2] == 30'h2000_0024) & io_be[1] & io_wdata[9]) le_arm <= 1'b1;
	if (le_arm && !isi_done && trace_valid && trace_last) begin
		le_pc[le_w] <= trace_pc;
		le_in[le_w] <= trace_insn;
		le_w        <= le_w + 6'd1;
	end
	le_pc_q <= le_pc[le_r];
	le_in_q <= le_in[le_r];
end
// the first program exception (vector 700) after the switch to little-endian: its LR, CTR and MSR, then the 40
// instructions retired from the vector on with the GPR each wrote (NT's handler reads SRR0 and SRR1 into GPRs)
assign isi_go = le_arm & ~isi_done & trace_valid & trace_last & (trace_pc == 32'h0000_0700);
reg  [23:0] stall_n = 0;
reg  [31:0] stall_pc = 0;
always @(posedge clk_cpu) begin
	if (trace_valid & trace_last) begin stall_n <= 24'd0; stall_pc <= trace_pc; end
	else if (stall_n != 24'hFFFFFF) stall_n <= stall_n + 24'd1;
end
wire        stall_go = isi_armed & ~isi_done & (stall_n == 24'hFFFFFE);
always @(posedge clk_cpu) begin
	if (post_ev && io_wdata[31:24] == 8'h2F) isi_armed <= 1'b1;
	if (DBG_GPR && trace_valid && trace_last && (isi_go || isi_n != 6'd0)) begin
		isi_pc[isi_w]  <= trace_pc[15:0];
		isi_v[isi_w]   <= trace_reg_val[31:0];
		isi_vw[isi_w]  <= trace_reg_we & ~trace_reg_idx[6] & ~trace_reg_idx[5];
		isi_w          <= isi_w + 6'd1;
		isi_n          <= isi_go ? 6'd39 : isi_n - 6'd1;
	end
	if (isi_go) begin isi_done <= 1'b1; isi_lr <= trace_lr; isi_ctr <= trace_ctr; isi_msr <= trace_msr; end
	if (stall_go) begin isi_done <= 1'b1; isi_lr <= stall_pc; isi_ctr <= {t_daddr, 2'b00}; isi_msr <= {t_dreq, t_dwe, trace_msr[29:0]}; end
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
wire        m_ev = 1'b0;                  // (off in the NT video build, for room: was m_s[2] ^ m_s[1], the latched data stands still long enough)

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
	hs_take <= 1'b0;
	if (post_ev) begin post_code <= io_wdata[31:24]; post_pc <= pc_prev[31:12] == 20'h00007 ? 32'd0 : pc_prev; end
	if (k92_ev) k92_d <= io_wdata[15:8];
	k92_pend   <= k92_pend | k92_ev;
	if (isi_go | stall_go) isi_hdr <= 2'd3;
	if ((stall_go | isi_go) & le_arm) begin le_r <= le_w; le_left <= 7'd64; end   // the ring at the stall, and at the first program exception
	if (1'b0 && isi_armed && io_ev && io_we && io_addr[31:3] == 29'h1000_007F && !usr_pend) begin   // (off in the NT video build, for room)
		usr_pend <= 1'b1; usr_we <= io_we; usr_isa <= 1'b1; usr_a <= {io_be, io_addr[11:0]};
		usr_d <= io_wdata;
	end
	c1_pendl <= c1_pendl | c1_evl;
	dec_pend <= dec_pend | dec_hit;
	c1_pendh <= c1_pendh | c1_evh;
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
	else if (le_half) begin
		stage_n <= 4'd9;
		stage   <= {hex8(le_hold), 8'h20, 40'h0};
		le_half <= 1'b0;
	end
	else if (isi_done && le_left != 7'd0) begin   // (le_pc_q/le_in_q: read a clock after le_r moved, long before this)
		stage_n <= 4'd9;
		stage   <= {hex8(le_pc_q), 8'h3A, 40'h0};
		le_hold <= le_in_q;
		le_half <= 1'b1;
		le_r    <= le_r + 6'd1;
		le_left <= le_left - 7'd1;
	end
	else if (isi_done && isi_n == 6'd0 && isi_r != isi_w) begin
		stage_n <= 4'd14;
		stage   <= {hex(isi_pc[isi_r][15:12]), hex(isi_pc[isi_r][11:8]), hex(isi_pc[isi_r][7:4]), hex(isi_pc[isi_r][3:0]), 8'h3D,
		            isi_vw[isi_r] ? hex8(isi_v[isi_r]) : {8{8'h2D}}, 8'h20};
		isi_r   <= isi_r + 6'd1;
	end
	else if (cq_r != cq_wq) begin           // (cq_e: read a clock after cq_r moved, long before this)
		stage_n <= cq_e[8] ? 4'd2 : 4'd1;
		stage   <= cq_e[8] ? {8'h80, 1'b1, cq_e[6:0], 96'h0} : {1'b1, cq_e[6:0], 104'h0};
		cq_r    <= cq_r + 6'd1;
	end
	else if (dec_pend) begin
		stage_n  <= 4'd7;
		stage    <= {8'h54, 8'h3D, hex(dec_n[15:12]), hex(dec_n[11:8]), hex(dec_n[7:4]), hex(dec_n[3:0]), 8'h20, 56'h0};
		dec_pend <= 1'b0;
	end
	else if (DBG_WATCH && wq_r != wq_wq) begin   // (wq_e: read a clock after wq_r moved, long before this)
		stage_n <= 4'd2;
		stage   <= {8'h7E, w_ch, 96'h0};
		wq_r    <= wq_r + 6'd1;
	end
	else if (DBG_IQ && iq_r != iq_wq) begin   // (iq_e: read a clock after iq_r moved, long before this)
		if (iq_e[20]) begin
			stage_n <= 4'd8;
			stage   <= {8'h50, hex(iq_e[19:16]), hex(iq_e[15:12]), hex(iq_e[11:8]), 8'h3D, hex(iq_e[7:4]), hex(iq_e[3:0]), 8'h20, 48'h0};
		end else begin
			stage_n <= 4'd5;
			stage   <= {8'h49, 8'h3D, hex(iq_e[7:4]), hex(iq_e[3:0]), 8'h20, 72'h0};
		end
		iq_r    <= iq_r + 6'd1;
	end
	else if (hs_half) begin stage_n <= 4'd10; stage <= {8'h4D, hex8(hs_b), 8'h20, 32'h0}; hs_half <= 1'b0; hs_take <= 1'b1; end
	else if (hs_pend && !hs_take) begin stage_n <= 4'd10; stage <= {8'h48, hex8(hs_a), 8'h20, 32'h0}; hs_half <= 1'b1; end
	else if (c1_pendl) begin stage_n <= 4'd11; stage <= {8'h4C, 8'h3D, hex8(c1_minl), 8'h20, 24'h0}; c1_pendl <= 1'b0; end
	else if (c1_pendh) begin stage_n <= 4'd11; stage <= {8'h48, 8'h3D, hex8(c1_minh), 8'h20, 24'h0}; c1_pendh <= 1'b0; end
	else if (dv_half) begin
		stage_n <= 4'd10;
		stage   <= {8'h3D, hex8(dv_d), 8'h20, 32'h0};
		dv_half <= 1'b0;
	end
	else if (dv_r != dv_wq) begin           // (dv_e: read a clock after dv_r moved, long before this)
		stage_n <= 4'd10;
		stage   <= {dv_e[66] ? 8'h44 : 8'h64, hex8({dv_e[65:36], 2'b00}), hex(dv_e[35:32]), 32'h0};
		dv_d    <= dv_e[31:0];
		dv_half <= 1'b1;
		dv_r    <= dv_r + 8'd1;
	end
	else if (nq_r != nq_wq) begin
		stage_n <= 4'd14;                  // (14 bytes: the stage's whole width; a pad byte had pushed the letter out)
		stage   <= {nq_e[44] ? (nq_e[45] ? 8'h77 : 8'h57) : (nq_e[45] ? 8'h72 : 8'h52), hex(nq_e[43:40]), hex(nq_e[39:36]), hex(nq_e[35:32]), 8'h3D, hex8(nq_e[31:0]),
		            8'h20};
		nq_r    <= nq_r + 6'd1;
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
// the source: the System page's UART mode. Any mode (PPP, Console, MIDI, Modem) connects the MiSTer's
// Linux to the machine's serial port, COM1; with None, a debug build sends this stream instead (read
// /dev/ttyS1 at 115200). A release build: COM1 always
`ifdef IBMRS6K7248_DEBUG
assign UART_TXD = uart_mode != 8'd0 ? com1_txd : post_txd;
`else
assign UART_TXD = com1_txd;
`endif

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
// the framework's integer scaling (the Video page's Scale, at once): video_freak measures the mode and
// sets the ratio and the active area
video_freak video_freak
(
	.CLK_VIDEO, .CE_PIXEL, .VGA_VS, .HDMI_WIDTH, .HDMI_HEIGHT, .VGA_DE, .VIDEO_ARX, .VIDEO_ARY,
	.VGA_DE_IN(~(vid_hblank | vid_vblank)),
	.ARX((!ar) ? 12'd4 : 12'(ar - 1'd1)), .ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0), .CROP_OFF(5'd0), .SCALE({1'b0, status[124:123]})
);
assign VGA_HS    = vid_hs;
assign VGA_VS    = vid_vs;
assign VGA_R     = vid_r;
assign VGA_G     = vid_g;
assign VGA_B     = vid_b;

endmodule
