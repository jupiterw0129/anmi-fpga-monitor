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

module usr_axi4mmr#(
	parameter 	DLY         = 1,
	parameter 	ODATA_WIDTH = 128, 
	parameter 	OKEEP_WIDTH = ODATA_WIDTH/8, 
	parameter   ONBYTE_WIDTH= $clog2(OKEEP_WIDTH),
	parameter 	C2H_CHNL_NUM= 1
	)
	(
    input   wire   usr_clk,
	input   wire   usr_rst_n,

	input   wire   [C2H_CHNL_NUM-1:0]  usr_c2h0r_run_i,
	input   wire   usr_lp0rw_run_i,
	input   wire   s0_axis_c2h_rst_i,

	output  wire   m_axi_arready_o,
	input   wire   [3:0]  m_axi_arid_i,//Each transaction channel has its own transaction ID
	input   wire   [63:0] m_axi_araddr_i,
	//specifies the number of data transfers that occur within each burst.
	input   wire   [7:0] m_axi_arlen_i,
	//specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
	input   wire   [2:0] m_axi_arsize_i,
	input   wire   [1:0] m_axi_arburst_i,//0b01 INCR
	input   wire   [2:0] m_axi_arprot_i,//ARPROT[2:0] defines the access permissions for read accesses
	input   wire   m_axi_arvalid_i,
	input   wire   m_axi_arlock_i,//ARLOCK[1:0] = 0b10 is converted to a normal read transaction, ARLOCK = 0b0.
	input   wire   [3:0] m_axi_arcache_i,//All accesses are defined as Non-modifiable, Non-bufferable, equivalent to an AxCACHE value of 0b0000.
/*
In a read transaction, the slave can signal different responses for different transfers in a burst. For example, in a burst
of 16 read transfers the slave might return an OKAY response for 15 of the transfers and a SLVERR response for
one of the transfers.
The protocol specifies that the required number of data transfers must be performed, even if an error is reported. For
example, if a read of 8 transfers is requested from a slave but the slave has an error condition, the slave must perform
8 data transfers, each with an error response. The remainder of the burst is not cancelled if the slave gives a single
error response.

	*/
	output  wire   [3:0] m_axi_rid_o,
	output  wire   [ODATA_WIDTH-1:0]m_axi_rdata_o,
	output  wire   [1:0] m_axi_rresp_o,
	output  wire   m_axi_rlast_o,
	output  wire   m_axi_rvalid_o,
	input   wire   m_axi_rready_i,

	// input   wire   [12:0]   usr_ram_pntr_i,
	output  wire   usr_c2h0_rden_o,
	output  wire   [15:0] usr_c2h0_rdaddr_o,
	input   wire   [ODATA_WIDTH-1:0]   usr_c2h0_dt_i,

	output  wire   usr_c2h0err_o


);

(*max_fanout = 100*) reg [3:0] c2h_rst_sync;
wire c2h_rst;

always @(posedge usr_clk or negedge usr_rst_n) begin
    if (!usr_rst_n)
        c2h_rst_sync <= 4'b1111;
    else
        c2h_rst_sync <= {c2h_rst_sync[2:0], s0_axis_c2h_rst_i};
end

assign c2h_rst = c2h_rst_sync[3];

localparam ADDR_FIFO_WIDTH = 72;
reg                          addr_fifo_we;
reg  [ADDR_FIFO_WIDTH-1:0]   addr_fifo_di;
wire                         addr_fifo_re;
wire [ADDR_FIFO_WIDTH-1:0]   addr_fifo_dout;
wire                         addr_fifo_valid;
wire                         addr_fifo_full_flag;
wire                         addr_fifo_empty_flag;
wire                         addr_fifo_afull;

sfifo #(
  .RESOURCE_TYPE      ("dram"),
  .DATA_WIDTH_W       ( ADDR_FIFO_WIDTH),
  .DATA_WIDTH_R       ( ADDR_FIFO_WIDTH),
  .ADDR_WIDTH_W       ( 4),
  .ADDR_WIDTH_R       ( 4),
  .AL_FULL_NUM        ( 10 ),
  .SHOW_AHEAD_EN      ( 1)
  )
u_addr_fifo(
  .rst                (!usr_rst_n | c2h_rst),  //asynchronous port,active hight
  .clk                (usr_clk),  //common clock for write and read
  .we                 (addr_fifo_we),  //write enable,active hight
  .di                 (addr_fifo_di),  //write data
  .re                 (addr_fifo_re),  //read enable,active hight
  .dout               (addr_fifo_dout),  //read data
  .valid              (addr_fifo_valid),  //read data valid flag
  .full_flag          (addr_fifo_full_flag),  //fifo full flag
  .empty_flag         (addr_fifo_empty_flag),  //fifo empty flag
  .afull              (addr_fifo_afull),  //fifo almost full flag
  .aempty             (),  //fifo almost empty flag
  .wrusedw            (),  //stored data number in fifo
  .rdusedw            ()//available data number for read
  );

wire             data_fifo_re;
wire [ODATA_WIDTH:0]	data_fifo_dout;
wire             data_fifo_valid;
wire             data_fifo_afull;

reg m_axi_arready;

always @(posedge usr_clk or negedge usr_rst_n) begin
	if (!usr_rst_n)
		m_axi_arready <= #DLY 1'b0;
	else if (c2h_rst)
		m_axi_arready <= #DLY 1'b0;
	else if (usr_c2h0r_run_i)
		m_axi_arready <= #DLY !addr_fifo_afull;
end
assign m_axi_arready_o = m_axi_arready;

always @(posedge usr_clk or negedge usr_rst_n) begin
	if (!usr_rst_n)
		addr_fifo_we <= #DLY 1'b0;
	else
		addr_fifo_we <= #DLY m_axi_arvalid_i & m_axi_arready;
end

always @(posedge usr_clk) begin
	addr_fifo_di <= #DLY {m_axi_arlen_i, m_axi_araddr_i};
end

wire [15:0] rd_addr;
wire [7:0] 	rd_len;
// wire 		bram_empty;
reg  		bram_rd_en;
reg [15:0] 	bram_rd_addr;
reg [7:0] 	bram_rd_len;

assign rd_addr = addr_fifo_dout[ONBYTE_WIDTH+:16];
assign rd_len = addr_fifo_dout[71:64];
// assign bram_empty = usr_ram_pntr_i == 'd0;

// assign bram_rd_en = addr_fifo_valid & !bram_empty;

always @(posedge usr_clk or negedge usr_rst_n) begin
    if (!usr_rst_n)
        bram_rd_en <= #DLY 'b0;
    else if (c2h_rst)
        bram_rd_en <= #DLY 'b0;
    else
        bram_rd_en <= #DLY addr_fifo_valid & !data_fifo_afull;
end

always @(posedge usr_clk or negedge usr_rst_n) begin
	if (!usr_rst_n)
		bram_rd_len <= #DLY 'b0;
	else if (c2h_rst)
		bram_rd_len <= #DLY 'b0;
	else if (addr_fifo_re)
		bram_rd_len <= #DLY 'b0;
	else if (addr_fifo_valid & !data_fifo_afull)
		bram_rd_len <= #DLY bram_rd_len+1;
end

// assign bram_rd_addr = rd_addr+bram_rd_len;

always @(posedge usr_clk) begin
    bram_rd_addr <= #DLY rd_addr+bram_rd_len;
end

assign usr_c2h0_rden_o = bram_rd_en;
assign usr_c2h0_rdaddr_o = bram_rd_addr;

reg 	bram_rd_en_d1;
reg 	bram_rd_en_d2;
wire 	rd_last;
reg		rd_last_d1;
reg		rd_last_d2;
reg		rd_last_d3;
wire 	m_axi_rvalid;
reg 	m_axi_rlast;
reg [ODATA_WIDTH-1:0] m_axi_rdata;

assign addr_fifo_re = addr_fifo_valid & !data_fifo_afull & rd_last;

always @(posedge usr_clk or negedge usr_rst_n) begin
	if (!usr_rst_n) begin
		bram_rd_en_d1 <= #DLY 1'b0;
		bram_rd_en_d2 <= #DLY 1'b0;
	end else if (c2h_rst) begin
		bram_rd_en_d1 <= #DLY 1'b0;
		bram_rd_en_d2 <= #DLY 1'b0;
	end else begin
		bram_rd_en_d1 <= #DLY bram_rd_en;
		bram_rd_en_d2 <= #DLY bram_rd_en_d1;
	end
end

assign m_axi_rvalid = bram_rd_en_d2;

always @(posedge usr_clk) begin
	m_axi_rdata <= #DLY usr_c2h0_dt_i;
end

assign rd_last = rd_len == bram_rd_len;

always @(posedge usr_clk) begin
	rd_last_d1 <= #DLY rd_last;
	rd_last_d2 <= #DLY rd_last_d1;
	rd_last_d3 <= #DLY rd_last_d2;
end

sfifo #(
  .RESOURCE_TYPE      ("dram"),
  .DATA_WIDTH_W       ( ODATA_WIDTH + 1),
  .DATA_WIDTH_R       ( ODATA_WIDTH + 1),
  .ADDR_WIDTH_W       (4),// 3),
  .ADDR_WIDTH_R       (4),// 3),
  .AL_FULL_NUM        (12),// 4 ),
  .SHOW_AHEAD_EN      ( 1)
  )
u_data_fifo(
  .rst                (!usr_rst_n | c2h_rst),  //asynchronous port,active hight
  .clk                (usr_clk),  //common clock for write and read
  .we                 (m_axi_rvalid),  //write enable,active hight
  .di                 ({rd_last_d3, m_axi_rdata}),  //write data
  .re                 (m_axi_rready_i),  //read enable,active hight
  .dout               (data_fifo_dout),  //read data
  .valid              (m_axi_rvalid_o),  //read data valid flag
  .full_flag          (),  //fifo full flag
  .empty_flag         (),  //fifo empty flag
  .afull              (data_fifo_afull),  //fifo almost full flag
  .aempty             (),  //fifo almost empty flag
  .wrusedw            (),  //stored data number in fifo
  .rdusedw            ()//available data number for read
  );

assign m_axi_rlast_o = data_fifo_dout[ODATA_WIDTH];

assign m_axi_rid_o   = 4'd0;
assign usr_c2h0err_o = 1'b0;
assign m_axi_rresp_o = 2'b0;

//-----------------------------
`ifdef DEBUG_MODE
	reg [31:0] c2h0_tdata0;

	always @(posedge usr_clk,negedge usr_rst_n)
	begin
		if(!usr_rst_n)
			c2h0_tdata0 <= #DLY 32'd0;
		else if(c2h_rst)
			c2h0_tdata0 <= #DLY 32'd0;
		else if(m_axi_rvalid_o & m_axi_rready_i)
			c2h0_tdata0 <= #DLY c2h0_tdata0 + 32'd1;
		else ;
	end

    localparam NDT = `SDATA_WIDTH/ODATA_WIDTH;
	wire   [ODATA_WIDTH-1:0]   c2h0_fm_tmp[`C2H0_FM_NUM*NDT-1:0];
	generate
	    genvar cnt_c2h0_fm;
        genvar cnt_odt;
		for(cnt_c2h0_fm=0;cnt_c2h0_fm<`C2H0_FM_NUM;cnt_c2h0_fm=cnt_c2h0_fm+1)
        begin
            for(cnt_odt=0;cnt_odt<NDT;cnt_odt=cnt_odt+1)
            begin
			    assign c2h0_fm_tmp[cnt_c2h0_fm*NDT+cnt_odt] = u_file_tx.c2h0_fm_dt[cnt_c2h0_fm][(cnt_odt+1)*ODATA_WIDTH-1:cnt_odt*ODATA_WIDTH];
            end
		end
	endgenerate
	assign m_axi_rdata_o  = usr_lp0rw_run_i ? data_fifo_dout[ODATA_WIDTH-1:0] : c2h0_fm_tmp[c2h0_tdata0];
`else
	reg [7:0] c2h0_tdata0;
	always @(posedge usr_clk,negedge usr_rst_n)
	begin
		if(!usr_rst_n)
			c2h0_tdata0 <= #DLY 8'd0;
		else if(c2h_rst)
			c2h0_tdata0 <= #DLY 8'd0;
		else if(m_axi_rvalid_o & m_axi_rready_i)
			c2h0_tdata0 <= #DLY c2h0_tdata0 + 8'd1;
		else ;
	end
	assign m_axi_rdata_o = usr_lp0rw_run_i ? data_fifo_dout[ODATA_WIDTH -1:0] : {(ODATA_WIDTH/6'd8){c2h0_tdata0}};
`endif

endmodule
