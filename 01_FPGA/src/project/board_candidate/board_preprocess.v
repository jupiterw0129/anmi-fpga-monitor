module board_preprocess (
    input wire clk,
    input wire reset_n,
    input wire [2:0] requested_mask,
    output reg [2:0] active_mask,
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
    reg [2:0] mask_pipe [0:4];
    reg [95:0] gray_bypass;
    reg [95:0] contrast_bypass [0:2];
    reg [95:0] brightness_bypass;
    wire [95:0] gray_data, contrast_data, brightness_data;
    wire gray_valid, gray_last, gray_user;
    wire contrast_valid, contrast_last, contrast_user;
    wire [95:0] gray_selected = mask_pipe[0][0] ? gray_data : gray_bypass;
    wire [95:0] contrast_selected = mask_pipe[3][1] ? contrast_data : contrast_bypass[2];
    integer stage_index;

    assign input_ready = output_ready;
    assign output_data = mask_pipe[4][2] ? brightness_data : brightness_bypass;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_mask <= 0;
            gray_bypass <= 0;
            brightness_bypass <= 0;
            for (stage_index = 0; stage_index < 5; stage_index = stage_index + 1)
                mask_pipe[stage_index] <= 0;
            for (stage_index = 0; stage_index < 3; stage_index = stage_index + 1)
                contrast_bypass[stage_index] <= 0;
        end else if (output_ready) begin
            if (input_valid && input_user)
                active_mask <= requested_mask;
            mask_pipe[0] <= input_valid && input_user ? requested_mask : active_mask;
            for (stage_index = 1; stage_index < 5; stage_index = stage_index + 1)
                mask_pipe[stage_index] <= mask_pipe[stage_index-1];
            gray_bypass <= input_data;
            contrast_bypass[0] <= gray_selected;
            contrast_bypass[1] <= contrast_bypass[0];
            contrast_bypass[2] <= contrast_bypass[1];
            brightness_bypass <= contrast_selected;
        end
    end

    ui_rgb24_to_gray gray (
        .I_clk(clk), .I_rst_n(reset_n), .I_tdata(input_data),
        .I_tvalid(input_valid && output_ready), .I_tready(),
        .I_tlast(input_last), .I_tuser(input_user),
        .O_tdata(gray_data), .O_tvalid(gray_valid), .O_tready(output_ready),
        .O_tlast(gray_last), .O_tuser(gray_user)
    );
    ui_contrast_stall_safe #(.contrast_level(160)) contrast (
        .I_clk(clk), .I_rst_n(reset_n), .I_tdata(gray_selected),
        .I_tvalid(gray_valid), .I_tready(), .I_tlast(gray_last), .I_tuser(gray_user),
        .O_tdata(contrast_data), .O_tvalid(contrast_valid), .O_tready(output_ready),
        .O_tlast(contrast_last), .O_tuser(contrast_user)
    );
    ui_brightness_stall_safe #(.BRIGHTNESS_ADD(20)) brightness (
        .I_clk(clk), .I_rst_n(reset_n), .I_tdata(contrast_selected),
        .I_tvalid(contrast_valid), .I_tready(),
        .I_tlast(contrast_last), .I_tuser(contrast_user),
        .O_tdata(brightness_data), .O_tvalid(output_valid), .O_tready(output_ready),
        .O_tlast(output_last), .O_tuser(output_user)
    );
endmodule
