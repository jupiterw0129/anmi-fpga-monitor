`timescale 1ns/1ps
// `ifdef DEBUG_MODE
// 	`include "para_def.vh"
// `endif
module usr_ctrl#(
	parameter 	H2C_CHNL_NUM = 1, 
	parameter 	C2H_CHNL_NUM = 1, 
	parameter 	DLY = 1
	)(
	input	wire   usr_rst_n,
	input	wire   usr_clk,

	input   wire   [1:0]   usr_lp0rw_cmd_i,
	input   wire   [H2C_CHNL_NUM-1:0] m0_axis_h2c_run_i,
    input   wire   [C2H_CHNL_NUM-1:0] s0_axis_c2h_run_i,
	input   wire   usr_cfgrw_cmd_i,

	output  wire   usr_cfgrw_run_o,
	output  wire   [1:0]   usr_dmarw_run_o,
	output  wire   [H2C_CHNL_NUM-1:0] usr_h2c0w_run_o,
    output  wire   [C2H_CHNL_NUM-1:0] usr_c2h0r_run_o,
    output  wire   usr_lp0rw_run_o
);
//---Constant definition;
localparam INIT_DLY = 12'd4010;

//---Variable definition;
reg   [11:0]   cnt_dly;
reg   init_en;
wire  init_over;
reg   usr_cfgrw_run;
reg   [1:0]    usr_dmarw_run;

wire  usr_lp0rw_run;

always@(posedge usr_clk,negedge usr_rst_n )
begin
	if(!usr_rst_n)
		cnt_dly <= #DLY 12'd0;
	else if(init_over)
		cnt_dly <= #DLY 12'd0;
	else if(init_en)
		cnt_dly <= #DLY cnt_dly + 12'd1;
	else ;
end
always@(posedge usr_clk,negedge usr_rst_n )
begin
	if(!usr_rst_n)
		init_en <= #DLY 1'b1;
	else if(init_over)
		init_en <= #DLY 1'b0;
	else ;
end
assign init_over = (cnt_dly==INIT_DLY-1) ? 1'b1 : 1'b0;

always@(posedge usr_clk,negedge usr_rst_n )
begin
	if(!usr_rst_n)
		usr_dmarw_run <=  #DLY 2'b00;
	else begin
    	case (cnt_dly)
		    12'd2000: usr_dmarw_run[0] <= #DLY 1'b1;
            12'd3000: usr_dmarw_run[1] <= #DLY 1'b1;
			default: ;
        endcase
	end
end
assign usr_cfgrw_run_o = usr_cfgrw_cmd_i;
assign usr_dmarw_run_o = usr_dmarw_run;

assign usr_lp0rw_run = (&usr_lp0rw_cmd_i);
assign usr_h2c0w_run_o = m0_axis_h2c_run_i;
assign usr_c2h0r_run_o = s0_axis_c2h_run_i;
assign usr_lp0rw_run_o = usr_lp0rw_run;


endmodule
