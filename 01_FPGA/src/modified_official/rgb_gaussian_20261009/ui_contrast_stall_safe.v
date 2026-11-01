module ui_contrast_stall_safe #(
    parameter contrast_level = 160
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_tlast,
    input wire I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    output wire I_tready,
    output wire O_tlast,
    output wire O_tuser,
    output wire [95:0] O_tdata,
    output wire O_tvalid,
    input wire O_tready
);
    reg [2:0] last_pipeline, user_pipeline, valid_pipeline;
    genvar component_index;
    generate for (component_index = 0; component_index < 12; component_index = component_index + 1) begin : channels
        reg [15:0] shifted;
        reg [15:0] scaled;
        reg [9:0] adjusted;

        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                shifted <= 0;
                scaled <= 0;
                adjusted <= 0;
            end else if (O_tready) begin
                if (I_tvalid)
                    shifted <= {8'd0, I_tdata[component_index*8 +: 8]} - 16'd128;
                if (valid_pipeline[0])
                    scaled <= (shifted * contrast_level) >> 7;
                if (valid_pipeline[1])
                    adjusted <= scaled + 16'd128;
            end
        end

        assign O_tdata[component_index*8 +: 8] = adjusted[9] ? 8'd0 :
            adjusted[8] ? 8'd255 : adjusted[7:0];
    end endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            last_pipeline <= 0;
            user_pipeline <= 0;
            valid_pipeline <= 0;
        end else if (O_tready) begin
            last_pipeline <= {last_pipeline[1:0], I_tlast};
            user_pipeline <= {user_pipeline[1:0], I_tuser};
            valid_pipeline <= {valid_pipeline[1:0], I_tvalid};
        end
    end

    assign O_tlast = last_pipeline[2];
    assign O_tuser = user_pipeline[2];
    assign O_tvalid = valid_pipeline[2];
    assign I_tready = O_tready;
endmodule
