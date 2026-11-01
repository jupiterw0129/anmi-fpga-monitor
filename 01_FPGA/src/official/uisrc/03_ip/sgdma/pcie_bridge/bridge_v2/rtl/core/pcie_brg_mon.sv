`include "pcie_brg_def.svh"

module pcie_brg_mon #(
    parameter PF_NUM = 4,
    parameter TAG_WIDTH = 6,
    parameter DATA_WIDTH = 512,
    // do not modify below
    parameter CQ_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_cq_tuser512_t) : $bits(pcie_cq_tuser_t),
    parameter CC_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_cc_tuser512_t) : $bits(pcie_cc_tuser_t),
    parameter RQ_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_rq_tuser512_t) : $bits(pcie_rq_tuser_t),
    parameter RC_USER_WIDTH  = (DATA_WIDTH == 512) ? $bits(pcie_rc_tuser512_t) : $bits(pcie_rc_tuser_t)
) (
    input  logic                          user_clk,
    input  logic                          user_rst,
    // cq
    input  logic [DATA_WIDTH-1:0]         m_axis_cq_tdata,
    input  logic [CQ_USER_WIDTH-1:0]      m_axis_cq_tuser,
    input  logic                          m_axis_cq_tlast,
    input  logic [DATA_WIDTH/32-1:0]      m_axis_cq_tkeep,
    input  logic                          m_axis_cq_tvalid,
    input  logic                          m_axis_cq_tready,
    input  logic [1:0]                    pcie_cq_np_req,
    input  logic [5:0]                    pcie_cq_np_req_count,
    // cc
    input  logic [DATA_WIDTH-1:0]         s_axis_cc_tdata,
    input  logic [CC_USER_WIDTH-1:0]      s_axis_cc_tuser,
    input  logic                          s_axis_cc_tlast,
    input  logic [DATA_WIDTH/32-1:0]      s_axis_cc_tkeep,
    input  logic                          s_axis_cc_tvalid,
    input  logic [3:0]                    s_axis_cc_tready,
    // rq
    input  logic [DATA_WIDTH-1:0]         s_axis_rq_tdata,
    input  logic [RQ_USER_WIDTH-1:0]      s_axis_rq_tuser,
    input  logic                          s_axis_rq_tlast,
    input  logic [DATA_WIDTH/32-1:0]      s_axis_rq_tkeep,
    input  logic                          s_axis_rq_tvalid,
    input  logic                          s_axis_rq_tready,
    input  logic [5:0]                    pcie_rq_seq_num0,
    input  logic [5:0]                    pcie_rq_seq_num1,
    input  logic                          pcie_rq_seq_num_vld0,
    input  logic                          pcie_rq_seq_num_vld1,
    // rc
    input  logic [DATA_WIDTH-1:0]         m_axis_rc_tdata,
    input  logic [RC_USER_WIDTH-1:0]      m_axis_rc_tuser,
    input  logic                          m_axis_rc_tlast,
    input  logic [DATA_WIDTH/32-1:0]      m_axis_rc_tkeep,
    input  logic                          m_axis_rc_tvalid,
    input  logic                          m_axis_rc_tready
);

localparam TAG_NUM = 2**TAG_WIDTH;

logic m_axis_cq_tfirst;
logic s_axis_cc_tfirst;
logic s_axis_rq_tfirst;
logic m_axis_rc_tfirst;

logic [TAG_NUM-1:0] req_pend_local [PF_NUM-1:0];
logic [PF_NUM-1:0] req_pend_cor_err_log_local;

always_ff @(posedge user_clk) begin
    m_axis_cq_tfirst <= (m_axis_cq_tvalid & m_axis_cq_tready) ? m_axis_cq_tlast : m_axis_cq_tfirst;
    s_axis_cc_tfirst <= (s_axis_cc_tvalid & s_axis_cc_tready) ? s_axis_cc_tlast : s_axis_cc_tfirst;
    s_axis_rq_tfirst <= (s_axis_rq_tvalid & s_axis_rq_tready) ? s_axis_rq_tlast : s_axis_rq_tfirst;
    m_axis_rc_tfirst <= (m_axis_rc_tvalid & m_axis_rc_tready) ? m_axis_rc_tlast : m_axis_rc_tfirst;
    if (user_rst) begin
        m_axis_cq_tfirst <= 1;
        s_axis_cc_tfirst <= 1;
        s_axis_rq_tfirst <= 1;
        m_axis_rc_tfirst <= 1;
    end
end

genvar i;
generate
    for (i=0; i<PF_NUM; i=i+1) begin: mon_req_cpl_local

        logic                 req_vld;
        logic [TAG_WIDTH-1:0] req_tag;
        logic [63:0]          req_addr;
        logic [1:0]           req_addr_lo;
        logic [12:0]          req_len, req_len_nxt;
        logic                 cpl_vld;
        logic [TAG_WIDTH-1:0] cpl_tag;
        logic [11:0]          cpl_addr;
        logic [12:0]          cpl_len, cpl_len_nxt;
        logic [12:0]          cpl_byte_count;
        logic                 cpl_last;
        logic [2:0]           cpl_stat;
        logic [TAG_NUM-1:0]   req_pend;
        logic                 cor_err;
        logic [63:0]          req_cnt_sum;
        logic [63:0]          cpl_cnt_sum;
        logic [63:0]          lcpl_cnt_sum;
        logic [63:0]          req_len_sum;
        logic [63:0]          cpl_len_sum;
        logic                 req_type_err;// only mrd and mwr
        logic                 cpl_type_err;// only successful cpld
        logic [2:0]           req_fbyte;
        logic [2:0]           req_lbyte;
        logic [2:0]           cpl_fbyte;

        assign req_pend_local[i] = req_pend;

        always_comb begin
            req_addr_lo = 0;
            req_fbyte = 0;
            req_lbyte = 0;
            cpl_fbyte = 0;
            req_len_nxt = 0;
            cpl_len_nxt = 0;
            if (DATA_WIDTH == 512) begin
            end else begin
                case (s_axis_rq_tuser[3:0])
                    4'b0001, 4'b0011, 4'b0111, 4'b1111: req_addr_lo = 2'b00;
                    4'b0010, 4'b0110, 4'b1110:          req_addr_lo = 2'b01;
                    4'b0100, 4'b1100:                   req_addr_lo = 2'b10;
                    4'b1000:                            req_addr_lo = 2'b11;
                endcase
                case (s_axis_rq_tuser[3:0])
                    4'b0001, 4'b0010, 4'b0100, 4'b1000: req_fbyte = 1;
                    4'b0011, 4'b0110, 4'b1100:          req_fbyte = 2;
                    4'b0111, 4'b1110:                   req_fbyte = 3;
                    4'b1111:                            req_fbyte = 4;
                endcase
                case (s_axis_rq_tuser[7:4])
                    4'b0001: req_lbyte = 1;
                    4'b0011: req_lbyte = 2;
                    4'b0111: req_lbyte = 3;
                    4'b1111: req_lbyte = 4;
                endcase
                case (m_axis_rc_tdata[1:0])
                    2'b00: cpl_fbyte = 4;
                    2'b01: cpl_fbyte = 3;
                    2'b10: cpl_fbyte = 2;
                    2'b11: cpl_fbyte = 1;
                endcase
                case (s_axis_rq_tdata[74:64])
                    0: req_len_nxt = 0;
                    1: req_len_nxt = req_fbyte;
                    2: req_len_nxt = req_fbyte + req_lbyte;
                    default: req_len_nxt = ((s_axis_rq_tdata[74:64] - 2) * 4) + req_fbyte + req_lbyte;
                endcase
                if (m_axis_rc_tdata[30]) begin
                    cpl_len_nxt = m_axis_rc_tdata[28:16];
                end else begin
                    case (m_axis_rc_tdata[42:32])
                        0: cpl_len_nxt = 0;
                        1: cpl_len_nxt = cpl_fbyte;
                        default: cpl_len_nxt = ((m_axis_rc_tdata[42:32] - 1) * 4) + cpl_fbyte;
                    endcase
                end
            end
        end

        always_ff @(posedge user_clk) begin
            req_pend_cor_err_log_local[i] <= req_pend_cor_err_log_local[i] | cor_err | req_type_err | cpl_type_err;
            if (user_rst) begin
                req_pend_cor_err_log_local[i] <= 0;
            end
        end


        always_ff @(posedge user_clk) begin
            if (DATA_WIDTH == 256) begin
                // req_vld <= s_axis_rq_tvalid & s_axis_rq_tready & s_axis_rq_tfirst & (s_axis_rq_tdata[87:80] == i) & (s_axis_rq_tdata[78:75] == 4'h0);todo, pf
                req_vld <= s_axis_rq_tvalid & s_axis_rq_tready & s_axis_rq_tfirst & (s_axis_rq_tdata[78:75] == 4'h0);
                req_tag <= s_axis_rq_tdata[103:96];
                req_addr <= {s_axis_rq_tdata[63:2], req_addr_lo};
                req_len <= req_len_nxt;
                // cpl_vld <= m_axis_rc_tvalid & m_axis_rc_tready & m_axis_rc_tfirst & (s_axis_rq_tdata[55:48] == i);
                cpl_vld <= m_axis_rc_tvalid & m_axis_rc_tready & m_axis_rc_tfirst;
                cpl_tag <= m_axis_rc_tdata[71:64];
                cpl_addr <= m_axis_rc_tdata[11:0];
                cpl_len <= cpl_len_nxt;
                cpl_byte_count <= m_axis_rc_tdata[28:16];
                cpl_last <= m_axis_rc_tdata[30];
                cpl_stat <= m_axis_rc_tdata[45:43];
                // req_type_err <= s_axis_rq_tvalid & s_axis_rq_tready & s_axis_rq_tfirst & (s_axis_rq_tdata[87:80] == i) & ((s_axis_rq_tdata[78:75] != 4'h0) & (s_axis_rq_tdata[78:75] != 4'h1));
                req_type_err <= s_axis_rq_tvalid & s_axis_rq_tready & s_axis_rq_tfirst & ((s_axis_rq_tdata[78:75] != 4'h0) & (s_axis_rq_tdata[78:75] != 4'h1));
                // cpl_type_err <= m_axis_rc_tvalid & m_axis_rc_tready & m_axis_rc_tfirst & (s_axis_rq_tdata[55:48] == i) & ((s_axis_rq_tdata[45:43] != 0) | (s_axis_rq_tdata[42:32] == 0));
                cpl_type_err <= m_axis_rc_tvalid & m_axis_rc_tready & m_axis_rc_tfirst & ((m_axis_rc_tdata[45:43] != 0) | (m_axis_rc_tdata[42:32] == 0));
            end
            if (user_rst) begin
                req_vld <= 0;
                cpl_vld <= 0;
                req_type_err <= 0;
                cpl_type_err <= 0;
            end
        end

        pcie_brg_mon_np_cpl #(
            .TAG_WIDTH(TAG_WIDTH),
            .CPL_ADDR_WIDTH(7)
        ) pcie_brg_mon_req_cpl_local(
            .user_clk(user_clk),
            .user_rst(user_rst),
            .req_vld(req_vld),
            .req_tag(req_tag),
            .req_addr(req_addr),
            .req_len(req_len),
            .cpl_vld(cpl_vld),
            .cpl_tag(cpl_tag),
            .cpl_addr(cpl_addr),
            .cpl_len(cpl_len),
            .cpl_byte_count(cpl_byte_count),
            .cpl_last(cpl_last),
            .cpl_stat(cpl_stat),
            .req_pend(req_pend),
            .cor_err(cor_err),
            .req_cnt_sum(req_cnt_sum),
            .cpl_cnt_sum(cpl_cnt_sum),
            .lcpl_cnt_sum(lcpl_cnt_sum),
            .req_len_sum(req_len_sum),
            .cpl_len_sum(cpl_len_sum)
        );
    end
endgenerate

pcie_brg_mon_rq #(
    .DATA_WIDTH(DATA_WIDTH)
) pcie_brg_mon_rq(
    .user_clk(user_clk),
    .user_rst(user_rst),

    .s_axis_rq_tdata(s_axis_rq_tdata),
    .s_axis_rq_tuser(s_axis_rq_tuser),
    .s_axis_rq_tfirst(s_axis_rq_tfirst),
    .s_axis_rq_tlast(s_axis_rq_tlast),
    .s_axis_rq_tkeep(s_axis_rq_tkeep),
    .s_axis_rq_tvalid(s_axis_rq_tvalid),
    .s_axis_rq_tready(s_axis_rq_tready),
    .pcie_rq_seq_num0(pcie_rq_seq_num0),
    .pcie_rq_seq_num1(pcie_rq_seq_num1),
    .pcie_rq_seq_num_vld0(pcie_rq_seq_num_vld0),
    .pcie_rq_seq_num_vld1(pcie_rq_seq_num_vld1)
);

endmodule
