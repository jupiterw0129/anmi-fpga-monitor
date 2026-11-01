module morphology_rgb4 #(
    parameter IMAGE_WIDTH = 1280
) (
    input wire clk,
    input wire reset_n,
    input wire [1:0] requested_mode,
    output reg [1:0] active_mode,
    input wire [95:0] input_data,
    input wire input_valid,
    output wire input_ready,
    input wire input_last,
    input wire input_user,
    output reg [95:0] output_data,
    output reg output_valid,
    input wire output_ready,
    output reg output_last,
    output reg output_user
);
    // Async assertion remains immediate. Admit no input until the local
    // register releases, so the RAM write enable has a nearby clocked source.
    (* dont_touch = "true" *) reg ram_live;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) ram_live <= 1'b0;
        else ram_live <= 1'b1;
    localparam WORDS = IMAGE_WIDTH / 4;
    localparam ADDRESS_BITS = WORDS > 1 ? $clog2(WORDS) : 1;
    reg [31:0] previous_row [0:WORDS-1];
    reg [31:0] second_row [0:WORDS-1];
    reg [ADDRESS_BITS-1:0] column_word;
    reg [1:0] row_count;
    wire advance = !output_valid || output_ready;
    wire [ADDRESS_BITS-1:0] address = input_user ? 0 : column_word;
    wire [1:0] current_row = input_user ? 0 : row_count;
    wire [31:0] input_luma;
    reg stage_valid, stage_last, stage_user, stage_first;
    reg [1:0] stage_mode, stage_row;
    reg [95:0] stage_rgb;
    reg [31:0] stage_top, stage_middle, stage_bottom;
    reg [15:0] left_top, left_middle, left_bottom;
    wire [47:0] window_top = {stage_top, stage_first ? 16'd0 : left_top};
    wire [47:0] window_middle = {stage_middle, stage_first ? 16'd0 : left_middle};
    wire [47:0] window_bottom = {stage_bottom, stage_first ? 16'd0 : left_bottom};
    reg reduced_valid, reduced_last, reduced_user;
    reg [1:0] reduced_mode;
    reg [3:0] reduced_border;
    reg [95:0] reduced_rgb;
    reg [7:0] row_min_top [0:3];
    reg [7:0] row_min_middle [0:3];
    reg [7:0] row_min_bottom [0:3];
    reg [7:0] row_max_top [0:3];
    reg [7:0] row_max_middle [0:3];
    reg [7:0] row_max_bottom [0:3];
    integer lane;

    function [7:0] luma;
        input [23:0] pixel;
        reg [15:0] red, green, blue;
        begin
            red = {8'd0, pixel[23:16]};
            green = {8'd0, pixel[15:8]};
            blue = {8'd0, pixel[7:0]};
            luma = ((red << 6) + (red << 3) + (red << 2) + red
                  + (green << 7) + (green << 4) + (green << 2) + (green << 1)
                  + (blue << 4) + (blue << 3) + (blue << 2) + blue) >> 8;
        end
    endfunction

    function [7:0] minimum3;
        input [7:0] first, second, third;
        reg [7:0] pair;
        begin
            pair = first < second ? first : second;
            minimum3 = pair < third ? pair : third;
        end
    endfunction

    function [7:0] maximum3;
        input [7:0] first, second, third;
        reg [7:0] pair;
        begin
            pair = first > second ? first : second;
            maximum3 = pair > third ? pair : third;
        end
    endfunction

    genvar pixel_lane;
    generate for (pixel_lane = 0; pixel_lane < 4; pixel_lane = pixel_lane + 1) begin: lanes
        assign input_luma[pixel_lane*8 +: 8] = luma(input_data[pixel_lane*24 +: 24]);
    end endgenerate
    assign input_ready = ram_live && advance;

    always @(posedge clk) begin
        if (ram_live && advance && input_valid) begin
            stage_top <= second_row[address];
            stage_middle <= previous_row[address];
            second_row[address] <= previous_row[address];
            previous_row[address] <= input_luma;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            column_word <= 0;
            row_count <= 0;
            active_mode <= 0;
            stage_valid <= 0;
            stage_last <= 0;
            stage_user <= 0;
            stage_first <= 0;
            stage_mode <= 0;
            stage_row <= 0;
            stage_rgb <= 0;
            stage_bottom <= 0;
            left_top <= 0;
            left_middle <= 0;
            left_bottom <= 0;
            reduced_valid <= 0;
            reduced_last <= 0;
            reduced_user <= 0;
            reduced_mode <= 0;
            reduced_border <= 0;
            reduced_rgb <= 0;
            output_data <= 0;
            output_valid <= 0;
            output_last <= 0;
            output_user <= 0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                row_min_top[lane] <= 0;
                row_min_middle[lane] <= 0;
                row_min_bottom[lane] <= 0;
                row_max_top[lane] <= 0;
                row_max_middle[lane] <= 0;
                row_max_bottom[lane] <= 0;
            end
        end else if (advance) begin
            output_valid <= reduced_valid;
            if (reduced_valid) begin
                output_last <= reduced_last;
                output_user <= reduced_user;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (reduced_mode == 0 || reduced_mode == 3)
                        output_data[lane*24 +: 24] <= reduced_rgb[lane*24 +: 24];
                    else if (reduced_border[lane])
                        output_data[lane*24 +: 24] <= 0;
                    else if (reduced_mode == 1)
                        output_data[lane*24 +: 24] <= {3{minimum3(row_min_top[lane], row_min_middle[lane], row_min_bottom[lane])}};
                    else
                        output_data[lane*24 +: 24] <= {3{maximum3(row_max_top[lane], row_max_middle[lane], row_max_bottom[lane])}};
                end
            end
            reduced_valid <= stage_valid;
            if (stage_valid) begin
                reduced_last <= stage_last;
                reduced_user <= stage_user;
                reduced_mode <= stage_mode;
                reduced_rgb <= stage_rgb;
                left_top <= stage_top[31:16];
                left_middle <= stage_middle[31:16];
                left_bottom <= stage_bottom[31:16];
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    reduced_border[lane] <= stage_row < 2 || (stage_first && lane < 2);
                    row_min_top[lane] <= minimum3(window_top[lane*8 +: 8], window_top[lane*8+8 +: 8], window_top[lane*8+16 +: 8]);
                    row_min_middle[lane] <= minimum3(window_middle[lane*8 +: 8], window_middle[lane*8+8 +: 8], window_middle[lane*8+16 +: 8]);
                    row_min_bottom[lane] <= minimum3(window_bottom[lane*8 +: 8], window_bottom[lane*8+8 +: 8], window_bottom[lane*8+16 +: 8]);
                    row_max_top[lane] <= maximum3(window_top[lane*8 +: 8], window_top[lane*8+8 +: 8], window_top[lane*8+16 +: 8]);
                    row_max_middle[lane] <= maximum3(window_middle[lane*8 +: 8], window_middle[lane*8+8 +: 8], window_middle[lane*8+16 +: 8]);
                    row_max_bottom[lane] <= maximum3(window_bottom[lane*8 +: 8], window_bottom[lane*8+8 +: 8], window_bottom[lane*8+16 +: 8]);
                end
            end
            stage_valid <= ram_live && input_valid;
            if (ram_live && input_valid) begin
                stage_rgb <= input_data;
                stage_bottom <= input_luma;
                stage_last <= input_last;
                stage_user <= input_user;
                stage_first <= address == 0;
                stage_row <= current_row;
                stage_mode <= input_user ? requested_mode : active_mode;
                if (input_user) active_mode <= requested_mode;
                if (input_last) begin
                    column_word <= 0;
                    row_count <= current_row < 2 ? current_row + 1'b1 : 2;
                end else begin
                    column_word <= address + 1'b1;
                    row_count <= current_row;
                end
            end
        end
    end
endmodule
