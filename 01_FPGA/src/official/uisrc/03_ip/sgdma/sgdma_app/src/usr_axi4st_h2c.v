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

module usr_axi4st_h2c#(
	parameter 	DLY         = 1,
	parameter 	ODATA_WIDTH = 128, 
	parameter 	OKEEP_WIDTH = ODATA_WIDTH/8, 
	parameter   ONBYTE_WIDTH= $clog2(OKEEP_WIDTH)
	)(
    input   wire    usr_clk,
	input   wire    usr_rst_n,
    input   wire    usr_lp0rw_run_i,

	output  wire    m0_axis_h2c_tready_o,
    input   wire   [ODATA_WIDTH-1:0]   m0_axis_h2c_tdata_i,
 	input   wire   [OKEEP_WIDTH-1:0]   m0_axis_h2c_tkeep_i,
 	input   wire   [OKEEP_WIDTH-1:0]   m0_axis_h2c_tuser_i,
	input   wire    m0_axis_h2c_tlast_i,
	input   wire    m0_axis_h2c_tvalid_i,

	input   wire    fifo_rdy_i,
	output  wire    fifo_we_o,
	output  wire	[ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1-1:0]	fifo_di_o,
	output  wire   	[31:0]   usr_h2c0err_num_o
);
//---Variable definition;
reg                     h2c0_trdy;
reg                     m0_axis_h2c_tready;
wire                    h2c0_handshake_ok;
reg   [7:0]             usr_h2c0err_num;

always@(posedge usr_clk,negedge usr_rst_n) begin
    if(!usr_rst_n)
        h2c0_trdy <= #DLY 1'b0;
    else
        h2c0_trdy <= #DLY ~h2c0_trdy;
end
always@(posedge usr_clk) begin
    m0_axis_h2c_tready  <= #DLY usr_lp0rw_run_i ? fifo_rdy_i : `ifdef DEBUG_MODE h2c0_trdy `else 1'b1 `endif;
end 
assign m0_axis_h2c_tready_o = m0_axis_h2c_tready;
assign h2c0_handshake_ok    = m0_axis_h2c_tready & m0_axis_h2c_tvalid_i;
//
reg     fifo_we;
wire    [ODATA_WIDTH-1:0]   h2c_tdata_c;
reg     [ODATA_WIDTH-1:0]   h2c_tdata;
reg     [OKEEP_WIDTH-1:0]   h2c_tkeep;
reg     [OKEEP_WIDTH-1:0]   h2c_tuser;
reg                         h2c_tlast;
generate begin 
    genvar i;
    for(i=0;i<OKEEP_WIDTH;i=i+1) begin : AXIS_H2C_REG_BLK
        always@(posedge usr_clk) begin
            h2c_tdata   <= #DLY m0_axis_h2c_tdata_i;
            h2c_tkeep   <= #DLY m0_axis_h2c_tkeep_i;
            h2c_tuser   <= #DLY m0_axis_h2c_tuser_i;
            h2c_tlast   <= #DLY m0_axis_h2c_tlast_i;
            fifo_we     <= #DLY h2c0_handshake_ok;
        end
        assign  h2c_tdata_c[8*i+7:8*i] = (h2c_tkeep[i]==1'b1) ? h2c_tdata[8*i+7:8*i] : 8'h00;
    end 
end
endgenerate
assign fifo_we_o        = usr_lp0rw_run_i ? fifo_we : 1'b0;
assign fifo_di_o        = usr_lp0rw_run_i ? {h2c_tdata_c, h2c_tkeep, h2c_tuser, h2c_tlast} : 'd0;
assign usr_h2c0err_num_o= 0;

endmodule
