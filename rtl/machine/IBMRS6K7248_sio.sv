//============================================================================
//
//  IBMRS6K7248 - the National PC87312's configuration, and its parallel port
//
//  The Super I/O's three configuration registers behind its index (398)
//  and data (399) ports, as QEMU's PC87312 (hw/isa/pc87312.c) and the
//  firmware (PC87312Init, ReadPC87312Regs, WritePC87312Regs) use them:
//    FER (0)  function enable: parallel, UART 1, UART 2, FDC, FDC at 370,
//             IDE, IDE at 170
//    FAR (1)  function address: the parallel port (378, 3BC, 278), UART 1
//             and UART 2 (3F8, 2F8, or COM3/COM4 by FAR[7:6])
//    PTR (2)  power and test
//  The first read of the index after reset returns the chip's ID, 88; the
//  next 00; then the index. (The firmware writes each data byte twice, as
//  the chip asks; any write takes here.) The registers come out of reset as
//  QEMU's configuration 12 has them (FER 0F, FAR 10, PTR 00); the firmware
//  sets its own.
//
//  The parallel port is here too, as far as the firmware uses it: its data
//  latch (the firmware's progress codes go there) read back, a status of
//  "not busy, selected, no error" (DF), the control register stored.
//
//  The bus: one byte access a cycle, the read value in rdata the cycle
//  after sel.
//
//============================================================================

module IBMRS6K7248_sio
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,           // the configuration ports
	input  logic        lpt_sel,       // the parallel port's three registers
	input  logic        we,
	input  logic [1:0]  off,           // 398/399: off[0]; the parallel port: 0 data, 1 status, 2 control
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	// the functions as configured
	output logic        lpt_on,
	output logic [15:2] lpt_base,
	output logic        uart1_on,
	output logic [15:3] uart1_base,
	output logic        uart2_on,
	output logic [15:3] uart2_base,
	output logic        fdc_on,
	output logic        fdc_alt,       // the FDC at 370 (else 3F0)
	output logic        ide_on,
	output logic        ide_alt        // the IDE at 170 (else 1F0)
);

logic [7:0] fer, far_r, ptr;
logic [1:0] index;
logic [7:0] index_raw;
logic [1:0] id_step;
logic [7:0] lpt_data, lpt_ctl;

always_ff @(posedge clk) begin
	if (sel) begin
		if (we) begin
			if (!off[0]) begin index_raw <= wdata; index <= wdata[1:0]; id_step <= 2'd2; end
			else if (index_raw < 8'd3) case (index)
				2'd0:    fer   <= wdata;
				2'd1:    far_r <= wdata;
				default: ptr   <= wdata;
			endcase
		end
		else if (!off[0]) begin
			rdata   <= id_step == 2'd0 ? 8'h88 : id_step == 2'd1 ? 8'h00 : index_raw;
			if (id_step != 2'd2) id_step <= id_step + 2'd1;
		end
		else rdata <= index_raw >= 8'd3 ? 8'h00 : index == 2'd0 ? fer : index == 2'd1 ? far_r : ptr;
	end
	if (lpt_sel) begin
		if (we) begin
			if (off == 2'd0) lpt_data <= wdata;
			if (off == 2'd2) lpt_ctl  <= wdata;
		end
		else rdata <= off == 2'd0 ? lpt_data : off == 2'd1 ? 8'hDF : lpt_ctl;
	end
	if (reset) begin
		fer <= 8'h0F; far_r <= 8'h10; ptr <= 8'h00;
		index <= 2'd0; index_raw <= 8'h00; id_step <= 2'd0;
		lpt_ctl <= 8'h0C;
	end
end

// the addresses
function automatic logic [15:3] uart_at(input logic [1:0] which, input logic [1:0] com34);
	case (which)
		2'd0:    uart_at = 13'h007F;                                   // 3F8
		2'd1:    uart_at = 13'h005F;                                   // 2F8
		2'd2:    case (com34)                                          // COM3
			2'd0: uart_at = 13'h007D; 2'd1: uart_at = 13'h0067; 2'd2: uart_at = 13'h005D; default: uart_at = 13'h0044;
		endcase
		default: case (com34)                                          // COM4
			2'd0: uart_at = 13'h005D; 2'd1: uart_at = 13'h0047; 2'd2: uart_at = 13'h005C; default: uart_at = 13'h0045;
		endcase
	endcase
endfunction

assign lpt_on     = fer[0];
assign lpt_base   = far_r[1:0] == 2'd0 ? 14'h00DE : far_r[1:0] == 2'd1 ? 14'h00EF : 14'h009E;   // 378, 3BC, 278
assign uart1_on   = fer[1];
assign uart1_base = uart_at(far_r[3:2], far_r[7:6]);
assign uart2_on   = fer[2];
assign uart2_base = uart_at(far_r[5:4], far_r[7:6]);
assign fdc_on     = fer[3];
assign fdc_alt    = fer[5];
assign ide_on     = fer[6];
assign ide_alt    = fer[7];

endmodule
