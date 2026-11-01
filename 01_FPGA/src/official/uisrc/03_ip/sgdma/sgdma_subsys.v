/*===========================================*\
Filename        :sgdma_subsys.v
Project name    :sgdma_subsys_tst
Description     :      sgdma ip   pcie_phy
Called by       :sgdma_subsys_tst.v
Email           :bingsong.wang@anlogic.com
Modified        :v1.0          2021-03-19
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/
`timescale 1ns/1ps

module sgdma_subsys #(
    parameter SIM_MODE                              = 0
`ifdef DEBUG_MODE
    | 1
`endif
    ,
    parameter DEVICE_FAMILY                         = "PH2A" ,//PH1A/PH2A/PH1A100/DR1/PH1P   
    parameter USER_CLK_FREQ                         = (DEVICE_FAMILY == "PH2A") ? 250 : 125,
    parameter LINK_WIDTH                            = (DEVICE_FAMILY == "PH2A") ? 8 : (DEVICE_FAMILY == "PH1A100") ? 2 : 4,
    parameter DATA_WIDTH                            =  ( DEVICE_FAMILY == "PH1A100")? 64 :
                                                       ((DEVICE_FAMILY == "PH1A")   ? 128:
                                                       ((DEVICE_FAMILY == "PH1P")   ? 256: 512)),
    parameter DATA_BYTE                             = DATA_WIDTH/8,
    parameter DATA_DW                               = DATA_WIDTH/32,
    //DMA MODE
    parameter AXI4MM_BUS_EN                         = 0,
    parameter AXI4ST_BUS_EN                         = 0,
    parameter DMA_BYPA_EN                           = 0,
    //Set config interface
    parameter CFG_MGMT_EN                           = 0,
    parameter AXI4L_MBUS_EN                         = 1,
    parameter AXI4L_SBUS_EN                         = 1,
    parameter USR_IRQ_NUM                           = 1,
    //set interrupt type
    parameter LGCY_EN                               = 0,
    parameter MSI_EN                                = 1,
    parameter MSIX_EN                               = 0,
    //set channel number
    parameter H2C_CHNL_NUM                          = 1,
    parameter C2H_CHNL_NUM                          = 1,
    parameter H2C_DSC_BYP_MAP                       = 1,
    parameter C2H_DSC_BYP_MAP                       = 1,
    //SET TAG NUMBER
    parameter H2C_ID_NUM                            = 32,
    parameter C2H_ID_NUM                            = 16,

    parameter PH2_SRAM_HXT_FILE = SIM_MODE? "pcie_brg_pcie_core_hxt_sram_fastsim.hex" : "pcie_brg_pcie_core_hxt_sram.hex",
    parameter PH2_CSR_HXT_FILE  = SIM_MODE? "pcie_brg_pcie_core_hxt_csr_fastsim.hex" : "pcie_brg_pcie_core_hxt_csr.hex"
    ) (
    input   wire                                    app_auxclk      ,
    input   wire                                    tl_power_on_rstn, //not use
    input   wire                                    tl_clk_user,
    input   wire                                    pll_lock,
// `ifdef  DEV_PH2A 
//     input   wire                                    tl_clk_user,
//     input   wire                                    pll_lock,
// `endif 
// `ifdef  DEV_PH1P 
//     input   wire                                    tl_clk_user,
//     input   wire                                    pll_lock,
// `endif 
    input   wire    [0:0]                           ref_pad_clk_p ,
    input   wire    [0:0]                           ref_pad_clk_n ,
    output  wire    [LINK_WIDTH-1:0]                pcie_tx_p ,
    output  wire    [LINK_WIDTH-1:0]                pcie_tx_n ,
    input   wire    [LINK_WIDTH-1:0]                pcie_rx_p ,
    input   wire    [LINK_WIDTH-1:0]                pcie_rx_n ,

    output   wire   [7:0]                           c2h_sts_0,
    output   wire   [7:0]                           h2c_sts_0,
    output   wire   [7:0]                           c2h_sts_1,
    output   wire   [7:0]                           h2c_sts_1,
    output   wire   [7:0]                           c2h_sts_2,
    output   wire   [7:0]                           h2c_sts_2,
    output   wire   [7:0]                           c2h_sts_3,
    output   wire   [7:0]                           h2c_sts_3,
`ifdef AXI4ST_BUS_EN
    output  wire    [C2H_CHNL_NUM-1:0]              s0_axis_c2h_tready,
    input   wire    [DATA_WIDTH*C2H_CHNL_NUM-1:0]   s0_axis_c2h_tdata,
    input   wire    [DATA_BYTE*C2H_CHNL_NUM-1:0]    s0_axis_c2h_tkeep,
    input   wire    [DATA_BYTE*C2H_CHNL_NUM-1:0]    s0_axis_c2h_tuser,
    input   wire    [C2H_CHNL_NUM-1:0]              s0_axis_c2h_tlast,
    input   wire    [C2H_CHNL_NUM-1:0]              s0_axis_c2h_tvalid,

    input   wire    [H2C_CHNL_NUM-1:0]              m0_axis_h2c_tready,
    output  wire    [DATA_WIDTH*H2C_CHNL_NUM-1:0]   m0_axis_h2c_tdata,
    output  wire    [DATA_BYTE*H2C_CHNL_NUM-1:0]    m0_axis_h2c_tkeep,
    output  wire    [DATA_BYTE*H2C_CHNL_NUM-1:0]    m0_axis_h2c_tuser,
    output  wire    [H2C_CHNL_NUM-1:0]              m0_axis_h2c_tlast,
    output  wire    [H2C_CHNL_NUM-1:0]              m0_axis_h2c_tvalid,
`endif
`ifdef AXI4MM_BUS_EN
    //---Write Address Interface---
    input   wire                                    m_axi_awready,
    output  wire    [3:0]                           m_axi_awid,
    output  wire    [63:0]                          m_axi_awaddr,
    output  wire    [7:0]                           m_axi_awlen,
    output  wire    [2:0]                           m_axi_awsize,
    output  wire    [1:0]                           m_axi_awburst,
    output  wire    [2:0]                           m_axi_awprot,
    output  wire                                    m_axi_awvalid,
    output  wire                                    m_axi_awlock,
    output  wire    [3:0]                           m_axi_awcache,
    //---Write Interface---
    output  wire    [DATA_WIDTH-1:0]               m_axi_wdata,
    output  wire    [DATA_BYTE-1:0]                m_axi_wstrb,
    input   wire                                    m_axi_wready,
    output  wire                                    m_axi_wlast,
    output  wire                                    m_axi_wvalid,
    //---Write Response Interface---
    input   wire    [3:0]                           m_axi_bid,
    input   wire    [1:0]                           m_axi_bresp,
    input   wire                                    m_axi_bvalid,
    output  wire                                    m_axi_bready,
    //---Read Address Interface---
    input   wire                                    m_axi_arready,
    output  wire    [3:0]                           m_axi_arid,
    output  wire    [63:0]                          m_axi_araddr,
    output  wire    [7:0]                           m_axi_arlen,
    output  wire    [2:0]                           m_axi_arsize,
    output  wire    [1:0]                           m_axi_arburst,
    output  wire    [2:0]                           m_axi_arprot,
    output  wire                                    m_axi_arvalid,
    output  wire                                    m_axi_arlock,
    output  wire    [3:0]                           m_axi_arcache,
    //---Read Interface---ccf
    input   wire    [3:0]                           m_axi_rid,
    input   wire    [DATA_WIDTH-1:0]               m_axi_rdata,
    input   wire    [DATA_BYTE-1:0]                m_axi_ruser,
    input   wire    [1:0]                           m_axi_rresp,
    input   wire                                    m_axi_rlast,
    input   wire                                    m_axi_rvalid,
    output  wire                                    m_axi_rready,
`endif
`ifdef  DSC_BYPASS_C2H_CHL0_EN
    //Descriptor byapss interface
    output  wire                                    c2h_dsc_byp_ready_0_o,
    input   wire                                    c2h_dsc_byp_load_0_i,
    input   wire    [63:0]                          c2h_dsc_byp_src_addr_0_i,
    input   wire    [63:0]                          c2h_dsc_byp_dst_addr_0_i,
    input   wire    [27:0]                          c2h_dsc_byp_len_0_i,
    input   wire    [15:0]                          c2h_dsc_byp_ctl_0_i,
`endif
`ifdef  DSC_BYPASS_C2H_CHL1_EN
    output  wire                                    c2h_dsc_byp_ready_1_o,
    input   wire                                    c2h_dsc_byp_load_1_i,
    input   wire    [63:0]                          c2h_dsc_byp_src_addr_1_i,
    input   wire    [63:0]                          c2h_dsc_byp_dst_addr_1_i,
    input   wire    [27:0]                          c2h_dsc_byp_len_1_i,
    input   wire    [15:0]                          c2h_dsc_byp_ctl_1_i,
`endif
`ifdef  DSC_BYPASS_C2H_CHL2_EN
    output  wire                                    c2h_dsc_byp_ready_2_o,
    input   wire                                    c2h_dsc_byp_load_2_i,
    input   wire    [63:0]                          c2h_dsc_byp_src_addr_2_i,
    input   wire    [63:0]                          c2h_dsc_byp_dst_addr_2_i,
    input   wire    [27:0]                          c2h_dsc_byp_len_2_i,
    input   wire    [15:0]                          c2h_dsc_byp_ctl_2_i,
`endif
`ifdef  DSC_BYPASS_C2H_CHL3_EN
    output  wire                                    c2h_dsc_byp_ready_3_o,
    input   wire                                    c2h_dsc_byp_load_3_i,
    input   wire    [63:0]                          c2h_dsc_byp_src_addr_3_i,
    input   wire    [63:0]                          c2h_dsc_byp_dst_addr_3_i,
    input   wire    [27:0]                          c2h_dsc_byp_len_3_i,
    input   wire    [15:0]                          c2h_dsc_byp_ctl_3_i,
`endif
`ifdef  DSC_BYPASS_H2C_CHL0_EN
    output  wire                                    h2c_dsc_byp_ready_0_o,
    input   wire                                    h2c_dsc_byp_load_0_i,
    input   wire    [63:0]                          h2c_dsc_byp_src_addr_0_i,
    input   wire    [63:0]                          h2c_dsc_byp_dst_addr_0_i,
    input   wire    [27:0]                          h2c_dsc_byp_len_0_i,
    input   wire    [15:0]                          h2c_dsc_byp_ctl_0_i,
`endif
`ifdef  DSC_BYPASS_H2C_CHL1_EN
    output  wire                                    h2c_dsc_byp_ready_1_o,
    input   wire                                    h2c_dsc_byp_load_1_i,
    input   wire    [63:0]                          h2c_dsc_byp_src_addr_1_i,
    input   wire    [63:0]                          h2c_dsc_byp_dst_addr_1_i,
    input   wire    [27:0]                          h2c_dsc_byp_len_1_i,
    input   wire    [15:0]                          h2c_dsc_byp_ctl_1_i,
`endif
`ifdef  DSC_BYPASS_H2C_CHL2_EN
    output  wire                                    h2c_dsc_byp_ready_2_o,
    input   wire                                    h2c_dsc_byp_load_2_i,
    input   wire    [63:0]                          h2c_dsc_byp_src_addr_2_i,
    input   wire    [63:0]                          h2c_dsc_byp_dst_addr_2_i,
    input   wire    [27:0]                          h2c_dsc_byp_len_2_i,
    input   wire    [15:0]                          h2c_dsc_byp_ctl_2_i,
`endif
`ifdef  DSC_BYPASS_H2C_CHL3_EN
    output  wire                                    h2c_dsc_byp_ready_3_o,
    input   wire                                    h2c_dsc_byp_load_3_i,
    input   wire    [63:0]                          h2c_dsc_byp_src_addr_3_i,
    input   wire    [63:0]                          h2c_dsc_byp_dst_addr_3_i,
    input   wire    [27:0]                          h2c_dsc_byp_len_3_i,
    input   wire    [15:0]                          h2c_dsc_byp_ctl_3_i,
`endif
`ifdef USR_IRQ_EN
    input   wire    [USR_IRQ_NUM-1:0]               usr_irq_req,
    output  wire    [USR_IRQ_NUM-1:0]               usr_irq_ack,
    `ifdef  MSI_EN
    output  wire                                    msi_enable,
    output  wire    [2:0]                           msi_vector_width,
    `elsif  MSIX_EN 
    output  wire                                    msix_enable,
    `endif
`endif
`ifdef AXI4L_MBUS_EN
    output  wire    [31:0]                          m_axil_awaddr,
    output  wire    [2:0]                           m_axil_awprot,
    output  wire                                    m_axil_awvalid,
    input   wire                                    m_axil_awready,
    output  wire    [31:0]                          m_axil_wdata,
    output  wire    [3:0]                           m_axil_wstrb,
    output  wire                                    m_axil_wvalid,
    input   wire                                    m_axil_wready,
    input   wire                                    m_axil_bvalid,
    input   wire    [1:0]                           m_axil_bresp,
    output  wire                                    m_axil_bready,
    output  wire    [31:0]                          m_axil_araddr,
    output  wire    [2:0]                           m_axil_arprot,
    output  wire                                    m_axil_arvalid,
    input   wire                                    m_axil_arready,
    input   wire    [31:0]                          m_axil_rdata,
    input   wire    [1:0]                           m_axil_rresp,
    input   wire                                    m_axil_rvalid,
    output  wire                                    m_axil_rready,
`endif
`ifdef AXI4L_SBUS_EN
    input   wire    [31:0]                          s_axil_awaddr,
    input   wire    [2:0]                           s_axil_awprot,
    input   wire                                    s_axil_awvalid,
    output  wire                                    s_axil_awready,
    input   wire    [31:0]                          s_axil_wdata,
    input   wire    [3:0]                           s_axil_wstrb,
    input   wire                                    s_axil_wvalid,
    output  wire                                    s_axil_wready,
    output  wire                                    s_axil_bvalid,
    output  wire    [1:0]                           s_axil_bresp,
    input   wire                                    s_axil_bready,
    input   wire    [31:0]                          s_axil_araddr,
    input   wire    [2:0]                           s_axil_arprot,
    input   wire                                    s_axil_arvalid,
    output  wire                                    s_axil_arready,
    output  wire    [31:0]                          s_axil_rdata,
    output  wire    [1:0]                           s_axil_rresp,
    output  wire                                    s_axil_rvalid,
    input   wire                                    s_axil_rready,
`endif
`ifdef CFG_MGMT_EN
    input   wire    [18:0]                          cfg_mgmt_addr,
    input   wire                                    cfg_mgmt_write,
    input   wire    [31:0]                          cfg_mgmt_write_data,
    input   wire    [3:0]                           cfg_mgmt_byte_enable,
    input   wire                                    cfg_mgmt_read,
    output  wire    [31:0]                          cfg_mgmt_read_data,
    output  wire                                    cfg_mgmt_read_write_done,
    input   wire                                    cfg_mgmt_type1_cfg_reg_access,
`endif
`ifdef DMA_BYPA_EN
    input   wire                                    m_axib_arready,
    output  wire    [3:0]                           m_axib_arid,
    output  wire    [63:0]                          m_axib_araddr,
    //specifies the number of data transfers that occur within each burst.
    output  wire    [7:0]                           m_axib_arlen,
    //specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
    output  wire    [2:0]                           m_axib_arsize,
    output  wire    [1:0]                           m_axib_arburst,
    output  wire    [2:0]                           m_axib_arprot,
    output  wire                                    m_axib_arvalid,
    output  wire                                    m_axib_arlock,
    output  wire    [3:0]                           m_axib_arcache,

    input   wire    [3:0]                           m_axib_rid,
    input   wire    [DATA_WIDTH-1:0]               m_axib_rdata,
    input   wire    [1:0]                           m_axib_rresp,
    input   wire                                    m_axib_rlast,
    input   wire                                    m_axib_rvalid,
    output  wire                                    m_axib_rready,

    input   wire                                    m_axib_awready,
    output  wire    [3:0]                           m_axib_awid,
    output  wire    [63:0]                          m_axib_awaddr,
    output  wire    [7:0]                           m_axib_awlen,
    output  wire    [2:0]                           m_axib_awsize,
    output  wire    [1:0]                           m_axib_awburst,
    output  wire    [2:0]                           m_axib_awprot,
    output  wire                                    m_axib_awvalid,
    output  wire                                    m_axib_awlock,
    output  wire    [3:0]                           m_axib_awcache,
    output  wire    [DATA_WIDTH-1:0]               m_axib_wdata,
    output  wire    [DATA_BYTE-1:0]                m_axib_wstrb,
    input   wire                                    m_axib_wready,
    output  wire                                    m_axib_wlast,
    output  wire                                    m_axib_wvalid,
    input   wire    [3:0]                           m_axib_bid,
    input   wire    [1:0]                           m_axib_bresp,
    input   wire                                    m_axib_bvalid,
    output  wire                                    m_axib_bready,
`endif
    output  wire                                    user_link_up,
    output  wire                                    user_clk ,
    output  wire                                    user_rst_n//user_resetn
);

localparam  RQ_TUSER_WIDTH = (DEVICE_FAMILY == "PH1A" || DEVICE_FAMILY == "PH1A100") ? 62 : 137;
localparam  RC_TUSER_WIDTH = (DEVICE_FAMILY == "PH1A" || DEVICE_FAMILY == "PH1A100") ? 75 : 161;
localparam  CQ_TUSER_WIDTH = (DEVICE_FAMILY == "PH1A" || DEVICE_FAMILY == "PH1A100") ? 88 : 183;
localparam  CC_TUSER_WIDTH = (DEVICE_FAMILY == "PH1A" || DEVICE_FAMILY == "PH1A100") ? 33 : 81;
// wire                            user_clk    ;
wire                            user_reset  ;

wire    [DATA_WIDTH-1:0]        s_axis_rq_tdata  ;
wire    [DATA_DW-1:0]           s_axis_rq_tkeep  ;
wire                            s_axis_rq_tlast  ;
wire    [DATA_DW-1:0]           s_axis_rq_tready ;
wire    [RQ_TUSER_WIDTH-1:0]    s_axis_rq_tuser  ;
wire                            s_axis_rq_tvalid ;
wire    [4:0]                   tuser2rq;

wire    [DATA_WIDTH-1:0]        m_axis_rc_tdata  ;
wire    [DATA_DW-1:0]           m_axis_rc_tkeep  ;
wire                            m_axis_rc_tlast  ;
wire                            m_axis_rc_tready ;
wire    [RC_TUSER_WIDTH-1:0]    m_axis_rc_tuser  ;
wire                            m_axis_rc_tvalid ;

wire    [DATA_WIDTH-1:0]        m_axis_cq_tdata  ;
wire    [DATA_DW-1:0]           m_axis_cq_tkeep  ;
wire                            m_axis_cq_tlast  ;
wire                            m_axis_cq_tready ;
wire    [CQ_TUSER_WIDTH-1:0]    m_axis_cq_tuser  ;
wire                            m_axis_cq_tvalid ;

wire    [DATA_WIDTH-1:0]        s_axis_cc_tdata  ;
wire    [DATA_DW-1:0]           s_axis_cc_tkeep  ;
wire                            s_axis_cc_tlast  ;
wire    [3:0]                   s_axis_cc_tready ;
wire    [CC_TUSER_WIDTH-1:0]    s_axis_cc_tuser  ;
wire                            s_axis_cc_tvalid ;

wire    [18:0]                  cfg_mgmt2core_addr;
wire                            cfg_mgmt2core_write;
wire    [31:0]                  cfg_mgmt2core_write_data;
wire    [3:0]                   cfg_mgmt2core_byte_enable;
wire                            cfg_mgmt2core_read;
wire    [31:0]                  cfg_mgmt2core_read_data;
wire                            cfg_mgmt2core_read_write_done;
wire                            cfg_mgmt2core_type1_cfg_reg_access;
//irq
wire    [3:0]                   cfg_interrupt_int;
wire    [3:0]                   cfg_interrupt_pending;
wire                            cfg_interrupt_sent;
wire    [3:0]                   cfg_interrupt_msi_enable;
wire    [11:0]                  cfg_interrupt_msi_mmenable ;    // not support at this time, user need read pcie register self
wire                            cfg_interrupt_msi_mask_update;   // not support
wire    [31:0]                  cfg_interrupt_msi_data;
wire    [1:0]                   cfg_interrupt_msi_select;
wire    [31:0]                  cfg_interrupt_msi_int;
wire    [31:0]                  cfg_interrupt_msi_pending_status;
wire                            cfg_interrupt_msi_pending_status_data_enable;
wire    [1:0]                   cfg_interrupt_msi_pending_status_function_num;
wire                            cfg_interrupt_msi_sent;
wire                            cfg_interrupt_msi_fail;
wire    [2:0]                   cfg_interrupt_msi_attr;
wire                            cfg_interrupt_msi_tph_present;
wire    [1:0]                   cfg_interrupt_msi_tph_type;
wire    [7:0]                   cfg_interrupt_msi_tph_st_tag;
wire    [7:0]                   cfg_interrupt_msi_function_number;

wire    [12:0]                  tl_cfg_busdev;
wire    [1:0]                   cfg_phy_link_down;
wire    [1:0]                   cfg_phy_link_status;
wire    [2:0]                   cfg_max_payload;
wire    [2:0]                   cfg_max_read_req;
wire    [5:0]                   cfg_ltssm_state;

assign  tl_cfg_busdev = 12'h00;
// `ifdef DEV_PH1A00
//     `define     DEV_PH1
// `elsif DEV_PH1A 
//     `define     DEV_PH1
// `endif 

generate if(DEVICE_FAMILY == "PH1A" || DEVICE_FAMILY == "PH1A100") begin : DEVICE_IS_PH1A
al_pcie_if_ep #(
    .SIM_MODE                                       (   SIM_MODE                                        ),
    .LINK_WIDTH                                     (   LINK_WIDTH                                      ),
    .DATA_WIDTH                                     (   DATA_WIDTH                                      )
    ) u_ph1a_if_ep(
    //---reference clock and transciever pairs-------------//
    .refclk_p                                       (   ref_pad_clk_p                                   ),
    .refclk_n                                       (   ref_pad_clk_n                                   ),
    .txp                                            (   pcie_tx_p                                       ),
    .txn                                            (   pcie_tx_n                                       ),
    .rxp                                            (   pcie_rx_p                                       ),
    .rxn                                            (   pcie_rx_n                                       ),

//    .c2h_run_i(c2h_sts_0[6]),
//    .h2c_run_i(h2c_sts_0[6]),
    //---system clock and reset output for user------   -----//
    .app_auxclk                                     (   app_auxclk                                      ),
    .app_perst_n                                    (   tl_power_on_rstn                                ),

    .user_clk                                       (   user_clk                                        ),
    .user_reset                                     (   user_reset                                      ),
    .user_link_up                                   (   user_link_up                                    ),
    .client02rq_tuser_o                             (   tuser2rq                                        ),
    //---pcie data bus interface---------------------   -----//
    .s_axis_rq_tdata                                (   s_axis_rq_tdata                                 ),
    .s_axis_rq_tkeep                                (   s_axis_rq_tkeep                                 ),
    .s_axis_rq_tlast                                (   s_axis_rq_tlast                                 ),
    .s_axis_rq_tready                               (   s_axis_rq_tready                                ),
    .s_axis_rq_tuser                                (   s_axis_rq_tuser                                 ),
    .s_axis_rq_tvalid                               (   s_axis_rq_tvalid                                ),

    .m_axis_rc_tdata                                (   m_axis_rc_tdata                                 ),
    .m_axis_rc_tkeep                                (   m_axis_rc_tkeep                                 ),
    .m_axis_rc_tlast                                (   m_axis_rc_tlast                                 ),
    .m_axis_rc_tready                               (   m_axis_rc_tready                                ),
    .m_axis_rc_tuser                                (   m_axis_rc_tuser                                 ),
    .m_axis_rc_tvalid                               (   m_axis_rc_tvalid                                ),

    .m_axis_cq_tdata                                (   m_axis_cq_tdata                                 ),
    .m_axis_cq_tkeep                                (   m_axis_cq_tkeep                                 ),
    .m_axis_cq_tlast                                (   m_axis_cq_tlast                                 ),
    .m_axis_cq_tready                               (   m_axis_cq_tready                                ),
    .m_axis_cq_tuser                                (   m_axis_cq_tuser                                 ),
    .m_axis_cq_tvalid                               (   m_axis_cq_tvalid                                ),

    .s_axis_cc_tdata                                (   s_axis_cc_tdata                                 ),
    .s_axis_cc_tkeep                                (   s_axis_cc_tkeep                                 ),
    .s_axis_cc_tlast                                (   s_axis_cc_tlast                                 ),
    .s_axis_cc_tready                               (   s_axis_cc_tready                                ),
    .s_axis_cc_tuser                                (   s_axis_cc_tuser                                 ),
    .s_axis_cc_tvalid                               (   s_axis_cc_tvalid                                ),
    //---pcie cfg bus interface--------------------------//
    .cfg_mgmt_addr                                  (   cfg_mgmt2core_addr                              ),
    .cfg_mgmt_function_number                       (   0                                               ),
    .cfg_mgmt_write                                 (   cfg_mgmt2core_write                             ),
    .cfg_mgmt_write_data                            (   cfg_mgmt2core_write_data                        ),
    .cfg_mgmt_byte_enable                           (   cfg_mgmt2core_byte_enable                       ),
    .cfg_mgmt_read                                  (   cfg_mgmt2core_read                              ),
    .cfg_mgmt_read_data                             (   cfg_mgmt2core_read_data                         ),
    .cfg_mgmt_read_write_done                       (   cfg_mgmt2core_read_write_done                   ),
    .cfg_mgmt_debug_access                          (   cfg_mgmt2core_type1_cfg_reg_access              ),
    //---pcie msi bus interface----------------------   ----//
    .cfg_interrupt_int                              (   cfg_interrupt_int                               ),
    .cfg_interrupt_pending                          (   cfg_interrupt_pending                           ),
    .cfg_interrupt_sent                             (   cfg_interrupt_sent                              ),
    .cfg_interrupt_msi_enable                       (   cfg_interrupt_msi_enable                        ),
    .cfg_interrupt_msi_mmenable                     (   cfg_interrupt_msi_mmenable                      ),
    .cfg_interrupt_msi_mask_update                  (   cfg_interrupt_msi_mask_update                   ),
    .cfg_interrupt_msi_data                         (   cfg_interrupt_msi_data                          ),
    .cfg_interrupt_msi_select                       (   cfg_interrupt_msi_select                        ),
    .cfg_interrupt_msi_int                          (   cfg_interrupt_msi_int                           ),
    .cfg_interrupt_msi_pending_status               (   cfg_interrupt_msi_pending_status                ),
    .cfg_interrupt_msi_pending_status_data_enable   (   cfg_interrupt_msi_pending_status_data_enable    ),
    .cfg_interrupt_msi_pending_status_function_num  (   cfg_interrupt_msi_pending_status_function_num   ),
    .cfg_interrupt_msi_sent                         (   cfg_interrupt_msi_sent                          ),
    .cfg_interrupt_msi_fail                         (   cfg_interrupt_msi_fail                          ),
    .cfg_interrupt_msi_attr                         (   cfg_interrupt_msi_attr                          ),
    .cfg_interrupt_msi_tph_present                  (   cfg_interrupt_msi_tph_present                   ),
    .cfg_interrupt_msi_tph_type                     (   cfg_interrupt_msi_tph_type                      ),
    .cfg_interrupt_msi_tph_st_tag                   (   cfg_interrupt_msi_tph_st_tag                    ),
    .cfg_interrupt_msi_function_number              (   cfg_interrupt_msi_function_number               ),
    .phy_rdy_out                                    (   )
);
end else if(DEVICE_FAMILY == "PH2A") begin : pcie_brg_ph2

    wire pcie_brg_user_reset;
    wire user_resetn;

    assign user_reset = ~user_resetn;

    ph2_pcie_rst_sync#(
        .LTSSM_VAULE(6'h10)
    ) u_ph2_pcie_rst_sync(
        .clk(user_clk),
        .rst(pcie_brg_user_reset),
        .tl_ltssm(cfg_ltssm_state),
        .pl_link_up(~cfg_phy_link_down),
        .rstn_sync(user_resetn)
    );

    pcie_brg_top#(
        .LANE_WIDTH(LINK_WIDTH),        // [PATCHED] was 8, now uses module parameter
        .USER_CLK_FREQ(USER_CLK_FREQ),
        .DATA_WIDTH(512),
        .CORE_DATA_WIDTH(512),
        .CQ_DWORD_ALIGN(1),
        .CC_DWORD_ALIGN(1),
        .RQ_DWORD_ALIGN(1),
        .RC_DWORD_ALIGN(1),
        .CQ_STRADDLE(0),
        .CC_STRADDLE(0),
        .RQ_STRADDLE(0),
        .RC_STRADDLE(0),
        .PF_NUM(4),
        .VF_NUM(252),
        .MSI_EN(1),
        .MSIX_EN(0),
        .XMIT_MSG_EN(0),
        .RECV_MSG_EN(0),
        .LEGACY_DEVICE(0),
        .EP_MODE(1),

        .PH2_SRAM_HXT_FILE(PH2_SRAM_HXT_FILE),
        .PH2_CSR_HXT_FILE(PH2_CSR_HXT_FILE)
    ) pcie_brg_top(
        .pcie_tx_n(pcie_tx_n),
        .pcie_tx_p(pcie_tx_p),
        .pcie_rx_n(pcie_rx_n),
        .pcie_rx_p(pcie_rx_p),
        .pcie_clk_p(ref_pad_clk_p),
        .pcie_clk_n(ref_pad_clk_n),
        .pcie_rstn(tl_power_on_rstn),
        .pll_lock(pll_lock),
        .init_clk(app_auxclk),
        .core_clk(tl_clk_user),
        .core_clk2(tl_clk_user),
        .user_clk(user_clk),
        .user_rst(pcie_brg_user_reset),
        // cq
        .m_axis_cq_tdata(m_axis_cq_tdata),
        .m_axis_cq_tuser(m_axis_cq_tuser),
        .m_axis_cq_tlast(m_axis_cq_tlast),
        .m_axis_cq_tkeep(m_axis_cq_tkeep),
        .m_axis_cq_tvalid(m_axis_cq_tvalid),
        .m_axis_cq_tready(m_axis_cq_tready),
        .pcie_cq_np_req(2'b11),
        .pcie_cq_np_req_count(),
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
        .pcie_rq_seq_num0(),
        .pcie_rq_seq_num1(),
        .pcie_rq_seq_num_vld0(),
        .pcie_rq_seq_num_vld1(),
        // rc
        .m_axis_rc_tdata(m_axis_rc_tdata),
        .m_axis_rc_tuser(m_axis_rc_tuser),
        .m_axis_rc_tlast(m_axis_rc_tlast),
        .m_axis_rc_tkeep(m_axis_rc_tkeep),
        .m_axis_rc_tvalid(m_axis_rc_tvalid),
        .m_axis_rc_tready(m_axis_rc_tready),
        // cfg mgmt
        .cfg_mgmt_addr(0),
        .cfg_mgmt_function_number(0),
        .cfg_mgmt_write(0),
        .cfg_mgmt_write_data(0),
        .cfg_mgmt_byte_enable(0),
        .cfg_mgmt_read(0),
        .cfg_mgmt_read_data(),
        .cfg_mgmt_read_write_done(),
        .cfg_mgmt_debug_access(0),
        // cfg status
        .cfg_phy_link_down(cfg_phy_link_down),
        .cfg_phy_link_status(cfg_phy_link_status),
        .cfg_negotiated_width(),
        .cfg_current_speed(),
        .cfg_max_payload(cfg_max_payload),
        .cfg_max_read_req(cfg_max_read_req),
        .cfg_function_status(),
        .cfg_vf_status(),
        .cfg_function_power_state(),
        .cfg_vf_power_state(),
        .cfg_link_power_state(),
        .cfg_local_error_out(),
        .cfg_local_error_valid(),
        .cfg_rx_pm_state(),
        .cfg_tx_pm_state(),
        .cfg_ltssm_state(cfg_ltssm_state),
        .cfg_rcb_status(),
        .cfg_dpa_substate_change(),
        .cfg_obff_enable(),
        .cfg_pl_status_change(),
        .cfg_tph_requester_enable(),
        .cfg_tph_st_mode(),
        .cfg_vf_tph_requester_enable(),
        .cfg_vf_tph_st_mode(),
        .pcie_tfc_nph_av(),
        .pcie_tfc_npd_av(),
        // recv msg
        .cfg_msg_received(),
        .cfg_msg_received_data(),
        .cfg_msg_received_type(),
        // xmit msg
        .cfg_msg_transmit(0),
        .cfg_msg_transmit_type(0),
        .cfg_msg_transmit_data(0),
        .cfg_msg_transmit_done(),
        // flow ctrl
        .cfg_fc_ph(),
        .cfg_fc_pd(),
        .cfg_fc_nph(),
        .cfg_fc_npd(),
        .cfg_fc_cplh(),
        .cfg_fc_cpld(),
        // ctrl
        .cfg_link_training_enable(1),
        .cfg_bus_number(),
        .cfg_dev_number(),
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
        .cfg_interrupt_msi_pending_status_function_number(cfg_interrupt_msi_pending_status_function_num),
        .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),
        .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),
        .cfg_interrupt_msi_select(cfg_interrupt_msi_select),
        .cfg_interrupt_msi_data(cfg_interrupt_msi_data),
        .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),
        .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),
        .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),
        .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),
        // msix int
        .cfg_interrupt_msix_enable(),
        .cfg_interrupt_msix_mask(),
        .cfg_interrupt_msix_vf_enable(),
        .cfg_interrupt_msix_vf_mask(),
        .cfg_interrupt_msix_addr(0),
        .cfg_interrupt_msix_data(0),
        .cfg_interrupt_msix_int(0),
        .cfg_interrupt_msix_vec_pending(0),
        .cfg_interrupt_msix_vec_pending_status()
    );

    assign user_clk = tl_clk_user;
    assign user_link_up = cfg_phy_link_status == 2'b11;
end else if(DEVICE_FAMILY == "PH1P") begin : DEVICE_IS_PH1P
    pcie_brg_top#(
        .DEVICE_FAMILY      ("PH1P"),
        .LANE_WIDTH         (LINK_WIDTH     ),
        .USER_CLK_FREQ      (USER_CLK_FREQ),
        .SYNC_CLOCK         (1),
        .DATA_WIDTH         (DATA_WIDTH),
        .CQ_DWORD_ALIGN     (1),
        .CC_DWORD_ALIGN     (1),
        .RQ_DWORD_ALIGN     (1),
        .RC_DWORD_ALIGN     (1),
        .CQ_STRADDLE        (0),
        .CC_STRADDLE        (0),
        .RQ_STRADDLE        (0),
        .RC_STRADDLE        (0),
        .PF_NUM             (5),
        .VF_NUM             (252),
        .MSI_EN             (MSI_EN     ),
        .MSIX_EN            (MSIX_EN    ),
        .XMIT_MSG_EN        (0),
        .RECV_MSG_EN        (0),
        .LEGACY_DEVICE      (0),
        .EP_MODE            (1)
    ) pcie_brg_ph1p(
        .pcie_tx_n          (pcie_tx_n),
        .pcie_tx_p          (pcie_tx_p),
        .pcie_rx_n          (pcie_rx_n),
        .pcie_rx_p          (pcie_rx_p),
        .pcie_clk_p         (ref_pad_clk_p),
        .pcie_clk_n         (ref_pad_clk_n),
        .pcie_rstn          (tl_power_on_rstn),
        .pll_lock           (pll_lock),
        .init_clk           (app_auxclk),
        .core_clk           (tl_clk_user),
        .core_clk2          (tl_clk_user),
        .user_rst           (user_reset),
        // cq
        .m_axis_cq_tdata    (m_axis_cq_tdata),
        .m_axis_cq_tuser    (m_axis_cq_tuser),
        .m_axis_cq_tlast    (m_axis_cq_tlast),
        .m_axis_cq_tkeep    (m_axis_cq_tkeep),
        .m_axis_cq_tvalid   (m_axis_cq_tvalid),
        .m_axis_cq_tready   (m_axis_cq_tready),
        .pcie_cq_np_req     (2'b11),
        .pcie_cq_np_req_count(),
        // cc
        .s_axis_cc_tdata    (s_axis_cc_tdata),
        .s_axis_cc_tuser    (s_axis_cc_tuser),
        .s_axis_cc_tlast    (s_axis_cc_tlast),
        .s_axis_cc_tkeep    (s_axis_cc_tkeep),
        .s_axis_cc_tvalid   (s_axis_cc_tvalid),
        .s_axis_cc_tready   (s_axis_cc_tready),
        // rq
        .s_axis_rq_tdata    (s_axis_rq_tdata),
        .s_axis_rq_tuser    (s_axis_rq_tuser),
        .s_axis_rq_tlast    (s_axis_rq_tlast),
        .s_axis_rq_tkeep    (s_axis_rq_tkeep),
        .s_axis_rq_tvalid   (s_axis_rq_tvalid),
        .s_axis_rq_tready   (s_axis_rq_tready),
        .pcie_rq_seq_num0   (),
        .pcie_rq_seq_num1   (),
        .pcie_rq_seq_num_vld0(),
        .pcie_rq_seq_num_vld1(),
        // rc
        .m_axis_rc_tdata    (m_axis_rc_tdata),
        .m_axis_rc_tuser    (m_axis_rc_tuser),
        .m_axis_rc_tlast    (m_axis_rc_tlast),
        .m_axis_rc_tkeep    (m_axis_rc_tkeep),
        .m_axis_rc_tvalid   (m_axis_rc_tvalid),
        .m_axis_rc_tready   (m_axis_rc_tready),
        // cfg status
        .cfg_phy_link_down  (),
        .cfg_phy_link_status(cfg_phy_link_status),
        .cfg_negotiated_width(),
        .cfg_current_speed  (),
        .cfg_max_payload    (cfg_max_payload),
        .cfg_max_read_req   (cfg_max_read_req),
        .cfg_function_status(),
        .cfg_vf_status      (),
        .cfg_function_power_state(),
        .cfg_vf_power_state (),
        .cfg_link_power_state(),
        .cfg_local_error_out(),
        .cfg_local_error_valid(),
        .cfg_rx_pm_state    (),
        .cfg_tx_pm_state    (),
        .cfg_ltssm_state    (),
        .cfg_rcb_status     (),
        .cfg_dpa_substate_change(),
        .cfg_obff_enable    (),
        .cfg_pl_status_change(),
        .cfg_tph_requester_enable(),
        .cfg_tph_st_mode    (),
        .cfg_vf_tph_requester_enable(),
        .cfg_vf_tph_st_mode (),
        .pcie_tfc_nph_av(),
        .pcie_tfc_npd_av(),
//        .pcie_rq_tag_av(),
        // recv msg
        .cfg_msg_received(),
        .cfg_msg_received_data(),
        .cfg_msg_received_type(),
        // xmit msg
        .cfg_msg_transmit(0),
        .cfg_msg_transmit_type(0),
        .cfg_msg_transmit_data(0),
        .cfg_msg_transmit_done(),

        .cfg_link_training_enable(1),
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
        .cfg_interrupt_msi_pending_status_function_number(cfg_interrupt_msi_pending_status_function_num),
        .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),
        .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),
        .cfg_interrupt_msi_select(cfg_interrupt_msi_select),
        .cfg_interrupt_msi_data(cfg_interrupt_msi_data),
        .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),
        .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),
        .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),
        .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),
        // msix int
        .cfg_interrupt_msix_enable(),
        .cfg_interrupt_msix_mask(),
        .cfg_interrupt_msix_vf_enable(),
        .cfg_interrupt_msix_vf_mask(),
        .cfg_interrupt_msix_addr(0),
        .cfg_interrupt_msix_data(0),
        .cfg_interrupt_msix_int(0),
        .cfg_interrupt_msix_vec_pending(0),
        .cfg_interrupt_msix_vec_pending_status()
    );

    assign user_clk = tl_clk_user;
    assign user_link_up = cfg_phy_link_status == 2'b11;
end
endgenerate

//---SGDMA-IP      ---
sgdma_ip #(
    .DLY                                            (   1                       ),
    .CWC_DBG                                        (   0                       ),
    .DEVICE_FAMILY                                  (   DEVICE_FAMILY           ),
    .DATA_WIDTH                                     (   DATA_WIDTH              ),
    .AXI4ST_BUS_EN                                  (   AXI4ST_BUS_EN           ),
    .AXI4MM_BUS_EN                                  (   AXI4MM_BUS_EN           ),
    .DMA_BYPA_EN                                    (   DMA_BYPA_EN             ),
    .AXI4L_MBUS_EN                                  (   AXI4L_MBUS_EN           ),
    .AXI4L_SBUS_EN                                  (   AXI4L_SBUS_EN           ),
    .H2C_CHNL_NUM                                   (   H2C_CHNL_NUM            ),
    .C2H_CHNL_NUM                                   (   C2H_CHNL_NUM            ),
    .H2C_DSC_BYP_MAP                                (   H2C_DSC_BYP_MAP         ),
    .C2H_DSC_BYP_MAP                                (   C2H_DSC_BYP_MAP         ),
`ifdef USR_IRQ_EN
    .DMA_USR_IRQ                                    (   USR_IRQ_NUM             ),
`else
    .DMA_USR_IRQ                                    (   1                       ),
`endif
    .H2C_ID_NUM                                     (   H2C_ID_NUM              ),
    .C2H_ID_NUM                                     (   C2H_ID_NUM              ),
    //set interrupt type
    .LGCY_EN                                        (   LGCY_EN                 ),
    .MSI_EN                                         (   MSI_EN                  ),
    .MSIX_EN                                        (   MSIX_EN                 ),
    .RQ_TUSER_WIDTH                                 (   RQ_TUSER_WIDTH          ),
    .RC_TUSER_WIDTH                                 (   RC_TUSER_WIDTH          ),
    .CQ_TUSER_WIDTH                                 (   CQ_TUSER_WIDTH          ),
    .CC_TUSER_WIDTH                                 (   CC_TUSER_WIDTH          )
) u_sgdma_ip(
    .core_rstn                                      (   !user_reset & ((DEVICE_FAMILY == "PH2A") ? (cfg_phy_link_status == 2'b11) : 1'b1)             ),
    .core_clk                                       (   user_clk                ),

    .c2h_sts_0_o                                    (c2h_sts_0                  ),
    .h2c_sts_0_o                                    (h2c_sts_0                  ),
    .c2h_sts_1_o                                    (c2h_sts_1                  ),
    .h2c_sts_1_o                                    (h2c_sts_1                  ),
    .c2h_sts_2_o                                    (c2h_sts_2                  ),
    .h2c_sts_2_o                                    (h2c_sts_2                  ),
    .c2h_sts_3_o                                    (c2h_sts_3                  ),
    .h2c_sts_3_o                                    (h2c_sts_3                  ),
    //---usr-irq->msi---
`ifdef USR_IRQ_EN
    .usr_irq_req_i                                  (   usr_irq_req             ),
    .usr_irq_ack_o                                  (   usr_irq_ack             ),
    .msi_enable_o                                   (   msi_enable              ),
    .msi_vector_width_o                             (   msi_vector_width        ),
`else
    .usr_irq_req_i                                  (   0                       ),
`endif
`ifdef DMA_BYPA_EN
    .m_axib_awready_i                               (   m_axib_awready          ),
    .m_axib_wready_i                                (   m_axib_wready           ),
    .m_axib_bid_i                                   (   m_axib_bid              ),
    .m_axib_bresp_i                                 (   m_axib_bresp            ),
    .m_axib_bvalid_i                                (   m_axib_bvalid           ),
    .m_axib_arready_i                               (   m_axib_arready          ),
    .m_axib_rid_i                                   (   m_axib_rid              ),
    .m_axib_rdata_i                                 (   m_axib_rdata            ),
    .m_axib_rresp_i                                 (   m_axib_rresp            ),
    .m_axib_rlast_i                                 (   m_axib_rlast            ),
    .m_axib_rvalid_i                                (   m_axib_rvalid           ),
    .m_axib_awid_o                                  (   m_axib_awid             ),
    .m_axib_awaddr_o                                (   m_axib_awaddr           ),
    .m_axib_awlen_o                                 (   m_axib_awlen            ),
    .m_axib_awsize_o                                (   m_axib_awsize           ),
    .m_axib_awburst_o                               (   m_axib_awburst          ),
    .m_axib_awprot_o                                (   m_axib_awprot           ),
    .m_axib_awvalid_o                               (   m_axib_awvalid          ),
    .m_axib_awlock_o                                (   m_axib_awlock           ),
    .m_axib_awcache_o                               (   m_axib_awcache          ),
    .m_axib_wdata_o                                 (   m_axib_wdata            ),
    .m_axib_wstrb_o                                 (   m_axib_wstrb            ),
    .m_axib_wlast_o                                 (   m_axib_wlast            ),
    .m_axib_wvalid_o                                (   m_axib_wvalid           ),
    .m_axib_bready_o                                (   m_axib_bready           ),
    .m_axib_arid_o                                  (   m_axib_arid             ),
    .m_axib_araddr_o                                (   m_axib_araddr           ),
    .m_axib_arlen_o                                 (   m_axib_arlen            ),
    .m_axib_arsize_o                                (   m_axib_arsize           ),
    .m_axib_arburst_o                               (   m_axib_arburst          ),
    .m_axib_arprot_o                                (   m_axib_arprot           ),
    .m_axib_arvalid_o                               (   m_axib_arvalid          ),
    .m_axib_arlock_o                                (   m_axib_arlock           ),
    .m_axib_arcache_o                               (   m_axib_arcache          ),
    .m_axib_rready_o                                (   m_axib_rready           )
`else
    .m_axib_awready_i                               (   0                       ),
    .m_axib_wready_i                                (   0                       ),
    .m_axib_bid_i                                   (   0                       ),
    .m_axib_bresp_i                                 (   0                       ),
    .m_axib_bvalid_i                                (   0                       ),
    .m_axib_arready_i                               (   0                       ),
    .m_axib_rid_i                                   (   0                       ),
    .m_axib_rdata_i                                 (   0                       ),
    .m_axib_rresp_i                                 (   0                       ),
    .m_axib_rlast_i                                 (   0                       ),
    .m_axib_rvalid_i                                (   0                       ),
`endif
`ifdef AXI4ST_BUS_EN
    .s_axis_tx_tdata_i                              (   s0_axis_c2h_tdata       ),
    .s_axis_tx_tlast_i                              (   s0_axis_c2h_tlast       ),
    .s_axis_tx_tvalid_i                             (   s0_axis_c2h_tvalid      ),
    .s_axis_tx_tready_o                             (   s0_axis_c2h_tready      ),
    .s_axis_tx_tuser_i                              (   s0_axis_c2h_tuser       ),
    .s_axis_tx_tkeep_i                              (   s0_axis_c2h_tkeep       ),
    .m_axis_rx_tdata_o                              (   m0_axis_h2c_tdata       ),
    .m_axis_rx_tlast_o                              (   m0_axis_h2c_tlast       ),
    .m_axis_rx_tvalid_o                             (   m0_axis_h2c_tvalid      ),
    .m_axis_rx_tready_i                             (   m0_axis_h2c_tready      ),
    .m_axis_rx_tuser_o                              (   m0_axis_h2c_tuser       ),
    .m_axis_rx_tkeep_o                              (   m0_axis_h2c_tkeep       ),
`else
    .s_axis_tx_tdata_i                              (   0                       ),
    .s_axis_tx_tlast_i                              (   0                       ),
    .s_axis_tx_tvalid_i                             (   0                       ),
    .s_axis_tx_tuser_i                              (   0                       ),
    .s_axis_tx_tkeep_i                              (   0                       ),
    .m_axis_rx_tready_i                             (   0                       ),
`endif
`ifdef AXI4MM_BUS_EN
    .m_axi_awready_i                                (   m_axi_awready           ),
    .m_axi_wready_i                                 (   m_axi_wready            ),
    .m_axi_bid_i                                    (   m_axi_bid               ),
    .m_axi_bresp_i                                  (   m_axi_bresp             ),
    .m_axi_bvalid_i                                 (   m_axi_bvalid            ),
    .m_axi_arready_i                                (   m_axi_arready           ),
    .m_axi_rid_i                                    (   m_axi_rid               ),
    .m_axi_rdata_i                                  (   m_axi_rdata             ),
    .m_axi_ruser_i                                  (   m_axi_ruser             ),
    .m_axi_rresp_i                                  (   m_axi_rresp             ),
    .m_axi_rlast_i                                  (   m_axi_rlast             ),
    .m_axi_rvalid_i                                 (   m_axi_rvalid            ),
    .m_axi_awid_o                                   (   m_axi_awid              ),
    .m_axi_awaddr_o                                 (   m_axi_awaddr            ),
    .m_axi_awlen_o                                  (   m_axi_awlen             ),
    .m_axi_awsize_o                                 (   m_axi_awsize            ),
    .m_axi_awburst_o                                (   m_axi_awburst           ),
    .m_axi_awprot_o                                 (   m_axi_awprot            ),
    .m_axi_awvalid_o                                (   m_axi_awvalid           ),
    .m_axi_awlock_o                                 (   m_axi_awlock            ),
    .m_axi_awcache_o                                (   m_axi_awcache           ),
    .m_axi_wdata_o                                  (   m_axi_wdata             ),
    .m_axi_wstrb_o                                  (   m_axi_wstrb             ),
    .m_axi_wlast_o                                  (   m_axi_wlast             ),
    .m_axi_wvalid_o                                 (   m_axi_wvalid            ),
    .m_axi_bready_o                                 (   m_axi_bready            ),
    .m_axi_arid_o                                   (   m_axi_arid              ),
    .m_axi_araddr_o                                 (   m_axi_araddr            ),
    .m_axi_arlen_o                                  (   m_axi_arlen             ),
    .m_axi_arsize_o                                 (   m_axi_arsize            ),
    .m_axi_arburst_o                                (   m_axi_arburst           ),
    .m_axi_arprot_o                                 (   m_axi_arprot            ),
    .m_axi_arvalid_o                                (   m_axi_arvalid           ),
    .m_axi_arlock_o                                 (   m_axi_arlock            ),
    .m_axi_arcache_o                                (   m_axi_arcache           ),
    .m_axi_rready_o                                 (   m_axi_rready            ),
`else
    .m_axi_awready_i                                (   0                       ),
    .m_axi_wready_i                                 (   0                       ),
    .m_axi_bid_i                                    (   0                       ),
    .m_axi_bresp_i                                  (   0                       ),
    .m_axi_bvalid_i                                 (   0                       ),
    .m_axi_arready_i                                (   0                       ),
    .m_axi_rid_i                                    (   0                       ),
    .m_axi_rdata_i                                  (   0                       ),
    .m_axi_ruser_i                                  (   0                       ),
    .m_axi_rresp_i                                  (   0                       ),
    .m_axi_rlast_i                                  (   0                       ),
    .m_axi_rvalid_i                                 (   0                       ),
`endif
`ifdef  DSC_BYPASS_C2H_CHL0_EN
    .c2h_dsc_byp_ready_0_o                          (   c2h_dsc_byp_ready_0_o   ),
    .c2h_dsc_byp_load_0_i                           (   c2h_dsc_byp_load_0_i    ),
    .c2h_dsc_byp_src_addr_0_i                       (   c2h_dsc_byp_src_addr_0_i),
    .c2h_dsc_byp_dst_addr_0_i                       (   c2h_dsc_byp_dst_addr_0_i),
    .c2h_dsc_byp_len_0_i                            (   c2h_dsc_byp_len_0_i     ),
    .c2h_dsc_byp_ctl_0_i                            (   c2h_dsc_byp_ctl_0_i     ),
`else
    .c2h_dsc_byp_load_0_i                           (   0                       ),
    .c2h_dsc_byp_src_addr_0_i                       (   0                       ),
    .c2h_dsc_byp_dst_addr_0_i                       (   0                       ),
    .c2h_dsc_byp_len_0_i                            (   0                       ),
    .c2h_dsc_byp_ctl_0_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_C2H_CHL1_EN
    .c2h_dsc_byp_ready_1_o                          (   c2h_dsc_byp_ready_1_o   ),
    .c2h_dsc_byp_load_1_i                           (   c2h_dsc_byp_load_1_i    ),
    .c2h_dsc_byp_src_addr_1_i                       (   c2h_dsc_byp_src_addr_1_i),
    .c2h_dsc_byp_dst_addr_1_i                       (   c2h_dsc_byp_dst_addr_1_i),
    .c2h_dsc_byp_len_1_i                            (   c2h_dsc_byp_len_1_i     ),
    .c2h_dsc_byp_ctl_1_i                            (   c2h_dsc_byp_ctl_1_i     ),
`else
    .c2h_dsc_byp_load_1_i                           (   0                       ),
    .c2h_dsc_byp_src_addr_1_i                       (   0                       ),
    .c2h_dsc_byp_dst_addr_1_i                       (   0                       ),
    .c2h_dsc_byp_len_1_i                            (   0                       ),
    .c2h_dsc_byp_ctl_1_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_C2H_CHL2_EN
    .c2h_dsc_byp_ready_2_o                          (   c2h_dsc_byp_ready_2_o   ),
    .c2h_dsc_byp_load_2_i                           (   c2h_dsc_byp_load_2_i    ),
    .c2h_dsc_byp_src_addr_2_i                       (   c2h_dsc_byp_src_addr_2_i),
    .c2h_dsc_byp_dst_addr_2_i                       (   c2h_dsc_byp_dst_addr_2_i),
    .c2h_dsc_byp_len_2_i                            (   c2h_dsc_byp_len_2_i     ),
    .c2h_dsc_byp_ctl_2_i                            (   c2h_dsc_byp_ctl_2_i     ),
`else
    .c2h_dsc_byp_load_2_i                           (   0                       ),
    .c2h_dsc_byp_src_addr_2_i                       (   0                       ),
    .c2h_dsc_byp_dst_addr_2_i                       (   0                       ),
    .c2h_dsc_byp_len_2_i                            (   0                       ),
    .c2h_dsc_byp_ctl_2_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_C2H_CHL3_EN
    .c2h_dsc_byp_ready_3_o                          (   c2h_dsc_byp_ready_3_o   ),
    .c2h_dsc_byp_load_3_i                           (   c2h_dsc_byp_load_3_i    ),
    .c2h_dsc_byp_src_addr_3_i                       (   c2h_dsc_byp_src_addr_3_i),
    .c2h_dsc_byp_dst_addr_3_i                       (   c2h_dsc_byp_dst_addr_3_i),
    .c2h_dsc_byp_len_3_i                            (   c2h_dsc_byp_len_3_i     ),
    .c2h_dsc_byp_ctl_3_i                            (   c2h_dsc_byp_ctl_3_i     ),
`else
    .c2h_dsc_byp_load_3_i                           (   0                       ),
    .c2h_dsc_byp_src_addr_3_i                       (   0                       ),
    .c2h_dsc_byp_dst_addr_3_i                       (   0                       ),
    .c2h_dsc_byp_len_3_i                            (   0                       ),
    .c2h_dsc_byp_ctl_3_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_H2C_CHL0_EN
    .h2c_dsc_byp_ready_0_o                          (   h2c_dsc_byp_ready_0_o   ),
    .h2c_dsc_byp_load_0_i                           (   h2c_dsc_byp_load_0_i    ),
    .h2c_dsc_byp_src_addr_0_i                       (   h2c_dsc_byp_src_addr_0_i),
    .h2c_dsc_byp_dst_addr_0_i                       (   h2c_dsc_byp_dst_addr_0_i),
    .h2c_dsc_byp_len_0_i                            (   h2c_dsc_byp_len_0_i     ),
    .h2c_dsc_byp_ctl_0_i                            (   h2c_dsc_byp_ctl_0_i     ),
`else
    .h2c_dsc_byp_load_0_i                           (   0                       ),
    .h2c_dsc_byp_src_addr_0_i                       (   0                       ),
    .h2c_dsc_byp_dst_addr_0_i                       (   0                       ),
    .h2c_dsc_byp_len_0_i                            (   0                       ),
    .h2c_dsc_byp_ctl_0_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_H2C_CHL1_EN
    .h2c_dsc_byp_ready_1_o                          (   h2c_dsc_byp_ready_1_o   ),
    .h2c_dsc_byp_load_1_i                           (   h2c_dsc_byp_load_1_i    ),
    .h2c_dsc_byp_src_addr_1_i                       (   h2c_dsc_byp_src_addr_1_i),
    .h2c_dsc_byp_dst_addr_1_i                       (   h2c_dsc_byp_dst_addr_1_i),
    .h2c_dsc_byp_len_1_i                            (   h2c_dsc_byp_len_1_i     ),
    .h2c_dsc_byp_ctl_1_i                            (   h2c_dsc_byp_ctl_1_i     ),
`else
    .h2c_dsc_byp_load_1_i                           (   0                       ),
    .h2c_dsc_byp_src_addr_1_i                       (   0                       ),
    .h2c_dsc_byp_dst_addr_1_i                       (   0                       ),
    .h2c_dsc_byp_len_1_i                            (   0                       ),
    .h2c_dsc_byp_ctl_1_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_H2C_CHL2_EN
    .h2c_dsc_byp_ready_2_o                          (   h2c_dsc_byp_ready_2_o   ),
    .h2c_dsc_byp_load_2_i                           (   h2c_dsc_byp_load_2_i    ),
    .h2c_dsc_byp_src_addr_2_i                       (   h2c_dsc_byp_src_addr_2_i),
    .h2c_dsc_byp_dst_addr_2_i                       (   h2c_dsc_byp_dst_addr_2_i),
    .h2c_dsc_byp_len_2_i                            (   h2c_dsc_byp_len_2_i     ),
    .h2c_dsc_byp_ctl_2_i                            (   h2c_dsc_byp_ctl_2_i     ),
`else
    .h2c_dsc_byp_load_2_i                           (   0                       ),
    .h2c_dsc_byp_src_addr_2_i                       (   0                       ),
    .h2c_dsc_byp_dst_addr_2_i                       (   0                       ),
    .h2c_dsc_byp_len_2_i                            (   0                       ),
    .h2c_dsc_byp_ctl_2_i                            (   0                       ),
`endif
`ifdef  DSC_BYPASS_H2C_CHL3_EN
    .h2c_dsc_byp_ready_3_o                          (   h2c_dsc_byp_ready_3_o   ),
    .h2c_dsc_byp_load_3_i                           (   h2c_dsc_byp_load_3_i    ),
    .h2c_dsc_byp_src_addr_3_i                       (   h2c_dsc_byp_src_addr_3_i),
    .h2c_dsc_byp_dst_addr_3_i                       (   h2c_dsc_byp_dst_addr_3_i),
    .h2c_dsc_byp_len_3_i                            (   h2c_dsc_byp_len_3_i     ),
    .h2c_dsc_byp_ctl_3_i                            (   h2c_dsc_byp_ctl_3_i     ),
`else
    .h2c_dsc_byp_load_3_i                           (   0                       ),
    .h2c_dsc_byp_src_addr_3_i                       (   0                       ),
    .h2c_dsc_byp_dst_addr_3_i                       (   0                       ),
    .h2c_dsc_byp_len_3_i                            (   0                       ),
    .h2c_dsc_byp_ctl_3_i                            (   0                       ),
`endif
`ifdef AXI4L_MBUS_EN
    //---axi-lite---
    .m_axil_awaddr_o                                (   m_axil_awaddr           ),
    .m_axil_awprot_o                                (   m_axil_awprot           ),
    .m_axil_awvalid_o                               (   m_axil_awvalid          ),
    .m_axil_awready_i                               (   m_axil_awready          ),
    .m_axil_wdata_o                                 (   m_axil_wdata            ),
    .m_axil_wstrb_o                                 (   m_axil_wstrb            ),
    .m_axil_wvalid_o                                (   m_axil_wvalid           ),
    .m_axil_wready_i                                (   m_axil_wready           ),
    .m_axil_bvalid_i                                (   m_axil_bvalid           ),
    .m_axil_bresp_i                                 (   m_axil_bresp            ),
    .m_axil_bready_o                                (   m_axil_bready           ),
    .m_axil_araddr_o                                (   m_axil_araddr           ),
    .m_axil_arprot_o                                (   m_axil_arprot           ),
    .m_axil_arvalid_o                               (   m_axil_arvalid          ),
    .m_axil_arready_i                               (   m_axil_arready          ),
    .m_axil_rdata_i                                 (   m_axil_rdata            ),
    .m_axil_rresp_i                                 (   m_axil_rresp            ),
    .m_axil_rvalid_i                                (   m_axil_rvalid           ),
    .m_axil_rready_o                                (   m_axil_rready           ),
`else
    .m_axil_awready_i                               (   0                       ),
    .m_axil_wready_i                                (   0                       ),
    .m_axil_bvalid_i                                (   0                       ),
    .m_axil_bresp_i                                 (   0                       ),
    .m_axil_arready_i                               (   0                       ),
    .m_axil_rdata_i                                 (   0                       ),
    .m_axil_rresp_i                                 (   0                       ),
    .m_axil_rvalid_i                                (   0                       ),
`endif
`ifdef AXI4L_SBUS_EN
    .s_axil_awaddr_i                                (   s_axil_awaddr           ),
    .s_axil_awprot_i                                (   s_axil_awprot           ),
    .s_axil_awvalid_i                               (   s_axil_awvalid          ),
    .s_axil_awready_o                               (   s_axil_awready          ),
    .s_axil_wdata_i                                 (   s_axil_wdata            ),
    .s_axil_wstrb_i                                 (   s_axil_wstrb            ),
    .s_axil_wvalid_i                                (   s_axil_wvalid           ),
    .s_axil_wready_o                                (   s_axil_wready           ),
    .s_axil_bvalid_o                                (   s_axil_bvalid           ),
    .s_axil_bresp_o                                 (   s_axil_bresp            ),
    .s_axil_bready_i                                (   s_axil_bready           ),
    .s_axil_araddr_i                                (   s_axil_araddr           ),
    .s_axil_arprot_i                                (   s_axil_arprot           ),
    .s_axil_arvalid_i                               (   s_axil_arvalid          ),
    .s_axil_arready_o                               (   s_axil_arready          ),
    .s_axil_rdata_o                                 (   s_axil_rdata            ),
    .s_axil_rresp_o                                 (   s_axil_rresp            ),
    .s_axil_rvalid_o                                (   s_axil_rvalid           ),
    .s_axil_rready_i                                (   s_axil_rready           ),
`else
    .s_axil_awaddr_i                                (   0                       ),
    .s_axil_awprot_i                                (   0                       ),
    .s_axil_awvalid_i                               (   0                       ),
    .s_axil_wdata_i                                 (   0                       ),
    .s_axil_wstrb_i                                 (   0                       ),
    .s_axil_wvalid_i                                (   0                       ),
    .s_axil_bready_i                                (   0                       ),
    .s_axil_araddr_i                                (   0                       ),
    .s_axil_arprot_i                                (   0                       ),
    .s_axil_arvalid_i                               (   0                       ),
    .s_axil_rready_i                                (   0                       ),
`endif
`ifdef  CFG_MGMT_EN
    .cfg_mgmt_addr_i                                (   cfg_mgmt_addr           ),
    .cfg_mgmt_write_i                               (   cfg_mgmt_write          ),
    .cfg_mgmt_write_data_i                          (   cfg_mgmt_write_data     ),
    .cfg_mgmt_byte_enable_i                         (   cfg_mgmt_byte_enable    ),
    .cfg_mgmt_read_i                                (   cfg_mgmt_read           ),
    .cfg_mgmt_read_data_o                           (   cfg_mgmt_read_data      ),
    .cfg_mgmt_read_write_done_o                     (   cfg_mgmt_read_write_done),
    .cfg_mgmt_type1_cfg_reg_access_i                (   0                       ),
`else
    .cfg_mgmt_addr_i                                (   0                       ),
    //.cfg_mgmt_function_number_i                     (   0                       ),
    .cfg_mgmt_write_i                               (   0                       ),
    .cfg_mgmt_write_data_i                          (   0                       ),
    .cfg_mgmt_byte_enable_i                         (   0                       ),
    .cfg_mgmt_read_i                                (   0                       ),
    .cfg_mgmt_type1_cfg_reg_access_i                (   0                       ),
`endif

    //to bridge
    .cfg_mgmt_addr_o                                (   cfg_mgmt2core_addr      ),
    .cfg_mgmt_write_o                               (   cfg_mgmt2core_write     ),
    .cfg_mgmt_write_data_o                          (   cfg_mgmt2core_write_data),
    .cfg_mgmt_byte_enable_o                         (   cfg_mgmt2core_byte_enable),
    .cfg_mgmt_read_o                                (   cfg_mgmt2core_read      ),
    .cfg_mgmt_read_data_i                           (   cfg_mgmt2core_read_data ),
    .cfg_mgmt_read_write_done_i                     (   cfg_mgmt2core_read_write_done),
    .cfg_mgmt_type1_cfg_reg_access_o                (   cfg_mgmt2core_type1_cfg_reg_access),
    //CQ
    .m_axis_cq_tdata_i                              (   m_axis_cq_tdata         ),
    .m_axis_cq_tkeep_i                              (   m_axis_cq_tkeep         ),
    .m_axis_cq_tuser_i                              (   m_axis_cq_tuser         ),
    .m_axis_cq_tvalid_i                             (   m_axis_cq_tvalid        ),
    .m_axis_cq_tlast_i                              (   m_axis_cq_tlast         ),
    .m_axis_cq_tready_o                             (   m_axis_cq_tready        ),
    //CC
    .m_axis_cc_tdata_o                              (   s_axis_cc_tdata         ),
    .m_axis_cc_tkeep_o                              (   s_axis_cc_tkeep         ),
    .m_axis_cc_tuser_o                              (   s_axis_cc_tuser         ),
    .m_axis_cc_tvalid_o                             (   s_axis_cc_tvalid        ),
    .m_axis_cc_tlast_o                              (   s_axis_cc_tlast         ),
    .m_axis_cc_tready_i                             (   s_axis_cc_tready        ),
    //RQ
    .m_axis_rq_tdata_o                              (   s_axis_rq_tdata         ),
    .m_axis_rq_tkeep_o                              (   s_axis_rq_tkeep         ),
    .m_axis_rq_tuser_o                              (   s_axis_rq_tuser         ),
    .m_axis_rq_tvalid_o                             (   s_axis_rq_tvalid        ),
    .m_axis_rq_tlast_o                              (   s_axis_rq_tlast         ),
    .m_axis_rq_tready_i                             (   s_axis_rq_tready        ),
    .tuser2rq_i                                     (   tuser2rq                ),
    //RC
    .m_axis_rc_tdata_i                              (   m_axis_rc_tdata         ),
    .m_axis_rc_tkeep_i                              (   m_axis_rc_tkeep         ),
    .m_axis_rc_tuser_i                              (   m_axis_rc_tuser         ),
    .m_axis_rc_tvalid_i                             (   m_axis_rc_tvalid        ),
    .m_axis_rc_tlast_i                              (   m_axis_rc_tlast         ),
    .m_axis_rc_tready_o                             (   m_axis_rc_tready        ),
    //---irq interface--------------------------//
    .cfg_interrupt_int                              (   cfg_interrupt_int               ),
    .cfg_interrupt_pending                          (   cfg_interrupt_pending           ),
    .cfg_interrupt_sent                             (   cfg_interrupt_sent              ),
    .cfg_interrupt_msi_enable                       (   cfg_interrupt_msi_enable        ),
    .cfg_interrupt_msi_mmenable                     (   cfg_interrupt_msi_mmenable      ),
    .cfg_interrupt_msi_mask_update                  (   cfg_interrupt_msi_mask_update   ),
    .cfg_interrupt_msi_data                         (   cfg_interrupt_msi_data          ),
    .cfg_interrupt_msi_select                       (   cfg_interrupt_msi_select        ),
    .cfg_interrupt_msi_int                          (   cfg_interrupt_msi_int           ),
    .cfg_interrupt_msi_pending_status               (   cfg_interrupt_msi_pending_status),
    .cfg_interrupt_msi_pending_status_data_enable   (   cfg_interrupt_msi_pending_status_data_enable    ),
    .cfg_interrupt_msi_pending_status_function_num  (   cfg_interrupt_msi_pending_status_function_num   ),
    .cfg_interrupt_msi_sent                         (   cfg_interrupt_msi_sent          ),
    .cfg_interrupt_msi_fail                         (   cfg_interrupt_msi_fail          ),
    .cfg_interrupt_msi_attr                         (   cfg_interrupt_msi_attr          ),
    .cfg_interrupt_msi_tph_present                  (   cfg_interrupt_msi_tph_present   ),
    .cfg_interrupt_msi_tph_type                     (   cfg_interrupt_msi_tph_type      ),
    .cfg_interrupt_msi_tph_st_tag                   (   cfg_interrupt_msi_tph_st_tag    ),
    .cfg_interrupt_msi_function_number              (   cfg_interrupt_msi_function_number   ),
    //---cfg direct access interface---
    .tl_cfg_busdev_i                                (   tl_cfg_busdev                   ),//tl_cfg_busdev
    .tl_cfg_max_payload_size_i                      (   cfg_max_payload         ),
    .tl_cfg_max_read_request_size_i                 (   cfg_max_read_req    )
);

assign  user_rst_n  =   !user_reset;

endmodule
