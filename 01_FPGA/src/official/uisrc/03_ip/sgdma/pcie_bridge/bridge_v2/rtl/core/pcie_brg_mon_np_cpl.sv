module pcie_brg_mon_np_cpl #(
    parameter TAG_WIDTH = 6,
    parameter CPL_ADDR_WIDTH = 7,
    //
    parameter TAG_NUM = 2**TAG_WIDTH
) (
    input  logic                 user_clk,
    input  logic                 user_rst,
    input  logic                 req_vld,
    input  logic [TAG_WIDTH-1:0] req_tag,
    input  logic [63:0]          req_addr,
    input  logic [12:0]          req_len,
    input  logic                 cpl_vld,
    input  logic [TAG_WIDTH-1:0] cpl_tag,
    input  logic [11:0]          cpl_addr,
    input  logic [12:0]          cpl_len,
    input  logic [12:0]          cpl_byte_count,
    input  logic                 cpl_last,
    input  logic [2:0]           cpl_stat,
    output logic [TAG_NUM-1:0]   req_pend,
    output logic                 cor_err,
    output logic [63:0]          req_cnt_sum,
    output logic [63:0]          cpl_cnt_sum,
    output logic [63:0]          lcpl_cnt_sum,
    output logic [63:0]          req_len_sum,
    output logic [63:0]          cpl_len_sum
);

logic [TAG_NUM-1:0] cpl_pend;
logic [12:0] cpl_len_pend [TAG_NUM-1:0];
logic [CPL_ADDR_WIDTH-1:0] cpl_addr_pend [TAG_NUM-1:0];

logic req_pend_err;
logic cpl_pend_err;
logic cpl_len_pend_err;
logic cpl_byte_count_err;
logic cpl_addr_err;
logic cpl_stat_err;

always_ff @(posedge user_clk) begin
    if (req_vld) begin
        cpl_pend[req_tag] <= 1;
        cpl_len_pend[req_tag] <= req_len;
        cpl_addr_pend[req_tag] <= req_addr;
        req_pend_err <= cpl_pend[req_tag];
    end else begin
        req_pend_err <= 0;
    end
    if (cpl_vld) begin
        if (cpl_last) begin
            cpl_pend[cpl_tag] <= 0;
        end
        cpl_len_pend[cpl_tag] <= cpl_byte_count - cpl_len;
        cpl_addr_pend[cpl_tag] <= cpl_addr + cpl_len;
        cpl_pend_err <= ~cpl_pend[cpl_tag];
        cpl_len_pend_err <= cpl_last ? (cpl_len != cpl_len_pend[cpl_tag]) : (cpl_len > cpl_len_pend[cpl_tag]);
        cpl_byte_count_err <= cpl_byte_count != cpl_len_pend[cpl_tag];
        cpl_addr_err <= cpl_addr[CPL_ADDR_WIDTH-1:0] != cpl_addr_pend[cpl_tag];
        cpl_stat_err <= (cpl_stat != 0) | (cpl_len == 0);
    end else begin
        cpl_pend_err <= 0;
        cpl_len_pend_err <= 0;
        cpl_byte_count_err <= 0;
        cpl_addr_err <= 0;
        cpl_stat_err <= 0;
    end
    cor_err <= req_pend_err | cpl_pend_err | cpl_len_pend_err | cpl_byte_count_err | cpl_addr_err | cpl_stat_err;
    if (user_rst) begin
        cpl_pend <= 0;
        req_pend_err <= 0;
        cpl_pend_err <= 0;
        cpl_len_pend_err <= 0;
        cpl_byte_count_err <= 0;
        cpl_addr_err <= 0;
        cpl_stat_err <= 0;
        cor_err <= 0;
    end
end

always_ff @(posedge user_clk) begin
    if (user_rst) begin
        req_cnt_sum <= 0;
        cpl_cnt_sum <= 0;
        lcpl_cnt_sum <= 0;
        req_len_sum <= 0;
        cpl_len_sum <= 0;
    end else begin
        req_cnt_sum <= req_vld ? (req_cnt_sum + 1) : req_cnt_sum;
        cpl_cnt_sum <= cpl_vld ? (cpl_cnt_sum + 1) : cpl_cnt_sum;
        lcpl_cnt_sum <= (cpl_vld & cpl_last) ? (lcpl_cnt_sum + 1) : lcpl_cnt_sum;
        req_len_sum <= req_vld ? (req_len_sum + req_len) : req_len_sum;
        cpl_len_sum <= cpl_vld ? (cpl_len_sum + cpl_len) : cpl_len_sum;
    end
end

endmodule
