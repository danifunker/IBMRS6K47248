//============================================================================
//  IBMRS6K7248 - an IDE hard disk on the primary IDE channel (1F0-1F7 and
//  3F6, IRQ 14), the slave of IBMRS6K7248_atapi's CD-ROM, for the Power
//  Series 830/850 personality
//
//  OS/2 PPC's installer wants a hard disk it can partition and format, and
//  the 850's disks are IDE (OS/2's install boot loads dd_ide only). This is
//  device 1: an ATA disk whose sectors are the OSD's disk 0 image, reached
//  as a third initiator on IBMRS6K7248_scsitgt's bus (the machine gives it
//  the bus while the 53C810 and the CD-ROM have nothing on it), with one
//  READ(10)/WRITE(10) of the block's sectors per DRQ block.
//
//  Registers (the byte of the access's first lane, wd8; the answer on every
//  lane; the data port 16 or 32 bits, aligned, lane 0 the lowest address):
//    1F0 data  1F1 error / features  1F2 sector count  1F3 sector number
//    (LBA 7:0)  1F4 cylinder low (LBA 15:8)  1F5 cylinder high (LBA 23:16)
//    1F6 drive/head (bit 4 the device, bit 6 LBA, bits 3:0 the head / LBA
//    27:24)  1F7 status / command  3F6 alternate status / device control
//  Both devices see the drive register; this one answers while bit 4 is set
//  (the machine picks the answer), and is silent when no disk image is
//  mounted (its registers read 00, as an empty position).
//  Geometry: 16 heads, 63 sectors a track, the cylinders from the image's
//  size (16383 at most in the identify data, as ATA-2 asks); LBA too.
//  Commands: IDENTIFY DEVICE (EC), READ/WRITE SECTORS (20/21, 30/31), READ/
//  WRITE MULTIPLE (C4/C5, after SET MULTIPLE C6: 8 sectors at most, the
//  buffer), READ VERIFY (40/41), RECALIBRATE (1x), SEEK (7x), INITIALIZE
//  DEVICE PARAMETERS (91), SET FEATURES (EF), the power commands and FLUSH
//  CACHE (E0-E7, done at once), DEVICE RESET / DIAGNOSTIC (08/90: the ATA
//  signature); anything else aborted (ERR, ABRT).
//  Timing as the CD-ROM's: a command's first DRQ or its completion no
//  sooner than LATENCY_US after the command (OS/2's drivers wait for their
//  interrupt thread's signal, which an instant answer loses).
//============================================================================

module IBMRS6K7248_idehd #(
	parameter int unsigned CLK_HZ = 70_000_000
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        en,                    // the 850's personality and a mounted disk image: else no device

	input  logic        sel,                   // an access to 1F0-1F7 (cs1 = 0) or 3F6 (cs1 = 1)
	input  logic        cs1,
	input  logic        we,
	input  logic [2:0]  reg_a,
	input  logic [3:0]  be,
	input  logic [7:0]  wd8,
	input  logic [31:0] wdata,
	output logic [31:0] rdata,                 // the cycle after sel
	output logic        irq,
	output logic        selected,              // the drive register names this device (the machine's mux)

	input  logic [31:0] blocks,                // the image's size in 512-byte blocks

	// the SCSI bus to IBMRS6K7248_scsitgt, as an initiator
	output logic        want,
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

localparam logic [2:0] DISK_ID = 3'd0;
localparam logic [2:0] P_DOUT = 3'b000, P_DIN = 3'b001, P_CMD = 3'b010, P_STAT = 3'b011;
localparam int unsigned LATENCY_US = 2000;
localparam logic [7:0]  HEADS = 8'd16, SPT = 8'd63;

// the task file
logic [7:0] err, scnt, snum, cyl_l, cyl_h, drv;
logic       bsy_s, drdy, drq, errb, nien, ipend;
assign      selected = drv[4];
assign      irq = ipend & ~nien & selected;
wire  [7:0] status = {bsy_s, drdy, 1'b0, 1'b1, drq, 2'b00, errb};   // DSC always

// the disk: cylinders for the identify data (16383 at most) and the CHS translation
wire [31:0] cyls_all = blocks / 32'(HEADS * SPT);
wire [15:0] cyls_id  = cyls_all > 32'd16383 ? 16'd16383 : cyls_all[15:0];
wire [31:0] lba_chs  = (({cyl_h, cyl_l} * 32'(HEADS)) + 32'(drv[3:0])) * 32'(SPT) + 32'(snum) - 32'd1;
wire [31:0] lba_in   = drv[6] ? {4'd0, drv[3:0], cyl_h, cyl_l, snum} : lba_chs;

// the command in progress
typedef enum logic [3:0] {S_IDLE, S_ID, S_WANT, S_SEL, S_RUN, S_HOST, S_NEXT, S_DONE} st_t;
st_t s;
logic        wr;                               // a write command (the host's data first)
logic        verify;                           // READ VERIFY: no data to the host
logic        multi;                            // READ/WRITE MULTIPLE: blocks of the SET MULTIPLE count
logic [31:0] lba;                              // the next block to transfer
logic [8:0]  left;                             // sectors left (256 at most)
logic [3:0]  mult, bsz;                        // the SET MULTIPLE count; the sectors of the block running
logic [12:0] hptr, hlen;                       // the host's byte position in the block, its length
logic [12:0] tptr;                             // the target's byte position
logic [31:0] acc;
logic [3:0]  ci;
logic [7:0]  stat_b, idw;
logic [31:0] lat_cnt;
wire         lat_ok = lat_cnt == 32'd0;

// the data buffer: 4 KB (8 sectors), a word a line
logic [31:0] buf_mem [1024];
logic [9:0]  bwa, bra, bra_q;
logic [31:0] bwd, brq;
logic        bwe;
wire         host_rd = s == S_HOST && !wr;
wire  [9:0]  rda = host_rd ? hptr[11:2] : bra;
always_ff @(posedge clk) begin
	if (bwe) buf_mem[bwa] <= bwd;
	brq   <= buf_mem[rda];
	bra_q <= rda;
end

// the identify data
function automatic logic [15:0] ident(input logic [7:0] w);
	case (w)
		8'd0:  ident = 16'h0040;               // a fixed disk
		8'd1:  ident = cyls_id;
		8'd3:  ident = 16'(HEADS);
		8'd6:  ident = 16'(SPT);
		8'd10: ident = 16'h3030; 8'd11: ident = 16'h3030; 8'd12: ident = 16'h3032;   // serial "00002"
		8'd23: ident = 16'h312E; 8'd24: ident = 16'h3030;                         // firmware "1.00"
		8'd27: ident = 16'h4942; 8'd28: ident = 16'h4D20; 8'd29: ident = 16'h4844;  // "IBM HD"
		8'd30: ident = 16'h2D4D; 8'd31: ident = 16'h6953; 8'd32: ident = 16'h5465; 8'd33: ident = 16'h7220;  // "-MiSTer "
		8'd47: ident = 16'h8008;               // READ/WRITE MULTIPLE: 8 sectors at most
		8'd49: ident = 16'h0200;               // LBA
		8'd53: ident = 16'h0003;               // words 54-58 and 64 valid
		8'd54: ident = cyls_id;
		8'd55: ident = 16'(HEADS);
		8'd56: ident = 16'(SPT);
		8'd57: ident = 16'(32'(cyls_id) * 32'(HEADS) * 32'(SPT));
		8'd58: ident = 16'((32'(cyls_id) * 32'(HEADS) * 32'(SPT)) >> 16);
		8'd59: ident = mult != 4'd0 ? {8'h01, 4'd0, mult} : 16'h0000;
		8'd60: ident = blocks[15:0];
		8'd61: ident = blocks[31:16];
		8'd64: ident = 16'h0003;               // PIO 3, 4
		8'd80: ident = 16'h001E;               // ATA-1..4
		default: ident = (w >= 8'd13 && w <= 8'd19) || w == 8'd25 || w == 8'd26 || (w >= 8'd34 && w <= 8'd46) ? 16'h2020 : 16'h0000;
	endcase
endfunction
wire [15:0] idv = ident(idw);

// the data port's lanes
wire [1:0]  dbase = {hptr[1] & ~be[1], 1'b0};
wire [2:0]  nb    = be[1] ? 3'd4 : be[2] ? 3'd2 : 3'd1;
wire [12:0] hnext = hptr + 13'(nb);
wire        dsel  = sel && en && selected && !cs1 && reg_a == 3'd0 && drq;

// the CDB of the block running: READ(10) or WRITE(10), bsz blocks at lba
function automatic logic [7:0] cdb(input logic [3:0] i);
	case (i)
		4'd0: cdb = wr ? 8'h2A : 8'h28;
		4'd2: cdb = lba[31:24]; 4'd3: cdb = lba[23:16]; 4'd4: cdb = lba[15:8]; 4'd5: cdb = lba[7:0];
		4'd8: cdb = {4'd0, bsz};
		default: cdb = 8'h00;
	endcase
endfunction

// a command's end: a write or a verify (and any error) ends with the completion interrupt, a read does not
// (its last block's interrupt came with its DRQ)
task automatic finish(input logic ok);
	bsy_s <= 1'b0; drdy <= 1'b1; drq <= 1'b0;
	errb  <= !ok; err <= ok ? 8'h00 : 8'h40;    // UNC
	ipend <= !ok || wr || verify; s <= S_IDLE;
endtask

// the sectors of a block: the multiple count (1 without one), or what is left
function automatic logic [3:0] blk(input logic [8:0] n, input logic multi);
	logic [3:0] m;
	m = (multi && mult != 4'd0) ? mult : 4'd1;
	blk = n < 9'(m) ? 4'(n) : m;
endfunction

// the block after this one, or done; a write's next block is the host's first (DRQ with the interrupt)
task automatic next_block();
	logic [8:0] rest;
	rest = left - 9'(bsz);
	lba  <= lba + 32'(bsz);
	left <= rest;
	if (rest == 9'd0) s <= S_DONE;
	else begin
		bsz <= blk(rest, bsz != 4'd1 || multi);
		if (wr) begin s <= S_HOST; drq <= 1'b1; bsy_s <= 1'b0; hptr <= 13'd0; hlen <= 13'(blk(rest, bsz != 4'd1 || multi)) * 13'd512; ipend <= 1'b1; end
		else s <= S_WANT;
	end
endtask

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
		if (hnext >= hlen && s == S_HOST) begin
			drq <= 1'b0; bsy_s <= 1'b1;
			s <= wr ? S_WANT : S_NEXT;                        // a write's block goes to the disk; a read's is done
		end
	end

	// ---- the task file (the drive register is every device's)
	if (sel && en && we && cs1) begin
		nien <= wd8[1];
		if (wd8[2]) begin                                     // SRST: the ATA signature
			s <= S_IDLE; drq <= 1'b0; bsy_s <= 1'b0; drdy <= 1'b1; errb <= 1'b0; err <= 8'h01;
			snum <= 8'h01; scnt <= 8'h01; cyl_l <= 8'h00; cyl_h <= 8'h00; ipend <= 1'b0;
		end
	end
	if (sel && en && we && !cs1) case (reg_a)
		3'd1: ;                                               // features
		3'd2: scnt  <= wd8;
		3'd3: snum  <= wd8;
		3'd4: cyl_l <= wd8;
		3'd5: cyl_h <= wd8;
		3'd6: drv   <= wd8;
		3'd7: if (selected) begin                             // a command
			ipend <= 1'b0; errb <= 1'b0; err <= 8'h00;
			lat_cnt <= 32'(CLK_HZ / 1_000_000) * LATENCY_US;
			case (wd8)
				8'hEC: begin s <= S_ID; bsy_s <= 1'b1; idw <= 8'd0; end
				8'h20, 8'h21, 8'h30, 8'h31, 8'h40, 8'h41, 8'hC4, 8'hC5: begin
					logic [8:0] n0;
					logic [3:0] b0;
					n0 = scnt == 8'd0 ? 9'd256 : 9'(scnt);
					b0 = (wd8[7] && mult != 4'd0) ? (n0 < 9'(mult) ? 4'(n0) : mult) : 4'd1;
					wr     <= wd8 == 8'h30 || wd8 == 8'h31 || wd8 == 8'hC5;
					verify <= wd8[6] && !wd8[7];
					multi  <= wd8[7];
					lba    <= lba_in;
					left   <= n0;
					bsz    <= b0;
					if (lba_in >= blocks || (wd8[7] && mult == 4'd0)) begin errb <= 1'b1; err <= wd8[7] ? 8'h04 : 8'h10; ipend <= 1'b1; end   // ABRT / IDNF
					else if (wd8 == 8'h30 || wd8 == 8'h31 || wd8 == 8'hC5) begin   // a write: the host's first block (no interrupt), then the disk
						s <= S_HOST; drq <= 1'b1; hptr <= 13'd0; hlen <= 13'(b0) * 13'd512;
					end
					else begin s <= S_WANT; bsy_s <= 1'b1; end
				end
				8'hC6: begin                                  // SET MULTIPLE
					if (scnt > 8'd8 || scnt == 8'd0) begin errb <= 1'b1; err <= 8'h04; end
					else mult <= scnt[3:0];
					ipend <= 1'b1;
				end
				8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17, 8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
				8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D, 8'h7E, 8'h7F,
				8'h91, 8'hEF, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE5, 8'hE6, 8'hE7: begin
					drdy <= 1'b1; ipend <= 1'b1;              // seeks, device parameters, features, power, flush: done
				end
				8'h08, 8'h90: begin                           // DEVICE RESET, DIAGNOSTIC: the signature
					snum <= 8'h01; scnt <= 8'h01; cyl_l <= 8'h00; cyl_h <= 8'h00; err <= 8'h01;
					drdy <= 1'b1; drq <= 1'b0; s <= S_IDLE; ipend <= wd8 == 8'h90;
				end
				default: begin errb <= 1'b1; err <= 8'h04; ipend <= 1'b1; end
			endcase
		end
		default: ;
	endcase
	if (sel && en && !we && !cs1 && reg_a == 3'd7 && selected) ipend <= 1'b0;

	// ---- the command
	case (s)
		S_ID: begin
			if (!idw[0]) acc[15:0] <= idv;
			else begin bwe <= 1'b1; bwa <= {2'b00, idw[7:1]}; bwd <= {idv, acc[15:0]}; end
			if (idw != 8'd255 || lat_ok) idw <= idw + 8'd1;
			if (idw == 8'd255 && lat_ok) begin
				bsy_s <= 1'b0; drq <= 1'b1; hptr <= 13'd0; hlen <= 13'd512; ipend <= 1'b1;
				s <= S_HOST; wr <= 1'b0; left <= 9'd1; bsz <= 4'd1;
			end
		end
		S_WANT: if (grant && !bsy && lat_ok) begin i_sel <= 1'b1; s <= S_SEL; ci <= 4'd0; tptr <= 13'd0; bra <= 10'd0; stat_b <= 8'h00; end
		S_SEL: begin
			if (sel_fail) begin stat_b <= 8'h02; s <= S_DONE; end
			else if (sel_done) s <= S_RUN;
		end
		S_RUN: begin
			if (!bsy && !req) begin                           // the target let go: the block is done
				if (stat_b != 8'h00) begin s <= S_DONE; end
				else if (wr || verify) begin s <= S_NEXT; end
				else begin                                    // a read block to the host
					drq <= 1'b1; bsy_s <= 1'b0; hptr <= 13'd0; hlen <= 13'(bsz) * 13'd512; ipend <= 1'b1; s <= S_HOST;
				end
			end
			else if (req && !ack) begin
				case (phase)
					P_CMD: begin idata <= cdb(ci); ack <= 1'b1; ci <= ci + 4'd1; end
					P_DIN: begin
						acc[8 * tptr[1:0] +: 8] <= tdata;
						bwe <= 1'b1; bwa <= tptr[11:2];
						bwd <= acc; bwd[8 * tptr[1:0] +: 8] <= tdata;
						tptr <= tptr + 13'd1;
						ack  <= 1'b1;
					end
					P_DOUT: begin
						bra <= tptr[11:2];
						idata <= brq[8 * tptr[1:0] +: 8];
						if (bra == tptr[11:2] && bra_q == tptr[11:2]) begin ack <= 1'b1; tptr <= tptr + 13'd1; end
					end
					P_STAT: begin stat_b <= tdata; ack <= 1'b1; end
					default: ack <= 1'b1;
				endcase
			end
		end
		S_HOST: ;                                             // the host drains or fills the block (the data port)
		S_NEXT: next_block();
		S_DONE: if (lat_ok) finish(stat_b == 8'h00);
		default: ;
	endcase

	if (reset || !en) begin
		s <= S_IDLE; drq <= 1'b0; bsy_s <= 1'b0; drdy <= 1'b1; errb <= 1'b0; err <= 8'h01;
		snum <= 8'h01; scnt <= 8'h01; cyl_l <= 8'h00; cyl_h <= 8'h00; ipend <= 1'b0;
		drv <= 8'h00; nien <= 1'b0; lat_cnt <= 32'd0; mult <= 4'd0; wr <= 1'b0; verify <= 1'b0; multi <= 1'b0;
	end
end

assign want     = s == S_WANT || s == S_SEL || s == S_RUN;
assign i_sel_id = DISK_ID;

// the answer
always_ff @(posedge clk) if (sel) begin
	logic [7:0] v;
	if (!en || !selected) v = 8'h00;
	else if (cs1) v = status;
	else case (reg_a)
		3'd1: v = err;
		3'd2: v = scnt;
		3'd3: v = snum;
		3'd4: v = cyl_l;
		3'd5: v = cyl_h;
		3'd6: v = drv | 8'hA0;
		default: v = status;
	endcase
	if (en && selected && !cs1 && reg_a == 3'd0)
		rdata <= {brq[8 * dbase +: 8], brq[8 * (dbase + 2'd1) +: 8], brq[23:16], brq[31:24]};
	else
		rdata <= {4{v}};
end

endmodule
