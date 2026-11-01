`include "pcie_brg_def.svh"

module pcie_brg#(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter CQ_DWORD_ALIGN = 1,
    parameter CC_DWORD_ALIGN = 1,
    parameter RQ_DWORD_ALIGN = 1,
    parameter RC_DWORD_ALIGN = 1,
    parameter CQ_STRADDLE = 0,
    parameter CC_STRADDLE = 0,
    parameter RQ_STRADDLE = 0,
    parameter RC_STRADDLE = 0,
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter MSI_EN = 1,
    parameter MSIX_EN = 1,
    parameter XMIT_MSG_EN = 1,
    parameter RECV_MSG_EN = 1,
    parameter LEGACY_DEVICE = 0,
    parameter EP_MODE = 1
) (
    input  logic core_clk,
    input  logic core_clk2,
    input  logic core_rst,
    output logic user_clk,
    output logic user_rst,

    pcie_cq_if.mst pcie_cq,
    pcie_cc_if.slv pcie_cc,
    pcie_rq_if.slv pcie_rq,
    pcie_rc_if.mst pcie_rc,
    cfg_mgmt_if.slv cfg_mgmt,
    cfg_status_if.mst cfg_status,
    cfg_recv_msg_if.mst cfg_recv_msg,
    cfg_xmit_msg_if.slv cfg_xmit_msg,
    cfg_fc_if.mst cfg_fc,
    cfg_ctrl_if.slv cfg_ctrl,
    cfg_legacy_int_if.slv cfg_legacy_int,
    cfg_msi_int_if.slv cfg_msi_int,
    cfg_msix_int_if.slv cfg_msix_int,

    core_tl_rx_if.slv core_tl_rx,
    core_tl_tx_if.mst core_tl_tx,
    core_tl_cfg_if.mst core_tl_cfg,
    core_tl_int_if.mst core_tl_int,
    core_tl_cfg_msix_if.slv core_tl_cfg_msix,
    core_tl_access_if.slv core_tl_access,
    core_phy_ltssm_if.slv core_phy_ltssm
);

localparam WIDTH_CONV = (DATA_WIDTH != CORE_DATA_WIDTH) ? 1 : 0;
localparam WIDTH_CONV_BUF_DEPTH = 2;
localparam CQ_STRADDLE_INT = (DATA_WIDTH == 512) & CQ_DWORD_ALIGN & CQ_STRADDLE;
localparam CC_STRADDLE_INT = (DATA_WIDTH == 512) & CC_DWORD_ALIGN & CC_STRADDLE;
localparam RQ_STRADDLE_INT = (DATA_WIDTH == 512) & RQ_DWORD_ALIGN & RQ_STRADDLE;
localparam RC_STRADDLE_INT = (DATA_WIDTH == 512) & RC_DWORD_ALIGN & RC_STRADDLE;

logic ari_cap;

logic [95:0] core_tl_tx_credits;
logic [VF_NUM-1:0] core_tl_msix_vf_enable;
logic [VF_NUM-1:0] core_tl_msix_vf_mask;
logic [7:0] bus_num;
logic [4:0] dev_num;

logic ur_np_tlp_rdy;
logic ur_np_tlp_vld;
pcie_tlp_header_t ur_np_tlp_header;

logic [1:0] pl_equ_phase;
logic pl_ltssm_enable;
logic [4:0] pl_ltssm;
logic [4:0] tl_ltssm;
logic pl_link_up;

assign ari_cap = 1'b1;

// clock and reset
logic core_clk2_int;
logic core_rst_int;
logic [31:0] core_rst_sync;
logic [3:0] user_rst_sync;

assign core_clk2_int = WIDTH_CONV ? core_clk2 : core_clk;
assign core_rst_int = core_rst_sync[31];
assign user_clk = WIDTH_CONV ? core_clk2 : core_clk;
assign user_rst = user_rst_sync[3];

always_ff @(posedge core_clk or posedge core_rst) begin
    if (core_rst)
        core_rst_sync <= 32'hffff_ffff;
    else
        core_rst_sync <= {core_rst_sync[30:0], 1'b0};
end

always_ff @(posedge user_clk) begin
    if (core_rst_int)
        user_rst_sync <= 4'hf;
    else
        user_rst_sync <= {user_rst_sync[2:0], 1'b0};
end

assign pl_equ_phase = core_phy_ltssm.pl_equ_phase;
assign core_phy_ltssm.pl_ltssm_enable = pl_ltssm_enable;
assign pl_ltssm = core_phy_ltssm.pl_ltssm;
assign tl_ltssm = core_phy_ltssm.tl_ltssm;
assign pl_link_up = core_phy_ltssm.pl_link_up;

pcie_brg_cfg_mgmt#(
    .SYNC_CLOCK(SYNC_CLOCK && !WIDTH_CONV),
    .PF_NUM(PF_NUM),
    .VF_NUM(VF_NUM),
    .EP_MODE(EP_MODE)
) pcie_brg_cfg_mgmt(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_rst(core_rst_int),

    .cfg_mgmt(cfg_mgmt),
    .core_tl_cfg(core_tl_cfg)
);

pcie_brg_cfg_status#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .VF_NUM(VF_NUM)
) pcie_brg_cfg_status(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_rst(core_rst_int),

    .core_tl_access(core_tl_access),
    .pl_equ_phase(pl_equ_phase),
    .tl_ltssm(tl_ltssm),
    .pl_link_up(pl_link_up),
    .core_tl_tx_credits(core_tl_tx_credits),

    .cfg_status(cfg_status),
    .core_tl_msix_vf_enable(core_tl_msix_vf_enable),
    .core_tl_msix_vf_mask(core_tl_msix_vf_mask),
    .bus_num(bus_num),
    .dev_num(dev_num)
);

pcie_brg_cfg_flow_ctrl #(
    .SYNC_CLOCK(SYNC_CLOCK)
) pcie_brg_cfg_flow_ctrl(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_rst(core_rst_int),

    .core_tl_tx_credits(core_tl_tx_credits),
    .cfg_fc(cfg_fc)
);

pcie_brg_cfg_ctrl#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .PF_NUM(PF_NUM),
    .VF_NUM(VF_NUM),
    .EP_MODE(EP_MODE)
) pcie_brg_cfg_ctrl(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_rst(core_rst_int),

    .cfg_ctrl(cfg_ctrl),
    .pl_ltssm_enable(pl_ltssm_enable),
    .bus_num(bus_num),
    .dev_num(dev_num)
);

pcie_brg_tx#(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_DATA_WIDTH(CORE_DATA_WIDTH),
    .WIDTH_CONV(WIDTH_CONV),
    .WIDTH_CONV_BUF_DEPTH(WIDTH_CONV_BUF_DEPTH),
    .RQ_DWORD_ALIGN(RQ_DWORD_ALIGN),
    .CC_DWORD_ALIGN(CC_DWORD_ALIGN),
    .RQ_STRADDLE(RQ_STRADDLE_INT),
    .CC_STRADDLE(CC_STRADDLE_INT),
    .PF_NUM(PF_NUM),
    .VF_NUM(VF_NUM),
    .MSI_EN(MSI_EN),
    .MSIX_EN(MSIX_EN),
    .XMIT_MSG_EN(XMIT_MSG_EN)
) pcie_brg_tx(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_clk2(core_clk2_int),
    .core_rst(core_rst_int),

    .pcie_rq(pcie_rq),
    .pcie_cc(pcie_cc),
    .cfg_xmit_msg(cfg_xmit_msg),
    .cfg_legacy_int(cfg_legacy_int),
    .cfg_msi_int(cfg_msi_int),
    .cfg_msix_int(cfg_msix_int),

    .core_tl_tx(core_tl_tx),
    .core_tl_int(core_tl_int),
    .core_tl_cfg_msix(core_tl_cfg_msix),
    .core_tl_tx_credits(core_tl_tx_credits),
    .core_tl_msix_vf_enable(core_tl_msix_vf_enable),
    .core_tl_msix_vf_mask(core_tl_msix_vf_mask),

    .ari_cap(ari_cap),
    .bus_num(bus_num),
    .dev_num(dev_num),

    .ur_np_tlp_rdy(ur_np_tlp_rdy),
    .ur_np_tlp_vld(ur_np_tlp_vld),
    .ur_np_tlp_header(ur_np_tlp_header)
);

pcie_brg_rx #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_DATA_WIDTH(CORE_DATA_WIDTH),
    .WIDTH_CONV(WIDTH_CONV),
    .WIDTH_CONV_BUF_DEPTH(WIDTH_CONV_BUF_DEPTH),
    .CQ_DWORD_ALIGN(CQ_DWORD_ALIGN),
    .RC_DWORD_ALIGN(RC_DWORD_ALIGN),
    .CQ_STRADDLE(CQ_STRADDLE_INT),
    .RC_STRADDLE(RC_STRADDLE_INT),
    .PF_NUM(PF_NUM),
    .RECV_MSG_EN(RECV_MSG_EN),
    .LEGACY_DEVICE(LEGACY_DEVICE),
    .EP_MODE(EP_MODE)
) pcie_brg_rx(
    .user_clk(user_clk),
    .user_rst(user_rst),
    .core_clk(core_clk),
    .core_clk2(core_clk2_int),
    .core_rst(core_rst_int),

    .core_tl_rx(core_tl_rx),
    .cfg_recv_msg(cfg_recv_msg),
    .pcie_cq(pcie_cq),
    .pcie_rc(pcie_rc),

    .ur_np_tlp_rdy(ur_np_tlp_rdy),
    .ur_np_tlp_vld(ur_np_tlp_vld),
    .ur_np_tlp_header(ur_np_tlp_header)
);

endmodule
