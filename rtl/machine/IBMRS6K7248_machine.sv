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
//    00000000-7FFFFFFF  system memory      ram_mb MB from SDRAM offset 0;
//                                          beyond it reads 0, writes ignored
//    80000000-807FFFFF  ISA/PCI I/O        port = address[22:0] (contiguous);
//                                          devices below, the rest reads FF
//    80800000-80FFFFFF  PCI config direct  no devices yet: reads FFFFFFFF
//    81000000-BF7FFFFF  PCI I/O            reads FF
//    BFFFF000-BFFFFFFF  interrupt ack      reads 0 (no 8259s yet)
//    C0000000-FEFFFFFF  PCI/ISA memory     reads FF
//    FFF00000-FFFFFFFF  system ROM         from SDRAM offset rom_at x 4 MB:
//                                          the soldered 512 KB flash at
//                                          FFF00000, the second socket at
//                                          FFF80000 (empty with a 512 KB
//                                          image, rom_512k: reads FF); writes go to
//                                          the device path and are ignored
//
//  Devices answered so far, in ISA I/O space:
//    03F8-03FF  COM1, a 16550A (IBMRS6K7248_uart) on the MiSTer's UART
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
//  Also made here: tb_tick for the CPU's time base and decrementer, at
//  TB_HZ on average (the 604 counts every fourth bus clock: 16.67 MHz on a
//  66 MHz bus).
//
//============================================================================

module IBMRS6K7248_machine
#(
	parameter int unsigned CPU_HZ = 100_000_000,
	parameter int unsigned TB_HZ  = 16_666_667
)
(
	input  logic         clk,
	input  logic         reset,
	input  logic [7:0]   ram_mb,                    // installed RAM, MB
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

	output logic         ext_irq,
	output logic         tb_tick,

	// COM1
	output logic         com1_txd,
	input  logic         com1_rxd,
	input  logic         com1_cts_n,
	output logic         com1_rts_n,

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

// ---- decode -------------------------------------------------------------------------------
wire [31:0] a      = {c_addr, 2'b00};
wire        is_ram = ~a[31] && a[30:20] < {3'd0, ram_mb};
wire        is_rom = a[31:20] == 12'hFFF && !(rom_512k && a[19]);
wire        to_mem = is_ram | (is_rom & ~c_we);
wire [19:2] rom_a  = a[19:2];

assign m_req   = c_req & to_mem & ~dev_busy;
assign m_we    = c_we;
assign m_line  = c_line;
assign m_addr  = is_rom ? {5'd0, rom_at, 2'b00, rom_a} : {3'd0, a[28:2]};
assign m_be    = c_be;
assign m_wdata = c_wdata;

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

always_ff @(posedge clk) begin
	dev_ack <= 1'b0;
	d_sel   <= 1'b0;
	d_sel_q <= d_sel;
	if (dev_take) begin
		dev_busy <= 1'b1;
		d_we     <= c_we;
		d_line   <= c_line;
		d_addr   <= c_addr;
		d_be     <= c_be;
		d_wdata  <= c_wdata;
		d_k      <= 3'd0;
		d_sel    <= 1'b1;
	end
	if (d_sel_q) begin
		line_buf[d_k] <= dev_rdata;
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

// COM1
wire        com1_hit = s_isa && bport[15:3] == 13'h007F;     // 03F8-03FF
wire  [7:0] com1_q;
logic       com1_irq, com1_out2;
IBMRS6K7248_uart #(.CLK_HZ(CPU_HZ)) com1 (
	.clk, .reset,
	.sel(d_sel & com1_hit), .we(d_we), .addr(bport[2:0]), .wdata(bwd), .rdata(com1_q),
	.irq(com1_irq), .out2(com1_out2),
	.txd(com1_txd), .rxd(com1_rxd),
	.cts_n(com1_cts_n), .dsr_n(1'b0), .dcd_n(1'b0), .ri_n(1'b1),
	.rts_n(com1_rts_n), .dtr_n()
);

// the planar ID
wire        planar_hit = s_isa && bport == 16'h0852;

// the answer, the cycle after the access
logic       q_com1, q_planar, q_pcicf, q_iack;
logic [1:0] q_lane;
always_ff @(posedge clk) if (d_sel) begin
	q_com1  <= com1_hit;
	q_planar <= planar_hit;
	q_pcicf <= s_pcicf;
	q_iack  <= s_iack;
	q_lane  <= lane;
end

logic [31:0] dev_rdata;
always_comb begin
	if      (q_com1)  dev_rdata = {4{com1_q}};               // every lane: the byte reaches whichever one was asked
	else if (q_planar) dev_rdata = {4{planar_id}};
	else if (q_pcicf) dev_rdata = 32'hFFFF_FFFF;
	else if (q_iack)  dev_rdata = 32'h0000_0000;
	else if (d_addr[31]) dev_rdata = 32'hFFFF_FFFF;          // I/O and bus space: nothing answers
	else              dev_rdata = 32'h0000_0000;             // RAM beyond the installed memory
end

assign ext_irq = 1'b0;                  // no interrupt controller yet (COM1's INTR goes to the 8259s' IRQ4)

// ---- the bench's view ---------------------------------------------------------------------
always_ff @(posedge clk) begin
	io_ev <= d_sel_q;
	if (d_sel_q) begin
		io_we    <= d_we;
		io_stub  <= ~(q_com1 | q_planar);
		io_addr  <= p_a;
		io_be    <= p_be;
		io_wdata <= p_wd;
		io_rdata <= dev_rdata;
	end
	if (reset) io_ev <= 1'b0;
end

// ---- to the CPU -------------------------------------------------------------------------
assign c_ack   = m_ack | dev_ack;
assign c_rdata = ~dev_ack ? m_rdata :
                 d_line   ? {line_buf[0], line_buf[1], line_buf[2], line_buf[3],
                             line_buf[4], line_buf[5], line_buf[6], line_buf[7]} :
                            {224'h0, line_buf[0]};

endmodule
