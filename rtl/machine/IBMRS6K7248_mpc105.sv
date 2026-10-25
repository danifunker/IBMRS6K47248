//============================================================================
//
//  IBMRS6K7248 - the Motorola MPC105 "Eagle": its configuration space
//
//  The host bridge, memory controller and L2 controller of the Carolina
//  board, bus 0 device 0 (1057:0001). Here: its configuration registers,
//  reached through the machine's CF8/CFC (IBMRS6K7248_machine decodes the
//  cycle), and the memory banks' registers brought out for the machine's
//  RAM decode. The decode itself, the RAM behind each bank and the
//  floating memory bus are the machine's.
//
//  Registers (the MPC105 user's manual's map; the values the 7248 v1.12
//  ROM writes are in firmware/disasm/reset_path.md, section 6):
//    00  vendor 1057, device 0001                       read only
//    04  command / status                               stored; status reads 0
//    08  revision, class 060000 (host bridge)           read only
//    80, 84  memory starting address, banks 0-3, 4-7    A27-A20 of each bank's first MB
//    88, 8C  extended starting address                  A29-A28
//    90, 94  memory ending address                      A27-A20 of each bank's last MB
//    98, 9C  extended ending address                    A29-A28
//    A0      memory bank enable (byte 0)                bit n: bank n
//    A8, AC  PICR1, PICR2                               stored (PICR1 brought out:
//                                                       its LE_MODE bit, later)
//    C0-C7   error enables and detection                stored; the detection and
//                                                       status bytes (C1, C3, C5, C7)
//                                                       read 0: no error is ever seen
//    F0-FC   MCCR1-MCCR4                                stored
//  Every other register is stored and read back as written (64 words).
//
//  The configuration interface: one access a cycle, a register by its
//  word number, little-endian byte enables and data (byte 0 in bits 7-0,
//  as the PCI bus has them); the read value in rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_mpc105
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic [7:2]  reg_n,
	input  logic [3:0]  be,            // bit k: byte k (little-endian)
	input  logic [31:0] wdata,
	output logic [31:0] rdata,

	// the memory banks (quasi-static once the firmware has set them)
	output logic [7:0]       bank_en,
	output logic [7:0][9:0]  bank_start,    // A29-A20 of the first MB
	output logic [7:0][9:0]  bank_end,      // A29-A20 of the last MB
	output logic [31:0]      picr1
);

// ---- the stored registers: block RAM (zero at load; the ROM writes what it uses first) ----
logic [31:0]     stored;
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
// ... and the ones the machine uses, copied in registers: 80-9C the banks, A0 the enables, A8 PICR1
logic [3:0][7:0] bk [8];
logic [3:0][7:0] r28, r2a;
always_ff @(posedge clk) begin
	if (sel & we)
		for (int k = 0; k < 4; k++)
			if (be[k]) begin
				if (reg_n[7:5] == 3'b100) bk[reg_n[4:2]][k] <= wdata[8 * k +: 8];
				if (reg_n == 6'h28) r28[k] <= wdata[8 * k +: 8];
				if (reg_n == 6'h2A) r2a[k] <= wdata[8 * k +: 8];
			end
	if (reset) begin
		for (int i = 0; i < 8; i++) bk[i] <= '0;
		r28 <= '0; r2a <= '0;
	end
end

// ---- read: the word a cycle after sel (rdata held until the next read) ----------------
logic [7:2] rn_q;
always_ff @(posedge clk) if (sel & ~we) rn_q <= reg_n;
always_comb begin
	case (rn_q)
		6'h00:   rdata = 32'h0001_1057;
		6'h01:   rdata = {16'h0000, stored[15:0]};                  // status: nothing to report
		6'h02:   rdata = 32'h0600_0000;                             // host bridge, revision 0
		6'h30:   rdata = stored & 32'h00FF_00FF;                     // C0-C3: the detection and status bytes 0
		6'h31:   rdata = stored & 32'h00FF_00FF;                     // C4-C7: likewise
		default: rdata = stored;
	endcase
end

// ---- the banks ----------------------------------------------------------------------
always_comb begin
	for (int n = 0; n < 8; n++) begin
		bank_start[n] = {bk[2 + n / 4][n % 4][1:0], bk[n / 4][n % 4]};
		bank_end[n]   = {bk[6 + n / 4][n % 4][1:0], bk[4 + n / 4][n % 4]};
	end
	bank_en = r28[0];
	picr1   = r2a;
end

endmodule
