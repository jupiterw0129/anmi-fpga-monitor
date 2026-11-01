`include "pcie_brg_def.svh"

module pcie_brg_tx#(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter WIDTH_CONV = (DATA_WIDTH != CORE_DATA_WIDTH) ? 1 : 0,
    parameter WIDTH_CONV_BUF_DEPTH = 2,
    parameter RQ_DWORD_ALIGN = 1,
    parameter CC_DWORD_ALIGN = 1,
    parameter RQ_STRADDLE = 0,
    parameter CC_STRADDLE = 0,
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter MSI_EN = 1,
    parameter MSIX_EN = 1,
    parameter XMIT_MSG_EN = 1
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_clk2,
    input logic core_rst,

    pcie_rq_if.slv pcie_rq,
    pcie_cc_if.slv pcie_cc,
    cfg_xmit_msg_if.slv cfg_xmit_msg,
    cfg_legacy_int_if.slv cfg_legacy_int,
    cfg_msi_int_if.slv cfg_msi_int,
    cfg_msix_int_if.slv cfg_msix_int,

    core_tl_tx_if.mst core_tl_tx,
    core_tl_int_if.mst core_tl_int,
    core_tl_cfg_msix_if.slv core_tl_cfg_msix,
    output logic [95:0] core_tl_tx_credits,
    input logic [VF_NUM-1:0] core_tl_msix_vf_enable,
    input logic [VF_NUM-1:0] core_tl_msix_vf_mask,

    input logic ari_cap,
    input logic [7:0] bus_num,
    input logic [4:0] dev_num,

    output logic ur_np_tlp_rdy,
    input  logic ur_np_tlp_vld,
    input  pcie_tlp_header_t ur_np_tlp_header,

    output logic busy,
    output logic [2:0] err
);

localparam KEEP_WIDTH = DATA_WIDTH/32;
localparam DW_WIDTH = $clog2(KEEP_WIDTH);
localparam CFG_PF_NUM = PF_NUM;
localparam CORE_PF_NUM = PF_NUM;

logic rq_cc_tready;
logic rq_cc_tvalid;
logic rq_cc_tlast;
pcie_rq_tuser512_t rq_cc_tuser;
logic [KEEP_WIDTH-1:0] rq_cc_tkeep;
logic [DATA_WIDTH-1:0] rq_cc_tdata;
logic rq_cc_is_rq;
logic [5:0] rq_cc_seq_num;
logic rq_cc_seq_num_vld;

logic rq_cc_tlp_rdy;
logic rq_cc_tlp_vld;
logic rq_cc_tlp_sop;
logic rq_cc_tlp_eop;
pcie_tlp_header_t rq_cc_tlp_header;
logic [DATA_WIDTH-1:0] rq_cc_tlp_data;
logic rq_cc_discontinue;
logic rq_cc_force_ecrc;
logic [5:0] rq_cc_tlp_seq_num;
logic rq_cc_tlp_is_rq;
logic rq_cc_req_type_err;
logic rq_cc_cpl_status_ur_ca;
logic rq_cc_cpl_status_err;
logic pcie_rq_seq_num_vld;
logic [5:0] pcie_rq_seq_num;

logic msix_rdy;
logic msix_vld;
pcie_tlp_header_t msix_header;
logic [31:0] msix_data;

logic xmit_msg_rdy;
logic xmit_msg_vld;
logic xmit_msg_err;
pcie_tlp_header_t xmit_msg_header;
logic [31:0] xmit_msg_data;

logic tlp_vld;
logic tlp_rdy;
logic tlp_header_vld;
logic tlp_header_rdy;
pcie_tlp_header_t tlp_header;
logic tlp_force_ecrc;
logic tlp_header_err;
logic tlp_data_rd;
logic [DATA_WIDTH-1:0] tlp_data;
logic tlp_data_discontinue;

logic rq_cc_mux_busy;
logic rq_cc_dec_busy;
logic int_busy;
logic xmit_msg_busy;
logic tx_mux_busy;
logic tx_enc_busy;
logic tx_width_conv_busy;

assign busy = rq_cc_mux_busy | rq_cc_dec_busy | int_busy | xmit_msg_busy | tx_mux_busy | tx_enc_busy | tx_width_conv_busy;
assign err = 0;//todo

core_tl_tx_if#(.DATA_WIDTH(DATA_WIDTH)) core_tl_tx_int();

pcie_brg_rq_cc_mux#(
    .DATA_WIDTH(DATA_WIDTH),
    .RQ_DWORD_ALIGN(RQ_DWORD_ALIGN),
    .CC_DWORD_ALIGN(CC_DWORD_ALIGN),
    .RQ_STRADDLE(RQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE)
) pcie_brg_rq_cc_mux(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .pcie_rq(pcie_rq),
    .pcie_cc(pcie_cc),

    .rq_cc_tready(rq_cc_tready),
    .rq_cc_tvalid(rq_cc_tvalid),
    .rq_cc_tlast(rq_cc_tlast),
    .rq_cc_tuser(rq_cc_tuser),
    .rq_cc_tkeep(rq_cc_tkeep),
    .rq_cc_tdata(rq_cc_tdata),
    .rq_cc_is_rq(rq_cc_is_rq),
    .rq_cc_seq_num(rq_cc_seq_num),
    .rq_cc_seq_num_vld(rq_cc_seq_num_vld),

    .busy(rq_cc_mux_busy)
);

pcie_brg_rq_cc_dec#(
    .DATA_WIDTH(DATA_WIDTH),
    .RQ_DWORD_ALIGN(RQ_DWORD_ALIGN),
    .CC_DWORD_ALIGN(CC_DWORD_ALIGN),
    .RQ_STRADDLE(RQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE)
) pcie_brg_rq_cc_dec(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .ari_cap(ari_cap),
    .bus_num(bus_num),
    .dev_num(dev_num),

    .rq_cc_tready(rq_cc_tready),
    .rq_cc_tvalid(rq_cc_tvalid),
    .rq_cc_tlast(rq_cc_tlast),
    .rq_cc_tuser(rq_cc_tuser),
    .rq_cc_tkeep(rq_cc_tkeep),
    .rq_cc_tdata(rq_cc_tdata),
    .rq_cc_is_rq(rq_cc_is_rq),
    .rq_cc_seq_num(rq_cc_seq_num),
    .rq_cc_seq_num_vld(rq_cc_seq_num_vld),

    .rq_cc_tlp_rdy(rq_cc_tlp_rdy),
    .rq_cc_tlp_vld(rq_cc_tlp_vld),
    .rq_cc_tlp_sop(rq_cc_tlp_sop),
    .rq_cc_tlp_eop(rq_cc_tlp_eop),
    .rq_cc_tlp_header(rq_cc_tlp_header),
    .rq_cc_tlp_data(rq_cc_tlp_data),
    .rq_cc_discontinue(rq_cc_discontinue),
    .rq_cc_force_ecrc(rq_cc_force_ecrc),
    .rq_cc_tlp_seq_num(rq_cc_tlp_seq_num),
    .rq_cc_tlp_is_rq(rq_cc_tlp_is_rq),
    .rq_cc_req_type_err(rq_cc_req_type_err),
    .rq_cc_cpl_status_ur_ca(rq_cc_cpl_status_ur_ca),
    .rq_cc_cpl_status_err(rq_cc_cpl_status_err),
    .pcie_rq_seq_num_vld(pcie_rq_seq_num_vld),
    .pcie_rq_seq_num(pcie_rq_seq_num),

    .busy(rq_cc_dec_busy)
);

pcie_brg_int#(
    .SYNC_CLOCK(SYNC_CLOCK && !WIDTH_CONV),
    .PF_NUM(PF_NUM),
    .VF_NUM(VF_NUM),
    .MSI_EN(MSI_EN),
    .MSIX_EN(MSIX_EN)
) pcie_brg_int(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_rst(core_rst),

    .ari_cap(ari_cap),
    .bus_num(bus_num),
    .dev_num(dev_num),

    .cfg_legacy_int(cfg_legacy_int),
    .cfg_msi_int(cfg_msi_int),
    .cfg_msix_int(cfg_msix_int),
    .core_tl_int(core_tl_int),
    .core_tl_cfg_msix(core_tl_cfg_msix),
    .core_tl_msix_vf_enable(core_tl_msix_vf_enable),
    .core_tl_msix_vf_mask(core_tl_msix_vf_mask),

    .msix_rdy(msix_rdy),
    .msix_vld(msix_vld),
    .msix_header(msix_header),
    .msix_data(msix_data),

    .busy(int_busy)
);

pcie_brg_xmit_msg#(
    .XMIT_MSG_EN(XMIT_MSG_EN),
    .CFG_PF_NUM(CFG_PF_NUM),
    .CORE_PF_NUM(CORE_PF_NUM)
) pcie_brg_xmit_msg(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .ari_cap(ari_cap),
    .bus_num(bus_num),
    .dev_num(dev_num),
    .cfg_xmit_msg(cfg_xmit_msg),

    .xmit_msg_rdy(xmit_msg_rdy),
    .xmit_msg_vld(xmit_msg_vld),
    .xmit_msg_err(xmit_msg_err),
    .xmit_msg_header(xmit_msg_header),
    .xmit_msg_data(xmit_msg_data),

    .busy(xmit_msg_busy)
);

pcie_brg_tx_mux#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH)
) pcie_brg_tx_mux(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk2(core_clk2),
    .core_rst(core_rst),

    .bus_num(bus_num),
    .dev_num(dev_num),
    // ur tlp
    .ur_np_tlp_rdy(ur_np_tlp_rdy),
    .ur_np_tlp_vld(ur_np_tlp_vld),
    .ur_np_tlp_header(ur_np_tlp_header),
    // msix
    .msix_rdy(msix_rdy),
    .msix_vld(msix_vld),
    .msix_header(msix_header),
    .msix_data(msix_data),
    // msg
    .xmit_msg_rdy(xmit_msg_rdy),
    .xmit_msg_vld(xmit_msg_vld),
    .xmit_msg_err(xmit_msg_err),
    .xmit_msg_header(xmit_msg_header),
    .xmit_msg_data(xmit_msg_data),
    // rq cc
    .rq_cc_tlp_rdy(rq_cc_tlp_rdy),
    .rq_cc_tlp_vld(rq_cc_tlp_vld),
    .rq_cc_tlp_sop(rq_cc_tlp_sop),
    .rq_cc_tlp_eop(rq_cc_tlp_eop),
    .rq_cc_tlp_header(rq_cc_tlp_header),
    .rq_cc_tlp_data(rq_cc_tlp_data),
    .rq_cc_discontinue(rq_cc_discontinue),
    .rq_cc_force_ecrc(rq_cc_force_ecrc),
    .rq_cc_tlp_seq_num(rq_cc_tlp_seq_num),
    .rq_cc_tlp_is_rq(rq_cc_tlp_is_rq),
    .rq_cc_req_type_err(rq_cc_req_type_err),
    .rq_cc_cpl_status_ur_ca(rq_cc_cpl_status_ur_ca),
    .rq_cc_cpl_status_err(rq_cc_cpl_status_err),
    .pcie_rq_seq_num_vld(pcie_rq_seq_num_vld),
    .pcie_rq_seq_num(pcie_rq_seq_num),

    .tlp_vld(tlp_vld),
    .tlp_rdy(tlp_rdy),
    .tlp_header_vld(tlp_header_vld),
    .tlp_header_rdy(tlp_header_rdy),
    .tlp_header(tlp_header),
    .tlp_force_ecrc(tlp_force_ecrc),
    .tlp_header_err(tlp_header_err),
    .tlp_data_rd(tlp_data_rd),
    .tlp_data(tlp_data),
    .tlp_data_discontinue(tlp_data_discontinue),

    .busy(tx_mux_busy)
);

pcie_brg_tx_enc#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH)
) pcie_brg_tx_enc(
    .core_clk2(core_clk2),
    .core_rst(core_rst),
    // tlp header and data
    .tlp_vld(tlp_vld),
    .tlp_rdy(tlp_rdy),
    .tlp_header_vld(tlp_header_vld),
    .tlp_header_rdy(tlp_header_rdy),
    .tlp_header(tlp_header),
    .tlp_force_ecrc(tlp_force_ecrc),
    .tlp_header_err(tlp_header_err),
    .tlp_data_rd(tlp_data_rd),
    .tlp_data(tlp_data),
    .tlp_data_discontinue(tlp_data_discontinue),
    // core tx
    .core_tl_tx(core_tl_tx_int),
    .core_tl_tx_credits(core_tl_tx_credits),

    .busy(tx_enc_busy)
);

pcie_brg_tx_width_conv#(
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_DATA_WIDTH(CORE_DATA_WIDTH),
    .BUF_DEPTH(WIDTH_CONV_BUF_DEPTH)
) pcie_brg_tx_width_conv(
    .core_clk(core_clk),
    .core_clk2(core_clk2),
    .core_rst(core_rst),

    .core_tl_tx_int(core_tl_tx_int),
    .core_tl_tx(core_tl_tx),

    .busy(tx_width_conv_busy)
);

endmodule
