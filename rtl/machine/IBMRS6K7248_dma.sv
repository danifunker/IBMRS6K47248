//============================================================================
//
//  IBMRS6K7248 - the ISA DMA controller: Fire Coral's two 8237s with the
//  82378's extensions
//
//  DMA1 at 00-0F (channels 0-3, 8-bit), DMA2 at C0-DF (channels 4-7, even
//  ports; 4 the cascade, 5-7 16-bit): each channel's base and current
//  address and count (low byte then high, through the byte pointer flip-
//  flop), the command, request, single and all mask, mode and status
//  registers, clear byte pointer, master clear, clear mask. The page
//  registers at 80-8F (87 0, 83 1, 81 2, 82 3, 8B 5, 89 6, 8A 7; the rest
//  scratch), the 82378's high pages at 481-48B (the address's bits 31:24:
//  the PCI address the transfer goes to, 8000_0000 + n for memory n), its
//  extended mode registers 40B / 4D6 (kept), and its scatter/gather: for
//  each channel a command at 410 + n (bits 1:0: 01 start, 10 stop), a
//  status at 418 + n (bit 3 active, bit 2 ended at a list's end), a table
//  pointer at 420 + 4n (little-endian), 40A / 4D4 the channels whose list
//  ended (read: cleared). A started channel takes its address and count
//  from the table's 8-byte entries (the PCI address; bits 23:0 the count
//  less 1, bit 31 the list's last), the next entry when one runs out; at
//  the last one's end it masks itself and raises IRQ 13 (sg_irq). The
//  firmware's startup tune is played so (audio_play: channel 1, the table
//  at 424).
//
//  A transfer: a channel unmasked, its DREQ high, not in cascade mode, is
//  served (the lowest number first): one byte (channels 0-3) or one word
//  (5-7, at {page[7:1], address, 0}) between memory, over the DMA port (as
//  the PCI masters', one doubleword a request), and the device, which sees
//  dack with the channel (a read transfer: dack_data the byte or word
//  memory gave; a write transfer: it gives dev_data) and tc on the last.
//  Then the address steps, the count steps down; past 0, TC: the status
//  bit, and the channel reloads (auto-initialise) or masks itself. Single,
//  demand and block modes alike: one transfer each time the request is
//  seen. Verify transfers count with no memory access.
//
//  The bus: one byte access a cycle by port, the read value in rdata the
//  cycle after sel.
//
//============================================================================

module IBMRS6K7248_dma
(
	input  logic        clk,
	input  logic        reset,

	input  logic        sel,
	input  logic        we,
	input  logic [15:0] port,
	input  logic [7:0]  wdata,
	output logic [7:0]  rdata,

	// the devices
	input  logic [7:0]  dreq,
	output logic        dack,           // a pulse: the channel's transfer is done
	output logic [2:0]  dack_ch,
	output logic [15:0] dack_data,      // a read transfer's byte (7:0) or word, from memory
	input  logic [15:0] dev_data,       // a write transfer's, from the device (dev_ch's)
	output logic [2:0]  dev_ch,         // the channel being served
	output logic        tc,             // with dack: the count ran out
	output logic        sg_irq,         // a scatter/gather list ended (IRQ 13)

	// DMA: one doubleword, held until dm_ack
	output logic        dm_req,
	output logic        dm_we,
	output logic [31:3] dm_addr,
	output logic [7:0]  dm_be,
	output logic [63:0] dm_wdata,
	input  logic        dm_ack,
	input  logic        dm_err,
	input  logic [63:0] dm_rdata
);

// ---- registers ----------------------------------------------------------------------------
logic [15:0] base_a [8], cur_a [8], base_c [8], cur_c [8];
logic [7:0]  page [8], hpage [8];
logic [5:0]  mode [8];                  // the mode register's bits 7:2
logic [7:0]  mask;                      // 1: masked
logic [7:0]  req_sw;                    // software requests
logic [7:0]  tc_st;                     // the status's TC bits (read clears)
logic [7:0]  cmd1, cmd2;
logic        ff1, ff2;                  // the byte pointers
logic [7:0]  ext1, ext2;                // the extended mode registers (40B, 4D6)
logic [7:0]  sg [48];                   // 410-43F
logic [7:0]  scratch [16];              // 80-8F
logic [7:0]  temp;                      // the last byte read (the temporary register)
// the engine's (below): the channel served, its step or its TC
logic [2:0]  ch;
assign dev_ch = ch;
logic        go_step, go_tc;
// scatter/gather: each channel's list running, its entry (address, count left, the last), loading, ended
logic [7:0]  sg_on, sg_load, sg_end, sg_int;
logic [31:0] sg_a [8];
logic [23:0] sg_c [8];
logic [7:0]  sg_last;
logic [31:0] sg_ptr [8];                // the next entry's address
logic        sg_go_step, sg_go_next, sg_go_end;   // the engine's (below)
logic        sg_loaded;
logic [31:0] sg_new_a, sg_new_c;
assign sg_irq = |sg_int;

// the page register port of each channel (80-8F), and back
function automatic logic [3:0] page_port(input logic [2:0] c);
	case (c)
		3'd0: page_port = 4'h7;  3'd1: page_port = 4'h3;  3'd2: page_port = 4'h1;  3'd3: page_port = 4'h2;
		3'd4: page_port = 4'hF;  3'd5: page_port = 4'hB;  3'd6: page_port = 4'h9;  default: page_port = 4'hA;
	endcase
endfunction
function automatic logic [3:0] port_ch(input logic [3:0] p);    // bit 3: a channel's
	case (p)
		4'h7: port_ch = 4'b1000;  4'h3: port_ch = 4'b1001;  4'h1: port_ch = 4'b1010;  4'h2: port_ch = 4'b1011;
		4'hF: port_ch = 4'b1100;  4'hB: port_ch = 4'b1101;  4'h9: port_ch = 4'b1110;  4'hA: port_ch = 4'b1111;
		default: port_ch = 4'b0000;
	endcase
endfunction

// the decode
wire        d1      = port[15:4] == 12'h000;                               // 00-0F
wire        d2      = port[15:5] == 11'h006 && !port[0];                   // C0-DF, even
wire [3:0]  d2r     = port[4:1];                                           // DMA2's register (as DMA1's)
wire        pg      = port[15:4] == 12'h008;                               // 80-8F
wire        hpg     = port[15:4] == 12'h048;                               // 480-48F
wire        sg_p    = port >= 16'h0410 && port <= 16'h043F;
wire [3:0]  pch     = port_ch(port[3:0]);
// a register access: the controller (0 or 1) and its register number (0-15)
wire        ctl     = d2;
wire [3:0]  rn      = d2 ? d2r : port[3:0];
wire [2:0]  rch     = {ctl, rn[2:1]};                                      // a channel's address or count

always_ff @(posedge clk) begin
	if (sel) begin
		if (we) begin
			if (d1 || d2) begin
				if (rn < 4'd8) begin
					// a channel's address (even) or count (odd), low byte then high; base and current
					if (!rn[0]) begin
						if (!(ctl ? ff2 : ff1)) begin base_a[rch][7:0]  <= wdata; cur_a[rch][7:0]  <= wdata; end
						else                    begin base_a[rch][15:8] <= wdata; cur_a[rch][15:8] <= wdata; end
					end
					else begin
						if (!(ctl ? ff2 : ff1)) begin base_c[rch][7:0]  <= wdata; cur_c[rch][7:0]  <= wdata; end
						else                    begin base_c[rch][15:8] <= wdata; cur_c[rch][15:8] <= wdata; end
					end
					if (ctl) ff2 <= ~ff2; else ff1 <= ~ff1;
				end
				else case (rn)
					4'h8: if (ctl) cmd2 <= wdata; else cmd1 <= wdata;
					4'h9: req_sw[{ctl, wdata[1:0]}] <= wdata[2];
					4'hA: mask[{ctl, wdata[1:0]}] <= wdata[2];
					4'hB: mode[{ctl, wdata[1:0]}] <= wdata[7:2];
					4'hC: if (ctl) ff2 <= 1'b0; else ff1 <= 1'b0;
					4'hD: begin                                    // master clear
						if (ctl) begin cmd2 <= 8'h0; ff2 <= 1'b0; mask[7:4] <= 4'hF; tc_st[7:4] <= 4'h0; req_sw[7:4] <= 4'h0; end
						else     begin cmd1 <= 8'h0; ff1 <= 1'b0; mask[3:0] <= 4'hF; tc_st[3:0] <= 4'h0; req_sw[3:0] <= 4'h0; end
					end
					4'hE: if (ctl) mask[7:4] <= 4'h0; else mask[3:0] <= 4'h0;
					4'hF: if (ctl) mask[7:4] <= wdata[3:0]; else mask[3:0] <= wdata[3:0];
					default: ;
				endcase
			end
			else if (pg) begin
				if (pch[3]) page[pch[2:0]] <= wdata;
				else scratch[port[3:0]] <= wdata;
			end
			else if (hpg) begin
				if (pch[3]) hpage[pch[2:0]] <= wdata;
			end
			else if (port == 16'h040B) ext1 <= wdata;
			else if (port == 16'h04D6) ext2 <= wdata;
			else if (sg_p) begin
				sg[6'(port - 16'h0410)] <= wdata;
				if (port[5:3] == 3'b010) begin             // 410-417: a channel's command
					if (wdata[1:0] == 2'b01) begin sg_load[port[2:0]] <= 1'b1; sg_on[port[2:0]] <= 1'b1; sg_end[port[2:0]] <= 1'b0; end
					if (wdata[1:0] == 2'b10) begin sg_on[port[2:0]] <= 1'b0; sg_load[port[2:0]] <= 1'b0; end
					sg_int[port[2:0]] <= 1'b0;
				end
				if (port[5] && port[1:0] == 2'b00) sg_ptr[port[4:2]][7:0]   <= wdata;   // 420-43F: the pointers
				if (port[5] && port[1:0] == 2'b01) sg_ptr[port[4:2]][15:8]  <= wdata;
				if (port[5] && port[1:0] == 2'b10) sg_ptr[port[4:2]][23:16] <= wdata;
				if (port[5] && port[1:0] == 2'b11) sg_ptr[port[4:2]][31:24] <= wdata;
			end
		end
		else begin
			rdata <= 8'h00;
			if (d1 || d2) begin
				if (rn < 4'd8) begin
					if (!rn[0]) rdata <= (ctl ? ff2 : ff1) ? cur_a[rch][15:8] : cur_a[rch][7:0];
					else        rdata <= (ctl ? ff2 : ff1) ? cur_c[rch][15:8] : cur_c[rch][7:0];
					if (ctl) ff2 <= ~ff2; else ff1 <= ~ff1;
				end
				else case (rn)
					4'h8: begin                                    // status: requests, TC (cleared by the read)
						rdata <= ctl ? {dreq[7:4] | req_sw[7:4], tc_st[7:4]} : {dreq[3:0] | req_sw[3:0], tc_st[3:0]};
						if (ctl) tc_st[7:4] <= 4'h0; else tc_st[3:0] <= 4'h0;
					end
					4'hD: rdata <= temp;
					4'hF: rdata <= {4'hF, ctl ? mask[7:4] : mask[3:0]};
					default: rdata <= 8'h00;
				endcase
			end
			else if (pg)  rdata <= pch[3] ? page[pch[2:0]] : scratch[port[3:0]];
			else if (hpg) rdata <= pch[3] ? hpage[pch[2:0]] : 8'h00;
			else if (port == 16'h040B) rdata <= ext1;
			else if (port == 16'h04D6) rdata <= ext2;
			else if (sg_p && port[5:3] == 3'b011) rdata <= {4'h0, sg_on[port[2:0]], sg_end[port[2:0]], 2'b00};   // 418-41F: status
			else if (sg_p) rdata <= sg[6'(port - 16'h0410)];
			else if (port == 16'h040A) begin rdata <= {4'h0, sg_int[3:0]}; sg_int[3:0] <= 4'h0; end
			else if (port == 16'h04D4) begin rdata <= {sg_int[7:4], 4'h0}; sg_int[7:4] <= 4'h0; end
		end
	end

	// ---- the transfers ----
	if (sg_loaded) begin                                   // an entry in
		sg_load[ch] <= 1'b0;
		sg_a[ch]    <= sg_new_a;
		sg_c[ch]    <= sg_new_c[23:0];
		sg_last[ch] <= sg_new_c[31];
		sg_ptr[ch]  <= sg_ptr[ch] + 32'd8;
	end
	if (sg_go_step) begin
		sg_a[ch] <= mode[ch][3] ? sg_a[ch] - (ch[2] ? 32'd2 : 32'd1) : sg_a[ch] + (ch[2] ? 32'd2 : 32'd1);
		sg_c[ch] <= sg_c[ch] - (ch[2] ? 24'd2 : 24'd1);
	end
	if (sg_go_next) sg_load[ch] <= 1'b1;
	if (sg_go_end) begin                                   // the list's end: masked, IRQ 13
		sg_on[ch]  <= 1'b0;
		sg_end[ch] <= 1'b1;
		sg_int[ch] <= 1'b1;
		mask[ch]   <= 1'b1;
		tc_st[ch]  <= 1'b1;
	end
	if (go_tc) begin
		tc_st[ch] <= 1'b1;
		if (mode[ch][2]) begin cur_a[ch] <= base_a[ch]; cur_c[ch] <= base_c[ch]; end    // auto-initialise
		else mask[ch] <= 1'b1;
		req_sw[ch] <= 1'b0;
	end
	else if (go_step) begin
		cur_a[ch] <= mode[ch][3] ? cur_a[ch] - 16'd1 : cur_a[ch] + 16'd1;
		cur_c[ch] <= cur_c[ch] - 16'd1;
	end

	if (reset) begin
		mask <= 8'hFF; req_sw <= 8'h0; tc_st <= 8'h0; cmd1 <= 8'h0; cmd2 <= 8'h0; ff1 <= 1'b0; ff2 <= 1'b0;
		for (int i = 0; i < 8; i++) begin hpage[i] <= 8'h0; page[i] <= 8'h0; mode[i] <= 6'h0; end
		ext1 <= 8'h0; ext2 <= 8'h0;
		sg_on <= 8'h0; sg_load <= 8'h0; sg_end <= 8'h0; sg_int <= 8'h0;
	end
end

// ---- the engine ---------------------------------------------------------------------------
// a channel wanting service: requested (DREQ or software), unmasked, not cascade (and not 4), its
// controller enabled (command bit 2 clear)
logic [7:0] want;
always_comb
	for (int i = 0; i < 8; i++)
		want[i] = (dreq[i] | req_sw[i]) && !mask[i] && mode[i][5:4] != 2'b11 && i != 4 &&
		          !(i < 4 ? cmd1[2] : cmd2[2]) && !sg_load[i];

typedef enum logic [2:0] {T_IDLE, T_RD, T_WR, T_DONE, T_GAP, T_SG, T_SG_W} tst_t;
tst_t        ts;
logic        w16;                                   // a 16-bit channel's transfer
wire  [31:0] ta = sg_on[ch] ? sg_a[ch] :
                  ch[2] ? {hpage[ch], page[ch][7:1], cur_a[ch], 1'b0} : {hpage[ch], page[ch], cur_a[ch]};
wire  [1:0]  ttype = mode[ch][1:0];                 // 00 verify, 01 write (to memory), 10 read (from memory)

// (dm_addr registered with dm_req: the channel's address mux stays out of the masters' arbiter)

always_ff @(posedge clk) begin
	dack    <= 1'b0;
	tc      <= 1'b0;
	go_step <= 1'b0;
	go_tc   <= 1'b0;
	sg_go_step <= 1'b0;
	sg_go_next <= 1'b0;
	sg_go_end  <= 1'b0;
	sg_loaded  <= 1'b0;
	case (ts)
		T_IDLE: begin
			if (|sg_load) begin                            // a list's next entry first
				for (int i = 7; i >= 0; i--) if (sg_load[i]) ch <= 3'(i);
				ts <= T_SG;
			end
			else begin
				for (int i = 7; i >= 0; i--) if (want[i]) ch <= 3'(i);
				if (|want) ts <= T_RD;
			end
		end
		T_SG: begin dm_we <= 1'b0; dm_be <= 8'hFF; dm_addr <= sg_ptr[ch][31:3]; dm_req <= 1'b1; ts <= T_SG_W; end
		T_SG_W: if (dm_ack) begin
			// the entry: the address (bytes 0-3), the count and the last flag (4-7), little-endian
			dm_req    <= 1'b0;
			sg_new_a  <= {dm_rdata[39:32], dm_rdata[47:40], dm_rdata[55:48], dm_rdata[63:56]};
			sg_new_c  <= {dm_rdata[7:0], dm_rdata[15:8], dm_rdata[23:16], dm_rdata[31:24]};
			sg_loaded <= 1'b1;
			ts        <= T_GAP;
		end
		T_RD: begin
			w16     <= ch[2];
			dm_addr <= ta[31:3];
			if (ttype == 2'b10) begin                      // a read transfer: memory's byte or word
				dm_we  <= 1'b0;
				dm_be  <= 8'hFF;
				dm_req <= 1'b1;
				ts     <= T_WR;
			end
			else if (ttype == 2'b01) begin                 // a write transfer: the device's into memory
				dm_we    <= 1'b1;
				dm_be    <= ch[2] ? (8'b1100_0000 >> ta[2:0]) : (8'b1000_0000 >> ta[2:0]);
				dm_wdata <= ch[2] ? {4{dev_data[7:0], dev_data[15:8]}} : {8{dev_data[7:0]}};   // (8-bit: on every lane)
				dm_req   <= 1'b1;
				ts       <= T_WR;
			end
			else ts <= T_DONE;                              // verify: no memory
		end
		T_WR: if (dm_ack) begin
			dm_req    <= 1'b0;
			temp      <= dm_rdata[63 - 8 * ta[2:0] -: 8];
			dack_data <= ch[2] ? {dm_rdata[63 - 8 * {ta[2:1], 1'b1} -: 8], dm_rdata[63 - 8 * ta[2:0] -: 8]}
			                   : {8'h00, dm_rdata[63 - 8 * ta[2:0] -: 8]};
			ts        <= T_DONE;
		end
		T_DONE: begin
			dack    <= 1'b1;
			dack_ch <= ch;
			if (sg_on[ch]) begin
				// a list's entry: its count is the bytes less 1
				if (sg_c[ch] < (ch[2] ? 24'd2 : 24'd1)) begin
					if (sg_last[ch]) begin tc <= 1'b1; sg_go_end <= 1'b1; end
					else sg_go_next <= 1'b1;
				end
				else sg_go_step <= 1'b1;
			end
			else begin
				tc <= cur_c[ch] == 16'd0;
				if (cur_c[ch] == 16'd0) go_tc <= 1'b1; else go_step <= 1'b1;
			end
			ts      <= T_GAP;
		end
		default: ts <= T_IDLE;                              // T_GAP: the device drops DREQ if it is full
	endcase
	if (reset) begin ts <= T_IDLE; dm_req <= 1'b0; end
end

endmodule
