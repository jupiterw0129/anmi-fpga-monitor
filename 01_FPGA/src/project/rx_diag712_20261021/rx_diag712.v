module rx_diag712 (
    input wire clock,
    input wire reset_n,
    input wire enable,
    input wire [31:0] raw_bytes,
    input wire [31:0] aligned_bytes,
    input wire [3:0] lane_valid,
    input wire word_valid,
    input wire header_attempt,
    input wire header_valid,
    input wire header_ecc_bad,
    input wire header_filter_bad,
    input wire [31:0] header_data,
    input wire payload_valid,
    input wire [2:0] payload_bytes,
    input wire unpack_valid,
    input wire packet_timeout,
    input wire [7:0] delay_status,
    input wire [5:0] best_length,
    input wire auto_done,
    output wire [1023:0] counters
);
    reg [31:0] count [0:31];
    reg [3:0] previous_valid;
    reg line_active;
    integer counter_index;
    integer lane_index;
    wire accepted = header_attempt && header_valid;
    wire [5:0] data_type = header_data[5:0];
    wire image_line = data_type == 6'h12 || data_type == 6'h2b ||
                      data_type == 6'h2c || data_type == 6'h37;
    genvar word_index;
    generate for (word_index = 0; word_index < 32; word_index = word_index + 1) begin : words
        assign counters[word_index*32 +: 32] = count[word_index];
    end endgenerate
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            for (counter_index = 0; counter_index < 32; counter_index = counter_index + 1)
                count[counter_index] <= 0;
            previous_valid <= 0;
            line_active <= 0;
        end else begin
            count[0] <= count[0] + 1'b1;
            count[1] <= raw_bytes;
            count[2] <= aligned_bytes;
            count[3] <= {13'd0, auto_done, best_length, delay_status, lane_valid};
            previous_valid <= lane_valid;
            if (enable) begin
                for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
                    if (lane_valid[lane_index] && !previous_valid[lane_index])
                        count[4+lane_index] <= count[4+lane_index] + 1'b1;
                    if (raw_bytes[lane_index*8 +: 8] == 8'hb8)
                        count[8+lane_index] <= count[8+lane_index] + 1'b1;
                end
                if (word_valid) count[12] <= count[12] + 1'b1;
                if (header_attempt) begin
                    count[13] <= count[13] + 1'b1;
                    if (header_valid) begin
                        count[14] <= count[14] + 1'b1;
                        count[18] <= header_data;
                    end else count[19] <= header_data;
                    if (header_ecc_bad) count[15] <= count[15] + 1'b1;
                    if (header_filter_bad) count[16] <= count[16] + 1'b1;
                end
                if (packet_timeout) count[17] <= count[17] + 1'b1;
                if (payload_valid) count[20] <= count[20] + {29'd0, payload_bytes};
                if (unpack_valid) begin
                    count[21] <= count[21] + 1'b1;
                    if (line_active) count[22] <= count[22] + 1'b1;
                end
                if (accepted) begin
                    if (line_active) begin
                        count[23] <= count[22];
                        line_active <= 0;
                    end
                    if (data_type == 0) begin
                        count[24] <= count[24] + 1'b1;
                        count[26] <= 0;
                    end
                    if (data_type == 1) begin
                        count[25] <= count[25] + 1'b1;
                        count[27] <= count[26];
                    end
                    if (image_line) begin
                        count[22] <= 0;
                        count[26] <= count[26] + 1'b1;
                        count[28] <= {10'd0, data_type, header_data[23:8]};
                        line_active <= 1;
                    end
                    if (data_type == 6'h2b) count[29] <= count[29] + 1'b1;
                    if (data_type == 6'h2c) count[30] <= count[30] + 1'b1;
                    if (data_type == 6'h12 || data_type == 6'h37)
                        count[31] <= count[31] + 1'b1;
                end
            end
        end
    end
endmodule
