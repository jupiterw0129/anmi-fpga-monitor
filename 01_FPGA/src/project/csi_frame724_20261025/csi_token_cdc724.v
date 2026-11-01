// Controls and data share one FIFO, preserving frame/error ordering across CDC.
module csi_token_cdc724 #(
    parameter ADDR_BITS=13
)(
    input wire source_clk, source_reset_n,
    input wire [63:0] source_data,
    input wire source_valid,
    output wire source_ready,
    input wire dest_clk, dest_reset_n,
    output wire [63:0] dest_data,
    output wire dest_valid,
    input wire dest_ready
);
    wire shared_reset_n=source_reset_n && dest_reset_n;
    wire write_reset_n, read_reset_n;
    wire full, empty;
    board_reset_release write_release(source_clk,shared_reset_n,write_reset_n);
    board_reset_release read_release(dest_clk,shared_reset_n,read_reset_n);
    assign source_ready=write_reset_n && !full;
    assign dest_valid=read_reset_n && !empty;
    mipi_sfifo #(
        .DATA_WIDTH_W(64),.DATA_WIDTH_R(64),
        .ADDR_WIDTH_W(ADDR_BITS),.ADDR_WIDTH_R(ADDR_BITS),
        .AL_FULL_NUM(1<<(ADDR_BITS-1)),.AL_EMPTY_NUM(2),
        .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")
    ) ordered_fifo (
        .rst(!shared_reset_n),.clkw(source_clk),.clkr(dest_clk),
        .we(source_valid && source_ready),.di(source_data),.full_flag(full),.afull(),
        .re(dest_valid && dest_ready),.dout(dest_data),.empty_flag(empty),
        .rdusedw(),.wrusedw()
    );
endmodule
