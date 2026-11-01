//============================================================================
//  IBMRS6K7248 - an ATAPI CD-ROM on the secondary IDE channel (Fire Coral's,
//  170-177 and 376: the machine maps them to this module's 1F0-1F7 and 3F6
//  names), for the Power Series 830/850 personality, where a real 850 has its
//  CD-ROM (OS/2's set_boot: "Defaulting to IDE CDROM at HD2")
//
//  The 850's CD-ROM is an IDE drive (OS/2's install boot loads dd_ide only).
//  This is the channel's master device, an ATAPI packet device whose packets go to the
//  same CD as the 53C810's: it is a second initiator on IBMRS6K7248_scsitgt's
//  bus (the machine gives it the bus while the 53C810 has nothing selected),
//  selecting the CD-ROM's ID and passing the 12-byte packet as the CDB, the
//  data phases through a 2 KB buffer, the status as ATAPI's.
//
//  Registers: the task file byte wide (the byte of the access's first lane,
//  wd8; the answer on every lane), the data port 16 or 32 bits, aligned
//  (lane 0 the lowest address):
//    1F0 data      1F1 error / features   1F2 interrupt reason (bit 0 C/D,
//    bit 1 I/O)    1F3 sector             1F4/1F5 byte count (low/high)
//    1F6 drive     1F7 status / command   3F6 alternate status / device
//    control (bit 1 nIEN, bit 2 SRST)
//  Device 1 (the slave) is absent: its registers read 0.
//  Commands: PACKET (A0), IDENTIFY PACKET DEVICE (A1), DEVICE RESET (08),
//  EXECUTE DEVICE DIAGNOSTIC (90), IDENTIFY DEVICE (EC: aborted, the packet
//  signature in 1F4/1F5, as ATAPI asks), SET FEATURES and the power commands
//  (done, nothing changes); anything else aborted.
//  A packet's data comes in blocks of at most the host's byte count (1F4/
//  1F5, even, 4096 at most); a CHECK CONDITION ends it with ERR and error
//  54 (sense key 5, ABRT), the host's REQUEST SENSE gives the real sense.
//============================================================================

module IBMRS6K7248_atapi #(
	parameter int unsigned CLK_HZ = 70_000_000   // clk's rate: a command's answer waits LATENCY_US after it
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        en,                    // the 850's personality: else no device

	input  logic        sel,                   // an access to 1F0-1F7 (cs1 = 0) or 3F6 (cs1 = 1)
	input  logic        cs1,
	input  logic        we,
	input  logic [2:0]  reg_a,                 // the register (port bits 2:0) of the access's first lane
	input  logic [3:0]  be,                    // the data port's lanes (bit 3 = lane 0)
	input  logic [7:0]  wd8,                   // the byte of the first lane
	input  logic [31:0] wdata,                 // the data port's lanes
	output logic [31:0] rdata,                 // the cycle after sel
	output logic        irq,

	// the SCSI bus to IBMRS6K7248_scsitgt, as an initiator
	output logic        want,                  // a packet runs: the machine gives the bus when it is free
	input  logic        grant,
	output logic        i_sel,
	output logic [2:0]  i_sel_id,
	input  logic        sel_done,
	input  logic        sel_fail,
	input  logic        bsy,
	input  logic        req,
	input  logic [2:0]  phase,
	input  logic [7:0]  tdata,
	output logic        ack,
	output logic [7:0]  idata
);

localparam logic [2:0] CD_ID = 3'd3;
localparam logic [2:0] P_DOUT = 3'b000, P_DIN = 3'b001, P_CMD = 3'b010, P_STAT = 3'b011;

// the task file
logic [7:0] err, ireason, sect, bcl, bch, drv;
logic       bsy_s, drdy, drq, errb, nien;
// an interrupt pending (a DRQ block ready, a command done): INTRQ while nIEN is clear; it stays pending through
// nIEN and is cleared by a read of the status register or a new command, as the ATA interrupt is (OS/2's
// dd_ide keeps nIEN set while it takes a block's data and expects the completion interrupt once it clears it)
logic       ipend;
assign      irq = ipend & ~nien;
wire        dev1 = drv[4];
wire  [7:0] status = {bsy_s, drdy, 1'b0, 1'b1, drq, 2'b00, errb};   // DSC (bit 4) always

typedef enum logic [3:0] {A_IDLE, A_ID, A_PKT, A_WANT, A_SEL, A_RUN, A_HOST, A_FILL, A_END} ast_t;
ast_t a;
logic        pkt;                              // a packet is on the bus (from its selection to its status)
logic        out_dir;                          // the host's block goes to the target (DATA OUT)
logic [15:0] limit;                            // the host's byte count limit for a packet
wire  [12:0] lim_e = (limit == 16'd0 || limit > 16'd4096) ? 13'd4096 : {limit[12:1], 1'b0};   // even, 4 KB at most (the buffer)
logic [12:0] hptr, hlen;                       // the host's byte position in the block, the block's length
logic [12:0] tptr;                             // the target's byte position
logic [31:0] acc;                              // bytes gathered into a word (the target's, the host's)
logic [3:0]  ci;                               // the CDB byte the target takes next
logic [7:0]  stat_b;
logic [7:0]  idw;                              // the identify word being written
// a command's first answer (its DRQ or its status, with the interrupt) comes no sooner than 2 ms after the
// command or the packet's last byte: a CD-ROM takes longer than that, and OS/2's dd_ide, which sends the packet
// and then waits for its interrupt thread's signal, lost the signal when a cached block answered at once
localparam int unsigned LATENCY_US = 2000;
logic [31:0] lat_cnt;
wire         lat_ok = lat_cnt == 32'd0;

// the data buffer: 4 KB (a host's byte count of 4096 in one DRQ block, as OS/2's dd_ide asks), a word a line
// (byte k of a line at bits 8k+7:8k)
logic [31:0] buf_mem [1024];
logic [9:0]  bwa, bra, bra_q;                  // bra_q: the line brq holds
logic [31:0] bwd, brq;
logic        bwe;
wire         host_rd = a == A_HOST && !out_dir;
wire  [9:0]  rda = host_rd ? hptr[11:2] : bra;
always_ff @(posedge clk) begin
	if (bwe) buf_mem[bwa] <= bwd;
	brq   <= buf_mem[rda];
	bra_q <= rda;
end

// the identify data, a word at a time (ATA strings: two characters a word, the first high)
function automatic logic [15:0] ident(input logic [7:0] w);
	case (w)
		8'd0:  ident = 16'h85C0;               // ATAPI, CD-ROM, removable, 12-byte packets
		8'd10: ident = 16'h3030; 8'd11: ident = 16'h3030; 8'd12: ident = 16'h3031;   // serial "00001"
		8'd23: ident = 16'h312E; 8'd24: ident = 16'h3030;                         // firmware "1.00"
		8'd27: ident = 16'h4942; 8'd28: ident = 16'h4D20; 8'd29: ident = 16'h4344;  // "IBM CD"
		8'd30: ident = 16'h524D; 8'd31: ident = 16'h3030; 8'd32: ident = 16'h3230; 8'd33: ident = 16'h3320;  // "RM00203 "
		8'd49: ident = 16'h0200;               // LBA
		8'd53: ident = 16'h0002;               // word 64 valid
		8'd64: ident = 16'h0003;               // PIO 3, 4
		8'd80: ident = 16'h001E;               // ATA/ATAPI-1..4
		default: ident = (w >= 8'd13 && w <= 8'd19) || w == 8'd25 || w == 8'd26 || (w >= 8'd34 && w <= 8'd46) ? 16'h2020 : 16'h0000;
	endcase
endfunction
wire [15:0] idv = ident(idw);

// the data port's lanes: aligned, lane k the byte at dbase + k (16-bit: hptr[1] * 2, 32-bit: 0)
wire [1:0]  dbase = {hptr[1] & ~be[1], 1'b0};
wire [2:0]  nb    = be[1] ? 3'd4 : be[2] ? 3'd2 : 3'd1;
wire [12:0] hnext = hptr + 13'(nb);
wire        dsel  = sel && en && !dev1 && !cs1 && reg_a == 3'd0 && drq;

always_ff @(posedge clk) begin
	bwe   <= 1'b0;
	ack   <= 1'b0;
	i_sel <= 1'b0;

	if (lat_cnt != 32'd0) lat_cnt <= lat_cnt - 32'd1;

	// ---- the data port
	if (dsel) begin
		hptr <= hnext;
		if (we) begin
			for (int k = 0; k < 4; k++)
				if (k < nb) acc[8 * (dbase + 2'(k)) +: 8] <= wdata[31 - 8 * k -: 8];
			if (hnext[1:0] == 2'd0 || hnext >= hlen) begin
				bwe <= 1'b1; bwa <= hptr[11:2];
				bwd <= acc;
				for (int k = 0; k < 4; k++)
					if (k < nb) bwd[8 * (dbase + 2'(k)) +: 8] <= wdata[31 - 8 * k -: 8];
			end
		end
		if (hnext >= hlen) begin
			drq <= 1'b0;
			if (a == A_PKT) begin a <= A_WANT; bsy_s <= 1'b1; pkt <= 1'b1; lat_cnt <= 32'(CLK_HZ / 1_000_000) * LATENCY_US; end
			else if (a == A_HOST) a <= !pkt ? A_IDLE : out_dir ? A_RUN : A_FILL;
		end
	end

	// ---- the task file
	if (sel && en && we && cs1) begin
		nien <= wd8[1];
		if (wd8[2]) begin                                     // SRST: the packet signature
			a <= A_IDLE; pkt <= 1'b0; drq <= 1'b0; bsy_s <= 1'b0; drdy <= 1'b0; errb <= 1'b0; err <= 8'h01;
			sect <= 8'h01; ireason <= 8'h01; bcl <= 8'h14; bch <= 8'hEB; ipend <= 1'b0; out_dir <= 1'b0; tptr <= 13'd0;
		end
	end
	if (sel && en && we && !cs1) case (reg_a)
		3'd2: ireason <= wd8;
		3'd3: sect <= wd8;
		3'd4: bcl <= wd8;
		3'd5: bch <= wd8;
		3'd6: drv <= wd8;
		3'd7: if (!dev1) begin                                // a command
			ipend <= 1'b0; errb <= 1'b0; err <= 8'h00;
			lat_cnt <= 32'(CLK_HZ / 1_000_000) * LATENCY_US;
			case (wd8)
				8'hA0: begin                                  // PACKET: the 12 bytes first
					a <= A_PKT; drq <= 1'b1; hptr <= 13'd0; hlen <= 13'd12;
					ireason <= 8'h01; limit <= {bch, bcl};
				end
				8'hA1: begin                                  // IDENTIFY PACKET DEVICE: into the buffer, then the host
					a <= A_ID; bsy_s <= 1'b1; idw <= 8'd0; drdy <= 1'b1;
				end
				8'h08, 8'h90: begin                           // DEVICE RESET, EXECUTE DEVICE DIAGNOSTIC
					sect <= 8'h01; ireason <= 8'h01; bcl <= 8'h14; bch <= 8'hEB;
					err <= 8'h01; drdy <= 1'b0; drq <= 1'b0; a <= A_IDLE; pkt <= 1'b0;
					ipend <= wd8 == 8'h90;
				end
				8'hEF, 8'hE0, 8'hE1, 8'hE3, 8'hE5, 8'hE7, 8'h91: begin   // SET FEATURES, power, flush: done
					drdy <= 1'b1; ipend <= 1'b1;
				end
				default: begin                                // IDENTIFY DEVICE and the rest: aborted, the device ready
					// (DRDY with the abort, as a drive that has come out of reset: dd_ide probes each unit with a NOP
					// and gives the channel up on 11 instead of 51 - the installed system's boot never used the CD
					// before, so the loader had not set it, 2026-10-31)
					errb <= 1'b1; err <= 8'h04; ipend <= 1'b1; drdy <= 1'b1;
					if (wd8 == 8'hEC) begin sect <= 8'h01; ireason <= 8'h01; bcl <= 8'h14; bch <= 8'hEB; end
				end
			endcase
		end
		default: ;
	endcase
	// reading the status acknowledges the interrupt
	if (sel && en && !we && !cs1 && reg_a == 3'd7) ipend <= 1'b0;

	// ---- the packet, and the identify data
	case (a)
		A_ID: begin                                           // two words a line, the even word low
			if (!idw[0]) acc[15:0] <= idv;
			else begin bwe <= 1'b1; bwa <= {2'b00, idw[7:1]}; bwd <= {idv, acc[15:0]}; end
			if (idw != 8'd255 || lat_ok) idw <= idw + 8'd1;
			if (idw == 8'd255 && lat_ok) begin
				bsy_s <= 1'b0; drq <= 1'b1; hptr <= 13'd0; hlen <= 13'd512; ireason <= 8'h02; ipend <= 1'b1;
				a <= A_HOST; out_dir <= 1'b0;
			end
		end
		A_WANT: if (grant && !bsy) begin i_sel <= 1'b1; a <= A_SEL; ci <= 4'd0; tptr <= 13'd0; bra <= 10'd0; end
		A_SEL: begin
			if (sel_fail) begin a <= A_END; stat_b <= 8'h02; end   // no CD target: aborted
			else if (sel_done) a <= A_RUN;
		end
		A_RUN: begin
			if (!bsy && !req) a <= A_END;                     // the target let go
			else if (req && !ack) begin
				case (phase)
					P_CMD: begin                              // the CDB: the packet's first bytes
						bra <= 10'(ci >> 2);
						idata <= brq[8 * ci[1:0] +: 8];
						if (bra == 10'(ci >> 2) && bra_q == 10'(ci >> 2)) begin ack <= 1'b1; ci <= ci + 4'd1; end
					end
					P_DIN: begin
						acc[8 * tptr[1:0] +: 8] <= tdata;
						bwe <= 1'b1; bwa <= tptr[11:2];
						bwd <= acc; bwd[8 * tptr[1:0] +: 8] <= tdata;
						tptr <= tptr + 13'd1;
						ack  <= 1'b1;
						if (tptr + 13'd1 >= lim_e) begin a <= A_HOST; out_dir <= 1'b0; end   // a block is full
					end
					P_DOUT: begin
						if (tptr == 13'd0 && !out_dir && lat_ok) begin  // the host gives a block first
							out_dir <= 1'b1; a <= A_HOST;
							drq <= 1'b1; hptr <= 13'd0; hlen <= lim_e;
							bcl <= lim_e[7:0]; bch <= {3'd0, lim_e[12:8]};
							ireason <= 8'h00; bsy_s <= 1'b0; ipend <= 1'b1;
						end
						else begin
							bra <= tptr[11:2];
							idata <= brq[8 * tptr[1:0] +: 8];
							if (bra == tptr[11:2] && bra_q == tptr[11:2]) begin
								ack <= 1'b1; tptr <= tptr + 13'd1;
								if (tptr + 13'd1 >= hlen) begin tptr <= 13'd0; out_dir <= 1'b0; end
							end
						end
					end
					P_STAT: begin stat_b <= tdata; ack <= 1'b1; end
					default: ack <= 1'b1;                     // MESSAGE IN (COMMAND COMPLETE)
				endcase
				// DATA IN ended short of a block: the rest goes to the host before the status
				if (phase != P_DIN && tptr != 13'd0 && !out_dir) a <= A_HOST;
			end
		end
		A_HOST: begin
			// hand a gathered DATA IN block to the host (once); it drains it through the data port
			if (pkt && !drq && !out_dir && tptr != 13'd0 && lat_ok) begin
				if (tptr[1:0] != 2'd0) begin bwe <= 1'b1; bwa <= tptr[11:2]; bwd <= acc; end
				drq <= 1'b1; hptr <= 13'd0; hlen <= tptr;
				bcl <= tptr[7:0]; bch <= {3'd0, tptr[12:8]};
				ireason <= 8'h02; bsy_s <= 1'b0; ipend <= 1'b1;
				tptr <= 13'd0;
			end
		end
		A_FILL: begin bsy_s <= 1'b1; a <= A_RUN; end
		A_END: if (lat_ok) begin
			bsy_s <= 1'b0; drdy <= 1'b1; drq <= 1'b0; pkt <= 1'b0;
			ireason <= 8'h03;                                 // C/D and I/O: the status
			errb <= stat_b != 8'h00; err <= stat_b != 8'h00 ? 8'h54 : 8'h00;
			ipend <= 1'b1; a <= A_IDLE;
		end
		default: ;
	endcase

	if (reset || !en) begin
		a <= A_IDLE; pkt <= 1'b0; drq <= 1'b0; bsy_s <= 1'b0; drdy <= 1'b0; errb <= 1'b0; err <= 8'h01;
		sect <= 8'h01; ireason <= 8'h01; bcl <= 8'h14; bch <= 8'hEB; ipend <= 1'b0;
		out_dir <= 1'b0; tptr <= 13'd0; drv <= 8'h00; nien <= 1'b0; lat_cnt <= 32'd0;
	end
end

assign want     = pkt;
assign i_sel_id = CD_ID;

// the answer: the task file's byte on every lane; the data port's bytes, lane k at dbase + k
always_ff @(posedge clk) if (sel) begin
	logic [7:0] v;
	if (!en || dev1) v = 8'h00;
	else if (cs1) v = status;
	else case (reg_a)
		3'd1: v = err;
		3'd2: v = ireason;
		3'd3: v = sect;
		3'd4: v = bcl;
		3'd5: v = bch;
		3'd6: v = drv | 8'hA0;
		default: v = status;
	endcase
	if (en && !dev1 && !cs1 && reg_a == 3'd0)
		rdata <= {brq[8 * dbase +: 8], brq[8 * (dbase + 2'd1) +: 8], brq[23:16], brq[31:24]};
	else
		rdata <= {4{v}};
end

endmodule
