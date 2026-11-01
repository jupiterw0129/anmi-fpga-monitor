module board_reset_release (
    input wire clk,
    input wire async_reset_n,
    output wire reset_n
);
    (* async_reg = "true", dont_touch = "true" *) reg [2:0] release_sync;
    always @(posedge clk or negedge async_reset_n) begin
        if (!async_reset_n)
            release_sync <= 3'b000;
        else
            release_sync <= {release_sync[1:0], 1'b1};
    end
    assign reset_n = release_sync[2];
endmodule
