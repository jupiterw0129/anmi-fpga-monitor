`include "pcie_brg_def.svh"

module pcie_brg_rq_cc_mux#(
    parameter DATA_WIDTH = 512,
    parameter RQ_DWORD_ALIGN = 1,
    parameter CC_DWORD_ALIGN = 1,
    parameter RQ_STRADDLE = 0,
    parameter CC_STRADDLE = 0,

    parameter KEEP_WIDTH = DATA_WIDTH/32
) (
    input logic user_clk,
    input logic user_rst,

    pcie_rq_if.slv pcie_rq,
    pcie_cc_if.slv pcie_cc,

    input  logic rq_cc_tready,
    output logic rq_cc_tvalid,
    output logic rq_cc_tlast,
    output pcie_rq_tuser512_t rq_cc_tuser,// rq_tuser512 is superset of rq and cc tuser in all option
    output logic [KEEP_WIDTH-1:0] rq_cc_tkeep,
    output logic [DATA_WIDTH-1:0] rq_cc_tdata,
    output logic rq_cc_is_rq,
    input  logic [5:0] rq_cc_seq_num,
    input  logic rq_cc_seq_num_vld,

    output logic busy
);

assign pcie_rq.pcie_rq_seq_num0 = rq_cc_seq_num;
assign pcie_rq.pcie_rq_seq_num_vld0 = rq_cc_seq_num_vld;
assign pcie_rq.pcie_rq_seq_num1 = 0;
assign pcie_rq.pcie_rq_seq_num_vld1 = 0;

pcie_rq_tuser512_t rq_tuser;
pcie_rq_tuser512_t cc_tuser;

// rq tuser
generate
    if (DATA_WIDTH == 512) begin
        if (RQ_STRADDLE) begin
            assign rq_tuser = pcie_rq.tuser;
        end else begin
            pcie_rq_tuser512_t pcie_rq_tuser512;
            assign pcie_rq_tuser512 = pcie_rq.tuser;
            always_comb begin
                rq_tuser = 0;
                rq_tuser.first_be[3:0] = pcie_rq_tuser512.first_be[3:0];
                rq_tuser.last_be[3:0] = pcie_rq_tuser512.last_be[3:0];
                rq_tuser.addr_offset[1:0] = RQ_DWORD_ALIGN ? 0 : pcie_rq_tuser512.addr_offset[1:0];
                rq_tuser.is_sop[0] = pcie_rq_tuser512.is_sop[0];
                rq_tuser.is_sop0_ptr = pcie_rq_tuser512.is_sop0_ptr;
                rq_tuser.is_eop[0] = pcie_rq_tuser512.is_eop[0];
                rq_tuser.is_eop0_ptr = pcie_rq_tuser512.is_eop0_ptr;
                rq_tuser.discontinue = pcie_rq_tuser512.discontinue;
                rq_tuser.tph_present[0] = pcie_rq_tuser512.tph_present[0];
                rq_tuser.tph_type[1:0] = pcie_rq_tuser512.tph_type[1:0];
                rq_tuser.tph_indirect_tag_en[0] = pcie_rq_tuser512.tph_indirect_tag_en[0];
                rq_tuser.tph_st_tag[7:0] = pcie_rq_tuser512.tph_st_tag[7:0];
                rq_tuser.seq_num0 = pcie_rq_tuser512.seq_num0;
                rq_tuser.parity = pcie_rq_tuser512.parity;
            end
        end
    end else begin
        pcie_rq_tuser_t pcie_rq_tuser;
        assign pcie_rq_tuser = pcie_rq.tuser;
        always_comb begin
            rq_tuser = 0;
            rq_tuser.first_be[3:0] = pcie_rq_tuser.first_be;
            rq_tuser.last_be[3:0] = pcie_rq_tuser.last_be;
            rq_tuser.addr_offset[2:0] = RQ_DWORD_ALIGN ? 0 : pcie_rq_tuser.addr_offset;
            rq_tuser.discontinue = pcie_rq_tuser.discontinue;
            rq_tuser.tph_present[0] = pcie_rq_tuser.tph_present;
            rq_tuser.tph_type[1:0] = pcie_rq_tuser.tph_type;
            rq_tuser.tph_indirect_tag_en[0] = pcie_rq_tuser.tph_indirect_tag_en;
            rq_tuser.tph_st_tag[7:0] = pcie_rq_tuser.tph_st_tag;
            rq_tuser.seq_num0 = {pcie_rq_tuser.seq_num_ext, pcie_rq_tuser.seq_num};
            rq_tuser.parity[31:0] = pcie_rq_tuser.parity;
        end
    end
endgenerate

// cc tuser
generate
    if (DATA_WIDTH == 512) begin
        if (CC_STRADDLE) begin
            pcie_cc_tuser512_t pcie_cc_tuser512;
            assign pcie_cc_tuser512 = pcie_cc.tuser;
            always_comb begin
                cc_tuser = 0;
                cc_tuser.is_sop = pcie_cc_tuser512.is_sop;
                cc_tuser.is_sop0_ptr = pcie_cc_tuser512.is_sop0_ptr;
                cc_tuser.is_sop1_ptr = pcie_cc_tuser512.is_sop1_ptr;
                cc_tuser.is_eop = pcie_cc_tuser512.is_eop;
                cc_tuser.is_eop0_ptr = pcie_cc_tuser512.is_eop0_ptr;
                cc_tuser.is_eop1_ptr = pcie_cc_tuser512.is_eop1_ptr;
                cc_tuser.discontinue = pcie_cc_tuser512.discontinue;
                cc_tuser.parity = pcie_cc_tuser512.parity;
            end
        end else begin
            pcie_cc_tuser512_t pcie_cc_tuser512;
            assign pcie_cc_tuser512 = pcie_cc.tuser;
            always_comb begin
                cc_tuser = 0;
                cc_tuser.is_sop[0] = pcie_cc_tuser512.is_sop[0];
                cc_tuser.is_sop0_ptr = pcie_cc_tuser512.is_sop0_ptr;
                cc_tuser.is_eop[0] = pcie_cc_tuser512.is_eop[0];
                cc_tuser.is_eop0_ptr = pcie_cc_tuser512.is_eop0_ptr;
                cc_tuser.discontinue = pcie_cc_tuser512.discontinue;
                cc_tuser.parity = pcie_cc_tuser512.parity;
            end
        end
    end else begin
        pcie_cc_tuser_t pcie_cc_tuser;
        assign pcie_cc_tuser = pcie_cc.tuser;
        always_comb begin
            cc_tuser = 0;
            cc_tuser.discontinue = pcie_cc_tuser.discontinue;
            cc_tuser.parity[31:0] = pcie_cc_tuser.parity;
        end
    end
endgenerate

// mux

logic pcie_rq_end;
logic pcie_cc_end;

always_comb begin
    pcie_rq_end = 0;
    pcie_cc_end = 0;
    if (RQ_STRADDLE) begin
        pcie_rq_end = (rq_tuser.is_eop[0] & ~((rq_tuser.is_sop[0] & rq_tuser.is_sop0_ptr[1]) | rq_tuser.is_sop[1])) | rq_tuser.is_eop[1];
    end else begin
        pcie_rq_end = pcie_rq.tlast;
    end
    if (CC_STRADDLE) begin
        pcie_cc_end = (cc_tuser.is_eop[0] & ~((cc_tuser.is_sop[0] & cc_tuser.is_sop0_ptr[1]) | cc_tuser.is_sop[1])) | cc_tuser.is_eop[1];
    end else begin
        pcie_cc_end = pcie_cc.tlast;
    end
end

logic rq_cc_tready_int;
logic rq_cc_tvalid_int;
logic rq_cc_tlast_int;
pcie_rq_tuser512_t rq_cc_tuser_int;
logic [KEEP_WIDTH-1:0] rq_cc_tkeep_int;
logic [DATA_WIDTH-1:0] rq_cc_tdata_int;
logic rq_cc_is_rq_int;
logic rq_prior;
logic mux_rq;

assign pcie_rq.tready = rq_cc_tready_int & (rq_prior | ~pcie_cc.tvalid);
assign pcie_cc.tready = rq_cc_tready_int & (~rq_prior | ~pcie_rq.tvalid);
assign rq_cc_tvalid_int = pcie_rq.tvalid | pcie_cc.tvalid;
assign mux_rq = rq_prior ? pcie_rq.tvalid : ~pcie_cc.tvalid;
assign rq_cc_tlast_int = mux_rq ? pcie_rq.tlast : pcie_cc.tlast;
assign rq_cc_tuser_int = mux_rq ? rq_tuser : cc_tuser;
assign rq_cc_tkeep_int = mux_rq ? pcie_rq.tkeep : pcie_cc.tkeep;
assign rq_cc_tdata_int = mux_rq ? pcie_rq.tdata : pcie_cc.tdata;
assign rq_cc_is_rq_int = mux_rq;

always_ff @(posedge user_clk) begin
    if (user_rst) begin
        rq_prior <= 1;
    end else begin
        if ((pcie_rq.tvalid & pcie_rq.tready & pcie_rq_end) | (pcie_cc.tvalid & pcie_cc.tready & pcie_cc_end))
            rq_prior <= ~mux_rq;
        else if ((pcie_rq.tvalid & pcie_rq.tready) | (pcie_cc.tvalid & pcie_cc.tready))
            rq_prior <= pcie_rq.tvalid & pcie_rq.tready;
    end
end

// reg slice

pcie_brg_reg_slice #(
    .MODE("BWD"),
    .WIDTH(1+$bits(pcie_rq_tuser512_t)+KEEP_WIDTH+DATA_WIDTH+1)
) rq_cc_reg_slice(
    .clk(user_clk),
    .rst(user_rst),
    .src_vld(rq_cc_tvalid_int),
    .src_rdy(rq_cc_tready_int),
    .src_pld({rq_cc_tlast_int, rq_cc_tuser_int, rq_cc_tkeep_int, rq_cc_tdata_int, rq_cc_is_rq_int}),
    .dst_vld(rq_cc_tvalid),
    .dst_rdy(rq_cc_tready),
    .dst_pld({rq_cc_tlast, rq_cc_tuser, rq_cc_tkeep, rq_cc_tdata, rq_cc_is_rq})
);

assign busy = ~rq_cc_tready_int;

endmodule
