module board_morphology_control (
    input wire clk,
    input wire reset_n,
    input wire write_enable,
    input wire [31:0] write_data,
    input wire [3:0] write_strobe,
    output reg [1:0] requested_mode,
    output reg [1:0] requested_morphology,
    output reg [7:0] requested_threshold,
    input wire [1:0] active_mode,
    input wire [1:0] active_morphology,
    input wire [7:0] active_threshold,
    output wire [31:0] requested_readback,
    output wire [31:0] active_readback
);
    assign requested_readback = {16'd0, requested_threshold, 4'd0, requested_morphology, requested_mode};
    assign active_readback = {16'd0, active_threshold, 4'd0, active_morphology, active_mode};
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            requested_mode <= 0;
            requested_morphology <= 0;
            requested_threshold <= 128;
        end else if (write_enable) begin
            if (write_strobe[0]) begin
                requested_mode <= write_data[1:0];
                requested_morphology <= write_data[3:2];
            end
            if (write_strobe[1]) requested_threshold <= write_data[15:8];
        end
    end
endmodule
