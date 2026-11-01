// output is not registered
module pcie_brg_cdc_gray #(
    parameter REG_OUT = 1,
    parameter WIDTH = 2// at least 2
) (
    input  logic             src_clk,
    input  logic [WIDTH-1:0] src_in,
    input  logic             dst_clk,
    output logic [WIDTH-1:0] dst_out
);

localparam SYNC_FF = 2;

logic [WIDTH-1:0] gray_r;
logic [SYNC_FF-1:0] [WIDTH-1:0] gray_sync;
logic [WIDTH-1:0] gray_dst;
logic [WIDTH-1:0] bin_c;
logic [WIDTH-1:0] bin_r;

always_ff @(posedge src_clk) begin
    gray_r <= src_in ^ (src_in >> 1);
end

integer i;
always_ff @(posedge dst_clk) begin
    for (i=0; i<SYNC_FF; i=i+1) begin
        if (i==0)
            gray_sync[i] <= gray_r;
        else
            gray_sync[i] <= gray_sync[i-1];
    end
end
assign gray_dst = gray_sync[SYNC_FF-1];

integer j;
always_comb begin
    for (j=(WIDTH-1); j>=0; j=j-1) begin
        if (j==(WIDTH-1))
            bin_c[j] = gray_dst[j];
        else
            bin_c[j] = bin_c[j+1] ^ gray_dst[j];
    end
end

always_ff @(posedge dst_clk) begin
    bin_r <= bin_c;
end
assign dst_out = REG_OUT ? bin_r : bin_c;

endmodule
