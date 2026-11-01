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
//          native ven_msi interface convert to cfg_interrupt interface
//       
// Email       :  
// 
// ===========================================================================

`timescale 1ns/1ns
`default_nettype none  


module  pcie_sideband_msi#(
    parameter   DATA_WIDTH = 128     
    )(
    //---system clock and reset------------------------------//
     input      wire                core_clk
    ,input      wire                core_rst_n
    ,input      wire        [15:0]  requester_id_i
    //INT-X 
    ,output     wire        [1:0]   sys_int
    ,input      wire                cfg_link_eq_req_int
    ,input      wire                assert_inta_grt
    ,input      wire                assert_intb_grt
    ,input      wire                assert_intc_grt
    ,input      wire                assert_intd_grt
    ,input      wire                deassert_inta_grt
    ,input      wire                deassert_intb_grt
    ,input      wire                deassert_intc_grt
    ,input      wire                deassert_intd_grt    
    ,input      wire        [15:0]  cfg_int_pin  
    ,input      wire        [1:0]   cfg_int_disable  
    //---native ven_msi interface-------------------------------//
    ,output     reg                 ven_msi_req             
    ,output     wire                ven_msi_func_num    
    ,output     wire        [63:0]  cfg_msi_pending         
    ,output     wire        [1:0]   ven_msi_vfunc_num   
    ,output     wire                ven_msi_vfunc_active 
    ,output     wire        [2:0]   ven_msi_tc          
    ,output     reg         [4:0]   ven_msi_vector      
    ,input      wire        [1:0]   cfg_msi_en          
    ,input      wire        [63:0]  cfg_msi_mask        
    ,input      wire                ven_msi_grant       

    //---cfg msi bus interface-------------------------------//
    // legacy int not support now
    ,input      wire       [3:0]    cfg_interrupt_int                           
    ,input      wire       [1:0]    cfg_interrupt_pending                       
    ,output     wire                cfg_interrupt_sent                          
    // msi signals  
    ,output     wire       [3:0]    cfg_interrupt_msi_enable                    
    ,output     wire       [11:0]   cfg_interrupt_msi_mmenable      // not support at this time, user need read pcie register self
    ,output     wire                cfg_interrupt_msi_mask_update   // not support 
    ,output     wire       [31:0]   cfg_interrupt_msi_data                                  
    ,input      wire       [1:0]    cfg_interrupt_msi_select                    
    ,input      wire       [31:0]   cfg_interrupt_msi_int                       
    ,input      wire       [31:0]   cfg_interrupt_msi_pending_status            
    ,input      wire                cfg_interrupt_msi_pending_status_data_enable
    ,input      wire       [1:0]    cfg_interrupt_msi_pending_status_function_num
    ,output     reg                 cfg_interrupt_msi_sent                      
    ,output     wire                cfg_interrupt_msi_fail     
    //Both MSI and MSI-X use the following signals                 
    ,input      wire       [2:0]    cfg_interrupt_msi_attr                      
    ,input      wire                cfg_interrupt_msi_tph_present               
    ,input      wire       [1:0]    cfg_interrupt_msi_tph_type                  
    ,input      wire       [9:0]    cfg_interrupt_msi_tph_st_tag                
    ,input      wire       [7:0]    cfg_interrupt_msi_function_number           
    //MSI-X 
    ,output     wire       [1:0]    cfg_interrupt_msix_enable   
    ,output     wire       [1:0]    cfg_interrupt_msix_mask     
    ,output     wire       [5:0]    cfg_interrupt_msix_vf_enable
    ,output     wire       [5:0]    cfg_interrupt_msix_vf_mask  
    ,input      wire       [63:0]   cfg_interrupt_msix_address  
    ,input      wire       [31:0]   cfg_interrupt_msix_data     
    ,input      wire                cfg_interrupt_msix_int      
    ,output     wire                cfg_interrupt_msix_sent   
    ,output     wire                cfg_interrupt_msix_fail  

    //---axi rq bus interface-------------------------------//
    ,output     wire                m_axis_rq_tvalid
    ,input      wire       [3:0]    m_axis_rq_tready
    ,output     wire       [DATA_WIDTH-1:0]     m_axis_rq_tdata
    ,output     wire       [DATA_WIDTH/32-1:0]  m_axis_rq_tkeep
    ,output     wire                m_axis_rq_tlast
    ,output     wire       [61:0]   m_axis_rq_tuser
    
    ,input      wire                msix_sent_i
    //---only for debug---------------------------------------//
    ,output     wire       [3:0]    ven2msi_debug
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================
    // misc signals
    integer         i;
    reg             msi_int_new;
    reg             msi_int_busy;

    // pipeline signals
    reg   [1:0]     cfg_interrupt_msi_select_ff;
    reg   [31:0]    cfg_interrupt_msi_int_ff;
    reg   [31:0]    cfg_interrupt_msi_pending_status_ff;            
    reg             cfg_interrupt_msi_pending_status_data_enable_ff;
    reg   [1:0]     cfg_interrupt_msi_pending_status_function_num_ff;
    reg   [2:0]     cfg_interrupt_msi_attr_ff;                      
    reg             cfg_interrupt_msi_tph_present_ff;               
    reg   [1:0]     cfg_interrupt_msi_tph_type_ff;                  
    reg   [7:0]     cfg_interrupt_msi_tph_st_tag_ff;                
    reg   [7:0]     cfg_interrupt_msi_function_number_ff;           

//INT-X
    reg [3:0]       cfg_interrupt_int_ff;
    reg [1:0]       cfg_interrupt_pending_ff;
    reg [1:0]       sys_int_ff;
    reg             assert_intx_grt;
    reg             deassert_intx_grt;
always@(posedge core_clk) begin 
    cfg_interrupt_int_ff        <= cfg_interrupt_int;
    cfg_interrupt_pending_ff    <= cfg_interrupt_pending;
    assert_intx_grt             <= assert_inta_grt | assert_intb_grt | assert_intc_grt | assert_intd_grt;
    deassert_intx_grt           <= deassert_inta_grt | deassert_intb_grt | deassert_intc_grt | deassert_intd_grt;
end 

assign  sys_int = cfg_interrupt_pending_ff & {2{(|cfg_interrupt_int_ff)}};
assign  cfg_interrupt_sent = assert_intx_grt | deassert_intx_grt;
// ====================================================================
// PipeLine
// ====================================================================
always@(posedge core_clk) begin 
    cfg_interrupt_msi_select_ff         <= cfg_interrupt_msi_select;
    cfg_interrupt_msi_int_ff            <= cfg_interrupt_msi_int;
    cfg_interrupt_msi_pending_status_ff <= cfg_interrupt_msi_pending_status;            
    cfg_interrupt_msi_attr_ff           <= cfg_interrupt_msi_attr;                      
    cfg_interrupt_msi_tph_present_ff    <= cfg_interrupt_msi_tph_present;               
    cfg_interrupt_msi_tph_type_ff       <= cfg_interrupt_msi_tph_type;                  
    cfg_interrupt_msi_tph_st_tag_ff     <= cfg_interrupt_msi_tph_st_tag[7:0];                
    cfg_interrupt_msi_function_number_ff<= cfg_interrupt_msi_function_number;           
    cfg_interrupt_msi_pending_status_data_enable_ff <= cfg_interrupt_msi_pending_status_data_enable;
    cfg_interrupt_msi_pending_status_function_num_ff <= cfg_interrupt_msi_pending_status_function_num;
end

// ====================================================================
// Main Code
// ====================================================================

// decode cfg_interrupt_msi_int_ff
always@(posedge core_clk or negedge core_rst_n) 
begin 
    if(!core_rst_n) begin 
        msi_int_new <= 1'b0;
    end else if( !msi_int_new && !msi_int_busy && ( |(cfg_interrupt_msi_int & ~cfg_interrupt_msi_int_ff)) ) begin // when not busy, posedge detect
        msi_int_new <= 1'b1;
    end else begin 
        msi_int_new <= 1'b0;
    end
end

// msi busy signal, only accept 1 interrupt at same time
always@(posedge core_clk or negedge core_rst_n)
begin 
    if(!core_rst_n)begin 
        msi_int_busy <= 1'b0;
    end else if(ven_msi_req & ven_msi_grant) begin
        msi_int_busy <= 1'b0;
    end else if( msi_int_new ) begin 
        msi_int_busy <= 1'b1;
    end

end

// change int to vector
always@(posedge core_clk or negedge core_rst_n)
begin
    if(!core_rst_n) begin 
        ven_msi_vector <= 5'b0;                
    end else if(msi_int_new )begin 
        for(i=31;i>=0;i=i-1)begin : int_2_vector
            if( cfg_interrupt_msi_int[i] == 1'b1 ) 
                ven_msi_vector <= i;               
        end
    end
end

// generate ven_msi_req
always@(posedge core_clk or negedge core_rst_n)
begin
    if(!core_rst_n)begin 
        ven_msi_req <= 1'b0;                    
    end else if( ven_msi_req & ven_msi_grant ) begin
        ven_msi_req <= 1'b0;                    
    end else if(msi_int_new )begin
        ven_msi_req <= 1'b1;                    
    end 
end

// ack send
always@(posedge core_clk or negedge core_rst_n)
begin 
    if(!core_rst_n)begin
        cfg_interrupt_msi_sent <= 1'b0;                     
    end else if(ven_msi_req & ven_msi_grant ) begin 
        cfg_interrupt_msi_sent <= 1'b1;
    end else begin 
        cfg_interrupt_msi_sent <= 1'b0;                     
    end
end

// cfg_interrput_* combination signals
assign cfg_interrupt_msi_enable      = {2'b0,cfg_msi_en[1:0]};                                
assign cfg_interrupt_msi_mmenable    = 12'd0;                      
assign cfg_interrupt_msi_mask_update = 1'b0;                
assign cfg_interrupt_msi_data        = 1'b0;                         
assign cfg_interrupt_msi_fail        = 1'b0; 

// ven_msi_* combination signals
assign  ven_msi_func_num = cfg_interrupt_msi_function_number[0];         
assign  cfg_msi_pending  ={2{cfg_interrupt_msi_pending_status_ff[31:0]}};       
assign  ven_msi_vfunc_num    = 2'b0;    
assign  ven_msi_vfunc_active = 1'b0;
assign  ven_msi_tc           = 2'b0;            

//MSI-X interrupt
reg             msix_int_ff;
reg     [63:0]  msix_address_ff;
reg     [31:0]  msix_data_ff;
reg     [2:0]   msix_attr_ff;                      
reg             msix_tph_present_ff;              
reg     [1:0]   msix_tph_type_ff;                  
reg     [7:0]   msix_tph_st_tag_ff;                
reg     [7:0]   msix_function_number_ff;      

always@(posedge core_clk or negedge core_rst_n) begin 
    if(!core_rst_n) begin
        msix_int_ff             <= 1'b0;
    end else begin
        msix_int_ff             <= cfg_interrupt_msix_int;
    end
end 
always@(posedge core_clk or negedge core_rst_n) begin 
    if(!core_rst_n) begin
        msix_address_ff         <= 1'b0;
        msix_data_ff            <= 1'b0;
        msix_attr_ff            <= 3'b000;                      
        msix_tph_present_ff     <= 1'b0;              
        msix_tph_type_ff        <= 2'b00;                  
        msix_tph_st_tag_ff      <= 8'h00;                
        msix_function_number_ff <= 8'h00;           
    end else if(!msix_int_ff && cfg_interrupt_msix_int) begin
        msix_address_ff         <= cfg_interrupt_msix_address;
        msix_data_ff            <= cfg_interrupt_msix_data;
        msix_attr_ff            <= cfg_interrupt_msi_attr;                      
        msix_tph_present_ff     <= cfg_interrupt_msi_tph_present;              
        msix_tph_type_ff        <= cfg_interrupt_msi_tph_type;                  
        msix_tph_st_tag_ff      <= cfg_interrupt_msi_tph_st_tag;                
        msix_function_number_ff <= cfg_interrupt_msi_function_number;   
    end
end 

reg     [1:0]               tx_cnt;
reg                         axis_rq_tvalid;
reg     [DATA_WIDTH-1:0]    axis_rq_tdata;
reg     [DATA_WIDTH/32-1:0] axis_rq_tkeep;
reg                         axis_rq_tlast;
reg     [61:0]              axis_rq_tuser;
wire    [3:0]               req_type;
wire    [10:0]              dw_cnt;

assign  req_type    = 4'b0001;
assign  dw_cnt      = 11'd1;
always@(posedge core_clk or negedge core_rst_n) begin 
    if(!core_rst_n) 
        axis_rq_tvalid              <= 1'd0;
    else if(axis_rq_tvalid && m_axis_rq_tready[0] && axis_rq_tlast)
        axis_rq_tvalid              <= 1'd0;
    else if(!msix_int_ff && cfg_interrupt_msix_int)
        axis_rq_tvalid              <= 1'd1;
end  
always@(posedge core_clk or negedge core_rst_n) begin 
    if(!core_rst_n) 
        tx_cnt                      <= 2'd0;
    else if(axis_rq_tvalid && m_axis_rq_tready[0] && axis_rq_tlast) 
        tx_cnt                      <= 2'd0;
    else if(axis_rq_tvalid && m_axis_rq_tready[0])
        tx_cnt                      <= tx_cnt + 2'd1;
end  

generate if(DATA_WIDTH == 64) begin : RQ_DWIDTH_64BIT
    always  @(*) begin
        if( (tx_cnt == 'd3 - 1'b1) && axis_rq_tvalid == 1'b1) 
            axis_rq_tlast       = 1'b1 ;
        else 
            axis_rq_tlast       = 1'b0 ;       
    end   
    always  @(*) begin
        if( (tx_cnt == 'd3 - 1'b1) && axis_rq_tvalid == 1'b1) 
            axis_rq_tkeep       = 2'b01 ;
        else 
            axis_rq_tkeep       = {(DATA_WIDTH/32){1'b1}} ;       
    end

    always  @(*) begin
        case(tx_cnt) 
            'd0    : axis_rq_tdata  =  {msix_address_ff[63:2],2'b00};
            'd1    : axis_rq_tdata  =  {1'b0,msix_attr_ff,3'b000,1'b1,16'h0000,msix_tph_st_tag_ff[7:0],requester_id_i,1'b0,req_type,dw_cnt} ;   
            default: axis_rq_tdata  =  msix_data_ff;                              
        endcase
    end  
end else if(DATA_WIDTH == 128) begin : RQ_DWIDTH_128BIT
    always  @(*) begin
        if( (tx_cnt == 'd2 - 1'b1) && axis_rq_tvalid == 1'b1) 
            axis_rq_tlast       = 1'b1 ;
        else 
            axis_rq_tlast       = 1'b0 ;       
    end   
    always  @(*) begin
        if( (tx_cnt == 'd2 - 1'b1) && axis_rq_tvalid == 1'b1) 
            axis_rq_tkeep       = 4'b0001 ;
        else 
            axis_rq_tkeep       = {(DATA_WIDTH/32){1'b1}} ;       
    end

    always  @(*) begin
        case(tx_cnt) 
            'd0    : axis_rq_tdata  =  {1'b0,msix_attr_ff,3'b000,1'b1,16'h0000,msix_tph_st_tag_ff[7:0],requester_id_i,1'b0,req_type,dw_cnt,msix_address_ff[63:2],2'b00}; 
            default: axis_rq_tdata  =  msix_data_ff;                              
        endcase
    end  
end
endgenerate

assign  m_axis_rq_tvalid = axis_rq_tvalid;
assign  m_axis_rq_tdata  = axis_rq_tdata;
assign  m_axis_rq_tkeep  = axis_rq_tkeep;
assign  m_axis_rq_tlast  = axis_rq_tlast;
assign  m_axis_rq_tuser  = {'d0,4'b0000,4'b1111};

assign  cfg_interrupt_msix_fail = 1'b0;
assign  cfg_interrupt_msix_sent = msix_sent_i;

endmodule

`default_nettype wire


