//============================================================================
//
//  IBMRS6K7248 - the Crystal CS4232 audio controller, first form: present
//
//  Enough of the chip for the firmware to find it and set it up as on a
//  real board (audio_mute, FFF0D9A4: the Crystal key and configuration at
//  0279, then the Sound Blaster DSP's write status at 022C, then the
//  Windows Sound System codec at 0534/0535). No sound yet (plan M7).
//
//    0226       DSP reset: writing 1 then 0 queues the DSP's AA
//    022A       DSP read data: AA after a reset, else 00
//    022C       DSP write status: ready (bit 7 clear)
//    022E       DSP read status: bit 7 while a byte waits at 022A
//    0534       WSS index (bit 7, INIT, reads clear: the codec is ready;
//               bit 6, MCE, kept)
//    0535       WSS indexed data: 32 registers, stored and read back
//    0536       WSS status: 00
//
//  The bus: one byte access a cycle by port offset, the read value in
//  rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_cs4232
(
	input  logic       clk,
	input  logic       reset,

	input  logic       sel,
	input  logic       we,
	input  logic       wss,            // 0534-0537 (else 0220-022F)
	input  logic [3:0] off,
	input  logic [7:0] wdata,
	output logic [7:0] rdata
);

logic       dsp_rst, dsp_avail;
logic [6:0] widx;
logic [7:0] wreg [32];

always_ff @(posedge clk) begin
	if (sel) begin
		if (wss) begin
			if (we) begin
				if (off[1:0] == 2'd0) widx <= wdata[6:0];
				if (off[1:0] == 2'd1) wreg[widx[4:0]] <= wdata;
			end
			else case (off[1:0])
				2'd0:    rdata <= {1'b0, widx};
				2'd1:    rdata <= wreg[widx[4:0]];
				default: rdata <= 8'h00;
			endcase
		end
		else begin
			if (we) begin
				if (off == 4'h6) begin
					if (wdata[0]) dsp_rst <= 1'b1;
					else if (dsp_rst) begin dsp_rst <= 1'b0; dsp_avail <= 1'b1; end
				end
			end
			else case (off)
				4'hA: begin rdata <= dsp_avail ? 8'hAA : 8'h00; dsp_avail <= 1'b0; end
				4'hC: rdata <= 8'h00;
				4'hE: rdata <= {dsp_avail, 7'h7F};
				default: rdata <= 8'hFF;
			endcase
		end
	end
	if (reset) begin
		dsp_rst <= 1'b0; dsp_avail <= 1'b0; widx <= 7'h00;
	end
end

endmodule
