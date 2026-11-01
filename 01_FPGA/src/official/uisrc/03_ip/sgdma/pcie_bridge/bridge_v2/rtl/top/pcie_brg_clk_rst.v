module pcie_brg_clk_rst(
    input  pll_lock,
    input  tl_clk_locked,
    input  user_clk,
    output user_rst,
    input  core_clk,
    output core_rst,
    input  pipe_clk,
    output pipe_rst
);

wire resetn_async;
wire pll_lock_user;
wire pll_lock_core;
wire pll_lock_pipe;
reg [15:0] user_rst_sync;
reg [15:0] core_rst_sync;
reg [15:0] pipe_rst_sync;

assign resetn_async = pll_lock & tl_clk_locked;
assign user_rst = user_rst_sync[15];
assign core_rst = core_rst_sync[15];
assign pipe_rst = pipe_rst_sync[15];

always @(posedge user_clk or negedge resetn_async) begin
    if (~resetn_async)
        user_rst_sync <= 16'hffff;
    else
        user_rst_sync <= {user_rst_sync[14:0], 1'b0};
end

always @(posedge core_clk or negedge resetn_async) begin
    if (~resetn_async)
        core_rst_sync <= 16'hffff;
    else
        core_rst_sync <= {core_rst_sync[14:0], 1'b0};
end

always @(posedge pipe_clk or negedge resetn_async) begin
    if (~resetn_async)
        pipe_rst_sync <= 16'hffff;
    else
        pipe_rst_sync <= {pipe_rst_sync[14:0], 1'b0};
end

endmodule
