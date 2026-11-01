module pcie_brg_cdc_sync # (
    parameter REG_IN = 0,
    parameter WIDTH = 1
) (
    input  logic             src_clk,
    input  logic [WIDTH-1:0] src_in,
    input  logic             dst_clk,
    output logic [WIDTH-1:0] dst_out
);

localparam SYNC_FF = 2;

logic [WIDTH-1:0] src_int;
logic [WIDTH-1:0] src_in_r;
logic [SYNC_FF-1:0] [WIDTH-1:0] dst_sync;

always_ff @(posedge src_clk) begin
    src_in_r <= src_in;
end
assign src_int = REG_IN ? src_in_r : src_in;

integer i;
always_ff @(posedge dst_clk) begin
    for (i=0; i<SYNC_FF; i=i+1) begin
        if (i==0)
            dst_sync[i] <= src_int;
        else
            dst_sync[i] <= dst_sync[i-1];
    end
end
assign dst_out = dst_sync[SYNC_FF-1];

endmodule
