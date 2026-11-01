`timescale 1ns/1ps
/*===========================================*\
Filename         : dma_regwr.v
Author           :
Project name     : sgdma_app
Description      :
Called by        : sgdma_subsystem_tst.v
Revision History : v1.0
Email            :
Modified         :
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/

module usr_axi4mmb#(
    parameter       DLY = 1,
    parameter       ODATA_WIDTH = 128,
    parameter       OKEEP_WIDTH = ODATA_WIDTH/8
    )(
    input   wire   usr_clk,
	input   wire   usr_rst_n,
	
    output   wire   m_axib_arready,
	input   wire  [3:0] m_axib_arid,
	input   wire  [63:0]m_axib_araddr,
	//specifies the number of data transfers that occur within each burst.
	input   wire  [7:0] m_axib_arlen,
	//specifies the maximum number of data bytes to transfer in each beat. 011-8byte,100-16byte
	input   wire  [2:0] m_axib_arsize,
	input   wire  [1:0] m_axib_arburst,
	input   wire  [2:0] m_axib_arprot,
	input   wire  m_axib_arvalid,
	input   wire  m_axib_arlock,
	input   wire  [3:0] m_axib_arcache,
	
	output   wire   [3:0] m_axib_rid,
	output   wire   [ODATA_WIDTH-1:0]m_axib_rdata,
	output   wire   [1:0] m_axib_rresp,
	output   wire   m_axib_rlast,
	output   wire   m_axib_rvalid,
	input   wire  m_axib_rready,
	
	output   wire   m_axib_awready,
	input   wire  [3:0] m_axib_awid,
	input   wire  [63:0]m_axib_awaddr,
	input   wire  [7:0] m_axib_awlen,
	input   wire  [2:0] m_axib_awsize,
	input   wire  [1:0] m_axib_awburst,
	input   wire  [2:0] m_axib_awprot,
	input   wire  m_axib_awvalid,
	input   wire  m_axib_awlock,
	input   wire  [3:0] m_axib_awcache,
	input   wire  [ODATA_WIDTH-1:0] m_axib_wdata,
	input   wire  [OKEEP_WIDTH-1:0] m_axib_wstrb,
	
    output   wire   m_axib_wready,
	input   wire  m_axib_wlast,
	input   wire  m_axib_wvalid,
	output   wire   [3:0] m_axib_bid,
	output   wire   [1:0] m_axib_bresp,
	output   wire   m_axib_bvalid,
	input   wire  m_axib_bready
);

wire mem_cea;
wire [7:0]  mem_wea;
wire [63:0] mem_dia; 
wire [60:0] mem_addra; 
wire [63:0] mem_doa;
wire [7:0] ram_wea;

axi_eram_controller #(
  .AXI_ID_WIDTH         (8),   
  .AXI_DATA_WIDTH       (64),   
  .AXI_ADDR_WIDTH       (64),   
  .OOR_ERR_EN           (1)
 )u_axi_eram_controller(
         .awid(m_axib_awid),
         .awaddr(m_axib_awaddr),
         .awlen(m_axib_awlen),
         .awsize(m_axib_awsize),
         .awburst(m_axib_awburst),
         .awlock(m_axib_awlock),
         .awvalid(m_axib_awvalid),
         .awready(m_axib_awready),
         .wdata(m_axib_wdata),
         .wstrb(m_axib_wstrb),
         .wvalid(m_axib_wvalid),
         .wready(m_axib_wready),
         .bid(m_axib_bid),
         .bresp(m_axib_bresp),
         .bvalid(m_axib_bvalid),
         .bready(m_axib_bready),
         .arid(m_axib_arid),
         .araddr(m_axib_araddr),
         .arlen(m_axib_arlen),
         .arsize(m_axib_arsize),
         .arburst(m_axib_arburst),
         .arlock(m_axib_arlock),
         .arvalid(m_axib_arvalid),
         .arready(m_axib_arready),
         .rid(m_axib_rid),
         .rdata(m_axib_rdata),
         .rresp(m_axib_rresp),
         .rlast(m_axib_rlast),
         .rvalid(m_axib_rvalid),
         .rready(m_axib_rready),
         .mem_addr(mem_addra),
         .mem_web(mem_wea),
         .mem_csb(mem_cea),
         .mem_din(mem_dia),
         .mem_dout(mem_doa),
         .aclk(usr_clk),
         .aresetn(usr_rst_n)
);


//assign ram_wea = {~mem_wea[7],~mem_wea[6],~mem_wea[5],~mem_wea[4],~mem_wea[3],~mem_wea[2],~mem_wea[1],~mem_wea[0]};

assign ram_wea = (mem_wea[7:0] == 8'hff) ? 8'h0 : 8'hff; 
  
ram2048x64 u_ram2048x64(
    //single port RAM
     .clka(usr_clk), 
     .cea(~mem_cea), 
     .wea(ram_wea), 
     .dia(mem_dia), 
     .addra(mem_addra[10:0]), 
     .doa(mem_doa)
 );

endmodule
