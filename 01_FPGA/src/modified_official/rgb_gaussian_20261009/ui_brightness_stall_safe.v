module ui_brightness_stall_safe #(
    parameter BRIGHTNESS_ADD = 20,
    parameter BRIGHTNESS_MINUS = 0
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_tlast,
    input wire I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    output wire I_tready,
    output reg O_tlast,
    output reg O_tuser,
    output reg [95:0] O_tdata,
    output reg O_tvalid,
    input wire O_tready
);
    function [7:0] adjusted_channel;
        input [7:0] component;
        reg [9:0] adjusted;
        begin
            adjusted = component + BRIGHTNESS_ADD - BRIGHTNESS_MINUS;
            adjusted_channel = adjusted[9] ? 8'd0 :
                adjusted[8] ? 8'd255 : adjusted[7:0];
        end
    endfunction

    integer pixel_index;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast <= 0;
            O_tuser <= 0;
            O_tvalid <= 0;
            O_tdata <= 0;
        end else if (O_tready) begin
            O_tlast <= I_tlast;
            O_tuser <= I_tuser;
            O_tvalid <= I_tvalid;
            if (I_tvalid)
                for (pixel_index = 0; pixel_index < 4; pixel_index = pixel_index + 1) begin
                    O_tdata[pixel_index*24 +: 8] <= adjusted_channel(I_tdata[pixel_index*24 +: 8]);
                    O_tdata[pixel_index*24+8 +: 8] <= adjusted_channel(I_tdata[pixel_index*24+8 +: 8]);
                    O_tdata[pixel_index*24+16 +: 8] <= adjusted_channel(I_tdata[pixel_index*24+16 +: 8]);
                end
        end
    end

    assign I_tready = O_tready;
endmodule
