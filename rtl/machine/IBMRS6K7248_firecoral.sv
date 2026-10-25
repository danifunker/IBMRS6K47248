//============================================================================
//
//  IBMRS6K7248 - IBM "Fire Coral", the PCI-ISA bridge: its configuration
//
//  Bus 0 device 11 (1014:000A) on the Carolina board. Here, first form:
//  its PCI configuration header (the ID, command, BAR0) and its internal
//  registers behind the index/data pair at BAR0 (index at BAR0+0, the
//  firmware writing it as a little-endian halfword; data at BAR0+4),
//  stored and read back. What the registers do (the ISA bus's timing, the
//  IDE, the interrupt routing) is not modelled yet: the firmware's values
//  are in firmware/disasm/reset_path.md, section 3.
//
//  The configuration interface is IBMRS6K7248_mpc105's. The I/O interface:
//  one byte a cycle, its offset in the BAR's 8 bytes; the read value in
//  io_rdata the cycle after io_sel.
//
//============================================================================

module IBMRS6K7248_firecoral
(
	input  logic        clk,
	input  logic        reset,

	// configuration
	input  logic        sel,
	input  logic        we,
	input  logic [7:2]  reg_n,
	input  logic [3:0]  be,            // bit k: byte k (little-endian)
	input  logic [31:0] wdata,
	output logic [31:0] rdata,

	// BAR0: where the index/data pair is, while I/O decoding is on
	output logic        io_on,
	output logic [15:3] io_base,

	// the index/data pair
	input  logic        io_sel,
	input  logic        io_we,
	input  logic [2:0]  io_off,
	input  logic [7:0]  io_wdata,
	output logic [7:0]  io_rdata
);

// ---- the configuration header -------------------------------------------------------
// (block RAM, zero at load; the command word and BAR0 also in registers, cleared by a reset)
logic [31:0]     stored;
logic [3:0][7:0] r01, r04;
// (four byte-wide RAMs: Quartus 17 infers no RAM from a byte-enabled packed array)
genvar bl;
generate for (bl = 0; bl < 4; bl = bl + 1) begin : lane
	logic [7:0] b [64];
	initial begin
		for (int i = 0; i < 64; i++) b[i] = 8'h00;
	end
	always_ff @(posedge clk) begin
		if (sel & we & be[bl]) b[reg_n] <= wdata[8 * bl +: 8];
		if (sel & ~we) stored[8 * bl +: 8] <= b[reg_n];
	end
end endgenerate
always_ff @(posedge clk) begin
	if (sel & we)
		for (int k = 0; k < 4; k++)
			if (be[k]) begin
				if (reg_n == 6'h01) r01[k] <= wdata[8 * k +: 8];
				if (reg_n == 6'h04) r04[k] <= wdata[8 * k +: 8];
			end
	if (reset) begin r01 <= '0; r04 <= '0; end
end

wire [31:0] bar0 = {r04[3], r04[2], r04[1], r04[0][7:3], 3'b001};   // 8 bytes of I/O
// the word a cycle after sel (rdata held until the next read)
logic [7:2] rn_q;
always_ff @(posedge clk) if (sel & ~we) rn_q <= reg_n;
always_comb begin
	case (rn_q)
		6'h00:   rdata = 32'h000A_1014;
		6'h01:   rdata = {16'h0200, r01[1], r01[0]};                     // status: medium DEVSEL
		6'h02:   rdata = 32'h0601_0000;                                  // ISA bridge
		6'h04:   rdata = bar0;
		default: rdata = stored;
	endcase
end
assign io_on   = r01[0][0];
assign io_base = bar0[15:3];

// ---- the internal registers -----------------------------------------------------------
logic [7:0] index;
logic [7:0] iregs [256];
always_ff @(posedge clk) begin
	if (io_sel) begin
		if (io_we) begin
			if (io_off == 3'd0) index <= io_wdata;
			if (io_off == 3'd4) iregs[index] <= io_wdata;
		end
		else io_rdata <= io_off == 3'd0 ? index : io_off == 3'd4 ? iregs[index] : 8'h00;
	end
	if (reset) index <= 8'h00;
end

endmodule
