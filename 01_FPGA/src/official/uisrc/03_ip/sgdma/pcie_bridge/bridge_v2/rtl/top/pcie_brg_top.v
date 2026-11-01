module pcie_brg_top#(
    parameter LANE_WIDTH     = 8,
    parameter USER_CLK_FREQ  = 250,
    parameter DATA_WIDTH     = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter CQ_DWORD_ALIGN = 1,
    parameter CC_DWORD_ALIGN = 1,
    parameter RQ_DWORD_ALIGN = 1,
    parameter RC_DWORD_ALIGN = 1,
    parameter CQ_STRADDLE    = 0,
    parameter CC_STRADDLE    = 0,
    parameter RQ_STRADDLE    = 0,
    parameter RC_STRADDLE    = 0,
    parameter MSI_EN         = 1,
    parameter MSIX_EN        = 0,
    parameter XMIT_MSG_EN    = 0,
    parameter RECV_MSG_EN    = 0,
    parameter LEGACY_DEVICE  = 0,
    parameter EP_MODE        = 1,
    // ph2 hxt
    parameter PH2_SRAM_HXT_FILE = "pcie_brg_pcie_core_hxt_sram.hex",
    parameter PH2_CSR_HXT_FILE  = "pcie_brg_pcie_core_hxt_csr.hex",
    // do not modify below
    parameter CQ_USER_WIDTH  = (DATA_WIDTH == 512) ? 183 : 88,
    parameter CC_USER_WIDTH  = (DATA_WIDTH == 512) ? 81 : 33,
    parameter RQ_USER_WIDTH  = (DATA_WIDTH == 512) ? 137 : 62,
    parameter RC_USER_WIDTH  = (DATA_WIDTH == 512) ? 161 : 75,
    parameter PF_NUM         = 4,
    parameter VF_NUM         = 252,
    parameter PF_NUM_BITS    = $clog2(PF_NUM)
) (
    output [LANE_WIDTH-1:0]    pcie_tx_n,
    output [LANE_WIDTH-1:0]    pcie_tx_p,
    input  [LANE_WIDTH-1:0]    pcie_rx_n,
    input  [LANE_WIDTH-1:0]    pcie_rx_p,
    input                      pcie_clk_p,
    input                      pcie_clk_n,
    input                      pcie_rstn,
    input                      pll_lock,
    input                      init_clk,
    input                      core_clk,
    input                      core_clk2,
    output                     user_clk,
    output                     user_rst,
    // cq
    output [DATA_WIDTH-1:0]    m_axis_cq_tdata,
    output [CQ_USER_WIDTH-1:0] m_axis_cq_tuser,
    output                     m_axis_cq_tlast,
    output [DATA_WIDTH/32-1:0] m_axis_cq_tkeep,
    output                     m_axis_cq_tvalid,
    input                      m_axis_cq_tready,
    input  [1:0]               pcie_cq_np_req,
    output [5:0]               pcie_cq_np_req_count,
    // cc
    input  [DATA_WIDTH-1:0]    s_axis_cc_tdata,
    input  [CC_USER_WIDTH-1:0] s_axis_cc_tuser,
    input                      s_axis_cc_tlast,
    input  [DATA_WIDTH/32-1:0] s_axis_cc_tkeep,
    input                      s_axis_cc_tvalid,
    output [3:0]               s_axis_cc_tready,
    // rq
    input  [DATA_WIDTH-1:0]    s_axis_rq_tdata,
    input  [RQ_USER_WIDTH-1:0] s_axis_rq_tuser,
    input                      s_axis_rq_tlast,
    input  [DATA_WIDTH/32-1:0] s_axis_rq_tkeep,
    input                      s_axis_rq_tvalid,
    output [3:0]               s_axis_rq_tready,
    output [5:0]               pcie_rq_seq_num0,
    output [5:0]               pcie_rq_seq_num1,
    output                     pcie_rq_seq_num_vld0,
    output                     pcie_rq_seq_num_vld1,
    // rc
    output [DATA_WIDTH-1:0]    m_axis_rc_tdata,
    output [RC_USER_WIDTH-1:0] m_axis_rc_tuser,
    output                     m_axis_rc_tlast,
    output [DATA_WIDTH/32-1:0] m_axis_rc_tkeep,
    output                     m_axis_rc_tvalid,
    input                      m_axis_rc_tready,
    // cfg mgmt
    input  [9:0]               cfg_mgmt_addr,
    input  [7:0]               cfg_mgmt_function_number,
    input                      cfg_mgmt_write,
    input  [31:0]              cfg_mgmt_write_data,
    input  [3:0]               cfg_mgmt_byte_enable,
    input                      cfg_mgmt_read,
    output [31:0]              cfg_mgmt_read_data,
    output                     cfg_mgmt_read_write_done,
    input                      cfg_mgmt_debug_access,
    // cfg status
    output                     cfg_phy_link_down,
    output [1:0]               cfg_phy_link_status,
    output [2:0]               cfg_negotiated_width,
    output [1:0]               cfg_current_speed,
    output [2:0]               cfg_max_payload,
    output [2:0]               cfg_max_read_req,
    output [15:0]              cfg_function_status,
    output [503:0]             cfg_vf_status,
    output [11:0]              cfg_function_power_state,
    output [755:0]             cfg_vf_power_state,
    output [1:0]               cfg_link_power_state,
    output [4:0]               cfg_local_error_out,
    output                     cfg_local_error_valid,
    output [1:0]               cfg_rx_pm_state,
    output [1:0]               cfg_tx_pm_state,
    output [5:0]               cfg_ltssm_state,
    output [3:0]               cfg_rcb_status,
    output [3:0]               cfg_dpa_substate_change,
    output [1:0]               cfg_obff_enable,
    output                     cfg_pl_status_change,
    output [3:0]               cfg_tph_requester_enable,
    output [11:0]              cfg_tph_st_mode,
    output [251:0]             cfg_vf_tph_requester_enable,
    output [755:0]             cfg_vf_tph_st_mode,
    output [3:0]               pcie_tfc_nph_av,
    output [3:0]               pcie_tfc_npd_av,
    // recv msg
    output                     cfg_msg_received,
    output [7:0]               cfg_msg_received_data,
    output [4:0]               cfg_msg_received_type,
    // xmit msg
    input                      cfg_msg_transmit,
    input  [2:0]               cfg_msg_transmit_type,
    input  [31:0]              cfg_msg_transmit_data,
    output                     cfg_msg_transmit_done,
    // flow ctrl
    output [7:0]               cfg_fc_ph,
    output [11:0]              cfg_fc_pd,
    output [7:0]               cfg_fc_nph,
    output [11:0]              cfg_fc_npd,
    output [7:0]               cfg_fc_cplh,
    output [11:0]              cfg_fc_cpld,
    // ctrl
    input                      cfg_link_training_enable,
    output [7:0]               cfg_bus_number,
    output [4:0]               cfg_dev_number,
    // legacy int
    input  [3:0]               cfg_interrupt_int,
    output                     cfg_interrupt_sent,
    input  [PF_NUM-1:0]        cfg_interrupt_pending,
    // msi int
    output [PF_NUM-1:0]        cfg_interrupt_msi_enable,
    input  [31:0]              cfg_interrupt_msi_int,
    input  [7:0]               cfg_interrupt_msi_function_number,
    output                     cfg_interrupt_msi_sent,
    output                     cfg_interrupt_msi_fail,
    output [PF_NUM*3-1:0]      cfg_interrupt_msi_mmenable,
    input  [31:0]              cfg_interrupt_msi_pending_status,
    input  [PF_NUM_BITS-1:0]   cfg_interrupt_msi_pending_status_function_number,
    input                      cfg_interrupt_msi_pending_status_data_enable,
    output                     cfg_interrupt_msi_mask_update,
    input  [PF_NUM_BITS-1:0]   cfg_interrupt_msi_select,
    output [31:0]              cfg_interrupt_msi_data,
    input  [2:0]               cfg_interrupt_msi_attr,
    input                      cfg_interrupt_msi_tph_present,
    input  [1:0]               cfg_interrupt_msi_tph_type,
    input  [31:0]              cfg_interrupt_msi_tph_st_tag,
    // msix int
    output [PF_NUM-1:0]        cfg_interrupt_msix_enable,
    output [PF_NUM-1:0]        cfg_interrupt_msix_mask,
    output [VF_NUM-1:0]        cfg_interrupt_msix_vf_enable,
    output [VF_NUM-1:0]        cfg_interrupt_msix_vf_mask,
    input  [63:0]              cfg_interrupt_msix_addr,
    input  [31:0]              cfg_interrupt_msix_data,
    input                      cfg_interrupt_msix_int,
    input  [1:0]               cfg_interrupt_msix_vec_pending,
    output                     cfg_interrupt_msix_vec_pending_status
);

// clock and reset
wire                     core_rst;
wire                     pipe_clk;
wire                     tl_clk_locked;
// tl rx
wire                     tl_rx_sop;
wire                     tl_rx_eop;
wire [CORE_DATA_WIDTH-1:0]    tl_rx_data;
wire [CORE_DATA_WIDTH/32-1:0] tl_rx_valid;
wire [47:0]              tl_rx_bardec;
wire [PF_NUM+7:0]        tl_rx_mchit;
wire [7:0]               tl_rx_err;
wire                     tl_rx_masknp;
wire                     tl_rx_wait;
// tl tx
wire                     tl_tx_sop;
wire                     tl_tx_eop;
wire [CORE_DATA_WIDTH-1:0]    tl_tx_data;
wire [CORE_DATA_WIDTH/32-1:0] tl_tx_valid;
wire [7:0]               tl_tx_err;
wire                     tl_tx_stream;
wire                     tl_tx_wait;
wire [95:0]              tl_tx_credits;
// tl cfg
wire                     tl_cfg_prst;
wire                     tl_cfg_penable;
wire                     tl_cfg_psel;
wire                     tl_cfg_pwrite;
wire [2:0]               tl_cfg_pprot;
wire [31:0]              tl_cfg_paddr;
wire [3:0]               tl_cfg_pstrb;
wire [31:0]              tl_cfg_pwdata;
wire                     tl_cfg_pready;
wire [31:0]              tl_cfg_prdata;
wire                     tl_cfg_pslverr;
// tl int
wire [PF_NUM-1:0]        tl_int_status;
wire [PF_NUM-1:0]        tl_int_msireq;
wire [PF_NUM*5-1:0]      tl_int_msinum;
wire [PF_NUM-1:0]        tl_int_msiack;
wire [3:0]               tl_int_pinstate;
wire [3:0]               tl_int_pincontrol;
wire [PF_NUM-1:0]        tl_int_msi_enable;
wire [PF_NUM*3-1:0]      tl_int_msi_multi_enable;
wire [PF_NUM*32-1:0]     tl_int_pf_msi_pending;
wire [PF_NUM*32-1:0]     tl_int_pf_msi_mask;
wire                     tl_int_vfmsireq;
wire [4:0]               tl_int_vfmsinum;
wire [15:0]              tl_int_vfmsifid;
wire                     tl_int_vfmsiack;
wire [7:0]               tl_int_vfmsi_enable_mask_sel;
wire [2:0]               tl_int_vfmsi_enable;
wire [31:0]              tl_int_vfmsi_mask;
// tl cfg msix
wire [PF_NUM-1:0]        tl_cfg_msix_enable;
wire [PF_NUM-1:0]        tl_cfg_msix_function_mask;
// tl access
wire [7:0]               tl_cfg_tcvc;
wire [12:0]              tl_cfg_busdev;
wire [2:0]               tl_cfg_max_payload_size;
wire [2:0]               tl_cfg_max_read_request_size;
wire [2:0]               tl_cfg_current_link_speed;
wire [3:0]               tl_cfg_negotiated_width;
wire                     tl_cfg_read_completion_boundary;
wire [PF_NUM*9-1:0]      tl_cfg_pfregs_vfnums;
wire [PF_NUM-1:0]        tl_cfg_pfregs_vfenable;
wire [PF_NUM-1:0]        tl_cfg_pfregs_vfmse;
wire [PF_NUM*4-1:0]      tl_cfg_pfregs_cmd;
wire [2:0]               tl_cfg_vfregs_bit_sel;
wire [255:0]             tl_cfg_vfregs_bit;
wire [7:0]               tl_cfg_pf0_primary_bus;
wire [7:0]               tl_cfg_pf1_primary_bus;
wire [7:0]               tl_cfg_pf2_primary_bus;
wire [7:0]               tl_cfg_pf3_primary_bus;
// phy ltssm
wire [1:0]               pl_equ_phase;
wire                     pl_ltssm_enable;
wire [4:0]               pl_ltssm;
wire [4:0]               tl_ltssm;
wire                     pl_link_up;
// debug
wire [255:0]             test_out_tl;
wire [255:0]             test_out_pl;

pcie_brg_wrapper#(
    .DATA_WIDTH(DATA_WIDTH),
    .CORE_DATA_WIDTH(CORE_DATA_WIDTH),
    .CQ_DWORD_ALIGN(CQ_DWORD_ALIGN),
    .CC_DWORD_ALIGN(CC_DWORD_ALIGN),
    .RQ_DWORD_ALIGN(RQ_DWORD_ALIGN),
    .RC_DWORD_ALIGN(RC_DWORD_ALIGN),
    .CQ_STRADDLE(CQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE),
    .RQ_STRADDLE(RQ_STRADDLE),
    .RC_STRADDLE(RC_STRADDLE),
    .PF_NUM(PF_NUM),
    .VF_NUM(VF_NUM),
    .MSI_EN(MSI_EN),
    .MSIX_EN(MSIX_EN),
    .XMIT_MSG_EN(XMIT_MSG_EN),
    .RECV_MSG_EN(RECV_MSG_EN),
    .LEGACY_DEVICE(LEGACY_DEVICE),
    .EP_MODE(EP_MODE)
) pcie_brg_wrapper(
    .core_clk(core_clk),
    .core_clk2(core_clk2),
    .core_rst(~(pll_lock & tl_clk_locked)),
    .user_clk(user_clk),
    .user_rst(user_rst),
    // cq
    .m_axis_cq_tdata(m_axis_cq_tdata),
    .m_axis_cq_tuser(m_axis_cq_tuser),
    .m_axis_cq_tlast(m_axis_cq_tlast),
    .m_axis_cq_tkeep(m_axis_cq_tkeep),
    .m_axis_cq_tvalid(m_axis_cq_tvalid),
    .m_axis_cq_tready(m_axis_cq_tready),
    .pcie_cq_np_req(pcie_cq_np_req),
    .pcie_cq_np_req_count(pcie_cq_np_req_count),
    // cc
    .s_axis_cc_tdata(s_axis_cc_tdata),
    .s_axis_cc_tuser(s_axis_cc_tuser),
    .s_axis_cc_tlast(s_axis_cc_tlast),
    .s_axis_cc_tkeep(s_axis_cc_tkeep),
    .s_axis_cc_tvalid(s_axis_cc_tvalid),
    .s_axis_cc_tready(s_axis_cc_tready),
    // rq
    .s_axis_rq_tdata(s_axis_rq_tdata),
    .s_axis_rq_tuser(s_axis_rq_tuser),
    .s_axis_rq_tlast(s_axis_rq_tlast),
    .s_axis_rq_tkeep(s_axis_rq_tkeep),
    .s_axis_rq_tvalid(s_axis_rq_tvalid),
    .s_axis_rq_tready(s_axis_rq_tready),
    .pcie_rq_seq_num0(pcie_rq_seq_num0),
    .pcie_rq_seq_num1(pcie_rq_seq_num1),
    .pcie_rq_seq_num_vld0(pcie_rq_seq_num_vld0),
    .pcie_rq_seq_num_vld1(pcie_rq_seq_num_vld1),
    // rc
    .m_axis_rc_tdata(m_axis_rc_tdata),
    .m_axis_rc_tuser(m_axis_rc_tuser),
    .m_axis_rc_tlast(m_axis_rc_tlast),
    .m_axis_rc_tkeep(m_axis_rc_tkeep),
    .m_axis_rc_tvalid(m_axis_rc_tvalid),
    .m_axis_rc_tready(m_axis_rc_tready),
    // cfg mgmt
    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
    .cfg_mgmt_debug_access(cfg_mgmt_debug_access),
    // cfg status
    .cfg_phy_link_down(cfg_phy_link_down),
    .cfg_phy_link_status(cfg_phy_link_status),
    .cfg_negotiated_width(cfg_negotiated_width),
    .cfg_current_speed(cfg_current_speed),
    .cfg_max_payload(cfg_max_payload),
    .cfg_max_read_req(cfg_max_read_req),
    .cfg_function_status(cfg_function_status),
    .cfg_vf_status(cfg_vf_status),
    .cfg_function_power_state(cfg_function_power_state),
    .cfg_vf_power_state(cfg_vf_power_state),
    .cfg_link_power_state(cfg_link_power_state),
    .cfg_local_error_out(cfg_local_error_out),
    .cfg_local_error_valid(cfg_local_error_valid),
    .cfg_rx_pm_state(cfg_rx_pm_state),
    .cfg_tx_pm_state(cfg_tx_pm_state),
    .cfg_ltssm_state(cfg_ltssm_state),
    .cfg_rcb_status(cfg_rcb_status),
    .cfg_dpa_substate_change(cfg_dpa_substate_change),
    .cfg_obff_enable(cfg_obff_enable),
    .cfg_pl_status_change(cfg_pl_status_change),
    .cfg_tph_requester_enable(cfg_tph_requester_enable),
    .cfg_tph_st_mode(cfg_tph_st_mode),
    .cfg_vf_tph_requester_enable(cfg_vf_tph_requester_enable),
    .cfg_vf_tph_st_mode(cfg_vf_tph_st_mode),
    .pcie_tfc_nph_av(pcie_tfc_nph_av),
    .pcie_tfc_npd_av(pcie_tfc_npd_av),
    // recv msg
    .cfg_msg_received(cfg_msg_received),
    .cfg_msg_received_data(cfg_msg_received_data),
    .cfg_msg_received_type(cfg_msg_received_type),
    // xmit msg
    .cfg_msg_transmit(cfg_msg_transmit),
    .cfg_msg_transmit_type(cfg_msg_transmit_type),
    .cfg_msg_transmit_data(cfg_msg_transmit_data),
    .cfg_msg_transmit_done(cfg_msg_transmit_done),
    // flow ctrl
    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    // ctrl
    .cfg_link_training_enable(cfg_link_training_enable),
    .cfg_bus_number(cfg_bus_number),
    .cfg_dev_number(cfg_dev_number),
    // legacy int
    .cfg_interrupt_int(cfg_interrupt_int),
    .cfg_interrupt_sent(cfg_interrupt_sent),
    .cfg_interrupt_pending(cfg_interrupt_pending),
    // msi int
    .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),
    .cfg_interrupt_msi_int(cfg_interrupt_msi_int),
    .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),
    .cfg_interrupt_msi_sent(cfg_interrupt_msi_sent),
    .cfg_interrupt_msi_fail(cfg_interrupt_msi_fail),
    .cfg_interrupt_msi_mmenable(cfg_interrupt_msi_mmenable),
    .cfg_interrupt_msi_pending_status(cfg_interrupt_msi_pending_status),
    .cfg_interrupt_msi_pending_status_function_number(cfg_interrupt_msi_pending_status_function_number),
    .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),
    .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),
    .cfg_interrupt_msi_select(cfg_interrupt_msi_select),
    .cfg_interrupt_msi_data(cfg_interrupt_msi_data),
    .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),
    .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),
    .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),
    .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),
    // msix int
    .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
    .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
    .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),
    .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),
    .cfg_interrupt_msix_addr(cfg_interrupt_msix_addr),
    .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
    .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
    .cfg_interrupt_msix_vec_pending(cfg_interrupt_msix_vec_pending),
    .cfg_interrupt_msix_vec_pending_status(cfg_interrupt_msix_vec_pending_status),
    // tl rx
    .tl_rx_sop(tl_rx_sop),
    .tl_rx_eop(tl_rx_eop),
    .tl_rx_data(tl_rx_data),
    .tl_rx_valid(tl_rx_valid),
    .tl_rx_bardec(tl_rx_bardec),
    .tl_rx_mchit(tl_rx_mchit),
    .tl_rx_err(tl_rx_err),
    .tl_rx_masknp(tl_rx_masknp),
    .tl_rx_wait(tl_rx_wait),
    // tl tx
    .tl_tx_sop(tl_tx_sop),
    .tl_tx_eop(tl_tx_eop),
    .tl_tx_data(tl_tx_data),
    .tl_tx_valid(tl_tx_valid),
    .tl_tx_err(tl_tx_err),
    .tl_tx_stream(tl_tx_stream),
    .tl_tx_wait(tl_tx_wait),
    .tl_tx_credits(tl_tx_credits),
    // tl cfg
    .tl_cfg_prst(tl_cfg_prst),
    .tl_cfg_penable(tl_cfg_penable),
    .tl_cfg_psel(tl_cfg_psel),
    .tl_cfg_pwrite(tl_cfg_pwrite),
    .tl_cfg_pprot(tl_cfg_pprot),
    .tl_cfg_paddr(tl_cfg_paddr),
    .tl_cfg_pstrb(tl_cfg_pstrb),
    .tl_cfg_pwdata(tl_cfg_pwdata),
    .tl_cfg_pready(tl_cfg_pready),
    .tl_cfg_prdata(tl_cfg_prdata),
    .tl_cfg_pslverr(tl_cfg_pslverr),
    // tl int
    .tl_int_status(tl_int_status),
    .tl_int_msireq(tl_int_msireq),
    .tl_int_msinum(tl_int_msinum),
    .tl_int_msiack(tl_int_msiack),
    .tl_int_pinstate(tl_int_pinstate),
    .tl_int_pincontrol(tl_int_pincontrol),
    .tl_int_msi_enable(tl_int_msi_enable),
    .tl_int_msi_multi_enable(tl_int_msi_multi_enable),
    .tl_int_pf_msi_pending(tl_int_pf_msi_pending),
    .tl_int_pf_msi_mask(tl_int_pf_msi_mask),
    .tl_int_vfmsireq(tl_int_vfmsireq),
    .tl_int_vfmsinum(tl_int_vfmsinum),
    .tl_int_vfmsifid(tl_int_vfmsifid),
    .tl_int_vfmsiack(tl_int_vfmsiack),
    .tl_int_vfmsi_enable_mask_sel(tl_int_vfmsi_enable_mask_sel),
    .tl_int_vfmsi_enable(tl_int_vfmsi_enable),
    .tl_int_vfmsi_mask(tl_int_vfmsi_mask),
    // tl cfg msix
    .tl_cfg_msix_enable(tl_cfg_msix_enable),
    .tl_cfg_msix_function_mask(tl_cfg_msix_function_mask),
    // tl access
    .tl_cfg_tcvc(tl_cfg_tcvc),
    .tl_cfg_busdev(tl_cfg_busdev),
    .tl_cfg_max_payload_size(tl_cfg_max_payload_size),
    .tl_cfg_max_read_request_size(tl_cfg_max_read_request_size),
    .tl_cfg_current_link_speed(tl_cfg_current_link_speed),
    .tl_cfg_negotiated_width(tl_cfg_negotiated_width),
    .tl_cfg_read_completion_boundary(tl_cfg_read_completion_boundary),
    .tl_cfg_pfregs_vfnums(tl_cfg_pfregs_vfnums),
    .tl_cfg_pfregs_vfenable(tl_cfg_pfregs_vfenable),
    .tl_cfg_pfregs_vfmse(tl_cfg_pfregs_vfmse),
    .tl_cfg_pfregs_cmd(tl_cfg_pfregs_cmd),
    .tl_cfg_vfregs_bit_sel(tl_cfg_vfregs_bit_sel),
    .tl_cfg_vfregs_bit(tl_cfg_vfregs_bit),
    .tl_cfg_pf0_primary_bus(tl_cfg_pf0_primary_bus),
    .tl_cfg_pf1_primary_bus(tl_cfg_pf1_primary_bus),
    .tl_cfg_pf2_primary_bus(tl_cfg_pf2_primary_bus),
    .tl_cfg_pf3_primary_bus(tl_cfg_pf3_primary_bus),
    // phy ltssm
    .pl_equ_phase(pl_equ_phase),
    .pl_ltssm_enable(pl_ltssm_enable),
    .pl_ltssm(pl_ltssm),
    .tl_ltssm(tl_ltssm),
    .pl_link_up(pl_link_up)
);

generate
    if (MSIX_EN) begin: pcie_core_msix
        pcie_brg_pcie_core#(
            .PH2_SRAM_HXT_FILE(PH2_SRAM_HXT_FILE)                      ,
            .PH2_CSR_HXT_FILE (PH2_CSR_HXT_FILE)
        ) pcie_brg_pcie_core(
            // serdes high speed pin
            .ref_pad_clk_p(pcie_clk_p)                           ,
            .ref_pad_clk_n(pcie_clk_n)                           ,
            .pcie_rx_p(pcie_rx_p)                               ,
            .pcie_rx_n(pcie_rx_n)                               ,
            .pcie_tx_p(pcie_tx_p)                               ,
            .pcie_tx_n(pcie_tx_n)                               ,
            // transcation layer clock signals
            .tl_clk_user(core_clk)                             ,
            .tl_clk_locked(tl_clk_locked)                           ,
            // clock and reset signals
            .tl_clk_gate()                             ,
            .tl_clk_user_freq(USER_CLK_FREQ)                        ,
            .tl_power_on_rst(~pcie_rstn)                         ,
            // user apb configure signals
            .tl_cfg_penable(tl_cfg_penable)                          ,
            .tl_cfg_psel(tl_cfg_psel)                             ,
            .tl_cfg_pwrite(tl_cfg_pwrite)                           ,
            .tl_cfg_pprot(tl_cfg_pprot)                            ,
            .tl_cfg_paddr(tl_cfg_paddr)                            ,
            .tl_cfg_pstrb(tl_cfg_pstrb)                            ,
            .tl_cfg_pwdata(tl_cfg_pwdata)                           ,
            .tl_cfg_pready(tl_cfg_pready)                           ,
            .tl_cfg_prdata(tl_cfg_prdata)                           ,
            .tl_cfg_pslverr(tl_cfg_pslverr)                          ,
            // cfg direct access
            .tl_cfg_tcvc(tl_cfg_tcvc)                             ,
            .tl_cfg_busdev(tl_cfg_busdev)                           ,
            .tl_cfg_max_payload_size(tl_cfg_max_payload_size)                 ,
            .tl_cfg_max_read_request_size(tl_cfg_max_read_request_size)            ,
            .tl_cfg_current_link_speed(tl_cfg_current_link_speed)               ,
            .tl_cfg_negotiated_width(tl_cfg_negotiated_width)                 ,
            .tl_cfg_read_completion_boundary(tl_cfg_read_completion_boundary)         ,
            .tl_cfg_pfregs_cmd(tl_cfg_pfregs_cmd)                       ,
            .tl_cfg_pf0_primary_bus(tl_cfg_pf0_primary_bus)                  ,
            .tl_cfg_pf1_primary_bus(tl_cfg_pf1_primary_bus)                  ,
            .tl_cfg_pf2_primary_bus(tl_cfg_pf2_primary_bus)                  ,
            .tl_cfg_pf3_primary_bus(tl_cfg_pf3_primary_bus)                  ,
            // vf
            .tl_cfg_vfregs_bit_sel(tl_cfg_vfregs_bit_sel)                   ,
            .tl_cfg_vfregs_bit(tl_cfg_vfregs_bit)                       ,
            .tl_cfg_pfregs_vfnums(tl_cfg_pfregs_vfnums)                    ,
            .tl_cfg_pfregs_vfenable(tl_cfg_pfregs_vfenable)                  ,
            .tl_cfg_pfregs_vfmse(tl_cfg_pfregs_vfmse)                     ,
            // pf msi-x
            .tl_cfg_msix_enable(tl_cfg_msix_enable)                      ,
            .tl_cfg_msix_function_mask(tl_cfg_msix_function_mask)               ,
            // physical ltssm signals
            .pl_equ_phase(pl_equ_phase)                            ,
            .tl_ltssm(tl_ltssm)                                ,
            .pl_ltssm(pl_ltssm)                                ,
            .pl_link_up(pl_link_up)                              ,
            .tl_ltssm_enable(pl_ltssm_enable)                         ,
            // PM legacy/native
            .pl_wake_in(0)                              ,
            .tl_pm_auxpwr(0)                            ,
            .tl_pm_data(0)                              ,
            .tl_pm_event(0)                             ,
            .tl_pm_lx_control(0)                        ,
            .pl_wake_oen()                             ,
            .tl_pm_lx_status()                         ,
            // Report
            .tl_report_error_10_1_bits(0)               ,
            .tl_report_error_22_12_bits(0)              ,
            .tl_report_error_63_40_bits(0)              ,
            .tl_report_header(0)                        ,
            .tl_report_hotplug(0)                       ,
            .tl_report_latency(0)                       ,
            .tl_report_state_pf0_misc_control(0)        ,
            .tl_report_state_pf1_misc_control(0)        ,
            .tl_report_state_pf2_misc_control(0)        ,
            .tl_report_state_pf3_misc_control(0)        ,
            .tl_report_event()                         ,
            .tl_report_vfstate_override_sel(0)          ,
            .tl_report_vfstate_override_bit(0)          ,
            .pinshare_grp0_out_sel(0)                   ,
            .pinshare_grp1_out_sel(0)                   ,
            // Debug
            .pl_pclk_user(pipe_clk)                            ,
            .pclk_deskew_cal_lock()                    ,
            .pclk_deskew_lock()                        ,
            .test_out_tl(test_out_tl)                             ,
            .test_out_pl(test_out_pl)                             ,
            //
            .hxt_apb4_pclk_in(init_clk)                        ,
            // Rx interface
            .tl_rx_wait(tl_rx_wait)                              ,
            .tl_rx_masknp(tl_rx_masknp)                            ,
            .tl_rx_bardec(tl_rx_bardec)                            ,
            .tl_rx_data(tl_rx_data)                              ,
            .tl_rx_eop(tl_rx_eop)                               ,
            .tl_rx_err(tl_rx_err)                               ,
            .tl_rx_mchit(tl_rx_mchit)                             ,
            .tl_rx_sop(tl_rx_sop)                               ,
            .tl_rx_valid(tl_rx_valid)                             ,
            // TX interface
            .tl_tx_data(tl_tx_data)                              ,
            .tl_tx_eop(tl_tx_eop)                               ,
            .tl_tx_err(tl_tx_err)                               ,
            .tl_tx_sop(tl_tx_sop)                               ,
            .tl_tx_stream(tl_tx_stream)                            ,
            .tl_tx_valid(tl_tx_valid)                             ,
            .tl_tx_wait(tl_tx_wait)                              ,
            .tl_tx_credits(tl_tx_credits)
        );
    end else if (MSI_EN) begin: pcie_core_msi
        pcie_brg_pcie_core#(
            .PH2_SRAM_HXT_FILE(PH2_SRAM_HXT_FILE)                      ,
            .PH2_CSR_HXT_FILE (PH2_CSR_HXT_FILE)
        ) pcie_brg_pcie_core(
            // serdes high speed pin
            .ref_pad_clk_p(pcie_clk_p)                           ,
            .ref_pad_clk_n(pcie_clk_n)                           ,
            .pcie_rx_p(pcie_rx_p)                               ,
            .pcie_rx_n(pcie_rx_n)                               ,
            .pcie_tx_p(pcie_tx_p)                               ,
            .pcie_tx_n(pcie_tx_n)                               ,
            // transcation layer clock signals
            .tl_clk_user(core_clk)                             ,
            .tl_clk_locked(tl_clk_locked)                           ,
            // clock and reset signals
            .tl_clk_gate()                             ,
            .tl_clk_user_freq(USER_CLK_FREQ)                        ,
            .tl_power_on_rst(~pcie_rstn)                         ,
            // user apb configure signals
            .tl_cfg_penable(tl_cfg_penable)                          ,
            .tl_cfg_psel(tl_cfg_psel)                             ,
            .tl_cfg_pwrite(tl_cfg_pwrite)                           ,
            .tl_cfg_pprot(tl_cfg_pprot)                            ,
            .tl_cfg_paddr(tl_cfg_paddr)                            ,
            .tl_cfg_pstrb(tl_cfg_pstrb)                            ,
            .tl_cfg_pwdata(tl_cfg_pwdata)                           ,
            .tl_cfg_pready(tl_cfg_pready)                           ,
            .tl_cfg_prdata(tl_cfg_prdata)                           ,
            .tl_cfg_pslverr(tl_cfg_pslverr)                          ,
            // cfg direct access
            .tl_cfg_tcvc(tl_cfg_tcvc)                             ,
            .tl_cfg_busdev(tl_cfg_busdev)                           ,
            .tl_cfg_max_payload_size(tl_cfg_max_payload_size)                 ,
            .tl_cfg_max_read_request_size(tl_cfg_max_read_request_size)            ,
            .tl_cfg_current_link_speed(tl_cfg_current_link_speed)               ,
            .tl_cfg_negotiated_width(tl_cfg_negotiated_width)                 ,
            .tl_cfg_read_completion_boundary(tl_cfg_read_completion_boundary)         ,
            .tl_cfg_pfregs_cmd(tl_cfg_pfregs_cmd)                       ,
            .tl_cfg_pf0_primary_bus(tl_cfg_pf0_primary_bus)                  ,
            .tl_cfg_pf1_primary_bus(tl_cfg_pf1_primary_bus)                  ,
            .tl_cfg_pf2_primary_bus(tl_cfg_pf2_primary_bus)                  ,
            .tl_cfg_pf3_primary_bus(tl_cfg_pf3_primary_bus)                  ,
            // vf
            .tl_cfg_vfregs_bit_sel(tl_cfg_vfregs_bit_sel)                   ,
            .tl_cfg_vfregs_bit(tl_cfg_vfregs_bit)                       ,
            .tl_cfg_pfregs_vfnums(tl_cfg_pfregs_vfnums)                    ,
            .tl_cfg_pfregs_vfenable(tl_cfg_pfregs_vfenable)                  ,
            .tl_cfg_pfregs_vfmse(tl_cfg_pfregs_vfmse)                     ,
            // pf msi int
            .tl_int_status(tl_int_status)                           ,
            .tl_int_msireq(tl_int_msireq)                           ,
            .tl_int_msinum(tl_int_msinum)                           ,
            .tl_int_msiack(tl_int_msiack)                           ,
            .tl_int_msi_enable(tl_int_msi_enable)                       ,
            .tl_int_msi_multi_enable(tl_int_msi_multi_enable)                 ,
            .tl_int_pf0_msi_pending(tl_int_pf_msi_pending[32*0+:32])                  ,
            .tl_int_pf1_msi_pending(tl_int_pf_msi_pending[32*1+:32])                  ,
            .tl_int_pf2_msi_pending(tl_int_pf_msi_pending[32*2+:32])                  ,
            .tl_int_pf3_msi_pending(tl_int_pf_msi_pending[32*3+:32])                  ,
            .tl_int_pf0_msi_mask(tl_int_pf_msi_mask[32*0+:32])                     ,
            .tl_int_pf1_msi_mask(tl_int_pf_msi_mask[32*1+:32])                     ,
            .tl_int_pf2_msi_mask(tl_int_pf_msi_mask[32*2+:32])                     ,
            .tl_int_pf3_msi_mask(tl_int_pf_msi_mask[32*3+:32])                     ,
            // vf msi
            .tl_int_vfmsifid(tl_int_vfmsifid)                         ,
            .tl_int_vfmsinum(tl_int_vfmsinum)                         ,
            .tl_int_vfmsireq(tl_int_vfmsireq)                         ,
            .tl_int_vfmsiack(tl_int_vfmsiack)                         ,
            .tl_int_vfmsi_enable_mask_sel(tl_int_vfmsi_enable_mask_sel)            ,
            .tl_int_vfmsi_enable(tl_int_vfmsi_enable)                     ,
            .tl_int_vfmsi_mask(tl_int_vfmsi_mask)                       ,
            // physical ltssm signals
            .pl_equ_phase(pl_equ_phase)                            ,
            .tl_ltssm(tl_ltssm)                                ,
            .pl_ltssm(pl_ltssm)                                ,
            .pl_link_up(pl_link_up)                              ,
            .tl_ltssm_enable(pl_ltssm_enable)                         ,
            // PM legacy/native
            .pl_wake_in(0)                              ,
            .tl_pm_auxpwr(0)                            ,
            .tl_pm_data(0)                              ,
            .tl_pm_event(0)                             ,
            .tl_pm_lx_control(0)                        ,
            .pl_wake_oen()                             ,
            .tl_pm_lx_status()                         ,
            // Report
            .tl_report_error_10_1_bits(0)               ,
            .tl_report_error_22_12_bits(0)              ,
            .tl_report_error_63_40_bits(0)              ,
            .tl_report_header(0)                        ,
            .tl_report_hotplug(0)                       ,
            .tl_report_latency(0)                       ,
            .tl_report_state_pf0_misc_control(0)        ,
            .tl_report_state_pf1_misc_control(0)        ,
            .tl_report_state_pf2_misc_control(0)        ,
            .tl_report_state_pf3_misc_control(0)        ,
            .tl_report_event()                         ,
            .tl_report_vfstate_override_sel(0)          ,
            .tl_report_vfstate_override_bit(0)          ,
            .pinshare_grp0_out_sel(0)                   ,
            .pinshare_grp1_out_sel(0)                   ,
            // Debug
            .pl_pclk_user(pipe_clk)                            ,
            .pclk_deskew_cal_lock()                    ,
            .pclk_deskew_lock()                        ,
            .test_out_tl(test_out_tl)                             ,
            .test_out_pl(test_out_pl)                             ,
            //
            .hxt_apb4_pclk_in(init_clk)                        ,
            // Rx interface
            .tl_rx_wait(tl_rx_wait)                              ,
            .tl_rx_masknp(tl_rx_masknp)                            ,
            .tl_rx_bardec(tl_rx_bardec)                            ,
            .tl_rx_data(tl_rx_data)                              ,
            .tl_rx_eop(tl_rx_eop)                               ,
            .tl_rx_err(tl_rx_err)                               ,
            .tl_rx_mchit(tl_rx_mchit)                             ,
            .tl_rx_sop(tl_rx_sop)                               ,
            .tl_rx_valid(tl_rx_valid)                             ,
            // TX interface
            .tl_tx_data(tl_tx_data)                              ,
            .tl_tx_eop(tl_tx_eop)                               ,
            .tl_tx_err(tl_tx_err)                               ,
            .tl_tx_sop(tl_tx_sop)                               ,
            .tl_tx_stream(tl_tx_stream)                            ,
            .tl_tx_valid(tl_tx_valid)                             ,
            .tl_tx_wait(tl_tx_wait)                              ,
            .tl_tx_credits(tl_tx_credits)
        );
    end else begin: pcie_core_intx
        pcie_brg_pcie_core#(
            .PH2_SRAM_HXT_FILE(PH2_SRAM_HXT_FILE)                      ,
            .PH2_CSR_HXT_FILE (PH2_CSR_HXT_FILE)
        ) pcie_brg_pcie_core(
            // serdes high speed pin
            .ref_pad_clk_p(pcie_clk_p)                           ,
            .ref_pad_clk_n(pcie_clk_n)                           ,
            .pcie_rx_p(pcie_rx_p)                               ,
            .pcie_rx_n(pcie_rx_n)                               ,
            .pcie_tx_p(pcie_tx_p)                               ,
            .pcie_tx_n(pcie_tx_n)                               ,
            // transcation layer clock signals
            .tl_clk_user(core_clk)                             ,
            .tl_clk_locked(tl_clk_locked)                           ,
            // clock and reset signals
            .tl_clk_gate()                             ,
            .tl_clk_user_freq(USER_CLK_FREQ)                        ,
            .tl_power_on_rst(~pcie_rstn)                         ,
            // user apb configure signals
            .tl_cfg_penable(tl_cfg_penable)                          ,
            .tl_cfg_psel(tl_cfg_psel)                             ,
            .tl_cfg_pwrite(tl_cfg_pwrite)                           ,
            .tl_cfg_pprot(tl_cfg_pprot)                            ,
            .tl_cfg_paddr(tl_cfg_paddr)                            ,
            .tl_cfg_pstrb(tl_cfg_pstrb)                            ,
            .tl_cfg_pwdata(tl_cfg_pwdata)                           ,
            .tl_cfg_pready(tl_cfg_pready)                           ,
            .tl_cfg_prdata(tl_cfg_prdata)                           ,
            .tl_cfg_pslverr(tl_cfg_pslverr)                          ,
            // cfg direct access
            .tl_cfg_tcvc(tl_cfg_tcvc)                             ,
            .tl_cfg_busdev(tl_cfg_busdev)                           ,
            .tl_cfg_max_payload_size(tl_cfg_max_payload_size)                 ,
            .tl_cfg_max_read_request_size(tl_cfg_max_read_request_size)            ,
            .tl_cfg_current_link_speed(tl_cfg_current_link_speed)               ,
            .tl_cfg_negotiated_width(tl_cfg_negotiated_width)                 ,
            .tl_cfg_read_completion_boundary(tl_cfg_read_completion_boundary)         ,
            .tl_cfg_pfregs_cmd(tl_cfg_pfregs_cmd)                       ,
            .tl_cfg_pf0_primary_bus(tl_cfg_pf0_primary_bus)                  ,
            .tl_cfg_pf1_primary_bus(tl_cfg_pf1_primary_bus)                  ,
            .tl_cfg_pf2_primary_bus(tl_cfg_pf2_primary_bus)                  ,
            .tl_cfg_pf3_primary_bus(tl_cfg_pf3_primary_bus)                  ,
            // vf
            .tl_cfg_vfregs_bit_sel(tl_cfg_vfregs_bit_sel)                   ,
            .tl_cfg_vfregs_bit(tl_cfg_vfregs_bit)                       ,
            .tl_cfg_pfregs_vfnums(tl_cfg_pfregs_vfnums)                    ,
            .tl_cfg_pfregs_vfenable(tl_cfg_pfregs_vfenable)                  ,
            .tl_cfg_pfregs_vfmse(tl_cfg_pfregs_vfmse)                     ,
            // pf legacy int
            .tl_int_status(tl_int_status)                           ,
            .tl_int_pincontrol(tl_int_pincontrol)                       ,
            .tl_int_pinstate(tl_int_pinstate)                         ,
            // physical ltssm signals
            .pl_equ_phase(pl_equ_phase)                            ,
            .tl_ltssm(tl_ltssm)                                ,
            .pl_ltssm(pl_ltssm)                                ,
            .pl_link_up(pl_link_up)                              ,
            .tl_ltssm_enable(pl_ltssm_enable)                         ,
            // PM legacy/native
            .pl_wake_in(0)                              ,
            .tl_pm_auxpwr(0)                            ,
            .tl_pm_data(0)                              ,
            .tl_pm_event(0)                             ,
            .tl_pm_lx_control(0)                        ,
            .pl_wake_oen()                             ,
            .tl_pm_lx_status()                         ,
            // Report
            .tl_report_error_10_1_bits(0)               ,
            .tl_report_error_22_12_bits(0)              ,
            .tl_report_error_63_40_bits(0)              ,
            .tl_report_header(0)                        ,
            .tl_report_hotplug(0)                       ,
            .tl_report_latency(0)                       ,
            .tl_report_state_pf0_misc_control(0)        ,
            .tl_report_state_pf1_misc_control(0)        ,
            .tl_report_state_pf2_misc_control(0)        ,
            .tl_report_state_pf3_misc_control(0)        ,
            .tl_report_event()                         ,
            .tl_report_vfstate_override_sel(0)          ,
            .tl_report_vfstate_override_bit(0)          ,
            .pinshare_grp0_out_sel(0)                   ,
            .pinshare_grp1_out_sel(0)                   ,
            // Debug
            .pl_pclk_user(pipe_clk)                            ,
            .pclk_deskew_cal_lock()                    ,
            .pclk_deskew_lock()                        ,
            .test_out_tl(test_out_tl)                             ,
            .test_out_pl(test_out_pl)                             ,
            //
            .hxt_apb4_pclk_in(init_clk)                        ,
            // Rx interface
            .tl_rx_wait(tl_rx_wait)                              ,
            .tl_rx_masknp(tl_rx_masknp)                            ,
            .tl_rx_bardec(tl_rx_bardec)                            ,
            .tl_rx_data(tl_rx_data)                              ,
            .tl_rx_eop(tl_rx_eop)                               ,
            .tl_rx_err(tl_rx_err)                               ,
            .tl_rx_mchit(tl_rx_mchit)                             ,
            .tl_rx_sop(tl_rx_sop)                               ,
            .tl_rx_valid(tl_rx_valid)                             ,
            // TX interface
            .tl_tx_data(tl_tx_data)                              ,
            .tl_tx_eop(tl_tx_eop)                               ,
            .tl_tx_err(tl_tx_err)                               ,
            .tl_tx_sop(tl_tx_sop)                               ,
            .tl_tx_stream(tl_tx_stream)                            ,
            .tl_tx_valid(tl_tx_valid)                             ,
            .tl_tx_wait(tl_tx_wait)                              ,
            .tl_tx_credits(tl_tx_credits)
        );
    end
endgenerate

// debug

endmodule
