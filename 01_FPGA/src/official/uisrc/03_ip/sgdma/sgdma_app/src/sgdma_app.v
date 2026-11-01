//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : sgdma_app.v
//  Author        : bswang - bingsong.wang@anlogic.com
//  Last Modified : 2025-09-29 09:30:08
//  Create        : 2024-06-27 09:34:29
//  Description   :
//
///////////////////////////////////////////////////////////////

module sgdma_app #(
    parameter DLY               = 1,
    parameter ODATA_WIDTH       = 128,
    parameter OKEEP_WIDTH       = ODATA_WIDTH/8,
    parameter H2C_CHNL_NUM      = 1,
    parameter C2H_CHNL_NUM      = 1,
    parameter H2C_DSC_BYP_MAP   = 1'b1,
    parameter C2H_DSC_BYP_MAP   = 1'b1,
    parameter DESC_BYP_EN       = 1,
    parameter USR_IRQ_NUM       = 8
)(
    input   wire            usr_clk,
    input   wire            usr_rst_n,
`ifdef DMA_BYPA_EN
    output  wire            m_axib_arready,
    input   wire    [3:0]   m_axib_arid,
    input   wire    [63:0]  m_axib_araddr,
    //specifies the number of data transfers that occur within each burst.
    input   wire    [7:0]   m_axib_arlen,
    //specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
    input   wire    [2:0]   m_axib_arsize,
    input   wire    [1:0]   m_axib_arburst,
    input   wire    [2:0]   m_axib_arprot,
    input   wire            m_axib_arvalid,
    input   wire            m_axib_arlock,
    input   wire    [3:0]   m_axib_arcache,

    output  wire    [3:0]   m_axib_rid,
    output  wire    [ODATA_WIDTH-1:0]m_axib_rdata,
    output  wire    [1:0]   m_axib_rresp,
    output  wire            m_axib_rlast,
    output  wire            m_axib_rvalid,
    input   wire            m_axib_rready,

    output  wire            m_axib_awready,
    input   wire    [3:0]   m_axib_awid,
    input   wire    [63:0]  m_axib_awaddr,
    input   wire    [7:0]   m_axib_awlen,
    input   wire    [2:0]   m_axib_awsize,
    input   wire    [1:0]   m_axib_awburst,
    input   wire    [2:0]   m_axib_awprot,
    input   wire            m_axib_awvalid,
    input   wire            m_axib_awlock,
    input   wire    [3:0]   m_axib_awcache,
    input   wire    [ODATA_WIDTH-1:0] m_axib_wdata,
    input   wire    [OKEEP_WIDTH-1:0] m_axib_wstrb,

    output  wire            m_axib_wready,
    input   wire            m_axib_wlast,
    input   wire            m_axib_wvalid,
    output  wire    [3:0]   m_axib_bid,
    output  wire    [1:0]   m_axib_bresp,
    output  wire            m_axib_bvalid,
    input   wire            m_axib_bready,
`endif
`ifdef AXI4ST_BUS_EN
    output  wire   [H2C_CHNL_NUM-1:0]   m0_axis_h2c_tready,
    input   wire   [H2C_CHNL_NUM*ODATA_WIDTH-1:0]   m0_axis_h2c_tdata,
    input   wire   [H2C_CHNL_NUM*OKEEP_WIDTH-1:0]   m0_axis_h2c_tkeep,
    input   wire   [H2C_CHNL_NUM*OKEEP_WIDTH-1:0]   m0_axis_h2c_tuser,
    input   wire   [H2C_CHNL_NUM-1:0]   m0_axis_h2c_tlast,
    input   wire   [H2C_CHNL_NUM-1:0]   m0_axis_h2c_tvalid,

    input   wire   [C2H_CHNL_NUM-1:0]   s0_axis_c2h_tready,
    output  wire   [C2H_CHNL_NUM*ODATA_WIDTH-1:0]   s0_axis_c2h_tdata,
    output  wire   [C2H_CHNL_NUM*OKEEP_WIDTH-1:0]   s0_axis_c2h_tkeep,
    output  wire   [C2H_CHNL_NUM*OKEEP_WIDTH-1:0]   s0_axis_c2h_tuser,
    output  wire   [C2H_CHNL_NUM-1:0]   s0_axis_c2h_tlast,
    output  wire   [C2H_CHNL_NUM-1:0]   s0_axis_c2h_tvalid,
`endif
`ifdef AXI4MM_BUS_EN
    output  wire            m_axi_arready,
    input   wire   [3:0]    m_axi_arid,
    input   wire   [63:0]   m_axi_araddr,
    //specifies the number of data transfers that occur within each burst.
    input   wire   [7:0]    m_axi_arlen,
    //specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
    input   wire   [2:0]    m_axi_arsize,
    input   wire   [1:0]    m_axi_arburst,
    input   wire   [2:0]    m_axi_arprot,
    input   wire            m_axi_arvalid,
    input   wire            m_axi_arlock,
    input   wire   [3:0]    m_axi_arcache,

    output  wire   [3:0]    m_axi_rid,
    output  wire   [ODATA_WIDTH-1:0]m_axi_rdata,
    output  wire   [1:0]    m_axi_rresp,
    output  wire            m_axi_rlast,
    output  wire            m_axi_rvalid,
    input   wire            m_axi_rready,

    output  wire            m_axi_awready,
    input   wire   [3:0]    m_axi_awid,
    input   wire   [63:0]   m_axi_awaddr,
    input   wire   [7:0]    m_axi_awlen,
    input   wire   [2:0]    m_axi_awsize,
    input   wire   [1:0]    m_axi_awburst,
    input   wire   [2:0]    m_axi_awprot,
    input   wire            m_axi_awvalid,
    input   wire            m_axi_awlock,
    input   wire   [3:0]    m_axi_awcache,
    input   wire   [ODATA_WIDTH-1:0] m_axi_wdata,
    input   wire   [OKEEP_WIDTH-1:0] m_axi_wstrb,
    output  wire            m_axi_wready,
    input   wire            m_axi_wlast,
    input   wire            m_axi_wvalid,
    output  wire   [3:0]    m_axi_bid,
    output  wire   [1:0]    m_axi_bresp,
    output  wire            m_axi_bvalid,
    input   wire            m_axi_bready,
`endif
//Descriptor byapss interface
`ifdef DSC_BYPASS_C2H_CHL0_EN
    input   wire            c2h_dsc_byp_ready_0_i,
    output  wire            c2h_dsc_byp_load_0_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_0_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_0_o,
    output  wire    [27:0]  c2h_dsc_byp_len_0_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_0_o,
`endif
`ifdef DSC_BYPASS_C2H_CHL1_EN
    input   wire            c2h_dsc_byp_ready_1_i,
    output  wire            c2h_dsc_byp_load_1_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_1_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_1_o,
    output  wire    [27:0]  c2h_dsc_byp_len_1_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_1_o,
`endif
`ifdef DSC_BYPASS_C2H_CHL2_EN
    input   wire            c2h_dsc_byp_ready_2_i,
    output  wire            c2h_dsc_byp_load_2_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_2_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_2_o,
    output  wire    [27:0]  c2h_dsc_byp_len_2_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_2_o,
`endif
`ifdef DSC_BYPASS_C2H_CHL3_EN
    input   wire            c2h_dsc_byp_ready_3_i,
    output  wire            c2h_dsc_byp_load_3_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_3_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_3_o,
    output  wire    [27:0]  c2h_dsc_byp_len_3_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_3_o,
`endif
`ifdef DSC_BYPASS_H2C_CHL0_EN
    input   wire            h2c_dsc_byp_ready_0_i,
    output  wire            h2c_dsc_byp_load_0_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_0_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_0_o,
    output  wire    [27:0]  h2c_dsc_byp_len_0_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_0_o,
`endif
`ifdef DSC_BYPASS_H2C_CHL1_EN
    input   wire            h2c_dsc_byp_ready_1_i,
    output  wire            h2c_dsc_byp_load_1_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_1_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_1_o,
    output  wire    [27:0]  h2c_dsc_byp_len_1_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_1_o,
`endif
`ifdef DSC_BYPASS_H2C_CHL2_EN
    input   wire            h2c_dsc_byp_ready_2_i,
    output  wire            h2c_dsc_byp_load_2_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_2_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_2_o,
    output  wire    [27:0]  h2c_dsc_byp_len_2_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_2_o,
`endif
`ifdef DSC_BYPASS_H2C_CHL3_EN
    input   wire            h2c_dsc_byp_ready_3_i,
    output  wire            h2c_dsc_byp_load_3_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_3_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_3_o,
    output  wire    [27:0]  h2c_dsc_byp_len_3_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_3_o,
`endif

`ifdef CFG_MGMT_EN
    output  wire    [18:0]  cfg_mgmt_addr,
    output  wire            cfg_mgmt_write,
    output  wire    [31:0]  cfg_mgmt_write_data,
    output  wire    [3:0]   cfg_mgmt_byte_enable,
    output  wire            cfg_mgmt_read,
    input   wire    [31:0]  cfg_mgmt_read_data,
    input   wire            cfg_mgmt_read_write_done,
    output  wire            cfg_mgmt_type1_cfg_reg_access,
`endif
`ifdef USR_IRQ_EN
    output  wire    [USR_IRQ_NUM-1:0]   usr_irq_req,
    input   wire    [USR_IRQ_NUM-1:0]   usr_irq_ack,
    input   wire            legacy_enable,
    input   wire    [2:0]   legacy_vector_width,
    input   wire            msi_enable,
    input   wire    [4:0]   msi_vector_width,
    input   wire            msix_enable,
    input   wire    [4:0]   msix_vector_width,
`endif
`ifdef AXI4L_MBUS_EN
    input   wire    [31:0]  m_axil_awaddr,
    input   wire    [2:0]   m_axil_awprot,
    input   wire            m_axil_awvalid,
    output  wire            m_axil_awready,
    input   wire    [31:0]  m_axil_wdata,
    input   wire    [3:0]   m_axil_wstrb,
    input   wire            m_axil_wvalid,
    output  wire            m_axil_wready,
    output  wire            m_axil_bvalid,
    output  wire    [1:0]   m_axil_bresp,
    input   wire            m_axil_bready,
    input   wire    [31:0]  m_axil_araddr,
    input   wire    [2:0]   m_axil_arprot,
    input   wire            m_axil_arvalid,
    output  wire            m_axil_arready,
    output  wire    [31:0]  m_axil_rdata,
    output  wire    [1:0]   m_axil_rresp,
    output  wire            m_axil_rvalid,
    input   wire            m_axil_rready,
`endif
`ifdef AXI4L_SBUS_EN
    output  wire    [31:0]  s_axil_awaddr,
    output  wire    [2 :0]  s_axil_awprot,
    output  wire            s_axil_awvalid,
    input   wire            s_axil_awready,
    output  wire    [31:0]  s_axil_wdata,
    output  wire    [3:0]   s_axil_wstrb,
    output  wire            s_axil_wvalid,
    input   wire            s_axil_wready,
    input   wire            s_axil_bvalid,
    input   wire    [1:0]   s_axil_bresp,
    output  wire            s_axil_bready,
    output  wire    [31:0]  s_axil_araddr,
    output  wire    [2:0]   s_axil_arprot,
    output  wire            s_axil_arvalid,
    input   wire            s_axil_arready,
    input   wire    [31:0]  s_axil_rdata,
    input   wire    [1:0]   s_axil_rresp,
    input   wire            s_axil_rvalid,
    output  wire            s_axil_rready,
`endif
    input   wire    [7:0]   c2h_sts_0,
    input   wire    [7:0]   h2c_sts_0,
    input   wire    [7:0]   c2h_sts_1,
    input   wire    [7:0]   h2c_sts_1,
    input   wire    [7:0]   c2h_sts_2,
    input   wire    [7:0]   h2c_sts_2,
    input   wire    [7:0]   c2h_sts_3,
    input   wire    [7:0]   h2c_sts_3
);

localparam CHNL_NUM = (C2H_CHNL_NUM < H2C_CHNL_NUM) ? C2H_CHNL_NUM : H2C_CHNL_NUM;

wire    [7:0]               h2c_sts [3:0];
wire    [7:0]               c2h_sts [3:0];
reg     [C2H_CHNL_NUM-1:0]  s0_axis_c2h_run;
reg     [H2C_CHNL_NUM-1:0]  m0_axis_h2c_run;
wire    [C2H_CHNL_NUM-1:0]  s0_axis_c2h_rst;
wire    [H2C_CHNL_NUM-1:0]  m0_axis_h2c_rst;
//---Variable definition---
wire    [31:0]              c2h0_chn_stts;
wire    [31:0]              h2c0_chn_stts;
`ifdef AXI4ST_BUS_EN
wire   [H2C_CHNL_NUM*32-1:0]usr_h2c0err_num;
`elsif AXI4MM_BUS_EN
wire   [31:0]               usr_h2c0err_num;
`endif
wire   [1:0]                usr_lp0rw_cmd;
wire                        usr_cfgrw_cmd;
wire                        usr_cfgrw_run;
wire   [1:0]                usr_dmarw_run;
wire   [H2C_CHNL_NUM-1:0]   usr_h2c0w_run;
wire   [C2H_CHNL_NUM-1:0]   usr_c2h0r_run;
wire                        usr_lp0rw_run;

`ifdef DMA_BYPA_EN

`elsif AXI4ST_BUS_EN
    wire   [H2C_CHNL_NUM-1:0] axist_h2c_tready;
    wire   [H2C_CHNL_NUM*ODATA_WIDTH-1:0] axist_h2c_tdata;
    wire   [H2C_CHNL_NUM*OKEEP_WIDTH-1:0] axist_h2c_tkeep;
    wire   [H2C_CHNL_NUM*OKEEP_WIDTH-1:0] axist_h2c_tuser;
    wire   [H2C_CHNL_NUM-1:0] axist_h2c_tlast;
    wire   [H2C_CHNL_NUM-1:0] axist_h2c_tvalid;

    wire   [C2H_CHNL_NUM-1:0] axist_c2h_tready;
    wire   [C2H_CHNL_NUM*ODATA_WIDTH-1:0] axist_c2h_tdata;
    wire   [C2H_CHNL_NUM*OKEEP_WIDTH-1:0] axist_c2h_tkeep;
    wire   [C2H_CHNL_NUM*OKEEP_WIDTH-1:0] axist_c2h_tuser;
    wire   [C2H_CHNL_NUM-1:0] axist_c2h_tlast;
    wire   [C2H_CHNL_NUM-1:0] axist_c2h_tvalid;

    wire [CHNL_NUM-1:0] m0_axis_lp_tready;
    wire [CHNL_NUM*ODATA_WIDTH-1:0] m0_axis_lp_tdata;
    wire [CHNL_NUM*OKEEP_WIDTH-1:0] m0_axis_lp_tkeep;
    wire [CHNL_NUM*OKEEP_WIDTH-1:0] m0_axis_lp_tuser;
    wire [CHNL_NUM-1:0] m0_axis_lp_tlast;
    wire [CHNL_NUM-1:0] m0_axis_lp_tvalid;

    wire [CHNL_NUM*ODATA_WIDTH-1:0] s0_axis_lp_tdata;
    wire [CHNL_NUM*OKEEP_WIDTH-1:0] s0_axis_lp_tkeep;
    wire [CHNL_NUM*OKEEP_WIDTH-1:0] s0_axis_lp_tuser;
    wire [CHNL_NUM-1:0] s0_axis_lp_tlast;
    wire [CHNL_NUM-1:0] s0_axis_lp_tvalid;
    wire [CHNL_NUM-1:0] s0_axis_lp_tready;
`elsif AXI4MM_BUS_EN
    wire   usr_h2c0_wren;
    wire   [15:0]  usr_h2c0_wraddr;
    wire   [ODATA_WIDTH-1:0] usr_h2c0_dt;
    wire   [OKEEP_WIDTH-1:0] usr_h2c0_wstrb;
    wire   usr_c2h0_rden;
    wire   [15:0]  usr_c2h0_rdaddr;
    wire   [ODATA_WIDTH-1:0] usr_c2h0_dt;
`endif

wire                irq_set      ;
wire                irq_clr      ;
wire   [3:0]        irq_num_lo   ;
wire   [3:0]        irq_num_hi   ;
wire   [31:0]       usr_irq_evt  ;
wire   [31:0]       usr_irq_req_set;
wire                c2h_h2c_start;
wire                c2h_h2c_mode ;
wire    [7:0]       axil_wshake  ;
wire    [7:0]       axil_rshake  ;
wire    [31:0]      axil_wdata   ;
wire    [31:0]      axil_waddr   ;
wire    [31:0]      axil_raddr   ;
wire    [32*8-1:0]  axil_rdata   ;

assign h2c_sts[0] = h2c_sts_0;
assign h2c_sts[1] = h2c_sts_1;
assign h2c_sts[2] = h2c_sts_2;
assign h2c_sts[3] = h2c_sts_3;
assign c2h_sts[0] = c2h_sts_0;
assign c2h_sts[1] = c2h_sts_1;
assign c2h_sts[2] = c2h_sts_2;
assign c2h_sts[3] = c2h_sts_3;
integer i0;
always @(*) begin
    for (i0=0;i0<4;i0=i0+1) begin
        if (i0<H2C_CHNL_NUM) begin
            m0_axis_h2c_run[i0] = h2c_sts[i0][6];
        end
        if (i0<C2H_CHNL_NUM) begin
            s0_axis_c2h_run[i0] = c2h_sts[i0][6];
        end
    end
end
assign s0_axis_c2h_rst = ~s0_axis_c2h_run;
assign m0_axis_h2c_rst = ~m0_axis_h2c_run;

axil_anal u_axil_anal(
    .core_rst_n             (usr_rst_n          ),
    .core_clk               (usr_clk            ),

    .m_axil_awaddr_i        (m_axil_awaddr      ),
    .m_axil_awprot_i        (m_axil_awprot      ),
    .m_axil_awvalid_i       (m_axil_awvalid     ),
    .m_axil_awready_o       (m_axil_awready     ),
    .m_axil_wdata_i         (m_axil_wdata       ),
    .m_axil_wstrb_i         (m_axil_wstrb       ),
    .m_axil_wvalid_i        (m_axil_wvalid      ),
    .m_axil_wready_o        (m_axil_wready      ),
    .m_axil_bvalid_o        (m_axil_bvalid      ),
    .m_axil_bresp_o         (m_axil_bresp       ),
    .m_axil_bready_i        (m_axil_bready      ),
    .m_axil_araddr_i        (m_axil_araddr      ),
    .m_axil_arprot_i        (m_axil_arprot      ),
    .m_axil_arvalid_i       (m_axil_arvalid     ),
    .m_axil_arready_o       (m_axil_arready     ),
    .m_axil_rdata_o         (m_axil_rdata       ),
    .m_axil_rresp_o         (m_axil_rresp       ),
    .m_axil_rvalid_o        (m_axil_rvalid      ),
    .m_axil_rready_i        (m_axil_rready      ),

    .usr_irq_req_o          (usr_irq_req_set    ),
    .usr_irq_evt_i          (usr_irq_evt        ),

    .usr_lp0rw_cmd_o        (usr_lp0rw_cmd      ),
    .usr_cfgrw_cmd_o        (usr_cfgrw_cmd      ),
    .c2h_h2c_start_o        (c2h_h2c_start      ),
    .c2h_h2c_mode_o         (c2h_h2c_mode       ),

    .axil_wshake_o          (axil_wshake        ),
    .axil_rshake_o          (axil_rshake        ),
    .axil_wdata_o           (axil_wdata         ),
    .axil_waddr_o           (axil_waddr         ),
    .axil_raddr_o           (axil_raddr         ),
    .axil_rdata_i           (axil_rdata         )
);

usr_ctrl #(
    .H2C_CHNL_NUM           (H2C_CHNL_NUM       ),
    .C2H_CHNL_NUM           (C2H_CHNL_NUM       ),
    .DLY                    (DLY                )
    ) u_usr_ctrl(
    .usr_rst_n              (usr_rst_n          ),
    .usr_clk                (usr_clk            ),

    .usr_lp0rw_cmd_i        (usr_lp0rw_cmd      ),
    .usr_cfgrw_cmd_i        (usr_cfgrw_cmd      ),
    .m0_axis_h2c_run_i      (m0_axis_h2c_run    ),
    .s0_axis_c2h_run_i      (s0_axis_c2h_run    ),

    .usr_cfgrw_run_o        (usr_cfgrw_run      ),
    .usr_dmarw_run_o        (usr_dmarw_run      ),
    .usr_h2c0w_run_o        (usr_h2c0w_run      ),
    .usr_c2h0r_run_o        (usr_c2h0r_run      ),
    .usr_lp0rw_run_o        (usr_lp0rw_run      )
);
/*Instantiate the usr_cfgrw.v to copmplete the
read and write test of configuration space;*/
usr_cfgrw #(
    .DLY                    (DLY                )
    ) u_usr_cfgrw(
    .usr_clk                (usr_clk            ),
    .usr_rst_n              (usr_rst_n          ),

    .cfg_mgmt_addr_o        (cfg_mgmt_addr      ),
    .cfg_mgmt_write_o       (cfg_mgmt_write     ),
    .cfg_mgmt_write_data_o  (cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable_o (cfg_mgmt_byte_enable),
    .cfg_mgmt_read_o        (cfg_mgmt_read      ),
    .cfg_mgmt_read_data_i   (cfg_mgmt_read_data ),
    .cfg_mgmt_read_write_done_i(cfg_mgmt_read_write_done),
    .cfg_mgmt_type1_cfg_reg_access_o(cfg_mgmt_type1_cfg_reg_access),

    .usr_cfgrw_run_i        (usr_cfgrw_run      ),
    .pcie_cfg_tst_o         ()
);

`ifdef DMA_BYPA_EN
s_usr_datarw u_usr_datarw(
    .usr_clk                (usr_clk    ),
    .usr_rst_n              (usr_rst_n  ),
    .m_axib_awid            (m_axib_awid),
    .m_axib_awaddr          (m_axib_awaddr),
    .m_axib_awlen           (m_axib_awlen),
    .m_axib_awsize          (m_axib_awsize),
    .m_axib_awburst         (m_axib_awburst),
    .m_axib_awlock          (m_axib_awlock),
    .m_axib_awvalid         (m_axib_awvalid),
    .m_axib_awready         (m_axib_awready),
    .m_axib_wdata           (m_axib_wdata),
    .m_axib_wstrb           (m_axib_wstrb),
    .m_axib_wvalid          (m_axib_wvalid),
    .m_axib_wready          (m_axib_wready),
    .m_axib_bid             (m_axib_bid),
    .m_axib_bresp           (m_axib_bresp),
    .m_axib_bvalid          (m_axib_bvalid),
    .m_axib_bready          (m_axib_bready),
    .m_axib_arid            (m_axib_arid),
    .m_axib_arprot          (m_axib_arprot),
    .m_axib_araddr          (m_axib_araddr),
    .m_axib_arlen           (m_axib_arlen),
    .m_axib_arsize          (m_axib_arsize),
    .m_axib_arburst         (m_axib_arburst),
    .m_axib_arlock          (m_axib_arlock),
    .m_axib_arvalid         (m_axib_arvalid),
    .m_axib_arready         (m_axib_arready),
    .m_axib_rid             (m_axib_rid),
    .m_axib_rdata           (m_axib_rdata),
    .m_axib_rresp           (m_axib_rresp),
    .m_axib_rlast           (m_axib_rlast),
    .m_axib_rvalid          (m_axib_rvalid),
    .m_axib_rready          (m_axib_rready)
    );
`endif
`ifdef AXI4ST_BUS_EN
    parameter   LOOPBACK_INFO_W = ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1;
    wire    [H2C_CHNL_NUM-1:0]  fifo_rdy;
    wire    [H2C_CHNL_NUM-1:0]  fifo_we;
    wire    [H2C_CHNL_NUM*LOOPBACK_INFO_W-1:0]  fifo_di;

    wire    [C2H_CHNL_NUM-1:0]  fifo_valid;
    wire    [C2H_CHNL_NUM-1:0]  fifo_re;
    wire    [C2H_CHNL_NUM*LOOPBACK_INFO_W-1:0]  fifo_dout;

    genvar k;
    for (k=0;k<H2C_CHNL_NUM;k=k+1) begin: st_h2c
        usr_axi4st_h2c #(
            .DLY                    (DLY            ),
            .ODATA_WIDTH            (ODATA_WIDTH    )
        ) u_usr_axi4st_h2c(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),
            .usr_lp0rw_run_i        (usr_lp0rw_run),

            .m0_axis_h2c_tready_o   (m0_axis_h2c_tready[k]),
            .m0_axis_h2c_tdata_i    (m0_axis_h2c_tdata[k*ODATA_WIDTH+:ODATA_WIDTH]),
            .m0_axis_h2c_tkeep_i    (m0_axis_h2c_tkeep[k*OKEEP_WIDTH+:OKEEP_WIDTH]),
            .m0_axis_h2c_tuser_i    (m0_axis_h2c_tuser[k*OKEEP_WIDTH+:OKEEP_WIDTH]),
            .m0_axis_h2c_tlast_i    (m0_axis_h2c_tlast[k]),
            .m0_axis_h2c_tvalid_i   (m0_axis_h2c_tvalid[k]),
            //to loopback FIFO
            .fifo_rdy_i             (fifo_rdy[k]),
            .fifo_we_o              (fifo_we[k]),
            .fifo_di_o              (fifo_di[k*LOOPBACK_INFO_W+:LOOPBACK_INFO_W]),
            .usr_h2c0err_num_o      (usr_h2c0err_num[k*32+:32])
        );
    end
    for (k=0;k<C2H_CHNL_NUM;k=k+1) begin: st_c2h
        usr_axi4st_c2h #(
            .DLY                    (DLY            ),
            .ODATA_WIDTH            (ODATA_WIDTH    )
        ) u_usr_axi4st_c2h(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),
            .usr_lp0rw_run_i        (usr_lp0rw_run),

            .s0_axis_c2h_tready_i   (s0_axis_c2h_tready[k]),
            .s0_axis_c2h_tdata_o    (s0_axis_c2h_tdata[k*ODATA_WIDTH+:ODATA_WIDTH]),
            .s0_axis_c2h_tkeep_o    (s0_axis_c2h_tkeep[k*OKEEP_WIDTH+:OKEEP_WIDTH]),
            .s0_axis_c2h_tuser_o    (s0_axis_c2h_tuser[k*OKEEP_WIDTH+:OKEEP_WIDTH]),
            .s0_axis_c2h_tlast_o    (s0_axis_c2h_tlast[k]),
            .s0_axis_c2h_tvalid_o   (s0_axis_c2h_tvalid[k]),

            .fifo_valid_i           (fifo_valid[k]),
            .fifo_re_o              (fifo_re[k]),
            .fifo_dout_i            (fifo_dout[k*LOOPBACK_INFO_W+:LOOPBACK_INFO_W]),
            .usr_c2h0err_o          ()//usr_c2h0err
        );
    end
    for (k=0;k<C2H_CHNL_NUM;k=k+1) begin
		if(k<CHNL_NUM) begin
        usr_axi4st_lp #(
            .DLY                    (DLY            ),
            .ODATA_WIDTH            (ODATA_WIDTH    )
        ) u_usr_axi4st_lp(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),

            .fifo_rdy_o             (fifo_rdy[k]    ),
            .fifo_we_i              (fifo_we[k]     ),
            .fifo_di_i              (fifo_di[k*LOOPBACK_INFO_W+:LOOPBACK_INFO_W]    ),

            .fifo_valid_o           (fifo_valid[k]  ),
            .fifo_re_i              (fifo_re[k]     ),
            .fifo_dout_o            (fifo_dout[k*LOOPBACK_INFO_W+:LOOPBACK_INFO_W]  )
        );
        end else begin
            assign fifo_valid[k] = 0;
            assign fifo_dout[k*LOOPBACK_INFO_W+:LOOPBACK_INFO_W] = 0;
        end
    end
`endif
`ifdef AXI4MM_BUS_EN
        usr_axi4mmw #(
            .DLY                    (DLY),
            .ODATA_WIDTH            (ODATA_WIDTH),
            .H2C_CHNL_NUM           (H2C_CHNL_NUM)
            ) u_usr_axi4mmw(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),

            .usr_lp0rw_run_i        (usr_lp0rw_run),
            .usr_h2c0w_run_i        (1'b1 ),
            .m0_axis_h2c_rst_i      (1'b0 ),

            .m_axi_awready_o        (m_axi_awready),
            .m_axi_awid_i           (m_axi_awid),
            .m_axi_awaddr_i         (m_axi_awaddr),
            .m_axi_awlen_i          (m_axi_awlen),
            .m_axi_awsize_i         (m_axi_awsize),
            .m_axi_awburst_i        (m_axi_awburst),
            .m_axi_awprot_i         (m_axi_awprot),
            .m_axi_awvalid_i        (m_axi_awvalid),
            .m_axi_awlock_i         (m_axi_awlock),
            .m_axi_awcache_i        (m_axi_awcache),
            .m_axi_wdata_i          (m_axi_wdata),
            .m_axi_wstrb_i          (m_axi_wstrb),
            .m_axi_wready_o         (m_axi_wready),
            .m_axi_wlast_i          (m_axi_wlast),
            .m_axi_wvalid_i         (m_axi_wvalid),
            .m_axi_bid_o            (m_axi_bid),
            .m_axi_bresp_o          (m_axi_bresp),
            .m_axi_bvalid_o         (m_axi_bvalid),
            .m_axi_bready_i         (m_axi_bready),

//            .usr_ram_pntr_i         (usr_ram_pntr),
            .usr_h2c0_wren_o        (usr_h2c0_wren),//+
            .usr_h2c0_wstrb_o       (usr_h2c0_wstrb),
            .usr_h2c0_wraddr_o      (usr_h2c0_wraddr),//+
            .usr_h2c0_dt_o          (usr_h2c0_dt),//+
            .usr_h2c0err_num_o      (usr_h2c0err_num)
        );

        usr_axi4mmr #(
            .DLY                    (DLY),
            .ODATA_WIDTH            (ODATA_WIDTH),
            .C2H_CHNL_NUM           (C2H_CHNL_NUM)
            ) u_usr_axi4mmr(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),
            .usr_c2h0r_run_i        (1'b1 ),
            .usr_lp0rw_run_i        (usr_lp0rw_run),
            .s0_axis_c2h_rst_i      (1'b0 ),

            .m_axi_arready_o        (m_axi_arready),
            .m_axi_arid_i           (m_axi_arid),
            .m_axi_araddr_i         (m_axi_araddr),
            //specifies the number of data transfers that occur within each burst.
            .m_axi_arlen_i          (m_axi_arlen),
            //specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
            .m_axi_arsize_i         (m_axi_arsize),
            .m_axi_arburst_i        (m_axi_arburst),
            .m_axi_arprot_i         (m_axi_arprot),
            .m_axi_arvalid_i        (m_axi_arvalid),
            .m_axi_arlock_i         (m_axi_arlock),
            .m_axi_arcache_i        (m_axi_arcache),

            .m_axi_rid_o            (m_axi_rid),
            .m_axi_rdata_o          (m_axi_rdata),
            .m_axi_rresp_o          (m_axi_rresp),
            .m_axi_rlast_o          (m_axi_rlast),
            .m_axi_rvalid_o         (m_axi_rvalid),
            .m_axi_rready_i         (m_axi_rready),

            // .usr_ram_pntr_i         (usr_ram_pntr),
            .usr_c2h0_rden_o        (usr_c2h0_rden),//+
            .usr_c2h0_rdaddr_o      (usr_c2h0_rdaddr),//+
            .usr_c2h0_dt_i          (usr_c2h0_dt),//+
            .usr_c2h0err_o          ()//usr_c2h0err
        );

        usr_axi4mmlp #(
            .DLY                    (DLY),
            .ODATA_WIDTH            (ODATA_WIDTH)
            )
        u_usr_axi4mmlp(
            .usr_rst_n              (usr_rst_n),
            .usr_clk                (usr_clk),
            .s0_axis_c2h_rst_i      (1'b0),
            .m0_axis_h2c_rst_i      (1'b0),

            // .usr_ram_pntr_o         (usr_ram_pntr),
            .usr_h2c0_wren_i        (usr_h2c0_wren),
            .usr_h2c0_wstrb_i       (usr_h2c0_wstrb),
            .usr_h2c0_wraddr_i      (usr_h2c0_wraddr),
            .usr_h2c0_dt_i          (usr_h2c0_dt),

            .usr_c2h0_rden_i        (usr_c2h0_rden),
            .usr_c2h0_rdaddr_i      (usr_c2h0_rdaddr),
            .usr_c2h0_dt_o          (usr_c2h0_dt)
        );
`endif

generate if (DESC_BYP_EN==1) begin : DSCP_BYPASS_SRC
desc_anal #(
    .H2C_CHNL_NUM                   (  H2C_CHNL_NUM     ),
    .H2C_DSC_BYP_MAP                (  H2C_DSC_BYP_MAP  ),
    .C2H_CHNL_NUM                   (  C2H_CHNL_NUM     ),
    .C2H_DSC_BYP_MAP                (  C2H_DSC_BYP_MAP  )
) u_desc_anal(
    .core_rst_n                     (usr_rst_n          ),
    .core_clk                       (usr_clk            ),
    //register config
    .c2h_h2c_start_i                (c2h_h2c_start      ),
    .c2h_h2c_mode_i                 (c2h_h2c_mode       ),
    .axil_wshake_i                  (axil_wshake        ),
    .axil_rshake_i                  (axil_rshake        ),
    .axil_wdata_i                   (axil_wdata         ),
    .axil_waddr_i                   (axil_waddr         ),
    .axil_raddr_i                   (axil_raddr         ),
    .axil_rdata_o                   (axil_rdata         ),
    //descriptor output
    .c2h_dsc_byp_ready_0_i          (c2h_dsc_byp_ready_0_i),
    .c2h_dsc_byp_load_0_o           (c2h_dsc_byp_load_0_o),
    .c2h_dsc_byp_src_addr_0_o       (c2h_dsc_byp_src_addr_0_o),
    .c2h_dsc_byp_dst_addr_0_o       (c2h_dsc_byp_dst_addr_0_o),
    .c2h_dsc_byp_len_0_o            (c2h_dsc_byp_len_0_o),
    .c2h_dsc_byp_ctl_0_o            (c2h_dsc_byp_ctl_0_o),

    .c2h_dsc_byp_ready_1_i          (c2h_dsc_byp_ready_1_i),
    .c2h_dsc_byp_load_1_o           (c2h_dsc_byp_load_1_o),
    .c2h_dsc_byp_src_addr_1_o       (c2h_dsc_byp_src_addr_1_o),
    .c2h_dsc_byp_dst_addr_1_o       (c2h_dsc_byp_dst_addr_1_o),
    .c2h_dsc_byp_len_1_o            (c2h_dsc_byp_len_1_o),
    .c2h_dsc_byp_ctl_1_o            (c2h_dsc_byp_ctl_1_o),

    .c2h_dsc_byp_ready_2_i          (c2h_dsc_byp_ready_2_i),
    .c2h_dsc_byp_load_2_o           (c2h_dsc_byp_load_2_o),
    .c2h_dsc_byp_src_addr_2_o       (c2h_dsc_byp_src_addr_2_o),
    .c2h_dsc_byp_dst_addr_2_o       (c2h_dsc_byp_dst_addr_2_o),
    .c2h_dsc_byp_len_2_o            (c2h_dsc_byp_len_2_o),
    .c2h_dsc_byp_ctl_2_o            (c2h_dsc_byp_ctl_2_o),

    .c2h_dsc_byp_ready_3_i          (c2h_dsc_byp_ready_3_i),
    .c2h_dsc_byp_load_3_o           (c2h_dsc_byp_load_3_o),
    .c2h_dsc_byp_src_addr_3_o       (c2h_dsc_byp_src_addr_3_o),
    .c2h_dsc_byp_dst_addr_3_o       (c2h_dsc_byp_dst_addr_3_o),
    .c2h_dsc_byp_len_3_o            (c2h_dsc_byp_len_3_o),
    .c2h_dsc_byp_ctl_3_o            (c2h_dsc_byp_ctl_3_o),

    .h2c_dsc_byp_ready_0_i          (h2c_dsc_byp_ready_0_i),
    .h2c_dsc_byp_load_0_o           (h2c_dsc_byp_load_0_o),
    .h2c_dsc_byp_src_addr_0_o       (h2c_dsc_byp_src_addr_0_o),
    .h2c_dsc_byp_dst_addr_0_o       (h2c_dsc_byp_dst_addr_0_o),
    .h2c_dsc_byp_len_0_o            (h2c_dsc_byp_len_0_o),
    .h2c_dsc_byp_ctl_0_o            (h2c_dsc_byp_ctl_0_o),

    .h2c_dsc_byp_ready_1_i          (h2c_dsc_byp_ready_1_i),
    .h2c_dsc_byp_load_1_o           (h2c_dsc_byp_load_1_o),
    .h2c_dsc_byp_src_addr_1_o       (h2c_dsc_byp_src_addr_1_o),
    .h2c_dsc_byp_dst_addr_1_o       (h2c_dsc_byp_dst_addr_1_o),
    .h2c_dsc_byp_len_1_o            (h2c_dsc_byp_len_1_o),
    .h2c_dsc_byp_ctl_1_o            (h2c_dsc_byp_ctl_1_o),

    .h2c_dsc_byp_ready_2_i          (h2c_dsc_byp_ready_2_i),
    .h2c_dsc_byp_load_2_o           (h2c_dsc_byp_load_2_o),
    .h2c_dsc_byp_src_addr_2_o       (h2c_dsc_byp_src_addr_2_o),
    .h2c_dsc_byp_dst_addr_2_o       (h2c_dsc_byp_dst_addr_2_o),
    .h2c_dsc_byp_len_2_o            (h2c_dsc_byp_len_2_o),
    .h2c_dsc_byp_ctl_2_o            (h2c_dsc_byp_ctl_2_o),

    .h2c_dsc_byp_ready_3_i          (h2c_dsc_byp_ready_3_i),
    .h2c_dsc_byp_load_3_o           (h2c_dsc_byp_load_3_o),
    .h2c_dsc_byp_src_addr_3_o       (h2c_dsc_byp_src_addr_3_o),
    .h2c_dsc_byp_dst_addr_3_o       (h2c_dsc_byp_dst_addr_3_o),
    .h2c_dsc_byp_len_3_o            (h2c_dsc_byp_len_3_o),
    .h2c_dsc_byp_ctl_3_o            (h2c_dsc_byp_ctl_3_o)
);
end
endgenerate

usr_dmarw u_usr_dmarw(
    .usr_rst_n                      (usr_rst_n),
    .usr_clk                        (usr_clk),
    .usr_dmarw_run_i                (2'b0),

    .s_axil_awaddr_o                (s_axil_awaddr),
    .s_axil_awprot_o                (s_axil_awprot),
    .s_axil_awvalid_o               (s_axil_awvalid),
    .s_axil_awready_i               (s_axil_awready),
    .s_axil_wdata_o                 (s_axil_wdata),
    .s_axil_wstrb_o                 (s_axil_wstrb),
    .s_axil_wvalid_o                (s_axil_wvalid),
    .s_axil_wready_i                (s_axil_wready),
    .s_axil_bvalid_i                (s_axil_bvalid),
    .s_axil_bresp_i                 (s_axil_bresp),
    .s_axil_bready_o                (s_axil_bready),
    .s_axil_araddr_o                (s_axil_araddr),
    .s_axil_arprot_o                (s_axil_arprot),
    .s_axil_arvalid_o               (s_axil_arvalid),
    .s_axil_arready_i               (s_axil_arready),
    .s_axil_rdata_i                 (s_axil_rdata),
    .s_axil_rresp_i                 (s_axil_rresp),
    .s_axil_rvalid_i                (s_axil_rvalid),
    .s_axil_rready_o                (s_axil_rready),

    .c2h0_chn_stts_o                (),
    .h2c0_chn_stts_o                ()
);

usr_irq #(
    .USR_INT_NUM                    (USR_IRQ_NUM    ),
    .MSIX_EN                        (0),
    .MSI_EN                         (1)
) usr_irq (
    .user_clk                       (usr_clk),
    .user_rstn                      (usr_rst_n),

    .usr_irq_req_i                  (usr_irq_req_set),
    .usr_irq_evt_o                  (usr_irq_evt),
    .usr_irq_req_o                  (usr_irq_req),
    .usr_irq_ack_i                  (usr_irq_ack)
);



endmodule
