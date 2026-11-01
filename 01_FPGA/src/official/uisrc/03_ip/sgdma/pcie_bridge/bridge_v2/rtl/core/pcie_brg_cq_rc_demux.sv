`include "pcie_brg_def.svh"

module pcie_brg_cq_rc_demux#(
    parameter DATA_WIDTH = 512,
    parameter CQ_STRADDLE = 0,
    parameter RC_STRADDLE = 0,

    parameter KEEP_WIDTH = DATA_WIDTH/32
) (
    input logic user_clk,
    input logic user_rst,

    pcie_cq_if.mst pcie_cq,
    pcie_rc_if.mst pcie_rc,

    output logic cq_rc_tready,
    input  logic cq_rc_tvalid,
    input  logic cq_rc_tlast,
    input  pcie_cq_tuser512_t cq_rc_tuser,// cq_tuser512 is superset of cq and rc tuser in all option
    input  logic [KEEP_WIDTH-1:0] cq_rc_tkeep,
    input  logic [DATA_WIDTH-1:0] cq_rc_tdata,
    input  logic cq_rc_is_cq,
    output logic [1:0] np_req,
    input  logic [5:0] np_req_count,

    output logic busy
);

pcie_cq_tuser512_t cq_tuser512;
pcie_rc_tuser512_t rc_tuser512;
pcie_cq_tuser_t cq_tuser;
pcie_rc_tuser_t rc_tuser;

// cq tuser
generate
    if (DATA_WIDTH == 512) begin
        if (CQ_STRADDLE) begin
            assign cq_tuser512 = cq_rc_tuser;
            assign cq_tuser = 0;
        end else begin
            always_comb begin
                cq_tuser512 = 0;
                cq_tuser512.first_be[3:0] = cq_rc_tuser.first_be[3:0];
                cq_tuser512.last_be[3:0] = cq_rc_tuser.last_be[3:0];
                cq_tuser512.byte_en = cq_rc_tuser.byte_en;
                cq_tuser512.is_sop[0] = cq_rc_tuser.is_sop[0];
                cq_tuser512.is_eop[0] = cq_rc_tuser.is_eop[0];
                cq_tuser512.discontinue = cq_rc_tuser.discontinue;
                cq_tuser512.tph_present[0] = cq_rc_tuser.tph_present[0];
                cq_tuser512.tph_type[1:0] = cq_rc_tuser.tph_type[1:0];
                cq_tuser512.tph_st_tag[7:0] = cq_rc_tuser.tph_st_tag[7:0];
                cq_tuser512.parity = cq_rc_tuser.parity;
            end
            assign cq_tuser = 0;
        end
    end else begin
        always_comb begin
            cq_tuser = 0;
            cq_tuser.first_be = cq_rc_tuser.first_be[3:0];
            cq_tuser.last_be = cq_rc_tuser.last_be[3:0];
            cq_tuser.byte_en = cq_rc_tuser.byte_en[31:0];
            cq_tuser.sop = cq_rc_tuser.is_sop[0];
            cq_tuser.discontinue = cq_rc_tuser.discontinue;
            cq_tuser.tph_present = cq_rc_tuser.tph_present[0];
            cq_tuser.tph_type = cq_rc_tuser.tph_type[1:0];
            cq_tuser.tph_st_tag = cq_rc_tuser.tph_st_tag[7:0];
            cq_tuser.parity = cq_rc_tuser.parity[31:0];
        end
        assign cq_tuser512 = 0;
    end
endgenerate

// rc tuser
generate
    if (DATA_WIDTH == 512) begin
        if (RC_STRADDLE) begin
            always_comb begin
                rc_tuser512 = 0;
                rc_tuser512.byte_en = cq_rc_tuser.byte_en;
                rc_tuser512.is_sop[1:0] = cq_rc_tuser.is_sop;
                rc_tuser512.is_sop0_ptr = cq_rc_tuser.is_sop0_ptr;
                rc_tuser512.is_sop1_ptr = cq_rc_tuser.is_sop1_ptr;
                rc_tuser512.is_eop[1:0] = cq_rc_tuser.is_eop;
                rc_tuser512.is_eop0_ptr = cq_rc_tuser.is_eop0_ptr;
                rc_tuser512.is_eop1_ptr = cq_rc_tuser.is_eop1_ptr;
                rc_tuser512.discontinue = cq_rc_tuser.discontinue;
                rc_tuser512.parity = cq_rc_tuser.parity;
            end
            assign rc_tuser = 0;
        end else begin
            always_comb begin
                rc_tuser512 = 0;
                rc_tuser512.byte_en = cq_rc_tuser.byte_en;
                rc_tuser512.is_sop[0] = cq_rc_tuser.is_sop[0];
                rc_tuser512.is_eop[0] = cq_rc_tuser.is_eop[0];
                rc_tuser512.discontinue = cq_rc_tuser.discontinue;
                rc_tuser512.parity = cq_rc_tuser.parity;
            end
            assign rc_tuser = 0;
        end
    end else begin
        always_comb begin
                rc_tuser = 0;
                rc_tuser.byte_en = cq_rc_tuser.byte_en[31:0];
                rc_tuser.is_sof_0 = cq_rc_tuser.is_sop[0];
                rc_tuser.is_eof_0[0] = cq_rc_tuser.is_eop[0];
                rc_tuser.is_eof_0[3:1] = cq_rc_tuser.is_eop0_ptr[2:0];
                rc_tuser.discontinue = cq_rc_tuser.discontinue;
                rc_tuser.parity = cq_rc_tuser.parity[31:0];
            end
        assign rc_tuser512 = 0;
    end
endgenerate

logic cq_rc_tvalid_r;
logic cq_rc_tlast_r;
logic [KEEP_WIDTH-1:0] cq_rc_tkeep_r;
logic [DATA_WIDTH-1:0] cq_rc_tdata_r;
pcie_cq_tuser512_t cq_tuser512_r;
pcie_rc_tuser512_t rc_tuser512_r;
pcie_cq_tuser_t cq_tuser_r;
pcie_rc_tuser_t rc_tuser_r;
logic cq_rc_is_cq_r;

assign cq_rc_tready = ~cq_rc_tvalid_r | (cq_rc_is_cq_r ? pcie_cq.tready : pcie_rc.tready);
assign pcie_cq.tdata = cq_rc_tdata_r;
assign pcie_cq.tuser = (DATA_WIDTH == 512) ? cq_tuser512_r : cq_tuser_r;
assign pcie_cq.tlast = cq_rc_tlast_r;
assign pcie_cq.tkeep = cq_rc_tkeep_r;
assign pcie_rc.tdata = cq_rc_tdata_r;
assign pcie_rc.tuser = (DATA_WIDTH == 512) ? rc_tuser512_r : rc_tuser_r;
assign pcie_rc.tlast = cq_rc_tlast_r;
assign pcie_rc.tkeep = cq_rc_tkeep_r;
assign np_req = pcie_cq.np_req;
assign pcie_cq.np_req_count = np_req_count;

always_ff @(posedge user_clk) begin
    if (cq_rc_tready) begin
        cq_rc_tlast_r <= cq_rc_tlast;
        cq_rc_tkeep_r <= cq_rc_tkeep;
        cq_rc_tdata_r <= cq_rc_tdata;
        cq_rc_is_cq_r <= cq_rc_is_cq;
        cq_tuser512_r <= cq_tuser512;
        rc_tuser512_r <= rc_tuser512;
        cq_tuser_r <= cq_tuser;
        rc_tuser_r <= rc_tuser;
    end
end

always_ff @(posedge user_clk) begin
    if (user_rst) begin
        cq_rc_tvalid_r <= 0;
        pcie_cq.tvalid <= 0;
        pcie_rc.tvalid <= 0;
    end else begin
        if (cq_rc_tvalid) begin
            cq_rc_tvalid_r <= 1;
        end else if (cq_rc_is_cq_r ? pcie_cq.tready : pcie_rc.tready) begin
            cq_rc_tvalid_r <= 0;
        end
        if (cq_rc_tready & cq_rc_tvalid & cq_rc_is_cq) begin
            pcie_cq.tvalid <= 1;
        end else if (pcie_cq.tready) begin
            pcie_cq.tvalid <= 0;
        end
        if (cq_rc_tready & cq_rc_tvalid & ~cq_rc_is_cq) begin
            pcie_rc.tvalid <= 1;
        end else if (pcie_rc.tready) begin
            pcie_rc.tvalid <= 0;
        end
    end
end

assign busy = cq_rc_tvalid_r;

endmodule
