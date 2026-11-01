//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : dsc_bypass_channel_block.v
//  Author        : dongyu.jiang
//  Last Modified : 2025-09-23 10:28:03
//  Create        : 2024-08-14
//  Description   : Initial version. v1.0
//
///////////////////////////////////////////////////////////////
// `ifdef DEBUG_MODE
//  `include "para_def.vh"
// `endif

module desc_byp_channel_block(
    input   wire            core_rst_n,
    input   wire            core_clk,

    input   wire            axil_wshake_i,
    input   wire    [31:0]  axil_wdata_i,
    input   wire    [31:0]  axil_waddr_i,
    input   wire            axil_rshake_i,
    input   wire    [31:0]  axil_raddr_i,
    output  wire    [31:0]  axil_rdata_o,

    input   wire            desc_byp_ready_i,
    output  wire            desc_byp_load_o,
    output  wire   [63:0]   desc_byp_src_addr_o,
    output  wire   [63:0]   desc_byp_dst_addr_o,
    output  wire   [27:0]   desc_byp_len_o,
    output  wire   [15:0]   desc_byp_ctl_o,
    
    input   wire            c2h_h2c_start_i,
    input   wire            c2h_h2c_mode_i
);

localparam  IDLE = 2'd0;
localparam  LOAD = 2'd1;
localparam  RAM_WIDTH = 16+64+64+32;
localparam  ADDRWIDTH = 9;

reg     [31:0]          axil_rdata;
reg     [15:0]          dscp_ctrl_bit;
reg     [15:0]          dscp_seq;
reg     [15:0]          dscp_max_seq;
reg     [31:0]          dst_addr_l;
reg     [31:0]          dst_addr_h;
reg     [31:0]          src_addr_l;
reg     [31:0]          src_addr_h;
reg     [31:0]          length;
reg     [3:0]           dam_ctrl;

reg                     start_load;
reg                     dsc_byp_load;
reg     [63:0]          dsc_byp_src_addr;
reg     [63:0]          dsc_byp_dst_addr;
reg     [27:0]          dsc_byp_len;
reg     [15:0]          dsc_byp_ctl;
reg                     trans_flag;

reg     [2:0]           start_cnt_d1;
reg     [2:0]           start_cnt;
reg                     c2h_h2c_start_d1;
wire                    c2h_h2c_start_rising;
wire                    start_pulse;
wire                    start_flag;

reg                     start_flag_d1;
reg     [1:0]           state ; 
reg                     axil_wshake;
reg     [31:0]          axil_wdata;
reg     [31:0]          axil_waddr;
reg                     dscp_is_ring;
(* ram_style = "bram" *)reg [RAM_WIDTH-1:0]   dat_ram [2**ADDRWIDTH-1:0];
reg     [RAM_WIDTH-1:0] dat_ram_out;
wire    [RAM_WIDTH-1:0] bram_din;
reg     [15:0]          bram_rdaddr;
reg                     bram_wren;

always @ ( posedge core_clk) begin
    axil_wshake     <= axil_wshake_i;
    axil_wdata      <= axil_wdata_i;
    axil_waddr      <= axil_waddr_i;
end 
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)begin
        dscp_ctrl_bit   <= 'd0;
        dscp_seq        <= 'd0;
        dst_addr_l      <= 'd0;
        dst_addr_h      <= 'd0;
        src_addr_l      <= 'd0;
        src_addr_h      <= 'd0;
        length          <= 'd0;
        dam_ctrl        <= 'd0;
    end else if(axil_wshake) begin
        case(axil_waddr[7:0])
            8'h00:begin dscp_ctrl_bit <= axil_wdata[15:0]; dscp_seq <= axil_wdata[31:16];end
            8'h04:dst_addr_h    <= axil_wdata;
            8'h08:dst_addr_l    <= axil_wdata;
            8'h0c:src_addr_h    <= axil_wdata;
            8'h10:src_addr_l    <= axil_wdata;
            8'h14:length        <= axil_wdata;
            8'h1c:dam_ctrl      <= axil_wdata[2:0];
            default:;
        endcase
    end
end

assign  bram_din = {dst_addr_h,dst_addr_l,src_addr_h,src_addr_l,length,dscp_ctrl_bit};
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        bram_wren   <= 'd0;
    else if(axil_wshake && axil_waddr[7:0] == 8'h14) 
        bram_wren   <= 'd1;
    else 
        bram_wren   <= 'd0;
end
always @(posedge core_clk) begin
    if( bram_wren ) begin 
        dat_ram[dscp_seq]   <= bram_din;
    end
end 
always @(posedge core_clk) begin
    dat_ram_out             <= dat_ram[bram_rdaddr];
end 
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        axil_rdata <= 'd0;
    else begin
        if(axil_rshake_i)begin
            case(axil_raddr_i[7:0])
            8'h00:axil_rdata <= {dscp_seq,dscp_ctrl_bit};
            8'h04:axil_rdata <= dst_addr_l;
            8'h08:axil_rdata <= dst_addr_h;
            8'h0c:axil_rdata <= src_addr_l;
            8'h10:axil_rdata <= src_addr_h;
            8'h14:axil_rdata <= length;
            8'h1c:axil_rdata <= dam_ctrl;
            default:axil_rdata <= 32'h0000;
            endcase
        end
    end
end
assign axil_rdata_o = axil_rdata;

always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        start_load          <= 'd0;
    else if(axil_wshake && axil_waddr[7:0] == 8'h1c )
        start_load          <= axil_wdata[0];
    else  
        start_load          <= 1'b0;
end
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        dscp_is_ring        <= 'd0;
    else if(axil_wshake && axil_waddr[7:0] == 8'h1c )
        dscp_is_ring        <= axil_wdata[1];
end
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        dscp_max_seq        <= 'd0;
    else if(axil_wshake && axil_waddr[7:0] == 8'h1c )
        dscp_max_seq        <= dscp_seq;
end

//****************************************************************************************************
assign start_flag = c2h_h2c_mode_i?start_pulse:start_load;

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        c2h_h2c_start_d1 <= 'd0;
    else begin
        c2h_h2c_start_d1 <= c2h_h2c_start_i;
    end
end

assign c2h_h2c_start_rising = c2h_h2c_start_i & ~c2h_h2c_start_d1;

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        start_cnt <= 'd0;
    else begin
        if(start_load | c2h_h2c_start_rising)
            start_cnt <= start_cnt + 1;
        else if(start_cnt == 2)
            start_cnt <= 'd0;
    end
end

always @ ( posedge core_clk or negedge core_rst_n )
begin
    if(!core_rst_n)
        start_cnt_d1 <= 'd0;
    else 
        start_cnt_d1 <= start_cnt;
end

assign start_pulse = (start_cnt == 2) & (start_cnt_d1 == 1);
always @ ( posedge core_clk ) begin
    start_flag_d1               <= start_flag;
end 
reg             is_first_load;
reg     [15:0]  start_load_addr;
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        is_first_load <= 'd1;
    else if(start_load) 
        is_first_load <= 'd1;
    else if(axil_wshake && axil_waddr[7:0] == 'd0)
        is_first_load <= 'd0;
end
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        start_load_addr     <= 'd0;
    else if(is_first_load && axil_wshake && axil_waddr[7:0] == 'd0) 
        start_load_addr     <= axil_wdata[31:16];
end

//This is the new round to start load descriptor
reg     reset_load;
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n)
        reset_load  <= 'd1;
    else if(axil_wshake && axil_waddr[7:0] == 'd0 && axil_wdata[31:16] == 'd0 )
        reset_load  <= 'd1;
    else 
        reset_load  <= 'd0;
end
///state machine
always @ ( posedge core_clk or negedge core_rst_n ) begin
    if(!core_rst_n) begin
        state                       <= IDLE;
        dsc_byp_load                <= 'd0;
        bram_rdaddr                 <= 'd0;
    end else if(reset_load) begin 
        state                       <= IDLE;
        dsc_byp_load                <= 'd0;
    end else begin
        case(state)
            IDLE : begin 
                if(start_flag_d1) 
                    state           <= LOAD;
                else 
                    state           <= IDLE;

                dsc_byp_load        <= 'd0;
                bram_rdaddr         <= start_load_addr;
            end 
            LOAD : begin 
                if(desc_byp_ready_i && bram_rdaddr == dscp_max_seq) 
                    bram_rdaddr     <= 'd0;
                else if(desc_byp_ready_i) 
                    bram_rdaddr     <= bram_rdaddr + 1'b1;
                else 
                    bram_rdaddr     <= bram_rdaddr;

                dsc_byp_load        <= desc_byp_ready_i && (bram_rdaddr <= dscp_max_seq);

                if( desc_byp_ready_i && bram_rdaddr == dscp_max_seq && !dscp_is_ring ) 
                    state           <= IDLE;
                else 
                    state           <= LOAD;
            end 
            default : begin 
                state               <= IDLE;
                dsc_byp_load        <= 'd0;
                bram_rdaddr         <= 'd0;                
            end 
        endcase
    end
end

always @ ( * ) begin
    dsc_byp_ctl     = dat_ram_out[15:0];
    dsc_byp_len     = dat_ram_out[47:16];
    dsc_byp_src_addr= dat_ram_out[111:48];
    dsc_byp_dst_addr= dat_ram_out[175:112];
end

assign desc_byp_load_o      = dsc_byp_load;
assign desc_byp_src_addr_o  = dsc_byp_src_addr;
assign desc_byp_dst_addr_o  = dsc_byp_dst_addr;
assign desc_byp_len_o       = dsc_byp_len;
assign desc_byp_ctl_o       = dsc_byp_ctl;

endmodule
