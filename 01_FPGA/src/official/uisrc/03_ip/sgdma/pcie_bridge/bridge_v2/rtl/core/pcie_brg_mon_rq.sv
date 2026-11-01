`include "pcie_brg_def.svh"

module pcie_brg_mon_rq #(
    parameter DATA_WIDTH = 512,
    // do not modify below
    parameter RQ_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_rq_tuser512_t) : $bits(pcie_rq_tuser_t)
) (
    input  logic                          user_clk,
    input  logic                          user_rst,

    input  logic [DATA_WIDTH-1:0]         s_axis_rq_tdata,
    input  logic [RQ_USER_WIDTH-1:0]      s_axis_rq_tuser,
    input  logic                          s_axis_rq_tfirst,
    input  logic                          s_axis_rq_tlast,
    input  logic [DATA_WIDTH/32-1:0]      s_axis_rq_tkeep,
    input  logic                          s_axis_rq_tvalid,
    input  logic                          s_axis_rq_tready,
    input  logic [5:0]                    pcie_rq_seq_num0,
    input  logic [5:0]                    pcie_rq_seq_num1,
    input  logic                          pcie_rq_seq_num_vld0,
    input  logic                          pcie_rq_seq_num_vld1
);

localparam SEQ_NUM_WIDTH = 6;
localparam SEQ_NUM_NUM = 2**SEQ_NUM_WIDTH;

logic rq_np_vld;
logic rq_p_vld;
logic rq_vld;
logic [5:0] rq_seq_num;

logic [SEQ_NUM_WIDTH-1:0] seq_num_pend_cnt [SEQ_NUM_NUM-1:0];
logic [SEQ_NUM_NUM-1:0] seq_num_pend;

logic [63:0] rq_np_cnt;
logic [63:0] rq_p_cnt;

assign rq_np_vld = s_axis_rq_tvalid & s_axis_rq_tready & ((DATA_WIDTH == 64) ? 0 : (s_axis_rq_tfirst & (s_axis_rq_tdata[78:75] == 4'b0000)));//todo
assign rq_p_vld = s_axis_rq_tvalid & s_axis_rq_tready & ((DATA_WIDTH == 64) ? 0 : (s_axis_rq_tfirst & (s_axis_rq_tdata[78:75] == 4'b0001)));
assign rq_vld = rq_np_vld | rq_p_vld;
assign rq_seq_num = {s_axis_rq_tuser[61:60], s_axis_rq_tuser[27:24]};

integer i;
always_ff @(posedge user_clk) begin
    for (i=0; i<SEQ_NUM_NUM; i=i+1) begin
        seq_num_pend[i] <= seq_num_pend_cnt[i] != 0;
    end
end

genvar j;
generate
    for (j=0; j<SEQ_NUM_NUM; j=j+1) begin
        always_ff @(posedge user_clk) begin
            seq_num_pend_cnt[j] <= seq_num_pend_cnt[j] + (rq_vld & (rq_seq_num == j)) - (pcie_rq_seq_num_vld0 & (pcie_rq_seq_num0 == j)) - (pcie_rq_seq_num_vld1 & (pcie_rq_seq_num1 == j));
            if (user_rst)
                seq_num_pend_cnt[j] <= 0;
        end
    end
endgenerate

always_ff @(posedge user_clk) begin
    if (rq_np_vld)
        rq_np_cnt <= rq_np_cnt + 1;
    if (user_rst)
        rq_np_cnt <= 0;
end

always_ff @(posedge user_clk) begin
    if (rq_p_vld)
        rq_p_cnt <= rq_p_cnt + 1;
    if (user_rst)
        rq_p_cnt <= 0;
end

endmodule
