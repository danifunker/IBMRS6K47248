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

`ifdef IBMRS6K7248_CPU100
localparam int CPU_MHZ = 100;               // the 100 MHz build (MacPPC7300's: the same CPU past its timing; the DE10-Nano, MiSTer Pi, SuperStation)
`elsif IBMRS6K7248_CPU90
localparam int CPU_MHZ = 90;                // the 90 MHz build (the PLL's VCO at 900 MHz; 100 ran POST but did not boot the disk)
`elsif IBMRS6K7248_CPU58
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
// Load ROM, Memory, the submenus by their fixed pages (P2 Video, P3 Input, P4 Audio, P5 Advanced),
// "Changes pending" and Apply and reset. Media and Input act at once; the rest waits for
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
wire        com1_txd;
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

	.io_ev(), .io_we(), .io_stub(), .io_ncr(), .io_addr(), .io_be(), .io_wdata(), .io_rdata(),
	.trace_valid, .trace_last, .trace_pc(), .trace_insn(), .trace_msr(), .trace_lr(), .trace_ctr(),
	.trace_reg_we(), .trace_reg_idx(), .trace_reg_val(),
	.trace_dreq(), .trace_dwe(), .trace_daddr()
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

///////////////////////   THE SERIAL PORT   ///////////////////////////////

// the MiSTer's UART is the machine's COM1 (the System page's UART mode: PPP, Console, MIDI or Modem connect
// the MiSTer's Linux to it; read it with picocom -b 9600 /dev/ttyS1)
assign UART_TXD = com1_txd;

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
