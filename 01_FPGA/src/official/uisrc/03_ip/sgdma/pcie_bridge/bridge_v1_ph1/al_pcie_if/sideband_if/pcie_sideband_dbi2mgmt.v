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
// 			native dbi interface convert to mgmt interface
//		 
// Email       :  
// 
// ===========================================================================


module pcie_sideband_dbi2mgmt
(
	//---system clock and reset------------------------------//
	 input		wire				core_clk
	,input		wire				core_rst_n

	//---native dbi interface-------------------------------//
    ,output      reg        [31:0]   ext_drp_dbi_din 			
    ,output      reg        [3:0]    ext_drp_dbi_wr 			
    ,output      reg        [31:0]   ext_drp_dbi_addr 		
    ,output      reg                 ext_drp_dbi_cs 			
    ,output      wire                ext_drp_dbi_cs2_exp 		
    ,output      reg        [1:0]    ext_drp_dbi_vfunc_num 	
    ,output      reg                 ext_drp_dbi_vfunc_active 
    ,output      wire       [2:0]    ext_drp_dbi_bar_num 		
    ,output      wire                ext_drp_dbi_rom_access 	
    ,output      wire                ext_drp_dbi_io_access 	
    ,output      reg                 ext_drp_dbi_func_num 	
    ,output      wire                ext_drp_app_dbi_ro_wr_disable 
    ,input       wire       [31:0]   ext_drp_lbc_dbi_dout 	
    ,input       wire                ext_drp_lbc_dbi_ack 		

	//---convert mgmt interface------------------------------//
  	,input  	 wire       [9:0] 	 cfg_mgmt_addr								
  	,input  	 wire       [7:0] 	 cfg_mgmt_function_number					
  	,input  	 wire       		 cfg_mgmt_write								
  	,input  	 wire       [31:0]   cfg_mgmt_write_data							
  	,input  	 wire       [3:0]    cfg_mgmt_byte_enable						
  	,input  	 wire       		 cfg_mgmt_read								
  	,output 	 reg        [31:0]   cfg_mgmt_read_data							
  	,output 	 reg        		 cfg_mgmt_read_write_done					
  	,input  	 wire       		 cfg_mgmt_debug_access						

	//---only for debug---------------------------------------//
	,output		wire		[3:0]	 dbi2mgmt_debug

);


// ====================================================================
// Parameter/wire/reg
// ====================================================================
	//state machine define and macro
    reg      [3:0]      dbi2mgmt_state;
    localparam          DBI2MGMT_IDLE   = 4'b0001,
                        DBI2MGMT_WR     = 4'b0010,
                        DBI2MGMT_RD     = 4'b0100,
                        DBI2MGMT_WAIT   = 4'b1000;

	//internal register and combination siangls
    reg                 local_mgmt_rst_n;
    reg       [2:0]     dbi2mgmt_wait_cnt;     

  	reg       [9:0] 	cfg_mgmt_addr_ff;								
  	reg       [7:0] 	cfg_mgmt_function_number_ff;					
  	reg       		    cfg_mgmt_write_ff;								
  	reg       [31:0]    cfg_mgmt_write_data_ff;							
  	reg       [3:0]     cfg_mgmt_byte_enable_ff;						
  	reg       		    cfg_mgmt_read_ff;								
  	reg       		    cfg_mgmt_debug_access_ff;						
// ====================================================================
// PipeLine
// ====================================================================

always@(posedge core_clk)
begin
    // mgmt input
  	cfg_mgmt_addr_ff            <= cfg_mgmt_addr            ;								
  	cfg_mgmt_function_number_ff <= cfg_mgmt_function_number ;					
  	cfg_mgmt_write_ff           <= cfg_mgmt_write           ;								
  	cfg_mgmt_write_data_ff      <= cfg_mgmt_write_data      ;							
  	cfg_mgmt_byte_enable_ff     <= cfg_mgmt_byte_enable     ;						
  	cfg_mgmt_read_ff            <= cfg_mgmt_read            ;								
  	cfg_mgmt_debug_access_ff    <= cfg_mgmt_debug_access    ;						
                                                               
end

// ====================================================================
// Main Code
// ====================================================================

//--- reset localization--------------------------------------//
always@(posedge core_clk or negedge core_rst_n) 
begin
    if(!core_rst_n)
        local_mgmt_rst_n <= 1'b0;
    else
        local_mgmt_rst_n <= 1'b1;
end

always@(posedge core_clk or negedge local_mgmt_rst_n)
begin 
    if(!local_mgmt_rst_n) begin
        dbi2mgmt_state <= DBI2MGMT_IDLE;
    end else begin 
        case(dbi2mgmt_state)
            DBI2MGMT_IDLE: begin 
                if(cfg_mgmt_write_ff)
                    dbi2mgmt_state <= DBI2MGMT_WR;
                else if(cfg_mgmt_read_ff)
                    dbi2mgmt_state <= DBI2MGMT_RD;
                else 
                    dbi2mgmt_state <= DBI2MGMT_IDLE;
            end

            DBI2MGMT_WR:begin 
                if(cfg_mgmt_read_write_done)					
                    dbi2mgmt_state <= DBI2MGMT_WAIT;
            end

            DBI2MGMT_RD:begin 
                if(cfg_mgmt_read_write_done)					
                    dbi2mgmt_state <= DBI2MGMT_WAIT;
            end

            DBI2MGMT_WAIT:begin 
                if(dbi2mgmt_wait_cnt[2])
                    dbi2mgmt_state <= DBI2MGMT_IDLE;
            end
        endcase
    end
end

always@(posedge core_clk or negedge local_mgmt_rst_n)
begin 
    if(!local_mgmt_rst_n) begin 
        ext_drp_dbi_wr          <= 4'b0;
        ext_drp_dbi_cs          <= 1'b0;
        ext_drp_dbi_din 	    <= 32'b0;
        ext_drp_dbi_addr 	    <= 32'b0;

  	    cfg_mgmt_read_data      <= 32'b0;							
  	    cfg_mgmt_read_write_done<= 1'b0;					

        dbi2mgmt_wait_cnt       <= 3'b0;
    end else begin
        
        ext_drp_dbi_wr          <= 4'b0;
        ext_drp_dbi_din 	    <= cfg_mgmt_write_data_ff;
        ext_drp_dbi_addr 	    <= {cfg_mgmt_addr_ff,2'b0}; // used DW address            
        dbi2mgmt_wait_cnt       <= 3'b0;

        case(dbi2mgmt_state)
            
            DBI2MGMT_WR:begin 
                ext_drp_dbi_wr <= cfg_mgmt_byte_enable_ff;
                cfg_mgmt_read_write_done <= ext_drp_lbc_dbi_ack;       
                if(ext_drp_lbc_dbi_ack | cfg_mgmt_read_write_done)
                    ext_drp_dbi_cs <= 1'b0;
                else
                    ext_drp_dbi_cs <= 1'b1;
            end

            DBI2MGMT_RD:begin 
                cfg_mgmt_read_data <= ext_drp_lbc_dbi_dout;     
                cfg_mgmt_read_write_done <= ext_drp_lbc_dbi_ack;       
                if(ext_drp_lbc_dbi_ack | cfg_mgmt_read_write_done)
                    ext_drp_dbi_cs <= 1'b0;
                else
                    ext_drp_dbi_cs <= 1'b1;
            end
            
            DBI2MGMT_WAIT:begin 
                cfg_mgmt_read_write_done <= 1'b0;       
                dbi2mgmt_wait_cnt <= dbi2mgmt_wait_cnt + 1'b1;
            end
        endcase
    end
end


always@(posedge core_clk or negedge local_mgmt_rst_n)
begin 
    if(!local_mgmt_rst_n) begin 
        ext_drp_dbi_func_num 	 <= 1'b0;
        ext_drp_dbi_vfunc_num    <= 2'b0; 	
        ext_drp_dbi_vfunc_active <= 1'b0;
    end else begin
        case(cfg_mgmt_function_number_ff[7:0])
            8'b0000_0001: begin                     // pf0
                ext_drp_dbi_func_num 	 <= 1'b0;
                ext_drp_dbi_vfunc_num    <= 2'b00; 	
                ext_drp_dbi_vfunc_active <= 1'b0;
            end

            8'b0000_0010: begin                     // pf1
                ext_drp_dbi_func_num 	 <= 1'b1;
                ext_drp_dbi_vfunc_num    <= 2'b00; 	
                ext_drp_dbi_vfunc_active <= 1'b0;
            end

            8'b0000_0100: begin                     // pf0-vf0
                ext_drp_dbi_func_num 	 <= 1'b0;
                ext_drp_dbi_vfunc_num    <= 2'b00; 	
                ext_drp_dbi_vfunc_active <= 1'b1;
            end

            8'b0000_1000: begin                     // pf0-vf1
                ext_drp_dbi_func_num 	 <= 1'b0;
                ext_drp_dbi_vfunc_num    <= 2'b01; 
                ext_drp_dbi_vfunc_active <= 1'b1;
            end
        
            8'b0000_1000: begin                     // pf1-vf0
                ext_drp_dbi_func_num 	 <= 1'b1;
                ext_drp_dbi_vfunc_num    <= 2'b10; 
                ext_drp_dbi_vfunc_active <= 1'b1;
            end

            8'b0001_0000: begin                     // pf1-vf1
                ext_drp_dbi_func_num 	 <= 1'b1;
                ext_drp_dbi_vfunc_num    <= 2'b11; 
                ext_drp_dbi_vfunc_active <= 1'b1;
            end

            default: begin 
                ext_drp_dbi_func_num 	 <= 1'b0;
                ext_drp_dbi_vfunc_num    <= 2'b00; 	
                ext_drp_dbi_vfunc_active <= 1'b0;
            end
        endcase
    end
end



assign  ext_drp_app_dbi_ro_wr_disable  = 1'b0;
assign  ext_drp_dbi_bar_num 	       = 3'b0;	
assign  ext_drp_dbi_rom_access         = 1'b0; 	
assign  ext_drp_dbi_io_access          = 1'b0; 	
assign  ext_drp_dbi_cs2_exp 		   = 1'b0;

endmodule
