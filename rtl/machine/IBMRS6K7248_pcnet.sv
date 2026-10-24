//============================================================================
//
//  IBMRS6K7248 - the AMD Am79C970 PCnet-PCI Ethernet controller (PCI device 12)
//
//  The planar's 10 Mb/s Ethernet as the firmware's driver (PCI_C970) and
//  AIX's see it; the semantics from QEMU's hw/net/pcnet.c and pcnet-pci.c
//  (the AIX `ent` driver runs on them), its chip ID too (a 79C970A's).
//
//  The host side: PCI configuration (as the 53C810's), BAR0's 32 bytes of
//  I/O: the address PROM at 00-0F, then RDP / RAP / RESET / BDP as 16-bit
//  registers at 10, 12, 14, 16 (WIO) or, after a 32-bit write of RDP, as
//  32-bit ones at 10, 14, 18, 1C (DWIO). The CSRs that matter: 0 (the
//  control and status bits, the interrupt flags), 1-2 (the init block's
//  address), 3 (the interrupt masks), 4, 5, 8-15 (from the init block:
//  the logical address filter, the physical address, the mode), 58 (the
//  software style), 76/78 (the ring lengths), 88/89 (the chip ID), 112 (the
//  missed frames); 16-47 keep what is written. BCR 2, 4-7, 9, 18-20, 22.
//
//  The engine, one thing at a time over the DMA port (as the 810's: one
//  doubleword a request, dm_*data[63:56] the byte at the lowest address,
//  the structures little-endian): the init block (16- or 32-bit), the
//  descriptor rings in software styles 0, 2 and 3, a frame gathered from
//  its transmit descriptors (STP to ENP) into the transmit buffer, a frame
//  scattered from the receive buffer into its receive descriptors (chained,
//  OFLO when they run out); the address filter (promiscuous, physical,
//  broadcast, the logical filter's bit by the CRC's top 6 bits); internal
//  loopback (CSR15 LOOP: the frame comes back with its FCS); the transmit
//  ring polled every 1.9 ms (unless DPOLL) as well as on TDMD, which stays
//  set until the ring has nothing more to send.
//
//  The wire: in clk_m, the transmit buffer's frame (tx_pend, tx_len, its
//  bytes at m_tx_a, a clock later m_tx_q) until m_tx_done; the receive
//  buffer written while rx_free, then m_rx_post with its length (the FCS
//  included) and its logical filter index. IBMRS6K7248_enetbox carries
//  them to the Main through DDR3. aprom_mac is the address PROM's MAC (the
//  Main's choice); padr the one the driver set (for the Main's filter).
//
//  Not done: the FIFO watermarks, the MII, the EEPROM interface, the
//  suspend and sleep modes, retries and collisions (the wire never fails),
//  BSWP (as QEMU: the MPC105 keeps bytes at their addresses), the memory
//  BAR's decode.
//
//============================================================================

module IBMRS6K7248_pcnet
(
	input  logic        clk,
	input  logic        reset,

	// PCI configuration
	input  logic        cfg_sel,
	input  logic        cfg_we,
	input  logic [7:2]  cfg_reg,
	input  logic [3:0]  cfg_be,                 // bit k: byte k (little-endian)
	input  logic [31:0] cfg_wdata,
	output logic [31:0] cfg_rdata,
	output logic        io_on,
	output logic [31:5] io_base,

	// the registers (BAR0)
	input  logic        sel,
	input  logic        we,
	input  logic [4:2]  off,
	input  logic [3:0]  be,                     // be[3]: the lowest address
	input  logic [31:0] wdata,                  // the lowest address's byte in 31:24
	output logic [31:0] rdata,
	output logic        irq,

	// DMA: one doubleword, held until dm_ack
	output logic        dm_req,
	output logic        dm_we,
	output logic [31:3] dm_addr,
	output logic [7:0]  dm_be,
	output logic [63:0] dm_wdata,
	input  logic        dm_ack,
	input  logic        dm_err,
	input  logic [63:0] dm_rdata,

	// the wire, in clk_m
	input  logic        clk_m,
	output logic        tx_pend,
	output logic [10:0] tx_len,
	input  logic [10:0] m_tx_a,
	output logic [7:0]  m_tx_q,
	input  logic        m_tx_done,              // a pulse
	output logic        rx_free,
	input  logic        m_rx_we,
	input  logic [10:0] m_rx_a,
	input  logic [7:0]  m_rx_d,
	input  logic        m_rx_post,              // a pulse, with:
	input  logic [10:0] m_rx_len,
	input  logic [5:0]  m_rx_hash,
	input  logic [47:0] aprom_mac,              // (quasi-static) the first byte in 47:40
	output logic [47:0] padr,                   // ... the driver's, the first byte in 47:40
	output logic        padr_ok
);

// ---- PCI configuration ----------------------------------------------------------------------
logic [15:0] pci_cmd;
logic [4:0]  pci_sts_w1c;
logic [7:0]  pci_cls, pci_lat, pci_intl;
logic [31:5] bar0, bar1;
logic        set_ma;
always_ff @(posedge clk) begin
	if (cfg_sel & cfg_we)
		case (cfg_reg)
			6'h01: begin
				if (cfg_be[0]) pci_cmd[7:0] <= cfg_wdata[7:0] & 8'h47;
				if (cfg_be[1]) pci_cmd[15:8] <= cfg_wdata[15:8] & 8'h01;
				if (cfg_be[3]) pci_sts_w1c <= pci_sts_w1c & ~cfg_wdata[31:27];
			end
			6'h03: begin
				if (cfg_be[0]) pci_cls <= cfg_wdata[7:0];
				if (cfg_be[1]) pci_lat <= cfg_wdata[15:8];
			end
			6'h04: begin
				if (cfg_be[0]) bar0[7:5] <= cfg_wdata[7:5];
				for (int k = 1; k < 4; k++) if (cfg_be[k]) bar0[8 * k +: 8] <= cfg_wdata[8 * k +: 8];
			end
			6'h05: begin
				if (cfg_be[0]) bar1[7:5] <= cfg_wdata[7:5];
				for (int k = 1; k < 4; k++) if (cfg_be[k]) bar1[8 * k +: 8] <= cfg_wdata[8 * k +: 8];
			end
			6'h0F: if (cfg_be[0]) pci_intl <= cfg_wdata[7:0];
			default: ;
		endcase
	if (set_ma) pci_sts_w1c[2] <= 1'b1;            // received master abort
	if (reset) begin
		pci_cmd <= 16'h0; pci_sts_w1c <= 5'd0;
		pci_cls <= 8'h0; pci_lat <= 8'h0; pci_intl <= 8'h0;
		bar0 <= 27'h0; bar1 <= 27'h0;
	end
end
always_ff @(posedge clk) if (cfg_sel & ~cfg_we)
	case (cfg_reg)
		6'h00:   cfg_rdata <= 32'h2000_1022;                                  // AMD, PCnet
		6'h01:   cfg_rdata <= {pci_sts_w1c, 2'b01, 1'b0, 1'b1, 7'h00, pci_cmd};  // medium DEVSEL, fast back-to-back
		6'h02:   cfg_rdata <= 32'h0200_0010;                                  // Ethernet, revision 10
		6'h03:   cfg_rdata <= {16'h0000, pci_lat, pci_cls};
		6'h04:   cfg_rdata <= {bar0, 5'h01};                                  // 32 bytes of I/O
		6'h05:   cfg_rdata <= {bar1, 5'h00};                                  // the same as memory (not decoded)
		6'h0F:   cfg_rdata <= {8'hFF, 8'h06, 8'h01, pci_intl};                 // MAX_LAT, MIN_GNT, INTA
		default: cfg_rdata <= 32'h0;
	endcase
assign io_on   = pci_cmd[0];
assign io_base = bar0;
wire   bm_on   = pci_cmd[2];                       // bus master enable

// ---- the buffers ------------------------------------------------------------------------------
// transmit: written here, read by the wire (clk_m) and by the loopback (here): two copies
logic [7:0]  txb_m [2048];
logic [7:0]  txb_l [2048];
logic        txb_we;
logic [10:0] txb_wa;
logic [7:0]  txb_d, txb_q;
logic [10:0] rd_a;                                 // the receive path's byte address (both buffers)
always_ff @(posedge clk) begin
	if (txb_we) begin txb_m[txb_wa] <= txb_d; txb_l[txb_wa] <= txb_d; end
	txb_q <= txb_l[rd_a];
end
always_ff @(posedge clk_m) m_tx_q <= txb_m[m_tx_a];
// receive: written by the wire, read here
logic [7:0]  rxb [2048];
logic [7:0]  rxb_q;
always_ff @(posedge clk_m) if (m_rx_we) rxb[m_rx_a] <= m_rx_d;
always_ff @(posedge clk) rxb_q <= rxb[rd_a];

// the handshakes (toggles), each synchronised into the other clock
logic        tx_t = 1'b0, tx_done_t = 1'b0;            // a frame posted (here) / taken (clk_m)
logic        rx_post_t = 1'b0, rx_take_t = 1'b0;       // a frame posted (clk_m) / taken (here)
logic [2:0]  tx_done_s, rx_post_s;
logic [2:0]  tx_t_m, rx_take_m;
logic [10:0] rx_len_m;                                 // (clk_m, held while the frame waits)
logic [5:0]  rx_hash_m;
always_ff @(posedge clk_m) begin
	tx_t_m    <= {tx_t_m[1:0], tx_t};
	rx_take_m <= {rx_take_m[1:0], rx_take_t};
	if (m_tx_done) tx_done_t <= ~tx_done_t;
	if (m_rx_post) begin rx_post_t <= ~rx_post_t; rx_len_m <= m_rx_len; rx_hash_m <= m_rx_hash; end
end
assign tx_pend = tx_t_m[2] != tx_done_t;
assign rx_free = rx_take_m[2] == rx_post_t && !m_rx_post;
always_ff @(posedge clk) begin
	tx_done_s <= {tx_done_s[1:0], tx_done_t};
	rx_post_s <= {rx_post_s[1:0], rx_post_t};
end
wire tx_busy  = tx_t != tx_done_s[2];                  // the wire has not taken the last frame
wire rx_ready = rx_post_s[2] != rx_take_t;             // a frame from the wire waits (its length and hash are still)

// ---- registers --------------------------------------------------------------------------------
logic [6:0]  rap;
logic        dwio;                                     // BCR18 bit 7
logic [15:0] csr0, csr1, csr2, csr3, csr4, csr5, csr15, csr47, csr112;
logic [63:0] ladrf;                                    // CSR8-11
logic [15:0] padr_r [3];                               // CSR12-14
logic [31:0] rdra, tdra;
logic [9:0]  rlen, tlen;                               // ring lengths, 1-512
logic [8:0]  rx_idx, tx_idx;                           // the current descriptors
logic [3:0]  rlen_c, tlen_c;                           // CSR6's codes
logic [15:0] csr_st [16:47];                           // CSR16-47 as written
logic [15:0] bcr2, bcr4, bcr5, bcr6, bcr7, bcr9, bcr19, bcr22;
logic [7:0]  swstyle;                                  // BCR20 7:0
logic        ssize32;                                  // BCR20 bit 8
logic [7:0]  aprom [16];
logic        aprom_w;                                  // the PROM written by software (BCR2 APROMWE)

wire         ss32   = ssize32;
wire [4:0]   dsz    = swstyle == 8'd0 ? 5'd8 : 5'd16;  // a descriptor's bytes
// the PROM: the MAC, 00 00, 00, 11, 00 00, the checksum (bytes 0-B and E-F), 'W' 'W'
logic [15:0] aprom_sum;
always_comb begin
	aprom_sum = 16'd0;
	for (int i = 0; i < 6; i++) aprom_sum = aprom_sum + {8'd0, aprom_mac[47 - 8 * i -: 8]};
	aprom_sum = aprom_sum + 16'h0011 + 16'h0057 + 16'h0057;
end
function automatic logic [7:0] prom(input logic [3:0] a);
	if (aprom_w) prom = aprom[a];
	else case (a)
		4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5: prom = aprom_mac[47 - 8 * a -: 8];
		4'd9:          prom = 8'h11;
		4'd12:         prom = aprom_sum[7:0];
		4'd13:         prom = aprom_sum[15:8];
		4'd14, 4'd15:  prom = 8'h57;
		default:       prom = 8'h00;
	endcase
endfunction

// CSR0's bits
wire init_b = csr0[0], strt_b = csr0[1], stop_b = csr0[2], tdmd_b = csr0[3];
wire txon   = csr0[4], rxon   = csr0[5], inea   = csr0[6];
wire intr   = |(csr0[14:8] & ~csr3[14:8] & 7'b1011111);
assign irq  = intr & inea;
wire loop_m = csr15[2];                                // loopback
wire drx    = csr15[0], dtx = csr15[1];
wire drcvpa = csr15[13], drcvbc = csr15[14], prom_m = csr15[15];
wire dpoll  = csr4[12];
wire tokintd = csr5[15], ltinten = csr5[14];

assign padr = {padr_r[0][7:0], padr_r[0][15:8], padr_r[1][7:0], padr_r[1][15:8], padr_r[2][7:0], padr_r[2][15:8]};

// a CSR read
function automatic logic [15:0] csr_rd(input logic [6:0] n);
	case (n)
		7'd0:   csr_rd = {|csr0[14:11], csr0[14:8], intr, csr0[6:0]};
		7'd1:   csr_rd = csr1;
		7'd2:   csr_rd = csr2;
		7'd3:   csr_rd = csr3;
		7'd4:   csr_rd = csr4;
		7'd5:   csr_rd = csr5;
		7'd6:   csr_rd = {tlen_c, rlen_c, 8'h00};
		7'd8:   csr_rd = ladrf[15:0];
		7'd9:   csr_rd = ladrf[31:16];
		7'd10:  csr_rd = ladrf[47:32];
		7'd11:  csr_rd = ladrf[63:48];
		7'd12:  csr_rd = padr_r[0];
		7'd13:  csr_rd = padr_r[1];
		7'd14:  csr_rd = padr_r[2];
		7'd15:  csr_rd = csr15;
		7'd47:  csr_rd = csr47;
		7'd58:  csr_rd = {6'd0, ssize32 ? 2'b11 : 2'b10, swstyle};
		7'd72:  csr_rd = 16'(rlen - {1'b0, rx_idx});          // RCVRC: counts down
		7'd74:  csr_rd = 16'(tlen - {1'b0, tx_idx});
		7'd76:  csr_rd = 16'(rlen);
		7'd78:  csr_rd = 16'(tlen);
		7'd88:  csr_rd = 16'h1003;                             // the chip ID: 79C970A (QEMU's)
		7'd89:  csr_rd = 16'h0262;
		7'd112: csr_rd = csr112;
		default: csr_rd = (n >= 7'd16 && n <= 7'd47) ? csr_st[n[5:0]] : 16'h0;
	endcase
endfunction
function automatic logic [15:0] bcr_rd(input logic [6:0] n);
	case (n)
		7'd0, 7'd1: bcr_rd = 16'h0005;
		7'd2:  bcr_rd = bcr2;
		7'd4:  bcr_rd = {1'b1, bcr4[14:0]};                    // the link is up
		7'd5:  bcr_rd = {1'b1, bcr5[14:0]};
		7'd6:  bcr_rd = {1'b1, bcr6[14:0]};
		7'd7:  bcr_rd = {1'b1, bcr7[14:0]};
		7'd9:  bcr_rd = bcr9;
		7'd18: bcr_rd = {8'h90, dwio, 7'h01};
		7'd19: bcr_rd = bcr19;
		7'd20: bcr_rd = {6'd0, ssize32 ? 2'b11 : 2'b10, swstyle};
		7'd22: bcr_rd = bcr22;
		default: bcr_rd = 16'h0;
	endcase
endfunction

// ---- the engine -------------------------------------------------------------------------------
typedef enum logic [4:0] {
	E_IDLE, E_DMA, E_INIT, E_INIT_N,
	E_TX, E_TXD, E_TXD_N, E_TXOWN, E_TXB, E_TXCP, E_TXSTAT, E_TXNEXT,
	E_RX, E_RXF, E_RXF_N, E_RXFILT, E_RXD, E_RXD_N, E_RXOWN, E_RXCP, E_RXCP_W, E_RXCP_D,
	E_RXBUF, E_RXMORE, E_RXLAST, E_RXSTAT, E_RXDONE, E_RXOVF, E_RXDROP
} est_t;
est_t        e, e_ret;                                 // (E_DMA returns to e_ret)

// a DMA request and its answer
logic [31:0] da;                                       // the byte address
logic        dwe;
logic [7:0]  dbe;
logic [63:0] dwd, drd;
assign dm_addr  = da[31:3];
assign dm_we    = dwe;
assign dm_be    = dbe;
assign dm_wdata = dwd;

// the little-endian 32-bit word at a doubleword's half h (bytes at the lowest address first)
function automatic logic [31:0] le32(input logic [63:0] d, input logic h);
	logic [31:0] w;
	w = h ? d[31:0] : d[63:32];
	le32 = {w[7:0], w[15:8], w[23:16], w[31:24]};
endfunction

// a write's byte lanes at an address (lane k: dbe bit 7 - k)
function automatic logic [7:0] be8(input logic [31:0] a);  be8  = 8'b1000_0000 >> a[2:0]; endfunction
function automatic logic [7:0] be16(input logic [31:0] a); be16 = 8'b1100_0000 >> a[2:0]; endfunction
function automatic logic [7:0] be32(input logic [31:0] a); be32 = a[2] ? 8'h0F : 8'hF0; endfunction

// the init block's words, a descriptor's words
logic [31:0] iw [7];
logic [2:0]  wi;                                       // the word being read
logic [31:0] dw0, dw1, dw2;
// a descriptor's fields as the software style places them
wire [31:0] d_badr   = swstyle == 8'd0 ? {csr2[15:8], dw0[23:0]} : swstyle == 8'd3 ? dw2 : dw0;
wire [15:0] d_status = swstyle == 8'd0 ? {dw0[31:24], 8'h00} : dw1[31:16];
wire [11:0] d_bcnt   = dw1[11:0];                       // two's complement: the buffer's length negated
wire [12:0] d_blen   = d_bcnt == 12'd0 ? 13'd4096 : 13'(13'h1000 - {1'b0, d_bcnt});
wire        d_own    = d_status[15];
wire [2:0]  d_last   = swstyle == 8'd0 ? 3'd1 : 3'd2;   // a descriptor's last word read

// the frame being gathered or scattered
logic [10:0] f_len;                                    // its length (receive: with the FCS)
logic [10:0] f_pos;                                    // the next byte
logic        f_lb;                                     // a loopback frame (from the transmit buffer)
logic [5:0]  f_hash;
logic        gathering;                                // between STP and ENP
logic [31:0] crc, crc_h;                               // the frame's CRC so far; after the address (the hash)
logic [47:0] dst;
logic        is_pa, is_bc, is_la;
logic        first_d;                                  // the frame's first receive descriptor
logic [31:0] b_a;                                      // the buffer's next byte's address
logic [12:0] b_left;                                   // the buffer's bytes left
logic [63:0] acc;                                      // a doubleword being filled (receive)
logic [7:0]  acc_be;
logic        lb_pend;                                  // a loopback frame waits to be received
logic [10:0] lb_len;
logic [31:0] lb_fcs, lb_hash;
logic [16:0] poll_n;                                   // the transmit poll's timer
logic        poll_due;
logic        init_req, strt_req;
logic [31:0] desc_a, prev_a;                           // the current descriptor's address, the one before
logic        prev_first;
logic        err_d;

// one CRC-32 (reflected) step over a byte
function automatic logic [31:0] crc8(input logic [31:0] c, input logic [7:0] b);
	logic [31:0] x;
	x = c ^ {24'd0, b};
	for (int k = 0; k < 8; k++) x = (x >> 1) ^ (32'hEDB8_8320 & {32{x[0]}});
	crc8 = x;
endfunction

// the receive path's byte (two clocks after rd_a has its address): the wire's buffer, or the loopback's
// with its FCS after the frame
logic [10:0] rd_a_q;
always_ff @(posedge clk) rd_a_q <= rd_a;
wire [10:0] lb_off  = rd_a_q - lb_len;
wire [7:0]  rx_byte = !f_lb ? rxb_q : (rd_a_q < lb_len) ? txb_q : lb_fcs[8 * lb_off[1:0] +: 8];

// ---- the bus side and the engine, one block -----------------------------------------------------
// a register read's value (the bus's lanes), and whether it reads RESET (a software reset)
wire  [15:0] csr_v = csr_rd(rap);
wire  [15:0] bcr_v = bcr_rd(rap);
logic [31:0] rv;
always_comb begin
	rv = 32'hFFFF_FFFF;
	if (off[4:2] < 3'd4) rv = {prom({off[3:2], 2'd0}), prom({off[3:2], 2'd1}), prom({off[3:2], 2'd2}), prom({off[3:2], 2'd3})};
	else if (!dwio) begin
		case (off)
			3'd4: rv = {csr_v[7:0], csr_v[15:8], 1'b0, rap, 8'h00};          // RDP, RAP
			3'd5: rv = {16'h0000, bcr_v[7:0], bcr_v[15:8]};                    // RESET, BDP
			default: ;
		endcase
	end
	else case (off)
		3'd4: rv = {csr_v[7:0], csr_v[15:8], 16'h0000};
		3'd5: rv = {1'b0, rap, 24'h000000};
		3'd6: rv = 32'h0;
		3'd7: rv = {bcr_v[7:0], bcr_v[15:8], 16'h0000};
		default: ;
	endcase
end
wire         rd_reset = dwio ? off == 3'd6 : (off == 3'd5 && be[3:2] == 2'b11);
logic        s_reset;                                  // a RESET register read (software reset)

task automatic bcr_write(input logic [6:0] n, input logic [15:0] v);
	case (n)
		7'd2:  bcr2 <= v;
		7'd4:  bcr4 <= v;
		7'd5:  bcr5 <= v;
		7'd6:  bcr6 <= v;
		7'd7:  bcr7 <= v;
		7'd9:  bcr9 <= v;
		7'd18: dwio <= v[7];
		7'd19: bcr19 <= v;
		7'd20: if (stop_b) begin                           // the software style: 0, 1 (ILACC), 2, 3
			case (v[7:0])
				8'd0:          begin swstyle <= 8'd0; ssize32 <= 1'b0; end
				8'd1:          begin swstyle <= 8'd1; ssize32 <= 1'b1; end
				8'd2, 8'd3:    begin swstyle <= v[7:0]; ssize32 <= 1'b1; end
				default:       begin swstyle <= 8'd0; ssize32 <= 1'b0; end
			endcase
		end
		7'd22: bcr22 <= v;
		default: ;
	endcase
endtask

task automatic csr_write(input logic [6:0] n, input logic [15:0] v);
	case (n)
		7'd0: begin
			csr0[14:8] <= csr0[14:8] & ~v[14:8];           // the flags: written 1, cleared
			csr0[6]    <= v[6];                             // INEA
			if (v[3]) csr0[3] <= 1'b1;                      // TDMD
			if (v[2] && !stop_b) begin                       // STOP: all else off
				csr0      <= 16'h0004;
				gathering <= 1'b0;
				lb_pend   <= 1'b0;
				init_req  <= 1'b0;
				strt_req  <= 1'b0;
			end
			else if (!v[2]) begin
				if (v[0] && !init_b) init_req <= 1'b1;
				if (v[1] && !strt_b) strt_req <= 1'b1;
			end
		end
		7'd1, 7'd16: csr1 <= v;
		7'd2, 7'd17: csr2 <= v;
		7'd3:  csr3 <= v;
		7'd4:  csr4 <= (v & ~16'h026A) | (csr4 & ~v & 16'h026A);
		7'd5:  csr5 <= (v & ~16'h0A90) | (csr5 & ~v & 16'h0A90);
		7'd8:  ladrf[15:0]  <= v;
		7'd9:  ladrf[31:16] <= v;
		7'd10: ladrf[47:32] <= v;
		7'd11: ladrf[63:48] <= v;
		7'd12: padr_r[0] <= v;
		7'd13: padr_r[1] <= v;
		7'd14: padr_r[2] <= v;
		7'd15: csr15 <= v;
		7'd47: csr47 <= v;
		7'd58: bcr_write(7'd20, v);
		7'd76: rlen <= (v == 16'd0 || v > 16'd512) ? 10'd512 : v[9:0];
		7'd78: tlen <= (v == 16'd0 || v > 16'd512) ? 10'd512 : v[9:0];
		7'd112: if (stop_b) csr112 <= v;
		default: ;
	endcase
	if (n >= 7'd16 && n <= 7'd47) csr_st[n[5:0]] <= v;
endtask

always_ff @(posedge clk) begin
	set_ma  <= 1'b0;
	txb_we  <= 1'b0;
	s_reset <= 1'b0;

	// the transmit poll
	if (poll_n != 17'd0) poll_n <= poll_n - 17'd1;
	else begin poll_n <= 17'h1FFFF; if (txon && !dpoll) poll_due <= 1'b1; end

	// ---- register accesses ----
	if (sel) begin
		if (we) begin
			if (off[4:2] < 3'd4) begin                         // the PROM (with APROMWE)
				if (bcr2[8]) begin
					for (int k = 0; k < 4; k++) if (be[3 - k]) aprom[{off[3:2], 2'(k)}] <= wdata[31 - 8 * k -: 8];
					if (!aprom_w) for (int i = 0; i < 16; i++) if (!(i[3:2] == off[3:2] && be[3 - i[1:0]])) aprom[i] <= prom(4'(i));
					aprom_w <= 1'b1;
				end
			end
			else if (!dwio) begin
				// 16-bit registers: RDP 10, RAP 12, (RESET 14), BDP 16; a 32-bit write of RDP turns DWIO on
				if (off == 3'd4 && be == 4'hF) dwio <= 1'b1;
				else begin
					if (off == 3'd4 && be[3:2] == 2'b11) csr_write(rap, {wdata[23:16], wdata[31:24]});
					if (off == 3'd4 && be[1:0] == 2'b11) rap <= wdata[14:8];
					if (off == 3'd5 && be[1:0] == 2'b11) bcr_write(rap, {wdata[7:0], wdata[15:8]});
				end
			end
			else if (be == 4'hF) begin
				// 32-bit registers: RDP 10, RAP 14, (RESET 18), BDP 1C
				case (off)
					3'd4: csr_write(rap, {wdata[23:16], wdata[31:24]});
					3'd5: rap <= wdata[30:24];
					3'd7: bcr_write(rap, {wdata[23:16], wdata[31:24]});
					default: ;
				endcase
			end
		end
		else begin
			rdata <= rv;
			if (rd_reset) s_reset <= 1'b1;
		end
	end

	// ---- the engine ----
	case (e)
		E_IDLE: begin
			if (init_req) begin
				init_req <= 1'b0;
				wi       <= 3'd0;
				if (bm_on) e <= E_INIT;
			end
			else if (strt_req) begin
				strt_req <= 1'b0;
				if (!dtx) csr0[4] <= 1'b1;                     // TXON
				if (!drx) csr0[5] <= 1'b1;                     // RXON
				csr0[1] <= 1'b1;
				csr0[2] <= 1'b0;
			end
			else if (lb_pend && bm_on) begin                   // a loopback frame comes back first
				f_lb   <= 1'b1;
				f_len  <= lb_len + 11'd4;
				f_hash <= lb_hash[31:26];
				e      <= (rxon && !drx) ? E_RX : E_RXDROP;
			end
			else if ((tdmd_b || poll_due) && txon && bm_on && !tx_busy) begin
				poll_due <= 1'b0;
				e        <= E_TX;
			end
			else if (rx_ready && bm_on) begin
				f_lb   <= 1'b0;
				f_len  <= rx_len_m;
				f_hash <= rx_hash_m;
				e      <= (rxon && !drx && !stop_b) ? E_RX : E_RXDROP;   // nowhere to put it: dropped
			end
			else if (tdmd_b && !txon) csr0[3] <= 1'b0;
		end

		E_DMA: begin
			if (!dm_req) dm_req <= 1'b1;
			else if (dm_ack) begin
				dm_req <= 1'b0;
				drd    <= dm_rdata;
				if (dm_err) begin
					// a master abort: MERR, and the engine drops what it was doing
					set_ma    <= 1'b1;
					csr0[11]  <= 1'b1;
					gathering <= 1'b0;
					e <= (e_ret >= E_RX) ? E_RXDROP : E_IDLE;
				end
				else e <= e_ret;
			end
		end

		// ---- the init block: 7 words ----
		E_INIT: begin
			da <= {csr2, csr1} + {27'd0, wi, 2'b00};
			dwe <= 1'b0; dbe <= 8'hFF; e_ret <= E_INIT_N; e <= E_DMA;
		end
		E_INIT_N: begin
			iw[wi] <= le32(drd, da[2]);
			if (wi != 3'd6) begin wi <= wi + 3'd1; e <= E_INIT; end
			else begin
				if (ss32) begin
					csr15    <= iw[0][15:0];
					rlen_c   <= iw[0][23:20];
					tlen_c   <= iw[0][31:28];
					rlen     <= iw[0][23:20] < 4'd9 ? 10'(10'd1 << iw[0][23:20]) : 10'd512;
					tlen     <= iw[0][31:28] < 4'd9 ? 10'(10'd1 << iw[0][31:28]) : 10'd512;
					padr_r[0] <= iw[1][15:0]; padr_r[1] <= iw[1][31:16]; padr_r[2] <= iw[2][15:0];
					ladrf    <= {iw[4], iw[3]};
					rdra     <= iw[5];
					tdra     <= le32(drd, da[2]);                   // (word 6: this one)
				end
				else begin
					csr15    <= iw[0][15:0];
					padr_r[0] <= iw[0][31:16]; padr_r[1] <= iw[1][15:0]; padr_r[2] <= iw[1][31:16];
					ladrf    <= {iw[3], iw[2]};
					rlen_c   <= {1'b0, iw[4][31:29]};
					tlen_c   <= {1'b0, iw[5][31:29]};
					rlen     <= 10'(10'd1 << iw[4][31:29]);
					tlen     <= 10'(10'd1 << iw[5][31:29]);
					rdra     <= {csr2[15:8], iw[4][23:0]};
					tdra     <= {csr2[15:8], iw[5][23:0]};
				end
				rx_idx    <= 9'd0;
				tx_idx    <= 9'd0;
				gathering <= 1'b0;
				csr0[8]   <= 1'b1;                             // IDON
				csr0[0]   <= 1'b1;
				csr0[2]   <= 1'b0;
				padr_ok   <= 1'b1;
				e         <= E_IDLE;
			end
		end

		// ---- transmit: the current descriptor's words ----
		E_TX: begin
			desc_a <= tdra + 32'(tx_idx) * 32'(dsz);
			wi     <= 3'd0;
			e      <= E_TXD;
		end
		E_TXD: begin
			da <= desc_a + {27'd0, wi, 2'b00}; dwe <= 1'b0; dbe <= 8'hFF; e_ret <= E_TXD_N; e <= E_DMA;
		end
		E_TXD_N: begin
			case (wi)
				3'd0:    dw0 <= le32(drd, da[2]);
				3'd1:    dw1 <= le32(drd, da[2]);
				default: dw2 <= le32(drd, da[2]);
			endcase
			if (wi != d_last) begin wi <= wi + 3'd1; e <= E_TXD; end
			else e <= E_TXOWN;
		end
		E_TXOWN: begin
			if (!d_own) begin
				// nothing (more) to send: a frame cut short is dropped
				gathering <= 1'b0;
				csr0[3]   <= 1'b0;                              // TDMD done
				e         <= E_IDLE;
			end
			else begin
				if (d_status[9]) begin                          // STP: a new frame
					gathering <= 1'b1;
					f_len     <= 11'd0;
					crc       <= 32'hFFFF_FFFF;
				end
				b_a    <= d_badr;
				b_left <= d_blen;
				err_d  <= 1'b0;
				e      <= (gathering || d_status[9]) ? E_TXB : E_TXSTAT;
			end
		end
		// the buffer, a doubleword at a time, its bytes into the transmit buffer
		E_TXB: begin
			if (b_left == 13'd0) e <= E_TXSTAT;
			else begin da <= b_a; dwe <= 1'b0; dbe <= 8'hFF; e_ret <= E_TXCP; e <= E_DMA; end
		end
		E_TXCP: begin
			if (b_left == 13'd0) e <= E_TXSTAT;
			else begin
				if (f_len != 11'h7FF) begin                     // (a frame longer than the buffer is cut)
					txb_we <= 1'b1;
					txb_wa <= f_len;
					txb_d  <= drd[63 - 8 * b_a[2:0] -: 8];
					f_len  <= f_len + 11'd1;
					crc    <= crc8(crc, drd[63 - 8 * b_a[2:0] -: 8]);
					if (f_len == 11'd5) crc_h <= crc8(crc, drd[63 - 8 * b_a[2:0] -: 8]);
				end
				b_a    <= b_a + 32'd1;
				b_left <= b_left - 13'd1;
				if (b_a[2:0] == 3'd7 && b_left != 13'd1) e <= E_TXB;    // the next doubleword
			end
		end
		// the descriptor back to the driver (OWN clear)
		E_TXSTAT: begin
			dwe <= 1'b1; e_ret <= E_TXNEXT; e <= E_DMA;
			if (swstyle == 8'd0) begin
				da <= desc_a + 32'd3; dbe <= be8(desc_a + 32'd3); dwd <= {8{1'b0, err_d, dw0[29:24]}};
			end
			else begin
				da <= desc_a + 32'd6; dbe <= be16(desc_a + 32'd6);
				dwd <= {4{d_status[7:0], 1'b0, err_d, d_status[13:8]}};
			end
		end
		E_TXNEXT: begin
			tx_idx <= (tx_idx == 9'(tlen - 10'd1)) ? 9'd0 : tx_idx + 9'd1;
			if (!tokintd || (ltinten && d_status[12])) csr0[9] <= 1'b1;     // TINT
			if (d_status[8] && gathering) begin                // ENP: the frame is whole
				gathering <= 1'b0;
				csr4[3]   <= 1'b1;                              // TXSTRT
				if (loop_m) begin
					lb_pend <= 1'b1;
					lb_len  <= f_len;
					lb_fcs  <= ~crc;
					lb_hash <= crc_h;
				end
				else begin
					tx_len <= f_len;
					tx_t   <= ~tx_t;
				end
				e <= E_IDLE;                                    // (TDMD stays until the ring has no more)
			end
			else e <= E_TX;                                     // the frame's next buffer, or the next frame
		end

		// ---- receive: the destination address (6 bytes), then the filter ----
		E_RX: begin
			f_pos <= 11'd0;
			rd_a  <= 11'd0;
			e     <= E_RXF;
		end
		E_RXF: e <= E_RXF_N;                                   // (the buffer takes the address)
		E_RXF_N: begin
			dst   <= {dst[39:0], rx_byte};
			f_pos <= f_pos + 11'd1;
			rd_a  <= f_pos + 11'd1;
			e     <= (f_pos == 11'd5) ? E_RXFILT : E_RXF;
		end
		E_RXFILT: begin
			is_pa <= !drcvpa && dst == padr;
			is_bc <= !drcvbc && dst == 48'hFFFF_FFFF_FFFF;
			is_la <= dst[40] && ladrf[f_hash];
			f_pos <= 11'd0;
			if (!(prom_m || (!drcvpa && dst == padr) || (!drcvbc && dst == 48'hFFFF_FFFF_FFFF) || (dst[40] && ladrf[f_hash])))
				e <= E_RXDROP;
			else begin
				first_d <= 1'b1;
				desc_a  <= rdra + 32'(rx_idx) * 32'(dsz);
				wi      <= 3'd0;
				e       <= E_RXD;
			end
		end
		// the descriptor's words
		E_RXD: begin
			da <= desc_a + {27'd0, wi, 2'b00}; dwe <= 1'b0; dbe <= 8'hFF; e_ret <= E_RXD_N; e <= E_DMA;
		end
		E_RXD_N: begin
			case (wi)
				3'd0:    dw0 <= le32(drd, da[2]);
				3'd1:    dw1 <= le32(drd, da[2]);
				default: dw2 <= le32(drd, da[2]);
			endcase
			if (wi != d_last) begin wi <= wi + 3'd1; e <= E_RXD; end
			else e <= E_RXOWN;
		end
		E_RXOWN: begin
			if (!d_own) begin
				if (first_d) begin                              // no buffer: missed
					csr0[12] <= 1'b1;
					csr112   <= csr112 + 16'd1;
					e        <= E_RXDROP;
				end
				else e <= E_RXOVF;                              // the frame overflows its buffers
			end
			else begin
				b_a    <= d_badr;
				b_left <= d_blen;
				acc_be <= 8'h00;
				e      <= E_RXCP;
			end
		end
		// the frame's bytes into the buffer: a doubleword filled a byte at a time, then written
		E_RXCP: begin
			if (b_left == 13'd0 || f_pos == f_len) e <= E_RXBUF;
			else begin rd_a <= f_pos; e <= E_RXCP_W; end
		end
		E_RXCP_W: e <= E_RXCP_D;                               // (the buffer takes the address)
		E_RXCP_D: begin
			acc[63 - 8 * b_a[2:0] -: 8] <= rx_byte;
			acc_be <= acc_be | (8'b1000_0000 >> b_a[2:0]);
			f_pos  <= f_pos + 11'd1;
			b_a    <= b_a + 32'd1;
			b_left <= b_left - 13'd1;
			if (b_a[2:0] == 3'd7 || b_left == 13'd1 || f_pos + 11'd1 == f_len) begin
				// the doubleword is full, or the buffer or the frame ends: write it
				da     <= b_a;
				dwe    <= 1'b1;
				dbe    <= acc_be | (8'b1000_0000 >> b_a[2:0]);
				dwd    <= acc;
				dwd[63 - 8 * b_a[2:0] -: 8] <= rx_byte;
				acc_be <= 8'h00;
				e_ret  <= E_RXCP;
				e      <= E_DMA;
			end
			else e <= E_RXCP;
		end
		E_RXBUF: e <= (f_pos != f_len) ? E_RXMORE : E_RXLAST;
		// a buffer filled with more of the frame to come: the descriptor back (STP if the first), then the next
		E_RXMORE: begin
			dwe <= 1'b1; e_ret <= E_RXDONE; e <= E_DMA;
			if (swstyle == 8'd0) begin
				da <= desc_a + 32'd3; dbe <= be8(desc_a + 32'd3); dwd <= {8{6'd0, first_d, 1'b0}};
			end
			else begin
				da <= desc_a + 32'd6; dbe <= be16(desc_a + 32'd6);
				dwd <= {4{8'h00, 6'd0, first_d, 1'b0}};
			end
		end
		// the frame's last buffer: its message length (with the FCS), then the status
		E_RXLAST: begin
			dwe <= 1'b1; e_ret <= E_RXSTAT; e <= E_DMA;
			if (swstyle == 8'd0) begin
				da <= desc_a + 32'd6; dbe <= be16(desc_a + 32'd6);
				dwd <= {4{f_len[7:0], 5'd0, f_len[10:8]}};
			end
			else begin
				da  <= (swstyle == 8'd3) ? desc_a : desc_a + 32'd8;
				dbe <= be32((swstyle == 8'd3) ? desc_a : desc_a + 32'd8);
				dwd <= {2{f_len[7:0], 5'd0, f_len[10:8], 16'h0000}};
			end
		end
		E_RXSTAT: begin
			dwe <= 1'b1; e_ret <= E_RXDONE; e <= E_DMA;
			if (swstyle == 8'd0) begin
				da <= desc_a + 32'd3; dbe <= be8(desc_a + 32'd3); dwd <= {8{6'd0, first_d, 1'b1}};
			end
			else begin
				da <= desc_a + 32'd6; dbe <= be16(desc_a + 32'd6);
				dwd <= {4{1'b0, is_pa, is_la, is_bc, 4'h0, 6'd0, first_d, 1'b1}};
			end
		end
		E_RXDONE: begin
			prev_a     <= desc_a;
			prev_first <= first_d;
			rx_idx     <= (rx_idx == 9'(rlen - 10'd1)) ? 9'd0 : rx_idx + 9'd1;
			if (f_pos != f_len) begin                           // the frame goes on in the next descriptor
				first_d <= 1'b0;
				desc_a  <= rdra + 32'(9'((rx_idx == 9'(rlen - 10'd1)) ? 9'd0 : rx_idx + 9'd1)) * 32'(dsz);
				wi      <= 3'd0;
				e       <= E_RXD;
			end
			else begin
				csr0[10] <= 1'b1;                               // RINT
				e        <= E_RXDROP;
			end
		end
		// no buffer for the rest of the frame: the last one written says so (ERR, OFLO, BUFF)
		E_RXOVF: begin
			dwe <= 1'b1; e_ret <= E_RXDROP; e <= E_DMA;
			csr0[10] <= 1'b1;
			if (swstyle == 8'd0) begin
				da <= prev_a + 32'd3; dbe <= be8(prev_a + 32'd3); dwd <= {8{2'b01, 2'b01, 2'b01, prev_first, 1'b0}};
			end
			else begin
				da <= prev_a + 32'd6; dbe <= be16(prev_a + 32'd6);
				dwd <= {4{8'h00, 2'b01, 2'b01, 2'b01, prev_first, 1'b0}};
			end
		end
		E_RXDROP: begin                                        // the frame is done with
			if (f_lb) lb_pend <= 1'b0;
			else      rx_take_t <= ~rx_take_t;
			e <= E_IDLE;
		end
		default: e <= E_IDLE;
	endcase

	// ---- resets ----
	if (s_reset || reset) begin
		rap <= 7'd0; dwio <= 1'b0;
		csr0 <= 16'h0004; csr3 <= 16'h0; csr4 <= 16'h0115; csr5 <= 16'h0; csr112 <= 16'h0;
		csr15 <= reset ? 16'h0 : (csr15 & 16'h21C4);
		ladrf <= 64'd0;
		padr_r[0] <= {aprom_mac[39:32], aprom_mac[47:40]};
		padr_r[1] <= {aprom_mac[23:16], aprom_mac[31:24]};
		padr_r[2] <= {aprom_mac[7:0], aprom_mac[15:8]};
		rlen <= 10'd1; tlen <= 10'd1; rx_idx <= 9'd0; tx_idx <= 9'd0;
		rdra <= 32'd0; tdra <= 32'd0;
		gathering <= 1'b0; init_req <= 1'b0; strt_req <= 1'b0; lb_pend <= 1'b0; poll_due <= 1'b0;
		dm_req <= 1'b0; e <= E_IDLE;
		padr_ok <= 1'b0;
	end
	if (reset) begin
		bcr2 <= 16'h0002; bcr4 <= 16'h00C0; bcr5 <= 16'h0084; bcr6 <= 16'h0088; bcr7 <= 16'h0090;
		bcr9 <= 16'h0; bcr19 <= 16'h0002; bcr22 <= 16'hFF06;
		swstyle <= 8'd0; ssize32 <= 1'b0;
		aprom_w <= 1'b0;
		csr1 <= 16'h0; csr2 <= 16'h0; csr47 <= 16'h0;
		tx_t <= tx_done_s[2];
		rx_take_t <= rx_post_s[2];
	end
end

endmodule
