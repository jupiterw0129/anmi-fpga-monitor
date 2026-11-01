// Candidate976: JPEG-only fixed1080p/Q50; compact burst crossing; physical60fps unverified.
/*===========================================*\
Filename        : imx415_pcie_top.v
Project name    : Phase 11 锟斤拷 IMX415 1080p60fps Camera via PCIe (AXI4-Stream)
Description     : Top module for PH1A90SEG324-2.
                  Camera-only design, no TPG.
                  Supports runtime resolution switching via REG_CAM_MODE:
                    0=1080p target60, 1=4K target30, 2=720p target60; board verification pending.
注锟解，pcie gen2 x1 锟斤拷支锟斤拷4k30锟斤拷默锟斤拷使锟斤拷1080p@60
\*===========================================*/
`timescale 1ns/1ps



module imx415_pcie_top #(
    parameter LINK_WIDTH    = 1,
    parameter DEVICE_FAMILY = "PH1A",
    parameter USER_CLK_FREQ = 125,
    parameter DATA_WIDTH    = 128,
    parameter KEEP_WIDTH    = DATA_WIDTH/8,
    parameter H2C_CHNL_NUM  = 1,
    parameter C2H_CHNL_NUM  = 1,
    parameter USR_IRQ_NUM   = 16,
    parameter MIPI_LAN      = 4
)(
    // 锟斤拷锟斤拷 System 锟斤拷锟斤拷
    input   wire                    sys_clk,        // 25 MHz

    // 锟斤拷锟斤拷 PCIe 锟斤拷锟斤拷
    input   wire                    refclk_p,
    input   wire                    refclk_n,
    output  wire   [LINK_WIDTH-1:0] txp,
    output  wire   [LINK_WIDTH-1:0] txn,
    input   wire   [LINK_WIDTH-1:0] rxp,
    input   wire   [LINK_WIDTH-1:0] rxn,
    input   wire                    pcie_mperst,

    // 锟斤拷锟斤拷 MIPI Reference Clock (100MHz LVDS differential, T13/T14) 锟斤拷锟斤拷
    input   wire                    mipi_ref_clk_p,         // 100MHz LVDS P (T13)

    // 锟斤拷锟斤拷 IMX415 MIPI CSI-2 锟斤拷锟斤拷
    input   wire                    mipi_clk_hs_rx_p,       // MIPI clock lane (P)
    input   wire   [MIPI_LAN-1:0]  mipi_data_hs_p,         // MIPI data lanes (P)

    // 锟斤拷锟斤拷 IMX415 I2C 锟斤拷锟斤拷
    output  wire                    cam_scl,
    inout   wire                    cam_sda,

    // 锟斤拷锟斤拷 IMX415 MCLK 锟斤拷锟斤拷
    output  wire                    cam_mclk,               

    // 锟斤拷锟斤拷 IMX415 XCLR (hardware reset, active-low on sensor) 锟斤拷锟斤拷
    output  wire                    cam_xclr,               

    // 锟斤拷锟斤拷 Debug UART 锟斤拷锟斤拷
    output  wire                    uart_tx,                // 115200 8N1 debug output (U11)
    input   wire                    uart_rx                 // 115200 8N1 debug input  (V11)
);

// ====================================================================
// Compile-time feature enable (same as Phase 8)
// ====================================================================
`ifdef  MSI_EN
localparam IRQ_LGCY_EN = 0; localparam IRQ_MSI_EN = 1; localparam IRQ_MSIX_EN = 0;
`elsif   MSIX_EN
localparam IRQ_LGCY_EN = 0; localparam IRQ_MSI_EN = 0; localparam IRQ_MSIX_EN = 1;
`else
localparam IRQ_LGCY_EN = 1; localparam IRQ_MSI_EN = 0; localparam IRQ_MSIX_EN = 0;
`endif
`ifdef  AXI4MM_BUS_EN          localparam AXI4MM_BUS_EN    = 1; `else localparam AXI4MM_BUS_EN    = 0; `endif
`ifdef  AXI4ST_BUS_EN          localparam AXI4ST_BUS_EN    = 1; `else localparam AXI4ST_BUS_EN    = 0; `endif
`ifdef  DSC_BYPASS_C2H_CHL0_EN localparam DSC_BYPASS_C2H0  = 1; `else localparam DSC_BYPASS_C2H0  = 0; `endif
`ifdef  DSC_BYPASS_C2H_CHL1_EN localparam DSC_BYPASS_C2H1  = 2; `else localparam DSC_BYPASS_C2H1  = 0; `endif
`ifdef  DSC_BYPASS_C2H_CHL2_EN localparam DSC_BYPASS_C2H2  = 4; `else localparam DSC_BYPASS_C2H2  = 0; `endif
`ifdef  DSC_BYPASS_C2H_CHL3_EN localparam DSC_BYPASS_C2H3  = 8; `else localparam DSC_BYPASS_C2H3  = 0; `endif
`ifdef  DSC_BYPASS_H2C_CHL0_EN localparam DSC_BYPASS_H2C0  = 1; `else localparam DSC_BYPASS_H2C0  = 0; `endif
`ifdef  DSC_BYPASS_H2C_CHL1_EN localparam DSC_BYPASS_H2C1  = 2; `else localparam DSC_BYPASS_H2C1  = 0; `endif
`ifdef  DSC_BYPASS_H2C_CHL2_EN localparam DSC_BYPASS_H2C2  = 4; `else localparam DSC_BYPASS_H2C2  = 0; `endif
`ifdef  DSC_BYPASS_H2C_CHL3_EN localparam DSC_BYPASS_H2C3  = 8; `else localparam DSC_BYPASS_H2C3  = 0; `endif
localparam [3:0]    H2C_DSC_BYP_MAP = DSC_BYPASS_H2C0 | DSC_BYPASS_H2C1 | DSC_BYPASS_H2C2 | DSC_BYPASS_H2C3;
localparam [3:0]    C2H_DSC_BYP_MAP = DSC_BYPASS_C2H0 | DSC_BYPASS_C2H1 | DSC_BYPASS_C2H2 | DSC_BYPASS_C2H3;
localparam          DESC_BYP_EN     = (C2H_DSC_BYP_MAP || H2C_DSC_BYP_MAP) ? 1'b1 : 1'b0;

// ====================================================================
// Internal wires
// ====================================================================

`ifdef AXI4ST_BUS_EN
    wire    [C2H_CHNL_NUM-1:0]             s0_axis_c2h_tready;
    wire    [DATA_WIDTH*C2H_CHNL_NUM-1:0]  s0_axis_c2h_tdata;
    wire    [KEEP_WIDTH*C2H_CHNL_NUM-1:0]  s0_axis_c2h_tkeep;
    wire    [KEEP_WIDTH*C2H_CHNL_NUM-1:0]  s0_axis_c2h_tuser;
    wire    [C2H_CHNL_NUM-1:0]             s0_axis_c2h_tlast;
    wire    [C2H_CHNL_NUM-1:0]             s0_axis_c2h_tvalid;

    wire    [H2C_CHNL_NUM-1:0]             m0_axis_h2c_tready;
    wire    [DATA_WIDTH*H2C_CHNL_NUM-1:0]  m0_axis_h2c_tdata;
    wire    [KEEP_WIDTH*H2C_CHNL_NUM-1:0]  m0_axis_h2c_tkeep;
    wire    [KEEP_WIDTH*H2C_CHNL_NUM-1:0]  m0_axis_h2c_tuser;
    wire    [H2C_CHNL_NUM-1:0]             m0_axis_h2c_tlast;
    wire    [H2C_CHNL_NUM-1:0]             m0_axis_h2c_tvalid;

    wire    [C2H_CHNL_NUM-1:0]             app_c2h_tready;
    wire    [DATA_WIDTH*C2H_CHNL_NUM-1:0]  app_c2h_tdata;
    wire    [KEEP_WIDTH*C2H_CHNL_NUM-1:0]  app_c2h_tkeep;
    wire    [KEEP_WIDTH*C2H_CHNL_NUM-1:0]  app_c2h_tuser;
    wire    [C2H_CHNL_NUM-1:0]             app_c2h_tlast;
    wire    [C2H_CHNL_NUM-1:0]             app_c2h_tvalid;

    // Camera output (128-bit AXI-Stream)
    wire    [DATA_WIDTH-1:0]                cam_tdata;
    wire                                    cam_tvalid;
    wire                                    cam_tready;
    wire                                    cam_tlast;
    wire                                    cam_frame_last;
    wire                                    cam_sof;
    wire                                    cam_eof;
`endif

`ifdef AXI4L_MBUS_EN
    wire    [31:0]                          m_axil_awaddr;
    wire    [2:0]                           m_axil_awprot;
    wire                                    m_axil_awvalid;
    wire                                    m_axil_awready;
    wire    [31:0]                          m_axil_wdata;
    wire    [3:0]                           m_axil_wstrb;
    wire                                    m_axil_wvalid;
    wire                                    m_axil_wready;
    wire                                    m_axil_bvalid;
    wire    [1:0]                           m_axil_bresp;
    wire                                    m_axil_bready;
    wire    [31:0]                          m_axil_araddr;
    wire    [2:0]                           m_axil_arprot;
    wire                                    m_axil_arvalid;
    wire                                    m_axil_arready;
    wire    [31:0]                          m_axil_rdata;
    wire    [1:0]                           m_axil_rresp;
    wire                                    m_axil_rvalid;
    wire                                    m_axil_rready;
    wire    [31:0]                          app_axil_rdata;
`ifndef AXI4ST_BUS_EN
    assign m_axil_rdata = app_axil_rdata;
`endif
`endif

`ifdef USR_IRQ_EN
    wire    [USR_IRQ_NUM-1:0]               usr_irq_req;
    wire    [USR_IRQ_NUM-1:0]               usr_irq_ack;
    wire                                    msi_enable;
    wire    [4:0]                           msi_vector_width;
`endif

`ifdef DSC_BYPASS_C2H_CHL0_EN
    wire c2h_dsc_byp_ready_0, c2h_dsc_byp_load_0;
    wire [63:0] c2h_dsc_byp_src_addr_0, c2h_dsc_byp_dst_addr_0;
    wire [27:0] c2h_dsc_byp_len_0;
    wire [15:0] c2h_dsc_byp_ctl_0;
`endif
`ifdef DSC_BYPASS_H2C_CHL0_EN
    wire h2c_dsc_byp_ready_0, h2c_dsc_byp_load_0;
    wire [63:0] h2c_dsc_byp_src_addr_0, h2c_dsc_byp_dst_addr_0;
    wire [27:0] h2c_dsc_byp_len_0;
    wire [15:0] h2c_dsc_byp_ctl_0;
`endif

    wire [7:0] c2h_sts_0, h2c_sts_0, c2h_sts_1, h2c_sts_1;
    wire [7:0] c2h_sts_2, h2c_sts_2, c2h_sts_3, h2c_sts_3;

    wire        sys_clk_g;
    wire        app_auxclk;
    wire        user_clk;
    wire        user_rst_n;
    wire        core_clk;
    wire        pll_lock;
    wire        user_link_up;

// ====================================================================
// Internal Power-On Reset
// ====================================================================
    reg  [9:0]  int_por_cnt = 10'd0;
    wire        int_por_done = &int_por_cnt;
    reg         int_por_done_r = 1'b0;

    always @(posedge sys_clk_g) begin
        if (!int_por_done)
            int_por_cnt <= int_por_cnt + 1'b1;
        int_por_done_r <= int_por_done;
    end

// ====================================================================
// Global Clock Buffer
// ====================================================================
PH1_LOGIC_BUFG u_sys_clk_bufg (
    .i  (sys_clk    ),
    .o  (sys_clk_g  )
);

// ====================================================================
// MIPI Reference Clock: 100MHz LVDS differential input (T13/T14)
// TD auto-infers LVDS input buffer from IOSTANDARD=LVDS18 constraint.
// Route through BUFG for global clock tree.
// ====================================================================
    wire mipi_ref_clk_bufg;
PH1_LOGIC_BUFG u_mipi_ref_clk_bufg (
    .i  (mipi_ref_clk_p ),
    .o  (mipi_ref_clk_bufg)
);

// ====================================================================
// Camera PLL: 100MHz LVDS -> 150MHz (cam_pclk) + 135MHz (cam_reserved135m) + 27MHz (cam_27m)
// cam_pclk  = mipi_ref_clock for MIPI PHY (150MHz required for Eye-Scan)
// cam_reserved135m  = reserved
// cam_27m   = MCLK source (ODDR) + I2C master clock
// ====================================================================
    wire cam_pclk, cam_reserved135m, cam_27m, ui_pll_lock;
ui_pll728 u_ui_pll (
    .refclk     (mipi_ref_clk_bufg  ),
    .reset      (1'b0              ),
    .lock       (ui_pll_lock        ),
    .clk0_out   (cam_pclk           ),
    .clk1_out   (cam_reserved135m           ),
    .clk2_out   (cam_27m            )
);

// ====================================================================
// PLL: 25MHz -> 125MHz (core_clk) + 25MHz (app_auxclk)
// ====================================================================
wire codec_clk;
sgdma_pll771 u_sgdma_pll(
    .refclk     (sys_clk_g          ),
    .reset      (!int_por_done_r    ),
    .lock       (pll_lock           ),
    .clk0_out   (core_clk           ),
    .clk1_out   (app_auxclk         ),
    .clk2_out   (codec_clk          )
);

// ====================================================================
// PERST# + PLL stable
// ====================================================================
    reg  [21:0] pll_lock_cnt;
    wire        pll_lock_stable_comb = (pll_lock_cnt == 22'h3FFFFF);

    always @(posedge core_clk or negedge pll_lock) begin
        if (!pll_lock)
            pll_lock_cnt <= 22'd0;
        else if (!pll_lock_stable_comb)
            pll_lock_cnt <= pll_lock_cnt + 1'b1;
    end

    reg pll_lock_stable;
    always @(posedge core_clk or negedge pll_lock) begin
        if (!pll_lock)
            pll_lock_stable <= 1'b0;
        else
            pll_lock_stable <= pll_lock_stable_comb;
    end

    wire tl_power_on_rstn = pcie_mperst & pll_lock_stable;

    // debug_button removed (no physical button on AFC03 board)
    // Tie high = "not pressed" (same as PULLUP idle state)
    wire debug_button_w = 1'b1;

    wire sensor_cfg_ready;
    sensor_startup728 u_sensor_startup728 (
        .clock_27m(cam_27m),
        .pll_locked(ui_pll_lock),
        .sensor_xclr(cam_xclr),
        .sensor_mclk(cam_mclk),
        .cfg_ready(sensor_cfg_ready)
    );

// ====================================================================
// SGDMA Subsystem (identical to Phase 8)
// ====================================================================
sgdma_subsys #(
    .USER_CLK_FREQ  (USER_CLK_FREQ),
    .DEVICE_FAMILY  (DEVICE_FAMILY),
    .LINK_WIDTH     (LINK_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .H2C_CHNL_NUM  (H2C_CHNL_NUM),
    .C2H_CHNL_NUM  (C2H_CHNL_NUM),
    .USR_IRQ_NUM    (USR_IRQ_NUM),
    .LGCY_EN        (IRQ_LGCY_EN),
    .MSI_EN         (IRQ_MSI_EN),
    .MSIX_EN        (IRQ_MSIX_EN),
    .AXI4MM_BUS_EN  (AXI4MM_BUS_EN),
    .AXI4ST_BUS_EN  (AXI4ST_BUS_EN),
    .H2C_DSC_BYP_MAP(H2C_DSC_BYP_MAP),
    .C2H_DSC_BYP_MAP(C2H_DSC_BYP_MAP)
) u_sgdma_subsys(
    .app_auxclk             (app_auxclk),
    .tl_power_on_rstn       (tl_power_on_rstn),
    .tl_clk_user            (core_clk),
    .pll_lock               (pll_lock),
    .ref_pad_clk_p          (refclk_p),
    .ref_pad_clk_n          (refclk_n),
    .pcie_tx_p              (txp),
    .pcie_tx_n              (txn),
    .pcie_rx_p              (rxp),
    .pcie_rx_n              (rxn),
    .c2h_sts_0              (c2h_sts_0),
    .h2c_sts_0              (h2c_sts_0),
    .c2h_sts_1              (c2h_sts_1),
    .h2c_sts_1              (h2c_sts_1),
    .c2h_sts_2              (c2h_sts_2),
    .h2c_sts_2              (h2c_sts_2),
    .c2h_sts_3              (c2h_sts_3),
    .h2c_sts_3              (h2c_sts_3),
`ifdef AXI4ST_BUS_EN
    .s0_axis_c2h_tready     (s0_axis_c2h_tready),
    .s0_axis_c2h_tdata      (s0_axis_c2h_tdata),
    .s0_axis_c2h_tkeep      (s0_axis_c2h_tkeep),
    .s0_axis_c2h_tuser      (s0_axis_c2h_tuser),
    .s0_axis_c2h_tlast      (s0_axis_c2h_tlast),
    .s0_axis_c2h_tvalid     (s0_axis_c2h_tvalid),
    .m0_axis_h2c_tready     (m0_axis_h2c_tready),
    .m0_axis_h2c_tdata      (m0_axis_h2c_tdata),
    .m0_axis_h2c_tkeep      (m0_axis_h2c_tkeep),
    .m0_axis_h2c_tuser      (m0_axis_h2c_tuser),
    .m0_axis_h2c_tlast      (m0_axis_h2c_tlast),
    .m0_axis_h2c_tvalid     (m0_axis_h2c_tvalid),
`endif
`ifdef AXI4L_MBUS_EN
    .m_axil_awaddr          (m_axil_awaddr),
    .m_axil_awprot          (m_axil_awprot),
    .m_axil_awvalid         (m_axil_awvalid),
    .m_axil_awready         (m_axil_awready),
    .m_axil_wdata           (m_axil_wdata),
    .m_axil_wstrb           (m_axil_wstrb),
    .m_axil_wvalid          (m_axil_wvalid),
    .m_axil_wready          (m_axil_wready),
    .m_axil_bvalid          (m_axil_bvalid),
    .m_axil_bresp           (m_axil_bresp),
    .m_axil_bready          (m_axil_bready),
    .m_axil_araddr          (m_axil_araddr),
    .m_axil_arprot          (m_axil_arprot),
    .m_axil_arvalid         (m_axil_arvalid),
    .m_axil_arready         (m_axil_arready),
    .m_axil_rdata           (m_axil_rdata),
    .m_axil_rresp           (m_axil_rresp),
    .m_axil_rvalid          (m_axil_rvalid),
    .m_axil_rready          (m_axil_rready),
`endif
`ifdef DSC_BYPASS_C2H_CHL0_EN
    .c2h_dsc_byp_ready_0_o (c2h_dsc_byp_ready_0),
    .c2h_dsc_byp_load_0_i  (c2h_dsc_byp_load_0),
    .c2h_dsc_byp_src_addr_0_i(c2h_dsc_byp_src_addr_0),
    .c2h_dsc_byp_dst_addr_0_i(c2h_dsc_byp_dst_addr_0),
    .c2h_dsc_byp_len_0_i   (c2h_dsc_byp_len_0),
    .c2h_dsc_byp_ctl_0_i   (c2h_dsc_byp_ctl_0),
`endif
`ifdef DSC_BYPASS_H2C_CHL0_EN
    .h2c_dsc_byp_ready_0_o (h2c_dsc_byp_ready_0),
    .h2c_dsc_byp_load_0_i  (h2c_dsc_byp_load_0),
    .h2c_dsc_byp_src_addr_0_i(h2c_dsc_byp_src_addr_0),
    .h2c_dsc_byp_dst_addr_0_i(h2c_dsc_byp_dst_addr_0),
    .h2c_dsc_byp_len_0_i   (h2c_dsc_byp_len_0),
    .h2c_dsc_byp_ctl_0_i   (h2c_dsc_byp_ctl_0),
`endif
`ifdef USR_IRQ_EN
    .usr_irq_req            (usr_irq_req),
    .usr_irq_ack            (usr_irq_ack),
    .msi_enable             (msi_enable),
    .msi_vector_width       (msi_vector_width),
`endif
    .user_link_up           (user_link_up),
    .user_clk               (user_clk),
    .user_rst_n             (user_rst_n)
);

// ====================================================================
// Video Source Pipeline
// ====================================================================
`ifdef AXI4ST_BUS_EN

    // 锟斤拷锟斤拷 Config Registers (Camera) 锟斤拷锟斤拷
    reg         reg_enable;
    reg         reg_soft_reset;
    reg [1:0]   reg_cam_mode;       // Camera resolution mode (0=1080p, 1=4K, 2=720p)
    wire jpeg_config_idle,source_configured;
    wire        reg_jpeg_mode;
    reg [2:0]   reg_preprocess_mask;
    reg [1:0] reg_bayer_phase;wire [1:0] active_bayer_phase;
    wire [6:0]  reg_jpeg_quality;
    wire [6:0]  jpeg_active_quality;
    wire [2:0]  cam_preprocess_active;
    wire wr_pulse;
    wire [1:0] advanced_requested_mode, advanced_active_mode;
    wire [1:0] morphology_requested_mode, morphology_active_mode,effective_morphology_mode;
    wire mode_frame_valid;
    wire jpeg_stop_requested;
    wire live_write_hit=m_axil_awvalid && m_axil_wvalid && m_axil_awaddr[15:0]==16'h0200;
    reg live_write_held;
    always @(posedge user_clk or negedge user_rst_n)
        if(!user_rst_n)live_write_held<=0;else live_write_held<=live_write_hit;
    wire live_write_pulse=live_write_hit && !live_write_held;
    wire [31:0] mode_frame_wire_id,live_preprocess_read_data;
    live_preprocess1512 live_preprocess (
        .clk(user_clk),.reset_n(user_rst_n),
        .write_enable(wr_pulse || live_write_pulse),.write_address(m_axil_awaddr),
        .write_data(m_axil_wdata),.write_strobe(m_axil_wstrb),
        .read_address(m_axil_araddr),.read_data(live_preprocess_read_data),
        .config_idle(jpeg_config_idle),
        .live_allowed(reg_enable && reg_jpeg_mode && !jpeg_stop_requested && reg_cam_mode==0),
        .baseline_mode(morphology_requested_mode),.requested_mode(effective_morphology_mode),
        .frame_valid(mode_frame_valid),.frame_wire_id(mode_frame_wire_id),
        .frame_mode(morphology_active_mode));
    wire [7:0] advanced_requested_threshold, advanced_active_threshold;
    wire [31:0] advanced_requested_readback, advanced_active_readback;

    board_morphology_control advanced_control (
        .clk(user_clk), .reset_n(user_rst_n),
        .write_enable(wr_pulse && jpeg_config_idle && m_axil_awaddr[15:0] == 16'h00CC),
        .write_data(m_axil_wdata), .write_strobe(m_axil_wstrb),
        .requested_mode(advanced_requested_mode), .requested_threshold(advanced_requested_threshold),
        .requested_morphology(morphology_requested_mode), .active_morphology(morphology_active_mode),
        .active_mode(advanced_active_mode), .active_threshold(advanced_active_threshold),
        .requested_readback(advanced_requested_readback), .active_readback(advanced_active_readback)
    );
    reg [7:0]   reg_ae_gain;        // AE gain value (0-240, default 100 = 30dB)
    reg         ae_gain_wr_toggle;  // toggles on PCIe write 锟斤拷 CDC to cam_27m

    // 锟斤拷锟斤拷 Resolution Mode LUT (runtime switchable) 锟斤拷锟斤拷
    // cam_mode 锟斤拷 { img_width[12:0], img_height[12:0], crop_v_start[14:0], crop_v_end[14:0], crop_h_end[14:0] }
    reg  [12:0] cam_img_width;
    reg  [12:0] cam_img_height;
    reg  [14:0] cam_crop_v_start;
    reg  [14:0] cam_crop_v_end;
    reg  [14:0] cam_crop_h_end;

    always @(*) begin
        case (reg_cam_mode)
            2'd0: begin  // 1080p 2锟斤拷2 binning
                cam_img_width    = 13'd1920;
                cam_img_height   = 13'd1080;
                cam_crop_v_start = (lossless_mode || reg_jpeg_mode) ? 15'd15 : 15'd19;
                cam_crop_v_end   = (lossless_mode || reg_jpeg_mode) ? 15'd1096 : 15'd1100;
                cam_crop_h_end   = 15'd481;
            end
            2'd1: begin  // 4K full resolution
                cam_img_width    = 13'd3840;
                cam_img_height   = 13'd2160;
                cam_crop_v_start = 15'd35;  // was 36 锟斤拷 fixed: first valid row must be even for correct RGGB Bayer phase
                cam_crop_v_end   = 15'd2196; // was 2197 锟斤拷 adjusted to keep exactly 2160 valid rows
                cam_crop_h_end   = 15'd961;
            end
            2'd2: begin  // 720p
                cam_img_width    = 13'd1280;
                cam_img_height   = 13'd720;
                cam_crop_v_start = 15'd35;
                cam_crop_v_end   = 15'd756;
                cam_crop_h_end   = 15'd321;
            end
            default: begin // fallback to 1080p
                cam_img_width    = 13'd1920;
                cam_img_height   = 13'd1080;
                cam_crop_v_start = 15'd19;
                cam_crop_v_end   = 15'd1100;
                cam_crop_h_end   = 15'd481;
            end
        endcase
    end

    wire        vid_sys_rst_n;
    board_reset_release video_release (
        user_clk, user_rst_n & ~reg_soft_reset, vid_sys_rst_n
    );
    wire        cam_sys_rst_n = vid_sys_rst_n;

    // Enable gating
    // Register the common link/capture control before camera abort logic.
    // BAR mode changes remain guarded by capture-off and lossless-busy.
    reg cam_enable;
    always @(posedge user_clk or negedge user_rst_n)begin
        if(!user_rst_n)cam_enable<=1'b0;
        else cam_enable<=reg_enable && user_link_up;
    end

    // Status wires
    wire [31:0] cam_frame_count;
    wire        cam_i2c_done;           // cam_27m domain
    wire        cam_mipi_div_clk;       // MIPI HS clock domain
    wire        cam_auto_delay_done;    // MIPI HS 锟斤拷 user_clk CDC
    wire        cam_mipi_tvalid;        // MIPI raw tvalid (debug)
    wire [31:0] cam_diag_data;
    wire [31:0] jpeg_diagnostic_data;
    wire [31:0] jpeg_quality_diagnostic_data;
    wire lossless_mode, lossless_busy, lossless_fault;
    wire jpeg_busy,jpeg_reset_request;
    wire jpeg_admission_stopped,jpeg_stop_ready;
    wire [31:0] jpeg_admitted,jpeg_committed,jpeg_aborted,jpeg_faults,jpeg_bar_data;
    wire jpeg_stop_write_pulse;
    board_stop_write1029 stop_write (
        .clk(user_clk),.reset_n(user_rst_n),.awvalid(m_axil_awvalid),.wvalid(m_axil_wvalid),
        .address(m_axil_awaddr),.pulse(jpeg_stop_write_pulse));
    board_jpg2_control774 jpg2_control (
        .clk(user_clk),.reset_n(user_rst_n),.write_enable(wr_pulse || jpeg_stop_write_pulse),
        .write_address(m_axil_awaddr),.write_data(m_axil_wdata),.write_strobe(m_axil_wstrb),
        .read_address(m_axil_araddr),.read_data(jpeg_bar_data),
        .capture_enabled(reg_enable),.camera_mode(reg_cam_mode),.geometry_configured(source_configured),
        .lossless_mode(lossless_mode),.lossless_busy(lossless_busy),.jpeg_busy(jpeg_busy),
        .stop_requested(jpeg_stop_requested),.admission_stopped(jpeg_admission_stopped),.stop_ready(jpeg_stop_ready),
        .admitted(jpeg_admitted),.committed(jpeg_committed),.aborted(jpeg_aborted),.faults(jpeg_faults),
        .jpeg_enabled(reg_jpeg_mode),.requested_quality(reg_jpeg_quality),
        .config_idle(jpeg_config_idle),.reset_request(jpeg_reset_request)
    );
    wire [15:0] source_beats,source_lines;
    wire [31:0] geometry_read_data,observation_data,owner_data,committed_frame_id;
    wire [3:0] observation_index,owner_index;
    wire geometry_hit=m_axil_wvalid && m_axil_awvalid && m_axil_awaddr[15:7]==9'h002;
    reg geometry_hit_d1;
    always @(posedge user_clk or negedge user_rst_n)
        if(!user_rst_n) geometry_hit_d1<=0;else geometry_hit_d1<=geometry_hit;
    board_geometry_control724 geometry_configuration (
        .clk(user_clk),.reset_n(user_rst_n),
        .idle(!reg_enable && !reg_jpeg_mode && !lossless_mode && !lossless_busy && !jpeg_busy),
        .write_enable(geometry_hit && !geometry_hit_d1),.write_address(m_axil_awaddr[6:0]),
        .write_data(m_axil_wdata),.write_strobe(m_axil_wstrb),.read_address(m_axil_araddr[6:0]),
        .beats_per_line(source_beats),.lines_per_frame(source_lines),.configured(source_configured),
        .observation_data(observation_data),.owner_data(owner_data),
        .observation_index(observation_index),.owner_index(owner_index),.read_data(geometry_read_data)
    );
    reg [7:0] cam_diag_index;
    wire [5:0] cam_delay_config;
    rx_delay_config714 rx_delay_configuration (
        .clock(user_clk), .reset_n(user_rst_n),
        .write_pulse(wr_pulse && m_axil_awaddr[7:0] == 8'h54),
        .idle(!reg_enable && !reg_soft_reset && !reg_jpeg_mode && !lossless_mode && !lossless_busy && !jpeg_busy),
        .write_strobes(m_axil_wstrb), .write_data(m_axil_wdata), .delay_config(cam_delay_config)
    );
    wire cam_diag_capture = wr_pulse && m_axil_awaddr[7:0] == 8'h6c &&
                            m_axil_wstrb[3] && m_axil_wdata[31];
    wire [7:0]  cam_dbg_mipi;           // MIPI debug bus (hs_div_clk)
    wire [7:0]  cam_dbg_delay;          // delay debug bus (hs_div_clk)
    wire [5:0]  cam_dbg_best_len;       // eye-scan best length
    wire [31:0] cam_mipi_fifo_overflow_count;
    wire [31:0] cam_mipi_fifo_overflow_snapshot;
    wire        cam_i2c_bus_error;      // I2C bus error
    wire        frame_pulse;

    // 锟斤拷锟斤拷 CDC: cam_i2c_done (cam_27m 锟斤拷 user_clk) 锟斤拷锟斤拷
    reg [1:0]   cam_i2c_done_sync;
    wire        cam_i2c_done_s = cam_i2c_done_sync[1];
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n)
            cam_i2c_done_sync <= 2'b00;
        else
            cam_i2c_done_sync <= {cam_i2c_done_sync[0], cam_i2c_done};
    end

    // 锟斤拷锟斤拷 CDC: cam_auto_delay_done (hs_div_clk 锟斤拷 user_clk) 锟斤拷锟斤拷
    reg [1:0]   cam_delay_done_sync;
    wire        cam_delay_done_s = cam_delay_done_sync[1];
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n)
            cam_delay_done_sync <= 2'b00;
        else
            cam_delay_done_sync <= {cam_delay_done_sync[0], cam_auto_delay_done};
    end

    // 锟斤拷锟斤拷 CDC: cam_dbg_best_len (hs_div_clk 锟斤拷 user_clk, quasi-static after calibration) 锟斤拷锟斤拷
    wire mipi_monitor_reset_n;
    wire [31:0] cam_best_len_snapshot;
    wire [5:0] cam_best_len_sync = cam_delay_done_s ? cam_best_len_snapshot[5:0] : 6'd0;
    board_counter_snapshot camera_best_len_cdc (
        .source_clk(cam_mipi_div_clk),
        .source_reset_n(user_rst_n),
        .source_data({26'd0, cam_dbg_best_len}),
        .dest_clk(user_clk),
        .dest_reset_n(user_rst_n),
        .dest_data(cam_best_len_snapshot),
        .dest_valid()
    );

    // 锟斤拷锟斤拷 Clock detect: cam_mipi_div_clk 锟斤拷 mipi_clk_present (user_clk) 锟斤拷锟斤拷
    // Toggle a flag in MIPI clock domain, sample with 2FF sync in user_clk,
    // detect edges to determine clock is alive.
    reg         mipi_clk_toggle;
    board_reset_release mipi_monitor_release (
        cam_mipi_div_clk, user_rst_n, mipi_monitor_reset_n
    );
    always @(posedge cam_mipi_div_clk or negedge mipi_monitor_reset_n) begin
        if (!mipi_monitor_reset_n)
            mipi_clk_toggle <= 1'b0;
        else
            mipi_clk_toggle <= ~mipi_clk_toggle;
    end

    reg [1:0]   mipi_toggle_sync;
    reg         mipi_toggle_prev;
    reg         mipi_clk_present;
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            mipi_toggle_sync <= 2'b00;
            mipi_toggle_prev <= 1'b0;
            mipi_clk_present <= 1'b0;
        end else begin
            mipi_toggle_sync <= {mipi_toggle_sync[0], mipi_clk_toggle};
            mipi_toggle_prev <= mipi_toggle_sync[1];
            mipi_clk_present <= (mipi_toggle_sync[1] != mipi_toggle_prev);
        end
    end

    // Frame bytes calculation (same as Phase 8)
    // Active resolution: always from camera mode LUT
    wire [15:0] active_width  = {3'd0, cam_img_width};
    wire [15:0] active_height = {3'd0, cam_img_height};

    localparam BYTES_PER_BEAT = DATA_WIDTH / 8;  // 16 for 128-bit

    wire [31:0] line_bytes_w      = {16'd0, active_width} * 32'd3;  // RGB24 = 3 bytes/pixel
    wire [31:0] beats_raw         = line_bytes_w / BYTES_PER_BEAT;
    wire [31:0] beats_mod         = line_bytes_w % BYTES_PER_BEAT;
    wire [15:0] beats_per_line_w  = (beats_mod == 32'd0) ? beats_raw[15:0] : beats_raw[15:0] + 16'd1;
    wire [31:0] frame_total_beats = {16'd0, beats_per_line_w} * {16'd0, active_height};
    wire [31:0] padded_frame_bytes = frame_total_beats * BYTES_PER_BEAT;

    wire [31:0] lossless_read_data;
    wire [95:0] lossless_source_data;
    wire lossless_source_valid, lossless_source_sof, lossless_source_eol;
    wire [127:0] lossless_packet_data;
    wire [15:0] lossless_packet_keep;
    wire lossless_packet_valid, lossless_packet_last;
    wire jpeg_active = reg_jpeg_mode && reg_cam_mode == 2'd0 && !lossless_mode;
    wire [95:0] jpeg_rgb4_data;
    wire jpeg_rgb4_valid;
    wire jpeg_rgb4_ready;
    wire jpeg_rgb4_last;
    wire jpeg_rgb4_user;
    wire jpeg_input_overflow;
    wire [127:0] jpeg_packet_data;
    wire [15:0] jpeg_packet_keep;
    wire jpeg_packet_valid;
    wire jpeg_packet_last;
    wire [31:0] jpeg_oversize_count;
    wire [31:0] jpeg_busy_drop_count;
    wire [31:0] jpeg_input_fault_count;
    wire fifo_in_tready;
    wire [11:0] fifo_fill_level;
    wire fc_in_tready;
    reg [31:0] jpeg_input_overflow_count;

    // 锟斤拷锟斤拷 cam_video_source (IMX415 camera video source, v2 verified) 锟斤拷锟斤拷
    // Resolution parameters now driven by runtime registers via reg_cam_mode LUT
    wire ll_session_clear;wire [31:0] ll_generation,ll_denied;
    wire [31:0] ll_admitted,ll_skipped,ll_completed,ll_rejected,ll_overflow,ll_shape,ll_epoch,ll_wire_id,ll_source_id;
    wire [11:0] ll_high_water;
    cam_video_source_board774 #(
        .MIPI_LAN       (MIPI_LAN),
        .DEVICE         ("PH1A"),
        .BAYER_MODE     ("RGGB")
    ) u_cam_video_source (
        .codec_clk(codec_clk),.jpeg_busy(jpeg_busy),
        .jpeg_stop_requested(jpeg_stop_requested),.jpeg_admission_stopped(jpeg_admission_stopped),.jpeg_stop_ready(jpeg_stop_ready),
        .jpeg_admitted(jpeg_admitted),.jpeg_committed(jpeg_committed),
        .jpeg_aborted(jpeg_aborted),.jpeg_faults(jpeg_faults),
        .cfg_source_beats(source_beats),.cfg_source_lines(source_lines),.requested_quality(reg_jpeg_quality),
        .observation_index(observation_index),.observation_data(observation_data),
        .owner_index(owner_index),.owner_data(owner_data),
        .committed_data(jpeg_packet_data),.committed_keep(jpeg_packet_keep),
        .committed_valid(jpeg_packet_valid),.committed_last(jpeg_packet_last),.committed_ready(s0_axis_c2h_tready),
        .committed_frame_id(committed_frame_id),.active_quality(jpeg_active_quality),
        .committed_oversize_count(jpeg_oversize_count),.committed_fault_count(jpeg_input_fault_count),
        .committed_busy_count(jpeg_busy_drop_count),.committed_diagnostic(jpeg_diagnostic_data),
        .committed_quality_diagnostic(jpeg_quality_diagnostic_data),
        .user_clk           (user_clk),
        .user_rst_n         (cam_sys_rst_n & cam_i2c_done_s),
        .enable             (cam_enable & cam_i2c_done_s & jpeg_active),
        // Runtime resolution parameters
        .cfg_img_width      (cam_img_width),
        .cfg_img_height     (cam_img_height),
        .cfg_preprocess_mask(reg_preprocess_mask),
        .cfg_advanced_mode(advanced_requested_mode),
        .cfg_bayer_phase(reg_bayer_phase),.active_bayer_phase(active_bayer_phase),
        .cfg_morphology_mode(effective_morphology_mode), .morphology_active_mode(morphology_active_mode),
        .mode_frame_valid(mode_frame_valid),.mode_frame_wire_id(mode_frame_wire_id),
        .cfg_advanced_threshold(advanced_requested_threshold),
        .advanced_active_mode(advanced_active_mode),
        .advanced_active_threshold(advanced_active_threshold),
        .preprocess_active_mask(cam_preprocess_active),
        .cfg_crop_v_start   (cam_crop_v_start),
        .cfg_crop_v_end     (cam_crop_v_end),
        .cfg_crop_h_end     (cam_crop_h_end),
        // MIPI CSI-2
        .mipi_ref_clock     (cam_pclk),          // 150MHz from ui_pll C0
        .mipi_clk_hs_rx_p   (mipi_clk_hs_rx_p),
        .mipi_data_hs_p     (mipi_data_hs_p),
        // Accept every frame 锟斤拷 FIFO(2048) + frame_completer absorb tready gaps
        .frame_request      (1'b1),
        // 128-bit AXI-Stream output
        .m_tdata            (cam_tdata),
        .m_tvalid           (cam_tvalid),
        .m_tready           (cam_tready),
        .m_tlast            (cam_tlast),
        .m_frame_last       (cam_frame_last),
        .sof                (cam_sof),
        .eof                (cam_eof),
        .frame_count_out    (cam_frame_count),
        .lossless_mode(lossless_mode),.session_reset_n(user_rst_n && !ll_session_clear),
        .ll_packet_data(lossless_packet_data),.ll_packet_keep(lossless_packet_keep),
        .ll_packet_valid(lossless_packet_valid),.ll_packet_last(lossless_packet_last),.ll_packet_ready(s0_axis_c2h_tready),
        .ll_busy(),.ll_admitted(ll_admitted),.ll_skipped(ll_skipped),.ll_completed(ll_completed),.ll_rejected(ll_rejected),
        .ll_overflow(ll_overflow),.ll_shape(ll_shape),.ll_epoch(ll_epoch),.ll_wire_id(ll_wire_id),.ll_source_id(ll_source_id),.ll_high_water(ll_high_water),
        .lossless_data(lossless_source_data), .lossless_valid(lossless_source_valid),
        .lossless_sof(lossless_source_sof), .lossless_eol(lossless_source_eol),
        .jpeg_mode         (1'b1),
        .jpeg_tdata        (jpeg_rgb4_data),
        .jpeg_tvalid       (jpeg_rgb4_valid),
        .jpeg_tready       (jpeg_rgb4_ready),
        .jpeg_tlast        (jpeg_rgb4_last),
        .jpeg_tuser        (jpeg_rgb4_user),
        .jpeg_input_overflow(jpeg_input_overflow),
        // Debug / status
        .debug_button       (debug_button_w),
        .mipi_div_clk_out   (cam_mipi_div_clk),
        .auto_delay_done    (cam_auto_delay_done),
        .mipi_tvalid_out    (cam_mipi_tvalid),
        .delay_config(cam_delay_config), .diag_capture(cam_diag_capture), .diag_index(cam_diag_index), .diag_data(cam_diag_data),
        .dbg_mipi           (cam_dbg_mipi),
        .dbg_delay          (cam_dbg_delay),
        .dbg_best_len       (cam_dbg_best_len),
        .mipi_fifo_overflow_count (cam_mipi_fifo_overflow_count)
    );

    board_counter_snapshot camera_fifo_overflow_cdc (
        .source_clk(cam_mipi_div_clk),
        .source_reset_n(user_rst_n),
        .source_data(cam_mipi_fifo_overflow_count),
        .dest_clk(user_clk),
        .dest_reset_n(user_rst_n),
        .dest_data(cam_mipi_fifo_overflow_snapshot),
        .dest_valid()
    );

    assign lossless_fault=1'b0;
    // This hardware profile has no P4R2/raw transport. Zero capabilities and
    // identity prevent legacy software from treating it as a lossless board.
    assign lossless_mode=1'b0;
    assign lossless_busy=1'b0;
    assign ll_session_clear=1'b0;
    assign ll_generation=0;
    assign ll_denied=0;
    assign lossless_read_data=0;

    assign jpeg_rgb4_ready=1'b1; // Legacy RGB-to-JPEG branch is disabled in this candidate.


    always @(posedge user_clk or negedge vid_sys_rst_n) begin
        if (!vid_sys_rst_n)
            jpeg_input_overflow_count <= 0;
        else if (jpeg_active && jpeg_input_overflow)
            jpeg_input_overflow_count <= jpeg_input_overflow_count + 1'b1;
    end

    // JPG2 has its own provisional DATA / COMMIT / ABORT transport and
    // preserves advertised packets under SGDMA backpressure. Raw frame gate,
    // raw C2H RAM FIFO and raw frame completer are absent from this profile.
    wire [DATA_WIDTH-1:0] vid_tdata=jpeg_packet_data;
    wire vid_tvalid=jpeg_packet_valid;
    wire vid_frame_last=jpeg_packet_last;
    wire [31:0] gate_drop_count=0,gate_pass_count=0,fc_drop_count=0;
    wire vid_frame_drop=1'b0;
    wire fc_out_tvalid=jpeg_packet_valid;
    assign cam_tready=1'b1;
    assign s0_axis_c2h_tdata=jpeg_packet_data;
    assign s0_axis_c2h_tkeep=jpeg_packet_keep;
    assign s0_axis_c2h_tuser={KEEP_WIDTH{1'b1}};
    assign s0_axis_c2h_tlast=jpeg_packet_last;
    assign s0_axis_c2h_tvalid=jpeg_packet_valid && jpeg_active;

    // 锟斤拷锟斤拷 Stall/drop counter (observable via REG_DROP_COUNT) 锟斤拷锟斤拷
    // Tracks flush-terminated frames. Should be 0 for perfect operation.
    // Non-zero = frames with short SGDMA packet (driver can detect & hold prev).
    wire [31:0] fifo_drop_count = fc_drop_count;

    // 锟斤拷锟斤拷 Debug counters 锟斤拷锟斤拷
    reg [31:0] dbg_dma_beat_cnt;
    reg        dbg_tready_ever;
    reg [31:0] drop_detect_count;       // vid_drop_detect trigger count
    wire       dma_beat_fire_dbg = fc_out_tvalid & s0_axis_c2h_tready;

    always @(posedge user_clk or negedge vid_sys_rst_n) begin
        if (!vid_sys_rst_n) begin
            dbg_dma_beat_cnt  <= 32'd0;
            dbg_tready_ever   <= 1'b0;
            drop_detect_count <= 32'd0;
        end else begin
            if (dma_beat_fire_dbg)
                dbg_dma_beat_cnt <= dbg_dma_beat_cnt + 1'b1;
            if (s0_axis_c2h_tready)
                dbg_tready_ever <= 1'b1;
            if (vid_frame_drop)
                drop_detect_count <= drop_detect_count + 1'b1;
        end
    end

    // Camera SOF detection (for status register)
    reg cam_sof_seen;
    always @(posedge user_clk or negedge vid_sys_rst_n) begin
        if (!vid_sys_rst_n)
            cam_sof_seen <= 1'b0;
        else if (cam_sof)
            cam_sof_seen <= 1'b1;
    end

    assign app_c2h_tready = 1'b0;
`endif

// ====================================================================
// IMX415 I2C Configuration (runs on cam_27m = 27MHz from ui_pll)
// CLK_DIV = 239 锟斤拷 27MHz / (239+1) = 100kHz I2C
// ====================================================================
    // CDC: reg_cam_mode (user_clk 125MHz) 锟斤拷 cam_27m (27MHz)
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] cam_mode_sync1, cam_mode_sync2;
    always @(posedge cam_27m or negedge ui_pll_lock) begin
        if (!ui_pll_lock) begin
            cam_mode_sync1 <= 2'd0;
            cam_mode_sync2 <= 2'd0;
        end else begin
            cam_mode_sync1 <= reg_cam_mode;
            cam_mode_sync2 <= cam_mode_sync1;
        end
    end

    // 锟斤拷锟斤拷 AE Gain: CDC + auto-trigger 锟斤拷锟斤拷
    // reg_ae_gain (user_clk) 锟斤拷 ae_gain_sync (cam_27m)
    (* async_reg = "true", dont_touch = "true" *) reg [7:0] ae_gain_sync1, ae_gain_sync2;
    always @(posedge cam_27m or negedge ui_pll_lock) begin
        if (!ui_pll_lock) begin
            ae_gain_sync1 <= 8'd100;
            ae_gain_sync2 <= 8'd100;
        end else begin
            ae_gain_sync1 <= reg_ae_gain;
            ae_gain_sync2 <= ae_gain_sync1;
        end
    end

    // CDC: ae_gain_wr_toggle (user_clk) 锟斤拷 cam_27m, edge detect
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] ae_toggle_sync;
    reg ae_toggle_prev;
    wire ae_wr_edge = ae_toggle_sync[1] ^ ae_toggle_prev;
    always @(posedge cam_27m or negedge ui_pll_lock) begin
        if (!ui_pll_lock) begin
            ae_toggle_sync <= 2'b0;
            ae_toggle_prev <= 1'b0;
        end else begin
            ae_toggle_sync <= {ae_toggle_sync[0], ae_gain_wr_toggle};
            ae_toggle_prev <= ae_toggle_sync[1];
        end
    end

    // AE trigger: pending flag in cam_27m domain
    //   Set on: PCIe write to REG_AE_GAIN (via CDC edge detect)
    //   Cleared on: ae_cfg_done FALLING edge (FSM accepted request and started)
    //   NOTE: Must clear on FSM START (not FSM END) to prevent same-cycle
    //         NBA race where FSM sees old pending=1 and restarts immediately.
    wire ae_cfg_done_w;   // from ui_cfg_imx415
    reg  ae_cfg_done_d1;
    wire ae_cfg_done_rise = ae_cfg_done_w & ~ae_cfg_done_d1;
    wire ae_cfg_done_fall = ~ae_cfg_done_w & ae_cfg_done_d1;
    reg  ae_trig_pending;
    reg  [7:0] ae_write_cnt;  // debug: AE I2C write count (increments each ae_cfg_done_rise)
    wire [31:0] camera_status_snapshot;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] mipi_valid_sync;

    board_counter_snapshot camera_status_cdc (
        .source_clk(cam_27m), .source_reset_n(ui_pll_lock),
        .source_data({21'd0, ae_write_cnt, ae_trig_pending, ae_cfg_done_w, cam_i2c_bus_error}),
        .dest_clk(user_clk), .dest_reset_n(user_rst_n),
        .dest_data(camera_status_snapshot), .dest_valid()
    );

    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n)
            mipi_valid_sync <= 2'b00;
        else
            mipi_valid_sync <= {mipi_valid_sync[0], cam_mipi_tvalid};
    end

    always @(posedge cam_27m or negedge ui_pll_lock) begin
        if (!ui_pll_lock) begin
            ae_trig_pending <= 1'b0;   // Initial config already writes gain; trigger from PCIe write only
            ae_cfg_done_d1  <= 1'b1;   // match O_ae_cfg_done reset value
            ae_write_cnt    <= 8'd0;
        end else begin
            ae_cfg_done_d1 <= ae_cfg_done_w;
            if (ae_wr_edge)
                ae_trig_pending <= 1'b1;
            else if (ae_cfg_done_fall)       // clear on FSM START
                ae_trig_pending <= 1'b0;
            if (ae_cfg_done_rise)            // count on FSM END (independent)
                ae_write_cnt <= ae_write_cnt + 1'b1;
        end
    end

    ui_cfg_imx415 #(
        .CLK_DIV    (`CAM_I2C_CLK_DIV)
    ) u_cam_i2c_cfg (
        .I_clk          (cam_27m),
        .I_rst_n        (sensor_cfg_ready),
        .I_cam_mode     (cam_mode_sync2),  // CDC-synchronized mode
        .I_ae_req       (ae_trig_pending),  // AE trigger: auto on startup + PCIe write
        .I_ae_data      (ae_gain_sync2),    // CDC-synchronized gain value
        .O_cam_scl      (cam_scl),
        .IO_cam_sda     (cam_sda),
        .O_cfg_done     (cam_i2c_done),
        .O_ae_cfg_done  (ae_cfg_done_w),
        .O_bus_error    (cam_i2c_bus_error)
    );

// ====================================================================
// User BAR Register Intercept (0x40-0xA0)
// Extended with camera registers at 0x80-0xA0
// ====================================================================
`ifdef AXI4L_MBUS_EN
`ifdef AXI4ST_BUS_EN
    // 锟斤拷锟斤拷 Write intercept 锟斤拷锟斤拷
    // BUG FIX v18: axil_anal.v generates awready/wready with 1-cycle latency,
    // so awvalid & wvalid stay high for 2 cycles per write. Using raw wr_hit
    // causes ae_gain_wr_toggle to flip TWICE (cancelling itself). Fix: use
    // rising-edge pulse to ensure exactly one register update per AXI write.
    wire wr_hit = m_axil_wvalid && m_axil_awvalid &&
                  (m_axil_awaddr[15:8] == 8'h00);
    reg  wr_hit_d1;
    always @(posedge user_clk or negedge user_rst_n)
        if (!user_rst_n) wr_hit_d1 <= 1'b0;
        else             wr_hit_d1 <= wr_hit;
    assign wr_pulse = wr_hit && !wr_hit_d1;

    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            cam_diag_index <= 0;
            reg_enable      <= 1'b0;
            reg_soft_reset  <= 1'b0;
            reg_cam_mode    <= 2'd0;    // This profile supports 1080p only.
            reg_preprocess_mask <= 3'd1;reg_bayer_phase<=2'd0;
            reg_ae_gain     <= 8'd80;  // Default: 30dB (100 锟斤拷 0.3dB)
            ae_gain_wr_toggle <= 1'b0;
        end else begin
            if (reg_soft_reset)
                reg_soft_reset <= 1'b0;
            if (jpeg_reset_request) reg_soft_reset <= 1'b1;

            if (wr_pulse) begin
                case (m_axil_awaddr[7:0])
                    8'h6C: if (m_axil_wstrb[0]) cam_diag_index <= m_axil_wdata[7:0];
                    `REG_CTRL: begin
                        reg_enable     <= m_axil_wdata[0] && reg_jpeg_mode && source_configured;
                        reg_soft_reset <= m_axil_wdata[1] && !jpeg_busy;
                    end
                    `REG_CAM_MODE: if (!reg_enable && !reg_jpeg_mode && !lossless_mode && !lossless_busy && !jpeg_busy)
                        if(m_axil_wstrb[0] && m_axil_wdata[1:0]==0)reg_cam_mode <= 2'd0;
                    8'hB8: if (jpeg_config_idle) reg_preprocess_mask <= m_axil_wdata[2:0];
                    8'hCC: if (jpeg_config_idle && m_axil_wstrb[0]) reg_bayer_phase<=m_axil_wdata[5:4];
                    `REG_AE_GAIN: begin
                        reg_ae_gain       <= m_axil_wdata[7:0];
                        ae_gain_wr_toggle <= ~ae_gain_wr_toggle;
                    end
                endcase
            end
        end
    end

    // 锟斤拷锟斤拷 Read intercept (register range 0x40-0xA0) 锟斤拷锟斤拷
    reg        vid_rd_sel_d1;

    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n)
            vid_rd_sel_d1 <= 1'b0;
        else
            vid_rd_sel_d1 <= m_axil_arvalid &&
                             ((m_axil_araddr[15:8] == 8'h00 && m_axil_araddr[7:0] >= 8'h40 && m_axil_araddr[7:0] <= 8'hFC) ||
                              m_axil_araddr[15:7] == 9'h002 || m_axil_araddr[15:5] == 11'h00c || m_axil_araddr[15:6] == 10'h007 || m_axil_araddr[15:5] == 11'h010);
    end

    // Active frame count: always camera
    wire [31:0] active_frame_count = cam_frame_count;

    reg [31:0] vid_reg_rdata_d1;

    always @(posedge user_clk) begin
        if(m_axil_araddr[15:5]==11'h010) vid_reg_rdata_d1<=live_preprocess_read_data;
        else if(m_axil_araddr[15:6]==10'h007) vid_reg_rdata_d1<=jpeg_bar_data;
        else if(m_axil_araddr[15:5]==11'h00c) vid_reg_rdata_d1<=lossless_read_data;
        else if(m_axil_araddr[15:7]==9'h002) vid_reg_rdata_d1<=geometry_read_data;
        else case (m_axil_araddr[7:0])
            // 锟斤拷锟斤拷 Video registers (0x40-0x7C) 锟斤拷锟斤拷
            `REG_TPG_STATUS:      vid_reg_rdata_d1 <= {30'd0,
                                                       user_link_up, reg_enable};
            `REG_WIDTH:           vid_reg_rdata_d1 <= {16'd0, active_width};
            `REG_HEIGHT:          vid_reg_rdata_d1 <= {16'd0, active_height};
            `REG_PIXEL_FORMAT:    vid_reg_rdata_d1 <= 32'h0000_0001;
            `REG_FRAME_COUNT:     vid_reg_rdata_d1 <= active_frame_count;
            `REG_FPS_CONFIG:      vid_reg_rdata_d1 <= {26'd0, cam_delay_config};
            `REG_BYTES_PER_FRAME: vid_reg_rdata_d1 <= {16'd0, active_width} *
                                                      {16'd0, active_height} * 32'd3;
            `REG_VERSION:         vid_reg_rdata_d1 <= 32'h4a505399;
            `REG_CTRL:            vid_reg_rdata_d1 <= {30'd0, reg_soft_reset, reg_enable};
            `REG_PADDED_BYTES:    vid_reg_rdata_d1 <= padded_frame_bytes;
            `REG_DROP_COUNT:      vid_reg_rdata_d1 <= fifo_drop_count;
            `REG_PATTERN_SEL:     vid_reg_rdata_d1 <= cam_diag_index[7:4] == 4'hf ? jpeg_quality_diagnostic_data :
                                                     cam_diag_index[7:4] == 4'he ? jpeg_diagnostic_data : cam_diag_data;
            `REG_DELIVERED_COUNT: vid_reg_rdata_d1 <= active_frame_count;
            `REG_DBG_STATE:       vid_reg_rdata_d1 <= {20'd0,
                                                       1'b1,               // [11] source=Camera (always)
                                                       cam_i2c_done_s,      // [10] I2C config done (synced)
                                                       cam_sof_seen,        // [9]  camera SOF detected
                                                       s0_axis_c2h_tready,  // [8]  DMA tready
                                                       vid_tvalid,          // [7]  video output valid
                                                       cam_enable,          // [6]  camera path enabled
                                                       1'b0,               // [5]  (was TPG enable)
                                                       mipi_clk_present,    // [4]  MIPI clock alive
                                                       vid_frame_last,      // [3]  frame tlast
                                                       dbg_tready_ever,     // [2]  tready ever asserted
                                                       reg_enable,          // [1]  global enable
                                                       user_link_up};       // [0]  PCIe link up
            `REG_DBG_PIX_CNT:     vid_reg_rdata_d1 <= frame_total_beats;
            `REG_DBG_DMA_BEAT:    vid_reg_rdata_d1 <= dbg_dma_beat_cnt;

            // 锟斤拷锟斤拷 Camera registers (0x80-0x98) 锟斤拷锟斤拷
            `REG_SOURCE_SEL:      vid_reg_rdata_d1 <= 32'd1;  // always camera
            `REG_CAM_STATUS:      vid_reg_rdata_d1 <= {camera_status_snapshot[10:3],
                                                       9'd0,
                                                       camera_status_snapshot[2],
                                                       camera_status_snapshot[1],
                                                       1'b0,
                                                       cam_best_len_sync,   // [11:6] eye-scan best length
                                                       mipi_valid_sync[1],
                                                       cam_delay_done_s,    // [4] auto delay calibration done
                                                       camera_status_snapshot[0],
                                                       cam_sof_seen,        // [2] camera frame active
                                                       mipi_clk_present,    // [1] MIPI clock alive (synced)
                                                       cam_i2c_done_s};     // [0] I2C config done (synced)
            `REG_CAM_FRAME_COUNT: vid_reg_rdata_d1 <= cam_frame_count;
            `REG_CAM_ERROR:       vid_reg_rdata_d1 <= {3'd0, cam_img_width,    // [28:16] active camera width
                                                       3'd0, cam_img_height}; // [12:0]  active camera height
            `REG_CAM_MODE:        vid_reg_rdata_d1 <= {30'd0, reg_cam_mode};
            `REG_DROP_DETECT_CNT: vid_reg_rdata_d1 <= drop_detect_count;
            `REG_AE_GAIN:         vid_reg_rdata_d1 <= {24'd0, reg_ae_gain};
            `REG_GATE_DROP_CNT:   vid_reg_rdata_d1 <= gate_drop_count;
            `REG_GATE_PASS_CNT:   vid_reg_rdata_d1 <= gate_pass_count;
            8'hA4:              vid_reg_rdata_d1 <= {31'd0, reg_jpeg_mode};
            8'hA8:              vid_reg_rdata_d1 <= jpeg_input_overflow_count;
            8'hAC:              vid_reg_rdata_d1 <= jpeg_oversize_count;
            8'hB0:              vid_reg_rdata_d1 <= jpeg_busy_drop_count;
            8'hB4:              vid_reg_rdata_d1 <= jpeg_input_fault_count;
            8'hB8:              vid_reg_rdata_d1 <= {29'd0, reg_preprocess_mask};
            8'hBC:              vid_reg_rdata_d1 <= {29'd0, cam_preprocess_active};
            8'hC0:              vid_reg_rdata_d1 <= cam_mipi_fifo_overflow_snapshot;
            8'hC4:              vid_reg_rdata_d1 <= {25'd0, reg_jpeg_quality};
            8'hC8:              vid_reg_rdata_d1 <= {25'd0, jpeg_active_quality};
            8'hCC:              vid_reg_rdata_d1 <= (advanced_requested_readback & 32'hfffffff3) | {28'd0,effective_morphology_mode,2'd0} | {26'd0,reg_bayer_phase,4'd0};
            8'hD0:              vid_reg_rdata_d1 <= advanced_active_readback | {26'd0,active_bayer_phase,4'd0};

            8'hD4, 8'hD8, 8'hDC, 8'hE0, 8'hE4, 8'hE8,
            8'hEC, 8'hF0, 8'hF4, 8'hF8, 8'hFC:
                                vid_reg_rdata_d1 <= lossless_read_data;
            default:              vid_reg_rdata_d1 <= 32'd0;
        endcase
    end

    assign m_axil_rdata = vid_rd_sel_d1 ? vid_reg_rdata_d1 : app_axil_rdata;
`endif
`endif

// ====================================================================
// SGDMA Application (identical to Phase 8)
// ====================================================================
sgdma_app #(
    .ODATA_WIDTH    (DATA_WIDTH),
    .OKEEP_WIDTH    (KEEP_WIDTH),
    .H2C_CHNL_NUM  (H2C_CHNL_NUM),
    .H2C_DSC_BYP_MAP(H2C_DSC_BYP_MAP),
    .C2H_CHNL_NUM  (C2H_CHNL_NUM),
    .C2H_DSC_BYP_MAP(C2H_DSC_BYP_MAP),
    .DESC_BYP_EN   (DESC_BYP_EN)
) u_sgdma_app(
    .usr_rst_n                  (user_rst_n),
    .usr_clk                    (user_clk),
`ifdef AXI4ST_BUS_EN
    .m0_axis_h2c_tready         (m0_axis_h2c_tready),
    .m0_axis_h2c_tdata          (m0_axis_h2c_tdata),
    .m0_axis_h2c_tkeep          (m0_axis_h2c_tkeep),
    .m0_axis_h2c_tuser          (m0_axis_h2c_tuser),
    .m0_axis_h2c_tlast          (m0_axis_h2c_tlast),
    .m0_axis_h2c_tvalid         (m0_axis_h2c_tvalid),
    .s0_axis_c2h_tready         (app_c2h_tready),
    .s0_axis_c2h_tdata          (app_c2h_tdata),
    .s0_axis_c2h_tkeep          (app_c2h_tkeep),
    .s0_axis_c2h_tuser          (app_c2h_tuser),
    .s0_axis_c2h_tlast          (app_c2h_tlast),
    .s0_axis_c2h_tvalid         (app_c2h_tvalid),
`endif
`ifdef AXI4L_MBUS_EN
    .m_axil_awaddr              (m_axil_awaddr),
    .m_axil_awprot              (m_axil_awprot),
    .m_axil_awvalid             (m_axil_awvalid),
    .m_axil_awready             (m_axil_awready),
    .m_axil_wdata               (m_axil_wdata),
    .m_axil_wstrb               (m_axil_wstrb),
    .m_axil_wvalid              (m_axil_wvalid),
    .m_axil_wready              (m_axil_wready),
    .m_axil_bvalid              (m_axil_bvalid),
    .m_axil_bresp               (m_axil_bresp),
    .m_axil_bready              (m_axil_bready),
    .m_axil_araddr              (m_axil_araddr),
    .m_axil_arprot              (m_axil_arprot),
    .m_axil_arvalid             (m_axil_arvalid),
    .m_axil_arready             (m_axil_arready),
    .m_axil_rdata               (app_axil_rdata),
    .m_axil_rresp               (m_axil_rresp),
    .m_axil_rvalid              (m_axil_rvalid),
    .m_axil_rready              (m_axil_rready),
`endif
`ifdef DSC_BYPASS_C2H_CHL0_EN
    .c2h_dsc_byp_ready_0_i     (c2h_dsc_byp_ready_0),
    .c2h_dsc_byp_load_0_o      (c2h_dsc_byp_load_0),
    .c2h_dsc_byp_src_addr_0_o  (c2h_dsc_byp_src_addr_0),
    .c2h_dsc_byp_dst_addr_0_o  (c2h_dsc_byp_dst_addr_0),
    .c2h_dsc_byp_len_0_o       (c2h_dsc_byp_len_0),
    .c2h_dsc_byp_ctl_0_o       (c2h_dsc_byp_ctl_0),
`endif
`ifdef DSC_BYPASS_H2C_CHL0_EN
    .h2c_dsc_byp_ready_0_i     (h2c_dsc_byp_ready_0),
    .h2c_dsc_byp_load_0_o      (h2c_dsc_byp_load_0),
    .h2c_dsc_byp_src_addr_0_o  (h2c_dsc_byp_src_addr_0),
    .h2c_dsc_byp_dst_addr_0_o  (h2c_dsc_byp_dst_addr_0),
    .h2c_dsc_byp_len_0_o       (h2c_dsc_byp_len_0),
    .h2c_dsc_byp_ctl_0_o       (h2c_dsc_byp_ctl_0),
`endif
`ifdef USR_IRQ_EN
    .usr_irq_req                (usr_irq_req),
    .usr_irq_ack                (usr_irq_ack),
    .msi_enable                 (msi_enable),
    .msi_vector_width           (msi_vector_width),
`endif
    .c2h_sts_0                  (c2h_sts_0),
    .h2c_sts_0                  (h2c_sts_0),
    .c2h_sts_1                  (c2h_sts_1),
    .h2c_sts_1                  (h2c_sts_1),
    .c2h_sts_2                  (c2h_sts_2),
    .h2c_sts_2                  (h2c_sts_2),
    .c2h_sts_3                  (c2h_sts_3),
    .h2c_sts_3                  (h2c_sts_3)
);

// ====================================================================
// Debug UART (115200 8N1, periodic status output every 0.5s)
// Clock: app_auxclk (25MHz from sgdma_pll, always available after PLL lock)
// Output format: "S:xx F:xxxxxxxx\r\n"
// Status byte: [0]=pll_lock [1]=pll_lock_stable [2]=link_up [3]=ui_pll_lock
// ====================================================================

    // CDC: pll_lock_stable (core_clk 锟斤拷 app_auxclk, same PLL but different freq)
    wire dbg_reset_n;
    board_reset_release debug_release (app_auxclk, pll_lock, dbg_reset_n);
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] dbg_pll_stable_sync;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] dbg_ui_lock_sync;
    always @(posedge app_auxclk or negedge dbg_reset_n) begin
        if (!dbg_reset_n) begin
            dbg_pll_stable_sync <= 2'b00;
            dbg_ui_lock_sync <= 2'b00;
        end else begin
            dbg_pll_stable_sync <= {dbg_pll_stable_sync[0], pll_lock_stable};
            dbg_ui_lock_sync <= {dbg_ui_lock_sync[0], ui_pll_lock};
        end
    end

    // CDC: user_link_up (user_clk 锟斤拷 app_auxclk, fully async)
    (* async_reg = "true", dont_touch = "true" *) reg [2:0] dbg_link_up_sync;
    always @(posedge app_auxclk or negedge dbg_reset_n) begin
        if (!dbg_reset_n)
            dbg_link_up_sync <= 3'b0;
        else
            dbg_link_up_sync <= {dbg_link_up_sync[1:0], user_link_up};
    end

    // Assemble status word
    wire [15:0] dbg_uart_status = {12'd0,
                                   dbg_ui_lock_sync[1],
                                   dbg_link_up_sync[2],      // [2]
                                   dbg_pll_stable_sync[1],   // [1]
                                   pll_lock};                // [0]

    // Frame count (user_clk domain, sampled without formal CDC 锟斤拷 debug display only)
`ifdef AXI4ST_BUS_EN
    wire [31:0] dbg_uart_fcount;
    board_counter_snapshot debug_frame_snapshot (
        .source_clk(user_clk),
        .source_reset_n(user_rst_n),
        .source_data(cam_frame_count),
        .dest_clk(app_auxclk),
        .dest_reset_n(dbg_reset_n),
        .dest_data(dbg_uart_fcount),
        .dest_valid()
    );
`else
    wire [31:0] dbg_uart_fcount = 32'd0;
`endif

    debug_uart #(
        .CLK_FREQ   (25_000_000),       // app_auxclk = 25MHz
        .BAUD_RATE  (115200)
    ) u_debug_uart (
        .clk         (app_auxclk),
        .rst_n       (dbg_reset_n),
        .tx          (uart_tx),
        .rx          (uart_rx),
        .status      (dbg_uart_status),
        .frame_count (dbg_uart_fcount)
    );

endmodule


