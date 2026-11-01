`timescale 1ns/1ps
/*===========================================*\
Filename        :sgdma_subsys.v
Project name    :sgdma_subsys_tst
Description     :      sgdma ip   pcie_phy
Called by       :sgdma_subsys_tst.v
Email           :bingsong.wang@anlogic.com
Modified        :v1.0          2021-03-19
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/

module usr_axi4st_c2h#(
	parameter 	DLY         = 1,
	parameter 	ODATA_WIDTH = 128, 
	parameter 	OKEEP_WIDTH = ODATA_WIDTH/8, 
	parameter   ONBYTE_WIDTH= $clog2(OKEEP_WIDTH)
	)(
    input   wire   	usr_clk,
	input   wire   	usr_rst_n,
	input   wire  	usr_lp0rw_run_i,

	input   wire   	s0_axis_c2h_tready_i,
    output  wire   	[ODATA_WIDTH-1:0]  s0_axis_c2h_tdata_o,
    output  wire   	[OKEEP_WIDTH-1:0]  s0_axis_c2h_tkeep_o,
    output  wire   	[OKEEP_WIDTH-1:0]  s0_axis_c2h_tuser_o,
    output  wire   	s0_axis_c2h_tlast_o,
    output  wire   	s0_axis_c2h_tvalid_o,

  	input 	wire   	fifo_valid_i,
  	output  wire   	fifo_re_o,
  	input 	wire  	[ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1-1:0]  fifo_dout_i,
	output  wire   	usr_c2h0err_o

);
localparam DLT_DT = 8'd1;
//---Variable definition;
reg    c2h0_tvalid;
reg    [31:0]   c2h0_tdata0;
reg    [31:0]   c2h0_tdata1;

wire   [ODATA_WIDTH-1:0]   lp_h2c_tdata;
wire   [OKEEP_WIDTH-1:0]   lp_h2c_tkeep;
wire   [OKEEP_WIDTH-1:0]   lp_h2c_tuser;
wire   lp_h2c_tlast;

assign {lp_h2c_tdata, lp_h2c_tkeep, lp_h2c_tuser, lp_h2c_tlast} = fifo_dout_i;
assign fifo_re_o 			= usr_lp0rw_run_i ? s0_axis_c2h_tready_i : 1'b0;
assign s0_axis_c2h_tvalid_o = usr_lp0rw_run_i ? fifo_valid_i : 1'b1; // for max performance
assign s0_axis_c2h_tlast_o  = usr_lp0rw_run_i ? lp_h2c_tlast : 1'b0;
assign s0_axis_c2h_tkeep_o  = usr_lp0rw_run_i ? lp_h2c_tkeep : {OKEEP_WIDTH{1'b1}};
assign s0_axis_c2h_tuser_o  = usr_lp0rw_run_i ? lp_h2c_tuser : {OKEEP_WIDTH{1'b0}};

always @(posedge usr_clk,negedge usr_rst_n) begin
	if(!usr_rst_n)
		c2h0_tdata0 <= #DLY 32'd0;
	else if(s0_axis_c2h_tready_i)
		c2h0_tdata0 <= #DLY c2h0_tdata0 + {24'd0,DLT_DT};
	else ;
end

assign s0_axis_c2h_tdata_o  = usr_lp0rw_run_i ? lp_h2c_tdata : {(ODATA_WIDTH/32){c2h0_tdata0}};
assign usr_c2h0err_o = 0;

endmodule
