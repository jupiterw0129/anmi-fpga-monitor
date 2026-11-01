// ===========================================================================
// Copyright (c) 2011-2021 Anlogic Inc., All Right Reserved.
//
// TEL: 86-21-61633787
// WEB: http://www.anlogic.com/
// ===========================================================================
//
// Designer    :
// Date        : 2021/09/15
// Discription :
//          native clinet1 interface convert axi cc interface
// Email       :
//
// ===========================================================================


`timescale 1ns/1ns
`default_nettype none

module  pcie_tx_client12cc #(

    parameter DATA_WIDTH  = 128,
    parameter DW_WIDTH    = DATA_WIDTH/32,
    parameter USER_WIDTH  = 33,
    parameter NBYTE_WIDTH = DATA_WIDTH/8

)
(

    //---system clock and reset------------------------------//
     input      wire                core_clk
    ,input      wire                core_rst_n

    //---native client interface-------------------------------//
    ,output      reg        [DATA_WIDTH-1:0]  client1_tlp_data=0
    ,output      reg        [63:0]   client1_tlp_addr
    ,output      reg        [15:0]   client1_remote_req_id
    ,output      wire       [7:0]    client1_tlp_byte_en
    ,output      reg        [11:0]   client1_cpl_byte_cnt
    ,output      wire                client1_addr_align_en
    ,output      reg        [2:0]    client1_tlp_tc
    ,output      reg        [2:0]    client1_tlp_attr
    ,output      reg        [2:0]    client1_cpl_status
    ,output      wire                client1_cpl_bcm
    ,output      reg                 client1_tlp_dv
    ,output      reg                 client1_tlp_eot
    ,output      wire                client1_tlp_bad_eot
    ,output      reg                 client1_tlp_hv
    ,output      reg        [4:0]    client1_tlp_type
    ,output      reg        [1:0]    client1_tlp_fmt
    ,output      wire                client1_tlp_td
    ,output      reg        [12:0]   client1_tlp_byte_len
    ,output      reg        [9:0]    client1_tlp_tid
    ,output      wire                client1_tlp_ep
    ,output      wire                client1_tlp_func_num
    ,output      wire       [1:0]    client1_tlp_vfunc_num
    ,output      wire       [1:0]    client1_tlp_ats
    ,output      wire       [7:0]    client1_tlp_st
    ,output      wire                client1_tlp_vfunc_active
    ,output      wire                client1_tlp_nw
    ,output      wire                client1_tlp_th
    ,output      wire       [1:0]    client1_tlp_ph
    ,output      wire                client1_tlp_atu_bypass
    ,output      wire       [9:0]    client1_cpl_lookup_id
    ,input       wire                xadm_client1_halt

    //---make connection with cc when need look up id------//
    ,output      reg        [9:0]    rq_lookup_addr
    ,input       wire       [9:0]    rq_lookup_dout

    //---axi rq bus interface-------------------------------//
    ,input       wire                s_axis_cc_tvalid
    ,output      wire                s_axis_cc_tready
    ,input       wire       [DATA_WIDTH-1:0]  s_axis_cc_tdata
    ,input       wire       [DW_WIDTH-1:0]    s_axis_cc_tkeep
    ,input       wire                         s_axis_cc_tlast
    ,input       wire       [USER_WIDTH-1:0]  s_axis_cc_tuser

    //---only for debug---------------------------------------//
    ,output      wire       [3:0]    client12cc_debug
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================

    // state machine define and macro

    reg     [4:0]   client12cc_state                    ;
    localparam      CLIENT12CC_IDLE  =   5'b00001       ,
                    CLIENT12CC_HEAD0 =   5'b00010       ,
                    CLIENT12CC_HEAD1 =   5'b00100       ,
                    CLIENT12CC_DATA  =   5'b01000       ,
                    CLIENT12CC_END   =   5'b10000       ;

    // internal register and combination siangls
    reg             local_cc_rst_n                      ;

    reg             fifo_cc_wr_en                       ;
    reg             fifo_cc_wr_en_ff                    ;
    reg [DATA_WIDTH+DW_WIDTH+26:0]     fifo_cc_wr_din;
    reg [DATA_WIDTH+DW_WIDTH+26:0]     fifo_cc_wr_din_ff;

    wire            fifo_cc_rd_en                       ;
    wire  [DATA_WIDTH+DW_WIDTH+26:0]   fifo_cc_rd_dout;
    wire            fifo_cc_empty_flag                  ;
    wire            fifo_cc_full_flag                   ;

    reg             fifo_cc_pkg_wr                      ;
    reg             fifo_cc_pkg_rd                      ;
    reg   [9:0]     fifo_cc_pkg_cnt                     ;

    reg   [1:0]     cc_fifo_read_end_cnt                ;
    reg             fifo_cc_rd_en_reg                   ;
    reg             fifo_cc_rd_en_latch                 ;

    reg             client1_cpl_cpld                    ;
    reg             client12cc_first_pkg                ;
    reg   [DATA_WIDTH-1:0]   fifo_cc_rd_dout_ff;
    reg             client1_cpl_last                    ;

// ====================================================================
// PipeLine
// ====================================================================

always@(posedge core_clk)
begin
    // fifo side
    fifo_cc_wr_en_ff <= fifo_cc_wr_en ;
    fifo_cc_wr_din_ff<= fifo_cc_wr_din;
end

// ====================================================================
// Main Code
// ====================================================================

// reset localization
always@(posedge core_clk or negedge core_rst_n)
begin
    if(!core_rst_n)
        local_cc_rst_n <= 1'b0;
    else
        local_cc_rst_n <= 1'b1;
end

// write head and pure data into fifo
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        fifo_cc_wr_en <= 1'b0;
    end else if(s_axis_cc_tvalid & s_axis_cc_tready ) begin
        fifo_cc_wr_en <= 1'b1;
    end else begin
        fifo_cc_wr_en <= 1'b0;
    end
end


// write data into fifo, not need reset
always@(posedge core_clk )
begin
    if(s_axis_cc_tvalid & s_axis_cc_tready) begin
        fifo_cc_wr_din <= { 14'd0,s_axis_cc_tuser[9:0],s_axis_cc_tkeep[DW_WIDTH-1:0],3'b0,s_axis_cc_tlast,s_axis_cc_tdata[DATA_WIDTH-1:0]}; // { keep, last , end , data }
    end
end

// pull up when write whole tlp into fifo
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        fifo_cc_pkg_wr <= 1'b0;
    end else if(s_axis_cc_tready & s_axis_cc_tvalid & s_axis_cc_tlast) begin
        fifo_cc_pkg_wr <= 1'b1;
    end else begin
        fifo_cc_pkg_wr <= 1'b0;
    end
end

// pull up when read whole tlp out from fifo
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        fifo_cc_pkg_rd <= 1'b0;
    end else if(client12cc_state ==CLIENT12CC_HEAD0) begin
        fifo_cc_pkg_rd <= 1'b1;
    end else begin
        fifo_cc_pkg_rd <= 1'b0;
    end
end

// count the total tlp num in fifo
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        fifo_cc_pkg_cnt <= 'd0;
    end else begin
        case({fifo_cc_pkg_rd,fifo_cc_pkg_wr})
            2'b01: begin
                fifo_cc_pkg_cnt <= fifo_cc_pkg_cnt + 1'b1;
            end
            2'b10: begin
                fifo_cc_pkg_cnt <= fifo_cc_pkg_cnt - 1'b1;
            end
        // when both rd and wr at same cycle , we do nothing
        default : fifo_cc_pkg_cnt <= fifo_cc_pkg_cnt;
        endcase
    end
end


// set s_axis_cc_tready for back pressure
assign  s_axis_cc_tready = (!fifo_cc_full_flag);

generate if ( DATA_WIDTH == 128 ) begin: PH1A400
// Local buffer for tlp head and data cache
sfifo #(
//  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( 160  ),
  .DATA_WIDTH_R       ( 160  ),
  .ADDR_WIDTH_W       ( 9    ),
  .ADDR_WIDTH_R       ( 9    ),
  .AL_FULL_NUM        ( 502  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u0_client12cc_fifo(
  .rst                (!local_cc_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (fifo_cc_wr_en_ff     ),   
  .di                 (fifo_cc_wr_din_ff    ),   
  .re                 (fifo_cc_rd_en        ),  
  .dout               (fifo_cc_rd_dout      ),   
  .valid              (),   
  .full_flag          (fifo_cc_full_flag    ),   
  .empty_flag         (fifo_cc_empty_flag   ),   
  .afull              (),  
  .aempty             (),   
  .wrusedw            (),   
  .rdusedw            ()    
  );


end else begin: PH1A100
sfifo #(
//  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( 80  ),
  .DATA_WIDTH_R       ( 80  ),
  .ADDR_WIDTH_W       ( 9    ),
  .ADDR_WIDTH_R       ( 9    ),
  .AL_FULL_NUM        ( 502  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u0_client12cc_fifo(
  .rst                (!local_cc_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (fifo_cc_wr_en_ff     ),   
  .di                 (fifo_cc_wr_din_ff    ),   
  .re                 (fifo_cc_rd_en        ),  
  .dout               (fifo_cc_rd_dout      ),   
  .valid              (),   
  .full_flag          (fifo_cc_full_flag    ),   
  .empty_flag         (fifo_cc_empty_flag   ),   
  .afull              (),  
  .aempty             (),   
  .wrusedw            (),   
  .rdusedw            ()    
  );


end
endgenerate

generate if ( DATA_WIDTH == 128 ) begin: PH1A400_STATE
// read fifo data out and repackage to client1 data
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        client12cc_state <= CLIENT12CC_IDLE;
    end else begin
        case(client12cc_state)
            // wait fifo at least one tlp package
            CLIENT12CC_IDLE: begin
                if((|fifo_cc_pkg_cnt == 1'b1) & (!fifo_cc_empty_flag)) begin
                    client12cc_state <= CLIENT12CC_HEAD0;
                end
            end
            // read tlp header out first
            CLIENT12CC_HEAD0: begin
                client12cc_state <= CLIENT12CC_DATA;
            end
            // transfer pure data
            CLIENT12CC_DATA:begin
                if((client1_tlp_dv | client1_tlp_hv) & client1_tlp_eot & (!xadm_client1_halt)) begin
                    client12cc_state <= CLIENT12CC_IDLE;
                end
            end
            CLIENT12CC_END :begin
                //if(cc_fifo_read_end_cnt[1]==1'b1)begin
                    client12cc_state <= CLIENT12CC_IDLE;
                //end
            end
        default : client12cc_state <= CLIENT12CC_IDLE;
        endcase
    end
end

end else begin: PH1A100_STATE
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        client12cc_state <= CLIENT12CC_IDLE;
    end else begin
        case(client12cc_state)
            // wait fifo at least one tlp package
            CLIENT12CC_IDLE: begin
                if((|fifo_cc_pkg_cnt == 1'b1) & (!fifo_cc_empty_flag)) begin
                    client12cc_state <= CLIENT12CC_HEAD0;
                end
            end
            // read tlp header out first
            CLIENT12CC_HEAD0: begin
                    client12cc_state <= CLIENT12CC_HEAD1;
            end

            CLIENT12CC_HEAD1: begin
                client12cc_state <= CLIENT12CC_DATA;
            end
            // transfer pure data
            CLIENT12CC_DATA:begin
                if((client1_tlp_dv | client1_tlp_hv) & client1_tlp_eot & (!xadm_client1_halt)) begin
                    client12cc_state <= CLIENT12CC_IDLE;
                end
            end
            CLIENT12CC_END :begin
                //if(cc_fifo_read_end_cnt[1]==1'b1)begin
                    client12cc_state <= CLIENT12CC_IDLE;
                //end
            end
        default : client12cc_state <= CLIENT12CC_IDLE;
        endcase
    end
end

end
endgenerate

generate if ( DATA_WIDTH == 128 ) begin:PH1A400_REG
// register type of fifo rd en
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        fifo_cc_rd_en_reg <= 1'b0;
    end else if((client12cc_state ==CLIENT12CC_IDLE) & (|fifo_cc_pkg_cnt==1'b1) & (!fifo_cc_empty_flag)  )begin // read the header first
        fifo_cc_rd_en_reg <= 1'b1;
    end else if(client12cc_state ==CLIENT12CC_HEAD0 & (!fifo_cc_rd_dout[DATA_WIDTH]) ) begin   // tlp with data
        fifo_cc_rd_en_reg <= 1'b1;
    end else begin
        fifo_cc_rd_en_reg <= 1'b0;
    end
end

end else begin: PH1A100_REG
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        fifo_cc_rd_en_reg <= 1'b0;
    end else if((client12cc_state ==CLIENT12CC_IDLE) & (|fifo_cc_pkg_cnt==1'b1) & (!fifo_cc_empty_flag)  )begin // read the header first
        fifo_cc_rd_en_reg <= 1'b1;
    end else if((client12cc_state ==CLIENT12CC_HEAD0 || client12cc_state == CLIENT12CC_HEAD1 )& (!fifo_cc_rd_dout[DATA_WIDTH]) ) begin
        fifo_cc_rd_en_reg <= 1'b1;
    end else begin
        fifo_cc_rd_en_reg <= 1'b0;
    end
end

end
endgenerate

// combination type of fifo rd en
always@(*)
begin
    if(client1_tlp_dv & !xadm_client1_halt & (!client1_tlp_eot)) begin
        fifo_cc_rd_en_latch <= 1'b1;
    end else begin
        fifo_cc_rd_en_latch <= 1'b0;
    end
end

assign  fifo_cc_rd_en = fifo_cc_rd_en_reg | fifo_cc_rd_en_latch;


// delay 2 cycle when finish transfer tlp pkg
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n)begin
        cc_fifo_read_end_cnt <= 2'b0;
    end else if(client12cc_state == CLIENT12CC_END) begin
        cc_fifo_read_end_cnt <= cc_fifo_read_end_cnt + 1'b1;
    end else begin
        cc_fifo_read_end_cnt <= 2'b0;
    end
end

generate if ( DATA_WIDTH == 128 ) begin: PH1A400_FF
// client1 bus tlp header misc signals
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        client1_tlp_addr        <= 'd0;
        client1_remote_req_id   <= 'd0;
        client1_cpl_byte_cnt    <= 'd0;
        client1_tlp_tc          <= 'd0;
        client1_tlp_attr        <= 'd0;
        client1_cpl_status      <= 'd0;
        client1_tlp_byte_len    <= 'd0;
        client1_tlp_tid         <= 'd0;
        client1_cpl_cpld        <= 'd0;
        client1_cpl_last        <= 'd0;
    end else if(client12cc_state == CLIENT12CC_HEAD0) begin // get the tlp header from fifo
        client1_tlp_addr        <= {57'd0,fifo_cc_rd_dout[6:0]};
        client1_remote_req_id   <= fifo_cc_rd_dout[63:48];
        client1_cpl_byte_cnt    <= fifo_cc_rd_dout[27:16];  // max byte cnt support is 2048
        client1_tlp_tc          <= fifo_cc_rd_dout[91:89];
        client1_tlp_attr        <= fifo_cc_rd_dout[94:92];
        client1_cpl_status      <= fifo_cc_rd_dout[45:43];
        client1_tlp_byte_len    <= {fifo_cc_rd_dout[42:32],2'd0};
        client1_tlp_tid         <= fifo_cc_rd_dout[71:64];
        client1_cpl_cpld        <= fifo_cc_rd_dout[DATA_WIDTH] & (fifo_cc_rd_dout[42:32]==0);
        client1_cpl_last        <= fifo_cc_rd_dout[DATA_WIDTH];
        //client1_cpl_lookup_id   <= fifo_cc_rd_dout[145:136];
        // client1_cpl_lookup_id   <= fifo_cc_rd_dout[71:64];
    end
end


always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        rq_lookup_addr <= 10'd0;
    end else if(client12cc_state ==CLIENT12CC_HEAD0) begin
        rq_lookup_addr <= fifo_cc_rd_dout[71:64];
    end
end

end else begin: PH1A100_FF
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        client1_tlp_addr        <= 'd0;
        client1_remote_req_id   <= 'd0;
        client1_cpl_byte_cnt    <= 'd0;
        client1_tlp_tc          <= 'd0;
        client1_tlp_attr        <= 'd0;
        client1_cpl_status      <= 'd0;
        client1_tlp_byte_len    <= 'd0;
        client1_tlp_tid         <= 'd0;
        client1_cpl_cpld        <= 'd0;
        client1_cpl_last        <= 'd0;
    end else if(client12cc_state == CLIENT12CC_HEAD0) begin // get the tlp header from fifo
        client1_tlp_addr        <= {57'd0,fifo_cc_rd_dout[6:0]};
        client1_remote_req_id   <= fifo_cc_rd_dout[63:48];
        client1_cpl_byte_cnt    <= fifo_cc_rd_dout[27:16];  // max byte cnt support is 2048
        client1_cpl_status      <= fifo_cc_rd_dout[45:43];
        client1_tlp_byte_len    <= {fifo_cc_rd_dout[42:32],2'd0};
        client1_cpl_cpld        <= fifo_cc_rd_dout[DATA_WIDTH] & (fifo_cc_rd_dout[42:32]==0);
        client1_cpl_last        <= fifo_cc_rd_dout[DATA_WIDTH];
        //client1_cpl_lookup_id   <= fifo_cc_rd_dout[145:136];
    end else if ( client12cc_state == CLIENT12CC_HEAD1 ) begin
        
        client1_tlp_attr        <= fifo_cc_rd_dout[30:28];
        client1_tlp_tid         <= fifo_cc_rd_dout[7:0];
        client1_tlp_tc          <= fifo_cc_rd_dout[27:25];
        // client1_cpl_lookup_id   <= fifo_cc_rd_dout[7:0];
    end
end


always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        rq_lookup_addr <= 10'd0;
    end else if(client12cc_state ==CLIENT12CC_HEAD1) begin
        rq_lookup_addr <= fifo_cc_rd_dout[7:0];
    end
end

end
endgenerate

// always@(posedge core_clk ) begin
//     client1_cpl_lookup_id <= rq_lookup_dout;
// end

assign    client1_cpl_lookup_id = rq_lookup_dout;

// client1 bus tlp header fmt/addr/type signals
always@(posedge core_clk)
begin
     client1_tlp_type <= 5'b0_1010;
     if(client1_cpl_cpld)   // cpl
         client1_tlp_fmt <= 2'b00;
     else                   // cpld
         client1_tlp_fmt <= 2'b10;
end

// client1 bus hv/dv/eot/data signals
always@(posedge core_clk or negedge local_cc_rst_n)
begin
    if(!local_cc_rst_n) begin
        client1_tlp_dv       <= 1'b0;
        client1_tlp_hv       <= 1'b0;
        client1_tlp_eot      <= 1'b0;
        client12cc_first_pkg <= 1'b0;
    end else begin
        case(client12cc_state)
            CLIENT12CC_IDLE:begin
                client1_tlp_dv       <= 1'b0;
                client1_tlp_hv       <= 1'b0;
                client1_tlp_eot      <= 1'b0;
                client12cc_first_pkg <= 1'b1;
            end
            CLIENT12CC_DATA:begin
                client12cc_first_pkg <= 1'b0;
                // tlp_hv handle
                if(client1_tlp_hv & !xadm_client1_halt) begin
                    client1_tlp_hv   <= 1'b0;
                end else if(client12cc_first_pkg ) begin
                    client1_tlp_hv   <= 1'b1;
                end
                // tlp_eot handle
                if (client1_tlp_eot & !xadm_client1_halt) begin
                    client1_tlp_eot <= 1'b0;
                end else if( client12cc_first_pkg ) begin
                    client1_tlp_eot <= client1_cpl_cpld | client1_tlp_byte_len <= NBYTE_WIDTH;//fifo_cc_rd_dout[`DATA_WIDTH] ; // 1.without payload , 2. less than 4DW
                end else if(client1_tlp_dv & !xadm_client1_halt) begin
                    client1_tlp_eot <= fifo_cc_rd_dout[DATA_WIDTH] ;
                end
                // tlp_dv handle
                if(client1_tlp_eot & !xadm_client1_halt) begin
                    client1_tlp_dv   <= 1'b0;
                end else if(client12cc_first_pkg & !client1_cpl_cpld )begin
                    client1_tlp_dv   <= 1'b1;
                end
            end
        endcase
    end
end

// no need reset for data bus
generate if ( DATA_WIDTH == 128 ) begin: PH1A400_DAT_OUT
always@(posedge core_clk)
begin
    if(fifo_cc_rd_en) begin
        fifo_cc_rd_dout_ff <= fifo_cc_rd_dout;

        if( client12cc_state == CLIENT12CC_HEAD0)
            client1_tlp_data   <= {96'b0,fifo_cc_rd_dout[127:96]};
        else
            client1_tlp_data   <= {fifo_cc_rd_dout[95:0],fifo_cc_rd_dout_ff[127:96]};
    end
end

end else begin: PH1A100_DAT_OUT
always@(posedge core_clk)
begin
    if(fifo_cc_rd_en) begin
        fifo_cc_rd_dout_ff <= fifo_cc_rd_dout;

        if( client12cc_state == CLIENT12CC_HEAD1)
            client1_tlp_data   <= {32'b0,fifo_cc_rd_dout[63:32]};
        else
            client1_tlp_data   <= {fifo_cc_rd_dout[31:0],fifo_cc_rd_dout_ff[63:32]};
    end
end

end
endgenerate

// client1 bus tlp not used signals
assign  client1_addr_align_en   = 1'b0;
assign  client1_tlp_byte_en     = 8'hff; // not used when cpld
assign  client1_cpl_bcm         = 1'b0;  // not used when cpld
assign  client1_tlp_bad_eot     = 1'b0;  // not used when cpld
assign  client1_tlp_td          = 1'b0;
assign  client1_tlp_ep          = 1'b0;  // not used when cpld
assign  client1_tlp_ats         = 2'b0;
assign  client1_tlp_st          = 8'd0;
assign  client1_tlp_nw          = 1'd0;
assign  client1_tlp_th          = 1'd0;
assign  client1_tlp_ph          = 2'd0;
assign  client1_tlp_atu_bypass  = 1'b0;
assign  client1_tlp_func_num    = 'd0;
assign  client1_tlp_vfunc_num   = 'd0;
assign  client1_tlp_vfunc_active= 1'b0;
//assign  client1_cpl_lookup_id   = 'd0;  // maybe not rigth

endmodule

`default_nettype wire
