module image_correction #(
    parameter DATA_WIDTH = 40,
    parameter TDEST_WIDTH = 10
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire [14:0] I_v_start,
    input wire [14:0] I_v_end,
    input wire [14:0] I_h_end,
    input wire [DATA_WIDTH-1:0] I_raw_tdata,
    input wire [TDEST_WIDTH-1:0] I_raw_tdest,
    input wire I_raw_tlast,
    input wire I_raw_tvalid,
    input wire I_raw_tuser,
    output wire I_raw_tready,
    output wire [DATA_WIDTH-1:0] O_raw_tdata,
    output wire O_raw_tlast,
    output reg [TDEST_WIDTH-1:0] O_raw_tdest,
    output wire O_raw_tvalid,
    output wire O_raw_tuser,
    input wire O_raw_tready
);
    reg input_valid_d;
    reg input_last_d;
    reg [DATA_WIDTH-1:0] input_data_d;
    reg [14:0] horizontal_count;
    reg [14:0] vertical_count;
    reg frame_synced;
    wire vertical_valid = vertical_count > I_v_start && vertical_count < I_v_end;
    wire horizontal_valid = horizontal_count > 0 && horizontal_count < I_h_end;
    wire advance = !O_raw_tvalid || O_raw_tready;

    assign I_raw_tready = advance;
    assign O_raw_tvalid = frame_synced && vertical_valid && horizontal_valid && input_valid_d;
    assign O_raw_tdata = vertical_valid && horizontal_valid ? input_data_d : {DATA_WIDTH{1'b0}};
    assign O_raw_tlast = frame_synced && vertical_valid && horizontal_count == I_h_end - 15'd1 && input_valid_d;
    assign O_raw_tuser = frame_synced && horizontal_count == 1 && vertical_count == I_v_start + 15'd1 && input_valid_d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            input_valid_d <= 1'b0;
            input_last_d <= 1'b0;
            input_data_d <= {DATA_WIDTH{1'b0}};
            O_raw_tdest <= {TDEST_WIDTH{1'b0}};
            horizontal_count <= 15'd0;
            vertical_count <= 15'd0;
            frame_synced <= 1'b0;
        end else if (advance) begin
            input_valid_d <= I_raw_tvalid;
            input_last_d <= I_raw_tlast;
            input_data_d <= I_raw_tdata;
            O_raw_tdest <= I_raw_tdest;
            if (I_raw_tvalid && I_raw_tuser) begin
                frame_synced <= 1'b1;
                horizontal_count <= 15'd0;
                vertical_count <= 15'd0;
            end else begin
                if (input_valid_d)
                    horizontal_count <= input_last_d ? 15'd0 : horizontal_count + 15'd1;
                if (input_last_d)
                    vertical_count <= vertical_count + 15'd1;
            end
        end
    end
endmodule
