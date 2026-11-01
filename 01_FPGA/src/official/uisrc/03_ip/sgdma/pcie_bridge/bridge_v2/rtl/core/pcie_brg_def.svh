`ifndef PCIE_BRG_DEF
`define PCIE_BRG_DEF

// pcie

typedef struct packed {
    logic [31:0] dw0;
    logic [31:0] dw1;
    logic [31:0] dw2;
    logic [31:0] dw3;
} pcie_tlp_header_t;

// core

interface core_tl_rx_if#(
    parameter DATA_WIDTH = 512,
    parameter PF_NUM = 4
);
    logic rx_sop;
    logic rx_eop;
    logic [DATA_WIDTH-1:0] rx_data;
    logic [DATA_WIDTH/32-1:0] rx_valid;
    logic [47:0] rx_bardec;
    logic [PF_NUM+7:0] rx_mchit;
    logic [7:0] rx_err;
    logic rx_masknp;
    logic rx_wait;
    modport mst (
        output rx_sop, rx_eop, rx_data, rx_valid, rx_bardec, rx_mchit, rx_err,
        input  rx_masknp, rx_wait
    );
    modport slv (
        input  rx_sop, rx_eop, rx_data, rx_valid, rx_bardec, rx_mchit, rx_err,
        output rx_masknp, rx_wait
    );
endinterface

interface core_tl_tx_if#(
    parameter DATA_WIDTH = 512
);
    logic tx_sop;
    logic tx_eop;
    logic [DATA_WIDTH-1:0] tx_data;
    logic [DATA_WIDTH/32-1:0] tx_valid;
    logic [7:0] tx_err;
    logic tx_stream;
    logic tx_wait;
    logic [95:0] tx_credits;
    modport mst (
        output tx_sop, tx_eop, tx_data, tx_valid, tx_err, tx_stream,
        input  tx_wait, tx_credits
    );
    modport slv (
        input  tx_sop, tx_eop, tx_data, tx_valid, tx_err, tx_stream,
        output tx_wait, tx_credits
    );
endinterface

interface core_tl_cfg_if;

    logic        tl_cfg_prst;
    logic        tl_cfg_penable;
    logic        tl_cfg_psel;
    logic        tl_cfg_pwrite;
    logic [2:0]  tl_cfg_pprot;
    logic [31:0] tl_cfg_paddr;
    logic [3:0]  tl_cfg_pstrb;
    logic [31:0] tl_cfg_pwdata;
    logic        tl_cfg_pready;
    logic [31:0] tl_cfg_prdata;
    logic        tl_cfg_pslverr;

    modport mst (
        output tl_cfg_prst, tl_cfg_penable, tl_cfg_psel, tl_cfg_pwrite, tl_cfg_pprot, tl_cfg_paddr, tl_cfg_pstrb, tl_cfg_pwdata,
        input  tl_cfg_pready, tl_cfg_prdata, tl_cfg_pslverr
    );
    modport slv (
        input  tl_cfg_prst, tl_cfg_penable, tl_cfg_psel, tl_cfg_pwrite, tl_cfg_pprot, tl_cfg_paddr, tl_cfg_pstrb, tl_cfg_pwdata,
        output tl_cfg_pready, tl_cfg_prdata, tl_cfg_pslverr
    );

endinterface

interface core_tl_int_if#(
    parameter PF_NUM = 4
);
    logic [PF_NUM-1:0] tl_int_status;
    logic [PF_NUM-1:0] tl_int_msireq;
    logic [PF_NUM*5-1:0] tl_int_msinum;
    logic [PF_NUM-1:0] tl_int_msiack;
    logic [3:0] tl_int_pinstate;
    logic [3:0] tl_int_pincontrol;
    logic [PF_NUM-1:0] tl_int_msi_enable;
    logic [PF_NUM*3-1:0] tl_int_msi_multi_enable;
    logic [PF_NUM-1:0] [31:0] tl_int_pf_msi_pending;
    logic [PF_NUM-1:0] [31:0] tl_int_pf_msi_mask;
    logic tl_int_vfmsireq;
    logic [4:0] tl_int_vfmsinum;
    logic [15:0] tl_int_vfmsifid;
    logic tl_int_vfmsiack;
    logic [7:0] tl_int_vfmsi_enable_mask_sel;
    logic [2:0] tl_int_vfmsi_enable;
    logic [31:0] tl_int_vfmsi_mask;
    modport mst (
        output tl_int_status, tl_int_msireq, tl_int_msinum, tl_int_pincontrol,
               tl_int_pf_msi_pending, tl_int_vfmsireq, tl_int_vfmsinum, tl_int_vfmsifid, tl_int_vfmsi_enable_mask_sel,
        input  tl_int_msiack, tl_int_pinstate, tl_int_msi_enable, tl_int_msi_multi_enable,
               tl_int_pf_msi_mask, tl_int_vfmsiack, tl_int_vfmsi_enable, tl_int_vfmsi_mask
    );
    modport slv (
        input  tl_int_status, tl_int_msireq, tl_int_msinum, tl_int_pincontrol,
               tl_int_pf_msi_pending, tl_int_vfmsireq, tl_int_vfmsinum, tl_int_vfmsifid, tl_int_vfmsi_enable_mask_sel,
        output tl_int_msiack, tl_int_pinstate, tl_int_msi_enable, tl_int_msi_multi_enable,
               tl_int_pf_msi_mask, tl_int_vfmsiack, tl_int_vfmsi_enable, tl_int_vfmsi_mask
    );
endinterface

interface core_tl_cfg_msix_if#(
    parameter PF_NUM = 4
);

    logic [PF_NUM-1:0] tl_cfg_msix_enable;
    logic [PF_NUM-1:0] tl_cfg_msix_function_mask;

    modport mst (
        output tl_cfg_msix_enable, tl_cfg_msix_function_mask
    );

    modport slv (
        input  tl_cfg_msix_enable, tl_cfg_msix_function_mask
    );

endinterface

interface core_tl_access_if#(
    parameter PF_NUM = 4
);

    logic [7:0] tl_cfg_tcvc;
    logic [12:0] tl_cfg_busdev;
    logic [2:0] tl_cfg_max_payload_size;
    logic [2:0] tl_cfg_max_read_request_size;
    logic [2:0] tl_cfg_current_link_speed;
    logic [3:0] tl_cfg_negotiated_width;
    logic tl_cfg_read_completion_boundary;
    logic [PF_NUM*9-1:0] tl_cfg_pfregs_vfnums;
    logic [PF_NUM-1:0] tl_cfg_pfregs_vfenable;
    logic [PF_NUM-1:0] tl_cfg_pfregs_vfmse;
    logic [PF_NUM*4-1:0] tl_cfg_pfregs_cmd;
    logic [2:0] tl_cfg_vfregs_bit_sel;
    logic [255:0] tl_cfg_vfregs_bit;
    logic [7:0] tl_cfg_pf0_primary_bus;
    logic [7:0] tl_cfg_pf1_primary_bus;
    logic [7:0] tl_cfg_pf2_primary_bus;
    logic [7:0] tl_cfg_pf3_primary_bus;

    modport mst (
        output tl_cfg_tcvc, tl_cfg_busdev, tl_cfg_max_payload_size, tl_cfg_max_read_request_size, tl_cfg_current_link_speed,
               tl_cfg_negotiated_width, tl_cfg_read_completion_boundary, tl_cfg_pfregs_vfnums, tl_cfg_pfregs_vfenable,
               tl_cfg_pfregs_vfmse, tl_cfg_pfregs_cmd, tl_cfg_vfregs_bit,
        input  tl_cfg_vfregs_bit_sel, tl_cfg_pf0_primary_bus, tl_cfg_pf1_primary_bus, tl_cfg_pf2_primary_bus, tl_cfg_pf3_primary_bus
    );

    modport slv (
        input  tl_cfg_tcvc, tl_cfg_busdev, tl_cfg_max_payload_size, tl_cfg_max_read_request_size, tl_cfg_current_link_speed,
               tl_cfg_negotiated_width, tl_cfg_read_completion_boundary, tl_cfg_pfregs_vfnums, tl_cfg_pfregs_vfenable,
               tl_cfg_pfregs_vfmse, tl_cfg_pfregs_cmd, tl_cfg_vfregs_bit,
        output  tl_cfg_vfregs_bit_sel, tl_cfg_pf0_primary_bus, tl_cfg_pf1_primary_bus, tl_cfg_pf2_primary_bus, tl_cfg_pf3_primary_bus
    );

endinterface

interface core_phy_ltssm_if;

    logic [1:0] pl_equ_phase;
    logic pl_ltssm_enable;
    logic [4:0] pl_ltssm;
    logic [4:0] tl_ltssm;
    logic pl_link_up;

    modport mst (
        output pl_equ_phase, pl_ltssm, tl_ltssm, pl_link_up,
        input  pl_ltssm_enable
    );

    modport slv (
        input  pl_equ_phase, pl_ltssm, tl_ltssm, pl_link_up,
        output pl_ltssm_enable
    );

endinterface

// CQ
interface pcie_cq_if#(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 183
);
    logic [DATA_WIDTH-1:0] tdata;
    logic [USER_WIDTH-1:0] tuser;
    logic tlast;
    logic [DATA_WIDTH/32-1:0] tkeep;
    logic tvalid;
    logic tready;
    logic [1:0] np_req;
    logic [5:0] np_req_count;
    modport mst (
        output tdata, tuser, tlast, tkeep, tvalid, np_req_count,
        input tready, np_req
    );
    modport slv (
        input tdata, tuser, tlast, tkeep, tvalid, np_req_count,
        output tready, np_req
    );
endinterface

typedef struct packed {
    logic [2:0] reserved;
    logic [31:0] parity;
    logic [7:0] tph_st_tag;
    logic [1:0] tph_type;
    logic tph_present;
    logic discontinue;
    logic sop;
    logic [31:0] byte_en;
    logic [3:0] last_be;
    logic [3:0] first_be;
} pcie_cq_tuser_t;

typedef struct packed {
    logic [63:0] parity;
    logic [15:0] tph_st_tag;
    logic [3:0] tph_type;
    logic [1:0] tph_present;
    logic discontinue;
    logic [3:0] is_eop1_ptr;
    logic [3:0] is_eop0_ptr;
    logic [1:0] is_eop;
    logic [1:0] is_sop1_ptr;
    logic [1:0] is_sop0_ptr;
    logic [1:0] is_sop;
    logic [63:0] byte_en;
    logic [7:0] last_be;
    logic [7:0] first_be;
} pcie_cq_tuser512_t;

typedef struct packed {
    logic [31:0] dw3;
    logic [31:0] dw2;
    logic [31:0] dw1;
    logic [31:0] dw0;
} pcie_cq_desc_dw_t;

typedef struct packed {
    logic r1;
    logic [2:0] attr;
    logic [2:0] tc;
    logic [5:0] bar_apt;
    logic [2:0] bar_id;
    logic [7:0] tgt_func;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r0;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [63:2] addr;
    logic [1:0] at;
} pcie_cq_desc_mem_t;

typedef struct packed {
    logic r4;
    logic [2:0] attr;
    logic [2:0] tc;
    logic r3;
    logic [15:0] cpl_id;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r2;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [51:0] r1;
    logic [3:0] ext_reg;
    logic [5:0] reg_num;
    logic [1:0] r0;
} pcie_cq_desc_cfg_t;

typedef struct packed {
    logic r2;
    logic [2:0] attr;
    logic [2:0] tc;
    logic [5:0] r1;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r0;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [31:0] vdr_hdr_bytes;
    logic [15:0] vdr_id;
    logic [15:0] dest_id;
} pcie_cq_desc_vd_msg_t;

typedef struct packed {
    logic r2;
    logic [2:0] attr;
    logic [2:0] tc;
    logic [5:0] r1;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r0;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [63:0] tl_hdr_bytes;
} pcie_cq_desc_ats_msg_t;

typedef struct packed {
    logic r3;
    logic [2:0] attr;
    logic [2:0] tc;
    logic [5:0] r2;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r1;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [27:0] r0;
    logic [3:0] obff_code;
    logic [15:0] no_snoop_latency;
    logic [15:0] snoop_latency;
} pcie_cq_desc_msg_t;

typedef union packed {
    pcie_cq_desc_dw_t  cq_desc_dw;
    pcie_cq_desc_mem_t cq_desc_mem;
    pcie_cq_desc_cfg_t cq_desc_cfg;
    pcie_cq_desc_vd_msg_t cq_desc_vd_msg;
    pcie_cq_desc_ats_msg_t cq_desc_ats_msg;
    pcie_cq_desc_msg_t cq_desc_msg;
} pcie_cq_desc_t;

// CC
interface pcie_cc_if#(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 81
);
    logic [DATA_WIDTH-1:0] tdata;
    logic [USER_WIDTH-1:0] tuser;
    logic tlast;
    logic [DATA_WIDTH/32-1:0] tkeep;
    logic tvalid;
    logic tready;
    modport mst (
        output tdata, tuser, tlast, tkeep, tvalid,
        input tready
    );
    modport slv (
        input tdata, tuser, tlast, tkeep, tvalid,
        output tready
    );
endinterface

typedef struct packed {
    logic [31:0] parity;
    logic discontinue;
} pcie_cc_tuser_t;

typedef struct packed {
    logic [63:0] parity;
    logic discontinue;
    logic [3:0] is_eop1_ptr;
    logic [3:0] is_eop0_ptr;
    logic [1:0] is_eop;
    logic [1:0] is_sop1_ptr;
    logic [1:0] is_sop0_ptr;
    logic [1:0] is_sop;
} pcie_cc_tuser512_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic cpl_id_en;
    logic [15:0] cpl_id;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r3;
    logic ep;
    logic [2:0] cpl_status;
    logic [10:0] dword_count;
    logic [1:0] r2;
    logic locked;
    logic [12:0] byte_count;
    logic [5:0] r1;
    logic [1:0] at;
    logic r0;
    logic [6:0] addr;
} pcie_cc_desc_t;

// RQ
interface pcie_rq_if#(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 137
);
    logic [DATA_WIDTH-1:0] tdata;
    logic [USER_WIDTH-1:0] tuser;
    logic tlast;
    logic [DATA_WIDTH/32-1:0] tkeep;
    logic tvalid;
    logic tready;
    logic [5:0] pcie_rq_seq_num0;
    logic [5:0] pcie_rq_seq_num1;
    logic pcie_rq_seq_num_vld0;
    logic pcie_rq_seq_num_vld1;
    modport mst (
        output tdata, tuser, tlast, tkeep, tvalid,
        input tready, pcie_rq_seq_num0, pcie_rq_seq_num1, pcie_rq_seq_num_vld0, pcie_rq_seq_num_vld1
    );
    modport slv (
        input tdata, tuser, tlast, tkeep, tvalid,
        output tready, pcie_rq_seq_num0, pcie_rq_seq_num1, pcie_rq_seq_num_vld0, pcie_rq_seq_num_vld1
    );
endinterface

typedef struct packed {
    logic [1:0] seq_num_ext;
    logic [31:0] parity;
    logic [3:0] seq_num;
    logic [7:0] tph_st_tag;
    logic tph_indirect_tag_en;
    logic [1:0] tph_type;
    logic tph_present;
    logic discontinue;
    logic [2:0] addr_offset;
    logic [3:0] last_be;
    logic [3:0] first_be;
} pcie_rq_tuser_t;

typedef struct packed {
    logic [63:0] parity;
    logic [5:0] seq_num1;
    logic [5:0] seq_num0;
    logic [15:0] tph_st_tag;
    logic [1:0] tph_indirect_tag_en;
    logic [3:0] tph_type;
    logic [1:0] tph_present;
    logic discontinue;
    logic [3:0] is_eop1_ptr;
    logic [3:0] is_eop0_ptr;
    logic [1:0] is_eop;
    logic [1:0] is_sop1_ptr;
    logic [1:0] is_sop0_ptr;
    logic [1:0] is_sop;
    logic [3:0] addr_offset;
    logic [7:0] last_be;
    logic [7:0] first_be;
} pcie_rq_tuser512_t;

typedef struct packed {
    logic [31:0] dw3;
    logic [31:0] dw2;
    logic [31:0] dw1;
    logic [31:0] dw0;
} pcie_rq_desc_dw_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic req_id_en;
    logic [15:0] cpl_id;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic ep;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [63:2] addr;
    logic [1:0] at;
} pcie_rq_desc_mem_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic req_id_en;
    logic [15:0] cpl_id;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic ep;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [51:0] r1;
    logic [3:0] ext_reg;
    logic [5:0] reg_num;
    logic [1:0] r0;
} pcie_rq_desc_cfg_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic [5:0] req_id_en;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic ep;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [31:0] vdr_hdr_bytes;
    logic [15:0] vdr_id;
    logic [15:0] dest_id;
} pcie_rq_desc_vd_msg_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic req_id_en;
    logic [4:0] r1;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic ep;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [63:0] tl_hdr_bytes;
} pcie_rq_desc_ats_msg_t;

typedef struct packed {
    logic force_ecrc;
    logic [2:0] attr;
    logic [2:0] tc;
    logic req_id_en;
    logic [4:0] r2;
    logic [2:0] msg_routing;
    logic [7:0] msg_code;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic ep;
    logic [3:0] req_type;
    logic [10:0] dword_count;
    logic [27:0] r0;
    logic [3:0] obff_code;
    logic [15:0] no_snoop_latency;
    logic [15:0] snoop_latency;
} pcie_rq_desc_msg_t;

typedef union packed {
    pcie_rq_desc_dw_t  rq_desc_dw;
    pcie_rq_desc_mem_t rq_desc_mem;
    pcie_rq_desc_cfg_t rq_desc_cfg;
    pcie_rq_desc_vd_msg_t rq_desc_vd_msg;
    pcie_rq_desc_ats_msg_t rq_desc_ats_msg;
    pcie_rq_desc_msg_t rq_desc_msg;
} pcie_rq_desc_t;

// RC
interface pcie_rc_if#(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 161
);
    logic [DATA_WIDTH-1:0] tdata;
    logic [USER_WIDTH-1:0] tuser;
    logic tlast;
    logic [DATA_WIDTH/32-1:0] tkeep;
    logic tvalid;
    logic tready;
    modport mst (
        output tdata, tuser, tlast, tkeep, tvalid,
        input tready
    );
    modport slv (
        input tdata, tuser, tlast, tkeep, tvalid,
        output tready
    );
endinterface

typedef struct packed {
    logic [31:0] parity;
    logic discontinue;
    logic [3:0] is_eof_1;
    logic [3:0] is_eof_0;
    logic is_sof_1;
    logic is_sof_0;
    logic [31:0] byte_en;
} pcie_rc_tuser_t;

typedef struct packed {
    logic [63:0] parity;
    logic discontinue;
    logic [3:0] is_eop3_ptr;
    logic [3:0] is_eop2_ptr;
    logic [3:0] is_eop1_ptr;
    logic [3:0] is_eop0_ptr;
    logic [3:0] is_eop;
    logic [1:0] is_sop3_ptr;
    logic [1:0] is_sop2_ptr;
    logic [1:0] is_sop1_ptr;
    logic [1:0] is_sop0_ptr;
    logic [3:0] is_sop;
    logic [63:0] byte_en;
} pcie_rc_tuser512_t;

typedef struct packed {
    logic r3;
    logic [2:0] attr;
    logic [2:0] tc;
    logic r2;
    logic [15:0] cpl_id;
    logic [7:0] tag;
    logic [15:0] req_id;
    logic r1;
    logic ep;
    logic [2:0] cpl_status;
    logic [10:0] dword_count;
    logic r0;
    logic req_cpl;
    logic locked;
    logic [12:0] byte_count;
    logic [3:0] err_code;
    logic [11:0] addr;
} pcie_rc_desc_t;

interface power_mgmt_if;
    logic cfg_pm_aspm_l1_entry_reject;
    logic cfg_pm_aspm_tx_l0s_entry_disable;
    modport mst (
        output cfg_pm_aspm_l1_entry_reject, cfg_pm_aspm_tx_l0s_entry_disable
    );
    modport slv (
        input cfg_pm_aspm_l1_entry_reject, cfg_pm_aspm_tx_l0s_entry_disable
    );
endinterface

interface cfg_mgmt_if;
    logic [9:0] cfg_mgmt_addr;
    logic [7:0] cfg_mgmt_function_number;
    logic cfg_mgmt_write;
    logic [31:0] cfg_mgmt_write_data;
    logic [3:0] cfg_mgmt_byte_enable;
    logic cfg_mgmt_read;
    logic [31:0] cfg_mgmt_read_data;
    logic cfg_mgmt_read_write_done;
    logic cfg_mgmt_debug_access;
    modport mst (
        output cfg_mgmt_addr, cfg_mgmt_function_number, cfg_mgmt_write, cfg_mgmt_write_data, cfg_mgmt_byte_enable, cfg_mgmt_read, cfg_mgmt_debug_access,
        input cfg_mgmt_read_data, cfg_mgmt_read_write_done
    );
    modport slv (
        input cfg_mgmt_addr, cfg_mgmt_function_number, cfg_mgmt_write, cfg_mgmt_write_data, cfg_mgmt_byte_enable, cfg_mgmt_read, cfg_mgmt_debug_access,
        output cfg_mgmt_read_data, cfg_mgmt_read_write_done
    );
endinterface

interface cfg_status_if;
    logic cfg_phy_link_down;
    logic [1:0] cfg_phy_link_status;
    logic [2:0] cfg_negotiated_width;
    logic [1:0] cfg_current_speed;
    logic [2:0] cfg_max_payload;
    logic [2:0] cfg_max_read_req;
    logic [15:0] cfg_function_status;
    logic [503:0] cfg_vf_status;
    logic [11:0] cfg_function_power_state;
    logic [755:0] cfg_vf_power_state;
    logic [1:0] cfg_link_power_state;
    logic [4:0] cfg_local_error_out;
    logic cfg_local_error_valid;
    logic [1:0] cfg_rx_pm_state;
    logic [1:0] cfg_tx_pm_state;
    logic [5:0] cfg_ltssm_state;
    logic [3:0] cfg_rcb_status;
    logic [3:0] cfg_dpa_substate_change;
    logic [1:0] cfg_obff_enable;
    logic cfg_pl_status_change;
    logic [3:0] cfg_tph_requester_enable;
    logic [11:0] cfg_tph_st_mode;
    logic [251:0] cfg_vf_tph_requester_enable;
    logic [755:0] cfg_vf_tph_st_mode;
    logic [3:0] pcie_tfc_nph_av;
    logic [3:0] pcie_tfc_npd_av;
    // logic [3:0] pcie_rq_tag_av;
    modport mst (
        output cfg_phy_link_down, cfg_phy_link_status, cfg_negotiated_width, cfg_current_speed, cfg_max_payload, cfg_max_read_req,
               cfg_function_status, cfg_vf_status, cfg_function_power_state, cfg_vf_power_state, cfg_link_power_state,
               cfg_local_error_out, cfg_local_error_valid, cfg_rx_pm_state, cfg_tx_pm_state, cfg_ltssm_state, cfg_rcb_status,
               cfg_dpa_substate_change, cfg_obff_enable, cfg_pl_status_change, cfg_tph_requester_enable, cfg_tph_st_mode,
               cfg_vf_tph_requester_enable, cfg_vf_tph_st_mode, pcie_tfc_nph_av, pcie_tfc_npd_av
    );
    modport slv (
        input cfg_phy_link_down, cfg_phy_link_status, cfg_negotiated_width, cfg_current_speed, cfg_max_payload, cfg_max_read_req,
               cfg_function_status, cfg_vf_status, cfg_function_power_state, cfg_vf_power_state, cfg_link_power_state,
               cfg_local_error_out, cfg_local_error_valid, cfg_rx_pm_state, cfg_tx_pm_state, cfg_ltssm_state, cfg_rcb_status,
               cfg_dpa_substate_change, cfg_obff_enable, cfg_pl_status_change, cfg_tph_requester_enable, cfg_tph_st_mode,
               cfg_vf_tph_requester_enable, cfg_vf_tph_st_mode, pcie_tfc_nph_av, pcie_tfc_npd_av
    );
endinterface

interface cfg_recv_msg_if;
    logic cfg_msg_received;
    logic [7:0] cfg_msg_received_data;
    logic [4:0] cfg_msg_received_type;
    modport mst (
        output cfg_msg_received, cfg_msg_received_data, cfg_msg_received_type
    );
    modport slv (
        input cfg_msg_received, cfg_msg_received_data, cfg_msg_received_type
    );
endinterface

interface cfg_xmit_msg_if;
    logic cfg_msg_transmit;
    logic [2:0] cfg_msg_transmit_type;
    logic [31:0] cfg_msg_transmit_data;
    logic cfg_msg_transmit_done;
    modport mst (
        output cfg_msg_transmit, cfg_msg_transmit_type, cfg_msg_transmit_data,
        input cfg_msg_transmit_done
    );
    modport slv (
        input cfg_msg_transmit, cfg_msg_transmit_type, cfg_msg_transmit_data,
        output cfg_msg_transmit_done
    );
endinterface

interface cfg_fc_if;
    logic [7:0]  cfg_fc_ph;
    logic [11:0] cfg_fc_pd;
    logic [7:0]  cfg_fc_nph;
    logic [11:0] cfg_fc_npd;
    logic [7:0]  cfg_fc_cplh;
    logic [11:0] cfg_fc_cpld;
    modport mst (
        output cfg_fc_ph, cfg_fc_pd, cfg_fc_nph, cfg_fc_npd, cfg_fc_cplh, cfg_fc_cpld
    );
    modport slv (
        input  cfg_fc_ph, cfg_fc_pd, cfg_fc_nph, cfg_fc_npd, cfg_fc_cplh, cfg_fc_cpld
    );
endinterface

interface cfg_ctrl_if;
    logic cfg_hot_reset_in;
    logic cfg_hot_reset_out;
    logic cfg_config_space_enable;
    logic [63:0] cfg_dsn;
    logic [7:0] cfg_ds_bus_number;
    logic [4:0] cfg_ds_device_number;
    logic [2:0] cfg_ds_function_number;
    logic cfg_power_state_change_ack;
    logic cfg_power_state_change_interrupt;
    logic [7:0] cfg_ds_port_number;
    logic cfg_err_cor_in;
    logic cfg_err_cor_out;
    logic cfg_err_fatal_out;
    logic cfg_err_nonfatal_out;
    logic cfg_err_uncor_in;
    logic [3:0] cfg_flr_done;
    logic cfg_vf_flr_done;
    logic [7:0] cfg_vf_flr_func_num;
    logic [3:0] cfg_flr_in_process;
    logic [251:0] cfg_vf_flr_in_process;
    logic cfg_req_pm_transition_l23_ready;
    logic cfg_link_training_enable;
    logic [7:0] cfg_bus_number;
    logic [4:0] cfg_dev_number;
    logic [15:0] cfg_vend_id;
    logic [15:0] cfg_subsys_vend_id;
    logic [15:0] cfg_dev_id_pf0;
    logic [15:0] cfg_dev_id_pf1;
    logic [15:0] cfg_dev_id_pf2;
    logic [15:0] cfg_dev_id_pf3;
    logic [7:0] cfg_rev_id_pf0;
    logic [7:0] cfg_rev_id_pf1;
    logic [7:0] cfg_rev_id_pf2;
    logic [7:0] cfg_rev_id_pf3;
    logic [15:0] cfg_subsys_id_pf0;
    logic [15:0] cfg_subsys_id_pf1;
    logic [15:0] cfg_subsys_id_pf2;
    logic [15:0] cfg_subsys_id_pf3;
    modport mst (
        output cfg_hot_reset_in, cfg_config_space_enable, cfg_dsn, cfg_ds_bus_number, cfg_ds_device_number, cfg_ds_function_number,
               cfg_power_state_change_ack, cfg_ds_port_number, cfg_err_cor_in, cfg_err_uncor_in, cfg_flr_done, cfg_vf_flr_func_num,
               cfg_req_pm_transition_l23_ready, cfg_link_training_enable, cfg_vend_id, cfg_subsys_vend_id, cfg_dev_id_pf0, cfg_dev_id_pf1,
               cfg_dev_id_pf2, cfg_dev_id_pf3, cfg_rev_id_pf0, cfg_rev_id_pf1, cfg_rev_id_pf2, cfg_rev_id_pf3, cfg_subsys_id_pf0,
               cfg_subsys_id_pf1, cfg_subsys_id_pf2, cfg_subsys_id_pf3,
        input  cfg_hot_reset_out, cfg_power_state_change_interrupt, cfg_err_cor_out, cfg_err_fatal_out, cfg_err_nonfatal_out,
               cfg_flr_in_process, cfg_vf_flr_in_process, cfg_bus_number, cfg_dev_number
    );
    modport slv (
        input  cfg_hot_reset_in, cfg_config_space_enable, cfg_dsn, cfg_ds_bus_number, cfg_ds_device_number, cfg_ds_function_number,
               cfg_power_state_change_ack, cfg_ds_port_number, cfg_err_cor_in, cfg_err_uncor_in, cfg_flr_done, cfg_vf_flr_func_num,
               cfg_req_pm_transition_l23_ready, cfg_link_training_enable, cfg_vend_id, cfg_subsys_vend_id, cfg_dev_id_pf0, cfg_dev_id_pf1,
               cfg_dev_id_pf2, cfg_dev_id_pf3, cfg_rev_id_pf0, cfg_rev_id_pf1, cfg_rev_id_pf2, cfg_rev_id_pf3, cfg_subsys_id_pf0,
               cfg_subsys_id_pf1, cfg_subsys_id_pf2, cfg_subsys_id_pf3,
        output cfg_hot_reset_out, cfg_power_state_change_interrupt, cfg_err_cor_out, cfg_err_fatal_out, cfg_err_nonfatal_out,
               cfg_flr_in_process, cfg_vf_flr_in_process, cfg_bus_number, cfg_dev_number
    );
endinterface

interface cfg_legacy_int_if#(
    parameter PF_NUM = 4
);
    logic [3:0] cfg_interrupt_int;
    logic cfg_interrupt_sent;
    logic [PF_NUM-1:0] cfg_interrupt_pending;
    modport mst (
        output cfg_interrupt_int, cfg_interrupt_pending,
        input cfg_interrupt_sent
    );
    modport slv (
        input cfg_interrupt_int, cfg_interrupt_pending,
        output cfg_interrupt_sent
    );
endinterface

interface cfg_msi_int_if#(
    parameter PF_NUM = 4
);
    localparam PF_NUM_BITS = $clog2(PF_NUM);
    logic [PF_NUM-1:0] cfg_interrupt_msi_enable;
    logic [31:0] cfg_interrupt_msi_int;
    logic [7:0] cfg_interrupt_msi_function_number;
    logic cfg_interrupt_msi_sent;
    logic cfg_interrupt_msi_fail;
    logic [PF_NUM*3-1:0] cfg_interrupt_msi_mmenable;
    logic [31:0] cfg_interrupt_msi_pending_status;
    logic [PF_NUM_BITS-1:0] cfg_interrupt_msi_pending_status_function_number;
    logic cfg_interrupt_msi_pending_status_data_enable;
    logic cfg_interrupt_msi_mask_update;
    logic [PF_NUM_BITS-1:0] cfg_interrupt_msi_select;
    logic [31:0] cfg_interrupt_msi_data;
    logic [2:0] cfg_interrupt_msi_attr;
    logic cfg_interrupt_msi_tph_present;
    logic [1:0] cfg_interrupt_msi_tph_type;
    logic [31:0] cfg_interrupt_msi_tph_st_tag;
    modport mst (
        output cfg_interrupt_msi_int, cfg_interrupt_msi_function_number, cfg_interrupt_msi_pending_status, cfg_interrupt_msi_pending_status_function_number,
               cfg_interrupt_msi_pending_status_data_enable, cfg_interrupt_msi_select, cfg_interrupt_msi_attr, cfg_interrupt_msi_tph_present,
               cfg_interrupt_msi_tph_type, cfg_interrupt_msi_tph_st_tag,
        input  cfg_interrupt_msi_enable, cfg_interrupt_msi_sent, cfg_interrupt_msi_fail, cfg_interrupt_msi_mmenable, cfg_interrupt_msi_mask_update,
               cfg_interrupt_msi_data
    );
    modport slv (
        input  cfg_interrupt_msi_int, cfg_interrupt_msi_function_number, cfg_interrupt_msi_pending_status, cfg_interrupt_msi_pending_status_function_number,
               cfg_interrupt_msi_pending_status_data_enable, cfg_interrupt_msi_select, cfg_interrupt_msi_attr, cfg_interrupt_msi_tph_present,
               cfg_interrupt_msi_tph_type, cfg_interrupt_msi_tph_st_tag,
        output cfg_interrupt_msi_enable, cfg_interrupt_msi_sent, cfg_interrupt_msi_fail, cfg_interrupt_msi_mmenable, cfg_interrupt_msi_mask_update,
               cfg_interrupt_msi_data
    );
endinterface

interface cfg_msix_int_if#(
    parameter PF_NUM = 4,
    parameter VF_NUM = 252
);
    logic [PF_NUM-1:0] cfg_interrupt_msix_enable;
    logic [PF_NUM-1:0] cfg_interrupt_msix_mask;
    logic [VF_NUM-1:0] cfg_interrupt_msix_vf_enable;
    logic [VF_NUM-1:0] cfg_interrupt_msix_vf_mask;
    logic [63:0] cfg_interrupt_msix_addr;
    logic [31:0] cfg_interrupt_msix_data;
    logic cfg_interrupt_msix_int;
    logic [1:0] cfg_interrupt_msix_vec_pending;
    logic cfg_interrupt_msix_vec_pending_status;
    modport mst (
        output cfg_interrupt_msix_addr, cfg_interrupt_msix_data, cfg_interrupt_msix_int, cfg_interrupt_msix_vec_pending,
        input  cfg_interrupt_msix_enable, cfg_interrupt_msix_mask, cfg_interrupt_msix_vf_enable, cfg_interrupt_msix_vf_mask, cfg_interrupt_msix_vec_pending_status
    );
    modport slv (
        input  cfg_interrupt_msix_addr, cfg_interrupt_msix_data, cfg_interrupt_msix_int, cfg_interrupt_msix_vec_pending,
        output cfg_interrupt_msix_enable, cfg_interrupt_msix_mask, cfg_interrupt_msix_vf_enable, cfg_interrupt_msix_vf_mask, cfg_interrupt_msix_vec_pending_status
    );
endinterface

interface cfg_ext_if;
    logic cfg_ext_read_received;
    logic cfg_ext_write_received;
    logic [9:0] cfg_ext_register_number;
    logic [7:0] cfg_ext_function_number;
    logic [31:0] cfg_ext_write_data;
    logic [3:0] cfg_ext_write_byte_enable;
    logic [31:0] cfg_ext_read_data;
    logic cfg_ext_read_data_valid;
    modport mst (
        output cfg_ext_read_received, cfg_ext_write_received, cfg_ext_register_number, cfg_ext_function_number, cfg_ext_write_data, cfg_ext_write_byte_enable,
        input  cfg_ext_read_data, cfg_ext_read_data_valid
    );
    modport slv (
        input  cfg_ext_read_received, cfg_ext_write_received, cfg_ext_register_number, cfg_ext_function_number, cfg_ext_write_data, cfg_ext_write_byte_enable,
        output cfg_ext_read_data, cfg_ext_read_data_valid
    );
endinterface

typedef struct packed {
    logic busy;
    logic [2:0] err;
} pcie_stat_err_t;

`endif
