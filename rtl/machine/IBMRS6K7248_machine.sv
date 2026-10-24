//============================================================================
//
//  IBMRS6K7248 - the machine around the CPU
//  The IBM RS/6000 43P 7248 ("Carolina", a PReP board): the address map and
//  the device stubs, first form
//
//  Sits on the CPU's side of the clock crossing, in the CPU's clock. It takes
//  the CPU's memory port, decodes the address, answers device accesses
//  itself and passes RAM and ROM reads on, as SDRAM offsets, to
//  DSPPC604_memcdc. The protocol is the CPU's port's on both sides: one
//  request at a time, req held until ack, a 32-byte line or one word with
//  byte enables (the lowest address in bits 255-224 or 31-24, be[3]).
//
//  The map, the PReP one as the IBM 27-82660 host bridge decodes it in
//  contiguous I/O mode (to be checked against the firmware: see
//  docs/firmware_analysis.md):
//
//    00000000-3FFFFFFF  system memory      the MPC105's eight banks (their
//                                          start, end and enable registers,
//                                          IBMRS6K7248_mpc105); a bank with
//                                          DRAM behind it reaches the SDRAM
//                                          (below), an address no such bank
//                                          holds reads the value last driven
//                                          onto the memory bus (what the
//                                          firmware's bank probe expects of
//                                          an empty bank) and writes nothing
//    80000000-807FFFFF  ISA/PCI I/O        port = address[22:0] (contiguous);
//                                          devices below, the rest reads FF
//    80000CF8, 80000CFC PCI configuration  the MPC105's CONFIG_ADDR/CONFIG_DATA
//                                          (little-endian registers): bus 0
//                                          device 0 the MPC105, device 11 Fire
//                                          Coral; any other reads FFFFFFFF
//    80800000-80FFFFFF  PCI config direct  not used by this board: reads FFFFFFFF
//    81000000-BF7FFFFF  PCI I/O            port = address[29:0]: the 53C810's
//                                          BAR0 (2000_0000 as the firmware sets
//                                          it); the rest reads FF
//    BFFFF000-BFFFFFFF  interrupt ack      reads 0 (no 8259s yet)
//    C0000000-FEFFFFFF  PCI/ISA memory     reads FF
//    FFF00000-FFFFFFFF  system ROM         from SDRAM offset rom_at x 4 MB:
//                                          the soldered 512 KB flash at
//                                          FFF00000, the second socket at
//                                          FFF80000 (empty with a 512 KB
//                                          image, rom_512k: reads FF); writes go to
//                                          the device path and are ignored
//
//  The RAM: three SIMM pairs (simm_cfg, 3 bits each: 0 empty, 1 8 MB, one
//  bank of 8 MB; 2 16 MB, two of 8; 3 32 MB, one of 32; 4 64 MB, two of
//  32). Pair p holds banks 2p and 2p+1. The banks' DRAM lies in the SDRAM
//  one after another from offset 0, bank 0 first; within a bank the
//  address wraps at its size. The presence-detect byte of each pair is
//  read at ports 0880-0882 (FF empty; 88, BB, AA, 99 as the firmware's
//  table at FFF05BA4 has them).
//
//  Devices answered so far, in ISA I/O space:
//    0398-0399  the PC87312's configuration (IBMRS6K7248_sio); where it puts them:
//    COM1       a 16550A (IBMRS6K7248_uart) on the MiSTer's UART (3F8 at reset)
//    COM2       a 16550A with nothing on its line (2F8 at reset)
//    FDC        the floppy disk controller, its drive empty (3F0; IBMRS6K7248_fdc), IRQ 6
//    LPT        the parallel port's registers (378 at reset; the firmware's
//               progress codes go to its data latch at 3BC)
//    0020-0021, 00A0-00A1, 04D0-04D1   the 8259s and their ELCR (IBMRS6K7248_pic);
//               BFFFFFF0 read: the interrupt acknowledge
//    0040-0043, 0061   the 8254 and port 61 (IBMRS6K7248_pit)
//    0060, 0064 the 8042 with a PS/2 keyboard and mouse (IBMRS6K7248_kbc)
//    0070-0071, 0074-0076   the RTC and the 4 KB NVRAM (IBMRS6K7248_rtc)
//    0078-007F              the VPD EEPROM's controller (IBMRS6K7248_eeprom)
//    0279       the CS4232's configuration (the Crystal key and commands); its
//               Sound Blaster DSP and WSS codec where they are placed and
//               only while active, present but silent (IBMRS6K7248_cs4232)
//    0092       port 92 (stored; its endian bit is for little-endian mode)
//    0840-0844  the memory and L2 error status registers: no error (0)
//    0880-0882  SIMM presence detect (read only)
//    Fire Coral's BAR0 (1000 as the firmware sets it): its index/data pair
//    PCI device 16: the NCR 53C810 (IBMRS6K7248_ncr810) at its BAR0, IRQ 15
//               with the S3's; its DMA through the CPU's snoop port (below)
//    0852       planar ID (read only): the model, which the firmware reads to
//               choose its personality (F4-F7 a 7248, with SCSI: F5 100 MHz,
//               F4 120, F6/F7 133; F0-F3 a Power Series 830/850, without)
//
//  Every other access is a stub, and is reported on the io_* outputs (the
//  test bench logs them: that list is what the next devices are chosen
//  from).
//
//  A line request to a device is eight word accesses to it, the lowest
//  address first: with data translation off the 604 treats every address
//  as cacheable, so early firmware may reach devices through the cache.
//
//  Little-endian mode (LE_MODE): while the MPC105's PICR1 LE_MODE bit (5)
//  is set, the bridge swaps the byte lanes of each doubleword between the
//  CPU's bus and everything behind it (memory, ROM, PCI, ISA), which undoes
//  the 604's address munging (DSPPC604, LE_MODE): a word access reaches the
//  other word of its doubleword with its bytes reversed, a line has the
//  bytes of each of its doublewords reversed. Memory then holds what the
//  little-endian program meant. (To be checked against the MPC105 manual:
//  docs/plan.md, the little-endian track.)
//
//  The 53C810's DMA (one doubleword a request, PCI address 8000_0000 + n
//  for memory n, the MPC105's map; anything else a master abort) shares the
//  memory port with the CPU, as MacPPC7300's DMA does: its line goes first to
//  the CPU's snoop port (the caches write it back if dirty, and drop it for
//  a write), then the access takes the port when it is free, before any new
//  CPU access (a read: the line; a write: one or two words), then a write's
//  line is snooped again (a copy fetched in between is dropped). No byte
//  swapping: the bridge keeps bytes at their addresses for PCI masters in
//  either mode.
//
//  Also made here: tb_tick for the CPU's time base and decrementer, at
//  TB_HZ on average (the 604 counts every fourth bus clock: 16.67 MHz on a
//  66 MHz bus).
//
//============================================================================

module IBMRS6K7248_machine
#(
	parameter int unsigned CPU_HZ = 100_000_000,
	parameter int unsigned TB_HZ  = 16_666_667,
	parameter int unsigned LE_MODE = 1,            // 1: the MPC105's little-endian mode (PICR1's LE_MODE bit) swaps the bus
	parameter int unsigned UART_FAST = 0,          // 1 (the bench only): the serial ports run at CLK_HZ / 16
	parameter int unsigned RTC_FAST  = 0,          // 1 (the bench only): the RTC's seconds 64 x faster (the firmware's waits on the clock)
	parameter int unsigned STO_UNIT = CPU_HZ / 16000    // the 53C810's selection timeout unit
)
(
	input  logic         clk,
	input  logic         reset,
	input  logic [8:0]   simm_cfg,                  // the SIMM pairs, 3 bits each (above; quasi-static)
	input  logic [4:0]   rom_at,                    // the ROM's SDRAM offset in 4 MB (quasi-static)
	input  logic         rom_512k,                  // the ROM image is 512 KB: the second socket (FFF80000) is empty
	input  logic [7:0]   planar_id,                 // port 0852 (quasi-static)

	// the CPU's memory port
	input  logic         c_req,
	input  logic         c_we,
	input  logic         c_line,
	input  logic [31:2]  c_addr,
	input  logic [3:0]   c_be,
	input  logic [255:0] c_wdata,
	output logic         c_ack,
	output logic [255:0] c_rdata,

	// RAM and ROM, by SDRAM offset, to DSPPC604_memcdc
	output logic         m_req,
	output logic         m_we,
	output logic         m_line,
	output logic [31:2]  m_addr,
	output logic [3:0]   m_be,
	output logic [255:0] m_wdata,
	input  logic         m_ack,
	input  logic [255:0] m_rdata,

	// the CPU's snoop port (DSPPC604)
	output logic         snoop_req,
	output logic         snoop_we,
	output logic [31:5]  snoop_addr,
	input  logic         snoop_ack,

	// the 53C810's SCSI bus (IBMRS6K7248_scsitgt's byte-level one)
	output logic         sb_sel,
	output logic [2:0]   sb_sel_id,
	output logic         sb_sel_atn,
	input  logic         sb_sel_done,
	input  logic         sb_sel_fail,
	input  logic         sb_bsy,
	input  logic         sb_req,
	input  logic [2:0]   sb_phase,
	input  logic [7:0]   sb_tdata,
	output logic         sb_ack,
	output logic [7:0]   sb_idata,
	output logic         sb_ackhold,
	output logic         sb_atn,
	output logic         sb_rst,

	output logic         ext_irq,
	output logic         tb_tick,
	output logic         kbc_reset,                 // the 8042's reset line (a pulse)
	output logic         speaker,                   // the 8254's counter 2 through port 61

	// the keyboard and mouse (hps_io's), the time to start the RTC from
	input  logic [10:0]  ps2_key,
	input  logic [24:0]  ps2_mouse,
	input  logic         rtc_set,
	input  logic [55:0]  rtc_time,
	// the RTC's maintenance port (the NVRAM and CMOS kept on the SD card: IBMRS6K7248_nvsave)
	input  logic [12:0]  nv_m_addr,
	input  logic         nv_m_we,
	input  logic [7:0]   nv_m_wdata,
	output logic [7:0]   nv_m_q,
	output logic         nv_m_ok,
	output logic [7:0]   nv_wr_seq,

	// COM1
	output logic         com1_txd,
	input  logic         com1_rxd,
	input  logic         com1_cts_n,
	output logic         com1_rts_n,

	// the S3's VRAM (2 MB): words with byte enables by byte offset, req held until ack
	output logic         v_req,
	output logic         v_we,
	output logic [20:2]  v_addr,
	output logic [3:0]   v_be,
	output logic [31:0]  v_wdata,
	input  logic         v_ack,
	input  logic [31:0]  v_rdata,
	// and to and from its picture side (IBMRS6K7248_s3video, in clk_v)
	input  logic         clk_v,
	output logic [10:0]  h_total, h_disp, h_ss, h_sl, v_total, v_disp, v_ss,
	output logic [4:0]   v_sl,
	output logic [20:0]  v_start,
	output logic [11:0]  v_pitch,
	output logic         v_screen_on,
	output logic [7:0]   v_pix_mask,
	output logic [6:0]   v_pll_m, v_pll_n,
	output logic         v_cur_on,
	output logic [10:0]  v_cur_x, v_cur_y,
	output logic [10:0]  v_cur_base,
	output logic         v_cur_x11,
	output logic [7:0]   v_cur_fg, v_cur_bg,
	input  logic [7:0]   pal_vaddr,
	output logic [17:0]  pal_vq,
	input  logic         vretrace_v,
	input  logic         disp_en_v,

	// every device access as it is answered (for the test bench)
	output logic         io_ev,
	output logic         io_we,
	output logic         io_stub,                   // no device answered it
	output logic [31:0]  io_addr,
	output logic [3:0]   io_be,
	output logic [31:0]  io_wdata,
	output logic [31:0]  io_rdata
);

// ---- the time base ------------------------------------------------------------------------
localparam logic [31:0] TB_INC = 32'((64'(TB_HZ) << 32) / 64'(CPU_HZ));
logic [31:0] tb_acc = '0;
always_ff @(posedge clk) {tb_tick, tb_acc} <= {1'b0, tb_acc} + {1'b0, TB_INC};

// ---- the SIMMs: each bank's DRAM, its size and where it lies in the SDRAM ------------------
// (from the quasi-static simm_cfg, registered: out of the request's path)
logic [5:0]      bk_dram;               // the bank has DRAM
logic [5:0]      bk_big;                // ... 32 MB (else 8)
logic [5:0][7:0] bk_base;               // ... from this SDRAM offset, in MB
logic [2:0][7:0] simm_pd;               // the presence-detect bytes
// a pair's size in MB, its first bank's
function automatic logic [7:0] pair_mb(input logic [2:0] c);
	case (c)
		3'd1:    pair_mb = 8'd8;
		3'd2:    pair_mb = 8'd16;
		3'd3:    pair_mb = 8'd32;
		3'd4:    pair_mb = 8'd64;
		default: pair_mb = 8'd0;
	endcase
endfunction
function automatic logic [7:0] side_mb(input logic [2:0] c);
	side_mb = (c == 3'd3 || c == 3'd4) ? 8'd32 : (c == 3'd1 || c == 3'd2) ? 8'd8 : 8'd0;
endfunction
wire [2:0] pc0 = simm_cfg[2:0], pc1 = simm_cfg[5:3], pc2 = simm_cfg[8:6];
always_ff @(posedge clk) begin
	bk_dram <= {pc2 == 3'd2 || pc2 == 3'd4, pc2 != 3'd0 && pc2 <= 3'd4,
	            pc1 == 3'd2 || pc1 == 3'd4, pc1 != 3'd0 && pc1 <= 3'd4,
	            pc0 == 3'd2 || pc0 == 3'd4, pc0 != 3'd0 && pc0 <= 3'd4};
	bk_big  <= {{2{pc2 == 3'd3 || pc2 == 3'd4}}, {2{pc1 == 3'd3 || pc1 == 3'd4}}, {2{pc0 == 3'd3 || pc0 == 3'd4}}};
	bk_base[0] <= 8'd0;
	bk_base[1] <= side_mb(pc0);
	bk_base[2] <= pair_mb(pc0);
	bk_base[3] <= pair_mb(pc0) + side_mb(pc1);
	bk_base[4] <= pair_mb(pc0) + pair_mb(pc1);
	bk_base[5] <= pair_mb(pc0) + pair_mb(pc1) + side_mb(pc2);
	for (int p = 0; p < 3; p++)
		case (simm_cfg[3 * p +: 3])
			3'd1:    simm_pd[p] <= 8'h88;
			3'd2:    simm_pd[p] <= 8'hBB;
			3'd3:    simm_pd[p] <= 8'hAA;
			3'd4:    simm_pd[p] <= 8'h99;
			default: simm_pd[p] <= 8'hFF;
		endcase
end

// the MPC105's bank registers
logic [7:0]      bank_en;
logic [7:0][9:0] bank_start, bank_end;
logic [31:0]     picr1;

// ---- decode -------------------------------------------------------------------------------
// ---- the bridge's byte-lane swap in little-endian mode ------------------------------------
function automatic logic [31:0] rev32(input logic [31:0] x);
	rev32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
endfunction
// a line's bytes reversed within each doubleword: word i becomes word i ^ 1, reversed
function automatic logic [255:0] swap_line(input logic [255:0] x);
	for (int i = 0; i < 8; i++) swap_line[255 - 32 * i -: 32] = rev32(x[255 - 32 * (i ^ 1) -: 32]);
endfunction
wire          le_bus  = (LE_MODE != 0) & picr1[5];
wire  [31:2]  x_addr  = le_bus & ~c_line ? {c_addr[31:3], ~c_addr[2]} : c_addr;
wire  [3:0]   x_be    = le_bus ? {c_be[0], c_be[1], c_be[2], c_be[3]} : c_be;
wire  [255:0] x_wdata = ~le_bus ? c_wdata : c_line ? swap_line(c_wdata) : {224'h0, rev32(c_wdata[31:0])};

wire [31:0] a      = {x_addr, 2'b00};

// the bank holding an address (the lowest if programmed to overlap), and its MB's offset in
// the SDRAM: {hit, offset}
function automatic logic [8:0] ram_dec(input logic [31:20] ad);
	ram_dec = 9'd0;
	for (int n = 5; n >= 0; n--)
		if (bank_en[n] && bk_dram[n] && ad[31:30] == 2'b00 &&
		    ad[29:20] >= bank_start[n] && ad[29:20] <= bank_end[n])
			ram_dec = {1'b1, bk_base[n] + {3'd0, (ad[24:20] - bank_start[n][4:0]) & (bk_big[n] ? 5'h1F : 5'h07)}};
endfunction
wire  [8:0] c_dec     = ram_dec(a[31:20]);
wire        is_ram    = c_dec[8];
wire  [7:0] ram_mb_at = c_dec[7:0];             // SDRAM offset of the address's MB
wire        is_rom = a[31:20] == 12'hFFF && !(rom_512k && a[19]);
wire        to_mem = is_ram | (is_rom & ~c_we);
wire [19:2] rom_a  = a[19:2];

// ---- the 53C810's DMA and the CPU on the memory port ---------------------------------------
logic         dm_req, dm_we, dm_ack, dm_err;
logic [31:3]  dm_addr;
logic [7:0]   dm_be;
logic [63:0]  dm_wdata, dm_rdata;
wire  [31:0]  dpa     = {dm_addr, 3'b000};                 // the PCI address
wire  [8:0]   d_dec   = ram_dec({1'b0, dpa[30:20]});
wire          d_ok    = dpa[31] & d_dec[8];                // memory behind the MPC105's window

typedef enum logic [2:0] {DQ_IDLE, DQ_SNOOP, DQ_MEM, DQ_SNOOP2, DQ_DONE} dq_t;
dq_t          dq;
logic         dq_w1;                                       // a write's second word (be 3-0) still to go
logic         own_cpu, own_dma;                            // whose request the crossing holds
logic         snoop_gap;
wire          port_free = ~own_cpu & ~own_dma;
wire          grant_dma = port_free & (dq == DQ_MEM);
wire          grant_cpu = port_free & ~grant_dma & (dq != DQ_MEM) & c_req & to_mem & ~dev_busy;
wire          pres_dma  = own_dma | grant_dma;
// the doubleword's word this access is: a read takes the line, a write word 0 (be 7-4) then 1
wire          dm_hi     = dm_we & (dq_w1 | dm_be[7:4] == 4'h0);

assign snoop_req  = dq == DQ_SNOOP || (dq == DQ_SNOOP2 && !snoop_gap);
assign snoop_we   = dm_we;
assign snoop_addr = dpa[31:5] & 27'h3FF_FFFF;              // the memory address (bit 31 the window's)

assign m_req   = pres_dma | ((own_cpu | grant_cpu) & c_req & to_mem);
assign m_we    = pres_dma ? dm_we : c_we;
assign m_line  = pres_dma ? ~dm_we : c_line;
assign m_addr  = pres_dma ? {4'd0, d_dec[7:0], dpa[19:3], dm_hi} :
                 is_rom ? {5'd0, rom_at, 2'b00, rom_a} : {4'd0, ram_mb_at, a[19:2]};
assign m_be    = pres_dma ? (dm_hi ? dm_be[3:0] : dm_be[7:4]) : x_be;
assign m_wdata = pres_dma ? {224'h0, dm_hi ? dm_wdata[31:0] : dm_wdata[63:32]} : x_wdata;
wire   cpu_m_ack = m_ack & own_cpu;

always_ff @(posedge clk) begin
	dm_ack <= 1'b0;
	if (m_ack) begin
		own_cpu <= 1'b0;
		own_dma <= 1'b0;
	end
	else begin
		if (grant_cpu) own_cpu <= 1'b1;
		if (grant_dma) own_dma <= 1'b1;
	end
	snoop_gap <= 1'b0;
	case (dq)
		DQ_IDLE: if (dm_req && !dm_ack) begin
			dq_w1 <= 1'b0;
			if (!d_ok) begin                                   // a master abort
				dm_err <= 1'b1; dm_rdata <= 64'hFFFF_FFFF_FFFF_FFFF; dm_ack <= 1'b1; dq <= DQ_DONE;
			end
			else begin dm_err <= 1'b0; dq <= DQ_SNOOP; end
		end
		DQ_SNOOP: if (snoop_ack) dq <= DQ_MEM;
		DQ_MEM: if (m_ack && own_dma) begin
			dm_rdata <= m_rdata[255 - 64 * dpa[4:3] -: 64];
			if (dm_we && !dm_hi && dm_be[3:0] != 4'h0) dq_w1 <= 1'b1;      // the second word next
			else if (dm_we) begin snoop_gap <= 1'b1; dq <= DQ_SNOOP2; end
			else begin dm_ack <= 1'b1; dq <= DQ_DONE; end
		end
		DQ_SNOOP2: if (!snoop_gap && snoop_ack) begin dm_ack <= 1'b1; dq <= DQ_DONE; end
		default: dq <= DQ_IDLE;                                 // the acknowledge's cycle
	endcase
	if (reset) begin
		dq        <= DQ_IDLE;
		own_cpu   <= 1'b0;
		own_dma   <= 1'b0;
		snoop_gap <= 1'b0;
		dm_ack    <= 1'b0;
		dq_w1     <= 1'b0;
	end
end

// ---- device accesses, a word at a time ----------------------------------------------------
logic         dev_busy;                 // a device request taken, not yet answered
logic         dev_ack;
logic         d_we, d_line;
logic [31:2]  d_addr;                   // the line's first word, or the word
logic [3:0]   d_be;
logic [255:0] d_wdata;
logic [2:0]   d_k;                      // the word of the line
logic         d_sel;                    // the word's access, this cycle
logic         d_sel_q;
logic [31:0]  line_buf [8];

wire          dev_take = c_req & ~to_mem & ~dev_busy & ~dev_ack;
wire  [31:0]  p_a  = {d_addr[31:5], d_line ? d_k : d_addr[4:2], 2'b00};
wire  [31:0]  p_wd = d_line ? d_wdata[255 - 32 * d_k -: 32] : d_wdata[31:0];
wire  [3:0]   p_be = d_line ? 4'hF : d_be;

// A word is done the cycle after its access (d_sel_q), or, for the S3, when it answers
// (its engine may hold the bus: docs/s3_design.md 4.2)
logic         s3_sel, q_s3, s3_ack;
logic [31:0]  s3_rdata;
wire          w_done  = (d_sel_q & ~q_s3) | s3_ack;
logic [31:0]  dev_rdata;
wire  [31:0]  w_rdata = s3_ack ? s3_rdata : dev_rdata;

always_ff @(posedge clk) begin
	dev_ack <= 1'b0;
	d_sel   <= 1'b0;
	d_sel_q <= d_sel;
	if (dev_take) begin
		dev_busy <= 1'b1;
		d_we     <= c_we;
		d_line   <= c_line;
		d_addr   <= x_addr;
		d_be     <= x_be;
		d_wdata  <= x_wdata;
		d_k      <= 3'd0;
		d_sel    <= 1'b1;
	end
	if (w_done) begin
		line_buf[d_k] <= w_rdata;
		if (!d_line || d_k == 3'd7) dev_ack <= 1'b1;
		else begin
			d_k   <= d_k + 3'd1;
			d_sel <= 1'b1;
		end
	end
	if (dev_ack) dev_busy <= 1'b0;
	if (reset) begin
		dev_busy <= 1'b0;
		dev_ack  <= 1'b0;
		d_sel    <= 1'b0;
		d_sel_q  <= 1'b0;
	end
end

// the S3's request: from the word's access until its answer
always_ff @(posedge clk) begin
	if (d_sel & s3_hit) s3_sel <= 1'b1;
	if (s3_ack)         s3_sel <= 1'b0;
	if (reset)          s3_sel <= 1'b0;
end

// the regions
wire s_isa   = p_a[31:23] == 9'h100;                         // 80000000-807FFFFF
wire s_pcicf = p_a[31:23] == 9'h101;                         // 80800000-80FFFFFF
wire s_iack  = p_a[31:12] == 20'hBFFFF;
wire [15:0] port = p_a[15:0];

// the byte lane of a byte access (be[3] the lowest address); the ISA devices
// are byte wide: a wider access reaches the byte at its first enabled lane
logic [1:0] lane;
always_comb begin
	casez (p_be)
		4'b1???: lane = 2'd0;
		4'b01??: lane = 2'd1;
		4'b001?: lane = 2'd2;
		default: lane = 2'd3;
	endcase
end
wire [15:0] bport = {port[15:2], lane};
wire [7:0]  bwd   = p_wd[31 - 8 * lane -: 8];

// the PC87312: its configuration, its parallel port; then COM1 and COM2 where it puts them
logic        lpt_on, uart1_on, uart2_on, fdc_on, fdc_alt, ide_on, ide_alt;
logic [15:2] lpt_base;
logic [15:3] uart1_base, uart2_base;
logic  [7:0] sio_q, com2_q;
wire         sio_hit  = s_isa && bport[15:1] == 15'h01CC;                        // 398/399
wire         lpt_hit  = s_isa && lpt_on && bport[15:2] == lpt_base && bport[1:0] != 2'd3;
IBMRS6K7248_sio sio (
	.clk, .reset,
	.sel(d_sel & sio_hit), .lpt_sel(d_sel & lpt_hit), .we(d_we), .off(bport[1:0]), .wdata(bwd), .rdata(sio_q),
	.lpt_on, .lpt_base, .uart1_on, .uart1_base, .uart2_on, .uart2_base, .fdc_on, .fdc_alt, .ide_on, .ide_alt
);

// the floppy disk controller where the PC87312 puts it (3F0 or 370; not 3F6, the IDE's)
logic [7:0] fdc_q;
logic       irq6;
wire        fdc_hit = s_isa && fdc_on && bport[15:3] == (fdc_alt ? 13'h006E : 13'h007E) && bport[2:0] != 3'd6;
IBMRS6K7248_fdc fdc (
	.clk, .reset,
	.sel(d_sel & fdc_hit), .we(d_we), .off(bport[2:0]), .wdata(bwd), .rdata(fdc_q),
	.irq6
);

// COM1
wire        com1_hit = s_isa && uart1_on && bport[15:3] == uart1_base;
wire  [7:0] com1_q;
logic       com1_irq, com1_out2;
IBMRS6K7248_uart #(.CLK_HZ(CPU_HZ), .FAST(UART_FAST)) com1 (
	.clk, .reset,
	.sel(d_sel & com1_hit), .we(d_we), .addr(bport[2:0]), .wdata(bwd), .rdata(com1_q),
	.irq(com1_irq), .out2(com1_out2),
	.txd(com1_txd), .rxd(com1_rxd),
	.cts_n(com1_cts_n), .dsr_n(1'b0), .dcd_n(1'b0), .ri_n(1'b1),
	.rts_n(com1_rts_n), .dtr_n()
);

// COM2: nothing on its line
wire        com2_hit = s_isa && uart2_on && bport[15:3] == uart2_base;
logic       com2_irq, com2_out2;
IBMRS6K7248_uart #(.CLK_HZ(CPU_HZ), .FAST(UART_FAST)) com2 (
	.clk, .reset,
	.sel(d_sel & com2_hit), .we(d_we), .addr(bport[2:0]), .wdata(bwd), .rdata(com2_q),
	.irq(com2_irq), .out2(com2_out2),
	.txd(), .rxd(1'b1),
	.cts_n(1'b1), .dsr_n(1'b1), .dcd_n(1'b1), .ri_n(1'b1),
	.rts_n(), .dtr_n()
);

// ---- the S3 Vision864 (PCI device 14): its ports, its frame buffer --------------------------
wire        s_pcimem = p_a[31:30] == 2'b11 && p_a[31:24] != 8'hFF;      // C0000000-FEFFFFFF
logic       s3_io_hit, s3_mem_hit;
wire        s3_hit   = (s_isa & s3_io_hit) | (s_pcimem & s3_mem_hit);
logic [31:0] s3_cfg_q;
logic        s3_irq;
IBMRS6K7248_s3 #(.CLK_HZ(CPU_HZ)) s3 (
	.clk, .reset,
	.cfg_sel(d_sel & cfg_dev14), .cfg_we(d_we), .cfg_reg(cf8[7:2]), .cfg_be(le_be), .cfg_wdata(le_wd), .cfg_rdata(s3_cfg_q),
	.port({p_a[15:2], 2'b00}), .pci_addr({2'b00, p_a[29:0]}), .io_hit(s3_io_hit), .mem_hit(s3_mem_hit),
	.sel(s3_sel & ~s3_ack), .we(d_we), .is_mem(s_pcimem), .be(p_be), .wdata(p_wd), .rdata(s3_rdata), .ack(s3_ack),
	.v_req, .v_we, .v_addr, .v_be, .v_wdata, .v_ack, .v_rdata,
	.clk_v, .h_total, .h_disp, .h_ss, .h_sl, .v_total, .v_disp, .v_ss, .v_sl, .v_start, .v_pitch,
	.v_screen_on, .v_pix_mask, .v_pll_m, .v_pll_n, .v_cur_on, .v_cur_x, .v_cur_y, .v_cur_base, .v_cur_x11, .v_cur_fg, .v_cur_bg,
	.pal_vaddr, .pal_vq, .vretrace_v, .disp_en_v,
	.irq(s3_irq), .monitor_id(4'hF)
);

// ---- the NCR 53C810 (PCI device 16): its registers at BAR0 in PCI I/O space -------------------
wire         s_pciio = p_a[31:30] == 2'b10 && !s_pcicf && !s_iack;      // 80000000-BF7FFFFF less the above
logic        ncr_io_on;
logic [31:8] ncr_io_base;
wire         ncr_hit = s_pciio && ncr_io_on && ncr_io_base == {2'b00, p_a[29:8]};
logic [31:0] ncr_cfg_q, ncr_q;
logic        ncr_irq;
IBMRS6K7248_ncr810 #(.STO_UNIT(STO_UNIT)) ncr810 (
	.clk, .reset,
	.cfg_sel(d_sel & cfg_dev16), .cfg_we(d_we), .cfg_reg(cf8[7:2]), .cfg_be(le_be), .cfg_wdata(le_wd), .cfg_rdata(ncr_cfg_q),
	.io_on(ncr_io_on), .io_base(ncr_io_base),
	.sel(d_sel & ncr_hit), .we(d_we), .off(p_a[7:2]), .be(p_be), .wdata(p_wd), .rdata(ncr_q), .irq(ncr_irq),
	.dm_req, .dm_we, .dm_addr, .dm_be, .dm_wdata, .dm_ack, .dm_err, .dm_rdata,
	.sb_sel, .sb_sel_id, .sb_sel_atn, .sb_sel_done, .sb_sel_fail, .sb_bsy, .sb_req, .sb_phase, .sb_tdata,
	.sb_ack, .sb_idata, .sb_ackhold, .sb_atn, .sb_rst
);

// ---- the ISA core: the 8259s, the 8254, the 8042, the RTC and NVRAM, port 92 -------------
wire        pic_hit  = s_isa && (bport[15:1] == 15'h0010 || bport[15:1] == 15'h0050);   // 20/21, A0/A1
wire        elcr_hit = s_isa && bport[15:1] == 15'h0268;                            // 4D0/4D1
wire        pit_hit  = s_isa && (bport[15:2] == 14'h0010 || bport == 16'h0061);     // 40-43, 61
wire        kbc_hit  = s_isa && (bport == 16'h0060 || bport == 16'h0064);
wire        rtc_hit  = s_isa && (bport[15:1] == 15'h0038 || (bport[15:2] == 14'h001D && bport[1:0] != 2'd3));   // 70/71, 74-76
wire        p92_hit  = s_isa && bport == 16'h0092;
wire        ee_hit   = s_isa && bport[15:3] == 13'h000F;
// the IDE channels (1F0-1F7/3F6, 170-177/376): no drive on the 7248's SCSI planar; FF, as a
// floating bus, ends the firmware's probe at once (a stub's 0 made it poll the status 65 K times)
wire        ide_hit  = s_isa && (bport[15:3] == 13'h003E || bport == 16'h03F6 || bport[15:3] == 13'h002E || bport == 16'h0376);                              // 78-7F: the VPD EEPROM's controller
wire        err_hit  = s_isa && bport >= 16'h0840 && bport <= 16'h0844;
logic        aud_on;
logic [15:4] sb_base;
logic [15:2] wss_base;
wire        aud_cfg  = s_isa && bport == 16'h0279;
wire        sb_hit   = s_isa && aud_on && bport[15:4] == sb_base;
wire        wss_hit  = s_isa && aud_on && bport[15:2] == wss_base;

logic [15:0] irq;
logic  [7:0] pic_q, pit_q, kbc_q, rtc_q, aud_q, ee_q;
logic        irq0, irq1, irq8, irq12, nmi_mask;
logic  [7:0] p92;

IBMRS6K7248_pic pic (
	.clk, .reset,
	.sel(d_sel & (pic_hit | elcr_hit | (s_iack & ~d_we))), .we(d_we),
	.slave(elcr_hit ? bport[0] : bport[7]), .a0(bport[0]), .elcr_sel(elcr_hit), .iack(s_iack),
	.wdata(bwd), .rdata(pic_q),
	.irq, .intr(ext_irq)
);

IBMRS6K7248_pit #(.CLK_HZ(CPU_HZ)) pit (
	.clk, .reset,
	.sel(d_sel & pit_hit), .we(d_we), .p61(bport == 16'h0061), .a(bport[1:0]), .wdata(bwd), .rdata(pit_q),
	.irq0, .spk(speaker)
);

IBMRS6K7248_kbc #(.CLK_HZ(CPU_HZ)) kbc (
	.clk, .reset,
	.sel(d_sel & kbc_hit), .we(d_we), .cmd(bport[2]), .wdata(bwd), .rdata(kbc_q),
	.irq1, .irq12, .rst(kbc_reset),
	.ps2_key, .ps2_mouse
);

IBMRS6K7248_rtc #(.CLK_HZ(CPU_HZ), .FAST(RTC_FAST)) rtc (
	.clk, .reset,
	.sel(d_sel & rtc_hit), .we(d_we), .port(bport[2:0]), .wdata(bwd), .rdata(rtc_q),
	.irq8, .nmi_mask,
	.set_time(rtc_set), .time_bcd(rtc_time),
	.m_addr(nv_m_addr), .m_we(nv_m_we), .m_wdata(nv_m_wdata), .m_q(nv_m_q), .m_ok(nv_m_ok), .wr_seq(nv_wr_seq)
);

IBMRS6K7248_eeprom eeprom (
	.clk, .reset,
	.sel(d_sel & ee_hit), .we(d_we), .port(bport[2:0]), .wdata(bwd), .rdata(ee_q)
);

IBMRS6K7248_cs4232 cs4232 (
	.clk, .reset,
	.cfg_sel(d_sel & d_we & aud_cfg),
	.sel(d_sel & (sb_hit | wss_hit)), .we(d_we), .wss(wss_hit), .off(bport[3:0]), .wdata(bwd), .rdata(aud_q),
	.on(aud_on), .sb_base, .wss_base
);

always_ff @(posedge clk) begin
	if (d_sel & d_we & p92_hit) p92 <= bwd;
	if (reset) p92 <= 8'h00;
end

// the request lines: COM1's INTR as a PC board gates it, with OUT2
// IRQ 15: every PCI device's interrupt (Carolina's routing): the S3's and the 53C810's
assign irq = {s3_irq | ncr_irq, 2'b00, irq12, 3'b000, irq8, 3'b000, com1_irq & com1_out2, com2_irq & com2_out2, 1'b0, irq1, irq0} | (16'(irq6) << 6);

// the planar ID, the SIMMs' presence detect
wire        planar_hit = s_isa && bport == 16'h0852;
wire        pd_hit     = s_isa && bport[15:2] == 14'h0220 && bport[1:0] != 2'd3;   // 0880-0882

// the memory bus's last value: what an address no bank holds reads (the CPU's
// last word written to memory or to such an address)
logic [31:0] mem_bus;
always_ff @(posedge clk) begin
	if (m_ack & m_we & ~m_line) mem_bus <= m_wdata[31:0];
	if (m_ack & m_we &  m_line) mem_bus <= m_wdata[31:0];          // a line's last word
	if (d_sel & d_we & ~d_addr[31]) mem_bus <= p_wd;
end

// ---- PCI configuration: CONFIG_ADDR (CF8) and CONFIG_DATA (CFC), little-endian ----------
// The CPU's byte lane k (be[3-k], bits 31-8k) is the register's byte k.
function automatic logic [31:0] swap32(input logic [31:0] x);
	swap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
endfunction
wire  [3:0] le_be = {p_be[0], p_be[1], p_be[2], p_be[3]};
wire [31:0] le_wd = swap32(p_wd);
logic [31:0] cf8;
wire        cf8_hit = s_isa && port == 16'h0CF8;
wire        cfc_hit = s_isa && port == 16'h0CFC;
wire        cfg_on  = cf8[31] && cf8[23:16] == 8'd0 && cf8[10:8] == 3'd0;   // bus 0, function 0
wire        cfg_dev0  = cfc_hit && cfg_on && cf8[15:11] == 5'd0;
wire        cfg_dev11 = cfc_hit && cfg_on && cf8[15:11] == 5'd11;
wire        cfg_dev14 = cfc_hit && cfg_on && cf8[15:11] == 5'd14;
wire        cfg_dev16 = cfc_hit && cfg_on && cf8[15:11] == 5'd16;
always_ff @(posedge clk) begin
	if (d_sel & d_we & cf8_hit)
		for (int k = 0; k < 4; k++) if (le_be[k]) cf8[8 * k +: 8] <= le_wd[8 * k +: 8];
	if (reset) cf8 <= 32'h0;
end

logic [31:0] mpc_q, fc_q;
IBMRS6K7248_mpc105 mpc105 (
	.clk, .reset,
	.sel(d_sel & cfg_dev0), .we(d_we), .reg_n(cf8[7:2]), .be(le_be), .wdata(le_wd), .rdata(mpc_q),
	.bank_en, .bank_start, .bank_end, .picr1
);

// Fire Coral: its configuration, and its index/data pair at BAR0
logic        fc_io_on;
logic [15:3] fc_io_base;
logic  [7:0] fc_io_q;
wire         fc_io_hit = s_isa && fc_io_on && bport[15:3] == fc_io_base;
IBMRS6K7248_firecoral firecoral (
	.clk, .reset,
	.sel(d_sel & cfg_dev11), .we(d_we), .reg_n(cf8[7:2]), .be(le_be), .wdata(le_wd), .rdata(fc_q),
	.io_on(fc_io_on), .io_base(fc_io_base),
	.io_sel(d_sel & fc_io_hit), .io_we(d_we), .io_off(bport[2:0]), .io_wdata(bwd), .io_rdata(fc_io_q)
);

// the answer, the cycle after the access
logic       q_sio, q_com2, q_dev14, q_fdc;
logic       q_pic, q_pit, q_kbc, q_rtc, q_p92, q_err, q_aud, q_audc, q_ee, q_ide;
logic       q_com1, q_planar, q_pd, q_cf8, q_cfc, q_dev0, q_dev11, q_fcio, q_pcicf, q_iack, q_dev16, q_ncr;
logic [1:0] q_lane;
always_ff @(posedge clk) if (d_sel) begin
	q_com1  <= com1_hit;
	q_com2  <= com2_hit;
	q_fdc   <= fdc_hit;
	q_sio   <= sio_hit | lpt_hit;
	q_pic   <= pic_hit | elcr_hit;
	q_pit   <= pit_hit;
	q_kbc   <= kbc_hit;
	q_rtc   <= rtc_hit;
	q_ee    <= ee_hit;
	q_ide   <= ide_hit;
	q_p92   <= p92_hit;
	q_err   <= err_hit;
	q_aud   <= sb_hit | wss_hit;
	q_audc  <= aud_cfg;
	q_planar <= planar_hit;
	q_pd    <= pd_hit;
	q_cf8   <= cf8_hit;
	q_cfc   <= cfc_hit;
	q_dev0  <= cfg_dev0;
	q_dev11 <= cfg_dev11;
	q_dev14 <= cfg_dev14;
	q_dev16 <= cfg_dev16;
	q_ncr   <= ncr_hit;
	q_s3    <= s3_hit;
	q_fcio  <= fc_io_hit;
	q_pcicf <= s_pcicf;
	q_iack  <= s_iack;
	q_lane  <= lane;
end

always_comb begin
	if      (q_com1)  dev_rdata = {4{com1_q}};               // every lane: the byte reaches whichever one was asked
	else if (q_com2)  dev_rdata = {4{com2_q}};
	else if (q_fdc)   dev_rdata = {4{fdc_q}};
	else if (q_sio)   dev_rdata = {4{sio_q}};
	else if (q_pic)   dev_rdata = {4{pic_q}};
	else if (q_pit)   dev_rdata = {4{pit_q}};
	else if (q_kbc)   dev_rdata = {4{kbc_q}};
	else if (q_rtc)   dev_rdata = {4{rtc_q}};
	else if (q_ee)    dev_rdata = {4{ee_q}};
	else if (q_ide)   dev_rdata = 32'hFFFF_FFFF;
	else if (q_p92)   dev_rdata = {4{p92}};
	else if (q_err)   dev_rdata = 32'h0000_0000;
	else if (q_aud)   dev_rdata = {4{aud_q}};
	else if (q_planar) dev_rdata = {4{planar_id}};
	else if (q_pd)    dev_rdata = {4{simm_pd[q_lane]}};
	else if (q_fcio)  dev_rdata = {4{fc_io_q}};
	else if (q_cf8)   dev_rdata = swap32(cf8);
	else if (q_cfc)   dev_rdata = q_dev0 ? swap32(mpc_q) : q_dev11 ? swap32(fc_q) : q_dev14 ? swap32(s3_cfg_q) :
	                              q_dev16 ? swap32(ncr_cfg_q) : 32'hFFFF_FFFF;
	else if (q_ncr)   dev_rdata = ncr_q;
	else if (q_pcicf) dev_rdata = 32'hFFFF_FFFF;
	else if (q_iack)  dev_rdata = {4{pic_q}};             // the vector
	else if (d_addr[31]) dev_rdata = 32'hFFFF_FFFF;          // I/O and bus space: nothing answers
	else              dev_rdata = mem_bus;                   // memory no bank holds: the bus floats
end


// ---- the bench's view ---------------------------------------------------------------------
always_ff @(posedge clk) begin
	io_ev <= w_done;
	if (w_done) begin
		io_we    <= d_we;
		io_stub  <= ~(q_s3 | q_fdc | q_com1 | q_com2 | q_sio | q_planar | q_pd | q_fcio | q_cf8 | q_dev0 | q_dev11 | q_dev14 | q_dev16 | q_ncr |
		              q_pic | q_pit | q_kbc | q_rtc | q_ee | q_ide | q_p92 | q_err | q_aud | q_audc | q_iack);
		io_addr  <= p_a;
		io_be    <= p_be;
		io_wdata <= p_wd;
		io_rdata <= w_rdata;
	end
	if (reset) io_ev <= 1'b0;
end

// ---- to the CPU -------------------------------------------------------------------------
assign c_ack   = cpu_m_ack | dev_ack;
logic [255:0] x_rdata;
assign c_rdata = ~le_bus ? x_rdata : c_line ? swap_line(x_rdata) : {224'h0, rev32(x_rdata[31:0])};
assign x_rdata = ~dev_ack ? m_rdata :
                 d_line   ? {line_buf[0], line_buf[1], line_buf[2], line_buf[3],
                             line_buf[4], line_buf[5], line_buf[6], line_buf[7]} :
                            {224'h0, line_buf[0]};

endmodule
