//============================================================================
//
//  IBMRS6K7248 - the IBM RS/6000 43P model 7248 for MiSTer
//  The top: the framework's ports, the clocks, the ROM upload, the SDRAM,
//  the machine (IBMRS6K7248_system), COM1 on the MiSTer's UART
//
//  Clocks from one PLL (rtl/pll.v, MacPPC7300's, built for 100 MHz only):
//    clk_cpu  100 MHz  the CPU and the machine (IBMRS6K7248_system)
//    clk_mem  100 MHz  the SDRAM controller, hps_io, the ROM upload, the picture
//  (the two are one PLL counter at 100 MHz; the clock crossing between them
//  stays, as in MacPPC7300's 100 MHz build.) outclk_0 (20 MHz) is unused.
//
//  First form: there is no video device yet. The picture is a black
//  640 x 480 at 60 Hz so the scaler has a mode; the console is COM1, the
//  MiSTer's UART (the firmware's serial console at 9600 baud).
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

localparam int CPU_MHZ = 100;
localparam int TB_HZ   = 16_666_667;        // the 604's time base: a quarter of a 66 MHz bus

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
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
	// the RAM beside the ROM (the board's top 4 MB): the board's most, or less
	"O[3:1],RAM (on reset),Most,16 MB,32 MB,64 MB,96 MB;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
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
wire [15:0] sdram_sz;                 // the Main's SDRAM board: [15] known, [1:0] 1 32 MB, 2 64 MB, 3 128 MB
reg   [1:0] sdram_mod = 2'd1;         // the board the ROM went into (an unknown one taken as 32 MB)

hps_io #(.CONF_STR(CONF_STR)) hps_io
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

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

///////////////////////   OPTIONS, ROM AND RESET (memory clock)   ///////////////////////////////

// the RAM: the OSD's size, no more than the board holds beside the ROM
wire [7:0] ram_max = sdram_mod == 2'd3 ? 8'd124 : sdram_mod == 2'd2 ? 8'd60 : 8'd28;
reg  [7:0] ram_sel;
always @(*) begin
	case (status[3:1])
		3'd1:    ram_sel = 8'd16;
		3'd2:    ram_sel = 8'd32;
		3'd3:    ram_sel = 8'd64;
		3'd4:    ram_sel = 8'd96;
		default: ram_sel = 8'd255;            // the most
	endcase
end
reg [7:0] ram_opt;
always @(posedge clk_mem) ram_opt <= ram_sel > ram_max ? ram_max : ram_sel;

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
always @(posedge clk_mem) reset_in <= {reset_in[1:0], RESET | status[0] | buttons[1]};

reg cpu_reset_m = 1;
always @(posedge clk_mem) cpu_reset_m <= reset_in[2] | ~sdram_ready | rom_dl | ~rom_loaded;

// the options taken under reset
reg [7:0] ram_mb = 8'd16;
reg       rom_512k = 1;
always @(posedge clk_mem) if (cpu_reset_m) begin
	ram_mb   <= ram_opt;
	rom_512k <= ~rom_big;
end

// into the CPU's clock (quasi-static: they change only with the reset held)
reg [2:0] cpu_reset_s = 3'b111;
reg [7:0] ram_mb_c [2];
reg [4:0] rom_at_c [2];
reg [1:0] rom_512k_c;
always @(posedge clk_cpu) begin
	cpu_reset_s <= {cpu_reset_s[1:0], cpu_reset_m};
	ram_mb_c[0] <= ram_mb;
	ram_mb_c[1] <= ram_mb_c[0];
	rom_at_c[0] <= rom_at;
	rom_at_c[1] <= rom_at_c[0];
	rom_512k_c  <= {rom_512k_c[0], rom_512k};
end
wire cpu_reset = cpu_reset_s[2];

///////////////////////   THE MACHINE   ///////////////////////////////

wire         b_req, b_we, b_line, b_ack;
wire [31:2]  b_addr;
wire  [3:0]  b_be;
wire [255:0] b_wdata, b_rdata;
wire         trace_valid, trace_last;

IBMRS6K7248_system #(.CPU_HZ(CPU_MHZ * 1_000_000), .TB_HZ(TB_HZ)) system
(
	.clk(clk_cpu),
	.reset(cpu_reset),
	.reset_pc(32'hFFF00100),
	.ram_mb(ram_mb_c[1]),
	.rom_at(rom_at_c[1]),
	.rom_512k(rom_512k_c[1]),
	.planar_id(8'hF5),                      // a 7248-100 (the OSD's model choice to come)

	.clk_b(clk_mem),
	.reset_b(cpu_reset_m),
	.b_req, .b_we, .b_line, .b_addr, .b_be, .b_wdata, .b_ack, .b_rdata,

	.com1_txd(UART_TXD),
	.com1_rxd(UART_RXD),
	.com1_cts_n(~UART_CTS),
	.com1_rts_n(),

	.io_ev(), .io_we(), .io_stub(), .io_addr(), .io_be(), .io_wdata(), .io_rdata(),
	.trace_valid, .trace_last, .trace_pc(), .trace_insn(), .trace_msr(),
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

///////////////////////   THE LED   ///////////////////////////////

// the CPU's heartbeat: it toggles every 2^20 instructions retired
reg [20:0] retired = 0;
always @(posedge clk_cpu) begin
	if (trace_valid & trace_last) retired <= retired + 1'd1;
	if (cpu_reset) retired <= 0;
end
assign LED_USER = retired[20];

///////////////////////   THE PICTURE   ///////////////////////////////

// a black 640 x 480 at 59.5 Hz (25 MHz pixels: 800 x 525) until there is a video device
reg [1:0] pix_div = 0;
reg [9:0] hc = 0, vc = 0;
reg       ce_pix = 0;
always @(posedge clk_mem) begin
	pix_div <= pix_div + 1'd1;
	ce_pix  <= pix_div == 2'd3;
	if (ce_pix) begin
		hc <= (hc == 10'd799) ? 10'd0 : hc + 1'd1;
		if (hc == 10'd799) vc <= (vc == 10'd524) ? 10'd0 : vc + 1'd1;
	end
end

assign CLK_VIDEO = clk_mem;
assign CE_PIXEL  = ce_pix;
assign VGA_DE    = hc < 10'd640 && vc < 10'd480;
assign VGA_HS    = hc >= 10'd656 && hc < 10'd752;     // the framework takes sync active high
assign VGA_VS    = vc >= 10'd490 && vc < 10'd492;
assign VGA_R     = 8'd0;
assign VGA_G     = 8'd0;
assign VGA_B     = 8'd0;

endmodule
