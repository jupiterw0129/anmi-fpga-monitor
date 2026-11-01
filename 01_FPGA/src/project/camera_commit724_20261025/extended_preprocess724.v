module extended_preprocess (
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
    wire advanced_ready;
    reg [95:0] stage_data;
    reg stage_valid,stage_last,stage_user;
    reg [9:0] stage_config;
    reg [9:0] config_pipe [0:4];
    assign middle_ready = !stage_valid || advanced_ready;
    // One elastic register cuts the legacy output mux -> luma arithmetic path.
    // Pixel markers and their frame configuration travel in the same slot.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            stage_data<=0; stage_valid<=0; stage_last<=0; stage_user<=0; stage_config<=0;
        end else if (middle_ready) begin
            stage_valid<=middle_valid;
            stage_data<=middle_data;
            stage_last<=middle_last;
            stage_user<=middle_user;
            stage_config<=config_pipe[4];
        end
    end
    reg [9:0] frame_config;
    integer stage_index;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            frame_config <= 0;
            for (stage_index = 0; stage_index < 5; stage_index = stage_index + 1)
                config_pipe[stage_index] <= 0;
        end else if (middle_ready) begin
            if (input_valid && input_user)
                frame_config <= {requested_threshold, requested_mode};
            config_pipe[0] <= input_valid && input_user ?
                {requested_threshold, requested_mode} : frame_config;
            for (stage_index = 1; stage_index < 5; stage_index = stage_index + 1)
                config_pipe[stage_index] <= config_pipe[stage_index-1];
        end
    end

    board_preprocess legacy (
        .clk(clk), .reset_n(reset_n), .requested_mask(requested_mask),
        .active_mask(active_mask), .input_data(input_data), .input_valid(input_valid),
        .input_ready(input_ready), .input_last(input_last), .input_user(input_user),
        .output_data(middle_data), .output_valid(middle_valid), .output_ready(middle_ready),
        .output_last(middle_last), .output_user(middle_user)
    );

    advanced_preprocess advanced (
        .clk(clk), .reset_n(reset_n), .requested_mode(stage_config[1:0]),
        .requested_threshold(stage_config[9:2]), .active_mode(active_mode),
        .active_threshold(active_threshold), .input_data(stage_data),
        .input_valid(stage_valid), .input_ready(advanced_ready), .input_last(stage_last),
        .input_user(stage_user), .output_data(output_data), .output_valid(output_valid),
        .output_ready(output_ready), .output_last(output_last), .output_user(output_user)
    );
endmodule
