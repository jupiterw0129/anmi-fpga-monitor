module csi_rx_hs_clk_phy(
    input  wire I_clk_hs_rx_p , 
    input  wire I_clk_hs_rx_n , 
    input  wire I_reset_n     , 
    output wire O_hs_ddr_clk  , 
    output wire O_hs_div_clk  
   );
    wire w_clk_hs_rx      ;
    wire w_clk_hs_rx_buf  ;
    wire w_hs_div_clk     ;

DR1_PHY_LCLK#(
   .CEMD    ("SYNC"),
   .CLKSEL  ("ORG"),
   .DIV     ("4"),
   .LCLK    ("DIV2TO8")
)u_PHY_LCLK (
   .clkin      (w_clk_hs_rx),
   .rst        (~I_reset_n),
   .ce         (1'b1),
   .clkout     (w_clk_hs_rx_buf),
   .clkdivout  (w_hs_div_clk)
);
    assign O_hs_ddr_clk = w_clk_hs_rx_buf  ;
    assign O_hs_div_clk = w_hs_div_clk ;

   endmodule