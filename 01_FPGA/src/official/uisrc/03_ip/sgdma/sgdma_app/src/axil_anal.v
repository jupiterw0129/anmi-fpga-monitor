//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : axil_anal.v
//  Author        : dongyu.jiang
//  Last Modified : 2025-09-30 10:06:46
//  Create        : 2024-08-14
//  Description   : Initial version. v1.0
//
///////////////////////////////////////////////////////////////
// `ifdef DEBUG_MODE
// 	`include "para_def.vh"
// `endif

module axil_anal(
    input   wire            core_clk,
    input   wire            core_rst_n,

    input   wire   [31:0]   m_axil_awaddr_i,
    input   wire   [2:0]    m_axil_awprot_i,
    input   wire            m_axil_awvalid_i,
    output  wire            m_axil_awready_o,
    input   wire   [31:0]   m_axil_wdata_i,
    input   wire   [3:0]    m_axil_wstrb_i,
    input   wire            m_axil_wvalid_i,
    output  wire            m_axil_wready_o,
    output  wire            m_axil_bvalid_o,
    output  wire   [1:0]    m_axil_bresp_o,
    input   wire            m_axil_bready_i,
    input   wire   [31:0]   m_axil_araddr_i,
    input   wire   [2:0]    m_axil_arprot_i,
    input   wire            m_axil_arvalid_i,
    output  wire            m_axil_arready_o,
    output  wire   [31:0]   m_axil_rdata_o,
    output  wire   [1:0]    m_axil_rresp_o,
    output  wire            m_axil_rvalid_o,
    input   wire            m_axil_rready_i,

    output  wire   [7:0]    axil_wshake_o,
    output  wire   [31:0]   axil_wdata_o,
    output  wire   [31:0]   axil_waddr_o,
    output  wire   [7:0]    axil_rshake_o,
    output  wire   [31:0]   axil_raddr_o,
    input   wire   [32*8-1:0]  axil_rdata_i,

    //user interrupt
    output  wire   [31:0]   usr_irq_req_o,
    input   wire   [31:0]   usr_irq_evt_i,

	output  wire   [1:0]    usr_lp0rw_cmd_o,
    output  wire            usr_cfgrw_cmd_o,
    output  wire            c2h_h2c_start_o,
    output  wire            c2h_h2c_mode_o
);

reg                     c2h_h2c_start;
reg                     c2h_h2c_mode;
reg                     m_axil_awready;
reg                     m_axil_wready;
reg     [31:0]          m_axil_wdata;
reg     [31:0]          m_axil_awaddr;
reg                     m_axil_bvalid;
reg                     m_axil_rvalid;
reg     [31:0]          m_axil_rdata;

wire                    bram_wren;
reg     [7:0]           axil_wshake;
reg     [7:0]           axil_rshake;
reg     [7:0]           axil_rshake_d1;
wire    [31:0]          bram_out;
// reg                     axil_user_rd_flag;

reg     [31:0]          usr_irq_req;
reg     [1:0]           usr_lp0rw_cmd;
reg                     usr_cfgrw_cmd;
reg     [7:0]           m_axil_araddr_d1;
(* ram_style = "bram" *)reg [32-1:0]    axi_reg_ram [512-1:0];//synthesis ram_style = bram
reg     [32-1:0]    reg_ram_out;
//****************************************************************************************************
assign m_axil_rresp_o   = 2'b00;
assign m_axil_bresp_o   = 2'b00;
assign m_axil_awready_o = m_axil_awready;
assign m_axil_arready_o = 1'b1;//m_axil_arready;
assign m_axil_wready_o  = m_axil_wready;
assign m_axil_rvalid_o  = m_axil_rvalid;
assign m_axil_rdata_o   = m_axil_rdata;
assign m_axil_bvalid_o  = m_axil_bvalid;

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        m_axil_awready <= 'd0;
    else begin
        if(m_axil_awvalid_i & m_axil_wvalid_i)
            m_axil_awready <= 1'b1;
        else
            m_axil_awready <= 1'b0;
    end
end

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        m_axil_wready <= 'd0;
    else begin
        if(m_axil_awvalid_i & m_axil_wvalid_i)
            m_axil_wready <= 1'b1;
        else
            m_axil_wready <= 1'b0;
    end
end

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        m_axil_bvalid <= 'd0;
    else begin
        if(m_axil_awvalid_i & m_axil_wvalid_i & m_axil_awready_o & m_axil_wready)
            m_axil_bvalid <= 1'b1;
        else if(m_axil_bvalid_o & m_axil_bready_i)
            m_axil_bvalid <= 1'b0;
    end
end

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        m_axil_rvalid <= 'd0;
    else begin
        if(m_axil_arvalid_i & m_axil_arready_o)
            m_axil_rvalid <= 1'b1;
        else if(m_axil_rvalid_o & m_axil_rready_i)
            m_axil_rvalid <= 1'b0;
    end
end

always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        axil_wshake[7:0]    <= 8'b0000_0000;
    else if(m_axil_awvalid_i & m_axil_awready_o)begin
        case(m_axil_awaddr_i[15:8])
            8'b0000_0000:axil_wshake[7:0]   <= 8'b0000_0001;
            8'b0000_0001:axil_wshake[7:0]   <= 8'b0000_0010;
            8'b0000_0010:axil_wshake[7:0]   <= 8'b0000_0100;
            8'b0000_0011:axil_wshake[7:0]   <= 8'b0000_1000;
            8'b0001_0000:axil_wshake[7:0]   <= 8'b0001_0000;
            8'b0001_0001:axil_wshake[7:0]   <= 8'b0010_0000;
            8'b0001_0010:axil_wshake[7:0]   <= 8'b0100_0000;
            8'b0001_0011:axil_wshake[7:0]   <= 8'b1000_0000;
            default:axil_wshake[7:0]        <= 8'b0000_0000;
        endcase
    end else
        axil_wshake     <= 'd0;
end
always @ ( posedge core_clk ) begin
    m_axil_wdata[7:0]       <= m_axil_wstrb_i[0]? m_axil_wdata_i[7:0]  :8'd0;
    m_axil_wdata[15:8]      <= m_axil_wstrb_i[1]? m_axil_wdata_i[15:8] :8'd0;
    m_axil_wdata[23:16]     <= m_axil_wstrb_i[2]? m_axil_wdata_i[23:16]:8'd0;
    m_axil_wdata[31:24]     <= m_axil_wstrb_i[3]? m_axil_wdata_i[31:24]:8'd0;
end
always @ ( posedge core_clk ) begin
    m_axil_awaddr           <= m_axil_awaddr_i;
end

// always @ ( * ) begin
//     if(!core_rst_n)
//         axil_rshake[7:0]    = 8'b0000_0000;
//     else if(m_axil_arvalid_i & m_axil_arready_o)begin
//         case(m_axil_araddr_i[15:8])
//             8'b0000_0000:axil_rshake[7:0]   = 8'b0000_0001;
//             8'b0000_0001:axil_rshake[7:0]   = 8'b0000_0010;
//             8'b0000_0010:axil_rshake[7:0]   = 8'b0000_0100;
//             8'b0000_0011:axil_rshake[7:0]   = 8'b0000_1000;
//             8'b0001_0000:axil_rshake[7:0]   = 8'b0001_0000;
//             8'b0001_0001:axil_rshake[7:0]   = 8'b0010_0000;
//             8'b0001_0010:axil_rshake[7:0]   = 8'b0100_0000;
//             8'b0001_0011:axil_rshake[7:0]   = 8'b1000_0000;
//             default:axil_rshake[7:0]        = 8'b0000_0000;
//         endcase
//     end else
//         axil_rshake     = 'd0;
// end


assign axil_wshake_o    = axil_wshake;
assign axil_waddr_o     = m_axil_awaddr;
assign axil_wdata_o     = m_axil_wdata;
assign axil_rshake_o    = 0;//axil_rshake;
assign axil_raddr_o     = 0;//m_axil_araddr_i;

always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        m_axil_araddr_d1    <= 'd0;
    else if(m_axil_arvalid_i & m_axil_arready_o)
        m_axil_araddr_d1 <= m_axil_araddr_i[7:0];
end
// always @ ( posedge core_clk ) begin
//     axil_rshake_d1 <= axil_rshake;
// end
always@(*) begin
    if(m_axil_araddr_d1[7:0] == 8'h28)
        m_axil_rdata = usr_irq_evt_i;
    else
        m_axil_rdata = bram_out;
end

assign bram_wren = |axil_wshake;
always @(posedge core_clk) begin
    if(bram_wren)
        axi_reg_ram[m_axil_awaddr[10:2]]  <= m_axil_wdata;
end
always @(posedge core_clk) begin
    reg_ram_out <= axi_reg_ram[m_axil_araddr_i[10:2]];
end
assign  bram_out = reg_ram_out;

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)begin
        usr_lp0rw_cmd <= 'd0;
        usr_cfgrw_cmd <= 'd0;
    end else begin
        if(axil_wshake[0] && (m_axil_awaddr[7:0] == 8'h20))begin
            usr_lp0rw_cmd   <= m_axil_wdata[1:0];
            usr_cfgrw_cmd   <= m_axil_wdata[2];
        end
    end
end

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)begin
        c2h_h2c_start <= 'd0;
        c2h_h2c_mode  <= 'd0;
    end else begin
        if(axil_wshake[0] && (m_axil_awaddr[7:0] == 8'h24))begin
            c2h_h2c_start <= m_axil_wdata[0];
            c2h_h2c_mode  <= m_axil_wdata[1];
        end
    end
end

always@(posedge core_clk,negedge core_rst_n) begin
    if(!core_rst_n) begin
        usr_irq_req <= 0;
    end else if(axil_wshake[0] && (m_axil_awaddr[7:0] == 8'h28)) begin
        usr_irq_req <= m_axil_wdata;
    end
end

assign  usr_irq_req_o  = usr_irq_req;

assign usr_lp0rw_cmd_o = usr_lp0rw_cmd;
assign usr_cfgrw_cmd_o = usr_cfgrw_cmd;

assign c2h_h2c_start_o = c2h_h2c_start;
assign c2h_h2c_mode_o  = c2h_h2c_mode;

endmodule

