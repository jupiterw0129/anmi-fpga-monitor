// 3x3 grayscale mean filter core.
// Pixels are ordered from top-left to bottom-right: p00 ... p22.
// The core is intentionally window-based; line-buffer integration is separate.
module ui_gray_mean3x3 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [7:0]  I_p00,
    input  wire [7:0]  I_p01,
    input  wire [7:0]  I_p02,
    input  wire [7:0]  I_p10,
    input  wire [7:0]  I_p11,
    input  wire [7:0]  I_p12,
    input  wire [7:0]  I_p20,
    input  wire [7:0]  I_p21,
    input  wire [7:0]  I_p22,
    input  wire         I_valid,
    output reg  [7:0]  O_pixel,
    output reg          O_valid
);

    reg [11:0] pixel_sum;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pixel_sum <= 12'd0;
            O_pixel   <= 8'd0;
            O_valid   <= 1'b0;
        end else begin
            O_valid <= I_valid;
            if (I_valid) begin
                pixel_sum <= {4'd0, I_p00} + {4'd0, I_p01} + {4'd0, I_p02} +
                             {4'd0, I_p10} + {4'd0, I_p11} + {4'd0, I_p12} +
                             {4'd0, I_p20} + {4'd0, I_p21} + {4'd0, I_p22};
                O_pixel <= ({4'd0, I_p00} + {4'd0, I_p01} + {4'd0, I_p02} +
                            {4'd0, I_p10} + {4'd0, I_p11} + {4'd0, I_p12} +
                            {4'd0, I_p20} + {4'd0, I_p21} + {4'd0, I_p22}) / 9;
            end
        end
    end

endmodule
