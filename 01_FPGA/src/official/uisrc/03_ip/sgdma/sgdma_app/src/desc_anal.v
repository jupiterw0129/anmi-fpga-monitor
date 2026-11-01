//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : dscp_anal.v
//  Author        : dongyu.jiang
//  Last Modified : 2025-05-08 09:59:55
//  Create        : 2024-08-14
//  Description   : Initial version. v1.0
//
///////////////////////////////////////////////////////////////
module desc_anal #(
    parameter H2C_CHNL_NUM = 1,
    parameter C2H_CHNL_NUM = 1,
    parameter H2C_DSC_BYP_MAP = 1'b1,
    parameter C2H_DSC_BYP_MAP = 1'b1
) (
    input   wire            core_clk,
    input   wire            core_rst_n,

    input   wire            c2h_h2c_start_i,
    input   wire            c2h_h2c_mode_i,
    input   wire    [7:0]   axil_wshake_i,
    input   wire    [7:0]   axil_rshake_i,
    input   wire    [31:0]  axil_wdata_i,
    input   wire    [31:0]  axil_waddr_i,
    input   wire    [31:0]  axil_raddr_i,
    output  wire    [32*8-1:0]  axil_rdata_o,

    input   wire            c2h_dsc_byp_ready_0_i,
    output  wire            c2h_dsc_byp_load_0_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_0_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_0_o,
    output  wire    [27:0]  c2h_dsc_byp_len_0_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_0_o,

    input   wire            c2h_dsc_byp_ready_1_i,
    output  wire            c2h_dsc_byp_load_1_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_1_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_1_o,
    output  wire    [27:0]  c2h_dsc_byp_len_1_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_1_o,

    input   wire            c2h_dsc_byp_ready_2_i,
    output  wire            c2h_dsc_byp_load_2_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_2_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_2_o,
    output  wire    [27:0]  c2h_dsc_byp_len_2_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_2_o,

    input   wire            c2h_dsc_byp_ready_3_i,
    output  wire            c2h_dsc_byp_load_3_o,
    output  wire    [63:0]  c2h_dsc_byp_src_addr_3_o,
    output  wire    [63:0]  c2h_dsc_byp_dst_addr_3_o,
    output  wire    [27:0]  c2h_dsc_byp_len_3_o,
    output  wire    [15:0]  c2h_dsc_byp_ctl_3_o,

    input   wire            h2c_dsc_byp_ready_0_i,
    output  wire            h2c_dsc_byp_load_0_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_0_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_0_o,
    output  wire    [27:0]  h2c_dsc_byp_len_0_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_0_o,

    input   wire            h2c_dsc_byp_ready_1_i,
    output  wire            h2c_dsc_byp_load_1_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_1_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_1_o,
    output  wire    [27:0]  h2c_dsc_byp_len_1_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_1_o,

    input   wire            h2c_dsc_byp_ready_2_i,
    output  wire            h2c_dsc_byp_load_2_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_2_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_2_o,
    output  wire    [27:0]  h2c_dsc_byp_len_2_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_2_o,

    input   wire            h2c_dsc_byp_ready_3_i,
    output  wire            h2c_dsc_byp_load_3_o,
    output  wire    [63:0]  h2c_dsc_byp_src_addr_3_o,
    output  wire    [63:0]  h2c_dsc_byp_dst_addr_3_o,
    output  wire    [27:0]  h2c_dsc_byp_len_3_o,
    output  wire    [15:0]  h2c_dsc_byp_ctl_3_o
);
wire    [4-1:0]     h2c_dsc_byp_ready;
wire    [4-1:0]     h2c_dsc_byp_load;
wire    [64*4-1:0]  h2c_dsc_byp_src_addr;
wire    [64*4-1:0]  h2c_dsc_byp_dst_addr;
wire    [28*4-1:0]  h2c_dsc_byp_len;
wire    [16*4-1:0]  h2c_dsc_byp_ctl;
    
wire    [4-1:0]     c2h_dsc_byp_ready;
wire    [4-1:0]     c2h_dsc_byp_load;
wire    [64*4-1:0]  c2h_dsc_byp_src_addr;
wire    [64*4-1:0]  c2h_dsc_byp_dst_addr;
wire    [28*4-1:0]  c2h_dsc_byp_len;
wire    [16*4-1:0]  c2h_dsc_byp_ctl;

assign c2h_dsc_byp_ready[0]     = c2h_dsc_byp_ready_0_i;
assign c2h_dsc_byp_load_0_o     = c2h_dsc_byp_load[0];
assign c2h_dsc_byp_src_addr_0_o = c2h_dsc_byp_src_addr[64*0+:64];
assign c2h_dsc_byp_dst_addr_0_o = c2h_dsc_byp_dst_addr[64*0+:64];
assign c2h_dsc_byp_len_0_o      = c2h_dsc_byp_len[28*0+:28];
assign c2h_dsc_byp_ctl_0_o      = c2h_dsc_byp_ctl[16*0+:16];

assign c2h_dsc_byp_ready[1]     = c2h_dsc_byp_ready_1_i;
assign c2h_dsc_byp_load_1_o     = c2h_dsc_byp_load[1];
assign c2h_dsc_byp_src_addr_1_o = c2h_dsc_byp_src_addr[64*1+:64];
assign c2h_dsc_byp_dst_addr_1_o = c2h_dsc_byp_dst_addr[64*1+:64];
assign c2h_dsc_byp_len_1_o      = c2h_dsc_byp_len[28*1+:28];
assign c2h_dsc_byp_ctl_1_o      = c2h_dsc_byp_ctl[16*1+:16];

assign c2h_dsc_byp_ready[2]     = c2h_dsc_byp_ready_2_i;
assign c2h_dsc_byp_load_2_o     = c2h_dsc_byp_load[2];
assign c2h_dsc_byp_src_addr_2_o = c2h_dsc_byp_src_addr[64*2+:64];
assign c2h_dsc_byp_dst_addr_2_o = c2h_dsc_byp_dst_addr[64*2+:64];
assign c2h_dsc_byp_len_2_o      = c2h_dsc_byp_len[28*2+:28];
assign c2h_dsc_byp_ctl_2_o      = c2h_dsc_byp_ctl[16*2+:16];

assign c2h_dsc_byp_ready[3]     = c2h_dsc_byp_ready_3_i;
assign c2h_dsc_byp_load_3_o     = c2h_dsc_byp_load[3];
assign c2h_dsc_byp_src_addr_3_o = c2h_dsc_byp_src_addr[64*3+:64];
assign c2h_dsc_byp_dst_addr_3_o = c2h_dsc_byp_dst_addr[64*3+:64];
assign c2h_dsc_byp_len_3_o      = c2h_dsc_byp_len[28*3+:28];
assign c2h_dsc_byp_ctl_3_o      = c2h_dsc_byp_ctl[16*3+:16];

assign h2c_dsc_byp_ready[0]     = h2c_dsc_byp_ready_0_i;
assign h2c_dsc_byp_load_0_o     = h2c_dsc_byp_load[0];
assign h2c_dsc_byp_src_addr_0_o = h2c_dsc_byp_src_addr[64*0+:64];
assign h2c_dsc_byp_dst_addr_0_o = h2c_dsc_byp_dst_addr[64*0+:64];
assign h2c_dsc_byp_len_0_o      = h2c_dsc_byp_len[28*0+:28];
assign h2c_dsc_byp_ctl_0_o      = h2c_dsc_byp_ctl[16*0+:16];

assign h2c_dsc_byp_ready[1]     = h2c_dsc_byp_ready_1_i;
assign h2c_dsc_byp_load_1_o     = h2c_dsc_byp_load[1];
assign h2c_dsc_byp_src_addr_1_o = h2c_dsc_byp_src_addr[64*1+:64];
assign h2c_dsc_byp_dst_addr_1_o = h2c_dsc_byp_dst_addr[64*1+:64];
assign h2c_dsc_byp_len_1_o      = h2c_dsc_byp_len[28*1+:28];
assign h2c_dsc_byp_ctl_1_o      = h2c_dsc_byp_ctl[16*1+:16];

assign h2c_dsc_byp_ready[2]     = h2c_dsc_byp_ready_2_i;
assign h2c_dsc_byp_load_2_o     = h2c_dsc_byp_load[2];
assign h2c_dsc_byp_src_addr_2_o = h2c_dsc_byp_src_addr[64*2+:64];
assign h2c_dsc_byp_dst_addr_2_o = h2c_dsc_byp_dst_addr[64*2+:64];
assign h2c_dsc_byp_len_2_o      = h2c_dsc_byp_len[28*2+:28];
assign h2c_dsc_byp_ctl_2_o      = h2c_dsc_byp_ctl[16*2+:16];

assign h2c_dsc_byp_ready[3]     = h2c_dsc_byp_ready_3_i;
assign h2c_dsc_byp_load_3_o     = h2c_dsc_byp_load[3];
assign h2c_dsc_byp_src_addr_3_o = h2c_dsc_byp_src_addr[64*3+:64];
assign h2c_dsc_byp_dst_addr_3_o = h2c_dsc_byp_dst_addr[64*3+:64];
assign h2c_dsc_byp_len_3_o      = h2c_dsc_byp_len[28*3+:28];
assign h2c_dsc_byp_ctl_3_o      = h2c_dsc_byp_ctl[16*3+:16];
//****************************************************************************************************
generate
genvar i;
    for(i=0;i<H2C_CHNL_NUM;i=i+1)begin:h2c_channel_block_inst
        if ((H2C_DSC_BYP_MAP>>i)&1) begin
            desc_byp_channel_block u_desc_byp_h2c_channel_block(
                .core_rst_n         (core_rst_n),
                .core_clk           (core_clk),

                .axil_wshake_i      (axil_wshake_i[i]),
                .axil_wdata_i       (axil_wdata_i),
                .axil_waddr_i       (axil_waddr_i),
                .axil_rshake_i      (axil_rshake_i[i]),
                .axil_raddr_i       (axil_raddr_i),
                .axil_rdata_o       (axil_rdata_o[i*32+31:i*32]),

                .desc_byp_ready_i   (h2c_dsc_byp_ready[i]),
                .desc_byp_load_o    (h2c_dsc_byp_load[i]),
                .desc_byp_src_addr_o(h2c_dsc_byp_src_addr[i*64+63:i*64]),
                .desc_byp_dst_addr_o(h2c_dsc_byp_dst_addr[i*64+63:i*64]),
                .desc_byp_len_o     (h2c_dsc_byp_len[i*28+27:i*28]),
                .desc_byp_ctl_o     (h2c_dsc_byp_ctl[i*16+15:i*16]),

                .c2h_h2c_start_i    (c2h_h2c_start_i),
                .c2h_h2c_mode_i     (c2h_h2c_mode_i)
            );
        end
    end

   for(i=0;i<C2H_CHNL_NUM;i=i+1)begin:c2h_channel_block_inst
        if ((C2H_DSC_BYP_MAP>>i)&1) begin
            desc_byp_channel_block u_desc_byp_c2h_channel_block(
                .core_rst_n         (core_rst_n),
                .core_clk           (core_clk),

                .axil_wshake_i      (axil_wshake_i[i+4]),
                .axil_wdata_i       (axil_wdata_i),
                .axil_waddr_i       (axil_waddr_i),
                .axil_rshake_i      (axil_rshake_i[i+4]),
                .axil_raddr_i       (axil_raddr_i),
                .axil_rdata_o       (axil_rdata_o[(i+4)*32+31:(i+4)*32]),

                .desc_byp_ready_i   (c2h_dsc_byp_ready[i]),
                .desc_byp_load_o    (c2h_dsc_byp_load[i]),
                .desc_byp_src_addr_o(c2h_dsc_byp_src_addr[i*64+63:i*64]),
                .desc_byp_dst_addr_o(c2h_dsc_byp_dst_addr[i*64+63:i*64]),
                .desc_byp_len_o     (c2h_dsc_byp_len[i*28+27:i*28]),
                .desc_byp_ctl_o     (c2h_dsc_byp_ctl[i*16+15:i*16]),

                .c2h_h2c_start_i    (c2h_h2c_start_i),
                .c2h_h2c_mode_i     (c2h_h2c_mode_i)
            );
        end
    end
endgenerate

endmodule
