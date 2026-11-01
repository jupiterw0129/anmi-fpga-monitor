`timescale 1ns / 1ps

module csi_rx_phy715#(
    parameter MIPI_LAN  = 4 ,
    parameter DEVICE    = "PH1A"
)(

input wire I_debug_button,
input wire [5:0] I_delay_config,
input wire I_header_good,
input wire I_header_bad,

    input wire                      I_ref_clock     ,   
    input wire                      I_clk_hs_rx_p   , 
    input wire                      I_reset_n       ,    
    input wire [MIPI_LAN-1:0]       I_hs_data_p     ,
    input wire                      I_enable        ,
    input  wire                     I_wait_for_sync ,
    input  wire                     I_packet_done   ,
    output wire                     O_hs_div_clk    ,
    output wire                     O_reset_out     ,      
    output wire [MIPI_LAN-1:0]      O_rx_byte_data_align_vaild,
    output wire [8*MIPI_LAN-1:0]    O_rx_byte_data_align, 
    output wire                     O_delay_value        ,
    output wire                     O_auto_delay_done,
    output wire [7:0]               O_dbg_delay,
    output wire [31:0] O_raw_bytes,
    output wire [5:0]               O_dbg_best_len
    );

wire                    w_hs_clk   ;
wire                    w_hs_clk_x2;
wire                    w_hs_clk_x4;
wire                    w_reset_out  ;
(* async_reg = "true", dont_touch = "true" *) reg [1:0] byte_enable_sync;
always @(posedge w_hs_clk or negedge w_reset_out) begin
    if (!w_reset_out) byte_enable_sync <= 2'b00;
    else byte_enable_sync <= {byte_enable_sync[0], I_enable};
end

wire [8*MIPI_LAN-1:0]   w_rx_byte_data;                   
wire [MIPI_LAN-1:0]     w_rx_byte_data_align_vaild;       
wire [8*MIPI_LAN-1:0]   w_rx_byte_data_align;             
wire [5:0]              w_auto_delay_value;
wire 	                w_auto_delay_vaild;
wire                    w_auto_delay_done;
wire [5:0]              w_auto_delay_best_len;
wire [5:0]              w_lane_delay_value;
wire                    w_lane_delay_vaild;
wire 	                w_delay_data_val[MIPI_LAN-1:0];
wire r_manual_mode;
wire calibration_success;

assign O_raw_bytes = w_rx_byte_data;
assign O_hs_div_clk                 = w_hs_clk              ;
assign O_reset_out                  = w_reset_out               ;    
assign O_rx_byte_data_align_vaild   = w_rx_byte_data_align_vaild;
assign O_rx_byte_data_align         = w_rx_byte_data_align      ;
assign O_delay_value                = w_lane_delay_value[0]     ;
assign O_auto_delay_done            = w_auto_delay_done && calibration_success;
assign O_dbg_best_len               = w_auto_delay_best_len;
assign O_dbg_delay                  = {w_lane_delay_vaild, r_manual_mode, w_lane_delay_value};

assign w_lane_delay_value = w_auto_delay_value;
assign w_lane_delay_vaild = w_auto_delay_vaild;

rx_clk_gen #(
    .DEVICE (DEVICE)
)u_rx_clk_gen(
    .I_mipi_clk_p (I_clk_hs_rx_p ),
    .I_rst        (~I_reset_n    ),
    .O_clk        (w_hs_clk      ),
    .O_clk_x2     (w_hs_clk_x2   ),
    .O_clk_x4     (w_hs_clk_x4   ) 

);

csi_rx_clock_det u_csi_rx_clock_det(
    .I_ref_clock (I_ref_clock ),
    .I_ext_clock (w_hs_clk),
    .I_enable    (I_enable    ),
    .I_reset_in  (I_reset_n  ),
    .O_reset_out (w_reset_out )
);

rx_delay_control714 calibration (
    .clock(w_hs_clk), .reset_n(w_reset_out), .config_async(I_delay_config),
    .header_good(I_header_good), .header_bad(I_header_bad),
    .delay_value(w_auto_delay_value), .delay_load(w_auto_delay_vaild),
    .done(w_auto_delay_done), .success(calibration_success), .manual_active(r_manual_mode),
    .best_length(w_auto_delay_best_len)
);

wire shared_iddr_reset_n;
shared_iddr_reset711d iddr_release (
    w_hs_clk_x4, w_reset_out, shared_iddr_reset_n
);

generate 
genvar i;
for (i=0; i<MIPI_LAN; i=i+1) begin : gen_channel_wrapper	
csi_rx_hs_data_phy715 u_csi_rx_hs_data_phy(
    .I_rxclk        (w_hs_clk      ),
    .I_rxclk_div_x2 (w_hs_clk_x2   ),
    .I_rxclk_div_x4 (w_hs_clk_x4   ),
    .I_reset_n      (w_reset_out   ),
    .I_iddr_reset_n (shared_iddr_reset_n),
    .I_hs_data_p    (I_hs_data_p[i]),
    .I_delay_value  (w_lane_delay_value),
    .I_delay_vaild  (w_lane_delay_vaild),
    .O_rx_data      (w_rx_byte_data[(8 * i) + 7:8 * i]),
    .O_delay_data_val(w_delay_data_val[i])
);

csi_rx_byte_align u_csi_rx_byte_align(
    .I_clock           (w_hs_clk    ),
    .I_reset_n         (w_reset_out     ),
    .I_enable          (byte_enable_sync[1] && w_delay_data_val[i]),
    .I_lan_data_in     (w_rx_byte_data[(8 * i) + 7:8 * i]),
    .I_wait_for_sync   (I_wait_for_sync ),
    .I_packet_done     (I_packet_done   ),
    .O_data_out_vaild  (w_rx_byte_data_align_vaild[i]),
    .O_data_out        (w_rx_byte_data_align[(8 * i) + 7:8 * i])
);

end
endgenerate	

endmodule
