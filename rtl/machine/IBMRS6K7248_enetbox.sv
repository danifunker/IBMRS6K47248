//============================================================================
//
//  IBMRS6K7248 - the PCnet's wire: its frames to and from the Main's
//  Ethernet bridge through a mailbox in DDR3
//
//  After the HP 9000/385 core's lan_wire.sv (the same mailbox, the same
//  start-up, pacing and dropping), carried to the PCnet's buffers
//  (IBMRS6K7248_pcnet: its transmit buffer read at m_tx_a, its receive
//  buffer written while rx_free). The Main side is a copy of
//  support/sun/sun_enet.cpp that knows this core's magic (mister/README.md).
//
//  The mailbox: 64 KB of DDR3 at ARM physical 1FF0_0000, 64-bit
//  little-endian words; nb_addr is the word (byte offset / 8):
//    +0000 MAGIC    ours, written last at start-up: "RS6ETH01" (16 RX slots)
//    +0008 GEN      ours, a new value at every start-up
//    +0010 TX_WPTR  ours: frames posted          +0018 TX_RPTR  Main's: taken
//    +0020 RX_WPTR  Main's: frames posted        +0028 RX_RPTR  ours: taken
//    +0030 MAC      ours: bit 63 valid, bits 47:40 the first byte (the
//                   driver's address, for the Main's filter)
//    +0038 PROM MAC the Main's: bit 63 valid, the MAC for the address PROM
//                   (this core's addition; else DEF_MAC)
//    +1000 TX ring  8 slots of 800: word 0 bits 10:0 the length, then the
//                   frame, byte i in lane i mod 8 of word 1 + i / 8; no FCS
//    +5000 RX ring  16 slots of 800: word 0 bits 10:0 the length with the
//                   FCS, bits 21:16 the logical filter's index; then the frame
//
//  Start-up (after every reset): MAGIC = 0, GEN = the free-running clock
//  count, the four pointers = 0, MAC, then MAGIC. TX: a frame waiting in
//  the PCnet goes into a free slot (TX_WPTR - TX_RPTR < 8), then its length,
//  then TX_WPTR++; full for 50 ms (no Main) or the network off: dropped.
//  RX: RX_WPTR polled; a slot copied into the PCnet's buffer and posted
//  after its wire time at 10 Mb/s (a guest's small ring cannot take a
//  host's bursts at memory speed); lengths under 18 or over 1522 skipped.
//
//============================================================================

module IBMRS6K7248_enetbox
#(
	parameter int unsigned CLK_HZ  = 100_000_000,
	parameter int unsigned BIT_HZ  = 10_000_000,
	parameter int unsigned POLL    = 20_000,                // clocks between RX_WPTR reads when idle
	parameter int unsigned TXPOLL  = 2_048,                 // ... TX_RPTR reads while the ring is full
	parameter int unsigned TXWAIT  = CLK_HZ / 20,           // full this long: drop the frame (50 ms)
	parameter int unsigned MACPOLL = CLK_HZ / 4,            // the PROM MAC re-read (0.25 s)
	parameter logic [47:0] DEF_MAC = 48'h08005A_4D5201       // an IBM address until the Main gives one
)
(
	input  logic        clk,
	input  logic        reset,
	input  logic        ena,                                 // the OSD's network not None

	// the PCnet's wire side (IBMRS6K7248_pcnet)
	input  logic        tx_pend,
	input  logic [10:0] tx_len,
	output logic [10:0] m_tx_a,
	input  logic [7:0]  m_tx_q,
	output logic        m_tx_done,
	input  logic        rx_free,
	output logic        m_rx_we,
	output logic [10:0] m_rx_a,
	output logic [7:0]  m_rx_d,
	output logic        m_rx_post,
	output logic [10:0] m_rx_len,
	output logic [5:0]  m_rx_hash,
	output logic [47:0] aprom_mac,
	input  logic [47:0] padr,
	input  logic        padr_ok,

	// the mailbox port: one 64-bit word, held until nb_ack
	output logic        nb_req,
	output logic        nb_we,
	output logic [12:0] nb_addr,
	output logic [63:0] nb_wdata,
	input  logic        nb_ack,                              // one clock; a read's data with it
	input  logic [63:0] nb_rdata
);

localparam logic [12:0] NB_MAGIC = 13'h0000, NB_GEN = 13'h0001, NB_TXW = 13'h0002, NB_TXR = 13'h0003,
                        NB_RXW   = 13'h0004, NB_RXR = 13'h0005, NB_MAC = 13'h0006, NB_PMAC = 13'h0007;
localparam logic [12:0] NB_TX = 13'h0200, NB_RX = 13'h0A00;  // 1000 / 8, 5000 / 8; slots of 100 words
localparam logic [63:0] MAGIC = 64'h5253_3645_5448_3031;    // "RS6ETH01"
localparam logic [31:0] TX_SLOTS = 32'd8, RX_SLOTS = 32'd16;
localparam logic [10:0] RXMIN = 11'd18, RXMAX = 11'd1522, TXMAX = 11'd2040;

typedef enum logic [3:0] {S_BOOT, S_IDLE, S_NB, S_TXA, S_TXB, S_TXHDR, S_TXPTR, S_TXDONE, S_TXR,
                          S_RXW, S_RXHDR, S_RXBYTE, S_PMAC} st_t;
st_t         st, nret;
logic [2:0]  bk;
logic [31:0] tick = 32'd0;
logic [31:0] gen_v;

// the mailbox word in flight
logic        n_req, n_we;
logic [12:0] n_a;
logic [63:0] n_wd, n_rd;
assign nb_req   = n_req;
assign nb_we    = n_we;
assign nb_addr  = n_a;
assign nb_wdata = n_wd;

// the pointers: ours, and the Main's as last read
logic [31:0] txw, txr_c, rxr, rxw_c;

// TX
logic        tx_busy;                        // the PCnet's frame is being taken
logic [11:0] tp;                             // its byte position
logic [10:0] tlen;
logic [63:0] tw;
logic [31:0] tx_wait, txr_tmr;
wire         tx_room = (txw - txr_c) < TX_SLOTS;
wire  [12:0] tslot   = NB_TX + {2'd0, txw[2:0], 8'd0};
wire  [63:0] tnw     = {tp < {1'b0, tlen} ? m_tx_q : 8'd0, tw[63:8]};
assign m_tx_a = tp[10:0];

// RX
logic        rx_held, rxr_pend;              // a frame in the PCnet's buffer, not yet posted
logic [10:0] rlen;
logic [5:0]  rhash;
logic [7:0]  rj;                             // the word within the slot's frame
logic [2:0]  rk;                             // the byte within the word
logic [31:0] poll_tmr, pmac_tmr;
logic [14:0] pace;                           // bit times until the frame may be posted
wire  [12:0] rslot = NB_RX + {1'b0, rxr[3:0], 8'd0};

// MAC
logic        mac_pend, padr_ok_q;
logic [47:0] padr_q;
wire  [63:0] mac_w = {padr_ok, 15'd0, padr};

// 10 Mb/s bit times
logic [31:0] acc;
logic        bit_tick;
wire  [32:0] acc_n = {1'b0, acc} + 33'(BIT_HZ);
always_ff @(posedge clk) begin
	if (acc_n >= 33'(CLK_HZ)) begin acc <= 32'(acc_n - 33'(CLK_HZ)); bit_tick <= 1'b1; end
	else begin acc <= acc_n[31:0]; bit_tick <= 1'b0; end
end

task automatic nb(input logic [12:0] a, input logic w, input logic [63:0] d, input st_t r);
	n_a <= a; n_we <= w; n_wd <= d; nret <= r; n_req <= 1'b1; st <= S_NB;
endtask

always_ff @(posedge clk) begin
	tick      <= tick + 32'd1;
	m_rx_we   <= 1'b0;
	m_rx_post <= 1'b0;
	m_tx_done <= 1'b0;

	if (reset) begin
		gen_v <= tick;
		st <= S_BOOT; bk <= 3'd0;
		if (nb_ack) n_req <= 1'b0;                    // a word in flight finishes; S_BOOT waits for it
		tx_busy <= 1'b0; mac_pend <= 1'b0; padr_ok_q <= 1'b0;
		rx_held <= 1'b0; rxr_pend <= 1'b0; pace <= 15'd0;
		txw <= 32'd0; txr_c <= 32'd0; rxr <= 32'd0; rxw_c <= 32'd0;
		poll_tmr <= 32'd0; pmac_tmr <= 32'd0; txr_tmr <= 32'd0; tx_wait <= 32'd0;
		aprom_mac <= DEF_MAC;
	end
	else begin
		if (poll_tmr != 32'd0) poll_tmr <= poll_tmr - 32'd1;
		if (pmac_tmr != 32'd0) pmac_tmr <= pmac_tmr - 32'd1;
		if (txr_tmr != 32'd0) txr_tmr <= txr_tmr - 32'd1;
		if (tx_pend && !tx_busy && !tx_room && tx_wait != TXWAIT) tx_wait <= tx_wait + 32'd1;
		if (bit_tick && pace != 15'd0) pace <= pace - 15'd1;

		// the driver's address, once set and whenever it changes
		padr_ok_q <= padr_ok;
		padr_q    <= padr;
		if ((padr_ok && !padr_ok_q) || (padr_ok && padr != padr_q)) mac_pend <= 1'b1;

		// a frame in the PCnet's buffer, its wire time passed: posted
		if (rx_held && pace == 15'd0 && rx_free) begin
			m_rx_post <= 1'b1;
			m_rx_len  <= rlen;
			m_rx_hash <= rhash;
			rx_held   <= 1'b0;
			rxr       <= rxr + 32'd1;
			rxr_pend  <= 1'b1;
		end

		case (st)
			// ---- one mailbox word, then nret
			S_NB: if (nb_ack) begin n_req <= 1'b0; n_rd <= nb_rdata; st <= nret; end

			// ---- start-up: MAGIC off, GEN, the pointers, MAC, MAGIC last
			S_BOOT: if (n_req) begin
				if (nb_ack) n_req <= 1'b0;                // the word that was in flight at reset
			end
			else begin
				bk <= bk + 3'd1;
				case (bk)
					3'd0: nb(NB_MAGIC, 1'b1, 64'd0, S_BOOT);
					3'd1: nb(NB_GEN, 1'b1, {32'd0, gen_v}, S_BOOT);
					3'd2: nb(NB_TXW, 1'b1, 64'd0, S_BOOT);
					3'd3: nb(NB_TXR, 1'b1, 64'd0, S_BOOT);
					3'd4: nb(NB_RXW, 1'b1, 64'd0, S_BOOT);
					3'd5: nb(NB_RXR, 1'b1, 64'd0, S_BOOT);
					3'd6: begin mac_pend <= 1'b0; nb(NB_MAC, 1'b1, mac_w, S_BOOT); end
					default: nb(NB_MAGIC, 1'b1, MAGIC, S_IDLE);
				endcase
			end

			S_IDLE:
				if (mac_pend) begin
					mac_pend <= 1'b0;
					nb(NB_MAC, 1'b1, mac_w, S_IDLE);
				end
				else if (rxr_pend) begin
					rxr_pend <= 1'b0;
					nb(NB_RXR, 1'b1, {32'd0, rxr}, S_IDLE);
				end
				else if (tx_pend && !tx_busy && (!ena || tx_len == 11'd0 || tx_len > TXMAX || tx_wait == TXWAIT)) begin
					m_tx_done <= 1'b1;                    // dropped
					tx_wait   <= 32'd0;
				end
				else if (tx_pend && !tx_busy && tx_room) begin
					tx_busy <= 1'b1;
					tlen    <= tx_len;
					tp      <= 12'd0;
					st      <= S_TXA;
				end
				else if (tx_pend && !tx_busy && txr_tmr == 32'd0) begin
					txr_tmr <= TXPOLL;
					nb(NB_TXR, 1'b0, 64'd0, S_TXR);
				end
				else if (!rx_held && rx_free && rxw_c != rxr) begin
					// off, or out of step (the Main's RX_WPTR from before our start-up): skip to the Main's
					if (!ena || rxw_c - rxr > RX_SLOTS) begin
						rxr <= rxw_c;
						nb(NB_RXR, 1'b1, {32'd0, rxw_c}, S_IDLE);
					end
					else nb(rslot, 1'b0, 64'd0, S_RXHDR);
				end
				else if (!rx_held && poll_tmr == 32'd0) begin
					poll_tmr <= POLL;
					nb(NB_RXW, 1'b0, 64'd0, S_RXW);
				end
				else if (pmac_tmr == 32'd0) begin
					pmac_tmr <= MACPOLL;
					nb(NB_PMAC, 1'b0, 64'd0, S_PMAC);
				end

			// ---- TX: the frame into the slot's words, little-endian (bytes shifted in from the top)
			S_TXA: st <= S_TXB;                              // (m_tx_q <- the byte at tp)
			S_TXB: begin
				tw <= tnw;
				tp <= tp + 12'd1;
				if (tp[2:0] == 3'd7)
					nb(tslot + 13'd1 + {4'd0, tp[11:3]}, 1'b1, tnw, (tp + 12'd1 >= {1'b0, tlen}) ? S_TXHDR : S_TXA);
				else st <= S_TXA;
			end
			S_TXHDR: nb(tslot, 1'b1, {53'd0, tlen}, S_TXPTR);
			S_TXPTR: begin
				txw <= txw + 32'd1;
				nb(NB_TXW, 1'b1, {32'd0, txw + 32'd1}, S_TXDONE);
			end
			S_TXDONE: begin tx_busy <= 1'b0; tx_wait <= 32'd0; m_tx_done <= 1'b1; st <= S_IDLE; end
			S_TXR: begin txr_c <= n_rd[31:0]; st <= S_IDLE; end

			// ---- RX
			S_RXW: begin rxw_c <= n_rd[31:0]; st <= S_IDLE; end
			S_RXHDR:
				if (n_rd[10:0] < RXMIN || n_rd[10:0] > RXMAX) begin
					rxr <= rxr + 32'd1;                     // skipped
					nb(NB_RXR, 1'b1, {32'd0, rxr + 32'd1}, S_IDLE);
				end
				else begin
					rlen  <= n_rd[10:0];
					rhash <= n_rd[21:16];
					pace  <= ({4'd0, n_rd[10:0]} + 15'd20) << 3;
					rj <= 8'd0; rk <= 3'd0;
					nb(rslot + 13'd1, 1'b0, 64'd0, S_RXBYTE);
				end
			S_RXBYTE: begin
				m_rx_we <= 1'b1; m_rx_a <= {rj, rk}; m_rx_d <= n_rd[7:0];
				n_rd <= {8'd0, n_rd[63:8]};
				rk <= rk + 3'd1;
				if (rk == 3'd7) begin
					rj <= rj + 8'd1;
					if ((({4'd0, rj} + 12'd1) << 3) >= {1'b0, rlen}) begin rx_held <= 1'b1; st <= S_IDLE; end
					else nb(rslot + 13'd2 + {5'd0, rj}, 1'b0, 64'd0, S_RXBYTE);
				end
			end

			// ---- the Main's MAC for the address PROM
			S_PMAC: begin
				if (n_rd[63]) aprom_mac <= n_rd[47:0];
				st <= S_IDLE;
			end
			default: st <= S_IDLE;
		endcase
	end
end

endmodule
