// RGB888 to grayscale, four pixels per 96-bit stream beat.
// The grayscale value is replicated to R, G and B for downstream RGB packing.
module ui_rgb24_to_gray (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire [95:0]  I_tdata,
    input  wire         I_tvalid,
    output wire         I_tready,
    input  wire         I_tlast,
    input  wire         I_tuser,
    output reg  [95:0]  O_tdata,
    output reg          O_tvalid,
    input  wire         O_tready,
    output reg          O_tlast,
    output reg          O_tuser
);

    wire transfer_in = I_tvalid && I_tready;
    wire transfer_out = O_tvalid && O_tready;

    assign I_tready = ~O_tvalid || O_tready;

    function [7:0] rgb_to_gray;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg [15:0] weighted_sum;
        begin
            weighted_sum =
                (({8'd0, red}   << 6) + ({8'd0, red}   << 3) +
                 ({8'd0, red}   << 2) +  {8'd0, red}) +
                (({8'd0, green} << 7) + ({8'd0, green} << 4) +
                 ({8'd0, green} << 2) + ({8'd0, green} << 1)) +
                (({8'd0, blue}  << 4) + ({8'd0, blue}  << 3) +
                 ({8'd0, blue}  << 2) +  {8'd0, blue});
            rgb_to_gray = weighted_sum[15:8];
        end
    endfunction

    function [23:0] gray_pixel;
        input [23:0] pixel;
        reg [7:0] gray;
        begin
            gray = rgb_to_gray(pixel[23:16], pixel[15:8], pixel[7:0]);
            gray_pixel = {gray, gray, gray};
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
        end else begin
            if (transfer_in) begin
                O_tdata  <= {
                    gray_pixel(I_tdata[95:72]),
                    gray_pixel(I_tdata[71:48]),
                    gray_pixel(I_tdata[47:24]),
                    gray_pixel(I_tdata[23:0])
                };
                O_tlast  <= I_tlast;
                O_tuser  <= I_tuser;
                O_tvalid <= 1'b1;
            end else if (transfer_out) begin
                O_tvalid <= 1'b0;
                O_tlast  <= 1'b0;
                O_tuser  <= 1'b0;
            end
        end
    end

endmodule
