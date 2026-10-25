//============================================================================
//
//  IBMRS6K7248 - the floppy disk controller (the PC87312's, an 82077AA in
//  AT mode) and its drive A:, a disk image
//
//  The registers at 3F0-3F7 (not 3F6, the IDE's): the digital output
//  register (DOR, 3F2), the tape drive register (TDR, 3F3), the main status
//  register (MSR, 3F4 read) and data rate select (DSR, 3F4 write), the
//  FIFO (3F5), the digital input register (DIR, 3F7 read: bit 7 the disk
//  change line) and the configuration control register (CCR, 3F7 write).
//  The command and result phases as QEMU's fdc.c has them: SPECIFY, SENSE
//  DRIVE STATUS, RECALIBRATE, SEEK, SENSE INTERRUPT STATUS (four results
//  after a reset), READ ID, the data commands, VERSION (90), CONFIGURE,
//  DUMPREG, LOCK, PERPENDICULAR MODE; anything else is invalid (80). IRQ 6
//  while an interrupt is pending and DOR bit 3 (DMA and interrupts on).
//
//  The drive: the OSD's floppy image (img_*, through IBMRS6K7248_fdimg's
//  sector bridge), 80 tracks, 2 heads, its sectors a track from its size
//  (720 KB 9, 1.2 MB 15, 1.44 MB 18, 2.88 MB 36), 512 bytes each. With no
//  image every command that needs a medium ends "missing address mark" (ST0
//  40, ST1 01); the disk change line is set by a mount and cleared by a
//  seek with a medium in.
//
//  The data commands: READ DATA (and its deleted form), READ TRACK (from
//  sector 1), VERIFY, WRITE DATA (a read-only image: "not writable", ST1
//  02), FORMAT TRACK (each sector's ID from the host, the filler byte
//  written), READ ID. A sector at a time from the image; its bytes to or
//  from the host by DMA channel 2 (dreq / dack, the byte at dev_byte) or,
//  with SPECIFY's ND set, through the FIFO (MSR's RQM, DIO and EXM). The
//  transfer ends with the DMA's terminal count, or at the track's end
//  sector (EOT; with MT on to head 1 first); the result: ST0-ST2, C, H, R
//  (the next sector), N.
//
//  The bus: one byte access a cycle by port offset, the read value in
//  rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_fdc
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic [2:0]  off,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	output logic        irq6,

	// DMA channel 2
	output logic        drq,
	input  logic        dack,
	input  logic [2:0]  dack_ch,
	input  logic [7:0]  dack_data,      // a write's byte from memory
	input  logic        tc,
	output logic [7:0]  dev_byte,       // a read's byte to memory

	// the image (IBMRS6K7248_fdimg): present, read-only, its size in sectors; mounted (a pulse)
	input  logic        img_in,
	input  logic        img_ro,
	input  logic [12:0] img_blocks,
	input  logic        img_mounted,
	// a sector: asked (toggle) to read (into the in buffer) or write (the out buffer), answered (toggle)
	output logic        sec_req,
	output logic        sec_we,
	output logic [12:0] sec_lba,
	input  logic        sec_ack,
	output logic [8:0]  buf_a,          // the in buffer's byte (a clock later at buf_q); the out buffer's write
	input  logic [7:0]  buf_q,
	output logic        buf_we,
	output logic [7:0]  buf_d
);

logic [7:0] dor, tdr, ccr;
logic [1:0] rate;                       // the data rate (DSR or CCR bits 1:0): 0 500 kbps, 1 300, 2 250, 3 1 Mbps
logic [7:0] cmdb [9];                 // the command's bytes
logic [3:0] ncmd, need;               // received, and how many it takes
logic [7:0] res [10];                 // the result
logic [3:0] nres, rpos;
logic       in_result;
logic       intp;                     // an interrupt pending
logic [7:0] st0;
logic [2:0] sensei;                   // results owed after a reset
logic [7:0] track [2];
logic [1:0] cur;
logic [7:0] spec1, spec2, config_r, precomp, perp;
logic       lock;
logic       dchg;                     // the disk change line

// the medium's sectors a track
wire  [5:0] spt = img_blocks >= 13'd5760 ? 6'd36 : img_blocks >= 13'd2880 ? 6'd18 : img_blocks >= 13'd2400 ? 6'd15 : 6'd9;
// the medium's data rate: 2.88 MB 1 Mbps, 1.44 MB and 1.2 MB 500 kbps, 720 KB 250 kbps. At another rate the
// controller finds no address marks (QEMU's fdc: ST0 40, ST1 01, as with no medium): a driver probing the
// density (the firmware tries 1 Mbps first) needs that answer
wire  [1:0] mrate = spt == 6'd36 ? 2'd3 : spt == 6'd9 ? 2'd2 : 2'd0;
wire        no_marks = !img_in || rate != mrate;
wire        nd  = spec2[0];           // SPECIFY's non-DMA

// the command's length by its first byte (0: invalid)
function automatic logic [3:0] cmdlen(input logic [7:0] c);
	case (c)
		8'h03: cmdlen = 4'd3;  8'h04: cmdlen = 4'd2;  8'h07: cmdlen = 4'd2;  8'h08: cmdlen = 4'd1;
		8'h0F: cmdlen = 4'd3;  8'h8F, 8'hCF: cmdlen = 4'd3;
		8'h0E: cmdlen = 4'd1;  8'h10: cmdlen = 4'd1;  8'h12: cmdlen = 4'd2;  8'h13: cmdlen = 4'd4;
		8'h14, 8'h94: cmdlen = 4'd1;
		default: case (c[4:0])
			5'h02, 5'h05, 5'h06, 5'h09, 5'h0C, 5'h11, 5'h16, 5'h19, 5'h1D: cmdlen = 4'd9;
			5'h0A: cmdlen = 4'd2;
			5'h0D: cmdlen = 4'd6;
			default: cmdlen = 4'd0;
		endcase
	endcase
endfunction

// ---- the execution phase -----------------------------------------------------------------------
typedef enum logic [3:0] {X_IDLE, X_SECT, X_RD, X_RD_W, X_OUT, X_IN, X_WR, X_WR_W, X_NEXT, X_FMT_ID, X_FMT_FILL,
                          X_FMT_WR, X_FMT_REQ, X_FMT_W, X_DONE} xst_t;
xst_t        xs;
logic [4:0]  xop;                     // the command (bits 4:0)
logic        mt;                      // multi-track
logic [1:0]  xd;                      // the drive
logic [7:0]  xc, xh, xr, xn, xeot;    // C, H, R, N, EOT
logic [9:0]  pos;                     // the byte in the sector (0-512)
logic        pf_ok;                   // the in buffer's byte at pos is in dev_byte / the FIFO
logic        tc_seen;
logic [7:0]  st1, st2;
logic        ack_q;
logic [7:0]  fmt_n, fmt_fill;         // FORMAT: sectors left, the filler
logic [1:0]  fmt_k;                   // ... the ID byte (C, H, R, N)
logic [7:0]  fmt_r;
wire         exec  = xs != X_IDLE;
wire         x_rd  = xs == X_OUT;     // bytes to the host
wire         x_wr  = xs == X_IN || xs == X_FMT_ID;   // bytes from the host
// the sector's address in the image
wire  [12:0] lba = 13'((({5'd0, xc} * 13'd2) + {12'd0, xh[0]}) * {7'd0, spt} + {5'd0, xr} - 13'd1);
wire         sec_ok = img_in && xc < 8'd80 && xr != 8'd0 && xr <= {2'b00, spt} && xn == 8'd2;

assign drq = !nd && dor[3] && ((x_rd && pf_ok) || x_wr);
wire   dma_go = dack && dack_ch == 3'd2;
// the FIFO, non-DMA: RQM while a byte can move
wire   pio_rq = nd && ((x_rd && pf_ok) || x_wr);
wire  [7:0] msr = in_result ? 8'hD0 : exec ? {pio_rq, x_rd, nd, 1'b1, 4'b0001} : (ncmd != 4'd0 ? 8'h90 : 8'h80);

// a byte to the host taken (DMA or the FIFO), or from it
wire   took_rd = x_rd && pf_ok && ((dma_go && !nd) || (sel && !we && off == 3'd5 && nd));
wire   got_wr  = x_wr && ((dma_go && !nd) || (sel && we && off == 3'd5 && nd));
wire  [7:0] host_byte = (sel && we && off == 3'd5) ? wdata : dack_data;

// results for a command that needs the medium: 7 bytes, abnormal termination, missing address mark
task automatic no_medium(input logic [1:0] d, input logic h, input logic [7:0] c, input logic [7:0] hh,
                         input logic [7:0] r, input logic [7:0] n);
	res[0] <= 8'h40 | {5'd0, h, d};
	res[1] <= 8'h01;
	res[2] <= 8'h00;
	res[3] <= c;
	res[4] <= hh;
	res[5] <= r;
	res[6] <= n;
	nres <= 4'd7;
	rpos <= 4'd0;
	in_result <= 1'b1;
	intp <= 1'b1;
endtask

always_ff @(posedge clk) begin
	buf_we <= 1'b0;
	if (img_mounted) dchg <= 1'b1;
	if (dma_go && tc) tc_seen <= 1'b1;

	if (sel) begin
		if (we) begin
			case (off)
				3'd2: begin
					// leaving reset (bit 2 from 0 to 1): the controller resets, an interrupt
					// and four sense-interrupt results owed
					if (!dor[2] && wdata[2]) begin
						ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b1; sensei <= 3'd4; st0 <= 8'hC0; xs <= X_IDLE;
					end
					if (!wdata[2]) begin ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b0; xs <= X_IDLE; end
					dor <= wdata;
				end
				3'd3: tdr <= wdata;
				3'd4: begin                  // DSR: the data rate; bit 7 a software reset
					rate <= wdata[1:0];
					if (wdata[7]) begin
						ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b1; sensei <= 3'd4; st0 <= 8'hC0; xs <= X_IDLE;
					end
				end
				3'd5: if (!in_result && !exec && dor[2]) begin
					cmdb[ncmd] <= wdata;
					if (ncmd == 4'd0) need <= cmdlen(wdata);
					// the command is complete: execute it
					if ((ncmd == 4'd0 && cmdlen(wdata) <= 4'd1) || (ncmd != 4'd0 && ncmd + 4'd1 == need)) begin
						ncmd <= 4'd0;
						case (ncmd == 4'd0 ? wdata : cmdb[0])
							8'h03: begin spec1 <= cmdb[1]; spec2 <= wdata; end          // SPECIFY
							8'h04: begin                                                   // SENSE DRIVE STATUS
								res[0] <= {1'b0, img_ro && img_in, 1'b1, track[wdata[0]] == 8'd0, 1'b1, wdata[2:0]};
								nres <= 4'd1; rpos <= 4'd0; in_result <= 1'b1;
							end
							8'h07: begin                                                   // RECALIBRATE
								cur <= wdata[1:0]; track[wdata[0]] <= 8'd0;
								st0 <= 8'h20 | {6'd0, wdata[1:0]}; intp <= 1'b1;
								if (img_in) dchg <= 1'b0;
							end
							8'h0F: begin                                                   // SEEK
								cur <= cmdb[1][1:0]; track[cmdb[1][0]] <= wdata;
								st0 <= 8'h20 | {6'd0, cmdb[1][1:0]}; intp <= 1'b1;
								if (img_in) dchg <= 1'b0;
							end
							8'h8F, 8'hCF: begin                                            // RELATIVE SEEK
								cur <= cmdb[1][1:0];
								track[cmdb[1][0]] <= cmdb[0][6] ? track[cmdb[1][0]] - wdata : track[cmdb[1][0]] + wdata;
								st0 <= 8'h20 | {6'd0, cmdb[1][1:0]}; intp <= 1'b1;
								if (img_in) dchg <= 1'b0;
							end
							8'h08: begin                                                   // SENSE INTERRUPT STATUS
								if (sensei != 3'd0) begin
									res[0] <= 8'hC0 + {6'd0, 2'(3'd4 - sensei)};
									res[1] <= track[2'(3'd4 - sensei) == 2'd0 ? 1'b0 : 1'b1];
									nres <= 4'd2; sensei <= sensei - 3'd1; intp <= 1'b0;
								end
								else if (!intp) begin res[0] <= 8'h80; nres <= 4'd1; end
								else begin
									res[0] <= {st0[7:2], cur}; res[1] <= track[cur[0]];
									nres <= 4'd2; intp <= 1'b0; st0 <= 8'hC0;
								end
								rpos <= 4'd0; in_result <= 1'b1;
							end
							8'h0E: begin                                                   // DUMPREG
								res[0] <= track[0]; res[1] <= track[1]; res[2] <= 8'd0; res[3] <= 8'd0;
								res[4] <= spec1; res[5] <= spec2; res[6] <= {2'b00, spt};
								res[7] <= {lock, perp[6:0]}; res[8] <= config_r; res[9] <= precomp;
								nres <= 4'd10; rpos <= 4'd0; in_result <= 1'b1;
							end
							8'h10: begin res[0] <= 8'h90; nres <= 4'd1; rpos <= 4'd0; in_result <= 1'b1; end   // VERSION
							8'h12: perp <= wdata;                                          // PERPENDICULAR MODE
							8'h13: begin config_r <= cmdb[2]; precomp <= wdata; end        // CONFIGURE
							8'h14, 8'h94: begin                                            // LOCK
								lock <= wdata[7];
								res[0] <= {3'd0, wdata[7], 4'd0}; nres <= 4'd1; rpos <= 4'd0; in_result <= 1'b1;
							end
							default: begin
								if (cmdlen(ncmd == 4'd0 ? wdata : cmdb[0]) == 4'd0) begin      // invalid
									res[0] <= 8'h80; nres <= 4'd1; rpos <= 4'd0; in_result <= 1'b1;
								end
								else if (cmdb[0][4:0] == 5'h0A) begin                       // READ ID
									cur <= wdata[1:0];
									if (no_marks) no_medium(wdata[1:0], wdata[2], track[wdata[0]], {7'd0, wdata[2]}, 8'd1, 8'd2);
									else begin
										res[0] <= {5'd0, wdata[2], wdata[1:0]}; res[1] <= 8'h00; res[2] <= 8'h00;
										res[3] <= track[wdata[0]]; res[4] <= {7'd0, wdata[2]}; res[5] <= 8'd1; res[6] <= 8'd2;
										nres <= 4'd7; rpos <= 4'd0; in_result <= 1'b1; intp <= 1'b1;
									end
								end
								else if (no_marks) begin                                    // no medium, or another data rate
									if (cmdb[0][4:0] == 5'h0D) begin
										cur <= cmdb[1][1:0];
										no_medium(cmdb[1][1:0], cmdb[1][2], track[cmdb[1][0]], {7'd0, cmdb[1][2]}, 8'd1, cmdb[2]);
									end
									else begin
										cur <= cmdb[1][1:0];
										no_medium(cmdb[1][1:0], cmdb[1][2], cmdb[2], cmdb[3], cmdb[4], cmdb[5]);
									end
								end
								else begin                                                  // a data command or FORMAT
									cur      <= cmdb[1][1:0];
									xop      <= cmdb[0][4:0];
									mt       <= cmdb[0][7];
									xd       <= cmdb[1][1:0];
									st0      <= 8'h00;
									st1      <= 8'h00;
									st2      <= 8'h00;
									tc_seen  <= 1'b0;
									if (cmdb[0][4:0] == 5'h0D) begin                        // FORMAT: N, SC, GPL, D
										xc       <= track[cmdb[1][0]];
										xh       <= {7'd0, cmdb[1][2]};
										xn       <= cmdb[2];
										fmt_n    <= cmdb[3];
										fmt_fill <= wdata;
										fmt_k    <= 2'd0;
										xs       <= X_FMT_ID;
									end
									else begin                                              // C H R N EOT GPL DTL
										xc   <= cmdb[2];
										xh   <= cmdb[3];
										xr   <= cmdb[0][4:0] == 5'h02 ? 8'd1 : cmdb[4];  // READ TRACK: from sector 1
										xn   <= cmdb[5];
										xeot <= cmdb[6];
										xs   <= X_SECT;
									end
								end
							end
						endcase
					end
					else ncmd <= ncmd + 4'd1;
				end
				3'd7: begin ccr <= wdata; rate <= wdata[1:0]; end   // CCR: the data rate too
				default: ;
			endcase
		end
		else begin
			case (off)
				3'd2: rdata <= dor;
				3'd3: rdata <= tdr;
				3'd4: rdata <= msr;
				3'd5: if (in_result) begin
					// (a result byte read clears the interrupt, as the 82077's: READ ID's left set would leave
					// the next command's completion no edge for the 8259; SENSE INTERRUPT clears it at the command)
					rdata <= res[rpos];
					intp  <= 1'b0;
					if (rpos + 4'd1 == nres) in_result <= 1'b0;
					else rpos <= rpos + 4'd1;
				end
				else if (exec && nd && x_rd) rdata <= dev_byte;
				else rdata <= 8'hFF;
				3'd7: rdata <= {dchg, 7'h7F};
				default: rdata <= 8'hFF;
			endcase
		end
	end

	// ---- the execution phase ----
	ack_q <= sec_ack;
	case (xs)
		X_SECT: begin                                    // the sector: there?
			if (!sec_ok) begin st1 <= 8'h04; st0 <= 8'h40; xs <= X_DONE; end            // no data
			else if (xop == 5'h05 || xop == 5'h09) begin
				if (img_ro) begin st1 <= 8'h02; st0 <= 8'h40; xs <= X_DONE; end         // not writable
				else begin pos <= 10'd0; xs <= X_IN; end
			end
			else if (xop == 5'h16) xs <= X_NEXT;                                     // VERIFY: no data moved
			else begin sec_we <= 1'b0; sec_lba <= lba; sec_req <= ~sec_req; xs <= X_RD_W; end
		end
		X_RD_W: if (sec_ack != ack_q) begin pos <= 10'd0; buf_a <= 9'd0; pf_ok <= 1'b0; xs <= X_RD; end
		X_RD: begin pf_ok <= 1'b0; xs <= X_OUT; end      // (the buffer takes the address)
		X_OUT: begin
			if (!pf_ok) begin dev_byte <= buf_q; pf_ok <= 1'b1; end
			else if (took_rd) begin
				pf_ok <= 1'b0;
				if (pos == 10'd511 || tc_seen || (dma_go && tc)) begin pos <= pos + 10'd1; xs <= X_NEXT; end
				else begin pos <= pos + 10'd1; buf_a <= 9'(pos + 10'd1); xs <= X_RD; end
			end
		end
		X_IN: if (got_wr) begin
			buf_we <= 1'b1; buf_a <= pos[8:0]; buf_d <= host_byte;
			pos <= pos + 10'd1;
			if (pos == 10'd511) xs <= X_WR;
		end
		X_WR: begin sec_we <= 1'b1; sec_lba <= lba; sec_req <= ~sec_req; xs <= X_WR_W; end
		X_WR_W: if (sec_ack != ack_q) xs <= X_NEXT;
		X_NEXT: begin
			// the next sector, unless the terminal count came or the track (and with MT, head 1) ended;
			// past head 1's last sector with MT the result's H is back to 0 (the 82077's, QEMU's)
			if (tc_seen) begin xr <= xr + 8'd1; xs <= X_DONE; end
			else if (xr == xeot) begin
				if (mt && xh == 8'd0) begin xh <= 8'd1; xr <= 8'd1; xs <= X_SECT; end
				else begin xr <= 8'd1; xc <= xc + 8'd1; if (mt) xh <= 8'd0; xs <= X_DONE; end
			end
			else begin xr <= xr + 8'd1; xs <= X_SECT; end
		end
		// FORMAT: each sector's C, H, R, N from the host, then the sector filled
		X_FMT_ID: if (got_wr) begin
			if (fmt_k == 2'd2) fmt_r <= host_byte;
			fmt_k <= fmt_k + 2'd1;
			if (fmt_k == 2'd3) begin pos <= 10'd0; xs <= X_FMT_FILL; end
		end
		X_FMT_FILL: begin
			buf_we <= 1'b1; buf_a <= pos[8:0]; buf_d <= fmt_fill;
			pos <= pos + 10'd1;
			if (pos == 10'd511) xs <= X_FMT_WR;
		end
		X_FMT_WR: begin
			if (img_ro) begin st1 <= 8'h02; st0 <= 8'h40; xs <= X_DONE; end
			else begin xr <= fmt_r; xs <= X_FMT_REQ; end
		end
		X_FMT_REQ: begin sec_lba <= lba; sec_we <= 1'b1; sec_req <= ~sec_req; xs <= X_FMT_W; end   // (the ID's R in xr)
		X_FMT_W: begin
			if (sec_ack != ack_q) begin
				fmt_n <= fmt_n - 8'd1;
				if (fmt_n == 8'd1 || tc_seen) begin xr <= fmt_r; xs <= X_DONE; end
				else begin fmt_k <= 2'd0; xs <= X_FMT_ID; end
			end
		end
		X_DONE: begin
			res[0] <= st0 | {5'd0, xh[0], xd};
			res[1] <= st1; res[2] <= st2;
			res[3] <= xc; res[4] <= xh; res[5] <= xr; res[6] <= xn;
			st0 <= 8'h00;
			nres <= 4'd7; rpos <= 4'd0; in_result <= 1'b1; intp <= 1'b1;
			xs <= X_IDLE;
		end
		default: ;
	endcase

	if (reset) begin
		dor <= 8'h00; tdr <= 8'h00; ccr <= 8'h00; rate <= 2'd0; ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b0;
		sensei <= 3'd0; st0 <= 8'hC0; track[0] <= 8'd0; track[1] <= 8'd0; cur <= 2'd0;
		spec1 <= 8'h00; spec2 <= 8'h00; config_r <= 8'h20; precomp <= 8'h00; perp <= 8'h00; lock <= 1'b0;
		xs <= X_IDLE; dchg <= 1'b1; sec_req <= 1'b0; pf_ok <= 1'b0;
	end
end

assign irq6 = intp & dor[3];

endmodule
