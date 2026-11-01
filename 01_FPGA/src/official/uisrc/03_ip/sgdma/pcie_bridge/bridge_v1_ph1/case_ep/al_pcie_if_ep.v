
// ===========================================================================
// Copyright (c) 2011-2021 Anlogic Inc., All Right Reserved.
// 
// TEL: 86-21-61633787
// WEB: http://www.anlogic.com/
// ===========================================================================
//
// Designer    :  
// Date        ：2021/09/15  
// Discription ：
//      top file of anlogic pcie interface convert
//       
// Email       :  
// 
// ===========================================================================

`timescale 1ns / 1ps
module  al_pcie_if_ep#(
    parameter SIM_MODE     = 0,
    parameter LINK_WIDTH   = 4,
    parameter DATA_WIDTH   =128,
    parameter DW_WIDTH     =DATA_WIDTH/32, 
    parameter RQ_USER_WIDTH=62,
    parameter RC_USER_WIDTH=75,
    parameter CQ_USER_WIDTH=88,
    parameter CC_USER_WIDTH=33
)(  

    //---reference clock and transciever pairs-------------//
    input                       refclk_p                            ,
    input                       refclk_n                            ,
    output  [LINK_WIDTH-1:0]    txp                                 ,
    output  [LINK_WIDTH-1:0]    txn                                 ,
    input   [LINK_WIDTH-1:0]    rxp                                 ,
    input   [LINK_WIDTH-1:0]    rxn                                 ,   
    //---system clock and reset output for user-----------//
    input                app_auxclk                                 ,
    input                app_perst_n                                ,
    output               user_clk                                   ,
    output               user_reset                                 ,
    output               user_link_up                               ,
    output      [4:0]    client02rq_tuser_o                         ,
    //---pcie data bus interface--------------------------//
    input       [DATA_WIDTH-1:0]    s_axis_rq_tdata ,
    input       [DW_WIDTH-1:0]      s_axis_rq_tkeep ,
    input                           s_axis_rq_tlast ,
    output      [3:0]               s_axis_rq_tready,
    input       [RQ_USER_WIDTH-1:0] s_axis_rq_tuser ,
    input                           s_axis_rq_tvalid,
    output      [DATA_WIDTH-1:0]    m_axis_rc_tdata ,
    output      [DW_WIDTH-1:0]      m_axis_rc_tkeep ,
    output                          m_axis_rc_tlast ,
    input                           m_axis_rc_tready,
    output      [RC_USER_WIDTH-1:0] m_axis_rc_tuser ,
    output                          m_axis_rc_tvalid,
    output      [DATA_WIDTH-1:0]    m_axis_cq_tdata ,
    output      [DW_WIDTH-1:0]      m_axis_cq_tkeep ,
    output                          m_axis_cq_tlast ,
    input                           m_axis_cq_tready,
    output      [CQ_USER_WIDTH-1:0] m_axis_cq_tuser ,
    output                          m_axis_cq_tvalid,
    input       [DATA_WIDTH-1:0]    s_axis_cc_tdata ,
    input       [DW_WIDTH-1:0]      s_axis_cc_tkeep ,
    input                           s_axis_cc_tlast ,
    output      [3:0]               s_axis_cc_tready    ,
    input       [CC_USER_WIDTH-1:0] s_axis_cc_tuser ,
    input                           s_axis_cc_tvalid    ,

    //---pcie cfg bus interface--------------------------//
    input       [9:0]   cfg_mgmt_addr                               ,
    input       [7:0]   cfg_mgmt_function_number                    ,
    input               cfg_mgmt_write                              ,
    input       [31:0]  cfg_mgmt_write_data                         ,
    input       [3:0]   cfg_mgmt_byte_enable                        ,
    input               cfg_mgmt_read                               ,
    output      [31:0]  cfg_mgmt_read_data                          ,
    output              cfg_mgmt_read_write_done                    ,
    input               cfg_mgmt_debug_access                       ,
    
    //---pcie msi bus interface--------------------------//
    //INT-X
    input       [3:0]   cfg_interrupt_int                           ,
    input       [1:0]   cfg_interrupt_pending                       ,
    output              cfg_interrupt_sent                          ,
    //MSI
    output      [3:0]   cfg_interrupt_msi_enable                    ,
    output      [11:0]  cfg_interrupt_msi_mmenable                  ,
    output              cfg_interrupt_msi_mask_update               ,
    output      [31:0]  cfg_interrupt_msi_data                      ,
    input       [1:0]   cfg_interrupt_msi_select                    ,
    input       [31:0]  cfg_interrupt_msi_int                       ,
    input       [31:0]  cfg_interrupt_msi_pending_status            ,
    input               cfg_interrupt_msi_pending_status_data_enable,
    input       [1:0]   cfg_interrupt_msi_pending_status_function_num,
    output              cfg_interrupt_msi_sent                      ,
    output              cfg_interrupt_msi_fail                      ,
    input       [2:0]   cfg_interrupt_msi_attr                      ,
    input               cfg_interrupt_msi_tph_present               ,
    input       [1:0]   cfg_interrupt_msi_tph_type                  ,
    input       [7:0]   cfg_interrupt_msi_tph_st_tag                ,
    input       [7:0]   cfg_interrupt_msi_function_number           ,
    //MSI-X
    output      [1:0]   cfg_interrupt_msix_enable                   , 
    output      [1:0]   cfg_interrupt_msix_mask                     , 
    output      [5:0]   cfg_interrupt_msix_vf_enable                , 
    output      [5:0]   cfg_interrupt_msix_vf_mask                  , 
    input       [63:0]  cfg_interrupt_msix_address                  , 
    input       [31:0]  cfg_interrupt_msix_data                     , 
    input               cfg_interrupt_msix_int                      , 
    output              cfg_interrupt_msix_sent                     , 
    //---pcie sideband bus interface-----------------------//
    output      [5:0]   pcie_rq_seq_num0                            ,
    output              pcie_rq_seq_num_vld0                        ,
    output      [5:0]   pcie_rq_seq_num1                            ,
    output              pcie_rq_seq_num_vld1                        ,
    output      [7:0]   pcie_rq_tag0                                ,
    output      [7:0]   pcie_rq_tag1                                ,
    output      [3:0]   pcie_rq_tag_av                              ,
    output              pcie_rq_tag_vld0                            ,
    output              pcie_rq_tag_vld1                            ,
    output      [3:0]   pcie_tfc_nph_av                             ,
    output      [3:0]   pcie_tfc_npd_av                             ,
    input       [1:0]   pcie_cq_np_req                              ,
    output      [5:0]   pcie_cq_np_req_count                        ,
    output              cfg_phy_link_down                           ,
    output      [1:0]   cfg_phy_link_status                         ,
    output      [2:0]   cfg_negotiated_width                        ,
    output      [1:0]   cfg_current_speed                           ,
    output      [1:0]   cfg_max_payload                             ,
    output      [2:0]   cfg_max_read_req                            ,
    output      [15:0]  cfg_function_status                         ,
    output      [11:0]  cfg_function_power_state                    ,
    output      [503:0] cfg_vf_status                               ,
    output      [755:0] cfg_vf_power_state                          ,
    output      [1:0]   cfg_link_power_state                        ,
    output              cfg_err_cor_out                             ,
    output              cfg_err_nonfatal_out                        ,
    output              cfg_err_fatal_out                           ,
    output              cfg_local_error_valid                       ,
    output      [4:0]   cfg_local_error_out                         ,
    output      [5:0]   cfg_ltssm_state                             ,
    output      [1:0]   cfg_rx_pm_state                             ,                               
    output      [1:0]   cfg_tx_pm_state                             ,
    output      [3:0]   cfg_rcb_status                              ,
    output      [1:0]   cfg_obff_enable                             ,
    output              cfg_pl_status_change                        ,
    output      [3:0]   cfg_tph_requester_enable                    ,
    output      [11:0]  cfg_tph_st_mode                             ,
    output      [251:0] cfg_vf_tph_requester_enable                 ,
    output      [755:0] cfg_vf_tph_st_mode                          ,
    output              cfg_msg_received                            ,
    output      [7:0]   cfg_msg_received_data                       ,
    output      [4:0]   cfg_msg_received_type                       ,
    input               cfg_msg_transmit                            ,
    input       [2:0]   cfg_msg_transmit_type                       ,
    input       [31:0]  cfg_msg_transmit_data                       ,
    output              cfg_msg_transmit_done                       ,
    output      [7:0]   cfg_fc_ph                                   ,
    output      [11:0]  cfg_fc_pd                                   ,
    output      [7:0]   cfg_fc_nph                                  ,
    output      [11:0]  cfg_fc_npd                                  ,
    output      [7:0]   cfg_fc_cplh                                 ,
    output      [11:0]  cfg_fc_cpld                                 ,
    input       [2:0]   cfg_fc_sel                                  ,
    input       [63:0]  cfg_dsn                                     ,
    output      [7:0]   cfg_bus_number                              ,
    input               cfg_power_state_change_ack                  ,
    output              cfg_power_state_change_interrupt            ,
    input               cfg_err_cor_in                              ,
    input               cfg_err_uncor_in                            ,
    output      [3:0]   cfg_flr_in_process                          ,
    input       [3:0]   cfg_flr_done                                ,
    output      [251:0] cfg_vf_flr_in_process                       ,
    input       [7:0]   cfg_vf_flr_func_num                         ,
    input       [0:0]   cfg_vf_flr_done                             ,
    input               cfg_link_training_enable                    ,
    input               cfg_pm_aspm_l1_entry_reject                 ,
    input               cfg_pm_aspm_tx_l0s_entry_disable            ,
    output              cfg_hot_reset_out                           ,
    input               cfg_config_space_enable                     ,
    input               cfg_req_pm_transition_l23_ready             ,
    input               cfg_hot_reset_in                            ,
    input       [7:0]   cfg_ds_port_number                          ,
    input       [7:0]   cfg_ds_bus_number                           ,
    input       [4:0]   cfg_ds_device_number                        ,
    input               sys_reset                                   ,
    output              phy_rdy_out                                 

);


// ====================================================================
// Parameter/wire/reg
// ====================================================================
// PCIE connection
    wire  [DATA_WIDTH-1:0]  client0_tlp_data         ;
    wire  [63:0]   client0_tlp_addr         ;
    wire  [15:0]   client0_remote_req_id    ;
    wire  [7:0]    client0_tlp_byte_en      ;
    wire  [11:0]   client0_cpl_byte_cnt     ;
    wire           client0_addr_align_en    ;
    wire  [2:0]    client0_tlp_tc           ;
    wire  [2:0]    client0_tlp_attr         ;
    wire  [2:0]    client0_cpl_status       ;
    wire           client0_cpl_bcm          ;
    wire           client0_tlp_dv           ;
    wire           client0_tlp_eot          ;
    wire           client0_tlp_bad_eot      ;
    wire           client0_tlp_hv           ;
    wire  [4:0]    client0_tlp_type         ;
    wire  [1:0]    client0_tlp_fmt          ;
    wire           client0_tlp_td           ;
    wire  [12:0]   client0_tlp_byte_len     ;
    wire  [9:0]    client0_tlp_tid          ;
    wire           client0_tlp_ep           ;
    wire           client0_tlp_func_num     ;
    wire  [1:0]    client0_tlp_vfunc_num    ;
    wire  [1:0]    client0_tlp_ats          ;
    wire  [7:0]    client0_tlp_st           ;
    wire           client0_tlp_vfunc_active ;
    wire           client0_tlp_nw           ;
    wire           client0_tlp_th           ;
    wire  [1:0]    client0_tlp_ph           ;
    wire           client0_tlp_atu_bypass   ;
    wire  [9:0]    client0_cpl_lookup_id    ;
    wire           xadm_client0_halt        ;

    wire  [DATA_WIDTH-1:0]  client1_tlp_data         ;
    wire  [63:0]   client1_tlp_addr         ;
    wire  [15:0]   client1_remote_req_id    ;
    wire  [7:0]    client1_tlp_byte_en      ;
    wire  [11:0]   client1_cpl_byte_cnt     ;
    wire           client1_addr_align_en    ;
    wire  [2:0]    client1_tlp_tc           ;
    wire  [2:0]    client1_tlp_attr         ;
    wire  [2:0]    client1_cpl_status       ;
    wire           client1_cpl_bcm          ;
    wire           client1_tlp_dv           ;
    wire           client1_tlp_eot          ;
    wire           client1_tlp_bad_eot      ;
    wire           client1_tlp_hv           ;
    wire  [4:0]    client1_tlp_type         ;
    wire  [1:0]    client1_tlp_fmt          ;
    wire           client1_tlp_td           ;
    wire  [12:0]   client1_tlp_byte_len     ;
    wire  [9:0]    client1_tlp_tid          ;
    wire           client1_tlp_ep           ;
    wire           client1_tlp_func_num     ;
    wire  [1:0]    client1_tlp_vfunc_num    ;
    wire  [1:0]    client1_tlp_ats          ;
    wire  [7:0]    client1_tlp_st           ;
    wire           client1_tlp_vfunc_active ;
    wire           client1_tlp_nw           ;
    wire           client1_tlp_th           ;
    wire  [1:0]    client1_tlp_ph           ;
    wire           client1_tlp_atu_bypass   ;
    wire  [9:0]    client1_cpl_lookup_id    ;
    wire           xadm_client1_halt        ;

    wire  [31:0]   ext_drp_dbi_din              ;
    wire  [3:0]    ext_drp_dbi_wr               ;
    wire  [31:0]   ext_drp_dbi_addr             ;
    wire           ext_drp_dbi_cs               ;
    wire           ext_drp_dbi_cs2_exp          ;
    wire  [1:0]    ext_drp_dbi_vfunc_num        ;
    wire           ext_drp_dbi_vfunc_active     ;
    wire  [2:0]    ext_drp_dbi_bar_num          ;
    wire           ext_drp_dbi_rom_access       ;
    wire           ext_drp_dbi_io_access        ;
    wire           ext_drp_dbi_func_num         ;
    wire           ext_drp_app_dbi_ro_wr_disable;
    wire    [31:0] ext_drp_lbc_dbi_dout         ;
    wire           ext_drp_lbc_dbi_ack          ;    

    wire  [DATA_WIDTH-1:0]  radm_bypass_data;
    wire  [3:0]    radm_bypass_dwen         ;
    wire           radm_bypass_dv           ;
    wire           radm_bypass_hv           ;
    wire           radm_bypass_eot          ;
    wire           radm_bypass_dllp_abort   ;
    wire           radm_bypass_tlp_abort    ;
    wire           radm_bypass_ecrc_err     ;
    wire  [63:0]   radm_bypass_addr         ;
    wire  [1:0]    radm_bypass_fmt          ;
    wire  [2:0]    radm_bypass_tc           ;
    wire  [2:0]    radm_bypass_attr         ;
    wire  [15:0]   radm_bypass_reqid        ;
    wire  [4:0]    radm_bypass_type         ;
    wire  [9:0]    radm_bypass_tag          ;
    wire           radm_bypass_func_num     ;
    wire  [1:0]    radm_bypass_vfunc_num    ;
    wire           radm_bypass_vfunc_active ;
    wire           radm_bypass_td           ;
    wire           radm_bypass_poisoned     ;
    wire  [9:0]    radm_bypass_dw_len       ;
    wire           radm_bypass_rom_in_range ;
    wire  [3:0]    radm_bypass_first_be     ;
    wire  [3:0]    radm_bypass_last_be      ;
    wire           radm_bypass_io_req_in_range ;
    wire  [2:0]    radm_bypass_in_membar_range ;
    wire           radm_bypass_cpl_last     ;
    wire  [2:0]    radm_bypass_cpl_status   ;
    wire  [7:0]    radm_bypass_st           ;
    wire  [15:0]   radm_bypass_cmpltr_id    ;
    wire  [11:0]   radm_bypass_byte_cnt     ;
    wire  [1:0]    radm_bypass_ats          ;
    wire           radm_bypass_th           ;
    wire  [1:0]    radm_bypass_ph           ;
    wire           radm_bypass_bcm          ;

    wire           radm_trgt1_dv            ;
    wire           radm_trgt1_hv            ;
    wire           radm_trgt1_eot           ;
    wire           radm_trgt1_tlp_abort     ;
    wire           radm_trgt1_dllp_abort    ;
    wire           radm_trgt1_ecrc_err      ;
    wire  [3:0]    radm_trgt1_dwen          ;
    wire  [1:0]    radm_trgt1_fmt           ;
    wire  [2:0]    radm_trgt1_attr          ;
    wire           radm_trgt1_func_num      ;
    wire  [4:0]    radm_trgt1_type          ;
    wire  [2:0]    radm_trgt1_tc            ;
    wire  [15:0]   radm_trgt1_reqid         ;
    wire  [DATA_WIDTH-1:0]  radm_trgt1_data ;
    wire  [3:0]    radm_trgt1_first_be      ;
    wire  [3:0]    radm_trgt1_last_be       ;
    wire  [63:0]   radm_trgt1_addr          ;
    wire  [1:0]    radm_trgt1_vfunc_num     ;
    wire           radm_trgt1_vfunc_active  ;
    wire           radm_trgt1_td            ;
    wire           radm_trgt1_poisoned      ;
    wire           radm_trgt1_hdr_uppr_bytes_valid ;
    wire           radm_trgt1_rom_in_range  ;
    wire           radm_trgt1_io_req_in_range;
    wire  [63:0]   radm_trgt1_hdr_uppr_bytes;
    wire  [2:0]    radm_trgt1_in_membar_range;
    wire  [2:0]    radm_trgt1_cpl_status    ;
    wire  [1:0]    radm_trgt1_ats           ;
    wire  [9:0]    radm_trgt1_tag           ;
    wire  [9:0]    radm_trgt1_dw_len        ;
    wire           radm_trgt1_nw            ;
    wire           radm_trgt1_th            ;
    wire  [1:0]    radm_trgt1_ph            ;
    wire  [7:0]    radm_trgt1_st            ;
    wire  [11:0]   radm_trgt1_byte_cnt      ;
    wire           radm_trgt1_bcm           ;
    wire  [2:0]    radm_trgt1_vc            ;
    wire  [15:0]   radm_trgt1_cmpltr_id     ;
    wire           radm_trgt1_cpl_last      ;
    wire  [2:0]    radm_grant_tlp_type      ;       
    wire  [1:0]    radm_trgt1_atu_sloc_match;
    wire  [1:0]    radm_trgt1_atu_cbuf_err  ;
    wire  [9:0]    trgt_lookup_id           ;
    wire           trgt_lookup_empty        ; 
    wire           trgt1_radm_halt          ;
    wire  [2:0]    trgt1_radm_pkt_halt      ;    

    wire  [1:0]    cfg_msi_en               ;
    wire  [63:0]   cfg_msi_mask             ;
    wire           ven_msi_grant            ;
    wire           ven_msi_req              ;
    wire           ven_msi_func_num         ;
    wire  [63:0]   cfg_msi_pending          ;
    wire  [1:0]    ven_msi_vfunc_num        ;
    wire           ven_msi_vfunc_active     ;
    wire  [2:0]    ven_msi_tc               ;
    wire  [4:0]    ven_msi_vector           ;

    wire           msix_sent;
    //--- msic signals-------------------------//
    wire            core_rst_n              ;
    wire            rdlh_link_up            ;
    wire  [5:0]     smlh_ltssm_state        ;
    //---make connection with cc when need look up id------//
    wire  [9:0]     rq_lookup_addr          ;
    wire  [9:0]     rq_lookup_dout          ;
    
    wire  [3:0]     client02rq_debug        ;
    wire  [3:0]     client12cc_debug        ;
    wire  [3:0]     bypass2rc_debug         ;
    wire  [3:0]     trgt2cq_debug           ;    

    wire                    m_axis_rq_tvalid        ;
    wire  [3:0]             m_axis_rq_tready        ;
    wire  [DATA_WIDTH-1:0]  m_axis_rq_tdata;
    wire  [DW_WIDTH-1:0]    m_axis_rq_tkeep;
    wire                    m_axis_rq_tlast         ;
    wire  [RQ_USER_WIDTH:0] m_axis_rq_tuser         ;

    wire                    s_axis_msix_rq_tvalid;
    wire  [3:0]             s_axis_msix_rq_tready;
    wire  [DATA_WIDTH-1:0]  s_axis_msix_rq_tdata ;
    wire  [DW_WIDTH-1:0]    s_axis_msix_rq_tkeep ;
    wire                    s_axis_msix_rq_tlast ;
    wire  [61:0]            s_axis_msix_rq_tuser ;    

    wire            core_clk;
    // wire            core_rst_n;
// ====================================================================
// Start of Main Code
// ====================================================================
assign      user_reset  =  !user_link_up;
assign      phy_rdy_out =   rdlh_link_up;  

axi4_st_mux #(
    .C_AXI_DATA_WIDTH       ( DATA_WIDTH        ),     
    .C_KEEP_WIDTH           ( DW_WIDTH          ),     
    .TCQ                    ( 1                 )                    
    ) u_axi4_st_mux(    
    .user_clk               (user_clk           ),
    .user_reset             (!core_rst_n        ),
    //-------------------------------------------------
    // AXI-S TX Interface to PCIe Hard Block
    //-------------------------------------------------
    .m_axis_tx_tdata        (m_axis_rq_tdata ),   // TX data
    .m_axis_tx_tvalid       (m_axis_rq_tvalid),  // TX data is valid
    .m_axis_tx_tready       (m_axis_rq_tready),  // TX ready for data
    .m_axis_tx_tkeep        (m_axis_rq_tkeep ),   // TX strobe byte enables
    .m_axis_tx_tlast        (m_axis_rq_tlast ),   // TX data is last
    .m_axis_tx_tuser        (m_axis_rq_tuser ),   // TX user signals
    //-------------------------------------------------
    // AXI-S TX Interface from DMA REQ
    //-------------------------------------------------
    .s_axis_tx_req_tdata    (s_axis_rq_tdata ),   // TX data
    .s_axis_tx_req_tvalid   (s_axis_rq_tvalid),  // TX data is valid
    .s_axis_tx_req_tready   (s_axis_rq_tready),  // TX ready for data
    .s_axis_tx_req_tkeep    (s_axis_rq_tkeep ),   // TX strobe byte enables
    .s_axis_tx_req_tlast    (s_axis_rq_tlast ),   // TX data is last
    .s_axis_tx_req_tuser    (s_axis_rq_tuser ),   // TX user signals
    //-------------------------------------------------
    // AXI-S TX Interface from CFG Sideband            
    //-------------------------------------------------
    .s_axis_tx_msix_tdata   (s_axis_msix_rq_tdata ),  // TX data
    .s_axis_tx_msix_tvalid  (s_axis_msix_rq_tvalid), // TX data is valid
    .s_axis_tx_msix_tready  (s_axis_msix_rq_tready), // TX ready for data
    .s_axis_tx_msix_tkeep   (s_axis_msix_rq_tkeep ),  // TX strobe byte enables
    .s_axis_tx_msix_tlast   (s_axis_msix_rq_tlast ),  // TX data is last
    .s_axis_tx_msix_tuser   (s_axis_msix_rq_tuser )   // TX user signals
);

// assign  m_axis_rq_tdata = s_axis_rq_tdata;
// assign  m_axis_rq_tvalid = s_axis_rq_tvalid;
// assign  s_axis_rq_tready = m_axis_rq_tready;
// assign  m_axis_rq_tkeep = s_axis_rq_tkeep;
// assign  m_axis_rq_tlast = s_axis_rq_tlast;
// assign  m_axis_rq_tuser = s_axis_rq_tuser;


// --------------------------------------------------------------------
// Tx Side
// --------------------------------------------------------------------    
pcie_tx_client02rq
#(
    .DATA_WIDTH                         (DATA_WIDTH),
    .DW_WIDTH                           (DW_WIDTH),
    .USER_WIDTH                         (RQ_USER_WIDTH)

)
u_pcie_tx_client02rq(
    
    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                          )
    ,.core_rst_n                        (core_rst_n                        )
    //---native client interface-------------------------------//
    ,.client0_tlp_data                  (client0_tlp_data                  )                   
    ,.client0_tlp_addr                  (client0_tlp_addr                  ) 
    ,.client0_remote_req_id             (client0_remote_req_id             ) 
    ,.client0_tlp_byte_en               (client0_tlp_byte_en               ) 
    ,.client0_cpl_byte_cnt              (client0_cpl_byte_cnt              )
    ,.client0_addr_align_en             (client0_addr_align_en             )
    ,.client0_tlp_tc                    (client0_tlp_tc                    )
    ,.client0_tlp_attr                  (client0_tlp_attr                  )
    ,.client0_cpl_status                (client0_cpl_status                )
    ,.client0_cpl_bcm                   (client0_cpl_bcm                   )
    ,.client0_tlp_dv                    (client0_tlp_dv                    ) 
    ,.client0_tlp_eot                   (client0_tlp_eot                   ) 
    ,.client0_tlp_bad_eot               (client0_tlp_bad_eot               )
    ,.client0_tlp_hv                    (client0_tlp_hv                    ) 
    ,.client0_tlp_type                  (client0_tlp_type                  )
    ,.client0_tlp_fmt                   (client0_tlp_fmt                   )
    ,.client0_tlp_td                    (client0_tlp_td                    )
    ,.client0_tlp_byte_len              (client0_tlp_byte_len              )
    ,.client0_tlp_tid                   (client0_tlp_tid                   )
    ,.client0_tlp_ep                    (client0_tlp_ep                    )
    ,.client0_tlp_func_num              (client0_tlp_func_num              )
    ,.client0_tlp_vfunc_num             (client0_tlp_vfunc_num             )
    ,.client0_tlp_ats                   (client0_tlp_ats                   )
    ,.client0_tlp_st                    (client0_tlp_st                    )
    ,.client0_tlp_vfunc_active          (client0_tlp_vfunc_active          )
    ,.client0_tlp_nw                    (client0_tlp_nw                    )
    ,.client0_tlp_th                    (client0_tlp_th                    )
    ,.client0_tlp_ph                    (client0_tlp_ph                    )
    ,.client0_tlp_atu_bypass            (client0_tlp_atu_bypass            )
    ,.client0_cpl_lookup_id             (client0_cpl_lookup_id             )
    ,.xadm_client0_halt                 (xadm_client0_halt                 )

    //---axi rq bus interface-------------------------------//
    ,.s_axis_rq_tvalid                  (m_axis_rq_tvalid                  )                        
    ,.s_axis_rq_tready                  (m_axis_rq_tready                  )        
    ,.s_axis_rq_tdata                   (m_axis_rq_tdata                   )        
    ,.s_axis_rq_tkeep                   (m_axis_rq_tkeep                   )        
    ,.s_axis_rq_tlast                   (m_axis_rq_tlast                   )        
    ,.s_axis_rq_tuser                   (m_axis_rq_tuser                   )        

    //---only for debug---------------------------------------//
    ,.client02rq_tuser_o                (client02rq_tuser_o                )
    ,.msix_sent_o                       (msix_sent                         )
    ,.client02rq_debug                  (client02rq_debug                  )
);

pcie_tx_client12cc #(
    .DATA_WIDTH                         (DATA_WIDTH),
    .DW_WIDTH                           (DW_WIDTH),
    .USER_WIDTH                         (CC_USER_WIDTH),
    .NBYTE_WIDTH                        (DATA_WIDTH/8)
) u_pcie_tx_client12cc(
    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                          )
    ,.core_rst_n                        (core_rst_n                        )

    //---native client interface-------------------------------//
    ,.client1_tlp_data                  (client1_tlp_data                  )                   
    ,.client1_tlp_addr                  (client1_tlp_addr                  ) 
    ,.client1_remote_req_id             (client1_remote_req_id             ) 
    ,.client1_tlp_byte_en               (client1_tlp_byte_en               ) 
    ,.client1_cpl_byte_cnt              (client1_cpl_byte_cnt              )
    ,.client1_addr_align_en             (client1_addr_align_en             )
    ,.client1_tlp_tc                    (client1_tlp_tc                    )
    ,.client1_tlp_attr                  (client1_tlp_attr                  )
    ,.client1_cpl_status                (client1_cpl_status                )
    ,.client1_cpl_bcm                   (client1_cpl_bcm                   )
    ,.client1_tlp_dv                    (client1_tlp_dv                    ) 
    ,.client1_tlp_eot                   (client1_tlp_eot                   ) 
    ,.client1_tlp_bad_eot               (client1_tlp_bad_eot               )
    ,.client1_tlp_hv                    (client1_tlp_hv                    ) 
    ,.client1_tlp_type                  (client1_tlp_type                  )
    ,.client1_tlp_fmt                   (client1_tlp_fmt                   )
    ,.client1_tlp_td                    (client1_tlp_td                    )
    ,.client1_tlp_byte_len              (client1_tlp_byte_len              )
    ,.client1_tlp_tid                   (client1_tlp_tid                   )
    ,.client1_tlp_ep                    (client1_tlp_ep                    )
    ,.client1_tlp_func_num              (client1_tlp_func_num              )
    ,.client1_tlp_vfunc_num             (client1_tlp_vfunc_num             )
    ,.client1_tlp_ats                   (client1_tlp_ats                   )
    ,.client1_tlp_st                    (client1_tlp_st                    )
    ,.client1_tlp_vfunc_active          (client1_tlp_vfunc_active          )
    ,.client1_tlp_nw                    (client1_tlp_nw                    )
    ,.client1_tlp_th                    (client1_tlp_th                    )
    ,.client1_tlp_ph                    (client1_tlp_ph                    )
    ,.client1_tlp_atu_bypass            (client1_tlp_atu_bypass            )
    ,.client1_cpl_lookup_id             (client1_cpl_lookup_id             )
    ,.xadm_client1_halt                 (xadm_client1_halt                 )
   
    //---make connection with cc when need look up id------//    
    ,.rq_lookup_addr                    (rq_lookup_addr                    )
    ,.rq_lookup_dout                    (rq_lookup_dout                    )

    //---axi rq bus interface-------------------------------//
    ,.s_axis_cc_tvalid                  (s_axis_cc_tvalid                  )                        
    ,.s_axis_cc_tready                  (s_axis_cc_tready                  )        
    ,.s_axis_cc_tdata                   (s_axis_cc_tdata                   )        
    ,.s_axis_cc_tkeep                   (s_axis_cc_tkeep                   )        
    ,.s_axis_cc_tlast                   (s_axis_cc_tlast                   )        
    ,.s_axis_cc_tuser                   (s_axis_cc_tuser                   )        

    //---only for debug---------------------------------------//
    ,.client12cc_debug                  (client12cc_debug                  )
);
// --------------------------------------------------------------------
// Rx Side
// --------------------------------------------------------------------    
pcie_rx_bypass2rc #(
    .DATA_WIDTH                         ( DATA_WIDTH ),
    .DW_WIDTH                           ( DW_WIDTH   ),
    .USER_WIDTH                         ( RC_USER_WIDTH  )
) u_pcie_rx_bypass2rc(

    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                          )
    ,.core_rst_n                        (core_rst_n                        )

    //---native radm bypass interface------------------------//
    ,.radm_bypass_data                  (radm_bypass_data                  )  
    ,.radm_bypass_dwen                  (radm_bypass_dwen                  )
    ,.radm_bypass_dv                    (radm_bypass_dv                    )
    ,.radm_bypass_hv                    (radm_bypass_hv                    )
    ,.radm_bypass_eot                   (radm_bypass_eot                   )
    ,.radm_bypass_dllp_abort            (radm_bypass_dllp_abort            )
    ,.radm_bypass_tlp_abort             (radm_bypass_tlp_abort             )
    ,.radm_bypass_ecrc_err              (radm_bypass_ecrc_err              )
    ,.radm_bypass_addr                  (radm_bypass_addr                  )
    ,.radm_bypass_fmt                   (radm_bypass_fmt                   )
    ,.radm_bypass_tc                    (radm_bypass_tc                    )
    ,.radm_bypass_attr                  (radm_bypass_attr                  )
    ,.radm_bypass_reqid                 (radm_bypass_reqid                 )
    ,.radm_bypass_type                  (radm_bypass_type                  )
    ,.radm_bypass_tag                   (radm_bypass_tag                   )
    ,.radm_bypass_func_num              (radm_bypass_func_num              )
    ,.radm_bypass_vfunc_num             (radm_bypass_vfunc_num             )
    ,.radm_bypass_vfunc_active          (radm_bypass_vfunc_active          )
    ,.radm_bypass_td                    (radm_bypass_td                    )
    ,.radm_bypass_poisoned              (radm_bypass_poisoned              )
    ,.radm_bypass_dw_len                (radm_bypass_dw_len                )
    ,.radm_bypass_rom_in_range          (radm_bypass_rom_in_range          )
    ,.radm_bypass_first_be              (radm_bypass_first_be              )
    ,.radm_bypass_last_be               (radm_bypass_last_be               )
    ,.radm_bypass_io_req_in_range       (radm_bypass_io_req_in_range       )
    ,.radm_bypass_in_membar_range       (radm_bypass_in_membar_range       )
    ,.radm_bypass_cpl_last              (radm_bypass_cpl_last              )
    ,.radm_bypass_cpl_status            (radm_bypass_cpl_status            )
    ,.radm_bypass_st                    (radm_bypass_st                    )
    ,.radm_bypass_cmpltr_id             (radm_bypass_cmpltr_id             )
    ,.radm_bypass_byte_cnt              (radm_bypass_byte_cnt              )
    ,.radm_bypass_ats                   (radm_bypass_ats                   )
    ,.radm_bypass_th                    (radm_bypass_th                    )
    ,.radm_bypass_ph                    (radm_bypass_ph                    )
    ,.radm_bypass_bcm                   (radm_bypass_bcm                   )
    
    //---convert requester completion package------------------//
    ,.m_axis_rc_tdata                   (m_axis_rc_tdata                    )                           
    ,.m_axis_rc_tkeep                   (m_axis_rc_tkeep                    )           
    ,.m_axis_rc_tlast                   (m_axis_rc_tlast                    )           
    ,.m_axis_rc_tuser                   (m_axis_rc_tuser                    )           
    ,.m_axis_rc_tvalid                  (m_axis_rc_tvalid                   )           
    ,.m_axis_rc_tready                  (m_axis_rc_tready                   )           

    //---only for debug---------------------------------------//
    ,.bypass2rc_debug                   (bypass2rc_debug                    )
);


pcie_rx_trgt2cq #(
    .DATA_WIDTH                         (DATA_WIDTH                         ),
    .DW_WIDTH                           (DW_WIDTH                           ),
    .USER_WIDTH                         (CQ_USER_WIDTH                      )
) u_pcie_rx_trgt2cq(

    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                           )
    ,.core_rst_n                        (core_rst_n                         )

    //---native trgt1 radm interface-------------------------//
    ,.radm_trgt1_dv                     (radm_trgt1_dv                      )                           
    ,.radm_trgt1_hv                     (radm_trgt1_hv                      )       
    ,.radm_trgt1_eot                    (radm_trgt1_eot                     )       
    ,.radm_trgt1_tlp_abort              (radm_trgt1_tlp_abort               )           
    ,.radm_trgt1_dllp_abort             (radm_trgt1_dllp_abort              )               
    ,.radm_trgt1_ecrc_err               (radm_trgt1_ecrc_err                )           
    ,.radm_trgt1_dwen                   (radm_trgt1_dwen                    )       
    ,.radm_trgt1_fmt                    (radm_trgt1_fmt                     )       
    ,.radm_trgt1_attr                   (radm_trgt1_attr                    )       
    ,.radm_trgt1_func_num               (radm_trgt1_func_num                )           
    ,.radm_trgt1_type                   (radm_trgt1_type                    )       
    ,.radm_trgt1_tc                     (radm_trgt1_tc                      )       
    ,.radm_trgt1_reqid                  (radm_trgt1_reqid                   )       
    ,.radm_trgt1_data                   (radm_trgt1_data                    )       
    ,.radm_trgt1_first_be               (radm_trgt1_first_be                )           
    ,.radm_trgt1_last_be                (radm_trgt1_last_be                 )           
    ,.radm_trgt1_addr                   (radm_trgt1_addr                    )       
    ,.radm_trgt1_vfunc_num              (radm_trgt1_vfunc_num               )           
    ,.radm_trgt1_vfunc_active           (radm_trgt1_vfunc_active            )               
    ,.radm_trgt1_td                     (radm_trgt1_td                      )       
    ,.radm_trgt1_poisoned               (radm_trgt1_poisoned                )           
    ,.radm_trgt1_hdr_uppr_bytes_valid   (radm_trgt1_hdr_uppr_bytes_valid    )                       
    ,.radm_trgt1_rom_in_range           (radm_trgt1_rom_in_range            )               
    ,.radm_trgt1_io_req_in_range        (radm_trgt1_io_req_in_range         )                   
    ,.radm_trgt1_hdr_uppr_bytes         (radm_trgt1_hdr_uppr_bytes          )                   
    ,.radm_trgt1_in_membar_range        (radm_trgt1_in_membar_range         )                   
    ,.radm_trgt1_cpl_status             (radm_trgt1_cpl_status              )               
    ,.radm_trgt1_ats                    (radm_trgt1_ats                     )           
    ,.radm_trgt1_tag                    (radm_trgt1_tag                     )           
    ,.radm_trgt1_dw_len                 (radm_trgt1_dw_len                  )           
    ,.radm_trgt1_nw                     (radm_trgt1_nw                      )           
    ,.radm_trgt1_th                     (radm_trgt1_th                      )           
    ,.radm_trgt1_ph                     (radm_trgt1_ph                      )           
    ,.radm_trgt1_st                     (radm_trgt1_st                      )           
    ,.radm_trgt1_byte_cnt               (radm_trgt1_byte_cnt                )           
    ,.radm_trgt1_bcm                    (radm_trgt1_bcm                     )           
    ,.radm_trgt1_vc                     (radm_trgt1_vc                      )           
    ,.radm_trgt1_cmpltr_id              (radm_trgt1_cmpltr_id               )           
    ,.radm_trgt1_cpl_last               (radm_trgt1_cpl_last                )           
    ,.radm_grant_tlp_type               (radm_grant_tlp_type                )           
    ,.radm_trgt1_atu_sloc_match         (radm_trgt1_atu_sloc_match          )                   
    ,.radm_trgt1_atu_cbuf_err           (radm_trgt1_atu_cbuf_err            )               
    ,.trgt_lookup_id                    (trgt_lookup_id                     )               
    ,.trgt_lookup_empty                 (trgt_lookup_empty                  )               
    ,.trgt1_radm_halt                   (trgt1_radm_halt                    )               
    ,.trgt1_radm_pkt_halt               (trgt1_radm_pkt_halt                )
    //---make connection with cc when need look up id------//
    ,.rq_lookup_addr                    (rq_lookup_addr                     )
    ,.rq_lookup_dout                    (rq_lookup_dout                     )
    //---convert completer requester package --------------//
    ,.m_axis_cq_tvalid                  (m_axis_cq_tvalid                   )                           
    ,.m_axis_cq_tdata                   (m_axis_cq_tdata                    )       
    ,.m_axis_cq_tkeep                   (m_axis_cq_tkeep                    )       
    ,.m_axis_cq_tlast                   (m_axis_cq_tlast                    )       
    ,.m_axis_cq_tuser                   (m_axis_cq_tuser                    )       
    ,.m_axis_cq_tready                  (m_axis_cq_tready                   )       

    //---only for debug---------------------------------------//
    ,.trgt2cq_debug                     (trgt2cq_debug                      )
);


// --------------------------------------------------------------------
// SideBand , mgmt/msi
// -------------------------------------------------------------------- 
pcie_sideband_dbi2mgmt u_pcie_sideband_dbi2mgmt(
    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                           )
    ,.core_rst_n                        (core_rst_n                         )
    
    //---native dbi interface-------------------------------//
    ,.ext_drp_dbi_din                   (ext_drp_dbi_din                    )               
    ,.ext_drp_dbi_wr                    (ext_drp_dbi_wr                     )  
    ,.ext_drp_dbi_addr                  (ext_drp_dbi_addr                   )  
    ,.ext_drp_dbi_cs                    (ext_drp_dbi_cs                     )  
    ,.ext_drp_dbi_cs2_exp               (ext_drp_dbi_cs2_exp                )  
    ,.ext_drp_dbi_vfunc_num             (ext_drp_dbi_vfunc_num              )  
    ,.ext_drp_dbi_vfunc_active          (ext_drp_dbi_vfunc_active           )  
    ,.ext_drp_dbi_bar_num               (ext_drp_dbi_bar_num                )  
    ,.ext_drp_dbi_rom_access            (ext_drp_dbi_rom_access             )  
    ,.ext_drp_dbi_io_access             (ext_drp_dbi_io_access              )  
    ,.ext_drp_dbi_func_num              (ext_drp_dbi_func_num               )  
    ,.ext_drp_app_dbi_ro_wr_disable     (ext_drp_app_dbi_ro_wr_disable      )  
    ,.ext_drp_lbc_dbi_dout              (ext_drp_lbc_dbi_dout               )  
    ,.ext_drp_lbc_dbi_ack               (ext_drp_lbc_dbi_ack                )  

    //---convert mgmt interface------------------------------//
    ,.cfg_mgmt_addr                     (cfg_mgmt_addr                      )           
    ,.cfg_mgmt_function_number          (cfg_mgmt_function_number           )       
    ,.cfg_mgmt_write                    (cfg_mgmt_write                     )           
    ,.cfg_mgmt_write_data               (cfg_mgmt_write_data                )           
    ,.cfg_mgmt_byte_enable              (cfg_mgmt_byte_enable               )       
    ,.cfg_mgmt_read                     (cfg_mgmt_read                      )       
    ,.cfg_mgmt_read_data                (cfg_mgmt_read_data                 )           
    ,.cfg_mgmt_read_write_done          (cfg_mgmt_read_write_done           )       
    ,.cfg_mgmt_debug_access             (cfg_mgmt_debug_access              )       

    //---only for debug---------------------------------------//
    ,.dbi2mgmt_debug                    (dbi2mgmt_debug                     )
);


pcie_sideband_msi #(
    .DATA_WIDTH                         (DATA_WIDTH                         )
    ) u_pcie_sideband_msi(
    //---system clock and reset------------------------------//
     .core_clk                          (user_clk                           )
    ,.core_rst_n                        (core_rst_n                         )

    //---native ven_msi interface-------------------------------//
    ,.ven_msi_req                       (ven_msi_req                        )
    ,.ven_msi_func_num                  (ven_msi_func_num                   )
    ,.cfg_msi_pending                   (cfg_msi_pending                    )
    ,.ven_msi_vfunc_num                 (ven_msi_vfunc_num                  )
    ,.ven_msi_vfunc_active              (ven_msi_vfunc_active               )
    ,.ven_msi_tc                        (ven_msi_tc                         )
    ,.ven_msi_vector                    (ven_msi_vector                     )
    ,.cfg_msi_en                        (cfg_msi_en                         )
    ,.cfg_msi_mask                      (cfg_msi_mask                       )
    ,.ven_msi_grant                     (ven_msi_grant                      )

    //---cfg msi bus interface-------------------------------//
    // legacy int not support now
    ,.cfg_interrupt_int                 (cfg_interrupt_int                  )                           
    ,.cfg_interrupt_pending             (cfg_interrupt_pending              )       
    ,.cfg_interrupt_sent                (cfg_interrupt_sent                 )                           
    // msi signals
    ,.cfg_interrupt_msi_enable          (cfg_interrupt_msi_enable           )       
    ,.cfg_interrupt_msi_mmenable        (cfg_interrupt_msi_mmenable         )// not support at this time, user need read pcie register self
    ,.cfg_interrupt_msi_mask_update     (cfg_interrupt_msi_mask_update      )// not support 
    ,.cfg_interrupt_msi_data            (cfg_interrupt_msi_data             )                   
    ,.cfg_interrupt_msi_select          (cfg_interrupt_msi_select           )       
    ,.cfg_interrupt_msi_int             (cfg_interrupt_msi_int              )       
    ,.cfg_interrupt_msi_pending_status  (cfg_interrupt_msi_pending_status   )       
    ,.cfg_interrupt_msi_sent            (cfg_interrupt_msi_sent             )                       
    ,.cfg_interrupt_msi_fail            (cfg_interrupt_msi_fail             )          
    ,.cfg_interrupt_msi_attr            (cfg_interrupt_msi_attr             )          
    ,.cfg_interrupt_msi_tph_present     (cfg_interrupt_msi_tph_present      )          
    ,.cfg_interrupt_msi_tph_type        (cfg_interrupt_msi_tph_type         )          
    ,.cfg_interrupt_msi_tph_st_tag      (cfg_interrupt_msi_tph_st_tag       )          
    ,.cfg_interrupt_msi_function_number (cfg_interrupt_msi_function_number  )          
    ,.cfg_interrupt_msi_pending_status_data_enable  (cfg_interrupt_msi_pending_status_data_enable  )
    ,.cfg_interrupt_msi_pending_status_function_num (cfg_interrupt_msi_pending_status_function_num )

    ,.cfg_interrupt_msix_enable         (cfg_interrupt_msix_enable         ) 
    ,.cfg_interrupt_msix_mask           (cfg_interrupt_msix_mask           ) 
    ,.cfg_interrupt_msix_vf_enable      (cfg_interrupt_msix_vf_enable      ) 
    ,.cfg_interrupt_msix_vf_mask        (cfg_interrupt_msix_vf_mask        ) 
    ,.cfg_interrupt_msix_address        (cfg_interrupt_msix_address        ) 
    ,.cfg_interrupt_msix_data           (cfg_interrupt_msix_data           ) 
    ,.cfg_interrupt_msix_int            (cfg_interrupt_msix_int            ) 
    ,.cfg_interrupt_msix_sent           (cfg_interrupt_msix_sent           ) 

    ,.m_axis_rq_tvalid                  (s_axis_msix_rq_tvalid             )
    ,.m_axis_rq_tready                  (s_axis_msix_rq_tready             )
    ,.m_axis_rq_tdata                   (s_axis_msix_rq_tdata              )
    ,.m_axis_rq_tkeep                   (s_axis_msix_rq_tkeep              )
    ,.m_axis_rq_tlast                   (s_axis_msix_rq_tlast              )
    ,.m_axis_rq_tuser                   (s_axis_msix_rq_tuser              )  
    //---only for debug---------------------------------------//
    ,.msix_sent_i                       (msix_sent                         )
    ,.ven2msi_debug                     (ven2msi_debug                     )
);

// --------------------------------------------------------------------
// PCIE EP core instance
// --------------------------------------------------------------------
generate begin 
if(DATA_WIDTH == 128) begin : PH1A_PCIE_CORE_BLK
al_pcie_ip #(
   .SIM_MODE                           (SIM_MODE                          )
) u_al_pcie_ip
   (
   .refclk_p                           (refclk_p                          )
   ,.refclk_n                          (refclk_n                          )
   ,.txp                               (txp                               )
   ,.txn                               (txn                               )
   ,.rxp                               (rxp                               )
   ,.rxn                               (rxn                               )       
        
   ,.client0_tlp_data                  (client0_tlp_data                  )
   ,.client0_tlp_addr                  (client0_tlp_addr                  )
   ,.client0_remote_req_id             (client0_remote_req_id             )
   ,.client0_tlp_byte_en               (client0_tlp_byte_en               )
   ,.client0_cpl_byte_cnt              (client0_cpl_byte_cnt              )
   ,.client0_addr_align_en             (client0_addr_align_en             )
   ,.client0_tlp_tc                    (client0_tlp_tc                    )
   ,.client0_tlp_attr                  (client0_tlp_attr                  )
   ,.client0_cpl_status                (client0_cpl_status                )
   ,.client0_cpl_bcm                   (client0_cpl_bcm                   )
   ,.client0_tlp_dv                    (client0_tlp_dv                    )
   ,.client0_tlp_eot                   (client0_tlp_eot                   )
   ,.client0_tlp_bad_eot               (client0_tlp_bad_eot               )
   ,.client0_tlp_hv                    (client0_tlp_hv                    )
   ,.client0_tlp_type                  (client0_tlp_type                  )
   ,.client0_tlp_fmt                   (client0_tlp_fmt                   )
   ,.client0_tlp_td                    (client0_tlp_td                    )
   ,.client0_tlp_byte_len              (client0_tlp_byte_len              )
   ,.client0_tlp_tid                   (client0_tlp_tid                   )
   ,.client0_tlp_ep                    (client0_tlp_ep                    )
   ,.client0_tlp_func_num              (client0_tlp_func_num              )
   ,.client0_tlp_vfunc_num             (client0_tlp_vfunc_num             )
   ,.client0_tlp_ats                   (client0_tlp_ats                   )
   ,.client0_tlp_st                    (client0_tlp_st                    )
   ,.client0_tlp_vfunc_active          (client0_tlp_vfunc_active          )
   ,.client0_tlp_nw                    (client0_tlp_nw                    )
   ,.client0_tlp_th                    (client0_tlp_th                    )
   ,.client0_tlp_ph                    (client0_tlp_ph                    )
   ,.client0_tlp_atu_bypass            (client0_tlp_atu_bypass            )
   ,.client0_cpl_lookup_id             (client0_cpl_lookup_id             )
   ,.xadm_client0_halt                 (xadm_client0_halt                 )

   ,.client1_tlp_data                  (client1_tlp_data                  )
   ,.client1_tlp_addr                  (client1_tlp_addr                  )
   ,.client1_remote_req_id             (client1_remote_req_id             )
   ,.client1_tlp_byte_en               (client1_tlp_byte_en               )
   ,.client1_cpl_byte_cnt              (client1_cpl_byte_cnt              )
   ,.client1_addr_align_en             (client1_addr_align_en             )
   ,.client1_tlp_tc                    (client1_tlp_tc                    )
   ,.client1_tlp_attr                  (client1_tlp_attr                  )
   ,.client1_cpl_status                (client1_cpl_status                )
   ,.client1_cpl_bcm                   (client1_cpl_bcm                   )
   ,.client1_tlp_dv                    (client1_tlp_dv                    )
   ,.client1_tlp_eot                   (client1_tlp_eot                   )
   ,.client1_tlp_bad_eot               (client1_tlp_bad_eot               )
   ,.client1_tlp_hv                    (client1_tlp_hv                    )
   ,.client1_tlp_type                  (client1_tlp_type                  )
   ,.client1_tlp_fmt                   (client1_tlp_fmt                   )
   ,.client1_tlp_td                    (client1_tlp_td                    )
   ,.client1_tlp_byte_len              (client1_tlp_byte_len              )
   ,.client1_tlp_tid                   (client1_tlp_tid                   )
   ,.client1_tlp_ep                    (client1_tlp_ep                    )
   ,.client1_tlp_func_num              (client1_tlp_func_num              )
   ,.client1_tlp_vfunc_num             (client1_tlp_vfunc_num             )
   ,.client1_tlp_ats                   (client1_tlp_ats                   )
   ,.client1_tlp_st                    (client1_tlp_st                    )
   ,.client1_tlp_vfunc_active          (client1_tlp_vfunc_active          )
   ,.client1_tlp_nw                    (client1_tlp_nw                    )
   ,.client1_tlp_th                    (client1_tlp_th                    )
   ,.client1_tlp_ph                    (client1_tlp_ph                    )
   ,.client1_tlp_atu_bypass            (client1_tlp_atu_bypass            )
   ,.client1_cpl_lookup_id             (client1_cpl_lookup_id             )
   ,.xadm_client1_halt                 (xadm_client1_halt                 )

   ,.ven_msi_req                       (ven_msi_req                        )
   ,.ven_msi_func_num                  (ven_msi_func_num                   )
   ,.cfg_msi_pending                   (cfg_msi_pending                    )
   ,.ven_msi_vfunc_num                 (ven_msi_vfunc_num                  )
   ,.ven_msi_vfunc_active              (ven_msi_vfunc_active               )
   ,.ven_msi_tc                        (ven_msi_tc                         )
   ,.ven_msi_vector                    (ven_msi_vector                     )
   ,.cfg_msi_en                        (cfg_msi_en                         )
   ,.cfg_msi_mask                      (cfg_msi_mask                       )
   ,.ven_msi_grant                     (ven_msi_grant                      )

   ,.drp_dbi_din                       (ext_drp_dbi_din                    )
   ,.drp_dbi_wr                        (ext_drp_dbi_wr                     )
   ,.drp_dbi_addr                      (ext_drp_dbi_addr                   )
   ,.drp_dbi_cs                        (ext_drp_dbi_cs                     )
   ,.drp_dbi_cs2_exp                   (ext_drp_dbi_cs2_exp                )
   ,.drp_dbi_vfunc_num                 (ext_drp_dbi_vfunc_num              )
   ,.drp_dbi_vfunc_active              (ext_drp_dbi_vfunc_active           )
   ,.drp_dbi_bar_num                   (ext_drp_dbi_bar_num                )   
   ,.drp_dbi_rom_access                (ext_drp_dbi_rom_access             )   
   ,.drp_dbi_io_access                 (ext_drp_dbi_io_access              )   
   ,.drp_dbi_func_num                  (ext_drp_dbi_func_num               )
   ,.drp_app_dbi_ro_wr_disable         (ext_drp_app_dbi_ro_wr_disable      )
   ,.drp_lbc_dbi_dout                  (ext_drp_lbc_dbi_dout               )
   ,.drp_lbc_dbi_ack                   (ext_drp_lbc_dbi_ack                )

   ,.radm_bypass_data                  (radm_bypass_data               )
   ,.radm_bypass_dwen                  (radm_bypass_dwen               )
   ,.radm_bypass_dv                    (radm_bypass_dv                 )
   ,.radm_bypass_hv                    (radm_bypass_hv                 )
   ,.radm_bypass_eot                   (radm_bypass_eot                )
   ,.radm_bypass_dllp_abort            (radm_bypass_dllp_abort         )
   ,.radm_bypass_tlp_abort             (radm_bypass_tlp_abort          )
   ,.radm_bypass_ecrc_err              (radm_bypass_ecrc_err           )
   ,.radm_bypass_addr                  (radm_bypass_addr               )
   ,.radm_bypass_fmt                   (radm_bypass_fmt                )
   ,.radm_bypass_tc                    (radm_bypass_tc                 )
   ,.radm_bypass_attr                  (radm_bypass_attr               )
   ,.radm_bypass_reqid                 (radm_bypass_reqid              )
   ,.radm_bypass_type                  (radm_bypass_type               )
   ,.radm_bypass_tag                   (radm_bypass_tag                )
   ,.radm_bypass_func_num              (radm_bypass_func_num           )
   ,.radm_bypass_vfunc_num             (radm_bypass_vfunc_num          )
   ,.radm_bypass_vfunc_active          (radm_bypass_vfunc_active       )
   ,.radm_bypass_td                    (radm_bypass_td                 )
   ,.radm_bypass_poisoned              (radm_bypass_poisoned           )
   ,.radm_bypass_dw_len                (radm_bypass_dw_len             )
   ,.radm_bypass_rom_in_range          (radm_bypass_rom_in_range       )
   ,.radm_bypass_first_be              (radm_bypass_first_be           )
   ,.radm_bypass_last_be               (radm_bypass_last_be            )
   ,.radm_bypass_io_req_in_range       (radm_bypass_io_req_in_range    )
   ,.radm_bypass_in_membar_range       (radm_bypass_in_membar_range    )
   ,.radm_bypass_cpl_last              (radm_bypass_cpl_last           )
   ,.radm_bypass_cpl_status            (radm_bypass_cpl_status         )
   ,.radm_bypass_st                    (radm_bypass_st                 )
   ,.radm_bypass_cmpltr_id             (radm_bypass_cmpltr_id          )
   ,.radm_bypass_byte_cnt              (radm_bypass_byte_cnt           )
   ,.radm_bypass_ats                   (radm_bypass_ats                )
   ,.radm_bypass_th                    (radm_bypass_th                 )
   ,.radm_bypass_ph                    (radm_bypass_ph                 )
   ,.radm_bypass_bcm                   (radm_bypass_bcm                )

   ,.radm_trgt1_dv                     (radm_trgt1_dv                  )
   ,.radm_trgt1_hv                     (radm_trgt1_hv                  )
   ,.radm_trgt1_eot                    (radm_trgt1_eot                 )
   ,.radm_trgt1_tlp_abort              (radm_trgt1_tlp_abort           )
   ,.radm_trgt1_dllp_abort             (radm_trgt1_dllp_abort          ) 
   ,.radm_trgt1_ecrc_err               (radm_trgt1_ecrc_err            )
   ,.radm_trgt1_dwen                   (radm_trgt1_dwen                )
   ,.radm_trgt1_fmt                    (radm_trgt1_fmt                 )
   ,.radm_trgt1_attr                   (radm_trgt1_attr                )
   ,.radm_trgt1_func_num               (radm_trgt1_func_num            )
   ,.radm_trgt1_type                   (radm_trgt1_type                )
   ,.radm_trgt1_tc                     (radm_trgt1_tc                  )
   ,.radm_trgt1_reqid                  (radm_trgt1_reqid               )
   ,.radm_trgt1_data                   (radm_trgt1_data                )
   ,.radm_trgt1_first_be               (radm_trgt1_first_be            )
   ,.radm_trgt1_last_be                (radm_trgt1_last_be             )
   ,.radm_trgt1_addr                   (radm_trgt1_addr                )
   ,.radm_trgt1_vfunc_num              (radm_trgt1_vfunc_num           )
   ,.radm_trgt1_vfunc_active           (radm_trgt1_vfunc_active        )
   ,.radm_trgt1_td                     (radm_trgt1_td                  )
   ,.radm_trgt1_poisoned               (radm_trgt1_poisoned            )
   ,.radm_trgt1_hdr_uppr_bytes_valid   (radm_trgt1_hdr_uppr_bytes_valid)
   ,.radm_trgt1_rom_in_range           (radm_trgt1_rom_in_range        )
   ,.radm_trgt1_io_req_in_range        (radm_trgt1_io_req_in_range     )
   ,.radm_trgt1_hdr_uppr_bytes         (radm_trgt1_hdr_uppr_bytes      )
   ,.radm_trgt1_in_membar_range        (radm_trgt1_in_membar_range     )
   ,.radm_trgt1_cpl_status             (radm_trgt1_cpl_status          )
   ,.radm_trgt1_ats                    (radm_trgt1_ats                 )
   ,.radm_trgt1_tag                    (radm_trgt1_tag                 )
   ,.radm_trgt1_dw_len                 (radm_trgt1_dw_len              )
   ,.radm_trgt1_nw                     (radm_trgt1_nw                  )
   ,.radm_trgt1_th                     (radm_trgt1_th                  )
   ,.radm_trgt1_ph                     (radm_trgt1_ph                  )
   ,.radm_trgt1_st                     (radm_trgt1_st                  )
   ,.radm_trgt1_byte_cnt               (radm_trgt1_byte_cnt            )
   ,.radm_trgt1_bcm                    (radm_trgt1_bcm                 )
   ,.radm_trgt1_vc                     (radm_trgt1_vc                  )
   ,.radm_trgt1_cmpltr_id              (radm_trgt1_cmpltr_id           )
   ,.radm_trgt1_cpl_last               (radm_trgt1_cpl_last            )
   ,.radm_grant_tlp_type               (radm_grant_tlp_type            )
   ,.radm_trgt1_atu_sloc_match         (radm_trgt1_atu_sloc_match      )
   ,.radm_trgt1_atu_cbuf_err           (radm_trgt1_atu_cbuf_err        )
   ,.trgt_lookup_id                    (trgt_lookup_id                 )
   ,.trgt_lookup_empty                 (trgt_lookup_empty              )
   ,.trgt1_radm_halt                   (trgt1_radm_halt                )
   ,.trgt1_radm_pkt_halt               (trgt1_radm_pkt_halt            )
    
   ,.sys_atten_button_pressed          (2'b0                              )
   ,.sys_pre_det_state                 (2'b0                              )
   ,.sys_mrl_sensor_state              (2'b0                              )
   ,.sys_pwr_fault_det                 (2'b0                              )
   ,.sys_mrl_sensor_chged              (2'b0                              )
   ,.sys_pre_det_chged                 (2'b0                              )
   ,.sys_cmd_cpled_int                 (2'b0                              )
   ,.sys_eml_interlock_engaged         (2'b0                              )
   ,.rx_lane_flip_en                   (1'b0                              )
   ,.tx_lane_flip_en                   (1'b0                              )
   ,.app_req_retry_en                  (1'b0                              )
   ,.app_sris_mode                     (1'b0                              )
   ,.app_vf_req_retry_en               (4'b0                              )
   ,.app_pf_req_retry_en               (2'b0                              )
   ,.app_unlock_msg                    (1'b0                              )
   ,.app_hdr_log                       (128'b0                            )
   ,.app_err_bus                       (13'b0                             )
   ,.app_err_advisory                  (1'b0                              )
   ,.app_err_func_num                  (1'b0                              )
   ,.app_err_vfunc_active              (1'b0                              )
   ,.app_hdr_valid                     (1'b0                              )
   ,.app_err_vfunc_num                 (2'b0                              )
     
//    ,.ext_lbc_din                       (0)
//    ,.ext_lbc_ack                       (0)
   ,.app_perst_n                       (1'b1                           ) 
   ,.app_power_up_rst_n                (app_perst_n                    ) 
   ,.app_button_rst_n                  (1'b1                       ) 

   ,.phy_cr_para_clk                   (app_auxclk                     )
   ,.user_clk                          (user_clk                       )
   ,.user_link                         (user_link_up                   )
    
   ,.app_auxclk                        (app_auxclk                     )

   ,.core_rst_n                        (core_rst_n                     )
   ,.rdlh_link_up                      (rdlh_link_up                   )
   ,.smlh_ltssm_state                  (smlh_ltssm_state               )

   );
end 
else if(DATA_WIDTH == 64) begin : PH1A100_PCIE_CORE_BLK
wire    [31:0]  drp_dbi_addr;       
wire    [2:0]   drp_dbi_bar_num;    
wire            drp_dbi_cs;     
wire            drp_dbi_cs2_exp;    
wire    [31:0]  drp_dbi_din;        
wire            drp_dbi_func_num;   
wire            drp_dbi_io_access;  
wire            drp_dbi_rom_access; 
wire            drp_dbi_vfunc_active;   
wire    [1:0]   drp_dbi_vfunc_num;  
wire    [3:0]   drp_dbi_wr;     
wire            drp_app_dbi_ro_wr_disable;
wire            drp_lbc_dbi_ack;        
wire    [31:0]  drp_lbc_dbi_dout;

wire            app_app_ltssm_enable;

PH1_PHY_GCLK app_auxclk_bufg(.clkin({app_auxclk,1'b1}),.clkout(app_auxclk_g),
            .cen({1'b0,1'b1}),.seln({1'b0,1'b1}),.drct({1'b0,1'b1}));

`ifdef DEBUG_MODE 
    assign  user_clk  = core_clk;
    assign  user_rstn = core_rst_n;
`else 
    sys_ctrl u_sys_ctrl(
        .core_rst_n                     (core_rst_n                       ),//rdlh_link_up
        .core_clk                       (core_clk                         ),    
        .aux_clk                        (app_auxclk_g                     ),
                                    
        .core_clk_pll                   (user_clk                         ),
        .core_rst_n_pll                 (user_rstn                        )
    );  
`endif  
    
dbi_init_mux u_dbi_init_mux(    
    .core_clk                           (core_clk                          ),
    .pcie_rst_n                         (app_perst_n                ),//
    .core_rst_n_pll                     (core_rst_n                        ),
    //.dbi_init_vaule                     (1'b0                              ),
    .dbi_init_disable                   ( 1'b0                             ),
    // external dbi bus     
    .ext_app_app_ltssm_enable           (1'b1          ),
    .ext_drp_dbi_din                    (ext_drp_dbi_din                   ),
    .ext_drp_dbi_wr                     (ext_drp_dbi_wr                    ),
    .ext_drp_dbi_addr                   (ext_drp_dbi_addr                  ),
    .ext_drp_dbi_cs                     (ext_drp_dbi_cs                    ),
    .ext_drp_dbi_cs2_exp                (ext_drp_dbi_cs2_exp               ),
    .ext_drp_dbi_vfunc_num              (ext_drp_dbi_vfunc_num             ),
    .ext_drp_dbi_vfunc_active           (ext_drp_dbi_vfunc_active          ),
    .ext_drp_dbi_bar_num                (ext_drp_dbi_bar_num               ),
    .ext_drp_dbi_rom_access             (ext_drp_dbi_rom_access            ),
    .ext_drp_dbi_io_access              (ext_drp_dbi_io_access             ),
    .ext_drp_dbi_func_num               (ext_drp_dbi_func_num              ),
    .ext_drp_app_dbi_ro_wr_disable      (ext_drp_app_dbi_ro_wr_disable     ),  
    .ext_drp_lbc_dbi_ack                (ext_drp_lbc_dbi_ack               ),       
    .ext_drp_lbc_dbi_dout               (ext_drp_lbc_dbi_dout              ),  
         
    // master bdi bus 
    .app_app_ltssm_enable               (app_app_ltssm_enable              ),
    .drp_dbi_din                        (drp_dbi_din                       ),
    .drp_dbi_wr                         (drp_dbi_wr                        ),
    .drp_dbi_addr                       (drp_dbi_addr                      ),
    .drp_dbi_cs                         (drp_dbi_cs                        ),
    .drp_dbi_cs2_exp                    (drp_dbi_cs2_exp                   ),
    .drp_dbi_vfunc_num                  (drp_dbi_vfunc_num                 ),
    .drp_dbi_vfunc_active               (drp_dbi_vfunc_active              ),
    .drp_dbi_bar_num                    (drp_dbi_bar_num                   ),
    .drp_dbi_rom_access                 (drp_dbi_rom_access                ),
    .drp_dbi_io_access                  (drp_dbi_io_access                 ),
    .drp_dbi_func_num                   (drp_dbi_func_num                  ),
    .drp_app_dbi_ro_wr_disable          (drp_app_dbi_ro_wr_disable         ),
    .drp_lbc_dbi_ack                    (drp_lbc_dbi_ack                   ),       
    .drp_lbc_dbi_dout                   (drp_lbc_dbi_dout                  )       
);  
    
al_pcie_ip_ph1a100 u_al_pcie_ip 
    (   
    .refclk_p                           (refclk_p                          )
    ,.refclk_n                          (refclk_n                          )
    ,.txp                               (txp                               )
    ,.txn                               (txn                               )
    ,.rxp                               (rxp                               )
    ,.rxn                               (rxn                               )       
    
    ,.client0_tlp_data                  (client0_tlp_data                  )
    ,.client0_tlp_addr                  (client0_tlp_addr                  )
    ,.client0_remote_req_id             (client0_remote_req_id             )
    ,.client0_tlp_byte_en               (client0_tlp_byte_en               )
    ,.client0_cpl_byte_cnt              (client0_cpl_byte_cnt              )
    ,.client0_addr_align_en             (client0_addr_align_en             )
    ,.client0_tlp_tc                    (client0_tlp_tc                    )
    ,.client0_tlp_attr                  (client0_tlp_attr                  )
    ,.client0_cpl_status                (client0_cpl_status                )
    ,.client0_cpl_bcm                   (client0_cpl_bcm                   )
    ,.client0_tlp_dv                    (client0_tlp_dv                    )
    ,.client0_tlp_eot                   (client0_tlp_eot                   )
    ,.client0_tlp_bad_eot               (client0_tlp_bad_eot               )
    ,.client0_tlp_hv                    (client0_tlp_hv                    )
    ,.client0_tlp_type                  (client0_tlp_type                  )
    ,.client0_tlp_fmt                   (client0_tlp_fmt                   )
    ,.client0_tlp_td                    (client0_tlp_td                    )
    ,.client0_tlp_byte_len              (client0_tlp_byte_len              )
    ,.client0_tlp_tid                   (client0_tlp_tid                   )
    ,.client0_tlp_ep                    (client0_tlp_ep                    )
    ,.client0_tlp_func_num              (client0_tlp_func_num              )
    ,.client0_tlp_vfunc_num             (client0_tlp_vfunc_num             )
    ,.client0_tlp_ats                   (client0_tlp_ats                   )
    ,.client0_tlp_st                    (client0_tlp_st                    )
    ,.client0_tlp_vfunc_active          (client0_tlp_vfunc_active          )
    ,.client0_tlp_nw                    (client0_tlp_nw                    )
    ,.client0_tlp_th                    (client0_tlp_th                    )
    ,.client0_tlp_ph                    (client0_tlp_ph                    )
    ,.client0_tlp_atu_bypass            (client0_tlp_atu_bypass            )
    ,.client0_cpl_lookup_id             (client0_cpl_lookup_id             )
    ,.xadm_client0_halt                 (xadm_client0_halt                 )

    ,.client1_tlp_data                  (client1_tlp_data                  )
    ,.client1_tlp_addr                  (client1_tlp_addr                  )
    ,.client1_remote_req_id             (client1_remote_req_id             )
    ,.client1_tlp_byte_en               (client1_tlp_byte_en               )
    ,.client1_cpl_byte_cnt              (client1_cpl_byte_cnt              )
    ,.client1_addr_align_en             (client1_addr_align_en             )
    ,.client1_tlp_tc                    (client1_tlp_tc                    )
    ,.client1_tlp_attr                  (client1_tlp_attr                  )
    ,.client1_cpl_status                (client1_cpl_status                )
    ,.client1_cpl_bcm                   (client1_cpl_bcm                   )
    ,.client1_tlp_dv                    (client1_tlp_dv                    )
    ,.client1_tlp_eot                   (client1_tlp_eot                   )
    ,.client1_tlp_bad_eot               (client1_tlp_bad_eot               )
    ,.client1_tlp_hv                    (client1_tlp_hv                    )
    ,.client1_tlp_type                  (client1_tlp_type                  )
    ,.client1_tlp_fmt                   (client1_tlp_fmt                   )
    ,.client1_tlp_td                    (client1_tlp_td                    )
    ,.client1_tlp_byte_len              (client1_tlp_byte_len              )
    ,.client1_tlp_tid                   (client1_tlp_tid                   )
    ,.client1_tlp_ep                    (client1_tlp_ep                    )
    ,.client1_tlp_func_num              (client1_tlp_func_num              )
    ,.client1_tlp_vfunc_num             (client1_tlp_vfunc_num             )
    ,.client1_tlp_ats                   (client1_tlp_ats                   )
    ,.client1_tlp_st                    (client1_tlp_st                    )
    ,.client1_tlp_vfunc_active          (client1_tlp_vfunc_active          )
    ,.client1_tlp_nw                    (client1_tlp_nw                    )
    ,.client1_tlp_th                    (client1_tlp_th                    )
    ,.client1_tlp_ph                    (client1_tlp_ph                    )
    ,.client1_tlp_atu_bypass            (client1_tlp_atu_bypass            )
    ,.client1_cpl_lookup_id             (client1_cpl_lookup_id             )
    ,.xadm_client1_halt                 (xadm_client1_halt                 )

    ,.ven_msi_req                       (ven_msi_req                        )
    ,.ven_msi_func_num                  (ven_msi_func_num                   )
    ,.cfg_msi_pending                   (cfg_msi_pending                    )
    ,.ven_msi_vfunc_num                 (ven_msi_vfunc_num                  )
    ,.ven_msi_vfunc_active              (ven_msi_vfunc_active               )
    ,.ven_msi_tc                        (ven_msi_tc                         )
    ,.ven_msi_vector                    (ven_msi_vector                     )
    ,.cfg_msi_en                        (cfg_msi_en                         )
    ,.cfg_msi_mask                      (cfg_msi_mask                       )
    ,.ven_msi_grant                     (ven_msi_grant                      )

    // ,.drp_dbi_din                   (ext_drp_dbi_din                    )
    // ,.drp_dbi_wr                    (ext_drp_dbi_wr                     )
    // ,.drp_dbi_addr                  (ext_drp_dbi_addr                   )
    // ,.drp_dbi_cs                    (ext_drp_dbi_cs                     )
    // ,.drp_dbi_cs2_exp               (ext_drp_dbi_cs2_exp                )
    // ,.drp_dbi_vfunc_num             (ext_drp_dbi_vfunc_num              )
    // ,.drp_dbi_vfunc_active          (ext_drp_dbi_vfunc_active           )
    // ,.drp_dbi_bar_num               (ext_drp_dbi_bar_num                )   
    // ,.drp_dbi_rom_access            (ext_drp_dbi_rom_access             )   
    // ,.drp_dbi_io_access             (ext_drp_dbi_io_access              )   
    // ,.drp_dbi_func_num              (ext_drp_dbi_func_num               )
    // ,.drp_app_dbi_ro_wr_disable     (ext_drp_app_dbi_ro_wr_disable      )
    // ,.drp_lbc_dbi_dout              (ext_drp_lbc_dbi_dout               )
    // ,.drp_lbc_dbi_ack               (ext_drp_lbc_dbi_ack                )
    `ifdef DEBUG_MODE

    `else 
    ,.drp_dbi_din                       (drp_dbi_din                    )
    ,.drp_dbi_wr                        (drp_dbi_wr                     )
    ,.drp_dbi_addr                      (drp_dbi_addr                   )
    ,.drp_dbi_cs                        (drp_dbi_cs                     )
    ,.drp_dbi_cs2_exp                   (drp_dbi_cs2_exp                )
    ,.drp_dbi_vfunc_num                 (drp_dbi_vfunc_num              )
    ,.drp_dbi_vfunc_active              (drp_dbi_vfunc_active           )
    ,.drp_dbi_bar_num                   (drp_dbi_bar_num                )
    ,.drp_dbi_rom_access                (drp_dbi_rom_access             )
    ,.drp_dbi_io_access                 (drp_dbi_io_access              )
    ,.drp_dbi_func_num                  (drp_dbi_func_num               )
    ,.drp_app_dbi_ro_wr_disable         (drp_app_dbi_ro_wr_disable      )
    ,.drp_lbc_dbi_dout                  (drp_lbc_dbi_dout               )
    ,.drp_lbc_dbi_ack                   (drp_lbc_dbi_ack                )   
    `endif 

    ,.radm_bypass_data                  (radm_bypass_data               )
    ,.radm_bypass_dwen                  (radm_bypass_dwen               )
    ,.radm_bypass_dv                    (radm_bypass_dv                 )
    ,.radm_bypass_hv                    (radm_bypass_hv                 )
    ,.radm_bypass_eot                   (radm_bypass_eot                )
    ,.radm_bypass_dllp_abort            (radm_bypass_dllp_abort         )
    ,.radm_bypass_tlp_abort             (radm_bypass_tlp_abort          )
    ,.radm_bypass_ecrc_err              (radm_bypass_ecrc_err           )
    ,.radm_bypass_addr                  (radm_bypass_addr               )
    ,.radm_bypass_fmt                   (radm_bypass_fmt                )
    ,.radm_bypass_tc                    (radm_bypass_tc                 )
    ,.radm_bypass_attr                  (radm_bypass_attr               )
    ,.radm_bypass_reqid                 (radm_bypass_reqid              )
    ,.radm_bypass_type                  (radm_bypass_type               )
    ,.radm_bypass_tag                   (radm_bypass_tag                )
    ,.radm_bypass_func_num              (radm_bypass_func_num           )
    ,.radm_bypass_vfunc_num             (radm_bypass_vfunc_num          )
    ,.radm_bypass_vfunc_active          (radm_bypass_vfunc_active       )
    ,.radm_bypass_td                    (radm_bypass_td                 )
    ,.radm_bypass_poisoned              (radm_bypass_poisoned           )
    ,.radm_bypass_dw_len                (radm_bypass_dw_len             )
    ,.radm_bypass_rom_in_range          (radm_bypass_rom_in_range       )
    ,.radm_bypass_first_be              (radm_bypass_first_be           )
    ,.radm_bypass_last_be               (radm_bypass_last_be            )
    ,.radm_bypass_io_req_in_range       (radm_bypass_io_req_in_range    )
    ,.radm_bypass_in_membar_range       (radm_bypass_in_membar_range    )
    ,.radm_bypass_cpl_last              (radm_bypass_cpl_last           )
    ,.radm_bypass_cpl_status            (radm_bypass_cpl_status         )
    ,.radm_bypass_st                    (radm_bypass_st                 )
    ,.radm_bypass_cmpltr_id             (radm_bypass_cmpltr_id          )
    ,.radm_bypass_byte_cnt              (radm_bypass_byte_cnt           )
    ,.radm_bypass_ats                   (radm_bypass_ats                )
    ,.radm_bypass_th                    (radm_bypass_th                 )
    ,.radm_bypass_ph                    (radm_bypass_ph                 )
    ,.radm_bypass_bcm                   (radm_bypass_bcm                )

    ,.radm_trgt1_dv                     (radm_trgt1_dv                  )
    ,.radm_trgt1_hv                     (radm_trgt1_hv                  )
    ,.radm_trgt1_eot                    (radm_trgt1_eot                 )
    ,.radm_trgt1_tlp_abort              (radm_trgt1_tlp_abort           )
    ,.radm_trgt1_dllp_abort             (radm_trgt1_dllp_abort          ) 
    ,.radm_trgt1_ecrc_err               (radm_trgt1_ecrc_err            )
    ,.radm_trgt1_dwen                   (radm_trgt1_dwen                )
    ,.radm_trgt1_fmt                    (radm_trgt1_fmt                 )
    ,.radm_trgt1_attr                   (radm_trgt1_attr                )
    ,.radm_trgt1_func_num               (radm_trgt1_func_num            )
    ,.radm_trgt1_type                   (radm_trgt1_type                )
    ,.radm_trgt1_tc                     (radm_trgt1_tc                  )
    ,.radm_trgt1_reqid                  (radm_trgt1_reqid               )
    ,.radm_trgt1_data                   (radm_trgt1_data                )
    ,.radm_trgt1_first_be               (radm_trgt1_first_be            )
    ,.radm_trgt1_last_be                (radm_trgt1_last_be             )
    ,.radm_trgt1_addr                   (radm_trgt1_addr                )
    ,.radm_trgt1_vfunc_num              (radm_trgt1_vfunc_num           )
    ,.radm_trgt1_vfunc_active           (radm_trgt1_vfunc_active        )
    ,.radm_trgt1_td                     (radm_trgt1_td                  )
    ,.radm_trgt1_poisoned               (radm_trgt1_poisoned            )
    ,.radm_trgt1_hdr_uppr_bytes_valid   (radm_trgt1_hdr_uppr_bytes_valid)
    ,.radm_trgt1_rom_in_range           (radm_trgt1_rom_in_range        )
    ,.radm_trgt1_io_req_in_range        (radm_trgt1_io_req_in_range     )
    ,.radm_trgt1_hdr_uppr_bytes         (radm_trgt1_hdr_uppr_bytes      )
    ,.radm_trgt1_in_membar_range        (radm_trgt1_in_membar_range     )
    ,.radm_trgt1_cpl_status             (radm_trgt1_cpl_status          )
    ,.radm_trgt1_ats                    (radm_trgt1_ats                 )
    ,.radm_trgt1_tag                    (radm_trgt1_tag                 )
    ,.radm_trgt1_dw_len                 (radm_trgt1_dw_len              )
    ,.radm_trgt1_nw                     (radm_trgt1_nw                  )
    ,.radm_trgt1_th                     (radm_trgt1_th                  )
    ,.radm_trgt1_ph                     (radm_trgt1_ph                  )
    ,.radm_trgt1_st                     (radm_trgt1_st                  )
    ,.radm_trgt1_byte_cnt               (radm_trgt1_byte_cnt            )
    ,.radm_trgt1_bcm                    (radm_trgt1_bcm                 )
    ,.radm_trgt1_vc                     (radm_trgt1_vc                  )
    ,.radm_trgt1_cmpltr_id              (radm_trgt1_cmpltr_id           )
    ,.radm_trgt1_cpl_last               (radm_trgt1_cpl_last            )
    ,.radm_grant_tlp_type               (radm_grant_tlp_type            )
    ,.radm_trgt1_atu_sloc_match         (radm_trgt1_atu_sloc_match      )
    ,.radm_trgt1_atu_cbuf_err           (radm_trgt1_atu_cbuf_err        )
    ,.trgt_lookup_id                    (trgt_lookup_id                 )
    ,.trgt_lookup_empty                 (trgt_lookup_empty              )
    ,.trgt1_radm_halt                   (trgt1_radm_halt                )
    ,.trgt1_radm_pkt_halt               (trgt1_radm_pkt_halt            )
    
    ,.sys_atten_button_pressed          (2'b0                              )
    ,.sys_pre_det_state                 (2'b0                              )
    ,.sys_mrl_sensor_state              (2'b0                              )
    ,.sys_pwr_fault_det                 (2'b0                              )
    ,.sys_mrl_sensor_chged              (2'b0                              )
    ,.sys_pre_det_chged                 (2'b0                              )
    ,.sys_cmd_cpled_int                 (2'b0                              )
    ,.sys_eml_interlock_engaged         (2'b0                              )
    ,.rx_lane_flip_en                   (1'b0                              )
    ,.tx_lane_flip_en                   (1'b0                              )
    ,.app_req_retry_en                  (1'b0                              )
    ,.app_sris_mode                     (1'b0                              )
    ,.app_vf_req_retry_en               (4'b0                              )
    ,.app_pf_req_retry_en               (2'b0                              )
    ,.app_unlock_msg                    (1'b0                              )
    ,.app_hdr_log                       (128'b0                            )
    ,.app_err_bus                       (13'b0                             )
    ,.app_err_advisory                  (1'b0                              )
    ,.app_err_func_num                  (1'b0                              )
    ,.app_err_vfunc_active              (1'b0                              )
    ,.app_hdr_valid                     (1'b0                              )
    ,.app_err_vfunc_num                 (2'b0                              )

    ,.prs_res_failure                    (2'b00) 
    ,.prs_uprgi                          (2'b00) 
    ,.prs_stopped                        (2'b00) 
 
    ,.app_drs_ready                      (1'b1)
    ,.app_vf_frs_ready                   (4'b1111)
    ,.app_pf_frs_ready                   (2'b11)

//    ,.ext_lbc_din                       (0)
//    ,.ext_lbc_ack                       (0)
    ,.app_perst_n                       (1'b1                              ) 
    ,.app_power_up_rst_n                (app_perst_n                       ) 
    ,.app_button_rst_n                  (1'b1                              ) 
`ifdef DEBUG_MODE
    ,.app_app_ltssm_enable              (1              )
`else 
    ,.app_app_ltssm_enable              (app_app_ltssm_enable              )
`endif
    ,.drp_cr_para_clk                   (app_auxclk_g                      )
//    ,.user_clk                          (user_clk                        )
//    ,.user_link                         (user_link_up                    )
    ,.app_auxclk                        (app_auxclk_g                      )
    ,.core_clk                          (core_clk                          )
    ,.core_rst_n                        (core_rst_n                        )
    ,.rdlh_link_up                      (rdlh_link_up                      )
    ,.smlh_ltssm_state                  (smlh_ltssm_state                  )

    );
     
    assign  user_link_up = rdlh_link_up;
    // PH1_LOGIC_BUF u_link_up_logic_buf(
    //   .o            ( user_link_up     ), //  1-Bit output. Buffer input port.             
    //   .i            ( rdlh_link_up     )  //  1-Bit input. Buffer output port.            
    // );
end 
end
endgenerate


endmodule
