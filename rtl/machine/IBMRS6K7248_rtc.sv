//============================================================================
//
//  IBMRS6K7248 - the real-time clock (an MC146818) and the 4 KB NVRAM
//
//  The RTC at 70 (index; bit 7 the NMI mask, kept for port 70's readers)
//  and 71 (data): the time and calendar, the alarm, registers A-D, the
//  update-in-progress flag, the periodic, alarm and update-ended
//  interrupts (IRQ8), and 114 bytes of CMOS RAM (0E-7F). The time is kept
//  in binary and shown as register B asks (BCD or binary, 12 or 24 hour);
//  the year is two digits (the firmware keeps the century in CMOS). It is
//  set from the MiSTer's clock when set_time pulses, then counts on its own
//  32,768 Hz time base (made from CLK_HZ by phase accumulation).
//
//  The NVRAM: 4,096 bytes behind 74 (address bits 7-0), 75 (bits 11-8) and
//  76 (data), the PReP NVRAM the firmware keeps its configuration in. It
//  starts as the firmware's own formatted image (below); IBMRS6K7248_nvsave
//  keeps it and the CMOS on the SD card through the maintenance port: m_addr
//  0-FFF the NVRAM, 1000-107F the CMOS, read a clock later, written in a
//  cycle the CPU leaves the RTC alone (m_ok); wr_seq (Gray) counts the
//  CPU's writes of the NVRAM and of CMOS 0E-7F.
//
//  The bus: one byte access a cycle by port offset, the read value in
//  rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_rtc
#(
	parameter int unsigned CLK_HZ = 100_000_000,
	parameter int unsigned FAST   = 0            // 1 (the bench only): a second every 512 ticks of the 32 kHz (64 x faster)
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic [2:0]  port,          // 0 70, 1 71, 4 74, 5 75, 6 76
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	output logic        irq8,
	output logic        nmi_mask,      // port 70 bit 7

	// the time to start from (hps_io's RTC: BCD seconds, minutes, hours, date, month, year;
	// then the weekday, 0-6 from Sunday)
	input  logic        set_time,
	input  logic [55:0] time_bcd,

	// the maintenance port (IBMRS6K7248_nvsave)
	input  logic [12:0] m_addr,
	input  logic        m_we,
	input  logic [7:0]  m_wdata,
	output logic [7:0]  m_q,
	output logic        m_ok,
	output logic [7:0]  wr_seq
);

// ---- the 32,768 Hz time base ---------------------------------------------------------
localparam logic [31:0] INC = 32'((64'd32_768 << 32) / 64'(CLK_HZ));
logic [31:0] acc = '0;
logic        t32k;
always_ff @(posedge clk) {t32k, acc} <= {1'b0, acc} + {1'b0, INC};
logic [14:0] div;                       // the divider chain: one second at its wrap
localparam logic [14:0] SEC_WRAP = FAST != 0 ? 15'h01FF : 15'h7FFF;   // (FAST: the periodic rates above 64 Hz unchanged)

// ---- registers ------------------------------------------------------------------------
logic [6:0] index;
logic [5:0] sec, min, sec_a, min_a;     // binary
logic [4:0] hour, hour_a;               // 0-23
logic [7:0] sec_a_raw, min_a_raw, hour_a_raw;   // the alarm bytes as written (C0-FF: don't care)
logic [2:0] dow;                        // 1-7
logic [4:0] date;
logic [3:0] month;
logic [6:0] year;
logic [6:0] reg_a;                      // DV, RS (UIP is made)
logic [7:0] reg_b;
logic [2:0] flags;                      // PF, AF, UF
logic [7:0] cmos_ram [128];                 // 0E-7F used

wire        bin  = reg_b[2];
wire        h24  = reg_b[1];
wire        run  = reg_a[6:4] == 3'b010 && !reg_b[7];

function automatic logic [7:0] to_bcd(input logic [6:0] v);
	to_bcd = {1'b0, 3'(32'(v) / 10), 4'(32'(v) % 10)};
endfunction
function automatic logic [6:0] from_bcd(input logic [7:0] v);
	from_bcd = 7'(32'(v[7:4]) * 10 + 32'(v[3:0]));
endfunction
// a value as register B shows it
function automatic logic [7:0] show(input logic [6:0] v, input logic b);
	show = b ? {1'b0, v} : to_bcd(v);
endfunction
function automatic logic [7:0] show_hour(input logic [4:0] h, input logic b, input logic t24);
	logic [4:0] h12;
	logic [7:0] v;
	if (t24) show_hour = show({2'd0, h}, b);
	else begin
		h12 = (h == 5'd0) ? 5'd12 : (h > 5'd12) ? 5'(h - 5'd12) : h;
		v   = show({2'd0, h12}, b);
		show_hour = {h >= 5'd12, v[6:0]};
	end
endfunction
function automatic logic [6:0] take(input logic [7:0] v, input logic b);
	take = b ? v[6:0] : from_bcd(v);
endfunction
function automatic logic [4:0] take_hour(input logic [7:0] v, input logic b, input logic t24);
	logic [6:0] h;
	h = take({1'b0, v[6:0]}, b);
	if (t24) take_hour = 5'(h);
	else     take_hour = 5'((h == 7'd12 ? 7'd0 : h) + (v[7] ? 7'd12 : 7'd0));
endfunction

// days in the month (two-digit years: every fourth is a leap year, as for 2000-2099)
wire [4:0] mdays = month == 4'd2 ? (year[1:0] == 2'd0 ? 5'd29 : 5'd28) :
                   (month == 4'd4 || month == 4'd6 || month == 4'd9 || month == 4'd11) ? 5'd30 : 5'd31;

// the update cycle: UIP for the last 244 us (8 ticks) before each second (SEC_WRAP - 7: with FAST
// the divider never reaches 32760, and AIX's planar_pal_init_ds1285 waits for UIP with interrupts off)
wire uip = run && div >= SEC_WRAP - 15'd7;

// the periodic interrupt: rate select 3-15 is every 2^(RS-1) ticks (8,192 Hz down to 2 Hz);
// 1 and 2 are 256 and 128 Hz (every 128 and 256 ticks)
logic [14:0] pmask;
always_comb begin
	case (reg_a[3:0])
		4'd1:    pmask = 15'h007F;
		4'd2:    pmask = 15'h00FF;
		default: pmask = 15'((16'd1 << (reg_a[3:0] - 4'd1)) - 16'd1);
	endcase
end

wire alarm_hit = (sec_a_raw[7:6] == 2'b11 || sec_a == sec) &&
                 (min_a_raw[7:6] == 2'b11 || min_a == min) &&
                 (hour_a_raw[7:6] == 2'b11 || hour_a == hour);

// the NVRAM
logic [11:0] nv_addr;
logic [7:0]  nvram [4096];
logic [7:0]  nv_q;

always_ff @(posedge clk) begin
	if (t32k && reg_a[6:4] == 3'b010) begin
		div <= div == SEC_WRAP ? 15'd0 : div + 15'd1;
		// periodic
		if (reg_a[3:0] != 4'd0 && (div & pmask) == pmask)
			flags[2] <= 1'b1;
		if (!reg_b[7] && div == SEC_WRAP) begin
			// the second: the time, then the alarm and the update-ended flag
			flags[0] <= 1'b1;
			if (sec != 6'd59) sec <= sec + 6'd1;
			else begin
				sec <= 6'd0;
				if (min != 6'd59) min <= min + 6'd1;
				else begin
					min <= 6'd0;
					if (hour != 5'd23) hour <= hour + 5'd1;
					else begin
						hour <= 5'd0;
						dow  <= dow == 3'd7 ? 3'd1 : dow + 3'd1;
						if (date != mdays) date <= date + 5'd1;
						else begin
							date <= 5'd1;
							if (month != 4'd12) month <= month + 4'd1;
							else begin month <= 4'd1; year <= year == 7'd99 ? 7'd0 : year + 7'd1; end
						end
					end
				end
			end
		end
	end
	// the alarm, checked after the second has moved
	if (t32k && run && div == 15'd0 && alarm_hit) flags[1] <= 1'b1;

	if (sel) begin
		case (port)
			3'd0: if (we) begin index <= wdata[6:0]; nmi_mask <= wdata[7]; end
			      else rdata <= {nmi_mask, index};
			3'd1: begin
				if (we) begin
					case (index)
						7'h00: sec   <= 6'(take(wdata, bin));
						7'h01: begin sec_a <= 6'(take(wdata, bin)); sec_a_raw <= wdata; end
						7'h02: min   <= 6'(take(wdata, bin));
						7'h03: begin min_a <= 6'(take(wdata, bin)); min_a_raw <= wdata; end
						7'h04: hour  <= take_hour(wdata, bin, h24);
						7'h05: begin hour_a <= take_hour(wdata, bin, h24); hour_a_raw <= wdata; end
						7'h06: dow   <= wdata[2:0];
						7'h07: date  <= 5'(take(wdata, bin));
						7'h08: month <= 4'(take(wdata, bin));
						7'h09: year  <= take(wdata, bin);
						7'h0A: begin
							reg_a <= wdata[6:0];
							if (wdata[6:4] != 3'b010) div <= 15'd0;     // the divider held in reset
						end
						7'h0B: begin
							reg_b <= wdata[7] ? {wdata[7:5], 1'b0, wdata[3:0]} : wdata;   // SET clears UIE
						end
						7'h0C, 7'h0D: ;                                     // read only
						default: cmos_ram[index] <= wdata;
					endcase
				end
				else begin
					case (index)
						7'h00: rdata <= show({1'b0, sec}, bin);
						7'h01: rdata <= sec_a_raw;
						7'h02: rdata <= show({1'b0, min}, bin);
						7'h03: rdata <= min_a_raw;
						7'h04: rdata <= show_hour(hour, bin, h24);
						7'h05: rdata <= hour_a_raw;
						7'h06: rdata <= {5'd0, dow};
						7'h07: rdata <= show({2'd0, date}, bin);
						7'h08: rdata <= show({3'd0, month}, bin);
						7'h09: rdata <= show(year, bin);
						7'h0A: rdata <= {uip, reg_a};
						7'h0B: rdata <= reg_b;
						7'h0C: begin
							rdata <= {irq8, flags[2], flags[1], flags[0], 4'd0};
							flags <= 3'd0;
						end
						7'h0D: rdata <= 8'h80;                              // the battery is good
						default: rdata <= cmos_ram[index];
					endcase
				end
			end
			3'd4: if (we) nv_addr[7:0]  <= wdata; else rdata <= nv_addr[7:0];
			3'd5: if (we) nv_addr[11:8] <= wdata[3:0]; else rdata <= {4'd0, nv_addr[11:8]};
			3'd6: if (!we) rdata <= nv_q;                // (the write: below)
			default: if (!we) rdata <= 8'hFF;
		endcase
	end

	// the maintenance port's CMOS write (0E-7F), in a cycle the CPU leaves the RTC alone
	if (m_we && !sel && m_addr[12] && m_addr[6:0] >= 7'h0E) cmos_ram[m_addr[6:0]] <= m_wdata;

	if (set_time) begin
		sec   <= 6'(from_bcd(time_bcd[7:0]));
		min   <= 6'(from_bcd(time_bcd[15:8]));
		hour  <= 5'(from_bcd(time_bcd[23:16]));
		date  <= 5'(from_bcd(time_bcd[31:24]));
		month <= 4'(from_bcd(time_bcd[39:32]));
		year  <= from_bcd(time_bcd[47:40]);
		dow   <= time_bcd[50:48] + 3'd1;                        // the MiSTer's 0-6 from Sunday; the chip's 1-7
	end

	if (reset) begin
		// what a power-on reset of the chip clears (the time and the CMOS are battery-backed)
		reg_b[6:4] <= 3'b000;
		flags      <= 3'd0;
		index      <= 7'd0;
		nmi_mask   <= 1'b1;
	end
end
// the NVRAM's write: the CPU's, else the maintenance port's in a cycle the CPU leaves the RTC alone
wire        cpu_nvw = sel & we & (port == 3'd6);
assign      m_ok    = ~sel;
wire        nv_we   = cpu_nvw | (m_we & m_ok & ~m_addr[12]);
always_ff @(posedge clk) begin
	if (nv_we) nvram[cpu_nvw ? nv_addr : m_addr[11:0]] <= cpu_nvw ? wdata : m_wdata;
	nv_q <= nvram[nv_addr];
end
// the maintenance port's reads (a second read port), and its CMOS
logic [7:0] m_nq, m_cq;
logic       m_c;
always_ff @(posedge clk) begin
	m_nq <= nvram[m_addr[11:0]];
	m_cq <= cmos_ram[m_addr[6:0]];
	m_c  <= m_addr[12];
end
assign m_q = m_c ? m_cq : m_nq;
// the CPU's writes counted (Gray, for the SD side's clock)
logic [7:0] wr_n = 8'd0;
always_ff @(posedge clk) begin
	if (cpu_nvw || (sel && we && port == 3'd1 && index >= 7'h0E)) wr_n <= wr_n + 8'd1;
	wr_seq <= wr_n ^ (wr_n >> 1);
end

assign irq8 = |(flags & reg_b[6:4]);

// a sensible clock before the first set_time (the bench, or a MiSTer without one)
// The CMOS as the firmware's init_cmos leaves it, its "the CMOS was reset" bit (1F bit 5) clear:
// the century 19 at 1A, the rest zero, the CRCs over 20-2D (at 2E-2F) and 30-3D (at 3E-3F)
// valid (scratch/work/cmos_image.py). A blank CMOS fails those CRCs, so init_cmos runs and sets
// the bit, and with it set the boot program (BOOT.6XE, through password() and security(35))
// gives up without trying a device: on the real machine the boot after a battery change.
initial begin
	for (int i = 0; i < 128; i++) cmos_ram[i] = 8'h00;
	cmos_ram[7'h1A] = 8'h19;
	cmos_ram[7'h2E] = 8'hA9; cmos_ram[7'h2F] = 8'h6A;
	cmos_ram[7'h3E] = 8'hA9; cmos_ram[7'h3F] = 8'h6A;
end
// The NVRAM as the firmware's own formatter leaves it (NVRAMAccess's initialisation path): a
// header nvram_good accepts (size 4 KB, version 1, revision 4, LastOS 1, big-endian, the serial
// placeholder 'f' x 16, the GE area F8-9FF, an empty configuration area, the OS area A00-BFF,
// the two CRCs, which skip bytes 4-7), the areas blank. The firmware never formats a bad NVRAM
// at boot, and a blank one makes the residual data say NvramSize = -1 (firmware/tools/nvram_image.py).
// Keeping the firmware's and AIX's writes across core loads is the Main_MiSTer branch's job.
initial begin
	for (int i = 0; i < 4096; i++) nvram[i] = 8'h00;
	// NVRAM_IMAGE_BEGIN (generated by firmware/tools/nvram_image.py; do not edit by hand)
	nvram[12'd1] = 8'h04;
	nvram[12'd2] = 8'h01;
	nvram[12'd3] = 8'h04;
	nvram[12'd4] = 8'h01;
	nvram[12'd5] = 8'hD4;
	nvram[12'd6] = 8'hFF;
	nvram[12'd7] = 8'hFF;
	nvram[12'd8] = 8'h01;
	nvram[12'd9] = 8'h42;
	nvram[12'd100] = 8'h30;
	nvram[12'd101] = 8'h30;
	nvram[12'd102] = 8'h30;
	nvram[12'd103] = 8'h30;
	nvram[12'd104] = 8'h30;
	nvram[12'd105] = 8'h30;
	nvram[12'd106] = 8'h30;
	nvram[12'd107] = 8'h30;
	nvram[12'd108] = 8'h30;
	nvram[12'd109] = 8'h30;
	nvram[12'd110] = 8'h30;
	nvram[12'd111] = 8'h31;
	nvram[12'd112] = 8'h32;
	nvram[12'd113] = 8'h33;
	nvram[12'd114] = 8'h34;
	nvram[12'd115] = 8'h35;
	nvram[12'd199] = 8'hF8;
	nvram[12'd202] = 8'h09;
	nvram[12'd203] = 8'h08;
	nvram[12'd214] = 8'h10;
	nvram[12'd234] = 8'h0A;
	nvram[12'd238] = 8'h02;
	// NVRAM_IMAGE_END
end
initial begin
	sec = 6'd0; min = 6'd0; hour = 5'd12; date = 5'd1; month = 4'd1; year = 7'd26; dow = 3'd5;
	reg_a = 7'b010_0110; reg_b = 8'b0000_0010; div = '0;
	sec_a_raw = 8'd0; min_a_raw = 8'd0; hour_a_raw = 8'd0; sec_a = '0; min_a = '0; hour_a = '0;
end

endmodule
