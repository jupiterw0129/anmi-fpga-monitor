module sobel_extended_preprocess #(
    parameter MAX_WIDTH = 3840
) (
    input wire clk,
    input wire reset_n,
    input wire [2:0] requested_mask,
    input wire [1:0] requested_mode,
    input wire [7:0] requested_threshold,
    output wire [2:0] active_mask,
    output wire [1:0] active_mode,
    output wire [7:0] active_threshold,
    input wire [95:0] input_data,
    input wire input_valid,
    output wire input_ready,
    input wire input_last,
    input wire input_user,
    output wire [95:0] output_data,
    output wire output_valid,
    input wire output_ready,
    output wire output_last,
    output wire output_user
);
    wire [95:0] middle_data;
    wire middle_valid, middle_ready, middle_last, middle_user;
    wire sobel_active;
    extended_preprocess original (
        .clk(clk), .reset_n(reset_n), .requested_mask(requested_mask),
        .requested_mode(requested_mode), .requested_threshold(requested_threshold),
        .active_mask(active_mask), .active_mode(active_mode), .active_threshold(active_threshold),
        .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
        .input_last(input_last), .input_user(input_user), .output_data(middle_data),
        .output_valid(middle_valid), .output_ready(middle_ready), .output_last(middle_last),
        .output_user(middle_user)
    );
    sobel_rgb4 #(.IMAGE_WIDTH(MAX_WIDTH)) edge_filter (
        .clk(clk), .reset_n(reset_n), .requested_enable(active_mode == 2'd3),
        .active_enable(sobel_active), .input_data(middle_data), .input_valid(middle_valid),
        .input_ready(middle_ready), .input_last(middle_last), .input_user(middle_user),
        .output_data(output_data), .output_valid(output_valid), .output_ready(output_ready),
        .output_last(output_last), .output_user(output_user)
    );
endmodule
