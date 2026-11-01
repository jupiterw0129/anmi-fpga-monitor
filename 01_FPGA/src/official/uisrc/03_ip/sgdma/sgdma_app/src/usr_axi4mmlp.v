//`timescale 1ns/1ps
//`ifdef DEBUG_MODE
//  `include "para_def.vh"
//`endif
module usr_axi4mmlp#(
    parameter   DLY         = 1,
    parameter   ODATA_WIDTH = 128, 
    parameter   OKEEP_WIDTH = ODATA_WIDTH/8
    )(
    input   wire   usr_rst_n,
    input   wire   usr_clk,
    input   wire   s0_axis_c2h_rst_i,
    input   wire   m0_axis_h2c_rst_i,

    // output  wire   [12:0]                usr_ram_pntr_o,
    input   wire                        usr_h2c0_wren_i,
    input   wire   [OKEEP_WIDTH-1:0]    usr_h2c0_wstrb_i,
    input   wire   [15:0]               usr_h2c0_wraddr_i,
    input   wire   [ODATA_WIDTH-1:0]    usr_h2c0_dt_i,

    input   wire                        usr_c2h0_rden_i,
    input   wire   [15:0]               usr_c2h0_rdaddr_i,
    output  wire   [ODATA_WIDTH-1:0]    usr_c2h0_dt_o
);
`ifdef DEBUG_MODE
localparam ADDRWIDTH = $clog2(1024*256/OKEEP_WIDTH);
`else
localparam ADDRWIDTH = $clog2(1024*128/OKEEP_WIDTH);
`endif

wire   [ODATA_WIDTH-1:0]    bram_din;
wire   [ADDRWIDTH-1:0]      bram_wraddr;
wire   [ADDRWIDTH-1:0]      bram_rdaddr; 
wire   [ODATA_WIDTH-1:0]    bram_dout;
wire   bram_wren;
wire   bram_rden;
wire   [OKEEP_WIDTH-1:0]    bram_wbe;
assign bram_din   = usr_h2c0_dt_i;
assign bram_wren  = usr_h2c0_wren_i;
assign bram_wraddr= usr_h2c0_wraddr_i;
assign bram_wbe   = usr_h2c0_wstrb_i ;


(* ram_style = "bram" *)reg [ODATA_WIDTH-1:0]   dat_ram [2**ADDRWIDTH-1:0];
reg     [ODATA_WIDTH-1:0]    dat_ram_out;
integer     i,j;
//Initial value
initial begin
    for (j = 0; j < 2**ADDRWIDTH; j=j+1) begin
        dat_ram[j] = 'd0;
    end
end
always @(posedge usr_clk) begin
    for(i=0;i<OKEEP_WIDTH;i=i+1) begin
        if( bram_wren && bram_wbe[i] ) begin //
            dat_ram[bram_wraddr][i*8+:8]  <= bram_din[i*8+:8];
        end
    end  
end 
always @(posedge usr_clk) begin
    if(bram_rden) begin 
        dat_ram_out     <= dat_ram[bram_rdaddr];
    end
end 

// assign  bram_dout       = dat_ram_out;
assign  bram_rden       = usr_c2h0_rden_i;
assign  bram_rdaddr     = usr_c2h0_rdaddr_i;
assign  usr_c2h0_dt_o   = dat_ram_out;//bram_dout;


endmodule
