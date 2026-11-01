module pcie_brg_cdc_bus_sync #(
    parameter WIDTH  = 1
) (
    input  logic             src_clk,
    input  logic             src_rst,
    input  logic [WIDTH-1:0] src_in,

    input  logic             dst_clk,
    input  logic             dst_rst,
    output logic [WIDTH-1:0] dst_out
);

// localparam SYNC_STAGE = 3;

// logic [WIDTH-1:0] data_r [SYNC_STAGE:0];

// integer i;
// always_ff @(posedge dst_clk) begin
//     for (i=0; i<(SYNC_STAGE+1); i=i+1)
//         data_r[i] <= (i==0) ? src_in : data_r[i-1];
// end

// always_ff @(posedge dst_clk) begin
//     if (data_r[SYNC_STAGE] == data_r[SYNC_STAGE-1])
//         dst_out <= data_r[SYNC_STAGE];
// end

logic src_send;
logic src_recv;
logic [WIDTH-1:0] src_data_r;

always_ff @(posedge src_clk) begin
    if (src_rst)
        src_send <= 0;
    else if (~src_send & ~src_recv & (src_in != src_data_r))
        src_send <= 1;
    else if (src_send & src_recv)
        src_send <= 0;
end

logic dst_req_r;
logic dst_req_sync;
logic src_send_r;

pcie_brg_cdc_sync #(
    .REG_IN(0),
    .WIDTH(1)
) cdc_send(
    .src_clk(src_clk),
    .src_in(src_send_r),
    .dst_clk(dst_clk),
    .dst_out(dst_req_sync)
);

pcie_brg_cdc_sync # (
    .REG_IN(0),
    .WIDTH(1)
) cdc_ack(
    .src_clk(dst_clk),
    .src_in(dst_req_r),
    .dst_clk(src_clk),
    .dst_out(src_recv)
);

always_ff @(posedge src_clk) begin
    src_send_r <= src_send;
    src_data_r <= (src_send & ~src_send_r) ? src_in : src_data_r;
    if (src_rst)
        src_data_r <= src_in;
end

always_ff @(posedge dst_clk) begin
    dst_out <= (~dst_req_r & dst_req_sync) ? src_data_r : dst_out;
    dst_req_r <= dst_req_sync;
    if (dst_rst)
        dst_out <= src_data_r;
end

endmodule
