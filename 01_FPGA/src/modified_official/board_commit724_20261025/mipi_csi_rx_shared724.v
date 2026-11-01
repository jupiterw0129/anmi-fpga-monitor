`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/17 09:00:03
// Design Name: 
// Module Name: mipi_csi_rx
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


module mipi_csi_rx_shared724#(
    parameter MIPI_LAN  = 4,
    parameter DEVICE    = "EG"
    
)(
input wire                I_debug_button  ,   

    input wire                I_ref_clock     ,   
    input wire                I_clk_hs_rx_p   , 
    input wire                I_reset_n       ,    
    input wire [MIPI_LAN-1:0] I_hs_data_p     ,
    input wire                I_enable        ,
    input wire                I_raw12_mode    ,
    output wire               O_hs_div_clk    ,

    input  wire               m_axis_video_aclk,
    input  wire               m_axis_video_aresetn,
	input  wire               m_axis_video_tready,
    output wire               m_axis_video_tuser,
    output wire               m_axis_video_tlast,
    output wire               m_axis_video_tvalid,
    output wire [39:0]        m_axis_video_tdata,
    output wire               O_auto_delay_done,

    // 调试总线（hs_div_clk 域，需要在顶层 CDC 采样）
    // [3:0] = 各 lane 字节对齐有效
    // [4]   = word 对齐有效
    // [5]   = in_frame（包处理器检测到帧起始）
    // [6]   = payload_valid（包数据输出有效）
    // [7]   = unpack_valid（10-bit 解包有效）
    output wire [7:0]         O_dbg_mipi,
    // delay 调试总线（hs_div_clk 域，需要在顶层 CDC 采样）
    // [5:0] = 当前生效 delay tap
    // [6]   = 手动扫 tap 模式已锁存
    // [7]   = 本拍 delay code load pulse
    output wire [7:0]         O_dbg_delay,
    output wire [5:0]         O_dbg_best_len,
    input wire [5:0] I_delay_config,
    input wire I_jpeg_select,
    input wire I_checked_packet_done,I_checked_sync_wait,
    input wire I_checked_header_attempt,I_checked_header_valid,I_checked_header_bad,
    output wire [31:0] O_byte_data,
    output wire O_byte_valid,O_byte_reset_n,
    input wire I_diag_capture,
    input wire [7:0] I_diag_index,
    output wire [31:0] O_diag_data,
    output wire [31:0]        O_fifo_overflow_count
    );

    wire [MIPI_LAN-1:0]     w_rx_byte_data_align_vaild;
    wire [8*MIPI_LAN-1:0]   w_rx_byte_data_align;
    wire [8*MIPI_LAN-1:0]   w_word_align_data;
    wire                    w_word_align_data_vaild;
    wire [31:0]             w_word_gear_data;
    wire                    w_word_gear_data_vaild;

    wire [31:0]             w_payload_out;
    wire                    w_payload_valid;
    wire                    w_hs_div_clk ;
    wire                    w_reset_out;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] byte_enable_sync;
    always @(posedge w_hs_div_clk or negedge w_reset_out) begin
        if (!w_reset_out) byte_enable_sync <= 2'b00;
        else byte_enable_sync <= {byte_enable_sync[0], I_enable};
    end
    wire [2:0] payload_bytes;
    wire payload_raw12;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] raw12_sync;
    always @(posedge w_hs_div_clk or negedge w_reset_out) begin
        if (!w_reset_out) raw12_sync <= 2'b11;
        else raw12_sync <= {raw12_sync[0], I_raw12_mode};
    end
    wire [39:0]             w_data_out_unpack;    
    wire                    w_dout_unpack_valid;
    wire                    w_delay_value;
    wire                    w_sync_wait;
    wire                    w_packet_done;
    wire                    w_vsync_out;
    wire                    w_in_frame;
    wire                    w_in_line;

wire header_attempt, header_valid, header_ecc_bad, header_filter_bad, payload_timeout;
   assign O_hs_div_clk = w_hs_div_clk;
    assign O_byte_data=w_word_gear_data;
    assign O_byte_valid=w_word_gear_data_vaild;
    assign O_byte_reset_n=w_reset_out;
    // Mode changes are idle-only and reset the video path at board top.
    (* async_reg="true",dont_touch="true" *) reg [1:0] jpeg_select_sync;
    always @(posedge w_hs_div_clk or negedge w_reset_out)
        if(!w_reset_out) jpeg_select_sync<=0;
        else jpeg_select_sync<={jpeg_select_sync[0],I_jpeg_select};
    wire selected_done=jpeg_select_sync[1] ? I_checked_packet_done : w_packet_done;
    wire selected_wait=jpeg_select_sync[1] ? I_checked_sync_wait : w_sync_wait;
    wire selected_attempt=jpeg_select_sync[1] ? I_checked_header_attempt : header_attempt;
    wire selected_valid=jpeg_select_sync[1] ? I_checked_header_valid : header_valid;
    wire selected_bad=jpeg_select_sync[1] ? I_checked_header_bad : header_ecc_bad;

    assign O_dbg_mipi = {w_dout_unpack_valid,
                         w_payload_valid,
                         w_in_frame,
                         w_word_align_data_vaild,
                         w_rx_byte_data_align_vaild};
 
wire [31:0] raw_bytes;
wire [1023:0] diag_counters;
rx_diag712 rx_diagnostics (
    .clock(w_hs_div_clk), .reset_n(w_reset_out), .enable(byte_enable_sync[1]),
    .raw_bytes(raw_bytes), .aligned_bytes(w_rx_byte_data_align),
    .lane_valid(w_rx_byte_data_align_vaild), .word_valid(w_word_gear_data_vaild),
    .header_attempt(header_attempt), .header_valid(header_valid),
    .header_ecc_bad(header_ecc_bad), .header_filter_bad(header_filter_bad),
    .header_data(w_word_gear_data), .payload_valid(w_payload_valid),
    .payload_bytes(payload_bytes), .unpack_valid(w_dout_unpack_valid),
    .packet_timeout(payload_timeout), .delay_status(O_dbg_delay),
    .best_length(O_dbg_best_len), .auto_done(O_auto_delay_done), .counters(diag_counters)
);
rx_snapshot714 rx_diagnostic_snapshot (
    .source_clk(w_hs_div_clk), .source_reset_n(w_reset_out), .source_data(diag_counters),
    .dest_clk(m_axis_video_aclk), .dest_reset_n(m_axis_video_aresetn),
    .capture(I_diag_capture), .index(I_diag_index), .read_data(O_diag_data)
);
csi_rx_phy715 #(
    .MIPI_LAN   (MIPI_LAN),
    .DEVICE     (DEVICE)
)u_csi_rx_phy(

.I_debug_button(I_debug_button),
    .I_delay_config(I_delay_config),
    .I_header_good(selected_attempt && selected_valid &&
                   w_word_gear_data[5:0] == (raw12_sync[1] ? 6'h2c : 6'h2b) &&
                   w_word_gear_data[23:8] >= 16'd128 && w_word_gear_data[23:8] <= 16'd8192),
    .I_header_bad(selected_attempt && selected_bad),

    .I_ref_clock                (I_ref_clock),
    .I_clk_hs_rx_p              (I_clk_hs_rx_p              ),
    .I_reset_n                  (I_reset_n                  ),
    .I_hs_data_p                (I_hs_data_p                ),
    .I_enable                   (I_enable                   ),
    .I_wait_for_sync            (selected_wait                ),
    .I_packet_done              (selected_done              ),
    .O_hs_div_clk               (w_hs_div_clk               ),
    .O_reset_out                (w_reset_out                ),
    .O_rx_byte_data_align_vaild (w_rx_byte_data_align_vaild ),
    .O_rx_byte_data_align       (w_rx_byte_data_align       ),
    .O_delay_value              (w_delay_value),
    .O_auto_delay_done          (O_auto_delay_done),
    .O_dbg_delay                (O_dbg_delay),
    .O_raw_bytes(raw_bytes),
    .O_dbg_best_len             (O_dbg_best_len)
);

csi_rx_word_align #(
    .MIPI_LAN(MIPI_LAN)
)u_csi_rx_word_align(
    .I_word_clock      (w_hs_div_clk        ),
    .I_reset_n         (w_reset_out         ),
    .I_enable          (byte_enable_sync[1]            ),
    .I_packet_done     (selected_done       ),
    .I_wait_for_sync   (selected_wait         ),
    .O_packet_done_out (),
    .I_word_in         (w_rx_byte_data_align),
    .I_valid_in        (w_rx_byte_data_align_vaild),
    .O_word_out        (w_word_align_data   ),
    .O_valid_out       (w_word_align_data_vaild)
);

csi_rx_word_gear_box #(
    .MIPI_LAN(MIPI_LAN)
)u_csi_rx_word_gear_box(
    .I_word_clock      (w_hs_div_clk           ),
    .I_reset_n         (w_reset_out            ),
    .I_enable          (byte_enable_sync[1]    ),
    .I_lane_data       (w_word_align_data      ),
    .I_lane_data_valid (w_word_align_data_vaild),
    .O_word_out        (w_word_gear_data       ),
    .O_valid_out       (w_word_gear_data_vaild )
);


csi_rx_packet_handler715 #(
    .MIPI_LAN(MIPI_LAN)
)u_csi_rx_packet_handler(
    .I_clock         (w_hs_div_clk           ),
    .I_reset_n       (w_reset_out            ),
    .I_enable        (byte_enable_sync[1]    ),
    .I_data          (w_word_gear_data       ),
    .I_data_valid    (w_word_gear_data_vaild ),
    .O_sync_wait     (w_sync_wait            ),
    .O_packet_done   (w_packet_done          ),
    .O_header_attempt(header_attempt), .O_header_valid(header_valid),
    .O_header_ecc_bad(header_ecc_bad), .O_header_filter_bad(header_filter_bad),
    .O_payload_timeout(payload_timeout),
    .I_default_raw12(raw12_sync[1]),
    .O_raw12(payload_raw12),
    .O_payload_bytes(payload_bytes),
    .O_payload_out   (w_payload_out          ),
    .O_payload_valid (w_payload_valid        ),
    .O_vsync_out     (w_vsync_out            ),
    .O_in_frame      (w_in_frame             ),
    .O_in_line       (w_in_line              )
);


csi_rx_10bit_unpack u_csi_rx_10bit_unpack(
    .I_clock        (w_hs_div_clk       ),
    .I_reset_n      (w_reset_out        ),
    .I_enable       (byte_enable_sync[1]           ),
    .I_line_in      (w_in_line          ),
    .I_raw12(payload_raw12),
    .I_valid_bytes(payload_bytes),
    .I_data_in      (w_payload_out      ),
    .I_din_valid    (w_payload_valid    ),
    .O_data_out     (w_data_out_unpack  ),
    .O_dout_valid   (w_dout_unpack_valid)
);

csi_rx_vid2stream u_csi_rx_vid2stream(
    .I_data_clk           (w_hs_div_clk         ),
    .I_reset_n            (w_reset_out          ),
    .I_packet_done        (w_packet_done        ),
    .I_packet_line        (w_in_line            ),
    .I_packet_frame       (w_in_frame           ),
    .I_data_unpack        (w_data_out_unpack    ),
    .I_dout_unpack_valid  (w_dout_unpack_valid  ),
    .m_axis_video_aclk    (m_axis_video_aclk    ),
    .m_axis_video_aresetn (m_axis_video_aresetn ),
    .m_axis_video_tready  (m_axis_video_tready  ),
    .m_axis_video_tuser   (m_axis_video_tuser   ),
    .m_axis_video_tlast   (m_axis_video_tlast   ),
    .m_axis_video_tvalid  (m_axis_video_tvalid  ),
    .m_axis_video_tdata   (m_axis_video_tdata   ),
    .O_fifo_overflow_count (O_fifo_overflow_count)
);

endmodule
