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
//          native clinet0 interface convert to axi rq interface
//
// Email       :
//
// ===========================================================================

`timescale 1ns/1ns
`default_nettype none

module  pcie_tx_client02rq #(
    parameter DATA_WIDTH = 128,
    parameter DW_WIDTH   = 4,
    parameter USER_WIDTH = 61

)
(
    //---system clock and reset------------------------------//
     input      wire                 core_clk
    ,input      wire                 core_rst_n

    //---native client interface-------------------------------//
    ,output      reg        [DATA_WIDTH-1:0]  client0_tlp_data=0
    ,output      reg        [63:0]   client0_tlp_addr
    ,output      reg        [15:0]   client0_remote_req_id
    ,output      reg        [7:0]    client0_tlp_byte_en
    ,output      wire       [11:0]   client0_cpl_byte_cnt
    ,output      wire                client0_addr_align_en
    ,output      reg        [2:0]    client0_tlp_tc
    ,output      reg        [2:0]    client0_tlp_attr
    ,output      wire       [2:0]    client0_cpl_status
    ,output      wire                client0_cpl_bcm
    ,(*MARK_DEBUG = "TRUE" *)output      reg                 client0_tlp_dv
    ,(*MARK_DEBUG = "TRUE" *)output      reg                 client0_tlp_eot
    ,output      wire                client0_tlp_bad_eot
    ,(*MARK_DEBUG = "TRUE" *)output      reg                 client0_tlp_hv
    ,output      reg        [4:0]    client0_tlp_type=0
    ,output      reg        [1:0]    client0_tlp_fmt=0
    ,output      wire                client0_tlp_td
    ,output      reg        [12:0]   client0_tlp_byte_len
    ,output      reg        [9:0]    client0_tlp_tid
    ,output      wire                client0_tlp_ep
    ,output      reg                 client0_tlp_func_num
    ,output      wire       [1:0]    client0_tlp_vfunc_num
    ,output      wire       [1:0]    client0_tlp_ats
    ,output      wire       [7:0]    client0_tlp_st
    ,output      wire                client0_tlp_vfunc_active
    ,output      wire                client0_tlp_nw
    ,output      wire                client0_tlp_th
    ,output      wire       [1:0]    client0_tlp_ph
    ,output      wire                client0_tlp_atu_bypass
    ,output      wire       [9:0]    client0_cpl_lookup_id
    ,(*MARK_DEBUG = "TRUE" *)input       wire                xadm_client0_halt

    //---axi rq bus interface-------------------------------//
    ,input       wire                s_axis_rq_tvalid
    ,output      wire                s_axis_rq_tready
    ,input       wire       [DATA_WIDTH-1:0]   s_axis_rq_tdata
    ,input       wire       [DW_WIDTH-1:0]     s_axis_rq_tkeep
    ,input       wire                          s_axis_rq_tlast
    ,input       wire       [USER_WIDTH-1:0]   s_axis_rq_tuser

    //---only for debug---------------------------------------//
    ,output      wire       [4:0]    client02rq_tuser_o
    ,output      wire                msix_sent_o
    ,output      wire       [3:0]    client02rq_debug

);

// ====================================================================
// Parameter/wire/reg
// ====================================================================

    // state machine define and macro
    reg     [4:0]   client02rq_state                    ;
    localparam      CLIENT02RQ_IDLE  =   5'b00001       ,
                    CLIENT02RQ_HEAD0 =   5'b00010       ,
                    CLIENT02RQ_HEAD1 =   5'b00100       ,
                    CLIENT02RQ_DATA  =   5'b01000       ,
                    CLIENT02RQ_END   =   5'b10000       ;

    // internal register and combination siangls
    reg             local_rq_rst_n                      ;
    reg             fifo_rq_wr_en                       ;
    reg             fifo_rq_wr_en_ff                    ;
    reg   [DATA_WIDTH+DW_WIDTH+26:0]   fifo_rq_wr_din;
    reg   [DATA_WIDTH+DW_WIDTH+26:0]   fifo_rq_wr_din_ff;
    wire            fifo_rq_rd_en                       ;
    wire  [DATA_WIDTH+DW_WIDTH+26:0]   fifo_rq_rd_dout;
    reg   [DATA_WIDTH+DW_WIDTH+26:0]   fifo_rq_rd_dout_ff;
    (*MARK_DEBUG = "TRUE" *)wire            fifo_rq_empty_flag                  ;
    wire            fifo_rq_full_flag                   ;

    reg             fifo_rq_pkg_wr                      ;
    reg             fifo_rq_pkg_rd                      ;
    reg   [9:0]     fifo_rq_pkg_cnt                     ;

    reg   [1:0]     rq_fifo_read_end_cnt                ;
    reg             fifo_rq_rd_en_reg                   ;
    reg             fifo_rq_rd_en_latch                 ;
    reg   [3:0]     clinet0_req_type                    ;
    reg             client0_addr_32_64                  ;
    reg   [63:0]    client0_addr_latch                  ;
    reg             client0_req_last                    ;
    reg             client02rq_first_pkg                ;

// ====================================================================
// PipeLine
// ====================================================================
always@(posedge core_clk)
begin
    // fifo side
    fifo_rq_wr_en_ff <= fifo_rq_wr_en ;
    fifo_rq_wr_din_ff<= fifo_rq_wr_din;
end

// ====================================================================
// Main Code
// ====================================================================
// reset localization
always@(posedge core_clk or negedge core_rst_n)
begin
    if(!core_rst_n)
        local_rq_rst_n <= 1'b0;
    else
        local_rq_rst_n <= 1'b1;
end

// write head and pure data into fifo
always@(posedge core_clk or negedge local_rq_rst_n )
begin
    if(!local_rq_rst_n)begin
        fifo_rq_wr_en <= 1'b0;
    end else if(s_axis_rq_tready & s_axis_rq_tvalid ) begin
        fifo_rq_wr_en <= 1'b1;
    end else begin
        fifo_rq_wr_en <= 1'b0;
    end
end

// write data into fifo, not need reset
always@(posedge core_clk )
begin
    if(s_axis_rq_tready & s_axis_rq_tvalid) begin
        fifo_rq_wr_din <= {11'b0,s_axis_rq_tuser[12:8],s_axis_rq_tuser[7:4],s_axis_rq_tuser[3:0],s_axis_rq_tkeep[DW_WIDTH-1:0],3'b0,s_axis_rq_tlast,s_axis_rq_tdata[DATA_WIDTH-1:0]};  // {last be, first be , keep,last , end , data}
    end
end

// pull up when write whole tlp into fifo
always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n)begin
        fifo_rq_pkg_wr <= 1'b0;
    end else if(s_axis_rq_tready & s_axis_rq_tvalid & s_axis_rq_tlast) begin
        fifo_rq_pkg_wr <= 1'b1;
    end else begin
        fifo_rq_pkg_wr <= 1'b0;
    end
end

// pull up when read whole tlp out from fifo
always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n)begin
        fifo_rq_pkg_rd <= 1'b0;
    //end else if(client02rq_state ==CLIENT02RQ_HEAD0) begin
end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
        fifo_rq_pkg_rd <= 1'b1;
    end else begin
        fifo_rq_pkg_rd <= 1'b0;
    end
end

// count the total tlp num in fifo
always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n) begin
        fifo_rq_pkg_cnt <= 'd0;
    end else begin
        case({fifo_rq_pkg_rd,fifo_rq_pkg_wr})
            2'b01: begin
                fifo_rq_pkg_cnt <= fifo_rq_pkg_cnt + 1'b1;
            end
            2'b10: begin
                fifo_rq_pkg_cnt <= fifo_rq_pkg_cnt - 1'b1;
            end
        // when both rd and wr at same cycle , we do nothing
        default : fifo_rq_pkg_cnt <= fifo_rq_pkg_cnt;
        endcase
    end
end

// set s_axis_rq_tready for back pressure
assign  s_axis_rq_tready = (!fifo_rq_full_flag);
sfifo #(
//  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( DATA_WIDTH == 128 ? 160 : 96 ),
  .DATA_WIDTH_R       ( DATA_WIDTH == 128 ? 160 : 96 ),
  .ADDR_WIDTH_W       ( 9    ),
  .ADDR_WIDTH_R       ( 9    ),
  .AL_FULL_NUM        ( 502  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u0_client02rq_fifo(
  .rst                (!local_rq_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (fifo_rq_wr_en_ff     ),   
  .di                 (fifo_rq_wr_din_ff ),   
  .re                 (fifo_rq_rd_en        ),  
  .dout               (fifo_rq_rd_dout   ),   
  .valid              (),   
  .full_flag          (),   
  .empty_flag         (fifo_rq_empty_flag   ),   
  .afull              (fifo_rq_full_flag    ),  
  .aempty             (),   
  .wrusedw            (),   
  .rdusedw            ()    
  );

// read fifo data out and repackage to client0 data
generate if ( DATA_WIDTH == 128 ) begin: PH1A400_STATE

always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n)begin
        client02rq_state <= CLIENT02RQ_IDLE;
    end else begin
        case(client02rq_state)
            // wait fifo at least one tlp package
            CLIENT02RQ_IDLE:begin
                if((|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) )
                    //client02rq_state <= CLIENT02RQ_HEAD0;
                    client02rq_state <= CLIENT02RQ_DATA;
            end
            // read tlp header out first
            CLIENT02RQ_HEAD0:begin
                    client02rq_state <= CLIENT02RQ_DATA;
            end
            // transfer pure data
            CLIENT02RQ_DATA:begin
                if((client0_tlp_dv | client0_tlp_hv) & client0_tlp_eot & (!xadm_client0_halt)) begin
                    //client02rq_state <= CLIENT02RQ_END;
		    client02rq_state <= CLIENT02RQ_IDLE;
                end
            end
            // delay a few tap, wait fifo  and pkg count ready
            //CLIENT02RQ_END:begin
            //    if(rq_fifo_read_end_cnt[1]==1'b1)begin
            //        client02rq_state <= CLIENT02RQ_IDLE;
            //    end
            //end

        default:client02rq_state <= CLIENT02RQ_IDLE;
        endcase
    end
end
end else  begin: PH1A100_STATE

always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n)begin
        client02rq_state <= CLIENT02RQ_IDLE;
    end else begin
        case(client02rq_state)
            // wait fifo at least one tlp package
            CLIENT02RQ_IDLE:begin
                if((|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) )
                    client02rq_state <= CLIENT02RQ_HEAD1;
            end
            // read tlp header out first
            CLIENT02RQ_HEAD0: begin
                    client02rq_state <= CLIENT02RQ_HEAD1;
            end
            CLIENT02RQ_HEAD1:begin
                    client02rq_state <= CLIENT02RQ_DATA;
            end
            // transfer pure data
            CLIENT02RQ_DATA:begin
                if((client0_tlp_dv | client0_tlp_hv) & client0_tlp_eot & (!xadm_client0_halt)) begin
                    //client02rq_state <= CLIENT02RQ_END;
		    client02rq_state <= CLIENT02RQ_IDLE;
                end
            end
            // delay a few tap, wait fifo  and pkg count ready
            //CLIENT02RQ_END:begin
             //   if(rq_fifo_read_end_cnt[1]==1'b1)begin
              //      client02rq_state <= CLIENT02RQ_IDLE;
              //  end
           // end

        default:client02rq_state <= CLIENT02RQ_IDLE;
        endcase
    end
end
end
endgenerate

always@(posedge core_clk ) 
begin
    if(fifo_rq_rd_en)
        fifo_rq_rd_dout_ff <=  fifo_rq_rd_dout;    
    else 
        fifo_rq_rd_dout_ff <=  fifo_rq_rd_dout_ff;             
end
// combination type of fifo rd en
generate begin
if ( DATA_WIDTH == 128 ) begin: PH1A400
    always@(*) begin
        if(client0_tlp_dv & !xadm_client0_halt & (!client0_tlp_eot) & (!fifo_rq_empty_flag)) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else if( client02rq_state ==CLIENT02RQ_DATA & client02rq_first_pkg & (!fifo_rq_rd_dout_ff[DATA_WIDTH]) & (!fifo_rq_empty_flag)) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else  begin
            fifo_rq_rd_en_latch = 1'b0;
        end
    end
end else begin: PH1A100
    always@(*) begin
        if(client0_tlp_dv && !xadm_client0_halt && (!client0_tlp_eot) && (!fifo_rq_empty_flag)) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else if( ((client02rq_state == CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag)) || 
                     ( client02rq_state == CLIENT02RQ_HEAD1 ) ) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else if( client02rq_state == CLIENT02RQ_DATA && client02rq_first_pkg && (!fifo_rq_rd_dout_ff[DATA_WIDTH]) && (!fifo_rq_empty_flag)) begin
            fifo_rq_rd_en_latch = 1'b1;
        end else  begin
            fifo_rq_rd_en_latch = 1'b0;
        end
    end
end
end
endgenerate

assign  fifo_rq_rd_en =  fifo_rq_rd_en_latch;

// client0 bus tlp header misc signals
generate if ( DATA_WIDTH == 128 ) begin: PH1A400_FF
always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n) begin
        client0_tlp_byte_en     <= 'd0;
        client0_remote_req_id   <= 'd0;
        client0_tlp_tc          <= 'd0;
        client0_tlp_attr        <= 'd0;
        client0_tlp_tid         <= 'd0;
        client0_tlp_byte_len    <= 'd0;
        client0_tlp_func_num    <= 'd0;
        // calculate fmt/addr/type
        clinet0_req_type        <= 'd0;
        client0_req_last        <= 'd0;
        client0_addr_32_64      <= 'd0;
        client0_addr_latch      <= 'd0;
    //end else if( client02rq_state ==CLIENT02RQ_HEAD0 ) begin // get the tlp header from fifo
    end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
        client0_tlp_byte_en     <= {fifo_rq_rd_dout[143:140],fifo_rq_rd_dout[139:136]}; // {last be,first be}
        client0_remote_req_id   <= fifo_rq_rd_dout[119:104];                            // for mem/io request, means local request id
        client0_tlp_tc          <= fifo_rq_rd_dout[123:121];                            // transaction class
        client0_tlp_attr        <= fifo_rq_rd_dout[126:124];
        client0_tlp_tid         <= {2'd0,fifo_rq_rd_dout[103:96]};                      // tag
        client0_tlp_byte_len    <= {fifo_rq_rd_dout[74:64], 2'b0};                      // dw count --> byte len
        client0_tlp_func_num    <= fifo_rq_rd_dout[82:80];
        // calculate fmt/addr/type
        clinet0_req_type        <= fifo_rq_rd_dout[78:75];
        client0_req_last        <= fifo_rq_rd_dout[128];
        client0_addr_32_64      <= (|fifo_rq_rd_dout[63:32]);
        client0_addr_latch      <= fifo_rq_rd_dout[63:0];
    end
end
end else begin: PH1A100_FF

always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n) begin
        client0_tlp_byte_en     <= 'd0;
        client0_remote_req_id   <= 'd0;
        client0_tlp_tc          <= 'd0;
        client0_tlp_attr        <= 'd0;
        client0_tlp_tid         <= 'd0;
        client0_tlp_byte_len    <= 'd0;
        client0_tlp_func_num    <= 'd0;
        // calculate fmt/addr/type
        clinet0_req_type        <= 'd0;
        client0_req_last        <= 'd0;
        client0_addr_32_64      <= 'd0;
        client0_addr_latch      <= 'd0;
    //end else if( client02rq_state ==CLIENT02RQ_HEAD0 ) begin // get the tlp header from fifo
    end else if( (client02rq_state ==CLIENT02RQ_IDLE) && (|fifo_rq_pkg_cnt==1'b1) && (!fifo_rq_empty_flag) ) begin
        client0_tlp_byte_en     <= {fifo_rq_rd_dout[77:74],fifo_rq_rd_dout[73:70]}; // {last be,first be}
        // calculate fmt/addr/type
        client0_addr_32_64      <= (|fifo_rq_rd_dout[63:32]);
        client0_addr_latch      <= fifo_rq_rd_dout[63:0];
    end else if ( client02rq_state == CLIENT02RQ_HEAD1 ) begin
        client0_req_last        <= fifo_rq_rd_dout[64];
        client0_remote_req_id   <= fifo_rq_rd_dout[55:40];                            // for mem/io request, means local request id
        client0_tlp_tc          <= fifo_rq_rd_dout[59:57];                            // transaction class
        clinet0_req_type        <= fifo_rq_rd_dout[14:11];
        client0_tlp_attr        <= fifo_rq_rd_dout[62:60];
        client0_tlp_tid         <= {2'd0,fifo_rq_rd_dout[39:32]};                      // tag
        client0_tlp_byte_len    <= {fifo_rq_rd_dout[10:0], 2'b0};                      // dw count --> byte len
        client0_tlp_func_num    <= fifo_rq_rd_dout[42:40];
    end
end
end
endgenerate
// client0 bus tlp header fmt/addr/type signals
always@(posedge core_clk)
begin
    if(client02rq_first_pkg) begin
        case(clinet0_req_type[3:0])
            // mem read req
            4'b0000 : begin
                    client0_tlp_addr <= client0_addr_latch[63:0];
                    client0_tlp_type <= 5'b0_0000;
                    if(client0_addr_32_64) // 4DW
                        client0_tlp_fmt <= 2'b01;
                    else                   // 3DW
                        client0_tlp_fmt <= 2'b00;
            end
            // mem write req
            4'b0001 : begin
                    client0_tlp_addr <= client0_addr_latch[63:0];
                    client0_tlp_type <= 5'b0_0000;
                    if(client0_addr_32_64) // 4DW
                        client0_tlp_fmt <= 2'b11;
                    else                   // 3DW
                        client0_tlp_fmt <= 2'b10;
            end
            // IO read req
            4'b0010 : begin
                    client0_tlp_addr <= {32'd0, client0_addr_latch[31:0]};
                    client0_tlp_type <= 5'b0_0010;
                    client0_tlp_fmt  <= 2'b00;
            end
            // IO write req
            4'b0011 : begin
                    client0_tlp_addr <= {32'd0, client0_addr_latch[31:0]};
                    client0_tlp_type <= 5'b0_0010;
                    client0_tlp_fmt  <= 2'b10;
            end
            //memory Fetch and add request
            4'b0100 : begin end
            //memory unconditional swap request
            4'b0101 : begin end
            //memory compare and swap request
            4'b0110 : begin end
            //locked read request
            4'b0111 : begin
                    client0_tlp_addr <= client0_addr_latch[63:0];
                    client0_tlp_type <= 5'b0_0001;
                    if(client0_addr_32_64) // 4DW
                        client0_tlp_fmt <= 2'b01;
                    else                   // 3DW
                        client0_tlp_fmt <= 2'b00;
            end
            // type0 cfg read req
            4'b1000 : begin
                    client0_tlp_addr <= {32'b0,client0_remote_req_id[15:0] ,4'b0,client0_addr_latch[11:2],2'b00};// {32'd0, ep_bdf[15:0], 4'd0, cfg0w_addr[11:2], 2'b00}
                    client0_tlp_type <= 5'b0_0100;
                    client0_tlp_fmt  <= 2'b00;
            end
            // type1 cfg read req
            4'b1001 : begin
                    client0_tlp_addr <= {32'b0,client0_remote_req_id[15:0] ,4'b0,client0_addr_latch[11:2],2'b00};// {32'd0, ep_bdf[15:0], 4'd0, cfg0w_addr[11:2], 2'b00}
                    client0_tlp_type <= 5'b0_0101;
                    client0_tlp_fmt  <= 2'b00;
            end
            // type0 cfg write req
            4'b1010 : begin
                    client0_tlp_addr <= {32'b0,client0_remote_req_id[15:0] ,4'b0,client0_addr_latch[11:2],2'b00};// {32'd0, ep_bdf[15:0], 4'd0, cfg0w_addr[11:2], 2'b00}
                    client0_tlp_type <= 5'b0_0100;
                    client0_tlp_fmt  <= 2'b10;
            end
            // type1 cfg write req
            4'b1011 : begin
                    client0_tlp_addr <= {32'b0,client0_remote_req_id[15:0] ,4'b0,client0_addr_latch[11:2],2'b00};// {32'd0, ep_bdf[15:0], 4'd0, cfg0w_addr[11:2], 2'b00}
                    client0_tlp_type <= 5'b0_0101;
                    client0_tlp_fmt  <= 2'b10;
            end
            // others do not support
            default : ;
        endcase
    end
end

// client0 bus hv/dv/eot/data signals
always@(posedge core_clk or negedge local_rq_rst_n)
begin
    if(!local_rq_rst_n) begin
        client0_tlp_dv       <= 1'b0;
        client0_tlp_hv       <= 1'b0;
        client0_tlp_eot      <= 1'b0;
        client02rq_first_pkg <= 1'b0;
    end else begin
        case(client02rq_state)
            CLIENT02RQ_IDLE:begin
                client0_tlp_dv       <= 1'b0;
                client0_tlp_hv       <= 1'b0;
                client0_tlp_eot      <= 1'b0;
                client02rq_first_pkg <= 1'b1;
            end
            CLIENT02RQ_DATA:begin
                client02rq_first_pkg <= 1'b0;
                // tlp_hv handle
                if(client0_tlp_hv & !xadm_client0_halt) begin
                    client0_tlp_hv   <= 1'b0;
                end else if(client02rq_first_pkg ) begin
                    client0_tlp_hv   <= 1'b1;
                end
                // tlp_eot handle
                if (client0_tlp_eot & !xadm_client0_halt) begin
                    client0_tlp_eot <= 1'b0;
                end else if( client02rq_first_pkg ) begin
                    client0_tlp_eot <= client0_req_last | (fifo_rq_rd_dout[DATA_WIDTH] & ~fifo_rq_empty_flag); // 1.without payload , 2. less than 4DW
                end else if(client0_tlp_dv & !xadm_client0_halt) begin
                    client0_tlp_eot <= (fifo_rq_rd_dout[DATA_WIDTH] & ~fifo_rq_empty_flag) ;
                end
                // tlp_dv handle
                if(client0_tlp_eot & !xadm_client0_halt) begin
                    client0_tlp_dv   <= 1'b0;
                end else if(client02rq_first_pkg & !client0_req_last )begin
                    client0_tlp_dv   <= 1'b1;
                end
            end
        endcase
    end
end

// no need reset for data bus
always@(posedge core_clk)
begin
    if(fifo_rq_rd_en) begin
        client0_tlp_data <= fifo_rq_rd_dout[DATA_WIDTH-1:0];
    end
end

// client0 bus tlp not used signals
assign  client0_addr_align_en   = 1'b0;
assign  client0_cpl_byte_cnt    = 12'd0;    // cpl byte count,  not used in rq
assign  client0_cpl_status      = 3'd0;     // cpl status,  not used in rq
assign  client0_cpl_bcm         = 1'b0;     // cpl bcm, not used in rq
assign  client0_tlp_bad_eot     = 1'b0;     // do not stop current tlp
assign  client0_tlp_td          = 1'b0;     // do not support
assign  client0_tlp_ep          = 1'b0;     // do not support
assign  client0_tlp_vfunc_num   = 2'b0;     // do not support
assign  client0_tlp_vfunc_active= 1'b0;     // do not support
assign  client0_tlp_ats         = 'd0;      // do not support
assign  client0_tlp_st          = 'd0;      // do not support
assign  client0_tlp_nw          = 'd0;      // do not support
assign  client0_tlp_th          = 'd0;      // do not support
assign  client0_tlp_ph          = 'd0;      // do not support
assign  client0_tlp_atu_bypass  = 1'b1;     // do not support
assign  client0_cpl_lookup_id   = 'd0;      // do not support

//add control signal by flsun
generate if(DATA_WIDTH==128) begin : USR_CTRL_128BIT_BLK
    reg     [4:0]   user_ctl;
    reg     [4:0]   user_ctl_send;
    reg             msix_sent;
    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            user_ctl        <= 'd0;
        end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
            user_ctl                <= fifo_rq_rd_dout[148:144];
        end
    end
    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            user_ctl_send   <= 5'b0;                
        end else if( client0_tlp_eot & !xadm_client0_halt  ) begin
            user_ctl_send   <= user_ctl;                
        end else begin
            user_ctl_send   <= 5'b0;                
        end
    end
    assign  client02rq_tuser_o = user_ctl_send;


    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            msix_sent       <= 'd0;
        end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
            msix_sent       <= fifo_rq_rd_dout[148];
        end else begin
            msix_sent       <= 1'b0;                
        end
    end
    assign  msix_sent_o = msix_sent;
end else begin : USR_CTRL_64BIT_BLK
    reg     [4:0]   user_ctl;
    reg     [4:0]   user_ctl_send;
    reg             msix_sent;
    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            user_ctl        <= 'd0;
        end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
            user_ctl                <= fifo_rq_rd_dout[82:78];
        end
    end
    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            user_ctl_send   <= 5'b0;                
        end else if( client0_tlp_eot & !xadm_client0_halt  ) begin
            user_ctl_send   <= user_ctl;                
        end else begin
            user_ctl_send   <= 5'b0;                
        end
    end
    assign  client02rq_tuser_o = user_ctl_send;


    always@(posedge core_clk or negedge local_rq_rst_n)
    begin
        if(!local_rq_rst_n) begin
            msix_sent       <= 'd0;
        end else if( (client02rq_state ==CLIENT02RQ_IDLE) & (|fifo_rq_pkg_cnt==1'b1) & (!fifo_rq_empty_flag) ) begin
            msix_sent       <= fifo_rq_rd_dout[82];
        end else begin
            msix_sent       <= 1'b0;                
        end
    end
    assign  msix_sent_o = msix_sent;

end 
endgenerate

endmodule

