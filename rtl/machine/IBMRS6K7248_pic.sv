//============================================================================
//
//  IBMRS6K7248 - the two 8259A interrupt controllers (in Fire Coral)
//
//  The PC/AT pair: the master at 20/21, the slave at A0/A1 on the master's
//  IRQ2, the edge/level control registers (ELCR) at 4D0/4D1. What a
//  PowerPC firmware and AIX use of the chip:
//
//    ICW1-ICW4 (ICW3's cascade wiring is the AT's whatever is written;
//    ICW4's AEOI and special fully nested mode), OCW1 (the mask), OCW2
//    (non-specific and specific EOI, rotation, set priority), OCW3 (read
//    IRR or ISR, poll, special mask mode), the interrupt acknowledge (the
//    PReP bridge's read of BFFFFFF0 is a whole INTA sequence: the vector of
//    the highest request, the slave's through the cascade; with no request
//    IRQ7's or IRQ15's vector, the 8259's spurious interrupt), and edge or
//    level sense per line (ELCR, or ICW1's LTIM for a whole chip).
//
//  Edge mode keeps a request latched from its rising edge until it is
//  acknowledged (the real chip also drops it if the line falls first).
//
//  The output is the master's INT, a level, for the CPU's external
//  interrupt.
//
//  The bus: one byte access a cycle by port, the read value in rdata the
//  cycle after sel; iack reads the vector in the same way.
//
//============================================================================

module IBMRS6K7248_pic
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic        slave,         // A0/A1 (else 20/21)
	input  logic        a0,
	input  logic        elcr_sel,      // 4D0 / 4D1 (slave picks)
	input  logic        iack,          // the interrupt acknowledge (a read)
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	input  logic [15:0] irq,           // the request lines (IRQ2 is the cascade: its input is ignored)
	output logic        intr
);

// the highest-priority bit of v, the priorities rotated so that line lowest is the lowest;
// bit 3 set: none
function automatic logic [3:0] prio(input logic [7:0] v, input logic [2:0] lowest);
	logic [3:0] r;
	logic [2:0] n;
	r = 4'h8;
	for (int i = 7; i >= 0; i--) begin
		n = 3'(lowest + 3'(i) + 3'd1);
		if (v[n]) r = {1'b0, n};
	end
	return r;
endfunction

// the request to raise INT for: the highest unmasked request above the highest in service
// (special mask mode: any unmasked request not itself in service); bit 3 set: none
function automatic logic [3:0] pending(input logic [7:0] irr, input logic [7:0] isr, input logic [7:0] imr,
                                       input logic [2:0] lowest, input logic smm);
	logic [3:0] hr, hs;
	logic [2:0] dr, ds;
	hr = prio(irr & ~imr, lowest);
	hs = prio(smm ? (isr & ~imr) : isr, lowest);
	dr = 3'(hr[2:0] - lowest - 3'd1);
	ds = 3'(hs[2:0] - lowest - 3'd1);
	if (hr[3])                  pending = 4'h8;
	else if (smm)               pending = isr[hr[2:0]] ? 4'h8 : hr;
	else if (!hs[3] && dr >= ds) pending = 4'h8;
	else                        pending = hr;
endfunction

logic [7:0] irr [2], isr [2], imr [2], last [2], elcr [2];
logic [4:0] vbase [2];
logic       ltim [2], need_icw4 [2], single [2], aeoi [2], smm [2], read_isr [2], poll [2], rot_aeoi [2];
logic [1:0] step [2];             // 0 ready; 1 ICW2 next; 2 ICW3 next; 3 ICW4 next
logic [2:0] lowest [2];
logic [3:0] pend [2];

assign pend[1] = pending(irr[1], isr[1], imr[1], lowest[1], smm[1]);
assign pend[0] = pending(irr[0], isr[0], imr[0], lowest[0], smm[0]);
wire   int_s   = ~pend[1][3];
assign intr    = ~pend[0][3];

// each chip's lines, and which are level-sensitive
wire [7:0] line [2];
assign line[0] = {irq[7:3], int_s, irq[1:0]};
assign line[1] = irq[15:8];
wire [7:0] lvl [2];
assign lvl[0] = elcr[0] | {8{ltim[0]}};
assign lvl[1] = elcr[1] | {8{ltim[1]}};

// the acknowledge: the master's highest request; through IRQ2, the slave's
wire       m_none = pend[0][3];
wire [2:0] m_n    = m_none ? 3'd7 : pend[0][2:0];
wire       via_s  = ~m_none & m_n == 3'd2;
wire       s_none = pend[1][3];
wire [2:0] s_n    = s_none ? 3'd7 : pend[1][2:0];
wire       ack_m  = sel & iack & ~m_none;
wire       ack_s  = sel & iack & via_s & ~s_none;

// non-specific EOI's line
wire [3:0] eoi_n [2];
assign eoi_n[0] = prio(isr[0], lowest[0]);
assign eoi_n[1] = prio(isr[1], lowest[1]);

wire       me    = slave;          // the chip addressed
wire       acc_w = sel & ~iack & ~elcr_sel & we;
wire       acc_r = sel & ~iack & ~elcr_sel & ~we;

for (genvar c = 0; c < 2; c++) begin : g_chip
	wire        this_w = acc_w & (me == c[0]);
	wire        this_r = acc_r & (me == c[0]);
	wire        icw1   = this_w & ~a0 & wdata[4];
	wire        ocw3   = this_w & ~a0 & ~wdata[4] & wdata[3];
	wire        ocw2   = this_w & ~a0 & ~wdata[4] & ~wdata[3];
	wire        odd_w  = this_w & a0;
	wire        ack    = c == 0 ? ack_m : ack_s;
	wire [2:0]  ack_n  = c == 0 ? m_n : s_n;
	wire        poll_r = this_r & poll[c];
	wire [3:0]  pn     = pend[c];

	always_ff @(posedge clk) begin
		last[c] <= line[c];
		// requests: a level line follows its input; an edge line latches a rising edge
		irr[c]  <= (lvl[c] & line[c]) | (~lvl[c] & (irr[c] | (line[c] & ~last[c])));

		if (icw1) begin
			ltim[c]      <= wdata[3];
			single[c]    <= wdata[1];
			need_icw4[c] <= wdata[0];
			imr[c]       <= 8'h00;
			isr[c]       <= 8'h00;
			irr[c]       <= 8'h00;
			lowest[c]    <= 3'd7;
			read_isr[c]  <= 1'b0;
			smm[c]       <= 1'b0;
			aeoi[c]      <= 1'b0;
			step[c]      <= 2'd1;
		end
		if (ocw3) begin
			if (wdata[1]) read_isr[c] <= wdata[0];
			poll[c] <= wdata[2];
			if (wdata[6]) smm[c] <= wdata[5];
		end
		if (ocw2) begin
			case (wdata[7:5])
				3'b001: if (!eoi_n[c][3]) isr[c][eoi_n[c][2:0]] <= 1'b0;            // non-specific EOI
				3'b101: if (!eoi_n[c][3]) begin                                    // ... and rotate
					isr[c][eoi_n[c][2:0]] <= 1'b0;
					lowest[c] <= eoi_n[c][2:0];
				end
				3'b011: isr[c][wdata[2:0]] <= 1'b0;                                // specific EOI
				3'b111: begin isr[c][wdata[2:0]] <= 1'b0; lowest[c] <= wdata[2:0]; end
				3'b110: lowest[c] <= wdata[2:0];                                   // set priority
				3'b100: rot_aeoi[c] <= 1'b1;
				3'b000: rot_aeoi[c] <= 1'b0;
				default: ;
			endcase
		end
		if (odd_w) begin
			case (step[c])
				2'd1: begin
					vbase[c] <= wdata[7:3];
					step[c]  <= single[c] ? (need_icw4[c] ? 2'd3 : 2'd0) : 2'd2;
				end
				2'd2: step[c] <= need_icw4[c] ? 2'd3 : 2'd0;                       // ICW3
				2'd3: begin
					aeoi[c] <= wdata[1];
					step[c] <= 2'd0;
				end
				default: imr[c] <= wdata;                                          // OCW1
			endcase
		end
		// a poll read is an acknowledge of this chip alone
		if (poll_r) begin
			poll[c] <= 1'b0;
			if (!pn[3]) begin
				isr[c][pn[2:0]] <= 1'b1;
				if (!lvl[c][pn[2:0]]) irr[c][pn[2:0]] <= 1'b0;
			end
		end
		if (ack) begin
			if (!aeoi[c]) isr[c][ack_n] <= 1'b1;
			else if (rot_aeoi[c]) lowest[c] <= ack_n;
			if (!lvl[c][ack_n]) irr[c][ack_n] <= 1'b0;
		end
		if (sel & elcr_sel & we & (me == c[0]))
			elcr[c] <= wdata & (c == 0 ? 8'hF8 : 8'hDE);                           // IRQ0-2, 8 and 13 are edge only

		if (reset) begin
			irr[c] <= '0; isr[c] <= '0; imr[c] <= 8'hFF; elcr[c] <= '0; vbase[c] <= '0;
			ltim[c] <= 1'b0; single[c] <= 1'b0; need_icw4[c] <= 1'b0; aeoi[c] <= 1'b0; smm[c] <= 1'b0;
			read_isr[c] <= 1'b0; poll[c] <= 1'b0; rot_aeoi[c] <= 1'b0; step[c] <= 2'd0; lowest[c] <= 3'd7;
		end
	end
end

// ---- reads --------------------------------------------------------------------------
always_ff @(posedge clk) begin
	if (sel & iack)
		rdata <= via_s ? {vbase[1], s_n} : {vbase[0], m_n};
	else if (sel & elcr_sel & ~we)
		rdata <= elcr[me];
	else if (acc_r) begin
		if (poll[me])       rdata <= {~pend[me][3], 4'd0, pend[me][2:0]};
		else if (!a0)       rdata <= read_isr[me] ? isr[me] : irr[me];
		else                rdata <= imr[me];
	end
end

endmodule
