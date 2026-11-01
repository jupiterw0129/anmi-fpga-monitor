`include "pcie_brg_def.svh"

module pcie_brg_wrapper#(
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
    parameter MSI_EN = 1,
    parameter MSIX_EN = 1,
    parameter XMIT_MSG_EN = 1,
    parameter RECV_MSG_EN = 1,
    parameter LEGACY_DEVICE = 0,
    parameter EP_MODE = 1,
    // do not modify below
    parameter CQ_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_cq_tuser512_t) : $bits(pcie_cq_tuser_t),
    parameter CC_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_cc_tuser512_t) : $bits(pcie_cc_tuser_t),
    parameter RQ_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_rq_tuser512_t) : $bits(pcie_rq_tuser_t),
    parameter RC_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_rc_tuser512_t) : $bits(pcie_rc_tuser_t),
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter PF_NUM_BITS    = $clog2(PF_NUM)
) (
    input  logic                          core_clk,
    input  logic                          core_clk2,
    input  logic                          core_rst,
    output logic                          user_clk,
    output logic                          user_rst,
    // cq
    output logic [DATA_WIDTH-1:0]         m_axis_cq_tdata,
    output logic [CQ_USER_WIDTH-1:0]      m_axis_cq_tuser,
    output logic                          m_axis_cq_tlast,
    output logic [DATA_WIDTH/32-1:0]      m_axis_cq_tkeep,
    output logic                          m_axis_cq_tvalid,
    input  logic                          m_axis_cq_tready,
    input  logic [1:0]                    pcie_cq_np_req,
    output logic [5:0]                    pcie_cq_np_req_count,
    // cc
    input  logic [DATA_WIDTH-1:0]         s_axis_cc_tdata,
    input  logic [CC_USER_WIDTH-1:0]      s_axis_cc_tuser,
    input  logic                          s_axis_cc_tlast,
    input  logic [DATA_WIDTH/32-1:0]      s_axis_cc_tkeep,
    input  logic                          s_axis_cc_tvalid,
    output logic [3:0]                    s_axis_cc_tready,
    // rq
    input  logic [DATA_WIDTH-1:0]         s_axis_rq_tdata,
    input  logic [RQ_USER_WIDTH-1:0]      s_axis_rq_tuser,
    input  logic                          s_axis_rq_tlast,
    input  logic [DATA_WIDTH/32-1:0]      s_axis_rq_tkeep,
    input  logic                          s_axis_rq_tvalid,
    output logic [3:0]                    s_axis_rq_tready,
    output logic [5:0]                    pcie_rq_seq_num0,
    output logic [5:0]                    pcie_rq_seq_num1,
    output logic                          pcie_rq_seq_num_vld0,
    output logic                          pcie_rq_seq_num_vld1,
    // rc
    output logic [DATA_WIDTH-1:0]         m_axis_rc_tdata,
    output logic [RC_USER_WIDTH-1:0]      m_axis_rc_tuser,
    output logic                          m_axis_rc_tlast,
    output logic [DATA_WIDTH/32-1:0]      m_axis_rc_tkeep,
    output logic                          m_axis_rc_tvalid,
    input  logic                          m_axis_rc_tready,
    // cfg mgmt
    input  logic [9:0]                    cfg_mgmt_addr,
    input  logic [7:0]                    cfg_mgmt_function_number,
    input  logic                          cfg_mgmt_write,
    input  logic [31:0]                   cfg_mgmt_write_data,
    input  logic [3:0]                    cfg_mgmt_byte_enable,
    input  logic                          cfg_mgmt_read,
    output logic [31:0]                   cfg_mgmt_read_data,
    output logic                          cfg_mgmt_read_write_done,
    input  logic                          cfg_mgmt_debug_access,
    // cfg status
    output logic                          cfg_phy_link_down,
    output logic [1:0]                    cfg_phy_link_status,
    output logic [2:0]                    cfg_negotiated_width,
    output logic [1:0]                    cfg_current_speed,
    output logic [2:0]                    cfg_max_payload,
    output logic [2:0]                    cfg_max_read_req,
    output logic [15:0]                   cfg_function_status,
    output logic [503:0]                  cfg_vf_status,
    output logic [11:0]                   cfg_function_power_state,
    output logic [755:0]                  cfg_vf_power_state,
    output logic [1:0]                    cfg_link_power_state,
    output logic [4:0]                    cfg_local_error_out,
    output logic                          cfg_local_error_valid,
    output logic [1:0]                    cfg_rx_pm_state,
    output logic [1:0]                    cfg_tx_pm_state,
    output logic [5:0]                    cfg_ltssm_state,
    output logic [3:0]                    cfg_rcb_status,
    output logic [3:0]                    cfg_dpa_substate_change,
    output logic [1:0]                    cfg_obff_enable,
    output logic                          cfg_pl_status_change,
    output logic [3:0]                    cfg_tph_requester_enable,
    output logic [11:0]                   cfg_tph_st_mode,
    output logic [251:0]                  cfg_vf_tph_requester_enable,
    output logic [755:0]                  cfg_vf_tph_st_mode,
    output logic [3:0]                    pcie_tfc_nph_av,
    output logic [3:0]                    pcie_tfc_npd_av,
    // recv msg
    output logic                          cfg_msg_received,
    output logic [7:0]                    cfg_msg_received_data,
    output logic [4:0]                    cfg_msg_received_type,
    // xmit msg
    input  logic                          cfg_msg_transmit,
    input  logic [2:0]                    cfg_msg_transmit_type,
    input  logic [31:0]                   cfg_msg_transmit_data,
    output logic                          cfg_msg_transmit_done,
    // flow ctrl
    output logic [7:0]                    cfg_fc_ph,
    output logic [11:0]                   cfg_fc_pd,
    output logic [7:0]                    cfg_fc_nph,
    output logic [11:0]                   cfg_fc_npd,
    output logic [7:0]                    cfg_fc_cplh,
    output logic [11:0]                   cfg_fc_cpld,
    // ctrl
    input  logic                          cfg_link_training_enable,
    output logic [7:0]                    cfg_bus_number,
    output logic [4:0]                    cfg_dev_number,
    // legacy int
    input  logic [3:0]                    cfg_interrupt_int,
    output logic                          cfg_interrupt_sent,
    input  logic [PF_NUM-1:0]             cfg_interrupt_pending,
    // msi int
    output logic [PF_NUM-1:0]             cfg_interrupt_msi_enable,
    input  logic [31:0]                   cfg_interrupt_msi_int,
    input  logic [7:0]                    cfg_interrupt_msi_function_number,
    output logic                          cfg_interrupt_msi_sent,
    output logic                          cfg_interrupt_msi_fail,
    output logic [PF_NUM*3-1:0]           cfg_interrupt_msi_mmenable,
    input  logic [31:0]                   cfg_interrupt_msi_pending_status,
    input  logic [PF_NUM_BITS-1:0]        cfg_interrupt_msi_pending_status_function_number,
    input  logic                          cfg_interrupt_msi_pending_status_data_enable,
    output logic                          cfg_interrupt_msi_mask_update,
    input  logic [PF_NUM_BITS-1:0]        cfg_interrupt_msi_select,
    output logic [31:0]                   cfg_interrupt_msi_data,
    input  logic [2:0]                    cfg_interrupt_msi_attr,
    input  logic                          cfg_interrupt_msi_tph_present,
    input  logic [1:0]                    cfg_interrupt_msi_tph_type,
    input  logic [31:0]                   cfg_interrupt_msi_tph_st_tag,
    // msix int
    output logic [PF_NUM-1:0]             cfg_interrupt_msix_enable,
    output logic [PF_NUM-1:0]             cfg_interrupt_msix_mask,
    output logic [VF_NUM-1:0]             cfg_interrupt_msix_vf_enable,
    output logic [VF_NUM-1:0]             cfg_interrupt_msix_vf_mask,
    input  logic [63:0]                   cfg_interrupt_msix_addr,
    input  logic [31:0]                   cfg_interrupt_msix_data,
    input  logic                          cfg_interrupt_msix_int,
    input  logic [1:0]                    cfg_interrupt_msix_vec_pending,
    output logic                          cfg_interrupt_msix_vec_pending_status,
    // tl rx
    input  logic                          tl_rx_sop,
    input  logic                          tl_rx_eop,
    input  logic [CORE_DATA_WIDTH-1:0]    tl_rx_data,
    input  logic [CORE_DATA_WIDTH/32-1:0] tl_rx_valid,
    input  logic [47:0]                   tl_rx_bardec,
    input  logic [PF_NUM+7:0]             tl_rx_mchit,
    input  logic [7:0]                    tl_rx_err,
    output logic                          tl_rx_masknp,
    output logic                          tl_rx_wait,
    // tl tx
    output logic                          tl_tx_sop,
    output logic                          tl_tx_eop,
    output logic [CORE_DATA_WIDTH-1:0]    tl_tx_data,
    output logic [CORE_DATA_WIDTH/32-1:0] tl_tx_valid,
    output logic [7:0]                    tl_tx_err,
    output logic                          tl_tx_stream,
    input  logic                          tl_tx_wait,
    input  logic [95:0]                   tl_tx_credits,
    // tl cfg
    output logic                          tl_cfg_prst,
    output logic                          tl_cfg_penable,
    output logic                          tl_cfg_psel,
    output logic                          tl_cfg_pwrite,
    output logic [2:0]                    tl_cfg_pprot,
    output logic [31:0]                   tl_cfg_paddr,
    output logic [3:0]                    tl_cfg_pstrb,
    output logic [31:0]                   tl_cfg_pwdata,
    input  logic                          tl_cfg_pready,
    input  logic [31:0]                   tl_cfg_prdata,
    input  logic                          tl_cfg_pslverr,
    // tl int
    output logic [PF_NUM-1:0]             tl_int_status,
    output logic [PF_NUM-1:0]             tl_int_msireq,
    output logic [PF_NUM*5-1:0]           tl_int_msinum,
    input  logic [PF_NUM-1:0]             tl_int_msiack,
    input  logic [3:0]                    tl_int_pinstate,
    output logic [3:0]                    tl_int_pincontrol,
    input  logic [PF_NUM-1:0]             tl_int_msi_enable,
    input  logic [PF_NUM*3-1:0]           tl_int_msi_multi_enable,
    output logic [PF_NUM*32-1:0]          tl_int_pf_msi_pending,
    input  logic [PF_NUM*32-1:0]          tl_int_pf_msi_mask,
    output logic                          tl_int_vfmsireq,
    output logic [4:0]                    tl_int_vfmsinum,
    output logic [15:0]                   tl_int_vfmsifid,
    input  logic                          tl_int_vfmsiack,
    output logic [7:0]                    tl_int_vfmsi_enable_mask_sel,
    input  logic [2:0]                    tl_int_vfmsi_enable,
    input  logic [31:0]                   tl_int_vfmsi_mask,
    // tl cfg msix
    input  logic [PF_NUM-1:0]             tl_cfg_msix_enable,
    input  logic [PF_NUM-1:0]             tl_cfg_msix_function_mask,
    // tl access
    input  logic [7:0]                    tl_cfg_tcvc,
    input  logic [12:0]                   tl_cfg_busdev,
    input  logic [2:0]                    tl_cfg_max_payload_size,
    input  logic [2:0]                    tl_cfg_max_read_request_size,
    input  logic [2:0]                    tl_cfg_current_link_speed,
    input  logic [3:0]                    tl_cfg_negotiated_width,
    input  logic                          tl_cfg_read_completion_boundary,
    input  logic [PF_NUM*9-1:0]           tl_cfg_pfregs_vfnums,
    input  logic [PF_NUM-1:0]             tl_cfg_pfregs_vfenable,
    input  logic [PF_NUM-1:0]             tl_cfg_pfregs_vfmse,
    input  logic [PF_NUM*4-1:0]           tl_cfg_pfregs_cmd,
    output logic [2:0]                    tl_cfg_vfregs_bit_sel,
    input  logic [255:0]                  tl_cfg_vfregs_bit,
    output logic [7:0]                    tl_cfg_pf0_primary_bus,
    output logic [7:0]                    tl_cfg_pf1_primary_bus,
    output logic [7:0]                    tl_cfg_pf2_primary_bus,
    output logic [7:0]                    tl_cfg_pf3_primary_bus,
    // phy ltssm
    input  logic [1:0]                    pl_equ_phase,
    output logic                          pl_ltssm_enable,
    input  logic [4:0]                    pl_ltssm,
    input  logic [4:0]                    tl_ltssm,
    input  logic                          pl_link_up
);

localparam SYNC_CLOCK = 1;
localparam MONITOR_EN = 0;

pcie_cq_if#(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(CQ_USER_WIDTH)) pcie_cq();
pcie_cc_if#(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(CC_USER_WIDTH)) pcie_cc();
pcie_rq_if#(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(RQ_USER_WIDTH)) pcie_rq();
pcie_rc_if#(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(RC_USER_WIDTH)) pcie_rc();
cfg_mgmt_if cfg_mgmt();
cfg_status_if cfg_status();
cfg_recv_msg_if cfg_recv_msg();
cfg_xmit_msg_if cfg_xmit_msg();
cfg_fc_if cfg_fc();
cfg_ctrl_if cfg_ctrl();
cfg_legacy_int_if#(.PF_NUM(PF_NUM)) cfg_legacy_int();
cfg_msi_int_if#(.PF_NUM(PF_NUM)) cfg_msi_int();
cfg_msix_int_if#(.PF_NUM(PF_NUM), .VF_NUM(VF_NUM)) cfg_msix_int();
core_tl_rx_if#(.DATA_WIDTH(CORE_DATA_WIDTH), .PF_NUM(PF_NUM)) core_tl_rx();
core_tl_tx_if#(.DATA_WIDTH(CORE_DATA_WIDTH)) core_tl_tx();
core_tl_cfg_if#() core_tl_cfg();
core_tl_int_if#(.PF_NUM(PF_NUM)) core_tl_int();
core_tl_cfg_msix_if#(.PF_NUM(PF_NUM)) core_tl_cfg_msix();
core_tl_access_if#(.PF_NUM(PF_NUM)) core_tl_access();
core_phy_ltssm_if core_phy_ltssm();

// cq
assign m_axis_cq_tdata = pcie_cq.tdata;
assign m_axis_cq_tuser = pcie_cq.tuser;
assign m_axis_cq_tlast = pcie_cq.tlast;
assign m_axis_cq_tkeep = pcie_cq.tkeep;
assign m_axis_cq_tvalid = pcie_cq.tvalid;
assign pcie_cq.tready = m_axis_cq_tready;
assign pcie_cq.np_req = pcie_cq_np_req;
assign pcie_cq_np_req_count = pcie_cq.np_req_count;
// cc
assign pcie_cc.tdata = s_axis_cc_tdata;
assign pcie_cc.tuser = s_axis_cc_tuser;
assign pcie_cc.tlast = s_axis_cc_tlast;
assign pcie_cc.tkeep = s_axis_cc_tkeep;
assign pcie_cc.tvalid = s_axis_cc_tvalid;
assign s_axis_cc_tready = {4{pcie_cc.tready}};
// rq
assign pcie_rq.tdata = s_axis_rq_tdata;
assign pcie_rq.tuser = s_axis_rq_tuser;
assign pcie_rq.tlast = s_axis_rq_tlast;
assign pcie_rq.tkeep = s_axis_rq_tkeep;
assign pcie_rq.tvalid = s_axis_rq_tvalid;
assign s_axis_rq_tready = {4{pcie_rq.tready}};
assign pcie_rq_seq_num0 = pcie_rq.pcie_rq_seq_num0;
assign pcie_rq_seq_num1 = pcie_rq.pcie_rq_seq_num1;
assign pcie_rq_seq_num_vld0 = pcie_rq.pcie_rq_seq_num_vld0;
assign pcie_rq_seq_num_vld1 = pcie_rq.pcie_rq_seq_num_vld1;
// rc
assign m_axis_rc_tdata = pcie_rc.tdata;
assign m_axis_rc_tuser = pcie_rc.tuser;
assign m_axis_rc_tlast = pcie_rc.tlast;
assign m_axis_rc_tkeep = pcie_rc.tkeep;
assign m_axis_rc_tvalid = pcie_rc.tvalid;
assign pcie_rc.tready = m_axis_rc_tready;
// cfg mgmt
assign cfg_mgmt.cfg_mgmt_addr = cfg_mgmt_addr;
assign cfg_mgmt.cfg_mgmt_function_number = cfg_mgmt_function_number;
assign cfg_mgmt.cfg_mgmt_write = cfg_mgmt_write;
assign cfg_mgmt.cfg_mgmt_write_data = cfg_mgmt_write_data;
assign cfg_mgmt.cfg_mgmt_byte_enable = cfg_mgmt_byte_enable;
assign cfg_mgmt.cfg_mgmt_read = cfg_mgmt_read;
assign cfg_mgmt_read_data = cfg_mgmt.cfg_mgmt_read_data;
assign cfg_mgmt_read_write_done = cfg_mgmt.cfg_mgmt_read_write_done;
assign cfg_mgmt.cfg_mgmt_debug_access = cfg_mgmt_debug_access;
// cfg status
assign cfg_phy_link_down = cfg_status.cfg_phy_link_down;
assign cfg_phy_link_status = cfg_status.cfg_phy_link_status;
assign cfg_negotiated_width = cfg_status.cfg_negotiated_width;
assign cfg_current_speed = cfg_status.cfg_current_speed;
assign cfg_max_payload = cfg_status.cfg_max_payload;
assign cfg_max_read_req = cfg_status.cfg_max_read_req;
assign cfg_function_status = cfg_status.cfg_function_status;
assign cfg_vf_status = cfg_status.cfg_vf_status;
assign cfg_function_power_state = cfg_status.cfg_function_power_state;
assign cfg_vf_power_state = cfg_status.cfg_vf_power_state;
assign cfg_link_power_state = cfg_status.cfg_link_power_state;
assign cfg_local_error_out = cfg_status.cfg_local_error_out;
assign cfg_local_error_valid = cfg_status.cfg_local_error_valid;
assign cfg_rx_pm_state = cfg_status.cfg_rx_pm_state;
assign cfg_tx_pm_state = cfg_status.cfg_tx_pm_state;
assign cfg_ltssm_state = cfg_status.cfg_ltssm_state;
assign cfg_rcb_status = cfg_status.cfg_rcb_status;
assign cfg_dpa_substate_change = cfg_status.cfg_dpa_substate_change;
assign cfg_obff_enable = cfg_status.cfg_obff_enable;
assign cfg_pl_status_change = cfg_status.cfg_pl_status_change;
assign cfg_tph_requester_enable = cfg_status.cfg_tph_requester_enable;
assign cfg_tph_st_mode = cfg_status.cfg_tph_st_mode;
assign cfg_vf_tph_requester_enable = cfg_status.cfg_vf_tph_requester_enable;
assign cfg_vf_tph_st_mode = cfg_status.cfg_vf_tph_st_mode;
assign pcie_tfc_nph_av = cfg_status.pcie_tfc_nph_av;
assign pcie_tfc_npd_av = cfg_status.pcie_tfc_npd_av;
// recv msg
assign cfg_msg_received = cfg_recv_msg.cfg_msg_received;
assign cfg_msg_received_data = cfg_recv_msg.cfg_msg_received_data;
assign cfg_msg_received_type = cfg_recv_msg.cfg_msg_received_type;
// xmit msg
assign cfg_xmit_msg.cfg_msg_transmit = cfg_msg_transmit;
assign cfg_xmit_msg.cfg_msg_transmit_type = cfg_msg_transmit_type;
assign cfg_xmit_msg.cfg_msg_transmit_data = cfg_msg_transmit_data;
assign cfg_msg_transmit_done = cfg_xmit_msg.cfg_msg_transmit_done;
// ctrl
assign cfg_bus_number = cfg_ctrl.cfg_bus_number;
assign cfg_dev_number = cfg_ctrl.cfg_dev_number;
assign cfg_ctrl.cfg_link_training_enable = cfg_link_training_enable;
// flow ctrl
assign cfg_fc_ph = cfg_fc.cfg_fc_ph;
assign cfg_fc_pd = cfg_fc.cfg_fc_pd;
assign cfg_fc_nph = cfg_fc.cfg_fc_nph;
assign cfg_fc_npd = cfg_fc.cfg_fc_npd;
assign cfg_fc_cplh = cfg_fc.cfg_fc_cplh;
assign cfg_fc_cpld = cfg_fc.cfg_fc_cpld;
// legacy int
assign cfg_legacy_int.cfg_interrupt_int = cfg_interrupt_int;
assign cfg_interrupt_sent = cfg_legacy_int.cfg_interrupt_sent;
assign cfg_legacy_int.cfg_interrupt_pending = cfg_interrupt_pending;
// msi int
assign cfg_interrupt_msi_enable = cfg_msi_int.cfg_interrupt_msi_enable;
assign cfg_msi_int.cfg_interrupt_msi_int = cfg_interrupt_msi_int;
assign cfg_msi_int.cfg_interrupt_msi_function_number = cfg_interrupt_msi_function_number;
assign cfg_interrupt_msi_sent = cfg_msi_int.cfg_interrupt_msi_sent;
assign cfg_interrupt_msi_fail = cfg_msi_int.cfg_interrupt_msi_fail;
assign cfg_interrupt_msi_mmenable = cfg_msi_int.cfg_interrupt_msi_mmenable;
assign cfg_msi_int.cfg_interrupt_msi_pending_status = cfg_interrupt_msi_pending_status;
assign cfg_msi_int.cfg_interrupt_msi_pending_status_function_number = cfg_interrupt_msi_pending_status_function_number;
assign cfg_msi_int.cfg_interrupt_msi_pending_status_data_enable = cfg_interrupt_msi_pending_status_data_enable;
assign cfg_interrupt_msi_mask_update = cfg_msi_int.cfg_interrupt_msi_mask_update;
assign cfg_msi_int.cfg_interrupt_msi_select = cfg_interrupt_msi_select;
assign cfg_interrupt_msi_data = cfg_msi_int.cfg_interrupt_msi_data;
assign cfg_msi_int.cfg_interrupt_msi_attr = cfg_interrupt_msi_attr;
assign cfg_msi_int.cfg_interrupt_msi_tph_present = cfg_interrupt_msi_tph_present;
assign cfg_msi_int.cfg_interrupt_msi_tph_type = cfg_interrupt_msi_tph_type;
assign cfg_msi_int.cfg_interrupt_msi_tph_st_tag = cfg_interrupt_msi_tph_st_tag;
// msix int
assign cfg_interrupt_msix_enable = cfg_msix_int.cfg_interrupt_msix_enable;
assign cfg_interrupt_msix_mask = cfg_msix_int.cfg_interrupt_msix_mask;
assign cfg_interrupt_msix_vf_enable = cfg_msix_int.cfg_interrupt_msix_vf_enable;
assign cfg_interrupt_msix_vf_mask = cfg_msix_int.cfg_interrupt_msix_vf_mask;
assign cfg_msix_int.cfg_interrupt_msix_addr = cfg_interrupt_msix_addr;
assign cfg_msix_int.cfg_interrupt_msix_data = cfg_interrupt_msix_data;
assign cfg_msix_int.cfg_interrupt_msix_int = cfg_interrupt_msix_int;
assign cfg_msix_int.cfg_interrupt_msix_vec_pending = cfg_interrupt_msix_vec_pending;
assign cfg_interrupt_msix_vec_pending_status = cfg_msix_int.cfg_interrupt_msix_vec_pending_status;
// tl rx
assign core_tl_rx.rx_sop = tl_rx_sop;
assign core_tl_rx.rx_eop = tl_rx_eop;
assign core_tl_rx.rx_data = tl_rx_data;
assign core_tl_rx.rx_valid = tl_rx_valid;
assign core_tl_rx.rx_bardec = tl_rx_bardec;
assign core_tl_rx.rx_mchit = tl_rx_mchit;
assign core_tl_rx.rx_err = tl_rx_err;
assign tl_rx_masknp = core_tl_rx.rx_masknp;
assign tl_rx_wait = core_tl_rx.rx_wait;
// tl tx
assign tl_tx_sop = core_tl_tx.tx_sop;
assign tl_tx_eop = core_tl_tx.tx_eop;
assign tl_tx_data = core_tl_tx.tx_data;
assign tl_tx_valid = core_tl_tx.tx_valid;
assign tl_tx_err = core_tl_tx.tx_err;
assign tl_tx_stream = core_tl_tx.tx_stream;
assign core_tl_tx.tx_wait = tl_tx_wait;
assign core_tl_tx.tx_credits = tl_tx_credits;
// tl cfg
assign tl_cfg_prst = core_tl_cfg.tl_cfg_prst;
assign tl_cfg_penable = core_tl_cfg.tl_cfg_penable;
assign tl_cfg_psel = core_tl_cfg.tl_cfg_psel;
assign tl_cfg_pwrite = core_tl_cfg.tl_cfg_pwrite;
assign tl_cfg_pprot = core_tl_cfg.tl_cfg_pprot;
assign tl_cfg_paddr = core_tl_cfg.tl_cfg_paddr;
assign tl_cfg_pstrb = core_tl_cfg.tl_cfg_pstrb;
assign tl_cfg_pwdata = core_tl_cfg.tl_cfg_pwdata;
assign core_tl_cfg.tl_cfg_pready = tl_cfg_pready;
assign core_tl_cfg.tl_cfg_prdata = tl_cfg_prdata;
assign core_tl_cfg.tl_cfg_pslverr = tl_cfg_pslverr;
// tl int
assign tl_int_status = core_tl_int.tl_int_status;
assign tl_int_msireq = core_tl_int.tl_int_msireq;
assign tl_int_msinum = core_tl_int.tl_int_msinum;
assign core_tl_int.tl_int_msiack = tl_int_msiack;
assign core_tl_int.tl_int_pinstate = tl_int_pinstate;
assign tl_int_pincontrol = core_tl_int.tl_int_pincontrol;
assign core_tl_int.tl_int_msi_enable = tl_int_msi_enable;
assign core_tl_int.tl_int_msi_multi_enable = tl_int_msi_multi_enable;
assign tl_int_vfmsireq = core_tl_int.tl_int_vfmsireq;
assign tl_int_vfmsinum = core_tl_int.tl_int_vfmsinum;
assign tl_int_vfmsifid = core_tl_int.tl_int_vfmsifid;
assign core_tl_int.tl_int_vfmsiack = tl_int_vfmsiack;
assign tl_int_vfmsi_enable_mask_sel = core_tl_int.tl_int_vfmsi_enable_mask_sel;
assign core_tl_int.tl_int_vfmsi_enable = tl_int_vfmsi_enable;
assign core_tl_int.tl_int_vfmsi_mask = tl_int_vfmsi_mask;
integer i;
always_comb begin
    for (i=0; i<PF_NUM; i=i+1) begin
        tl_int_pf_msi_pending[i*32+:32] = core_tl_int.tl_int_pf_msi_pending[i];
        core_tl_int.tl_int_pf_msi_mask[i] = tl_int_pf_msi_mask[i*32+:32];
    end
end
// tl cfg msix
assign core_tl_cfg_msix.tl_cfg_msix_enable = tl_cfg_msix_enable;
assign core_tl_cfg_msix.tl_cfg_msix_function_mask = tl_cfg_msix_function_mask;
// tl access
assign core_tl_access.tl_cfg_tcvc = tl_cfg_tcvc;
assign core_tl_access.tl_cfg_busdev = tl_cfg_busdev;
assign core_tl_access.tl_cfg_max_payload_size = tl_cfg_max_payload_size;
assign core_tl_access.tl_cfg_max_read_request_size = tl_cfg_max_read_request_size;
assign core_tl_access.tl_cfg_current_link_speed = tl_cfg_current_link_speed;
assign core_tl_access.tl_cfg_negotiated_width = tl_cfg_negotiated_width;
assign core_tl_access.tl_cfg_read_completion_boundary = tl_cfg_read_completion_boundary;
assign core_tl_access.tl_cfg_pfregs_vfnums = tl_cfg_pfregs_vfnums;
assign core_tl_access.tl_cfg_pfregs_vfenable = tl_cfg_pfregs_vfenable;
assign core_tl_access.tl_cfg_pfregs_vfmse = tl_cfg_pfregs_vfmse;
assign core_tl_access.tl_cfg_pfregs_cmd = tl_cfg_pfregs_cmd;
assign tl_cfg_vfregs_bit_sel = core_tl_access.tl_cfg_vfregs_bit_sel;
assign core_tl_access.tl_cfg_vfregs_bit = tl_cfg_vfregs_bit;
assign tl_cfg_pf0_primary_bus = core_tl_access.tl_cfg_pf0_primary_bus;
assign tl_cfg_pf1_primary_bus = core_tl_access.tl_cfg_pf1_primary_bus;
assign tl_cfg_pf2_primary_bus = core_tl_access.tl_cfg_pf2_primary_bus;
assign tl_cfg_pf3_primary_bus = core_tl_access.tl_cfg_pf3_primary_bus;
// phy ltssm
assign core_phy_ltssm.pl_equ_phase = pl_equ_phase;
assign pl_ltssm_enable = core_phy_ltssm.pl_ltssm_enable;
assign core_phy_ltssm.pl_ltssm = pl_ltssm;
assign core_phy_ltssm.tl_ltssm = tl_ltssm;
assign core_phy_ltssm.pl_link_up = pl_link_up;

pcie_brg#(
    .SYNC_CLOCK(SYNC_CLOCK),
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
) pcie_brg(
    .core_clk(core_clk),
    .core_clk2(core_clk2),
    .core_rst(core_rst),
    .user_clk(user_clk),
    .user_rst(user_rst),

    .pcie_cq(pcie_cq.mst),
    .pcie_cc(pcie_cc.slv),
    .pcie_rq(pcie_rq.slv),
    .pcie_rc(pcie_rc.mst),
    .cfg_mgmt(cfg_mgmt.slv),
    .cfg_status(cfg_status.mst),
    .cfg_recv_msg(cfg_recv_msg.mst),
    .cfg_xmit_msg(cfg_xmit_msg.slv),
    .cfg_fc(cfg_fc.mst),
    .cfg_ctrl(cfg_ctrl.slv),
    .cfg_legacy_int(cfg_legacy_int.slv),
    .cfg_msi_int(cfg_msi_int.slv),
    .cfg_msix_int(cfg_msix_int.slv),

    .core_tl_rx(core_tl_rx.slv),
    .core_tl_tx(core_tl_tx.mst),
    .core_tl_cfg(core_tl_cfg.mst),
    .core_tl_int(core_tl_int.mst),
    .core_tl_cfg_msix(core_tl_cfg_msix.slv),
    .core_tl_access(core_tl_access.slv),
    .core_phy_ltssm(core_phy_ltssm.slv)
);

generate
    if (MONITOR_EN) begin: pcie_brg_mon_en
        pcie_brg_mon#(
            .PF_NUM(1),// monitor 1 pf
            .TAG_WIDTH(6),// monitor 64 tag
            .DATA_WIDTH(DATA_WIDTH)
        ) pcie_brg_mon(
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
            .m_axis_rc_tready(m_axis_rc_tready)
        );
    end
endgenerate

endmodule
