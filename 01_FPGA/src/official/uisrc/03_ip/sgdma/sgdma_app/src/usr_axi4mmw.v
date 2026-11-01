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
`ifdef DEBUG_MODE
	`include "spara_def.vh"
	`include "case_def.vh"
`endif

module usr_axi4mmw#(
	parameter 	DLY         = 1,
	parameter 	ODATA_WIDTH = 128, 
	parameter 	OKEEP_WIDTH = ODATA_WIDTH/8, 
	parameter   ONBYTE_WIDTH= $clog2(OKEEP_WIDTH),
	parameter 	H2C_CHNL_NUM= 1
	)(
   	input   wire   usr_clk,
	input   wire   usr_rst_n,

	input   wire   [H2C_CHNL_NUM-1:0]	usr_h2c0w_run_i,
	input   wire   m0_axis_h2c_rst_i,
    input   wire   usr_lp0rw_run_i,

	output  wire   m_axi_awready_o,
	input   wire   [3:0]  m_axi_awid_i,//Write address channel
	input   wire   [63:0] m_axi_awaddr_i,//A burst must not cross a 4KB address boundary.
	input   wire   [7:0] m_axi_awlen_i,//AXI4 extends burst length support for the INCR burst type to 1 to 256 transfers,Burst_Length = AxLEN[3:0] + 1
	input   wire   [2:0] m_axi_awsize_i,//The maximum number of bytes to transfer in each data transfer,0b111 128
	input   wire   [1:0] m_axi_awburst_i,//The AXI protocol defines three burst types:,0b01 INCR
	input   wire   [2:0] m_axi_awprot_i,//AWPROT[2:0] defines the access permissions for write accesses.0 Unprivileged access,0 Secure access,0 Data access
	input   wire   m_axi_awvalid_i,
	input   wire   m_axi_awlock_i,//0b00 Normal access
	input   wire   [3:0] m_axi_awcache_i,//All accesses are defined as Non-modifiable, Non-bufferable, equivalent to an AxCACHE value of 0b0000.
	input   wire   [ODATA_WIDTH-1:0] m_axi_wdata_i,
	input   wire   [OKEEP_WIDTH-1:0] m_axi_wstrb_i,//The WSTRB[n:0] signals when HIGH, specify the byte lanes of the data bus that contain valid information. There
										//is one write strobe for each eight bits of the write data bus, therefore WSTRB[n] corresponds to WDATA[(8n)+7: (8n)].
	output  wire   m_axi_wready_o,
	input   wire   m_axi_wlast_i,
	input   wire   m_axi_wvalid_i,
	output  wire   [3:0] m_axi_bid_o,//Slaves are required to reflect on the appropriate BID or RID response an AXI ID received from a master
	output  wire   [1:0] m_axi_bresp_o,
	output  wire   m_axi_bvalid_o,
	input   wire   m_axi_bready_i,

	// input   wire   [12:0]   usr_ram_pntr_i,
	output  wire   usr_h2c0_wren_o,
	output  wire   [OKEEP_WIDTH-1:0]   usr_h2c0_wstrb_o,
	output  wire   [15:0]   usr_h2c0_wraddr_o,
	output  wire   [ODATA_WIDTH-1:0]   usr_h2c0_dt_o,

	output  wire   [31:0]   usr_h2c0err_num_o

);
//---Variable definition;
reg   h2c0_trdy;
wire  h2c0_handshake_ok;
reg   h2c0_wren;
reg   [ODATA_WIDTH-1:0]   h2c0_din;
reg   [31:0]   h2c0_tst_dt;
reg   [31:0]   usr_h2c0err_num;

// wire   h2c0_ram_ufull;
wire   w_handshake_ok;
wire   m_axi_wlastv;
wire   b_handshake_ok;
reg    m_axi_bvalid;
reg    [15:0]   bram_wraddr;
wire   aw_handshake_ok;

always@(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		h2c0_trdy <= #DLY 1'b0;
	else if(m0_axis_h2c_rst_i)
		h2c0_trdy <= #DLY 1'b0;
	else if(usr_h2c0w_run_i)
		h2c0_trdy <= #DLY 1'b1;//~h2c0_trdy
	else ;
end
always@(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		h2c0_tst_dt <= #DLY 32'd0;
	else if(m0_axis_h2c_rst_i)
		h2c0_tst_dt <= #DLY 32'd0;
	else if(h2c0_wren)
		h2c0_tst_dt <= #DLY h2c0_tst_dt + 32'd1;
	else ;
end

reg [1:0] aw_w_seq;
localparam S_IDLE = 2'd0;
localparam S_ADDR_DATA = 2'd1;
localparam S_DATA = 2'd2;

always@(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		aw_w_seq <= #DLY S_IDLE;
	else if(m0_axis_h2c_rst_i)
		aw_w_seq <= #DLY S_IDLE;
	else //if(usr_h2c0w_run_i)
		case (aw_w_seq)
			S_IDLE: begin
				aw_w_seq <= #DLY S_ADDR_DATA;
			end
			S_ADDR_DATA: begin
				if (m_axi_wvalid_i & m_axi_wready_o & m_axi_wlast_i)
					aw_w_seq <= #DLY S_ADDR_DATA;
				else if (m_axi_awvalid_i & m_axi_awready_o)
					aw_w_seq <= #DLY S_DATA;
			end
			S_DATA: begin
				if (m_axi_wvalid_i & m_axi_wready_o & m_axi_wlast_i)
					aw_w_seq <= #DLY S_ADDR_DATA;
			end
		endcase
end

// assign h2c0_ram_ufull = ~(usr_ram_pntr_i[12]);
// assign m_axi_wready_o = h2c0_trdy & h2c0_ram_ufull;
// assign m_axi_awready_o = h2c0_trdy;
assign m_axi_wready_o = (((aw_w_seq == S_ADDR_DATA) & m_axi_awvalid_i) | (aw_w_seq == S_DATA));
assign m_axi_awready_o = (aw_w_seq == S_ADDR_DATA);
assign w_handshake_ok = m_axi_wready_o & m_axi_wvalid_i;
always @(posedge usr_clk)
begin
	if(w_handshake_ok)
		h2c0_din <= #DLY m_axi_wdata_i;
	else ;
end
always@(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		h2c0_wren <= #DLY 1'b0;
	else
		h2c0_wren <= #DLY w_handshake_ok;
end
reg [OKEEP_WIDTH-1:0] h2c0_wstrb ;
always @(posedge usr_clk) begin
	if(w_handshake_ok)
		h2c0_wstrb <= #DLY m_axi_wstrb_i;
	else ;
end

assign usr_h2c0_dt_o = h2c0_din;
assign usr_h2c0_wren_o = h2c0_wren & usr_lp0rw_run_i;
assign usr_h2c0_wstrb_o= h2c0_wstrb;
assign aw_handshake_ok = m_axi_awready_o & m_axi_awvalid_i;
always @(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		bram_wraddr <= #DLY 14'd0;
	else if(aw_handshake_ok)
		bram_wraddr <= #DLY m_axi_awaddr_i[15+ONBYTE_WIDTH:ONBYTE_WIDTH];
	else if(h2c0_wren)//---Wraddr and wrdata have the same phase;
		bram_wraddr <= #DLY bram_wraddr + 12'd1;
	else ;
end
assign usr_h2c0_wraddr_o = bram_wraddr;
assign m_axi_wlastv = m_axi_wlast_i & w_handshake_ok;
assign b_handshake_ok = m_axi_bvalid & m_axi_bready_i;
always @(posedge usr_clk,negedge usr_rst_n)
begin
	if(!usr_rst_n)
		m_axi_bvalid <= #DLY 1'b0;
	else if(b_handshake_ok | m0_axis_h2c_rst_i)
		m_axi_bvalid <= #DLY 1'b0;
	else if(m_axi_wlastv)
		m_axi_bvalid <= #DLY 1'b1;
	else ;
end
assign m_axi_bvalid_o = m_axi_bvalid;
assign m_axi_bresp_o = 2'b00;
assign m_axi_bid_o = 4'd0;


`ifdef DEBUG_MODE
	integer j;

    localparam NDT = `SDATA_WIDTH/ODATA_WIDTH,
               NDT_WD = $clog2(NDT);
    reg     [ODATA_WIDTH-1:0]   h2c0_fm_tmp[`H2C0_FM_NUM*NDT-1:0];
	reg     [`SDATA_WIDTH-1:0]   h2c0_fm_sim[`H2C0_FM_NUM-1:0];
    wire    [`H2C0_FMNUM_WD-1:0] cntx_h2c0_fm;
    wire    h2c0_tst_en;
    `ifdef CASE9_2
        assign h2c0_tst_en = 1'b1;
    `elsif CASE11
        assign h2c0_tst_en = 1'b1;
    `else
        assign h2c0_tst_en = 1'b0;
    `endif

	generate
	genvar m;
	for(m=0;m<OKEEP_WIDTH;m=m+1) begin
		always@(posedge usr_clk or negedge usr_rst_n)
		begin
			if(!usr_rst_n) begin
				for (j=0;j<`H2C0_FM_NUM*NDT;j=j+1)
				begin
					h2c0_fm_tmp[j] <= #DLY {ODATA_WIDTH{1'b0}};
				end
			end
			else if(((~usr_lp0rw_run_i)|h2c0_tst_en) & h2c0_wren) begin
				if(h2c0_wstrb[m])
					h2c0_fm_tmp[h2c0_tst_dt][m*8+7:m*8] <= #DLY h2c0_din[m*8+7:m*8];
				else
					h2c0_fm_tmp[h2c0_tst_dt][m*8+7:m*8] <= #DLY 8'h00;
			end
			else ;
		end
	end
	endgenerate

    generate
        genvar cnt_h2c0_fm;
        genvar cnt_odt;
        for (cnt_h2c0_fm=0;cnt_h2c0_fm<`H2C0_FM_NUM;cnt_h2c0_fm=cnt_h2c0_fm+1)
        begin
            for (cnt_odt=0;cnt_odt<NDT;cnt_odt=cnt_odt+1)
            begin
                assign h2c0_fm_sim[cnt_h2c0_fm][ODATA_WIDTH*(cnt_odt+1)-1:ODATA_WIDTH*cnt_odt] = h2c0_fm_tmp[cnt_h2c0_fm*NDT+cnt_odt];
            end
        end
    endgenerate
    assign usr_h2c0err_num_o  = 32'h00000000;
    assign cntx_h2c0_fm = ((h2c0_tst_dt+NDT-1)>>NDT_WD);
`else
	//---Compare test data with h2c data, and output test results;
	always@(posedge usr_clk,negedge usr_rst_n)
	begin
		if(!usr_rst_n)
			usr_h2c0err_num <= #DLY 32'd0;
		else if(m0_axis_h2c_rst_i)
			usr_h2c0err_num <= #DLY 32'd0;
		else if(h2c0_wren==1'b1 && h2c0_tst_dt[31:0]!=h2c0_din[31:0])
			usr_h2c0err_num <= #DLY usr_h2c0err_num + 32'd1;
		else ;
	end
	assign usr_h2c0err_num_o  = usr_h2c0err_num;
`endif

endmodule
