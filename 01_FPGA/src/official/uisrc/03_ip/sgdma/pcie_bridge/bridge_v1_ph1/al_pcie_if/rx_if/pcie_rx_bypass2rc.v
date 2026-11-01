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
//          native radm bypass interface convert to requester completion
//          interface
//
// Email       :
//
// ===========================================================================

`timescale 1ns/1ns
`default_nettype none

module  pcie_rx_bypass2rc#(
    parameter DATA_WIDTH = 128,
    parameter DW_WIDTH   = 4,
    parameter USER_WIDTH = 75
)(

    //---system clock and reset------------------------------//
     input      wire                core_clk
    ,input      wire                core_rst_n

    //---native radm bypass interface------------------------//
    ,input      wire        [DATA_WIDTH-1:0]    radm_bypass_data
    ,input      wire        [DW_WIDTH-1:0]      radm_bypass_dwen
    ,input      wire                radm_bypass_dv
    ,input      wire                radm_bypass_hv
    ,input      wire                radm_bypass_eot
    ,input      wire                radm_bypass_dllp_abort
    ,input      wire                radm_bypass_tlp_abort
    ,input      wire                radm_bypass_ecrc_err
    ,input      wire        [63:0]  radm_bypass_addr
    ,input      wire        [1:0]   radm_bypass_fmt
    ,input      wire        [2:0]   radm_bypass_tc
    ,input      wire        [2:0]   radm_bypass_attr
    ,input      wire        [15:0]  radm_bypass_reqid
    ,input      wire        [4:0]   radm_bypass_type
    ,input      wire        [9:0]   radm_bypass_tag
    ,input      wire                radm_bypass_func_num
    ,input      wire        [1:0]   radm_bypass_vfunc_num
    ,input      wire                radm_bypass_vfunc_active
    ,input      wire                radm_bypass_td
    ,input      wire                radm_bypass_poisoned
    ,input      wire        [9:0]   radm_bypass_dw_len
    ,input      wire                radm_bypass_rom_in_range
    ,input      wire        [3:0]   radm_bypass_first_be
    ,input      wire        [3:0]   radm_bypass_last_be
    ,input      wire                radm_bypass_io_req_in_range
    ,input      wire        [2:0]   radm_bypass_in_membar_range
    ,input      wire                radm_bypass_cpl_last
    ,input      wire        [2:0]   radm_bypass_cpl_status
    ,input      wire        [7:0]   radm_bypass_st
    ,input      wire        [15:0]  radm_bypass_cmpltr_id
    ,input      wire        [11:0]  radm_bypass_byte_cnt
    ,input      wire        [1:0]   radm_bypass_ats
    ,input      wire                radm_bypass_th
    ,input      wire        [1:0]   radm_bypass_ph
    ,input      wire                radm_bypass_bcm

    //---convert requester completion package------------------//
    ,output     wire        [DATA_WIDTH-1:0]    m_axis_rc_tdata
    ,output     wire        [DW_WIDTH-1:0]      m_axis_rc_tkeep
    ,output     wire                            m_axis_rc_tlast
    ,output     wire        [USER_WIDTH-1:0]    m_axis_rc_tuser
    ,output     wire                            m_axis_rc_tvalid
    ,input      wire                            m_axis_rc_tready               // must be set 1

    //---only for debug---------------------------------------//
    ,output     wire        [3:0]   bypass2rc_debug
);


// ====================================================================
// Parameter/wire/reg
// ====================================================================
    //---state machine define and macro------------------------------//
    reg     [3:0]   bypass2rc_state             ;
    localparam      BYPASS2RC_IDLE  =   4'b0001 ,
                    BYPASS2RC_HEAD  =   4'b0010 ,
                    BYPASS2RC_DATA  =   4'b0100 ,
                    BYPASS2RC_END   =   4'b1000 ;

    //---internal register and combination siangls-------------------//
    reg             local_rc_rst_n                  ;
    //data fifo
    reg             fifo_rc_wr_en                   ;
    reg             fifo_rc_wr_en_ff                ;
    reg     [DATA_WIDTH:0] fifo_rc_wr_din=0 ;
    reg     [DATA_WIDTH:0] fifo_rc_wr_din_ff=0  ;
    wire            fifo_rc_rd_en                   ;
    wire    [DATA_WIDTH:0] fifo_rc_rd_dout  ;
    reg     [DATA_WIDTH:0] fifo_rc_rd_dout_ff ;
    reg             fifo_rc_rd_en_reg               ;
    reg             fifo_rc_rd_en_latch             ;
    // reg             fifo_rc_rd_en_done              ;
    // header fifo
    reg             fifo_rc_hv_wr_en                ;
    reg             fifo_rc_hv_wr_en_ff             ;
    reg     [159:0] fifo_rc_hv_wr_din=0             ;
    reg     [159:0] fifo_rc_hv_wr_din_ff=0          ;
    reg             fifo_rc_hv_rd_en                ;
    wire    [159:0] fifo_rc_hv_rd_dout              ;
    reg     [159:0] fifo_rc_hv_rd_dout_ff=0         ;
    wire            fifo_rc_hv_empty_flag           ;
    
    wire            bypass2rc_last_delay            ;
    reg             bypass2rc_last_delay_comb       ;
    reg             bypass2rc_last_delay_reg        ;
    wire    [1:0]   bypass2rc_end_offset            ;
    reg     [DW_WIDTH-1:0]    bypass2rc_end_keep  ;
    wire    [DATA_WIDTH/8-1:0]bypass2rc_byte_en ;

    reg     [DATA_WIDTH-1:0] m_axis_rc_tdata_ff              ;
    reg     [DW_WIDTH-1:0]   m_axis_rc_tkeep_ff              ;
    reg             m_axis_rc_tlast_ff              ;
    reg     [74:0]  m_axis_rc_tuser_ff              ;
    reg             m_axis_rc_tvalid_ff             ;
    //---pipepline register for timing-------------------------------//
    reg     [DATA_WIDTH-1:0] radm_bypass_data_ff            ;
    reg     [DW_WIDTH-1:0]   radm_bypass_dwen_ff            ;
    reg             radm_bypass_dv_ff              ;
    reg             radm_bypass_hv_ff              ;
    reg             radm_bypass_eot_ff             ;
    reg             radm_bypass_dllp_abort_ff      ;
    reg             radm_bypass_tlp_abort_ff       ;
    reg             radm_bypass_ecrc_err_ff        ;
    reg     [63:0]  radm_bypass_addr_ff            ;
    reg     [1:0]   radm_bypass_fmt_ff             ;
    reg     [2:0]   radm_bypass_tc_ff              ;
    reg     [2:0]   radm_bypass_attr_ff            ;
    reg     [15:0]  radm_bypass_reqid_ff           ;
    reg     [4:0]   radm_bypass_type_ff            ;
    reg     [9:0]   radm_bypass_tag_ff             ;
    reg             radm_bypass_func_num_ff        ;
    reg     [1:0]   radm_bypass_vfunc_num_ff       ;
    reg             radm_bypass_vfunc_active_ff    ;
    reg             radm_bypass_td_ff              ;
    reg             radm_bypass_poisoned_ff        ;
    reg     [9:0]   radm_bypass_dw_len_ff          ;
    reg             radm_bypass_rom_in_range_ff    ;
    reg     [3:0]   radm_bypass_first_be_ff        ;
    reg     [3:0]   radm_bypass_last_be_ff         ;
    reg             radm_bypass_io_req_in_range_ff ;
    reg     [2:0]   radm_bypass_in_membar_range_ff ;
    reg             radm_bypass_cpl_last_ff        ;
    reg     [2:0]   radm_bypass_cpl_status_ff      ;
    reg     [7:0]   radm_bypass_st_ff              ;
    reg     [15:0]  radm_bypass_cmpltr_id_ff       ;
    reg     [11:0]  radm_bypass_byte_cnt_ff        ;
    reg     [1:0]   radm_bypass_ats_ff             ;
    reg             radm_bypass_th_ff              ;
    reg     [1:0]   radm_bypass_ph_ff              ;
    reg             radm_bypass_bcm_ff             ;

// ====================================================================
// PipeLine
// ====================================================================
always@(posedge core_clk )
begin
    // radm bypass pipeline
    radm_bypass_data_ff            <=  radm_bypass_data            ;
    radm_bypass_dwen_ff            <=  radm_bypass_dwen            ;
    radm_bypass_dv_ff              <=  radm_bypass_dv              ;
    radm_bypass_hv_ff              <=  radm_bypass_hv              ;
    radm_bypass_eot_ff             <=  radm_bypass_eot             ;
    radm_bypass_dllp_abort_ff      <=  radm_bypass_dllp_abort      ;
    radm_bypass_tlp_abort_ff       <=  radm_bypass_tlp_abort       ;
    radm_bypass_ecrc_err_ff        <=  radm_bypass_ecrc_err        ;
    radm_bypass_addr_ff            <=  radm_bypass_addr            ;
    radm_bypass_fmt_ff             <=  radm_bypass_fmt             ;
    radm_bypass_tc_ff              <=  radm_bypass_tc              ;
    radm_bypass_attr_ff            <=  radm_bypass_attr            ;
    radm_bypass_reqid_ff           <=  radm_bypass_reqid           ;
    radm_bypass_type_ff            <=  radm_bypass_type            ;
    radm_bypass_tag_ff             <=  radm_bypass_tag             ;
    radm_bypass_func_num_ff        <=  radm_bypass_func_num        ;
    radm_bypass_vfunc_num_ff       <=  radm_bypass_vfunc_num       ;
    radm_bypass_vfunc_active_ff    <=  radm_bypass_vfunc_active    ;
    radm_bypass_td_ff              <=  radm_bypass_td              ;
    radm_bypass_poisoned_ff        <=  radm_bypass_poisoned        ;
    radm_bypass_dw_len_ff          <=  radm_bypass_dw_len          ;
    radm_bypass_rom_in_range_ff    <=  radm_bypass_rom_in_range    ;
    radm_bypass_first_be_ff        <=  radm_bypass_first_be        ;
    radm_bypass_last_be_ff         <=  radm_bypass_last_be         ;
    radm_bypass_io_req_in_range_ff <=  radm_bypass_io_req_in_range ;
    radm_bypass_in_membar_range_ff <=  radm_bypass_in_membar_range ;
    radm_bypass_cpl_last_ff        <=  radm_bypass_cpl_last        ;
    radm_bypass_cpl_status_ff      <=  radm_bypass_cpl_status      ;
    radm_bypass_st_ff              <=  radm_bypass_st              ;
    radm_bypass_cmpltr_id_ff       <=  radm_bypass_cmpltr_id       ;
    radm_bypass_byte_cnt_ff        <=  radm_bypass_byte_cnt        ;
    radm_bypass_ats_ff             <=  radm_bypass_ats             ;
    radm_bypass_th_ff              <=  radm_bypass_th              ;
    radm_bypass_ph_ff              <=  radm_bypass_ph              ;
    radm_bypass_bcm_ff             <=  radm_bypass_bcm             ;

    // fifo sginals
    fifo_rc_wr_en_ff               <= fifo_rc_wr_en                ;
    fifo_rc_wr_din_ff              <= fifo_rc_wr_din               ;
    fifo_rc_hv_wr_en_ff            <= fifo_rc_hv_wr_en             ;   
    fifo_rc_hv_wr_din_ff           <= fifo_rc_hv_wr_din            ;
end

// ====================================================================
// Main Code
// ====================================================================

// reset localization
always@(posedge core_clk or negedge core_rst_n)
begin
    if(!core_rst_n)
        local_rc_rst_n <= 1'b0;
    else
        local_rc_rst_n <= 1'b1;
end

// hv fifo wr en
always@(posedge core_clk or negedge local_rc_rst_n ) begin
    if(!local_rc_rst_n ) begin
        fifo_rc_hv_wr_en <= 1'b0;
    end else if( (radm_bypass_hv_ff|radm_bypass_dv_ff) & radm_bypass_eot_ff  ) begin  // write head into fifo
        fifo_rc_hv_wr_en <= 1'b1;
    end else begin
        fifo_rc_hv_wr_en <= 1'b0;
    end
end

always@(posedge core_clk) begin
    if( radm_bypass_hv_ff ) begin
        // DW4,expect header and pure data, include first/last be for tuers byte enable used
        fifo_rc_hv_wr_din[159:128] <= {
                                    radm_bypass_dwen_ff[DW_WIDTH-1:0]       , // dwen at eot
                                    7'b0                                    , // Reserved
                                    radm_bypass_eot_ff&(!radm_bypass_dv_ff) , // cpl eot
                                    6'b0                                    , // Reserved
                                    radm_bypass_fmt_ff[1:0]                 , // tlp_format
                                    radm_bypass_first_be_ff[3:0]            , // first_be
                                    radm_bypass_last_be_ff[3:0]               // last_be
                                   };
        // DW3, not used in cpl/cpld , only 3DW header
        fifo_rc_hv_wr_din[127:96] <= 32'b0;
        //DW2, RC bus header format
        fifo_rc_hv_wr_din[95:64]  <= {1'b0                                  , // Reserved
                                   radm_bypass_attr_ff[2:0]              , // Attributes
                                   radm_bypass_tc_ff[2:0]                , // Transcation class
                                   1'b0                                  , // Reserved
                                   radm_bypass_cmpltr_id_ff[15:0]        , // Completion ID
                                   radm_bypass_tag_ff[7:0]                 // Tag
                                  };
        //DW1,RC bus header format
        fifo_rc_hv_wr_din[63:32]  <= {radm_bypass_reqid_ff[15:0]            , // Requster ID
                                   1'b0                                  , // Reserved
                                   radm_bypass_poisoned_ff               , // Poisoned completion
                                   radm_bypass_cpl_status_ff[2:0]        , // Completion status
                                   {1'b0,radm_bypass_dw_len_ff[9:0]}       // Dowrd Count
                                  };

        // DW0,RC bus header format
        fifo_rc_hv_wr_din[31:0]  <= {1'b0                                    , // Reserved
                                   radm_bypass_cpl_last_ff                , // Requester completed
                                   1'b0                                   , // lock read
                                   {1'b0,radm_bypass_byte_cnt_ff[11:0]}   , // Byte count
                                   4'b0000                                , // Error code, not supprot
                                   radm_bypass_addr_ff[11:0]                // Lower address
                                  };
    end
end

// repackage tlp to internal signals and write to fifo
always@(posedge core_clk or negedge local_rc_rst_n ) begin
    if(!local_rc_rst_n ) begin
        fifo_rc_wr_en <= 1'b0;
    end else if( radm_bypass_dv_ff ) begin  // write data into fifo
        fifo_rc_wr_en <= 1'b1;
    end else begin
        fifo_rc_wr_en <= 1'b0;
    end
end

// write four dw data, include eot
always@(posedge core_clk) begin
    if( radm_bypass_dv_ff ) begin
        fifo_rc_wr_din[DATA_WIDTH]      <= radm_bypass_eot_ff;
        fifo_rc_wr_din[DATA_WIDTH-1:0]  <= radm_bypass_data_ff[DATA_WIDTH-1:0];
    end
end

wire    dbg_hv_full_flag;
wire    dbg_dv_full_flag;

sfifo #(
  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( 160  ),
  .DATA_WIDTH_R       ( 160  ),
  .ADDR_WIDTH_W       ( 9   ),
  .ADDR_WIDTH_R       ( 9   ),
  .AL_FULL_NUM        ( 500  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u0_bypass2rc_fifo_header(
  .rst                (!local_rc_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (fifo_rc_hv_wr_en_ff  ),   
  .di                 (fifo_rc_hv_wr_din_ff ),   
  .re                 (fifo_rc_hv_rd_en     ),  
  .dout               (fifo_rc_hv_rd_dout   ),   
  .valid              (),   
  .full_flag          (dbg_hv_full_flag),   
  .empty_flag         (fifo_rc_hv_empty_flag),   
  .afull              (),  
  .aempty             (),   
  .wrusedw            (),   
  .rdusedw            ()    
  );

sfifo #(
  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( DATA_WIDTH + 1  ),
  .DATA_WIDTH_R       ( DATA_WIDTH + 1  ),
  .ADDR_WIDTH_W       ( 9   ),
  .ADDR_WIDTH_R       ( 9   ),
  .AL_FULL_NUM        ( 500  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u1_bypass2rc_fifo_data(
  .rst                (!local_rc_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (fifo_rc_wr_en_ff     ),   
  .di                 (fifo_rc_wr_din_ff    ),   
  .re                 (fifo_rc_rd_en        ),  
  .dout               (fifo_rc_rd_dout      ),   
  .valid              (),   
  .full_flag          (dbg_dv_full_flag     ),   
  .empty_flag         (),   
  .afull              (),  
  .aempty             (),   
  .wrusedw            (),   
  .rdusedw            ()    
  );

wire    [95:0]  bypass2rc_header;
wire            bypass2rc_cpl_last;
wire    [9:0]   bypass2rc_cpld_dwlen;
wire            bypass2rc_dat_eot;
reg             bypass2rc_dat_eot_ff;
// reg     [1:0]   bypass2rc_cpld_dwlen_ff; 
assign  bypass2rc_cpl_last   = fifo_rc_hv_rd_dout[144];
assign  bypass2rc_header     = fifo_rc_hv_rd_dout[95:0];
assign  bypass2rc_cpld_dwlen = fifo_rc_hv_rd_dout[41:32];

reg     [95:0]  bypass2rc_header_ff;
reg             bypass2rc_cpl_last_ff=0;
reg     [9:0]   bypass2rc_cpld_dwlen_ff=0;
always@(posedge core_clk) begin
    if(fifo_rc_hv_rd_en) begin
        bypass2rc_header_ff     <= bypass2rc_header;
        bypass2rc_cpl_last_ff   <= bypass2rc_cpl_last;
        bypass2rc_cpld_dwlen_ff <= bypass2rc_cpld_dwlen;
    end 
end

assign  bypass2rc_dat_eot    = fifo_rc_rd_dout[DATA_WIDTH];

always@(posedge core_clk) begin
    if(fifo_rc_rd_en) begin
        fifo_rc_rd_dout_ff      <=  fifo_rc_rd_dout ;
        bypass2rc_dat_eot_ff    <=  bypass2rc_dat_eot ;
    end 
end 

always@(*) begin
    if( (bypass2rc_state==BYPASS2RC_IDLE) && !fifo_rc_hv_empty_flag )  // read tlp header out
        fifo_rc_hv_rd_en = 1'b1;
    else 
        fifo_rc_hv_rd_en = 1'b0;
end

always@(*) begin
    if( fifo_rc_hv_rd_en && !bypass2rc_cpl_last )  // read tlp header out
        fifo_rc_rd_en_reg = 1'b1;
    else 
        fifo_rc_rd_en_reg = 1'b0;
end
always@(*) begin
    if(bypass2rc_state==BYPASS2RC_DATA && !bypass2rc_dat_eot_ff)  // read tlp header out
        fifo_rc_rd_en_latch = 1'b1;
    else 
        fifo_rc_rd_en_latch = 1'b0;
end
assign  fifo_rc_rd_en = fifo_rc_rd_en_reg | fifo_rc_rd_en_latch;

// calculation the dw keep at eot
assign  bypass2rc_end_offset = bypass2rc_cpld_dwlen[1:0] + 2'b11;
generate if(DATA_WIDTH==128) begin : KEEP_CALC_128BIT
  always@(posedge core_clk or negedge local_rc_rst_n  ) begin
      if(!local_rc_rst_n ) begin
          bypass2rc_end_keep <= 4'b1111;
      end else if(fifo_rc_hv_rd_en) begin 
          case(bypass2rc_end_offset )
              2'b00: bypass2rc_end_keep <= 4'b1111;
              2'b01: bypass2rc_end_keep <= 4'b0001;
              2'b10: bypass2rc_end_keep <= 4'b0011;
              2'b11: bypass2rc_end_keep <= 4'b0111;
          default:;
          endcase
      end    
  end
  assign bypass2rc_byte_en = 16'hffff;
end else begin : KEEP_CALC_64BIT
  always@(posedge core_clk or negedge local_rc_rst_n  ) begin
      if(!local_rc_rst_n ) begin
          bypass2rc_end_keep <= 2'b11;
      end else if(fifo_rc_hv_rd_en) begin 
          case(bypass2rc_end_offset[0] )
              1'b0: bypass2rc_end_keep <= 2'b11;
              1'b1: bypass2rc_end_keep <= 2'b01;
          default : bypass2rc_end_keep <= 2'b11;
          endcase
      end    
  end
  assign bypass2rc_byte_en = 8'hff;
end 
endgenerate

generate if(DATA_WIDTH==128) begin : AXIS_128BIT
  always@(posedge core_clk or negedge local_rc_rst_n  ) begin
      if(!local_rc_rst_n ) begin
          m_axis_rc_tvalid_ff <= 1'b0;
          m_axis_rc_tlast_ff  <= 1'b0;
          m_axis_rc_tkeep_ff  <= 4'b0;
          m_axis_rc_tdata_ff  <= 0;
          m_axis_rc_tuser_ff  <= 0;

          bypass2rc_state     <= BYPASS2RC_IDLE   ;
      end else begin
          case(bypass2rc_state)
              BYPASS2RC_IDLE : begin
                  if(!fifo_rc_hv_empty_flag) begin
                      m_axis_rc_tkeep_ff  <= {!bypass2rc_cpl_last,3'b111};
                      m_axis_rc_tvalid_ff <= 1'b1;
                      m_axis_rc_tlast_ff  <= bypass2rc_cpl_last || (bypass2rc_cpld_dwlen == 4'h1);   // cpl package without data or cpld whitn only one DW
                      m_axis_rc_tdata_ff  <= {fifo_rc_rd_dout[31:0],bypass2rc_header};
                      m_axis_rc_tuser_ff  <= {16'b0,              //byte_en[31:16]
                                              bypass2rc_byte_en,  //byte_en[15: 0]
                                              1'b1,               //is_sof_0
                                              1'b0,               //is_sof_1
                                              4'b0,               //is_eof_0
                                              4'b0,               //is_eof_1
                                              1'b0,               //discontinue
                                              32'b0               //parity
                                              };

                      if(!bypass2rc_cpl_last && (bypass2rc_cpld_dwlen > 'd1)) 
                          bypass2rc_state <= BYPASS2RC_DATA   ;
                      else 
                          bypass2rc_state <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;
                  end else begin
                      m_axis_rc_tvalid_ff <= 1'b0;
                      m_axis_rc_tlast_ff  <= 1'b0;
                      m_axis_rc_tkeep_ff  <= 4'b0;
                  end
              end 
              BYPASS2RC_DATA : begin 
                  if(bypass2rc_cpld_dwlen_ff[1:0] == 'd1 && bypass2rc_dat_eot) 
                      bypass2rc_state     <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;
                  else if(bypass2rc_dat_eot_ff) 
                      bypass2rc_state     <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;
                  else 
                      bypass2rc_state     <= BYPASS2RC_DATA   ;

                  m_axis_rc_tdata_ff      <= {fifo_rc_rd_dout[31:0],fifo_rc_rd_dout_ff[127:32]} ;
                  m_axis_rc_tvalid_ff     <= 1'b1;

                  if(bypass2rc_cpld_dwlen_ff[1:0] == 'd1 && bypass2rc_dat_eot) 
                      m_axis_rc_tkeep_ff  <=  bypass2rc_end_keep;
                  else if(bypass2rc_dat_eot_ff) 
                      m_axis_rc_tkeep_ff  <=  bypass2rc_end_keep;
                  else 
                      m_axis_rc_tkeep_ff  <=  4'b1111;
                  
                  // tlast
                  if(bypass2rc_cpld_dwlen_ff[1:0] == 'd1 && bypass2rc_dat_eot) 
                      m_axis_rc_tlast_ff  <=  1'b1;
                  else if(bypass2rc_dat_eot_ff)
                      m_axis_rc_tlast_ff  <=  1'b1;
                  else 
                      m_axis_rc_tlast_ff  <= 1'b0;                             // the last data
              end 
              default : begin 
                  m_axis_rc_tvalid_ff     <= 1'b0;
                  m_axis_rc_tlast_ff      <= 1'b0;
                  m_axis_rc_tkeep_ff      <= 4'b0;
                  m_axis_rc_tdata_ff      <= 0;
                  m_axis_rc_tuser_ff      <= 0;
                  bypass2rc_state         <= BYPASS2RC_IDLE   ;
              end 
          endcase
      end 
  end 
end else begin : AXIS_64BIT
  always@(posedge core_clk or negedge local_rc_rst_n  ) begin
      if(!local_rc_rst_n ) begin
          m_axis_rc_tvalid_ff <= 1'b0;
          m_axis_rc_tlast_ff  <= 1'b0;
          m_axis_rc_tkeep_ff  <= 4'b0;
          m_axis_rc_tdata_ff  <= 0;
          m_axis_rc_tuser_ff  <= 0;

          bypass2rc_state     <= BYPASS2RC_IDLE   ;
      end else begin
          case(bypass2rc_state)
              BYPASS2RC_IDLE : begin
                  if(!fifo_rc_hv_empty_flag) begin
                      m_axis_rc_tkeep_ff  <= 2'b11;
                      m_axis_rc_tvalid_ff <= 1'b1;
                      m_axis_rc_tlast_ff  <= 1'b0;//bypass2rc_cpl_last || (bypass2rc_cpld_dwlen == 4'h1);   // cpl package without data or cpld whitn only one DW
                      m_axis_rc_tdata_ff  <= bypass2rc_header[63:0];
                      m_axis_rc_tuser_ff  <= {16'b0,              //byte_en[31:16]
                                              bypass2rc_byte_en,  //byte_en[15: 0]
                                              1'b1,               //is_sof_0
                                              1'b0,               //is_sof_1
                                              4'b0,               //is_eof_0
                                              4'b0,               //is_eof_1
                                              1'b0,               //discontinue
                                              32'b0               //parity
                                              };
                      bypass2rc_state     <= BYPASS2RC_HEAD   ;                        
                  end else begin
                      m_axis_rc_tvalid_ff <= 1'b0;
                      m_axis_rc_tlast_ff  <= 1'b0;
                      m_axis_rc_tkeep_ff  <= 4'b0;
                  end
              end 
              BYPASS2RC_HEAD : begin 
                    m_axis_rc_tkeep_ff  <= {!bypass2rc_cpl_last_ff,1'b1};
                    m_axis_rc_tvalid_ff <= 1'b1;
                    m_axis_rc_tdata_ff  <= {fifo_rc_rd_dout_ff[31:0],bypass2rc_header_ff[95:64]};
                    m_axis_rc_tlast_ff  <= bypass2rc_cpl_last_ff || (bypass2rc_cpld_dwlen_ff == 4'h1);
                    if(!bypass2rc_cpl_last_ff && (bypass2rc_cpld_dwlen_ff > 'd1)) 
                        bypass2rc_state <= BYPASS2RC_DATA   ;
                    else 
                        bypass2rc_state <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;                    
              end
              BYPASS2RC_DATA : begin 
                  if(bypass2rc_cpld_dwlen_ff[0] == 'd1 && bypass2rc_dat_eot) 
                      bypass2rc_state     <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;
                  else if(bypass2rc_dat_eot_ff) 
                      bypass2rc_state     <= BYPASS2RC_IDLE;//BYPASS2RC_END;//BYPASS2RC_IDLE   ;
                  else 
                      bypass2rc_state     <= BYPASS2RC_DATA   ;

                  m_axis_rc_tdata_ff      <= {fifo_rc_rd_dout[31:0],fifo_rc_rd_dout_ff[63:32]} ;
                  m_axis_rc_tvalid_ff     <= 1'b1;

                  if(bypass2rc_cpld_dwlen_ff[0] == 'd1 && bypass2rc_dat_eot) 
                      m_axis_rc_tkeep_ff  <=  bypass2rc_end_keep;
                  else if(bypass2rc_dat_eot_ff) 
                      m_axis_rc_tkeep_ff  <=  bypass2rc_end_keep;
                  else 
                      m_axis_rc_tkeep_ff  <=  2'b11;
                  
                  // tlast
                  if(bypass2rc_cpld_dwlen_ff[0] == 'd1 && bypass2rc_dat_eot) 
                      m_axis_rc_tlast_ff  <=  1'b1;
                  else if(bypass2rc_dat_eot_ff)
                      m_axis_rc_tlast_ff  <=  1'b1;
                  else 
                      m_axis_rc_tlast_ff  <= 1'b0;                             // the last data
              end 
              default : begin 
                  m_axis_rc_tvalid_ff     <= 1'b0;
                  m_axis_rc_tlast_ff      <= 1'b0;
                  m_axis_rc_tkeep_ff      <= 4'b0;
                  m_axis_rc_tdata_ff      <= 0;
                  m_axis_rc_tuser_ff      <= 0;
                  bypass2rc_state         <= BYPASS2RC_IDLE   ;
              end 
          endcase
      end 
  end 
end 
endgenerate


//---output axi bus---------------------------------//
assign      m_axis_rc_tdata     = m_axis_rc_tdata_ff;
assign      m_axis_rc_tkeep     = m_axis_rc_tkeep_ff;
assign      m_axis_rc_tlast     = m_axis_rc_tlast_ff;
assign      m_axis_rc_tuser     = m_axis_rc_tuser_ff;
assign      m_axis_rc_tvalid    = m_axis_rc_tvalid_ff;


//---debug used-------------------------------------//
assign      bypass2rc_debug     = 4'b0;

//debug
// reg     [7:0]   dbg_radm_bypass_tag;
// reg             dbg_radm_bypass_eot_d1;
// reg             dbg_radm_bypass_back2back;
// always@( posedge core_clk)
// begin
//     dbg_radm_bypass_eot_d1 <= radm_bypass_eot;
//     if( radm_bypass_hv) 
//         dbg_radm_bypass_tag <= radm_bypass_tag;

//     if(dbg_radm_bypass_eot_d1&&radm_bypass_hv) 
//         dbg_radm_bypass_back2back <= 1;
//     else 
//         dbg_radm_bypass_back2back <= 0;
// end 

// reg     [15:0]   dbg_radm_bypass_pktcnt;/*synthesis keep=1*/
// reg     [15:0]   dbg_axis_rc_pktcnt;/*synthesis keep=1*/
// reg              dbg_dv_full_flag_log;/*synthesis keep=1*/
// reg              dbg_hv_full_flag_log;/*synthesis keep=1*/
// always@( posedge core_clk)
// begin
//     if( radm_bypass_dv && radm_bypass_eot) 
//         dbg_radm_bypass_pktcnt <= dbg_radm_bypass_pktcnt + 1;

//     if( m_axis_rc_tvalid && m_axis_rc_tlast) 
//         dbg_axis_rc_pktcnt <= dbg_axis_rc_pktcnt + 1;    
// end 

// reg     [31:0]   dbg_bypass_wcnt;/*synthesis keep=1*/
// reg     [31:0]   dbg_bypass_rcnt;/*synthesis keep=1*/

// always @(posedge core_clk,negedge core_rst_n) begin
//     if(!core_rst_n) begin
//         dbg_dv_full_flag_log <= 0;
//         dbg_hv_full_flag_log <= 0;
//     end else  begin
//         if(dbg_dv_full_flag) 
//              dbg_dv_full_flag_log <= 1;
//         if(dbg_hv_full_flag) 
//              dbg_hv_full_flag_log <= 1;    
//     end
// end 

// always @(posedge core_clk,negedge core_rst_n) begin
//     if(!core_rst_n)
//         dbg_bypass_wcnt   <= 'd0;
//     else if(fifo_rc_wr_en_ff) 
//         dbg_bypass_wcnt   <= dbg_bypass_wcnt + 'd1;
// end 
// always @(posedge core_clk,negedge core_rst_n) begin
//     if(!core_rst_n)
//         dbg_bypass_rcnt   <= 'd0;
//     else if(fifo_rc_rd_en) 
//         dbg_bypass_rcnt   <= dbg_bypass_rcnt + 'd1;
// end 

endmodule

`default_nettype wire
