`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/11 10:55:01
// Design Name: 
// Module Name: csi_rx_idelayctrl_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module csi_rx_idelayctrl_gen(ref_clock, reset, rdy);
   parameter [32*8:1] fpga_series = "ULTRASCALE_PLUS";
   input              ref_clock;
   input              reset;
   output             rdy;
   
   generate
      if (fpga_series == "VIRTEX6" | fpga_series == "7SERIES")
      begin : gen_v6_7s
         
      IDELAYCTRL IDELAYCTRL_inst (
      .RDY(rdy),       // 1-bit output: Ready output
      .REFCLK(ref_clock), // 1-bit input: Reference clock input
      .RST(reset)        // 1-bit input: Active high reset input
   );
      end
   endgenerate
   
   generate
      if (fpga_series == "ULTRASCALE_PLUS")
      begin : gen_us
         
         IDELAYCTRL #("ULTRASCALE") delayctrl(.rdy(rdy), .refclk(ref_clock), .rst(reset));
      end
   endgenerate
   
endmodule
