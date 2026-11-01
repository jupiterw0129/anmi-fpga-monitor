module sobel_rgb4 #(
    parameter IMAGE_WIDTH = 1280
) (
    input wire clk,
    input wire reset_n,
    input wire requested_enable,
    output reg active_enable,
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
    wire [ADDRESS_BITS-1:0] read_address = input_user ? 0 : column_word;
    wire [1:0] current_row = input_user ? 0 : row_count;
    reg stage_valid, stage_last, stage_user, stage_enable, stage_first;
    reg [1:0] stage_row;
    reg [95:0] stage_rgb;
    reg [31:0] stage_top, stage_middle, stage_bottom;
    reg [15:0] left_top, left_middle, left_bottom;
    wire [47:0] window_top = {stage_top, stage_first ? 16'd0 : left_top};
    wire [47:0] window_middle = {stage_middle, stage_first ? 16'd0 : left_middle};
    wire [47:0] window_bottom = {stage_bottom, stage_first ? 16'd0 : left_bottom};
    reg partial_valid, partial_last, partial_user, partial_enable;
    reg [3:0] partial_border;
    reg [95:0] partial_rgb;
    reg signed [8:0] difference_top [0:3];
    reg signed [8:0] difference_middle [0:3];
    reg signed [8:0] difference_bottom [0:3];
    reg [9:0] sum_top [0:3];
    reg [9:0] sum_bottom [0:3];
    reg gradient_valid, gradient_last, gradient_user, gradient_enable;
    reg [3:0] gradient_border;
    reg [95:0] gradient_rgb;
    reg signed [10:0] gradient_x [0:3];
    reg signed [10:0] gradient_y [0:3];
    reg absolute_valid, absolute_last, absolute_user, absolute_enable;
    reg [3:0] absolute_border;
    reg [95:0] absolute_rgb;
    reg [9:0] absolute_x [0:3];
    reg [9:0] absolute_y [0:3];
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

    function signed [8:0] horizontal_difference;
        input [23:0] pixels;
        begin
            horizontal_difference = $signed({1'b0, pixels[23:16]}) - $signed({1'b0, pixels[7:0]});
        end
    endfunction

    function [9:0] vertical_sum;
        input [23:0] pixels;
        begin
            vertical_sum = {2'b0, pixels[7:0]} + {1'b0, pixels[15:8], 1'b0} + {2'b0, pixels[23:16]};
        end
    endfunction

    function [7:0] magnitude;
        input [9:0] horizontal, vertical;
        reg [10:0] total;
        begin
            total = {1'b0, horizontal} + {1'b0, vertical};
            magnitude = total > 255 ? 8'd255 : total[7:0];
        end
    endfunction

    wire [31:0] input_luma;
    genvar pixel_lane;
    generate for (pixel_lane = 0; pixel_lane < 4; pixel_lane = pixel_lane + 1) begin: lanes
        assign input_luma[pixel_lane*8 +: 8] = luma(input_data[pixel_lane*24 +: 24]);
    end endgenerate

    assign input_ready = ram_live && advance;

    always @(posedge clk) begin
        if (ram_live && advance && input_valid) begin
            stage_top <= second_row[read_address];
            stage_middle <= previous_row[read_address];
            second_row[read_address] <= previous_row[read_address];
            previous_row[read_address] <= input_luma;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            column_word <= 0;
            row_count <= 0;
            active_enable <= 0;
            stage_valid <= 0;
            stage_last <= 0;
            stage_user <= 0;
            stage_enable <= 0;
            stage_first <= 0;
            stage_row <= 0;
            stage_rgb <= 0;
            stage_bottom <= 0;
            left_top <= 0;
            left_middle <= 0;
            left_bottom <= 0;
            partial_valid <= 0;
            partial_last <= 0;
            partial_user <= 0;
            partial_enable <= 0;
            partial_border <= 0;
            partial_rgb <= 0;
            gradient_valid <= 0;
            gradient_last <= 0;
            gradient_user <= 0;
            gradient_enable <= 0;
            gradient_border <= 0;
            gradient_rgb <= 0;
            absolute_valid <= 0;
            absolute_last <= 0;
            absolute_user <= 0;
            absolute_enable <= 0;
            absolute_border <= 0;
            absolute_rgb <= 0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                difference_top[lane] <= 0;
                difference_middle[lane] <= 0;
                difference_bottom[lane] <= 0;
                sum_top[lane] <= 0;
                sum_bottom[lane] <= 0;
                gradient_x[lane] <= 0;
                gradient_y[lane] <= 0;
                absolute_x[lane] <= 0;
                absolute_y[lane] <= 0;
            end
            output_data <= 0;
            output_valid <= 0;
            output_last <= 0;
            output_user <= 0;
        end else if (advance) begin
            output_valid <= absolute_valid;
            if (absolute_valid) begin
                output_last <= absolute_last;
                output_user <= absolute_user;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (!absolute_enable)
                        output_data[lane*24 +: 24] <= absolute_rgb[lane*24 +: 24];
                    else if (absolute_border[lane])
                        output_data[lane*24 +: 24] <= 0;
                    else
                        output_data[lane*24 +: 24] <= {3{magnitude(absolute_x[lane], absolute_y[lane])}};
                end
            end
            absolute_valid <= gradient_valid;
            if (gradient_valid) begin
                absolute_last <= gradient_last;
                absolute_user <= gradient_user;
                absolute_enable <= gradient_enable;
                absolute_border <= gradient_border;
                absolute_rgb <= gradient_rgb;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    absolute_x[lane] <= gradient_x[lane] < 0 ? -gradient_x[lane] : gradient_x[lane];
                    absolute_y[lane] <= gradient_y[lane] < 0 ? -gradient_y[lane] : gradient_y[lane];
                end
            end
            gradient_valid <= partial_valid;
            if (partial_valid) begin
                gradient_last <= partial_last;
                gradient_user <= partial_user;
                gradient_enable <= partial_enable;
                gradient_border <= partial_border;
                gradient_rgb <= partial_rgb;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    gradient_x[lane] <= $signed({{2{difference_top[lane][8]}}, difference_top[lane]})
                        + $signed({difference_middle[lane][8], difference_middle[lane], 1'b0})
                        + $signed({{2{difference_bottom[lane][8]}}, difference_bottom[lane]});
                    gradient_y[lane] <= $signed({1'b0, sum_bottom[lane]}) - $signed({1'b0, sum_top[lane]});
                end
            end
            partial_valid <= stage_valid;
            if (stage_valid) begin
                partial_last <= stage_last;
                partial_user <= stage_user;
                partial_enable <= stage_enable;
                partial_rgb <= stage_rgb;
                left_top <= stage_top[31:16];
                left_middle <= stage_middle[31:16];
                left_bottom <= stage_bottom[31:16];
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    partial_border[lane] <= stage_row < 2 || (stage_first && lane < 2);
                    difference_top[lane] <= horizontal_difference(window_top[lane*8 +: 24]);
                    difference_middle[lane] <= horizontal_difference(window_middle[lane*8 +: 24]);
                    difference_bottom[lane] <= horizontal_difference(window_bottom[lane*8 +: 24]);
                    sum_top[lane] <= vertical_sum(window_top[lane*8 +: 24]);
                    sum_bottom[lane] <= vertical_sum(window_bottom[lane*8 +: 24]);
                end
            end
            stage_valid <= ram_live && input_valid;
            if (ram_live && input_valid) begin
                stage_rgb <= input_data;
                stage_bottom <= input_luma;
                stage_last <= input_last;
                stage_user <= input_user;
                stage_first <= read_address == 0;
                stage_row <= current_row;
                stage_enable <= input_user ? requested_enable : active_enable;
                if (input_user) active_enable <= requested_enable;
                if (input_last) begin
                    column_word <= 0;
                    row_count <= current_row < 2 ? current_row + 1'b1 : 2;
                end else begin
                    column_word <= read_address + 1'b1;
                    row_count <= current_row;
                end
            end
        end
    end
endmodule
