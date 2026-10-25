//============================================================================
//
//  IBMRS6K7248 - the 8042 keyboard controller, its keyboard and mouse
//
//  The controller at 60 (data) and 64 (status, command), with a PS/2
//  keyboard on its first port and a PS/2 mouse on its second, both made
//  here from the MiSTer's (hps_io's ps2_key and ps2_mouse, toggling once
//  an event, synchronised here).
//
//  The controller: the command byte (20/60), the self and interface tests
//  (AA: 55; AB, A9: 00), enabling and disabling either port (AD/AE,
//  A7/A8), the input and output ports (C0, D0/D1), writing either output
//  buffer (D2/D3), a byte to the mouse (D4), the reset pulse (FE: rst);
//  the set 2 to set 1 translation when the command byte asks (QEMU's
//  table, hw/input/ps2.c); IRQ1 and IRQ12 while the output buffer holds a
//  byte from that port, with a gap of 20 us after each read so the next
//  byte makes a new edge for the 8259.
//
//  The keyboard: reset (FA AA), identify (FA AB 83), enable and disable,
//  the LEDs, the scan set (2, or 3 as AIX selects it; asked, it answers which), the set 3
//  key types (FB/FC/FD and their key lists: all keys stay make/break), typematic, echo, FE for a
//  byte that is not a command;
//  its keys in set 2 (E0 for extended keys, F0 before a release). The
//  mouse: reset (FA AA 00), identify (FA 00), enable and disable
//  streaming, defaults, sample rate, resolution, scaling, status (FA 00 02
//  64), read data; its movement as three-byte packets while streaming.
//
//  The bus: one byte access a cycle (cmd: port 64), the read value in
//  rdata the cycle after sel.
//
//============================================================================

module IBMRS6K7248_kbc
#(
	parameter int unsigned CLK_HZ = 100_000_000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic        cmd,           // port 64 (else 60)
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	output logic        irq1,
	output logic        irq12,
	output logic        rst,           // a pulse: the controller's reset line (command FE)

	input  logic [10:0] ps2_key,       // {toggle, pressed, extended, set 2 code}
	input  logic [24:0] ps2_mouse      // {toggle, Y, X, buttons and signs}
);

function automatic logic [7:0] xlat(input logic [7:0] c);
	case (c)
		8'h00: xlat = 8'hFF;
		8'h01: xlat = 8'h43;
		8'h02: xlat = 8'h41;
		8'h03: xlat = 8'h3F;
		8'h04: xlat = 8'h3D;
		8'h05: xlat = 8'h3B;
		8'h06: xlat = 8'h3C;
		8'h07: xlat = 8'h58;
		8'h08: xlat = 8'h64;
		8'h09: xlat = 8'h44;
		8'h0A: xlat = 8'h42;
		8'h0B: xlat = 8'h40;
		8'h0C: xlat = 8'h3E;
		8'h0D: xlat = 8'h0F;
		8'h0E: xlat = 8'h29;
		8'h0F: xlat = 8'h59;
		8'h10: xlat = 8'h65;
		8'h11: xlat = 8'h38;
		8'h12: xlat = 8'h2A;
		8'h13: xlat = 8'h70;
		8'h14: xlat = 8'h1D;
		8'h15: xlat = 8'h10;
		8'h16: xlat = 8'h02;
		8'h17: xlat = 8'h5A;
		8'h18: xlat = 8'h66;
		8'h19: xlat = 8'h71;
		8'h1A: xlat = 8'h2C;
		8'h1B: xlat = 8'h1F;
		8'h1C: xlat = 8'h1E;
		8'h1D: xlat = 8'h11;
		8'h1E: xlat = 8'h03;
		8'h1F: xlat = 8'h5B;
		8'h20: xlat = 8'h67;
		8'h21: xlat = 8'h2E;
		8'h22: xlat = 8'h2D;
		8'h23: xlat = 8'h20;
		8'h24: xlat = 8'h12;
		8'h25: xlat = 8'h05;
		8'h26: xlat = 8'h04;
		8'h27: xlat = 8'h5C;
		8'h28: xlat = 8'h68;
		8'h29: xlat = 8'h39;
		8'h2A: xlat = 8'h2F;
		8'h2B: xlat = 8'h21;
		8'h2C: xlat = 8'h14;
		8'h2D: xlat = 8'h13;
		8'h2E: xlat = 8'h06;
		8'h2F: xlat = 8'h5D;
		8'h30: xlat = 8'h69;
		8'h32: xlat = 8'h30;
		8'h33: xlat = 8'h23;
		8'h34: xlat = 8'h22;
		8'h35: xlat = 8'h15;
		8'h36: xlat = 8'h07;
		8'h37: xlat = 8'h5E;
		8'h38: xlat = 8'h6A;
		8'h39: xlat = 8'h72;
		8'h3A: xlat = 8'h32;
		8'h3B: xlat = 8'h24;
		8'h3C: xlat = 8'h16;
		8'h3D: xlat = 8'h08;
		8'h3E: xlat = 8'h09;
		8'h3F: xlat = 8'h5F;
		8'h40: xlat = 8'h6B;
		8'h41: xlat = 8'h33;
		8'h42: xlat = 8'h25;
		8'h43: xlat = 8'h17;
		8'h44: xlat = 8'h18;
		8'h45: xlat = 8'h0B;
		8'h46: xlat = 8'h0A;
		8'h47: xlat = 8'h60;
		8'h48: xlat = 8'h6C;
		8'h49: xlat = 8'h34;
		8'h4A: xlat = 8'h35;
		8'h4B: xlat = 8'h26;
		8'h4C: xlat = 8'h27;
		8'h4D: xlat = 8'h19;
		8'h4E: xlat = 8'h0C;
		8'h4F: xlat = 8'h61;
		8'h50: xlat = 8'h6D;
		8'h51: xlat = 8'h73;
		8'h52: xlat = 8'h28;
		8'h53: xlat = 8'h74;
		8'h54: xlat = 8'h1A;
		8'h55: xlat = 8'h0D;
		8'h56: xlat = 8'h62;
		8'h57: xlat = 8'h6E;
		8'h58: xlat = 8'h3A;
		8'h59: xlat = 8'h36;
		8'h5A: xlat = 8'h1C;
		8'h5B: xlat = 8'h1B;
		8'h5C: xlat = 8'h75;
		8'h5D: xlat = 8'h2B;
		8'h5E: xlat = 8'h63;
		8'h5F: xlat = 8'h76;
		8'h60: xlat = 8'h55;
		8'h61: xlat = 8'h56;
		8'h62: xlat = 8'h77;
		8'h63: xlat = 8'h78;
		8'h64: xlat = 8'h79;
		8'h65: xlat = 8'h7A;
		8'h66: xlat = 8'h0E;
		8'h67: xlat = 8'h7B;
		8'h68: xlat = 8'h7C;
		8'h69: xlat = 8'h4F;
		8'h6A: xlat = 8'h7D;
		8'h6B: xlat = 8'h4B;
		8'h6C: xlat = 8'h47;
		8'h6D: xlat = 8'h7E;
		8'h6E: xlat = 8'h7F;
		8'h70: xlat = 8'h52;
		8'h71: xlat = 8'h53;
		8'h72: xlat = 8'h50;
		8'h73: xlat = 8'h4C;
		8'h74: xlat = 8'h4D;
		8'h75: xlat = 8'h48;
		8'h76: xlat = 8'h01;
		8'h77: xlat = 8'h45;
		8'h78: xlat = 8'h57;
		8'h79: xlat = 8'h4E;
		8'h7A: xlat = 8'h51;
		8'h7B: xlat = 8'h4A;
		8'h7C: xlat = 8'h37;
		8'h7D: xlat = 8'h49;
		8'h7E: xlat = 8'h46;
		8'h7F: xlat = 8'h54;
		8'h83: xlat = 8'h41;
		8'h84: xlat = 8'h54;
		default: xlat = c;
	endcase
endfunction

// a key's scan set 3 code from the Main's set 2 code (e: E0-extended in set 2); 00 for keys set 3 has
// no code for here. Set 3 is the IBM terminal set AIX selects (F0 03); its letters, digits, Enter, Space,
// Backspace, Tab, the shifts and most of the keypad keep their set 2 codes
function automatic logic [7:0] set3(input logic e, input logic [7:0] c);
	if (e) case (c)
		8'h11: set3 = 8'h39;    // right Alt
		8'h14: set3 = 8'h58;    // right Ctrl
		8'h70: set3 = 8'h67;    // Insert
		8'h6C: set3 = 8'h6E;    // Home
		8'h7D: set3 = 8'h6F;    // Page Up
		8'h71: set3 = 8'h64;    // Delete
		8'h69: set3 = 8'h65;    // End
		8'h7A: set3 = 8'h6D;    // Page Down
		8'h75: set3 = 8'h63;    // Up
		8'h6B: set3 = 8'h61;    // Left
		8'h72: set3 = 8'h60;    // Down
		8'h74: set3 = 8'h6A;    // Right
		8'h4A: set3 = 8'h77;    // keypad /
		8'h5A: set3 = 8'h79;    // keypad Enter
		8'h7C: set3 = 8'h57;    // Print Screen
		8'h1F: set3 = 8'h8B;    // left Windows
		8'h27: set3 = 8'h8C;    // right Windows
		8'h2F: set3 = 8'h8D;    // Menu
		default: set3 = 8'h00;
	endcase
	else case (c)
		8'h76: set3 = 8'h08;    // Esc
		8'h05: set3 = 8'h07;    // F1
		8'h06: set3 = 8'h0F;    // F2
		8'h04: set3 = 8'h17;    // F3
		8'h0C: set3 = 8'h1F;    // F4
		8'h03: set3 = 8'h27;    // F5
		8'h0B: set3 = 8'h2F;    // F6
		8'h83: set3 = 8'h37;    // F7
		8'h0A: set3 = 8'h3F;    // F8
		8'h01: set3 = 8'h47;    // F9
		8'h09: set3 = 8'h4F;    // F10
		8'h78: set3 = 8'h56;    // F11
		8'h07: set3 = 8'h5E;    // F12
		8'h7E: set3 = 8'h5F;    // Scroll Lock
		8'h14: set3 = 8'h11;    // left Ctrl
		8'h11: set3 = 8'h19;    // left Alt
		8'h58: set3 = 8'h14;    // Caps Lock
		8'h5D: set3 = 8'h5C;    // backslash
		8'h61: set3 = 8'h13;    // the 102nd key (< >)
		8'h77: set3 = 8'h76;    // Num Lock
		8'h7C: set3 = 8'h7E;    // keypad *
		8'h7B: set3 = 8'h84;    // keypad -
		8'h79: set3 = 8'h7C;    // keypad +
		default: set3 = c;
	endcase
endfunction

// a byte the keyboard takes as a command: ED, EE, F0, F2-FF (anything else is answered FE)
function automatic logic k_cmd(input logic [7:0] b);
	return b == 8'hED || b == 8'hEE || b == 8'hF0 || b >= 8'hF2;
endfunction

// ---- queues: the controller's answers first, then the keyboard's, then the mouse's -------
localparam int QN = 16;
logic [7:0] kq [QN], mq [QN];
logic [3:0] kq_r, kq_w, mq_r, mq_w;
logic [4:0] kq_n, mq_n;
logic [2:0] kp_n, mp_n;                 // the pushes registered (below)
logic [7:0] kp [4], mp [4];
logic [7:0] ks [8], ms [8];             // ... and staged for the queues
logic [3:0] ks_n, ms_n;

logic [7:0] obuf;
logic       obf, ob_aux;
logic [7:0] cbyte;                      // the command byte
logic       a2;                         // the last write was to 64
logic [7:0] pend;                       // a command waiting for its data byte (0 none)
logic [7:0] outport;
localparam int GAP = CLK_HZ / 50_000;   // 20 us
logic [15:0] gap;

// keyboard device
logic       k_on;                       // scanning
logic [7:0] k_wait;                     // a command waiting for its parameter (0 none)
logic       k_rel;                      // translation: the next code is a release
logic       k_set3;                     // scan set 3 selected (F0 03; else set 2)
logic       k_list;                     // after FB/FC/FD: key codes follow until the next command
// mouse device
logic       m_on;
logic [7:0] m_wait;
logic [7:0] m_rate, m_res;
logic       m_scale;

// the events from hps_io
logic [2:0] kt, mt;
always_ff @(posedge clk) begin
	kt <= {kt[1:0], ps2_key[10]};
	mt <= {mt[1:0], ps2_mouse[24]};
end
wire key_ev   = kt[2] != kt[1];
wire mouse_ev = mt[2] != mt[1];

// queue pushes: up to four bytes for one queue in a cycle, from these (registered, then fed into the
// queue a byte a clock through a small stage: the queues are single-port RAMs)
logic [2:0] kpush_n, mpush_n;
logic [7:0] kpush [4], mpush [4];

always_comb begin
	kpush_n = 3'd0; kpush[0] = 8'h00; kpush[1] = 8'h00; kpush[2] = 8'h00; kpush[3] = 8'h00;
	mpush_n = 3'd0; mpush[0] = 8'h00; mpush[1] = 8'h00; mpush[2] = 8'h00; mpush[3] = 8'h00;
	// the keyboard's answer to a byte written to 60 (no controller command pending)
	if (sel & we & ~cmd & pend == 8'h00) begin
		// the scan set, asked (F0 00): the keyboard answers its set (2 or 3) after its FA
		if (k_wait == 8'hF0 && wdata == 8'h00) begin kpush_n = 3'd2; kpush[0] = 8'hFA; kpush[1] = k_set3 ? 8'h03 : 8'h02; end
		else if (k_wait != 8'h00) begin kpush_n = 3'd1; kpush[0] = 8'hFA; end
		else if (k_list && !k_cmd(wdata)) begin kpush_n = 3'd1; kpush[0] = 8'hFA; end   // a key code after FB/FC/FD
		else case (wdata)
			8'hFF:   begin kpush_n = 3'd2; kpush[0] = 8'hFA; kpush[1] = 8'hAA; end
			8'hF2:   begin kpush_n = 3'd3; kpush[0] = 8'hFA; kpush[1] = 8'hAB; kpush[2] = cbyte[6] ? 8'h41 : 8'h83; end
			8'hEE:   begin kpush_n = 3'd1; kpush[0] = 8'hEE; end
			// the other commands are ED, F0 and F2-FF (acknowledged); anything else is not a command and
			// a real keyboard asks for it again (FE, Resend): AIX's keyboard probe sends EF after its reset and
			// gives up on the keyboard (command byte 30) when it is acknowledged
			default: begin kpush_n = 3'd1; kpush[0] = k_cmd(wdata) ? 8'hFA : 8'hFE; end
		endcase
	end
	// a key
	else if (key_ev && k_on && kq_n + 5'(ks_n) <= 5'(QN - 3)) begin
		if (k_set3 && !cbyte[6]) begin
			// set 3 (AIX): the code, F0 before it for a release; keys without a set 3 code are dropped
			logic [7:0] c3;
			c3 = set3(ps2_key[8], ps2_key[7:0]);
			if (c3 != 8'h00) begin
				if (ps2_key[9]) begin kpush_n = 3'd1; kpush[0] = c3; end
				else            begin kpush_n = 3'd2; kpush[0] = 8'hF0; kpush[1] = c3; end
			end
		end
		else if (cbyte[6]) begin
			// translated: E0, then the code with bit 7 for a release
			if (ps2_key[8]) begin kpush_n = 3'd2; kpush[0] = 8'hE0; kpush[1] = xlat(ps2_key[7:0]) | {~ps2_key[9], 7'd0}; end
			else            begin kpush_n = 3'd1; kpush[0] = xlat(ps2_key[7:0]) | {~ps2_key[9], 7'd0}; end
		end
		else begin
			case ({ps2_key[8], ps2_key[9]})
				2'b01: begin kpush_n = 3'd1; kpush[0] = ps2_key[7:0]; end
				2'b00: begin kpush_n = 3'd2; kpush[0] = 8'hF0; kpush[1] = ps2_key[7:0]; end
				2'b11: begin kpush_n = 3'd2; kpush[0] = 8'hE0; kpush[1] = ps2_key[7:0]; end
				2'b10: begin kpush_n = 3'd3; kpush[0] = 8'hE0; kpush[1] = 8'hF0; kpush[2] = ps2_key[7:0]; end
			endcase
		end
	end

	// the mouse's answer to a byte sent with D4
	if (sel & we & ~cmd & pend == 8'hD4) begin
		if (m_wait != 8'h00) begin mpush_n = 3'd1; mpush[0] = 8'hFA; end
		else case (wdata)
			8'hFF:   begin mpush_n = 3'd3; mpush[0] = 8'hFA; mpush[1] = 8'hAA; mpush[2] = 8'h00; end
			8'hF2:   begin mpush_n = 3'd2; mpush[0] = 8'hFA; mpush[1] = 8'h00; end
			// the status bytes after E9's FA, a packet after EB's
			8'hE9:   begin mpush_n = 3'd4; mpush[0] = 8'hFA; mpush[1] = {1'b0, ~m_on, m_on, m_scale, 4'h0};
			               mpush[2] = m_res; mpush[3] = m_rate; end
			8'hEB:   begin mpush_n = 3'd4; mpush[0] = 8'hFA; mpush[1] = 8'h08; mpush[2] = 8'h00; mpush[3] = 8'h00; end
			default: begin mpush_n = 3'd1; mpush[0] = 8'hFA; end
		endcase
	end
	else if (mouse_ev && m_on && mq_n + 5'(ms_n) <= 5'(QN - 3)) begin
		mpush_n = 3'd3;
		mpush[0] = ps2_mouse[7:0] | 8'h08;
		mpush[1] = ps2_mouse[15:8];
		mpush[2] = ps2_mouse[23:16];
	end
end

// the controller's own answers go straight into the output buffer (it is free:
// software reads it before issuing a command that answers)
logic       c_put;
logic [7:0] c_byte;
always_comb begin
	c_put = 1'b0; c_byte = 8'h00;
	if (sel & we & cmd) begin
		case (wdata)
			8'h20:   begin c_put = 1'b1; c_byte = cbyte; end
			8'hA9:   begin c_put = 1'b1; c_byte = 8'h00; end
			8'hAA:   begin c_put = 1'b1; c_byte = 8'h55; end
			8'hAB:   begin c_put = 1'b1; c_byte = 8'h00; end
			8'hA4:   begin c_put = 1'b1; c_byte = 8'hF1; end        // no password installed
			8'hC0:   begin c_put = 1'b1; c_byte = 8'hBF; end        // the input port: not inhibited
			8'hD0:   begin c_put = 1'b1; c_byte = outport; end
			8'hE0:   begin c_put = 1'b1; c_byte = 8'h00; end
			default: if (wdata[7:5] == 3'b001) begin c_put = 1'b1; c_byte = 8'h00; end   // 21-3F: the controller's RAM
		endcase
	end
end

// the pushes registered, then staged (up to 8 bytes a queue) and written a byte a clock
wire        k_pop = ks_n != 4'd0;
wire        m_pop = ms_n != 4'd0;
wire  [3:0] ks_b  = ks_n - {3'd0, k_pop};       // where the new bytes go, after this clock's pop
wire  [3:0] ms_b  = ms_n - {3'd0, m_pop};
always_ff @(posedge clk) begin
	kp_n <= kpush_n; mp_n <= mpush_n;
	for (int i = 0; i < 4; i++) begin kp[i] <= kpush[i]; mp[i] <= mpush[i]; end
	for (int i = 0; i < 8; i++) begin
		ks[i] <= k_pop ? (i < 7 ? ks[i + 1] : 8'h00) : ks[i];
		ms[i] <= m_pop ? (i < 7 ? ms[i + 1] : 8'h00) : ms[i];
	end
	for (int j = 0; j < 4; j++) begin
		if (3'(j) < kp_n) ks[3'(ks_b + 4'(j))] <= kp[j];
		if (3'(j) < mp_n) ms[3'(ms_b + 4'(j))] <= mp[j];
	end
	ks_n <= ks_b + {1'b0, kp_n};
	ms_n <= ms_b + {1'b0, mp_n};
	if (reset) begin kp_n <= 3'd0; mp_n <= 3'd0; ks_n <= 4'd0; ms_n <= 4'd0; end
end
// the queues: one write a clock (the stage's first byte), one read
always_ff @(posedge clk) begin
	if (k_pop) kq[kq_w] <= ks[0];
	if (m_pop) mq[mq_w] <= ms[0];
end

always_ff @(posedge clk) begin
	rst <= 1'b0;

	// queues in
	if (k_pop) kq_w <= kq_w + 4'd1;
	if (m_pop) mq_w <= mq_w + 4'd1;

	// the output buffer: a controller answer at once; else the next queued byte after the gap
	if (gap != 16'd0) gap <= gap - 16'd1;
	if (c_put) begin
		obuf <= c_byte; obf <= 1'b1; ob_aux <= 1'b0;
	end
	else if (!obf && gap == 16'd0) begin
		if (kq_n != 5'd0 && !cbyte[4]) begin
			obuf <= kq[kq_r]; obf <= 1'b1; ob_aux <= 1'b0; kq_r <= kq_r + 4'd1;
		end
		else if (mq_n != 5'd0 && !cbyte[5]) begin
			obuf <= mq[mq_r]; obf <= 1'b1; ob_aux <= 1'b1; mq_r <= mq_r + 4'd1;
		end
	end

	if (sel) begin
		if (we) begin
			a2 <= cmd;
			if (cmd) begin
				pend <= 8'h00;
				case (wdata)
					8'h60, 8'hD1, 8'hD2, 8'hD3, 8'hD4: pend <= wdata;
					8'hA7: cbyte[5] <= 1'b1;
					8'hA8: cbyte[5] <= 1'b0;
					8'hAA: cbyte[2] <= 1'b1;                // the self test passed: the system flag
					8'hAD: cbyte[4] <= 1'b1;
					8'hAE: cbyte[4] <= 1'b0;
					default: if (wdata[7:4] == 4'hF && !wdata[0]) rst <= 1'b1;   // F0-FF: bit 0 low pulses the reset line
				endcase
			end
			else begin
				pend <= 8'h00;
				case (pend)
					8'h60: cbyte <= wdata;
					8'hD1: outport <= wdata;
					8'hD2: begin obuf <= wdata; obf <= 1'b1; ob_aux <= 1'b0; end
					8'hD3: begin obuf <= wdata; obf <= 1'b1; ob_aux <= 1'b1; end
					8'hD4: begin
						cbyte[5] <= 1'b0;                   // writing to the mouse enables its port
						if (m_wait != 8'h00) begin
							if (m_wait == 8'hF3) m_rate <= wdata;
							if (m_wait == 8'hE8) m_res  <= wdata;
							m_wait <= 8'h00;
						end
						else case (wdata)
							8'hF3, 8'hE8: m_wait <= wdata;
							8'hF4: m_on <= 1'b1;
							8'hF5: m_on <= 1'b0;
							8'hF6, 8'hFF: begin m_on <= 1'b0; m_rate <= 8'd100; m_res <= 8'd2; m_scale <= 1'b0; end
							8'hE6: m_scale <= 1'b0;
							8'hE7: m_scale <= 1'b1;
							default: ;
						endcase
					end
					default: begin                          // to the keyboard
						cbyte[4] <= 1'b0;
						if (k_wait != 8'h00) begin
							// the scan set: 1-3 select (set 1 is taken as 2), 0 asks (answered below)
							if (k_wait == 8'hF0 && wdata != 8'h00) k_set3 <= wdata == 8'h03;
							k_wait <= 8'h00;
						end
						else if (k_list && !k_cmd(wdata)) ;      // a key code after FB/FC/FD: all keys stay make/break
						else begin
							k_list <= wdata == 8'hFB || wdata == 8'hFC || wdata == 8'hFD;
							case (wdata)
								8'hED, 8'hF0, 8'hF3: k_wait <= wdata;
								8'hF4: k_on <= 1'b1;
								8'hF5: k_on <= 1'b0;
								8'hF6: k_on <= 1'b1;
								8'hFF: begin k_on <= 1'b1; k_set3 <= 1'b0; end     // the reset: set 2 again
								default: ;
							endcase
						end
					end
				endcase
			end
		end
		else begin
			if (cmd) rdata <= {1'b0, 1'b0, ob_aux & obf, 1'b1, a2, cbyte[2], 1'b0, obf};
			else begin
				rdata <= obuf;
				if (obf) gap <= 16'(GAP);
				obf <= 1'b0;
			end
		end
	end


	if (reset) begin
		kq_r <= '0; kq_w <= '0; mq_r <= '0; mq_w <= '0;
		obf <= 1'b0; ob_aux <= 1'b0; cbyte <= 8'h00; a2 <= 1'b0; pend <= 8'h00; outport <= 8'hCF;
		gap <= '0; k_on <= 1'b1; k_wait <= 8'h00; k_set3 <= 1'b0; k_list <= 1'b0; m_on <= 1'b0; m_wait <= 8'h00;
		m_rate <= 8'd100; m_res <= 8'd2; m_scale <= 1'b0;
	end
end

assign kq_n = 5'(kq_w - kq_r);
assign mq_n = 5'(mq_w - mq_r);

assign irq1  = obf & ~ob_aux & cbyte[0];
assign irq12 = obf &  ob_aux & cbyte[1];

endmodule
