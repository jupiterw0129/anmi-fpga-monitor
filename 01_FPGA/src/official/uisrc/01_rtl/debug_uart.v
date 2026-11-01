/*===========================================*\
Filename        : debug_uart.v
Description     : Lightweight debug UART transmitter.
                  Periodically sends status + frame count as hex string.
                  Output format (every ~0.5s):
                    S:xx F:xxxxxxxx\r\n
                  Status byte bits:
                    [0] pll_lock (raw PLL output)
                    [1] pll_lock_stable (warmup done)
                    [2] user_link_up (PCIe link)
                    [3] ui_pll_lock (camera PLL)
                    [7:4] reserved
                  Baud: 115200, 8N1
\*===========================================*/
`timescale 1ns/1ps

module debug_uart #(
    parameter CLK_FREQ  = 25_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg         tx,
    input  wire        rx,          // reserved for future use
    input  wire [15:0] status,
    input  wire [31:0] frame_count
);

    localparam BAUD_DIV  = CLK_FREQ / BAUD_RATE;
    localparam INTERVAL  = CLK_FREQ / 2;            // 0.5 second
    localparam MSG_LEN   = 17;                       // "S:xx F:xxxxxxxx\r\n"

    // ©¤©¤ Hex nibble ¡ú ASCII ©¤©¤
    function [7:0] hex_char;
        input [3:0] nibble;
        hex_char = (nibble < 4'd10) ? (8'h30 + {4'd0, nibble})
                                    : (8'h37 + {4'd0, nibble});
    endfunction

    // ©¤©¤ Message buffer ©¤©¤
    reg [7:0] msg [0:MSG_LEN-1];

    // ©¤©¤ State machine ©¤©¤
    localparam S_IDLE  = 3'd0;
    localparam S_LOAD  = 3'd1;
    localparam S_START = 3'd2;
    localparam S_DATA  = 3'd3;
    localparam S_STOP  = 3'd4;

    reg [2:0]  state;
    reg [23:0] tick_cnt;
    reg [15:0] baud_cnt;
    reg [4:0]  msg_idx;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            tick_cnt <= 24'd0;
            baud_cnt <= 16'd0;
            msg_idx  <= 5'd0;
            bit_idx  <= 3'd0;
            tx       <= 1'b1;
            tx_data  <= 8'hFF;
        end else begin
            case (state)
                // ©¤©¤ Wait for interval, then snapshot & build message ©¤©¤
                S_IDLE: begin
                    tx <= 1'b1;
                    if (tick_cnt >= INTERVAL - 1) begin
                        tick_cnt <= 24'd0;
                        // Build message: "S:xx F:xxxxxxxx\r\n"
                        msg[0]  <= 8'h53;  // 'S'
                        msg[1]  <= 8'h3A;  // ':'
                        msg[2]  <= hex_char(status[7:4]);
                        msg[3]  <= hex_char(status[3:0]);
                        msg[4]  <= 8'h20;  // ' '
                        msg[5]  <= 8'h46;  // 'F'
                        msg[6]  <= 8'h3A;  // ':'
                        msg[7]  <= hex_char(frame_count[31:28]);
                        msg[8]  <= hex_char(frame_count[27:24]);
                        msg[9]  <= hex_char(frame_count[23:20]);
                        msg[10] <= hex_char(frame_count[19:16]);
                        msg[11] <= hex_char(frame_count[15:12]);
                        msg[12] <= hex_char(frame_count[11:8]);
                        msg[13] <= hex_char(frame_count[7:4]);
                        msg[14] <= hex_char(frame_count[3:0]);
                        msg[15] <= 8'h0D;  // '\r'
                        msg[16] <= 8'h0A;  // '\n'
                        msg_idx <= 5'd0;
                        state   <= S_LOAD;
                    end else begin
                        tick_cnt <= tick_cnt + 24'd1;
                    end
                end

                // ©¤©¤ Load next byte from message buffer ©¤©¤
                S_LOAD: begin
                    if (msg_idx >= MSG_LEN) begin
                        state <= S_IDLE;
                    end else begin
                        tx_data  <= msg[msg_idx];
                        baud_cnt <= 16'd0;
                        bit_idx  <= 3'd0;
                        state    <= S_START;
                    end
                end

                // ©¤©¤ Start bit (low for 1 baud period) ©¤©¤
                S_START: begin
                    tx <= 1'b0;
                    if (baud_cnt >= BAUD_DIV - 1) begin
                        baud_cnt <= 16'd0;
                        state    <= S_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end

                // ©¤©¤ Data bits [0..7], LSB first ©¤©¤
                S_DATA: begin
                    tx <= tx_data[bit_idx];
                    if (baud_cnt >= BAUD_DIV - 1) begin
                        baud_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end

                // ©¤©¤ Stop bit (high for 1 baud period) ©¤©¤
                S_STOP: begin
                    tx <= 1'b1;
                    if (baud_cnt >= BAUD_DIV - 1) begin
                        baud_cnt <= 16'd0;
                        msg_idx  <= msg_idx + 5'd1;
                        state    <= S_LOAD;
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
