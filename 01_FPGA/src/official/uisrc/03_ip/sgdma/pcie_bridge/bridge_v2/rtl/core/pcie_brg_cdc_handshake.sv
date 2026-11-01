module pcie_brg_cdc_handshake #(
    parameter WIDTH = 1
) (
    input  logic             src_clk,
    input  logic [WIDTH-1:0] src_in,
    input  logic             src_send,
    output logic             src_recv,

    input  logic             dst_clk,
    output logic [WIDTH-1:0] dst_out,
    output logic             dst_req,
    input  logic             dst_ack
);

logic [WIDTH-1:0] src_data_r;
logic             dst_req_r;
logic             dst_req_sync;
logic             src_send_r;

assign dst_req = dst_req_r;

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
    .src_in(dst_ack),
    .dst_clk(src_clk),
    .dst_out(src_recv)
);

always_ff @(posedge src_clk) begin
    src_send_r <= src_send;
    src_data_r <= ~src_send_r ? src_in : src_data_r;
end

always_ff @(posedge dst_clk) begin
    if (~dst_req_r & dst_req_sync) begin
        dst_out <= src_data_r;
    end
    dst_req_r <= dst_req_sync;
end

endmodule
