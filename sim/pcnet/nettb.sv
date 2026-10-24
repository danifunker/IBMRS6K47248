// the PCnet's wire end to end: IBMRS6K7248_pcnet, IBMRS6K7248_enetbox and IBMRS6K7248_ddrarb on a DDR3 model
module nettb (
	input  logic        clk, clk_m, reset,
	// the PCnet's bus side, as tb_pcnet drives it
	input  logic        cfg_sel, cfg_we, input logic [7:2] cfg_reg, input logic [3:0] cfg_be, input logic [31:0] cfg_wdata,
	output logic [31:0] cfg_rdata,
	input  logic        sel, we, input logic [4:2] off, input logic [3:0] be, input logic [31:0] wdata,
	output logic [31:0] rdata, output logic irq,
	output logic        dm_req, dm_we, output logic [31:3] dm_addr, output logic [7:0] dm_be, output logic [63:0] dm_wdata,
	input  logic        dm_ack, dm_err, input logic [63:0] dm_rdata,
	// the DDRAM port
	input  logic        ddr_busy, output logic [7:0] ddr_burstcnt, output logic [28:0] ddr_addr,
	input  logic [63:0] ddr_dout, input logic ddr_dout_ready, output logic ddr_rd, output logic [63:0] ddr_din,
	output logic [7:0]  ddr_be, output logic ddr_we,
	// a stand-in for the picture side: a burst read now and then
	input  logic        v_rd, input logic [28:0] v_addr, output logic v_busy, output logic v_dout_ready
);
logic tx_pend, tx_done, rx_free, rx_we, rx_post, padr_ok;
logic [10:0] tx_len, tx_a, rx_a, rx_len; logic [7:0] tx_q, rx_d; logic [5:0] rx_hash; logic [47:0] aprom_mac, padr;
logic nb_req, nb_we, nb_ack; logic [12:0] nb_addr; logic [63:0] nb_wdata, nb_rdata;
IBMRS6K7248_pcnet pcnet (.clk, .reset, .cfg_sel, .cfg_we, .cfg_reg, .cfg_be, .cfg_wdata, .cfg_rdata, .io_on(), .io_base(),
	.sel, .we, .off, .be, .wdata, .rdata, .irq, .dm_req, .dm_we, .dm_addr, .dm_be, .dm_wdata, .dm_ack, .dm_err, .dm_rdata,
	.clk_m, .tx_pend, .tx_len, .m_tx_a(tx_a), .m_tx_q(tx_q), .m_tx_done(tx_done), .rx_free, .m_rx_we(rx_we), .m_rx_a(rx_a),
	.m_rx_d(rx_d), .m_rx_post(rx_post), .m_rx_len(rx_len), .m_rx_hash(rx_hash), .aprom_mac, .padr, .padr_ok);
IBMRS6K7248_enetbox #(.CLK_HZ(100_000_000), .POLL(500), .MACPOLL(5000)) enetbox (.clk(clk_m), .reset, .ena(1'b1),
	.tx_pend, .tx_len, .m_tx_a(tx_a), .m_tx_q(tx_q), .m_tx_done(tx_done), .rx_free, .m_rx_we(rx_we), .m_rx_a(rx_a), .m_rx_d(rx_d),
	.m_rx_post(rx_post), .m_rx_len(rx_len), .m_rx_hash(rx_hash), .aprom_mac, .padr, .padr_ok,
	.nb_req, .nb_we, .nb_addr, .nb_wdata, .nb_ack, .nb_rdata);
IBMRS6K7248_ddrarb ddrarb (.clk(clk_m), .reset,
	.a_busy(v_busy), .a_burstcnt(8'd16), .a_addr(v_addr), .a_dout(), .a_dout_ready(v_dout_ready), .a_rd(v_rd), .a_din(64'd0),
	.a_be(8'hFF), .a_we(1'b0),
	.nb_req, .nb_we, .nb_addr, .nb_wdata, .nb_ack, .nb_rdata,
	.ddr_busy, .ddr_burstcnt, .ddr_addr, .ddr_dout, .ddr_dout_ready, .ddr_rd, .ddr_din, .ddr_be, .ddr_we);
endmodule
