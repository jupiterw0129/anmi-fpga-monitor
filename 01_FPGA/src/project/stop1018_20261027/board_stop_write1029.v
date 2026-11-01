// Match only the new stop register. Existing low-page write decode is unchanged.
module board_stop_write1029 (
    input wire clk,reset_n,awvalid,wvalid,
    input wire [31:0] address,
    output wire pulse
);
    wire hit=awvalid && wvalid && address[15:0]==16'h01f4;
    reg held;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)held<=0;else held<=hit;
    assign pulse=hit && !held;
endmodule
