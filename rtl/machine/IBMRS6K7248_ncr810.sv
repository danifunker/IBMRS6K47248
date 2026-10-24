//============================================================================
//
//  IBMRS6K7248 - the NCR 53C810 PCI SCSI controller (PCI device 16)
//
//  docs/scsi_design.md has what the firmware's driver uses (section 1) and
//  this design (section 5). The SCRIPTS processor is the HP 9000/715 core's
//  ncr53c710.sv (rtl/scsi/ncr53c710.sv there: a 53C710 running HP-UX),
//  carried to the 810:
//    - the 810's register map (7-bit addresses, 00-5F), SIST0/SIST1 with
//      SIEN0/SIEN1 in place of the 710's SSTAT0/SIEN, ISTAT at 14 with
//      INTF, CTEST3's revision and CLF, STEST3's CSF, SCRATCHB, RESPID,
//      STIME0 (the selection timeout's code), MACNTL, GPREG/GPCNTL;
//    - register instructions with the 810's eight operators (= SHL OR XOR
//      AND SHR ADD ADC) and 7-bit addresses; INTFLY (INT with bit 20: sets
//      ISTAT.INTF and goes on); SELECT with an encoded ID;
//    - its words read little-endian from memory (PCI): the program, the
//      table entries, the memory move's; data bytes keep their addresses;
//    - DFIFO reads DBC's low 7 bits (no FIFO: what is in flight is always
//      0, as the driver's residual arithmetic wants), DSTAT.DFE always 1.
//  Phase 1 (docs/scsi_design.md 5.8): no LOAD/STORE, no memory BAR (its
//  register writes are stored, nothing decodes it), no reselection, no
//  timers but the selection's, no single step, no target mode.
//
//  The host side: PCI configuration (as IBMRS6K7248_firecoral's: register
//  number, byte k in wdata[8k+7:8k]), and BAR0's 256 bytes of I/O: one
//  access a cycle of up to four registers, off[7:2], be[3] the lowest
//  address's, its byte in wdata[31:24] (the CPU's byte lanes, as the
//  machine's device bus has them); the read value in rdata the cycle after
//  sel. Register reads that clear (DSTAT, SIST0, SIST1, CTEST2's SIGP) do so
//  only for the lanes enabled.
//
//  DMA: one doubleword a request, dm_addr the PCI address (the machine
//  maps 8000_0000 + n to memory n, and answers dm_err for anything else:
//  a master abort, DSTAT.BF), dm_be[7] / dm_*data[63:56] the byte at the
//  doubleword's lowest address.
//
//  The SCSI bus is IBMRS6K7248_scsitgt's byte-level one.
//
//============================================================================

module IBMRS6K7248_ncr810 #(
	parameter int STO_UNIT = 6250               // clocks per 1/16 ms (100 MHz): STIME0 code n = 2^n units
)
(
	input  logic        clk,
	input  logic        reset,

	// PCI configuration
	input  logic        cfg_sel,
	input  logic        cfg_we,
	input  logic [7:2]  cfg_reg,
	input  logic [3:0]  cfg_be,                 // bit k: byte k (little-endian)
	input  logic [31:0] cfg_wdata,
	output logic [31:0] cfg_rdata,
	output logic        io_on,                  // BAR0 decoded
	output logic [31:8] io_base,

	// the registers (BAR0)
	input  logic        sel,
	input  logic        we,
	input  logic [7:2]  off,
	input  logic [3:0]  be,                     // be[3]: the lowest address
	input  logic [31:0] wdata,
	output logic [31:0] rdata,
	output logic        irq,

	// DMA: one doubleword, held until dm_ack
	output logic        dm_req,
	output logic        dm_we,
	output logic [31:3] dm_addr,
	output logic [7:0]  dm_be,
	output logic [63:0] dm_wdata,
	input  logic        dm_ack,
	input  logic        dm_err,
	input  logic [63:0] dm_rdata,

	// the SCSI bus
	output logic        sb_sel,
	output logic [2:0]  sb_sel_id,
	output logic        sb_sel_atn,
	input  logic        sb_sel_done,
	input  logic        sb_sel_fail,
	input  logic        sb_bsy,
	input  logic        sb_req,
	input  logic [2:0]  sb_phase,
	input  logic [7:0]  sb_tdata,
	output logic        sb_ack,
	output logic [7:0]  sb_idata,
	output logic        sb_ackhold,
	output logic        sb_atn,
	output logic        sb_rst
);

// ---- PCI configuration ----------------------------------------------------------------------
localparam logic [7:0] REV = 8'h02;
logic [15:0] pci_cmd;
logic [4:0]  pci_sts_w1c;                       // status bits 15-11
logic        pci_sts_dpd;                       // status bit 8
logic [7:0]  pci_cls, pci_lat, pci_intl;
logic [31:8] bar0, bar1;
logic        set_ma;                            // a master abort (from the engine)
always_ff @(posedge clk) begin
	if (cfg_sel & cfg_we)
		case (cfg_reg)
			6'h01: begin
				if (cfg_be[0]) pci_cmd[7:0] <= cfg_wdata[7:0] & 8'h47;
				if (cfg_be[1]) pci_cmd[15:8] <= cfg_wdata[15:8] & 8'h01;
				if (cfg_be[3]) pci_sts_w1c <= pci_sts_w1c & ~cfg_wdata[31:27];
				if (cfg_be[3]) pci_sts_dpd <= pci_sts_dpd & ~cfg_wdata[24];
			end
			6'h03: begin
				if (cfg_be[0]) pci_cls <= cfg_wdata[7:0];
				if (cfg_be[1]) pci_lat <= cfg_wdata[15:8];
			end
			6'h04: for (int k = 1; k < 4; k++) if (cfg_be[k]) bar0[8 * k +: 8] <= cfg_wdata[8 * k +: 8];
			6'h05: for (int k = 1; k < 4; k++) if (cfg_be[k]) bar1[8 * k +: 8] <= cfg_wdata[8 * k +: 8];
			6'h0F: if (cfg_be[0]) pci_intl <= cfg_wdata[7:0];
			default: ;
		endcase
	if (set_ma) pci_sts_w1c[2] <= 1'b1;            // bit 13: received master abort
	if (reset) begin
		pci_cmd <= 16'h0; pci_sts_w1c <= 5'd0; pci_sts_dpd <= 1'b0;
		pci_cls <= 8'h0; pci_lat <= 8'h0; pci_intl <= 8'h0;
		bar0 <= 24'h0; bar1 <= 24'h0;
	end
end
always_ff @(posedge clk) if (cfg_sel & ~cfg_we)
	case (cfg_reg)
		6'h00:   cfg_rdata <= 32'h0001_1000;
		6'h01:   cfg_rdata <= {pci_sts_w1c, 2'b01, pci_sts_dpd, 8'h00, pci_cmd};   // medium DEVSEL
		6'h02:   cfg_rdata <= {24'h01_0000, REV};
		6'h03:   cfg_rdata <= {16'h0000, pci_lat, pci_cls};
		6'h04:   cfg_rdata <= {bar0, 8'h01};
		6'h05:   cfg_rdata <= {bar1, 8'h00};
		6'h0F:   cfg_rdata <= {8'h40, 8'h11, 8'h01, pci_intl};                   // MAX_LAT, MIN_GNT, INTA
		default: cfg_rdata <= 32'h0;
	endcase
assign io_on   = pci_cmd[0];
assign io_base = bar0;

// ---- the chip's registers -------------------------------------------------------------------
logic [7:0]  scntl0, scntl1, scntl2, scntl3, scid, sxfer, sdid, gpreg, sfbr, socl, ssid;
logic [6:0]  dstat_st, dstat_pend;              // DSTAT 6-0 (DFE separately)
logic [7:0]  sist0_st, sist0_pend;
logic [2:0]  sist1_st, sist1_pend;
logic [2:0]  latched_phase;                     // SSTAT1's: the phase at the last REQ
logic [31:0] dsa, temp, dnad, dsp, dsps, scratcha, scratchb, adder;
logic [7:0]  ctest0, ctest3_w, ctest4, ctest5, ctest6;
logic [23:0] dbc;
logic [7:0]  dcmd;
logic [7:0]  dmode, dien, sbr, dcntl;
logic [7:0]  sien0;
logic [2:0]  sien1;
logic [7:0]  slpar, macntl, gpcntl, stime0, stime1, respid, stest1, stest2, stest3_w;
logic [7:0]  sidl, sodl;
logic        sigp, sem, intf, abrt_req, srst, carry;
logic        con;                                // connected
logic        bsy_q;
logic        target_mode;

wire         sip    = sist0_st != 8'd0 || sist1_st != 3'd0;
wire         dip    = dstat_st != 7'd0;
wire  [7:0]  dstat  = {1'b1, dstat_st};                       // DFE: no FIFO
wire  [7:0]  istat  = {abrt_req, srst, sigp, sem, con, intf, sip, dip};
wire  [7:0]  sstat0 = {6'd0, sb_rst, 1'b0};
wire  [7:0]  sstat1 = {5'd0, latched_phase};
wire  [7:0]  sbcl   = {sb_req, sb_ack | sb_ackhold, sb_bsy, sb_sel, sb_atn, sb_phase};
wire  [7:0]  sbdl   = sb_req ? sb_tdata : sodl;
wire  [7:0]  ctest1 = 8'hF0;                                  // the FIFO's lanes empty
wire  [7:0]  ctest2 = {1'b0, sigp, 1'b1, 1'b0, 3'b000, 1'b1}; // CIO, DACK
wire  [7:0]  ctest3 = {REV[3:0], ctest3_w[3], 1'b0, ctest3_w[1:0]};
wire  [7:0]  dfifo  = {1'b0, dbc[6:0]};

assign irq = !dcntl[1] && ((dstat_st & dien[6:0] & 7'h7D) != 7'd0 || (sist0_st & sien0) != 8'd0 ||
                           (sist1_st & sien1) != 3'd0 || intf);

function automatic logic [7:0] reg_rd(input logic [6:0] a);
	case (a)
		7'h00: return scntl0;   7'h01: return {scntl1[7:5], con, scntl1[3:0]};
		7'h02: return scntl2;   7'h03: return scntl3;
		7'h04: return scid;     7'h05: return sxfer;
		7'h06: return sdid;     7'h07: return gpreg;
		7'h08: return sfbr;     7'h09: return socl;
		7'h0A: return ssid;     7'h0B: return sbcl;
		7'h0C: return dstat;    7'h0D: return sstat0;
		7'h0E: return sstat1;   7'h0F: return 8'h00;              // SSTAT2
		7'h10: return dsa[7:0]; 7'h11: return dsa[15:8]; 7'h12: return dsa[23:16]; 7'h13: return dsa[31:24];
		7'h14: return istat;
		7'h18: return ctest0;   7'h19: return ctest1;
		7'h1A: return ctest2;   7'h1B: return ctest3;
		7'h1C: return temp[7:0]; 7'h1D: return temp[15:8]; 7'h1E: return temp[23:16]; 7'h1F: return temp[31:24];
		7'h20: return dfifo;    7'h21: return ctest4;
		7'h22: return ctest5;   7'h23: return ctest6;
		7'h24: return dbc[7:0]; 7'h25: return dbc[15:8]; 7'h26: return dbc[23:16]; 7'h27: return dcmd;
		7'h28: return dnad[7:0]; 7'h29: return dnad[15:8]; 7'h2A: return dnad[23:16]; 7'h2B: return dnad[31:24];
		7'h2C: return dsp[7:0]; 7'h2D: return dsp[15:8]; 7'h2E: return dsp[23:16]; 7'h2F: return dsp[31:24];
		7'h30: return dsps[7:0]; 7'h31: return dsps[15:8]; 7'h32: return dsps[23:16]; 7'h33: return dsps[31:24];
		7'h34: return scratcha[7:0]; 7'h35: return scratcha[15:8]; 7'h36: return scratcha[23:16]; 7'h37: return scratcha[31:24];
		7'h38: return dmode;    7'h39: return dien;
		7'h3A: return sbr;      7'h3B: return dcntl;
		7'h3C: return adder[7:0]; 7'h3D: return adder[15:8]; 7'h3E: return adder[23:16]; 7'h3F: return adder[31:24];
		7'h40: return sien0;    7'h41: return {5'd0, sien1};
		7'h42: return sist0_st; 7'h43: return {5'd0, sist1_st};
		7'h44: return slpar;
		7'h46: return {4'h0, macntl[3:0]};
		7'h47: return gpcntl;
		7'h48: return stime0;   7'h49: return stime1;
		7'h4A: return respid;
		7'h4C: return 8'h00;    7'h4D: return stest1;            // STEST0, STEST1
		7'h4E: return stest2;   7'h4F: return {stest3_w[7:2], 1'b0, stest3_w[0]};
		7'h50: return sidl;     7'h54: return sodl;     7'h58: return sbdl;
		7'h5C: return scratchb[7:0]; 7'h5D: return scratchb[15:8]; 7'h5E: return scratchb[23:16]; 7'h5F: return scratchb[31:24];
		default: return 8'h00;
	endcase
endfunction

// ---- the SCRIPTS engine ---------------------------------------------------------------------
typedef enum logic [4:0] {
	E_IDLE, E_FETCH, E_DECODE, E_IND,
	E_BM_WAIT, E_BM_BYTE, E_BM_RD, E_BM_GIVE, E_BM_END,
	E_SEL, E_SEL_WAIT, E_STO, E_WDISC, E_WRESEL,
	E_TC_WAIT, E_TC_EVAL,
	E_MM_RD, E_MM_WR, E_FLUSH
} est_e;
est_e est;

logic [2:0]  fcnt;                              // the fetch's word
logic [31:0] ins0;                              // DCMD | DBC as fetched
logic        first_byte;
logic        fl_next;                           // after E_FLUSH: the next instruction (else halt)
logic [31:0] sto_cnt, sto_lim;
// the one-doubleword write buffer and read cache
logic        wb_valid;
logic [31:3] wb_addr;
logic [63:0] wb_data;
logic [7:0]  wb_be;
logic        rc_valid;
logic [31:3] rc_addr;
logic [63:0] rc_data;
// the DMA: dm_* are its registers, held while the request is out
typedef enum logic [0:0] { D_IDLE, D_BUSY } dst_e;
dst_e        dmst;
logic        d_go, d_done, d_err;
logic [31:0] d_addr;
assign dm_addr = d_addr[31:3];

wire [7:0] reg_imm = ins0[15:8];
wire [6:0] reg_adr = ins0[22:16];

// a memory move's source (DMODE.SIOM) or destination (DMODE.DIOM) in PCI I/O space: inside our own
// BAR0 it is the chip's own registers (80-FF alias 00-7F), as AIX's ncr810dd copies DSA and the
// SCRATCH registers to and from memory; any other I/O address is a bus fault
wire       mm_src_io   = dmode[5];
wire       mm_dst_io   = dmode[4];
wire       mm_src_self = mm_src_io && io_on && dnad[31:8] == io_base;
wire       mm_dst_self = mm_dst_io && io_on && temp[31:8] == io_base;
logic [7:0] mm_byte;                            // the byte read from our own registers

function automatic logic [31:0] sext24(input logic [23:0] v);
	return {{8{v[23]}}, v};
endfunction
// byte k (0 = the lowest address) of a doubleword
function automatic logic [7:0] dw_byte(input logic [63:0] d, input logic [2:0] k);
	return d[63 - 8 * k -: 8];
endfunction
// the little-endian word at byte 4h of a doubleword
function automatic logic [31:0] dw_word(input logic [63:0] d, input logic h);
	logic [31:0] w;
	w = h ? d[31:0] : d[63:32];
	return {w[7:0], w[15:8], w[23:16], w[31:24]};
endfunction

always_ff @(posedge clk) begin
	d_done <= 1'b0; d_err <= 1'b0;
	if (reset || srst) begin dmst <= D_IDLE; dm_req <= 1'b0; end
	else case (dmst)
		D_IDLE: if (d_go) begin dm_req <= 1'b1; dmst <= D_BUSY; end
		default: if (dm_ack) begin
			dm_req <= 1'b0; d_done <= 1'b1; d_err <= dm_err; dmst <= D_IDLE;
		end
	endcase
end
wire d_idle = dmst == D_IDLE && !d_go && !d_done;

// the selection timeout: 2^code units (code 0: none)
always_ff @(posedge clk) sto_lim <= stime0[3:0] == 4'd0 ? 32'hFFFF_FFFF : 32'(STO_UNIT) << stime0[3:0];

// a register written by the host or by SCRIPTS (not those with side effects)
task automatic reg_wr(input logic [6:0] a, input logic [7:0] v);
	case (a)
		7'h00: scntl0 <= v;
		7'h02: scntl2 <= v;   7'h03: scntl3 <= v;
		7'h04: scid <= v;     7'h05: sxfer <= v;
		7'h06: sdid <= v;     7'h07: gpreg <= v;
		7'h08: sfbr <= v;     7'h09: socl <= v;
		7'h0A: ssid <= v;
		7'h10: dsa[7:0] <= v; 7'h11: dsa[15:8] <= v; 7'h12: dsa[23:16] <= v; 7'h13: dsa[31:24] <= v;
		7'h18: ctest0 <= v;
		7'h1C: temp[7:0] <= v; 7'h1D: temp[15:8] <= v; 7'h1E: temp[23:16] <= v; 7'h1F: temp[31:24] <= v;
		7'h21: ctest4 <= v;   7'h22: ctest5 <= v;   7'h23: ctest6 <= v;
		7'h24: dbc[7:0] <= v; 7'h25: dbc[15:8] <= v; 7'h26: dbc[23:16] <= v; 7'h27: dcmd <= v;
		7'h28: dnad[7:0] <= v; 7'h29: dnad[15:8] <= v; 7'h2A: dnad[23:16] <= v; 7'h2B: dnad[31:24] <= v;
		7'h30: dsps[7:0] <= v; 7'h31: dsps[15:8] <= v; 7'h32: dsps[23:16] <= v; 7'h33: dsps[31:24] <= v;
		7'h34: scratcha[7:0] <= v; 7'h35: scratcha[15:8] <= v; 7'h36: scratcha[23:16] <= v; 7'h37: scratcha[31:24] <= v;
		7'h38: dmode <= v;    7'h39: dien <= v;     7'h3A: sbr <= v;
		7'h40: sien0 <= v;    7'h41: sien1 <= v[2:0];
		7'h44: slpar <= v;    7'h46: macntl <= v;   7'h47: gpcntl <= v;
		7'h48: stime0 <= v;   7'h49: stime1 <= v;   7'h4A: respid <= v;
		7'h4D: stest1 <= v;   7'h4E: stest2 <= v;
		7'h54: sodl <= v;
		7'h5C: scratchb[7:0] <= v; 7'h5D: scratchb[15:8] <= v; 7'h5E: scratchb[23:16] <= v; 7'h5F: scratchb[31:24] <= v;
		default: ;
	endcase
endtask

always_ff @(posedge clk) begin
	logic [7:0] set_s0, set_ds;
	logic [2:0] set_s1;
	set_s0 = 8'd0; set_ds = 8'd0; set_s1 = 3'd0;
	sb_sel <= 1'b0; sb_ack <= 1'b0;
	d_go <= 1'b0;
	set_ma <= 1'b0;

	if (reset || srst) begin
		scntl0 <= 8'hC0; scntl1 <= 8'd0; scntl2 <= 8'd0; scntl3 <= 8'd0; scid <= 8'd0; sxfer <= 8'd0;
		sdid <= 8'd0; gpreg <= 8'd0; sfbr <= 8'd0; socl <= 8'd0; ssid <= 8'd0;
		dstat_st <= 7'd0; dstat_pend <= 7'd0; sist0_st <= 8'd0; sist0_pend <= 8'd0; sist1_st <= 3'd0; sist1_pend <= 3'd0;
		latched_phase <= 3'd0; dsa <= 32'd0; temp <= 32'd0; dnad <= 32'd0; dsp <= 32'd0; dsps <= 32'd0;
		scratcha <= 32'd0; scratchb <= 32'd0; adder <= 32'd0;
		ctest0 <= 8'd0; ctest3_w <= 8'd0; ctest4 <= 8'd0; ctest5 <= 8'd0; ctest6 <= 8'd0;
		dbc <= 24'd0; dcmd <= 8'd0; dmode <= 8'd0; dien <= 8'd0; sbr <= 8'd0; dcntl <= 8'd0;
		sien0 <= 8'd0; sien1 <= 3'd0;
		slpar <= 8'd0; macntl <= 8'd0; gpcntl <= 8'h0F; stime0 <= 8'd0; stime1 <= 8'd0; respid <= 8'd0;
		stest1 <= 8'd0; stest2 <= 8'd0; stest3_w <= 8'd0; sidl <= 8'd0; sodl <= 8'd0;
		if (reset) srst <= 1'b0;
		sigp <= 1'b0; sem <= 1'b0; intf <= 1'b0; abrt_req <= 1'b0; carry <= 1'b0; con <= 1'b0; target_mode <= 1'b0;
		bsy_q <= 1'b0;
		sb_atn <= 1'b0; sb_ackhold <= 1'b0; sb_rst <= 1'b0;
		est <= E_IDLE; wb_valid <= 1'b0; rc_valid <= 1'b0; fcnt <= 3'd0;
	end
	if (reset) ;
	else if (srst) begin
		// ISTAT.SRST holds the chip in reset until the host clears it
		if (sel && we && off[6:2] == 5'h05 && be[3] && !wdata[30]) srst <= 1'b0;
		if (sel && !we) rdata <= {reg_rd({off[6:2], 2'd0}), reg_rd({off[6:2], 2'd1}), reg_rd({off[6:2], 2'd2}), reg_rd({off[6:2], 2'd3})};
	end else begin
		// ------------------------------------------------ the host's register access
		if (sel) begin
			if (!we) begin
				rdata <= {reg_rd({off[6:2], 2'd0}), reg_rd({off[6:2], 2'd1}), reg_rd({off[6:2], 2'd2}), reg_rd({off[6:2], 2'd3})};
				// reads that clear (and unstack)
				if (off[6:2] == 5'h03 && be[3]) begin dstat_st <= dstat_pend; dstat_pend <= 7'd0; end      // DSTAT (0C)
				if (off[6:2] == 5'h10 && be[1]) begin sist0_st <= sist0_pend; sist0_pend <= 8'd0; end      // SIST0 (42)
				if (off[6:2] == 5'h10 && be[0]) begin sist1_st <= sist1_pend; sist1_pend <= 3'd0; end      // SIST1 (43)
				if (off[6:2] == 5'h06 && be[1]) sigp <= 1'b0;                                              // CTEST2 (1A)
			end else begin
				for (int i = 0; i < 4; i++) if (be[3 - i]) begin
					logic [6:0] a;
					logic [7:0] v;
					a = {off[6:2], i[1:0]}; v = wdata[31 - 8 * i -: 8];   // (80-FF alias 00-7F; no size casts of ints: Quartus 17 reads them signed)
					case (a)
						7'h01: begin
							scntl1 <= v;
							sb_rst <= v[3];
							if (v[3] && !scntl1[3]) set_s0[1] = 1'b1;              // our own RST
							if (v[4]) con <= 1'b1;
						end
						7'h14: begin                                               // ISTAT
							abrt_req <= v[7];
							if (v[6]) srst <= 1'b1;
							sigp <= v[5];
							sem  <= v[4];
							if (v[2]) intf <= 1'b0;
							if (v[7]) begin set_ds[4] = 1'b1; est <= E_IDLE; end
						end
						7'h1B: ctest3_w <= v & 8'hFB;                             // CLF reads 0
						7'h2F: begin dsp[31:24] <= v; if (!dmode[0]) begin est <= E_FETCH; fcnt <= 3'd0; end end
						7'h2C: dsp[7:0] <= v; 7'h2D: dsp[15:8] <= v; 7'h2E: dsp[23:16] <= v;
						7'h3B: begin dcntl <= v & 8'hFB; if (v[2]) begin est <= E_FETCH; fcnt <= 3'd0; end end   // STD
						7'h4F: stest3_w <= v & 8'hFD;                             // CSF reads 0
						default: reg_wr(a, v);
					endcase
				end
			end
		end
		if (sb_req) latched_phase <= sb_phase;
		bsy_q <= sb_bsy;
		if (bsy_q && !sb_bsy && est == E_IDLE) con <= 1'b0;

		// ------------------------------------------------ the engine
		case (est)
			E_IDLE: fcnt <= 3'd0;

			// fetch: 2 words (3 for a memory move)
			E_FETCH: begin
				if (d_idle && !wb_valid) begin
					d_go <= 1'b1; dm_we <= 1'b0; d_addr <= dsp; dm_be <= 8'hFF;
				end else if (wb_valid && d_idle) begin
					d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
					wb_valid <= 1'b0;
					est <= E_FLUSH; fl_next <= 1'b1;                    // write back, then fetch again
				end
				if (d_done && !dm_we) begin
					logic [31:0] w;
					w = dw_word(dm_rdata, dsp[2]);
					if (d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
					else begin
						case (fcnt)
							3'd0: begin ins0 <= w; dcmd <= w[31:24]; dbc <= w[23:0]; end
							3'd1: begin dsps <= w; dnad <= w; end
							default: temp <= w;
						endcase
						dsp <= dsp + 32'd4;
						fcnt <= fcnt + 3'd1;
						if ((fcnt == 3'd1 && ins0[31:30] != 2'b11) || fcnt == 3'd2) est <= E_DECODE;
					end
				end
			end

			E_DECODE: begin
				first_byte <= 1'b1;
				fcnt <= 3'd0;
				case (ins0[31:30])
					2'b00: begin                                         // block move
						if (target_mode || !ins0[27]) begin set_ds[0] = 1'b1; est <= E_IDLE; end    // target mode / CHMOV
						else if (ins0[28] || ins0[29]) begin
							// table indirect (DSA + offset) or indirect: the count and address
							d_go <= 1'b1; dm_we <= 1'b0; dm_be <= 8'hFF;
							d_addr <= ins0[28] ? dsa + sext24(dsps[23:0]) : dsps;
							if (ins0[28]) adder <= dsa + sext24(dsps[23:0]);
							est <= E_IND;
						end else if (dbc == 24'd0) begin set_ds[0] = 1'b1; est <= E_IDLE; end
						else est <= E_BM_WAIT;
					end
					2'b01: begin
						if (ins0[29:27] >= 3'b101) begin
							// register read / write: 101 SFBR op data to the register, 110 the
							// register op data to SFBR, 111 read-modify-write
							logic [7:0] src, res;
							logic [8:0] sum;
							logic       c_out;
							src = ins0[29:27] == 3'b101 ? sfbr : reg_rd(reg_adr);
							sum = {1'b0, src} + {1'b0, reg_imm} + {8'd0, ins0[26:24] == 3'b111 && carry};
							c_out = carry;
							case (ins0[26:24])
								3'b000: res = reg_imm;
								3'b001: begin res = {src[6:0], carry}; c_out = src[7]; end      // SHL
								3'b010: res = src | reg_imm;
								3'b011: res = src ^ reg_imm;
								3'b100: res = src & reg_imm;
								3'b101: begin res = {carry, src[7:1]}; c_out = src[0]; end      // SHR
								default: begin res = sum[7:0]; c_out = sum[8]; end              // ADD, ADC
							endcase
							carry <= c_out;
							if (ins0[29:27] == 3'b110) sfbr <= res;
							else case (reg_adr)
								7'h01: begin scntl1 <= res; sb_rst <= res[3]; if (res[3] && !scntl1[3]) set_s0[1] = 1'b1; end   // our own RST, as from the host
								7'h14: begin sigp <= res[5]; sem <= res[4]; end
								7'h1B: ctest3_w <= res & 8'hFB;
								7'h2C: dsp[7:0] <= res; 7'h2D: dsp[15:8] <= res; 7'h2E: dsp[23:16] <= res; 7'h2F: dsp[31:24] <= res;
								7'h3B: dcntl <= res & 8'hFB;
								7'h4F: stest3_w <= res & 8'hFD;
								default: reg_wr(reg_adr, res);
							endcase
							est <= E_FETCH;
						end else case (ins0[29:27])
							3'b000: begin                                   // SELECT
								if (ins0[25]) begin
									// table indirect: SCNTL3, the ID and SXFER from DSA + offset
									d_go <= 1'b1; dm_we <= 1'b0; dm_be <= 8'hFF;
									d_addr <= dsa + sext24(ins0[23:0]); adder <= dsa + sext24(ins0[23:0]);
									est <= E_IND;
								end else begin
									sdid <= {4'd0, ins0[19:16]}; est <= E_SEL;
								end
							end
							3'b001: est <= E_WDISC;                         // WAIT DISCONNECT
							3'b010: est <= E_WRESEL;                        // WAIT RESELECT
							3'b011, 3'b100: begin                           // SET / CLEAR
								logic s;
								s = ins0[29:27] == 3'b011;
								if (ins0[3]) sb_atn <= s;
								if (ins0[6]) sb_ackhold <= s;
								if (ins0[9]) target_mode <= s;
								if (ins0[10]) carry <= s;
								est <= E_FETCH;
							end
							default: begin set_ds[0] = 1'b1; est <= E_IDLE; end
						endcase
					end
					2'b10: begin                                         // transfer control
						if (ins0[29:27] > 3'b011) begin set_ds[0] = 1'b1; est <= E_IDLE; end
						else if (ins0[16] && con) est <= E_TC_WAIT;
						else est <= E_TC_EVAL;
					end
					default: begin                                       // memory move (LOAD/STORE: illegal here)
						if (ins0[29:25] != 5'd0 || dsps[1:0] != temp[1:0]) begin set_ds[0] = 1'b1; est <= E_IDLE; end
						else if (dbc == 24'd0) est <= E_FETCH;
						else begin dnad <= dsps; est <= E_MM_RD; end
					end
				endcase
			end

			// the indirect fetches: block move {count, address}, select {SCNTL3, ID, SXFER}
			E_IND: if (d_done) begin
				logic [31:0] w;
				w = dw_word(dm_rdata, d_addr[2]);
				if (d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
				else if (ins0[31:30] == 2'b01) begin
					scntl3 <= w[31:24]; sdid <= {4'd0, w[19:16]}; sxfer <= w[15:8]; est <= E_SEL;
				end else if (fcnt == 3'd0 && ins0[28]) begin
					dbc <= w[23:0]; fcnt <= 3'd1;
					d_go <= 1'b1; d_addr <= d_addr + 32'd4;
				end else begin
					dnad <= w;
					fcnt <= 3'd0;
					if (dbc == 24'd0 && !(ins0[28] && fcnt == 3'd0)) begin set_ds[0] = 1'b1; est <= E_IDLE; end
					else est <= E_BM_WAIT;
				end
			end

			// ---- block move: wait for REQ, compare the phase, move the bytes
			E_BM_WAIT: begin
				if (!sb_bsy) begin set_s0[2] = 1'b1; con <= 1'b0; sb_ackhold <= 1'b0; est <= E_FLUSH; fl_next <= 1'b0; end   // UDC
				else if (sb_req) begin
					if (sb_phase != ins0[26:24]) begin set_s0[7] = 1'b1; est <= E_FLUSH; fl_next <= 1'b0; end      // phase mismatch
					else begin
						sb_ackhold <= 1'b0;
						if (sb_phase[0]) est <= E_BM_BYTE;              // IN
						else est <= E_BM_RD;                            // OUT: the byte first
					end
				end
			end
			// IN: the byte into the write buffer
			E_BM_BYTE: begin
				if (wb_valid && wb_addr != dnad[31:3]) begin
					if (d_idle) begin
						d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
						wb_valid <= 1'b0;
					end
				end else if (d_idle) begin
					logic [7:0] b;
					b = sb_tdata;
					if (!wb_valid) begin wb_valid <= 1'b1; wb_addr <= dnad[31:3]; wb_be <= 8'h80 >> dnad[2:0]; end
					else wb_be[7 - dnad[2:0]] <= 1'b1;
					wb_data[63 - 8 * dnad[2:0] -: 8] <= b;
					rc_valid <= 1'b0;
					sidl <= b;
					if (first_byte) sfbr <= b;
					first_byte <= 1'b0;
					dnad <= dnad + 32'd1; dbc <= dbc - 24'd1;
					sb_ack <= 1'b1;
					// the last byte of a MESSAGE IN move keeps ACK asserted
					if (dbc == 24'd1 && sb_phase == 3'b111) sb_ackhold <= 1'b1;
					est <= E_BM_END;
				end
				if (d_done && d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
			end
			// OUT: the byte (from the read cache), then give it
			E_BM_RD: begin
				if (rc_valid && rc_addr == dnad[31:3]) est <= E_BM_GIVE;
				else if (wb_valid && d_idle) begin
					d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
					wb_valid <= 1'b0;
				end else if (d_idle && !wb_valid) begin
					d_go <= 1'b1; dm_we <= 1'b0; d_addr <= dnad; dm_be <= 8'hFF;
				end
				if (d_done) begin
					if (d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
					else if (!dm_we) begin rc_valid <= 1'b1; rc_addr <= dnad[31:3]; rc_data <= dm_rdata; est <= E_BM_GIVE; end
				end
			end
			E_BM_GIVE: begin
				logic [7:0] b;
				b = dw_byte(rc_data, dnad[2:0]);
				sb_idata <= b; sodl <= b;
				if (first_byte) sfbr <= b;
				first_byte <= 1'b0;
				// MESSAGE OUT: ATN drops before the last byte
				if (dbc == 24'd1 && sb_phase == 3'b110) sb_atn <= 1'b0;
				dnad <= dnad + 32'd1; dbc <= dbc - 24'd1;
				sb_ack <= 1'b1;
				est <= E_BM_END;
			end
			// after each byte the target drops REQ: then the next byte, or done
			E_BM_END: if (!sb_ack && !sb_req) begin
				if (dbc == 24'd0) begin est <= E_FLUSH; fl_next <= 1'b1; end
				else est <= E_BM_WAIT;
			end

			// ---- SELECT: the target answers, or the time runs out
			E_SEL: begin
				sb_sel <= 1'b1;
				sb_sel_id <= sdid[2:0];
				sb_sel_atn <= ins0[24];
				sto_cnt <= 32'd0;
				est <= E_SEL_WAIT;
			end
			E_SEL_WAIT: begin
				if (sb_sel_done) begin
					con <= 1'b1;
					scntl2[7] <= 1'b1;                              // SDU: a disconnect now is unexpected
					if (ins0[24]) sb_atn <= 1'b1;
					est <= E_FETCH;
				end else if (sb_sel_fail) est <= E_STO;
			end
			E_STO: begin
				sto_cnt <= sto_cnt + 32'd1;
				if (sto_cnt == sto_lim) begin set_s1[2] = 1'b1; est <= E_IDLE; end
			end
			E_WDISC: if (!sb_bsy) begin con <= 1'b0; sb_ackhold <= 1'b0; est <= E_FETCH; end
			E_WRESEL: if (sigp) begin
				// SIGP: the alternate address (nothing reselects in phase 1)
				dsp <= ins0[26] ? dsp + sext24(dsps[23:0]) : dsps;
				est <= E_FETCH;
			end

			// ---- transfer control
			E_TC_WAIT: begin
				if (!sb_bsy) begin set_s0[2] = 1'b1; con <= 1'b0; est <= E_IDLE; end
				else if (sb_req && !sb_ackhold) est <= E_TC_EVAL;
			end
			E_TC_EVAL: begin
				logic pm, dm, cnd, take;
				logic [2:0] ph;
				ph = sb_req ? sb_phase : latched_phase;
				pm = ph == ins0[26:24];
				dm = ((sfbr ^ ins0[7:0]) & ~ins0[15:8]) == 8'd0;
				if (ins0[21]) cnd = carry;
				else if (ins0[17] && ins0[18]) cnd = ins0[19] ? (pm && dm) : (pm || dm);
				else if (ins0[17]) cnd = pm;
				else if (ins0[18]) cnd = dm;
				else cnd = 1'b1;
				take = ins0[19] ? cnd : !cnd;
				if (!ins0[17] && !ins0[18] && !ins0[21]) take = ins0[19];     // no test: bit 19 (the assemblers' "always" sets it)
				if (take) case (ins0[29:27])
					3'b000: begin dsp <= ins0[23] ? dsp + sext24(dsps[23:0]) : dsps; est <= E_FETCH; end
					3'b001: begin temp <= dsp; dsp <= ins0[23] ? dsp + sext24(dsps[23:0]) : dsps; est <= E_FETCH; end
					3'b010: begin dsp <= temp; est <= E_FETCH; end
					default:
						if (ins0[20]) begin intf <= 1'b1; est <= E_FETCH; end                 // INTFLY
						else begin est <= E_FLUSH; fl_next <= 1'b0; set_ds[2] = 1'b1; end      // INT: SIR
				endcase
				else est <= E_FETCH;
			end

			// ---- memory move: a byte at a time through the read cache and the write buffer
			E_MM_RD: begin
				if (mm_src_io) begin
					// I/O space: our own registers, or a bus fault
					if (mm_src_self) begin mm_byte <= reg_rd(dnad[6:0]); est <= E_MM_WR; end
					else begin set_ds[5] = 1'b1; est <= E_FLUSH; fl_next <= 1'b0; end
				end
				else if (rc_valid && rc_addr == dnad[31:3]) est <= E_MM_WR;
				else if (wb_valid && d_idle) begin
					d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
					wb_valid <= 1'b0;
				end else if (d_idle && !wb_valid) begin
					d_go <= 1'b1; dm_we <= 1'b0; d_addr <= dnad; dm_be <= 8'hFF;
				end
				if (d_done) begin
					if (d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
					else if (!dm_we) begin rc_valid <= 1'b1; rc_addr <= dnad[31:3]; rc_data <= dm_rdata; est <= E_MM_WR; end
				end
			end
			E_MM_WR: begin
				logic [7:0] b;
				b = mm_src_io ? mm_byte : dw_byte(rc_data, dnad[2:0]);
				if (mm_dst_io) begin
					// I/O space: our own registers (as a register write from SCRIPTS), or a bus fault
					if (mm_dst_self) begin
						case (temp[6:0])
							7'h01: begin scntl1 <= b; sb_rst <= b[3]; if (b[3] && !scntl1[3]) set_s0[1] = 1'b1; end
							7'h14: begin sigp <= b[5]; sem <= b[4]; end
							7'h1B: ctest3_w <= b & 8'hFB;
							7'h2C: dsp[7:0] <= b; 7'h2D: dsp[15:8] <= b; 7'h2E: dsp[23:16] <= b; 7'h2F: dsp[31:24] <= b;
							7'h3B: dcntl <= b & 8'hFB;
							7'h4F: stest3_w <= b & 8'hFD;
							default: reg_wr(temp[6:0], b);
						endcase
						dnad <= dnad + 32'd1; temp <= temp + 32'd1; dbc <= dbc - 24'd1;
						est <= (dbc == 24'd1) ? E_FLUSH : E_MM_RD; fl_next <= 1'b1;
					end
					else begin set_ds[5] = 1'b1; est <= E_FLUSH; fl_next <= 1'b0; end
				end
				else if (wb_valid && wb_addr != temp[31:3]) begin
					if (d_idle) begin
						d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
						wb_valid <= 1'b0;
					end
				end else if (d_idle) begin
					if (!wb_valid) begin wb_valid <= 1'b1; wb_addr <= temp[31:3]; wb_be <= 8'h80 >> temp[2:0]; end
					else wb_be[7 - temp[2:0]] <= 1'b1;
					wb_data[63 - 8 * temp[2:0] -: 8] <= b;
					if (rc_addr == temp[31:3]) rc_valid <= 1'b0;     // the read cache is stale
					dnad <= dnad + 32'd1; temp <= temp + 32'd1; dbc <= dbc - 24'd1;
					est <= (dbc == 24'd1) ? E_FLUSH : E_MM_RD; fl_next <= 1'b1;
				end
				if (d_done && d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; end
			end

			// write the buffer back; then the next instruction (fl_next) or the halt
			// (its interrupt already raised)
			E_FLUSH: begin
				if (wb_valid && d_idle) begin
					d_go <= 1'b1; dm_we <= 1'b1; d_addr <= {wb_addr, 3'd0}; dm_be <= wb_be; dm_wdata <= wb_data;
					wb_valid <= 1'b0;
				end else if (!wb_valid && d_idle) begin
					rc_valid <= 1'b0;
					est <= fl_next ? E_FETCH : E_IDLE;
				end
				if (d_done && d_err) begin set_ds[5] = 1'b1; set_ma <= 1'b1; est <= E_IDLE; wb_valid <= 1'b0; end
			end
			default: est <= E_IDLE;
		endcase

		// ---------------------------------------- the interrupt status, stacked
		if (set_s0 != 8'd0 || set_s1 != 3'd0 || set_ds != 8'd0) begin
			if (sip || dip) begin
				sist0_pend <= sist0_pend | set_s0; sist1_pend <= sist1_pend | set_s1; dstat_pend <= dstat_pend | set_ds[6:0];
			end else begin
				sist0_st <= sist0_st | set_s0; sist1_st <= sist1_st | set_s1; dstat_st <= dstat_st | set_ds[6:0];
			end
		end
`ifdef VERILATOR
		// the bench's trace of the SCRIPTS processor (never in the bitstream; no state of its own,
		// so the bench's snapshots stay valid): each instruction as decoded, the interrupt status as set
		if (est == E_DECODE)
			$display("ncr %08X: %08X %08X", dsp - (ins0[31:30] == 2'b11 ? 32'd12 : 32'd8), ins0, dsps);
		if (set_s0 != 8'd0 || set_s1 != 3'd0 || set_ds != 8'd0)
			$display("ncr set dstat %02X sist0 %02X sist1 %01X  (irq %0d istat %02X dien %02X dcntl %02X)",
			         set_ds, set_s0, set_s1, irq, istat, dien, dcntl);
`endif
	end
end

endmodule
