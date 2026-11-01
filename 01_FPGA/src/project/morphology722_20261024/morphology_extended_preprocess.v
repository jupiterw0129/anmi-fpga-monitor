module morphology_extended_preprocess #(
    parameter MAX_WIDTH = 3840
) (
    input wire clk,
    input wire reset_n,
    input wire [2:0] requested_mask,
    input wire [1:0] requested_mode,
    input wire [1:0] requested_morphology,
    input wire [7:0] requested_threshold,
    output wire [2:0] active_mask,
    output wire [1:0] active_mode,
    output wire [1:0] active_morphology,
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
    wire original_ready, morphology_ready;
    reg [1:0] config_fifo [0:31];
    reg [4:0] write_pointer, read_pointer;
    reg [5:0] config_count;
    reg [1:0] frame_morphology;
    wire config_space = config_count < 32;
    wire push_config = input_valid && input_ready;
    wire pop_config = middle_valid && middle_ready;

    assign input_ready = original_ready && config_space;
    assign middle_ready = morphology_ready && config_count != 0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_pointer <= 0;
            read_pointer <= 0;
            config_count <= 0;
            frame_morphology <= 0;
        end else begin
            if (push_config) begin
                config_fifo[write_pointer] <= input_user ? requested_morphology : frame_morphology;
                write_pointer <= write_pointer + 1'b1;
                if (input_user) frame_morphology <= requested_morphology;
            end
            if (pop_config) read_pointer <= read_pointer + 1'b1;
            case ({push_config, pop_config})
                2'b10: config_count <= config_count + 1'b1;
                2'b01: config_count <= config_count - 1'b1;
                default: config_count <= config_count;
            endcase
        end
    end

    sobel_extended_preprocess #(.MAX_WIDTH(MAX_WIDTH)) original (
        .clk(clk), .reset_n(reset_n), .requested_mask(requested_mask),
        .requested_mode(requested_mode), .requested_threshold(requested_threshold),
        .active_mask(active_mask), .active_mode(active_mode), .active_threshold(active_threshold),
        .input_data(input_data), .input_valid(input_valid && config_space), .input_ready(original_ready),
        .input_last(input_last), .input_user(input_user), .output_data(middle_data),
        .output_valid(middle_valid), .output_ready(middle_ready), .output_last(middle_last),
        .output_user(middle_user)
    );

    morphology_rgb4 #(.IMAGE_WIDTH(MAX_WIDTH)) morphology (
        .clk(clk), .reset_n(reset_n), .requested_mode(config_fifo[read_pointer]),
        .active_mode(active_morphology), .input_data(middle_data),
        .input_valid(middle_valid && config_count != 0), .input_ready(morphology_ready),
        .input_last(middle_last), .input_user(middle_user), .output_data(output_data),
        .output_valid(output_valid), .output_ready(output_ready), .output_last(output_last),
        .output_user(output_user)
    );
endmodule

