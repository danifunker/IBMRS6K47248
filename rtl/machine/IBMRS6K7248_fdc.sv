//============================================================================
//
//  IBMRS6K7248 - the floppy disk controller (the PC87312's, an 82077AA in
//  AT mode), first form: the drive empty
//
//  The registers at 3F0-3F7 (not 3F6, the IDE's): the digital output
//  register (DOR, 3F2), the tape drive register (TDR, 3F3), the main status
//  register (MSR, 3F4 read) and data rate select (DSR, 3F4 write), the
//  FIFO (3F5), the digital input register (DIR, 3F7 read: bit 7 the disk
//  change line) and the configuration control register (CCR, 3F7 write).
//  The command and result phases as QEMU's fdc.c has them: SPECIFY, SENSE
//  DRIVE STATUS, RECALIBRATE, SEEK, SENSE INTERRUPT STATUS (four results
//  after a reset), READ ID, the data commands (READ, WRITE, the deleted and
//  scan forms, READ TRACK, FORMAT), VERSION (90), CONFIGURE, DUMPREG, LOCK,
//  PERPENDICULAR MODE; anything else is invalid (80). IRQ 6 while an
//  interrupt is pending and DOR bit 3 (DMA and interrupts on) is set.
//
//  The drive (A:) is there and empty: seeks and recalibrations move its
//  head and end at once; every command that needs the medium ends with
//  "abnormal termination, missing address mark" (ST0 40, ST1 01), as QEMU
//  answers for no medium, and the disk change line stays set. Disk images
//  and the 8237's channel 2 come with milestone M5 (docs/plan.md).
//
//  The bus: one byte access a cycle by port offset, the read value in
//  rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_fdc
(
	input  logic       clk,
	input  logic       reset,

	input  logic       sel,
	input  logic       we,
	input  logic [2:0] off,
	input  logic [7:0] wdata,
	output logic [7:0] rdata,

	output logic       irq6
);

logic [7:0] dor, tdr, ccr;
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

// the command's length by its first byte (0: invalid)
function automatic logic [3:0] cmdlen(input logic [7:0] c);
	case (c)
		8'h03: cmdlen = 4'd3;  8'h04: cmdlen = 4'd2;  8'h07: cmdlen = 4'd2;  8'h08: cmdlen = 4'd1;
		8'h0F: cmdlen = 4'd3;  8'h8F, 8'hCF: cmdlen = 4'd3;
		8'h0E: cmdlen = 4'd1;  8'h10: cmdlen = 4'd1;  8'h12: cmdlen = 4'd2;  8'h13: cmdlen = 4'd4;
		8'h14, 8'h94: cmdlen = 4'd1;
		default: case (c[4:0])
			5'h02, 5'h05, 5'h06, 5'h09, 5'h0C, 5'h11, 5'h19, 5'h1D: cmdlen = 4'd9;
			5'h0A: cmdlen = 4'd2;
			5'h0D: cmdlen = 4'd6;
			default: cmdlen = 4'd0;
		endcase
	endcase
endfunction

wire [7:0] msr = in_result ? 8'hD0 : (ncmd != 4'd0 ? 8'h90 : 8'h80);

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
	if (sel) begin
		if (we) begin
			case (off)
				3'd2: begin
					// leaving reset (bit 2 from 0 to 1): the controller resets, an interrupt
					// and four sense-interrupt results owed
					if (!dor[2] && wdata[2]) begin
						ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b1; sensei <= 3'd4; st0 <= 8'hC0;
					end
					if (!wdata[2]) begin ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b0; end
					dor <= wdata;
				end
				3'd3: tdr <= wdata;
				3'd4: if (wdata[7]) begin    // DSR: software reset
					ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b1; sensei <= 3'd4; st0 <= 8'hC0;
				end
				3'd5: if (!in_result && dor[2]) begin
					cmdb[ncmd] <= wdata;
					if (ncmd == 4'd0) need <= cmdlen(wdata);
					// the command is complete: execute it
					if ((ncmd == 4'd0 && cmdlen(wdata) <= 4'd1) || (ncmd != 4'd0 && ncmd + 4'd1 == need)) begin
						ncmd <= 4'd0;
						case (ncmd == 4'd0 ? wdata : cmdb[0])
							8'h03: begin spec1 <= cmdb[1]; spec2 <= wdata; end          // SPECIFY
							8'h04: begin                                                   // SENSE DRIVE STATUS
								res[0] <= {2'b00, 1'b1, track[wdata[0]] == 8'd0, 1'b1, wdata[2:0]};
								nres <= 4'd1; rpos <= 4'd0; in_result <= 1'b1;
							end
							8'h07: begin                                                   // RECALIBRATE
								cur <= wdata[1:0]; track[wdata[0]] <= 8'd0;
								st0 <= 8'h20 | {6'd0, wdata[1:0]}; intp <= 1'b1;
							end
							8'h0F: begin                                                   // SEEK
								cur <= cmdb[1][1:0]; track[cmdb[1][0]] <= wdata;
								st0 <= 8'h20 | {6'd0, cmdb[1][1:0]}; intp <= 1'b1;
							end
							8'h8F, 8'hCF: begin                                            // RELATIVE SEEK
								cur <= cmdb[1][1:0];
								track[cmdb[1][0]] <= cmdb[0][6] ? track[cmdb[1][0]] - wdata : track[cmdb[1][0]] + wdata;
								st0 <= 8'h20 | {6'd0, cmdb[1][1:0]}; intp <= 1'b1;
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
								res[4] <= spec1; res[5] <= spec2; res[6] <= 8'd18;
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
									no_medium(wdata[1:0], wdata[2], track[wdata[0]], {7'd0, wdata[2]}, 8'd1, 8'd2);
								end
								else if (cmdb[0][4:0] == 5'h0D) begin                       // FORMAT
									cur <= cmdb[1][1:0];
									no_medium(cmdb[1][1:0], cmdb[1][2], track[cmdb[1][0]], {7'd0, cmdb[1][2]}, 8'd1, cmdb[2]);
								end
								else begin                                                  // the data commands
									cur <= cmdb[1][1:0];
									no_medium(cmdb[1][1:0], cmdb[1][2], cmdb[2], cmdb[3], cmdb[4], cmdb[5]);
								end
							end
						endcase
					end
					else ncmd <= ncmd + 4'd1;
				end
				3'd7: ccr <= wdata;
				default: ;
			endcase
		end
		else begin
			case (off)
				3'd2: rdata <= dor;
				3'd3: rdata <= tdr;
				3'd4: rdata <= msr;
				3'd5: if (in_result) begin
					rdata <= res[rpos];
					if (rpos + 4'd1 == nres) in_result <= 1'b0;
					else rpos <= rpos + 4'd1;
				end
				else rdata <= 8'hFF;
				3'd7: rdata <= 8'h80;              // the disk change line: no diskette
				default: rdata <= 8'hFF;
			endcase
		end
	end
	if (reset) begin
		dor <= 8'h00; tdr <= 8'h00; ccr <= 8'h00; ncmd <= 4'd0; in_result <= 1'b0; intp <= 1'b0;
		sensei <= 3'd0; st0 <= 8'hC0; track[0] <= 8'd0; track[1] <= 8'd0; cur <= 2'd0;
		spec1 <= 8'h00; spec2 <= 8'h00; config_r <= 8'h20; precomp <= 8'h00; perp <= 8'h00; lock <= 1'b0;
	end
end

assign irq6 = intp & dor[3];

endmodule
