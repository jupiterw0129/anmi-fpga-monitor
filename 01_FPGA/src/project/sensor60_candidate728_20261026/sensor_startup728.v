module sensor_startup728 (
    input wire clock_27m,
    input wire pll_locked,
    output reg sensor_xclr,
    output wire sensor_mclk,
    output reg cfg_ready
);
    reg [15:0] startup_count;
    reg mclk_enable;

    always @(posedge clock_27m or negedge pll_locked) begin
        if (!pll_locked) begin
            startup_count <= 16'd0;
            sensor_xclr <= 1'b0;
            cfg_ready <= 1'b0;
        end else begin
            if (startup_count < 16'd54054)
                startup_count <= startup_count + 1'b1;
            if (startup_count == 16'd26999)
                sensor_xclr <= 1'b1;
            if (startup_count == 16'd54053)
                cfg_ready <= 1'b1;
        end
    end

    always @(negedge clock_27m or negedge pll_locked) begin
        if (!pll_locked)
            mclk_enable <= 1'b0;
        else
            mclk_enable <= startup_count >= 16'd27027;
    end

    assign sensor_mclk = clock_27m && mclk_enable;
endmodule
