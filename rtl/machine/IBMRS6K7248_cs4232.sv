//============================================================================
//
//  IBMRS6K7248 - the Crystal CS4232 audio controller, first form: present
//
//  Enough of the chip for the firmware to find it, configure it and move it
//  as a real board's (audio_mute, FFF0D9A4; init_4232, SendKey,
//  ConfigDevice, configByDefault). No sound yet (plan M7).
//
//  Configuration, at 0279 (write only): two zeros, then the 32-byte
//  Crystal key (96 35 9A CD ... 1A, as the firmware sends it: the first 96
//  after a 00 is taken as its start), then commands until 79:
//    15 n      select logical device n
//    47 hi lo  its I/O base 0 (device 0: the WSS codec, 534)
//    48 hi lo  its I/O base 1 (device 0: the FM synthesiser, 388)
//    42 hi lo  its I/O base 2 (device 0: the Sound Blaster, 220)
//    22 n, 27 n, 2A n, 25 n   interrupt and DMA settings (taken, unused)
//    33 n      activate (1) or deactivate (0)
//    79        leave configuration
//  Only logical device 0 is modelled. It is inactive at reset (the chip
//  with no EEPROM), so its ports float until the firmware places it; the
//  firmware checks that the Sound Blaster appears when activated and
//  disappears when deactivated (init_4232).
//
//  Device 0's ports while active:
//    base 2 + 6   DSP reset: writing 1 then 0 queues the DSP's AA
//    base 2 + A   DSP read data: AA after a reset, else 00
//    base 2 + C   DSP write status: ready (bit 7 clear)
//    base 2 + E   DSP read status: bit 7 while a byte waits at + A
//    base 0       WSS index (bit 7, INIT, reads clear: the codec is ready)
//    base 0 + 1   WSS indexed data: 32 registers, stored and read back
//    base 0 + 2   WSS status: 00
//
//  The bus: the machine decodes 0279 and the two windows from the bases
//  brought out here; one byte access a cycle, the read value in rdata the
//  cycle after sel.
//
//============================================================================

module IBMRS6K7248_cs4232
(
	input  logic        clk,
	input  logic        reset,

	input  logic        cfg_sel,       // a write to 0279
	input  logic        sel,           // an access to one of device 0's windows
	input  logic        we,
	input  logic        wss,           // ... the WSS codec's (else the Sound Blaster's)
	input  logic [3:0]  off,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	output logic        on,            // device 0 active
	output logic [15:4] sb_base,
	output logic [15:2] wss_base
);

// ---- configuration ----------------------------------------------------------------------
logic [7:0]  prev;
logic [5:0]  keyn;                       // key bytes still to come
logic        cfg;                        // in configuration
logic [7:0]  cmd;
logic [1:0]  argn;                       // arguments still to come
logic [7:0]  arg_hi;
logic [7:0]  ld;
logic [15:0] base0, base2;

always_ff @(posedge clk) begin
	if (cfg_sel) begin
		prev <= wdata;
		if (keyn != 6'd0) begin
			keyn <= keyn - 6'd1;
			if (keyn == 6'd1) cfg <= 1'b1;
		end
		else if (!cfg) begin
			if (prev == 8'h00 && wdata == 8'h96) keyn <= 6'd31;
		end
		else if (argn != 2'd0) begin
			argn <= argn - 2'd1;
			if (argn == 2'd2) arg_hi <= wdata;
			else case (cmd)
				8'h15: ld <= wdata;
				8'h47: if (ld == 8'd0) base0 <= {arg_hi, wdata};
				8'h42: if (ld == 8'd0) base2 <= {arg_hi, wdata};
				8'h33: if (ld == 8'd0) on <= wdata[0];
				default: ;
			endcase
		end
		else begin
			cmd <= wdata;
			case (wdata)
				8'h79:                      cfg  <= 1'b0;
				8'h47, 8'h48, 8'h42:        argn <= 2'd2;
				default:                    argn <= 2'd1;
			endcase
		end
	end
	if (reset) begin
		prev <= 8'hFF; keyn <= 6'd0; cfg <= 1'b0; argn <= 2'd0; ld <= 8'd0;
		on <= 1'b0; base0 <= 16'h0534; base2 <= 16'h0220;
	end
end

assign sb_base  = base2[15:4];
assign wss_base = base0[15:2];

// ---- device 0's ports -------------------------------------------------------------------
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
