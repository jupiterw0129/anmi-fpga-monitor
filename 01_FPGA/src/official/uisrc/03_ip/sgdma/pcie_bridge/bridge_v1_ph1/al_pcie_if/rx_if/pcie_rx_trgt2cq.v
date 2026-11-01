
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
//          native trgt1_radm interface convert to completer request
//          interface
//
// Email       :
//
// ===========================================================================

`timescale 1ns/1ns
`default_nettype none


module pcie_rx_trgt2cq #(
    
    parameter DATA_WIDTH = 128,
    parameter DW_WIDTH   = 4,
    parameter USER_WIDTH = 88

)
(

    //---system clock and reset------------------------------//
     input      wire                core_clk
    ,input      wire                core_rst_n
    //---native trgt1 radm interface-------------------------//
    ,input      wire                radm_trgt1_dv
    ,input      wire                radm_trgt1_hv
    ,input      wire                radm_trgt1_eot
    ,input      wire                radm_trgt1_tlp_abort
    ,input      wire                radm_trgt1_dllp_abort
    ,input      wire                radm_trgt1_ecrc_err
    ,input      wire        [3:0]   radm_trgt1_dwen
    ,input      wire        [1:0]   radm_trgt1_fmt
    ,input      wire        [2:0]   radm_trgt1_attr
    ,input      wire                radm_trgt1_func_num
    ,input      wire        [4:0]   radm_trgt1_type
    ,input      wire        [2:0]   radm_trgt1_tc
    ,input      wire        [15:0]  radm_trgt1_reqid
    ,input      wire        [DATA_WIDTH-1:0] radm_trgt1_data
    ,input      wire        [3:0]   radm_trgt1_first_be
    ,input      wire        [3:0]   radm_trgt1_last_be
    ,input      wire        [63:0]  radm_trgt1_addr
    ,input      wire        [1:0]   radm_trgt1_vfunc_num
    ,input      wire                radm_trgt1_vfunc_active
    ,input      wire                radm_trgt1_td
    ,input      wire                radm_trgt1_poisoned
    ,input      wire                radm_trgt1_hdr_uppr_bytes_valid
    ,input      wire                radm_trgt1_rom_in_range
    ,input      wire                radm_trgt1_io_req_in_range
    ,input      wire        [63:0]  radm_trgt1_hdr_uppr_bytes
    ,input      wire        [2:0]   radm_trgt1_in_membar_range
    ,input      wire        [2:0]   radm_trgt1_cpl_status
    ,input      wire        [1:0]   radm_trgt1_ats
    ,input      wire        [9:0]   radm_trgt1_tag
    ,input      wire        [9:0]   radm_trgt1_dw_len
    ,input      wire                radm_trgt1_nw
    ,input      wire                radm_trgt1_th
    ,input      wire        [1:0]   radm_trgt1_ph
    ,input      wire        [7:0]   radm_trgt1_st
    ,input      wire        [11:0]  radm_trgt1_byte_cnt
    ,input      wire                radm_trgt1_bcm
    ,input      wire        [2:0]   radm_trgt1_vc
    ,input      wire        [15:0]  radm_trgt1_cmpltr_id
    ,input      wire                radm_trgt1_cpl_last
    ,input      wire        [2:0]   radm_grant_tlp_type
    ,input      wire        [1:0]   radm_trgt1_atu_sloc_match
    ,input      wire        [1:0]   radm_trgt1_atu_cbuf_err
    ,input      wire        [9:0]   trgt_lookup_id
    ,input      wire                trgt_lookup_empty
    ,output     wire                trgt1_radm_halt
    ,output     wire        [2:0]   trgt1_radm_pkt_halt
    //---make connection with cc when need look up id------//
    ,input      wire        [9:0]   rq_lookup_addr
    ,output     wire        [9:0]   rq_lookup_dout
    //---convert completer requester package --------------//
    ,output     wire                m_axis_cq_tvalid
    ,output     wire        [DATA_WIDTH-1:0] m_axis_cq_tdata
    ,output     wire        [DW_WIDTH-1:0]   m_axis_cq_tkeep
    ,output     wire                         m_axis_cq_tlast
    ,output     wire        [USER_WIDTH:0]   m_axis_cq_tuser
    ,input      wire                         m_axis_cq_tready

    //---only for debug---------------------------------------//
    ,output     wire        [3:0]   trgt2cq_debug
);



// ====================================================================
// Parameter/wire/reg
// ====================================================================
    //---state machine define and macro------------------------------//
    reg     [4:0]   trgt2cq_state                       ;
    localparam      TRGT2CQ_IDLE     =   5'b00001       ,
                    TRGT2CQ_HEAD0    =   5'b00010       ,
                    TRGT2CQ_HEAD1    =   5'b00100       ,
                    TRGT2CQ_DATA     =   5'b01000       ,
                    TRGT2CQ_END      =   5'b10000       ;

    //---internal register and combination siangls-------------------//
    reg             local_cq_rst_n                      ;
    reg     [31:0]  tlp_fifo_wrdw0                      ;
    reg     [31:0]  tlp_fifo_wrdw1                      ;
    reg     [31:0]  tlp_fifo_wrdw2                      ;
    reg     [31:0]  tlp_fifo_wrdw3                      ;
    reg     [31:0]  tlp_fifo_wrdw4                      ;
    reg             tlp_fifo_wren                       ;
    reg             tlp_fifo_rden                       ;
    wire    [DATA_WIDTH+31:0] tlp_fifo_rdout           ;
    wire    [DATA_WIDTH+31:0] tlp_fifo_wrdin           ;

    wire            fifo_empty_flag                     ;
    // reg             fifo_empty_flag_ff                  ;
    // reg             fifo_empty_flag_2ff                 ;

    wire            fifo_full_flag                      ;
    wire            fifo_valid_flag;
    // reg             fifo_full_flag_ff                   ;
    wire            fifo_afull_flag;
    reg             fifo_full_flag_2ff                  ;
    wire    [9:0]   wrusedw                             ;
    reg     [9:0]   wrusedw_ff                          ;

    reg     [DATA_WIDTH-1:0] m_axis_cq_tdata_ff         ;
    reg     [DW_WIDTH-1:0]   m_axis_cq_tkeep_ff         ;
    reg             m_axis_cq_tlast_ff                  ;
    reg     [USER_WIDTH-1:0] m_axis_cq_tuser_ff         ;
    reg             m_axis_cq_tvalid_ff                 ;

    wire    [5:0]   bar_aperture                        ;
    reg     [2:0]   bar_id                              ;
    reg     [7:0]   target_function                     ;
    reg     [3:0]   req_type                            ;

    // reg     [2:0]   cq_fifo_read_end_cnt                ;
    reg     [DATA_WIDTH+31:0] cq_fifo_rd_header         ;
    reg     [1:0]   cq_fifo_rd_fmt                      ;
    reg     [9:0]   cq_fifo_rd_lookup_id                ;
    reg     [3:0]   cq_fifo_rd_first_be                 ;
    reg     [3:0]   cq_fifo_rd_last_be                  ;
    reg             cq_fifo_rd_first_pkg                ;
    reg     [9:0]   cq_fifo_rd_dwlen                    ;
    wire            cq_fifo_rd_less_1dw                 ;
    reg             cq_fifo_rd_less_4dw                 ;
    reg     [DW_WIDTH-1:0]   cq_fifo_rd_less_4dw_keep   ;
    reg             cq_fifo_rd_less_2dw                 ;
    reg     [DW_WIDTH-1:0]   cq_fifo_rd_less_2dw_keep   ;


    //---pipepline register for timing-------------------------------//
    reg             radm_trgt1_dv_ff                    ;
    reg             radm_trgt1_dv_1ff                   ;
    reg             radm_trgt1_dv_2ff                   ;
    reg             radm_trgt1_dv_3ff                   ;    
    reg             radm_trgt1_hv_ff                    ;
    reg             radm_trgt1_hv_1ff                   ;
    reg             radm_trgt1_eot_ff                   ;
    reg             radm_trgt1_eot_1ff                  ;
    reg             radm_trgt1_eot_2ff                  ;
    reg             radm_trgt1_tlp_abort_ff             ;
    reg             radm_trgt1_dllp_abort_ff            ;
    reg             radm_trgt1_ecrc_err_ff              ;
    reg     [3:0]   radm_trgt1_dwen_ff                  ;
    reg     [1:0]   radm_trgt1_fmt_ff                   ;
    reg     [2:0]   radm_trgt1_attr_ff                  ;
    reg             radm_trgt1_func_num_ff              ;
    reg     [4:0]   radm_trgt1_type_ff                  ;
    reg     [2:0]   radm_trgt1_tc_ff                    ;
    reg     [15:0]  radm_trgt1_reqid_ff                 ;
    reg     [DATA_WIDTH-1:0] radm_trgt1_data_ff         ;
    reg     [DATA_WIDTH-1:0] radm_trgt1_data_1ff        ;
    reg     [DATA_WIDTH-1:0] radm_trgt1_data_2ff        ;
    reg     [3:0]   radm_trgt1_first_be_ff              ;
    reg     [3:0]   radm_trgt1_last_be_ff               ;
    reg     [63:0]  radm_trgt1_addr_ff                  ;
    reg     [1:0]   radm_trgt1_vfunc_num_ff             ;
    reg             radm_trgt1_vfunc_active_ff          ;
    reg             radm_trgt1_td_ff                    ;
    reg             radm_trgt1_poisoned_ff              ;
    reg             radm_trgt1_hdr_uppr_bytes_valid_ff  ;
    reg             radm_trgt1_rom_in_range_ff          ;
    reg             radm_trgt1_io_req_in_range_ff       ;
    reg     [63:0]  radm_trgt1_hdr_uppr_bytes_ff        ;
    reg     [2:0]   radm_trgt1_in_membar_range_ff       ;
    reg     [2:0]   radm_trgt1_cpl_status_ff            ;
    reg     [1:0]   radm_trgt1_ats_ff                   ;
    reg     [9:0]   radm_trgt1_tag_ff                   ;
    reg     [9:0]   radm_trgt1_dw_len_ff                ;
    reg             radm_trgt1_nw_ff                    ;
    reg             radm_trgt1_th_ff                    ;
    reg     [1:0]   radm_trgt1_ph_ff                    ;
    reg     [7:0]   radm_trgt1_st_ff                    ;
    reg     [11:0]  radm_trgt1_byte_cnt_ff              ;
    reg             radm_trgt1_bcm_ff                   ;
    reg     [2:0]   radm_trgt1_vc_ff                    ;
    reg     [15:0]  radm_trgt1_cmpltr_id_ff             ;
    reg             radm_trgt1_cpl_last_ff              ;
    reg     [2:0]   radm_grant_tlp_type_ff              ;
    reg     [1:0]   radm_trgt1_atu_sloc_match_ff        ;
    reg     [1:0]   radm_trgt1_atu_cbuf_err_ff          ;
    reg     [9:0]   trgt_lookup_id_ff                   ;
    reg             trgt_lookup_empty_ff                ;
    reg             trgt1_radm_halt_ff                  ;
    reg     [9:0]   cq_lookup_din                       ;
    reg     [9:0]   cq_lookup_addr                      ;
    reg             cq_lookup_en                        ;
    reg             eot;
// ====================================================================
// PipeLine
// ====================================================================
reg     hv_halt;
reg     radm_trgt1_hv_valid_ff1;
reg     radm_trgt1_hv_valid_ff2;
wire    radm_trgt1_hv_valid;
always@(posedge core_clk) begin
    // trgt1 signals
    radm_trgt1_dv_ff                    <= radm_trgt1_dv && !trgt1_radm_halt;
    radm_trgt1_dv_1ff                   <= radm_trgt1_dv_ff ;
    radm_trgt1_dv_2ff                   <= radm_trgt1_dv_1ff;
    radm_trgt1_dv_3ff                   <= radm_trgt1_dv_2ff;
            
    radm_trgt1_data_ff                  <= radm_trgt1_dv && !trgt1_radm_halt ? radm_trgt1_data : radm_trgt1_data_ff;
    radm_trgt1_data_1ff                 <= radm_trgt1_data_ff;
    radm_trgt1_data_2ff                 <= radm_trgt1_data_1ff;
            
    radm_trgt1_hv_ff                    <= radm_trgt1_hv && !trgt1_radm_halt;//trgt1_radm_halt==1'b0 ? radm_trgt1_hv : 1'b0;
    radm_trgt1_hv_1ff                   <= radm_trgt1_hv_ff;
            
    radm_trgt1_eot_ff                   <= radm_trgt1_eot&& !trgt1_radm_halt;//trgt1_radm_halt==1'b0 ? radm_trgt1_eot: 1'b0;
    radm_trgt1_eot_1ff                  <= radm_trgt1_eot_ff;
    radm_trgt1_eot_2ff                  <= radm_trgt1_eot_1ff;
    
    radm_trgt1_tlp_abort_ff             <= radm_trgt1_tlp_abort             ;
    radm_trgt1_dllp_abort_ff            <= radm_trgt1_dllp_abort            ;
    radm_trgt1_ecrc_err_ff              <= radm_trgt1_ecrc_err              ;
    radm_trgt1_dwen_ff                  <= radm_trgt1_dwen                  ;
    radm_trgt1_fmt_ff                   <= radm_trgt1_fmt                   ;
    radm_trgt1_attr_ff                  <= radm_trgt1_hv ? radm_trgt1_attr : radm_trgt1_attr_ff ;
    radm_trgt1_func_num_ff              <= radm_trgt1_func_num              ;
    radm_trgt1_type_ff                  <= radm_trgt1_type                  ;
    radm_trgt1_tc_ff                    <= radm_trgt1_hv ? radm_trgt1_tc : radm_trgt1_tc_ff ;
    radm_trgt1_reqid_ff                 <= radm_trgt1_hv ? radm_trgt1_reqid : radm_trgt1_reqid_ff;
    radm_trgt1_first_be_ff              <= radm_trgt1_first_be              ;
    radm_trgt1_last_be_ff               <= radm_trgt1_last_be               ;
    radm_trgt1_addr_ff                  <= radm_trgt1_addr                  ;
    radm_trgt1_vfunc_num_ff             <= radm_trgt1_vfunc_num             ;
    radm_trgt1_vfunc_active_ff          <= radm_trgt1_vfunc_active          ;
    radm_trgt1_td_ff                    <= radm_trgt1_td                    ;
    radm_trgt1_poisoned_ff              <= radm_trgt1_poisoned              ;
    radm_trgt1_hdr_uppr_bytes_valid_ff  <= radm_trgt1_hdr_uppr_bytes_valid  ;
    radm_trgt1_rom_in_range_ff          <= radm_trgt1_rom_in_range          ;
    radm_trgt1_io_req_in_range_ff       <= radm_trgt1_io_req_in_range       ;
    radm_trgt1_hdr_uppr_bytes_ff        <= radm_trgt1_hdr_uppr_bytes        ;
    radm_trgt1_in_membar_range_ff       <= radm_trgt1_in_membar_range       ;
    radm_trgt1_cpl_status_ff            <= radm_trgt1_cpl_status            ;
    radm_trgt1_ats_ff                   <= radm_trgt1_ats                   ;
    radm_trgt1_tag_ff                   <= radm_trgt1_hv ? radm_trgt1_tag : radm_trgt1_tag_ff;
    radm_trgt1_dw_len_ff                <= radm_trgt1_hv ? radm_trgt1_dw_len : radm_trgt1_dw_len_ff;
    radm_trgt1_nw_ff                    <= radm_trgt1_nw                    ;
    radm_trgt1_th_ff                    <= radm_trgt1_th                    ;
    radm_trgt1_ph_ff                    <= radm_trgt1_ph                    ;
    radm_trgt1_st_ff                    <= radm_trgt1_st                    ;
    radm_trgt1_byte_cnt_ff              <= radm_trgt1_byte_cnt              ;
    radm_trgt1_bcm_ff                   <= radm_trgt1_bcm                   ;
    radm_trgt1_vc_ff                    <= radm_trgt1_vc                    ;
    radm_trgt1_cmpltr_id_ff             <= radm_trgt1_cmpltr_id             ;
    radm_trgt1_cpl_last_ff              <= radm_trgt1_cpl_last              ;
    radm_grant_tlp_type_ff              <= radm_grant_tlp_type              ;
    radm_trgt1_atu_sloc_match_ff        <= radm_trgt1_atu_sloc_match        ;
    radm_trgt1_atu_cbuf_err_ff          <= radm_trgt1_atu_cbuf_err          ;
    trgt_lookup_id_ff                   <= trgt_lookup_id                   ;
    trgt_lookup_empty_ff                <= trgt_lookup_empty                ;
end
always@(posedge core_clk) begin
    fifo_full_flag_2ff                  <=  fifo_afull_flag; 
end
// ====================================================================
// Main Code
// ====================================================================
//--- reset localization--------------------------------------//
always@(posedge core_clk or negedge core_rst_n) begin
    if(!core_rst_n)
        local_cq_rst_n <= 1'b0;
    else
        local_cq_rst_n <= 1'b1;
end

//--- set radm_halt for back pressure-------------------------//
assign  trgt1_radm_halt     = fifo_full_flag_2ff || hv_halt;//| trgt1_radm_halt_ff;
assign  trgt1_radm_pkt_halt = 3'b000;
assign  radm_trgt1_hv_valid = radm_trgt1_hv && !trgt1_radm_halt;
always@(posedge core_clk or negedge local_cq_rst_n) begin
    if(!local_cq_rst_n) 
        radm_trgt1_hv_valid_ff1     <= 1'b0;
    else 
        radm_trgt1_hv_valid_ff1     <= radm_trgt1_hv_valid;
end
generate if ( DATA_WIDTH == 64 ) begin: PH1A100_BLK
    always@(posedge core_clk) begin
        radm_trgt1_hv_valid_ff2         <= !radm_trgt1_hv_valid_ff1 && radm_trgt1_hv_valid;
    end 
    always@(posedge core_clk or negedge local_cq_rst_n) begin
        if(!local_cq_rst_n) 
            hv_halt                     <= 1'b0;
        else if((!radm_trgt1_hv_valid_ff1 && radm_trgt1_hv_valid) || radm_trgt1_hv_valid_ff2)
            hv_halt                     <= 1'b1;
        else 
            hv_halt                     <= 1'b0;
    end
end else begin : PH1A400_BLK
    always@(posedge core_clk or negedge local_cq_rst_n) begin
        if(!local_cq_rst_n) 
            hv_halt <= 1'b0;
        else if(!radm_trgt1_hv_valid_ff1 && radm_trgt1_hv_valid)
            hv_halt <= 1'b1;
        else 
            hv_halt <= 1'b0;
    end
end 
endgenerate

//---translate bar_id---------------------------------------//
always@(posedge core_clk) begin
    if(radm_trgt1_hv ) begin
        casez({radm_trgt1_rom_in_range,radm_trgt1_in_membar_range})
            4'b1_zzz : bar_id <= 3'b110;
            4'b0_000 : bar_id <= 3'b000;
            4'b0_001 : bar_id <= 3'b001;
            4'b0_010 : bar_id <= 3'b010;
            4'b0_011 : bar_id <= 3'b011;
            4'b0_100 : bar_id <= 3'b100;
            4'b0_101 : bar_id <= 3'b101;
            default  : bar_id <= 3'b000;
        endcase
    end
end
//---now do not support the bar_size auto detect------------//
assign  bar_aperture = 5'd26;
//---traslate target_function------------------------------//
always@(posedge core_clk)
begin
    if(radm_trgt1_hv ) begin
        casez({ radm_trgt1_vfunc_active, radm_trgt1_vfunc_num,radm_trgt1_func_num})
            4'b0000 : target_function <= 8'b0000_0000;  // pf0
            4'b0001 : target_function <= 8'b0000_0001;  // pf1
            4'b1000 : target_function <= 8'b0000_0100;  // pf0-vf0
            4'b1010 : target_function <= 8'b0000_0101;  // pf0-vf1
            4'b1100 : target_function <= 8'b0000_0110;  // pf1-vf0
            4'b1110 : target_function <= 8'b0000_0111;  // pf1-vf1
            default : target_function <= 8'b0000_0000;
        endcase
    end
end
//---translate req_type-----------------------------------//
always@(posedge core_clk) begin
    if(radm_trgt1_hv ) begin
        casez({radm_trgt1_fmt,radm_trgt1_type})
            7'b00_00000: req_type <= 4'b0000; // memory read requeset
            7'b01_00000: req_type <= 4'b0000;
            7'b00_00001: req_type <= 4'b0111; // locked read request
            7'b01_00001: req_type <= 4'b0111;
            7'b10_00000: req_type <= 4'b0001; // memory write request
            7'b11_00000: req_type <= 4'b0001;
            7'b00_00010: req_type <= 4'b0010; // io read requeset
            7'b10_00010: req_type <= 4'b0011; // io wrire requeset
            7'b00_00100: req_type <= 4'b1000; // type0 cfg read request
            7'b00_00101: req_type <= 4'b1001; // type1 cfg read request
            7'b10_00100: req_type <= 4'b1010; // type0 cfg write request
            7'b10_00101: req_type <= 4'b1011; // type1 cfg write request
            7'bzz_10zzz: req_type <= 4'b1100; // any msg
            default    : req_type <= 4'b0000;
        endcase
    end
end

generate if ( DATA_WIDTH == 128 ) begin: PH1A400_HEAD
always@(posedge core_clk) begin
    if(radm_trgt1_hv && radm_trgt1_dv) begin 
        case(radm_trgt1_dw_len[1:0])
            2'b00: cq_fifo_rd_less_4dw_keep <= 4'b1111;
            2'b01: cq_fifo_rd_less_4dw_keep <= 4'b0001;
            2'b10: cq_fifo_rd_less_4dw_keep <= 4'b0011;
            2'b11: cq_fifo_rd_less_4dw_keep <= 4'b0111;
            default:cq_fifo_rd_less_4dw_keep<= 4'b1111;
        endcase
    end else begin 
        cq_fifo_rd_less_4dw_keep <= 4'b1111;
    end
end

always@(*) begin
    if( radm_trgt1_hv_ff && !radm_trgt1_dv_ff ) 
        eot     = radm_trgt1_eot_ff;
    else if(radm_trgt1_dv_1ff)
        eot     = radm_trgt1_eot_1ff;
    else 
        eot     = 1'b0;
end 
always@(posedge core_clk or negedge local_cq_rst_n) begin
    if(!local_cq_rst_n)begin
        tlp_fifo_wren <= 1'b0;
    end else if( radm_trgt1_hv_ff | radm_trgt1_dv_1ff ) begin // write head and first data or pure data after header
        tlp_fifo_wren <= 1'b1;
    end else begin
        tlp_fifo_wren <= 1'b0;
    end
end
//---write five dw head, include first_be and last be--------//
always@(posedge core_clk) begin
    if( radm_trgt1_hv_ff )begin
        //DW4, expect header, include first/last be for tuers byte enable used
        tlp_fifo_wrdw4     <= {eot                       ,
                               cq_fifo_rd_less_4dw_keep  ,
                               1'b0                      , // Reserved
                               trgt_lookup_id_ff[9:0]       , // look up id
                               3'b0                      , // Reserved
                               radm_trgt1_ph_ff[1:0]        , // ph
                               radm_trgt1_th_ff             , // th
                               radm_trgt1_fmt_ff[1:0]       , // format
                               radm_trgt1_first_be_ff[3:0]  , // first be
                               radm_trgt1_last_be_ff[3:0]     // last be
                              };
        //DW3, CQ bus header format
        tlp_fifo_wrdw3     <= {1'b0                         , // Reserved
                               radm_trgt1_attr_ff[2:0]      , // Attributes
                               radm_trgt1_tc_ff[2:0]        , // TC
                               bar_aperture[5:0]            , // BAR Apterture
                               bar_id[2:0]                  , // BAR ID
                               target_function[7:0]         , // Target Fcuntion
                               radm_trgt1_tag_ff[7:0]         // Tag
                              };
        //DW2, CQ bus header format
        tlp_fifo_wrdw2     <= {radm_trgt1_reqid_ff[15:0]    , // Req ID
                               1'b0                         , // Reserved
                               req_type[3:0]                , // Req type
                               {1'b0,radm_trgt1_dw_len_ff}    // DWord count
                              };
        //DW1,CQ bus header format
        tlp_fifo_wrdw1     <= {radm_trgt1_addr_ff[63:32]      // high address
                              };
        // DW0,CQ bus header format
        tlp_fifo_wrdw0     <=  {radm_trgt1_addr_ff[31:2]    , // low address
                                radm_trgt1_ats_ff[1:0]        // address transcation
                                };
    end else if( radm_trgt1_dv_1ff ) begin // judge dv_2ff first, incase back2back trans
        // write pure payload data into fifo
        tlp_fifo_wrdw0  <= radm_trgt1_data_1ff[31:0];
        tlp_fifo_wrdw1  <= radm_trgt1_data_1ff[63:32];
        tlp_fifo_wrdw2  <= radm_trgt1_data_1ff[95:64];
        tlp_fifo_wrdw3  <= radm_trgt1_data_1ff[127:96];
        tlp_fifo_wrdw4  <= {eot , cq_fifo_rd_less_4dw_keep,27'd0};
    end
end

end else begin: PH1A100_DW_FF
always@(posedge core_clk) begin
    if(radm_trgt1_hv && radm_trgt1_dv) begin 
        case(radm_trgt1_dw_len[0])
            1'b0: cq_fifo_rd_less_4dw_keep <= 2'b11;
            1'b1: cq_fifo_rd_less_4dw_keep <= 2'b01;
            default:cq_fifo_rd_less_4dw_keep <= 2'b11;
        endcase
    end else begin 
        cq_fifo_rd_less_4dw_keep <= 2'b11;
    end 
end

always@(*) begin
    if(radm_trgt1_hv_1ff && !radm_trgt1_dv_1ff) 
        eot     = radm_trgt1_eot_1ff;
    else if(radm_trgt1_dv_2ff)
        eot     = radm_trgt1_eot_2ff;
    else 
        eot     = 1'b0;
end 
always@(posedge core_clk or negedge local_cq_rst_n) begin
    if(!local_cq_rst_n)begin
        tlp_fifo_wren <= 1'b0;
    end else if( (radm_trgt1_hv_ff | radm_trgt1_hv_1ff | radm_trgt1_dv_2ff ) ) begin // write head and first data or pure data after header
        tlp_fifo_wren <= 1'b1;
    end else begin
        tlp_fifo_wren <= 1'b0;
    end
end

always@(posedge core_clk)begin
    if(radm_trgt1_hv_ff )begin
        //DW4, expect header, include first/last be for tuers byte enable used
        tlp_fifo_wrdw2     <= {
                               6'b0                         , // Reserved
                               trgt_lookup_id_ff[9:0]       , // look up id
                               3'b0                         , // Reserved
                               radm_trgt1_ph_ff[1:0]        , // ph
                               radm_trgt1_th_ff             , // th
                               radm_trgt1_fmt_ff[1:0]       , // format
                               radm_trgt1_first_be_ff[3:0]  , // first be
                               radm_trgt1_last_be_ff[3:0]     // last be
                              };
        //DW1,CQ bus header format
        tlp_fifo_wrdw1     <= {radm_trgt1_addr_ff[63:32]      // high address
                              };
        // DW0,CQ bus header format
        tlp_fifo_wrdw0     <=  {radm_trgt1_addr_ff[31:2]    , // low address
                                radm_trgt1_ats_ff[1:0]        // address transcation
                                };
    end else if ( radm_trgt1_hv_1ff ) begin

        //DW3, CQ bus header format
        tlp_fifo_wrdw2     <= {eot,cq_fifo_rd_less_4dw_keep,29'd0};
        tlp_fifo_wrdw1     <= {
                               1'b0                         , // Reserved
                               radm_trgt1_attr_ff[2:0]      , // Attributes
                               radm_trgt1_tc_ff[2:0]        , // TC
                               bar_aperture[5:0]            , // BAR Apterture
                               bar_id[2:0]                  , // BAR ID
                               target_function[7:0]         , // Target Fcuntion
                               radm_trgt1_tag_ff[7:0]         // Tag
                              };
        //DW2, CQ bus header format
        tlp_fifo_wrdw0     <= {
                               radm_trgt1_reqid_ff[15:0]    , // Req ID
                               1'b0                         , // Reserved
                               req_type[3:0]                , // Req type
                               {1'b0,radm_trgt1_dw_len_ff}    // DWord count
                              };

    end else if(radm_trgt1_dv_2ff ) begin // judge dv_2ff first, incase back2back trans
        // write pure payload data into fifo
        tlp_fifo_wrdw0  <= radm_trgt1_data_2ff[31:0];
        tlp_fifo_wrdw1  <= radm_trgt1_data_2ff[63:32];
        tlp_fifo_wrdw2  <= {eot,cq_fifo_rd_less_4dw_keep,29'd0};
    end
end

end
endgenerate

//---Local buffer for tlp head&data cache---------------------//
generate if ( DATA_WIDTH == 128 ) begin: PH1A400_FIFO
assign  tlp_fifo_wrdin = {tlp_fifo_wrdw4,tlp_fifo_wrdw3,tlp_fifo_wrdw2,tlp_fifo_wrdw1,tlp_fifo_wrdw0};
end else begin: PH1A100_FIFO
assign  tlp_fifo_wrdin = { tlp_fifo_wrdw2,tlp_fifo_wrdw1,tlp_fifo_wrdw0 };
end
endgenerate

sfifo #(
//  .RESOURCE_TYPE      ("bram"),
  .DATA_WIDTH_W       ( DATA_WIDTH+32  ),
  .DATA_WIDTH_R       ( DATA_WIDTH+32  ),
  .ADDR_WIDTH_W       ( 9    ),
  .ADDR_WIDTH_R       ( 9    ),
  .AL_FULL_NUM        ( 500  ),
  .SHOW_AHEAD_EN      ( 1    )
  )
u0_client12cc_fifo(
  .rst                (!local_cq_rst_n      ),   
  .clk                (core_clk             ),   
  .we                 (tlp_fifo_wren        ),   
  .di                 (tlp_fifo_wrdin       ),   
  .re                 (tlp_fifo_rden        ),  
  .dout               (tlp_fifo_rdout       ),   
  .valid              (fifo_valid_flag      ),   
  .full_flag          (fifo_full_flag       ),   
  .empty_flag         (fifo_empty_flag      ),   
  .afull              (fifo_afull_flag      ),  
  .aempty             (),   
  .wrusedw            (wrusedw[9:0]         ),   
  .rdusedw            ()    
  );

always@(*) begin
    tlp_fifo_rden       = m_axis_cq_tvalid_ff && m_axis_cq_tready && fifo_valid_flag;
end
always@(*) begin 
    m_axis_cq_tvalid_ff = fifo_valid_flag;
    m_axis_cq_tlast_ff  = tlp_fifo_rdout[DATA_WIDTH+32-1];
    m_axis_cq_tkeep_ff  = m_axis_cq_tlast_ff ? tlp_fifo_rdout[DATA_WIDTH+32-2:DATA_WIDTH+32-1-DW_WIDTH] : {DW_WIDTH{1'b1}}; 
end 
reg     [1:0]   m_axis_cnt;
always@(posedge core_clk or negedge local_cq_rst_n) begin
    if(!local_cq_rst_n) 
        m_axis_cnt      <= 'd0;
    else if(m_axis_cq_tvalid_ff && m_axis_cq_tready && m_axis_cq_tlast_ff && fifo_valid_flag)
        m_axis_cnt      <= 'd0;
    else if(m_axis_cq_tvalid_ff && m_axis_cq_tready && fifo_valid_flag)
        m_axis_cnt      <= m_axis_cnt + 'd1;
end 
generate if(DATA_WIDTH==128) begin 
    always@( * ) begin 
        case(m_axis_cnt)
            2'b00 : begin 
                m_axis_cq_tdata_ff  =  tlp_fifo_rdout[DATA_WIDTH-1:0];
                m_axis_cq_tuser_ff  =  {3'b0                      ,  //  Reserved
                                        {16'b0,6'b0,/*cq_fifo_rd_lookup_id*/10'b0},  //  parity
                                        tlp_fifo_rdout[151:144],  //  tph_st_tag
                                        tlp_fifo_rdout[138:137],  //  tph_type
                                        tlp_fifo_rdout[136]    ,  //  tph_present
                                        1'b0                      ,  //  discontinue
                                        1'b1                      ,  //  sop
                                        32'b0                     ,  //  byte_en
                                        tlp_fifo_rdout[131:128]   ,  //  last_be
                                        tlp_fifo_rdout[135:132]     //  first_be
                                        };
            end 
            default : begin 
                m_axis_cq_tdata_ff  = tlp_fifo_rdout[DATA_WIDTH-1:0];
                m_axis_cq_tuser_ff  = 0;
            end 
        endcase
    end 
end else begin 
    always@( * ) begin 
        case(m_axis_cnt)
            2'b00 : begin 
                m_axis_cq_tdata_ff  = tlp_fifo_rdout[DATA_WIDTH-1:0];
                m_axis_cq_tuser_ff  = {3'b0,/*Reserved*/ {16'b0, 6'b0,/*cq_fifo_rd_lookup_id*/10'b0},  //  parity
                                        tlp_fifo_rdout[87:80]  ,  //  tph_st_tag
                                        tlp_fifo_rdout[74:73]  ,  //  tph_type
                                        tlp_fifo_rdout[72]     ,  //  tph_present
                                        1'b0                   ,  //  discontinue
                                        1'b1                   ,  //  sop
                                        32'b0                  ,  //  byte_en
                                        tlp_fifo_rdout[67:64]  ,  //  last_be
                                        tlp_fifo_rdout[71:68]     //  first_be
                                 };
            end 
            default : begin 
                m_axis_cq_tdata_ff  = tlp_fifo_rdout[DATA_WIDTH-1:0];
                m_axis_cq_tuser_ff  = 0;
            end 
        endcase
    end 
end 
endgenerate

// record the look up id according tag
always@(posedge core_clk or negedge local_cq_rst_n)
begin
    if(!local_cq_rst_n) begin
        cq_lookup_en    <= 1'b0;
    end else if(radm_trgt1_hv && (!trgt1_radm_halt)) begin
        case({radm_trgt1_fmt,radm_trgt1_type})
            7'b00_00000: cq_lookup_en <= 1'b1;      // memory read requeset
            7'b01_00000: cq_lookup_en <= 1'b1;
            7'b00_00001: cq_lookup_en <= 1'b1;      // locked read request
            7'b01_00001: cq_lookup_en <= 1'b1;
            //7'b10_00000: cq_lookup_en <= 1'b0;    // memory write request
            //7'b11_00000: cq_lookup_en <= 1'b0;
            7'b00_00010: cq_lookup_en <= 1'b1;      // io read requeset
            //7'b10_00010: cq_lookup_en <= 1'b0;    // io wrire requeset
            7'b00_00100: cq_lookup_en <= 1'b1;      // type0 cfg read request
            7'b00_00101: cq_lookup_en <= 1'b1;      // type1 cfg read request
            //7'b10_00100: cq_lookup_en <= 1'b0;    // type0 cfg write request
            //7'b10_00101: cq_lookup_en <= 1'b0;    // type1 cfg write request
         default: cq_lookup_en    <= 1'b0;
         endcase
    end else begin
        cq_lookup_en    <= 1'b0;
    end
end

always@(posedge core_clk) begin
        cq_lookup_din   <= trgt_lookup_id;
        cq_lookup_addr  <= radm_trgt1_tag;
end

(* ram_style = "bram" *)reg [10-1:0]   mem_id_ram [1024-1:0];//synthesis ram_style = bram
reg     [10-1:0]    mem_id_out=0;
integer mm;
initial begin 
    for(mm=0;mm<1024;mm=mm+1) begin 
        mem_id_ram[mm] = {10{1'b0}};
    end 
end 
always @(posedge core_clk) begin
    if(cq_lookup_en)
        mem_id_ram[cq_lookup_addr]  <= cq_lookup_din;
end 
always @(posedge core_clk) begin
    mem_id_out <= mem_id_ram[rq_lookup_addr];
end 
assign  rq_lookup_dout = mem_id_out;
//---output axi bus---------------------------------//
assign      m_axis_cq_tdata     = m_axis_cq_tdata_ff;
assign      m_axis_cq_tkeep     = m_axis_cq_tkeep_ff;
assign      m_axis_cq_tlast     = m_axis_cq_tlast_ff;
assign      m_axis_cq_tuser     = m_axis_cq_tuser_ff;
assign      m_axis_cq_tvalid    = m_axis_cq_tvalid_ff;

//---debug used-------------------------------------//
assign      trgt2cq_debug     = 4'b0;

endmodule

`default_nettype wire
