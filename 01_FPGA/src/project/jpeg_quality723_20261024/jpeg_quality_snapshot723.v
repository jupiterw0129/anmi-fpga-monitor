module jpeg_quality_snapshot723 (
    input wire clk, input wire reset_n,
    input wire [3:0] read_index, output reg [31:0] read_data,
    input wire [6:0] requested_quality, active_quality, configured_quality,
    input wire config_ready, config_error,
    input wire [31:0] encoder_debug,
    input wire [7:0] jpeg_data,
    input wire jpeg_valid, jpeg_last,
    input wire [16:0] jpeg_bytes
);
    wire [31:0] context_word = {9'd0, config_error, config_ready,
        requested_quality, active_quality, configured_quality};
    wire mismatch = active_quality != configured_quality ||
        active_quality != encoder_debug[14:8] || active_quality != encoder_debug[21:15];
    reg [31:0] started, completed, mismatches, first_encoder, first_context;
    reg [31:0] last_encoder, last_context, last_end, dqt_count, dqt_context;
    reg [7:0] dqt_byte;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            started <= 0; completed <= 0; mismatches <= 0;
            first_encoder <= 0; first_context <= 0;
            last_encoder <= 0; last_context <= 0; last_end <= 0;
            dqt_byte <= 0; dqt_count <= 0; dqt_context <= 0;
        end else if (jpeg_valid) begin
            if (jpeg_bytes == 0) begin
                started <= started + 1'b1;
                last_encoder <= encoder_debug;
                last_context <= context_word;
                if (mismatch) begin
                    mismatches <= mismatches + 1'b1;
                    if (mismatches == 0) begin
                        first_encoder <= encoder_debug;
                        first_context <= context_word;
                    end
                end
            end
            // Current non-EXIF JFIF header: first luma DQT value is byte 25 (zero based).
            if (jpeg_bytes == 25) begin
                dqt_byte <= jpeg_data;
                dqt_count <= dqt_count + 1'b1;
                dqt_context <= context_word;
            end
            if (jpeg_last) begin
                completed <= completed + 1'b1;
                last_end <= encoder_debug;
            end
        end
    end
    always @* begin
        case (read_index)
            0: read_data = 32'h51443723;
            1: read_data = encoder_debug;
            2: read_data = context_word;
            3: read_data = started;
            4: read_data = mismatches;
            5: read_data = first_encoder;
            6: read_data = first_context;
            7: read_data = last_encoder;
            8: read_data = last_context;
            9: read_data = {24'd0,dqt_byte};
            10: read_data = dqt_count;
            11: read_data = completed;
            12: read_data = last_end;
            13: read_data = dqt_context;
            14: read_data = 0;
            15: read_data = 1;
        endcase
    end
endmodule
