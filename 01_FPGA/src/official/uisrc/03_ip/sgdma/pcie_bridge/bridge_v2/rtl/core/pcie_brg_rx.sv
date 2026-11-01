`include "pcie_brg_def.svh"

module pcie_brg_rx #(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter WIDTH_CONV = (DATA_WIDTH != CORE_DATA_WIDTH) ? 1 : 0,
    parameter WIDTH_CONV_BUF_DEPTH = 2,
    parameter CQ_DWORD_ALIGN = 1,
    parameter RC_DWORD_ALIGN = 1,
    parameter CQ_STRADDLE = 0,
    parameter RC_STRADDLE = 0,
    parameter PF_NUM = 4,
    parameter RECV_MSG_EN = 1,
    parameter LEGACY_DEVICE = 0,
    parameter EP_MODE = 1
) (
    input  logic user_clk,
    input  logic user_rst,
    input  logic core_clk,
    input  logic core_clk2,
    input  logic core_rst,

    core_tl_rx_if.slv core_tl_rx,
    cfg_recv_msg_if.mst cfg_recv_msg,
    pcie_cq_if.mst pcie_cq,
    pcie_rc_if.mst pcie_rc,

    input  logic ur_np_tlp_rdy,
    output logic ur_np_tlp_vld,
    output pcie_tlp_header_t ur_np_tlp_header,

    output logic busy
);

localparam KEEP_WIDTH = DATA_WIDTH/32;
localparam DW_WIDTH = $clog2(KEEP_WIDTH);
localparam CFG_PF_NUM = PF_NUM;
localparam CORE_PF_NUM = PF_NUM;
localparam NP_BUF_DEPTH = 32 > (WIDTH_CONV_BUF_DEPTH * 2) ? 32 : (WIDTH_CONV_BUF_DEPTH * 2);

core_tl_rx_if#(.DATA_WIDTH(DATA_WIDTH), .PF_NUM(CORE_PF_NUM)) core_tl_rx_int();

logic tlp_vld;
logic tlp_rdy;
logic tlp_header_vld;
logic tlp_header_rdy;
pcie_tlp_header_t tlp_header;
logic [47:0] tlp_bardec;
logic [CORE_PF_NUM+7:0] tlp_mchit;
logic [KEEP_WIDTH-1:0] tlp_valid;
logic tlp_ur;
logic tlp_np;
logic tlp_msg_route;
logic tlp_is_cq;
logic tlp_eop;
logic [9-DW_WIDTH:0] tlp_cycle_m1;
logic tlp_data_rd;
logic [DATA_WIDTH-1:0] tlp_data;
logic tlp_discontinue;
logic np_dec;

logic msg_vld;
logic msg_rdy;
pcie_tlp_header_t msg_header;
logic [31:0] msg_data;
logic recv_msg_err;

logic cq_rc_tlp_vld;
logic cq_rc_tlp_rdy;
logic cq_rc_tlp_header_vld;
logic cq_rc_tlp_header_rdy;
pcie_tlp_header_t cq_rc_tlp_header;
logic [47:0] cq_rc_tlp_bardec;
logic [CORE_PF_NUM+7:0] cq_rc_tlp_mchit;
logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid;
logic cq_rc_tlp_is_cq;
logic cq_rc_tlp_is_np;
logic cq_rc_tlp_eop;
logic [9-DW_WIDTH:0] cq_rc_tlp_cycle_m1;
logic cq_rc_tlp_data_rd;
logic cq_rc_tlp_data_rd_eop;
logic [DATA_WIDTH-1:0] cq_rc_tlp_data;
logic cq_rc_tlp_discontinue;
logic cq_rc_np_mask;

logic cq_rc_tready;
logic cq_rc_tvalid;
logic cq_rc_tlast;
pcie_cq_tuser512_t cq_rc_tuser;
logic [KEEP_WIDTH-1:0] cq_rc_tkeep;
logic [DATA_WIDTH-1:0] cq_rc_tdata;
logic cq_rc_is_cq;
logic [1:0] np_req;
logic [5:0] np_req_count;

logic rx_width_conv_busy;
logic rx_dec_busy;
logic rx_demux_busy;
logic recv_msg_busy;
logic cq_rc_enc_busy;
logic cq_rc_demux_busy;

pcie_brg_rx_width_conv#(
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_DATA_WIDTH(CORE_DATA_WIDTH),
    .BUF_DEPTH(WIDTH_CONV_BUF_DEPTH),
    .CORE_PF_NUM(CORE_PF_NUM)
) pcie_brg_rx_width_conv(
    .core_clk(core_clk),
    .core_clk2(core_clk2),
    .core_rst(core_rst),

    .core_tl_rx_int(core_tl_rx_int),
    .core_tl_rx(core_tl_rx),

    .busy(rx_width_conv_busy)
);

pcie_brg_rx_dec #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH),
    .WIDTH_CONV_BUF_DEPTH(WIDTH_CONV_BUF_DEPTH),
    .CORE_PF_NUM(CORE_PF_NUM),
    .LEGACY_DEVICE(LEGACY_DEVICE),
    .EP_MODE(EP_MODE),
    .NP_BUF_DEPTH(NP_BUF_DEPTH)
) pcie_brg_rx_dec(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk2(core_clk2),
    .core_rst(core_rst),

    .tlp_vld(tlp_vld),
    .tlp_rdy(tlp_rdy),
    .tlp_header_vld(tlp_header_vld),
    .tlp_header_rdy(tlp_header_rdy),
    .tlp_header(tlp_header),
    .tlp_bardec(tlp_bardec),
    .tlp_mchit(tlp_mchit),
    .tlp_valid(tlp_valid),
    .tlp_ur(tlp_ur),
    .tlp_np(tlp_np),
    .tlp_msg_route(tlp_msg_route),
    .tlp_is_cq(tlp_is_cq),
    .tlp_eop(tlp_eop),
    .tlp_cycle_m1(tlp_cycle_m1),
    .tlp_data_rd(tlp_data_rd),
    .tlp_data(tlp_data),
    .tlp_discontinue(tlp_discontinue),
    .np_dec(np_dec),

    .core_tl_rx(core_tl_rx_int),

    .busy(rx_dec_busy)
);

pcie_brg_rx_demux #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_PF_NUM(CORE_PF_NUM),
    .RECV_MSG_EN(RECV_MSG_EN),
    .NP_BUF_DEPTH(NP_BUF_DEPTH)
) pcie_brg_rx_demux(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .tlp_vld(tlp_vld),
    .tlp_rdy(tlp_rdy),
    .tlp_header_vld(tlp_header_vld),
    .tlp_header_rdy(tlp_header_rdy),
    .tlp_header(tlp_header),
    .tlp_bardec(tlp_bardec),
    .tlp_mchit(tlp_mchit),
    .tlp_valid(tlp_valid),
    .tlp_ur(tlp_ur),
    .tlp_np(tlp_np),
    .tlp_msg_route(tlp_msg_route),
    .tlp_is_cq(tlp_is_cq),
    .tlp_eop(tlp_eop),
    .tlp_cycle_m1(tlp_cycle_m1),
    .tlp_data_rd(tlp_data_rd),
    .tlp_data(tlp_data),
    .tlp_discontinue(tlp_discontinue),
    .np_dec(np_dec),

    .ur_np_tlp_rdy(ur_np_tlp_rdy),
    .ur_np_tlp_vld(ur_np_tlp_vld),
    .ur_np_tlp_header(ur_np_tlp_header),

    .msg_vld(msg_vld),
    .msg_rdy(msg_rdy),
    .msg_header(msg_header),
    .msg_data(msg_data),

    .cq_rc_tlp_vld(cq_rc_tlp_vld),
    .cq_rc_tlp_rdy(cq_rc_tlp_rdy),
    .cq_rc_tlp_header_vld(cq_rc_tlp_header_vld),
    .cq_rc_tlp_header_rdy(cq_rc_tlp_header_rdy),
    .cq_rc_tlp_header(cq_rc_tlp_header),
    .cq_rc_tlp_bardec(cq_rc_tlp_bardec),
    .cq_rc_tlp_mchit(cq_rc_tlp_mchit),
    .cq_rc_tlp_valid(cq_rc_tlp_valid),
    .cq_rc_tlp_is_cq(cq_rc_tlp_is_cq),
    .cq_rc_tlp_is_np(cq_rc_tlp_is_np),
    .cq_rc_tlp_eop(cq_rc_tlp_eop),
    .cq_rc_tlp_cycle_m1(cq_rc_tlp_cycle_m1),
    .cq_rc_tlp_data_rd(cq_rc_tlp_data_rd),
    .cq_rc_tlp_data_rd_eop(cq_rc_tlp_data_rd_eop),
    .cq_rc_tlp_data(cq_rc_tlp_data),
    .cq_rc_tlp_discontinue(cq_rc_tlp_discontinue),
    .cq_rc_np_mask(cq_rc_np_mask),

    .busy(rx_demux_busy)
);

pcie_brg_recv_msg #(
    .RECV_MSG_EN(RECV_MSG_EN)
) pcie_brg_recv_msg(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .msg_vld(msg_vld),
    .msg_rdy(msg_rdy),
    .msg_header(msg_header),
    .msg_data(msg_data),

    .cfg_recv_msg(cfg_recv_msg),
    .recv_msg_err(recv_msg_err),

    .busy(recv_msg_busy)
);

pcie_brg_cq_rc_enc#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH),
    .CQ_DWORD_ALIGN(CQ_DWORD_ALIGN),
    .RC_DWORD_ALIGN(RC_DWORD_ALIGN),
    .CQ_STRADDLE(CQ_STRADDLE),
    .RC_STRADDLE(RC_STRADDLE),
    .CFG_PF_NUM(CFG_PF_NUM),
    .CORE_PF_NUM(CORE_PF_NUM)
) pcie_brg_cq_rc_enc(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .cq_rc_tlp_vld(cq_rc_tlp_vld),
    .cq_rc_tlp_rdy(cq_rc_tlp_rdy),
    .cq_rc_tlp_header_vld(cq_rc_tlp_header_vld),
    .cq_rc_tlp_header_rdy(cq_rc_tlp_header_rdy),
    .cq_rc_tlp_header(cq_rc_tlp_header),
    .cq_rc_tlp_bardec(cq_rc_tlp_bardec),
    .cq_rc_tlp_mchit(cq_rc_tlp_mchit),
    .cq_rc_tlp_valid(cq_rc_tlp_valid),
    .cq_rc_tlp_is_cq(cq_rc_tlp_is_cq),
    .cq_rc_tlp_is_np(cq_rc_tlp_is_np),
    .cq_rc_tlp_eop(cq_rc_tlp_eop),
    .cq_rc_tlp_cycle_m1(cq_rc_tlp_cycle_m1),
    .cq_rc_tlp_data_rd(cq_rc_tlp_data_rd),
    .cq_rc_tlp_data_rd_eop(cq_rc_tlp_data_rd_eop),
    .cq_rc_tlp_data(cq_rc_tlp_data),
    .cq_rc_tlp_discontinue(cq_rc_tlp_discontinue),
    .cq_rc_np_mask(cq_rc_np_mask),

    .cq_rc_tready(cq_rc_tready),
    .cq_rc_tvalid(cq_rc_tvalid),
    .cq_rc_tlast(cq_rc_tlast),
    .cq_rc_tuser(cq_rc_tuser),
    .cq_rc_tkeep(cq_rc_tkeep),
    .cq_rc_tdata(cq_rc_tdata),
    .cq_rc_is_cq(cq_rc_is_cq),
    .np_req(np_req),
    .np_req_count(np_req_count),

    .busy(cq_rc_enc_busy)
);

pcie_brg_cq_rc_demux#(
    .DATA_WIDTH(DATA_WIDTH),
    .CQ_STRADDLE(CQ_STRADDLE),
    .RC_STRADDLE(RC_STRADDLE)
) pcie_brg_cq_rc_demux(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .pcie_cq(pcie_cq),
    .pcie_rc(pcie_rc),

    .cq_rc_tready(cq_rc_tready),
    .cq_rc_tvalid(cq_rc_tvalid),
    .cq_rc_tlast(cq_rc_tlast),
    .cq_rc_tuser(cq_rc_tuser),
    .cq_rc_tkeep(cq_rc_tkeep),
    .cq_rc_tdata(cq_rc_tdata),
    .cq_rc_is_cq(cq_rc_is_cq),
    .np_req(np_req),
    .np_req_count(np_req_count),

    .busy(cq_rc_demux_busy)
);

assign busy = rx_width_conv_busy | rx_dec_busy | rx_demux_busy | recv_msg_busy | cq_rc_enc_busy | cq_rc_demux_busy;

endmodule
