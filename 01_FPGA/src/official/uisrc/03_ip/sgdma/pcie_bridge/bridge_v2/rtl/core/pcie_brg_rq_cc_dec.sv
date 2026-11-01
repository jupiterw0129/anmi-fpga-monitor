`include "pcie_brg_def.svh"

module pcie_brg_rq_cc_dec#(
    parameter DATA_WIDTH = 512,
    parameter RQ_DWORD_ALIGN = 1,
    parameter CC_DWORD_ALIGN = 1,
    parameter RQ_STRADDLE = 0,
    parameter CC_STRADDLE = 0,

    parameter KEEP_WIDTH = DATA_WIDTH/32,
    parameter DW_WIDTH = $clog2(KEEP_WIDTH)
) (
    input  logic user_clk,
    input  logic user_rst,

    input  logic ari_cap,
    input  logic [7:0] bus_num,
    input  logic [4:0] dev_num,

    output logic rq_cc_tready,
    input  logic rq_cc_tvalid,
    input  logic rq_cc_tlast,
    input  pcie_rq_tuser512_t rq_cc_tuser,
    input  logic [KEEP_WIDTH-1:0] rq_cc_tkeep,
    input  logic [DATA_WIDTH-1:0] rq_cc_tdata,
    input  logic rq_cc_is_rq,
    output logic [5:0] rq_cc_seq_num,
    output logic rq_cc_seq_num_vld,

    input  logic rq_cc_tlp_rdy,
    output logic rq_cc_tlp_vld,
    output logic rq_cc_tlp_sop,
    output logic rq_cc_tlp_eop,
    output pcie_tlp_header_t rq_cc_tlp_header,
    output logic [DATA_WIDTH-1:0] rq_cc_tlp_data,
    output logic rq_cc_discontinue,
    output logic rq_cc_force_ecrc,
    output logic [5:0] rq_cc_tlp_seq_num,
    output logic rq_cc_tlp_is_rq,
    output logic rq_cc_req_type_err,
    output logic rq_cc_cpl_status_ur_ca,
    output logic rq_cc_cpl_status_err,
    input  logic pcie_rq_seq_num_vld,
    input  logic [5:0] pcie_rq_seq_num,

    output logic busy
);

logic sm_idle_c, sm_header_half_c, sm_header_wait_c, sm_xmit_c, sm_xmit2_c;
logic sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_xmit_r, sm_xmit2_r;

logic                  rq_cc_straddle_c;
logic                  rq_cc_dword_align_c;
logic                  rq_cc_tvalid_c;
logic                  rq_cc_tready_c;
logic                  rq_cc_tlast_c;
pcie_rq_tuser512_t     rq_cc_tuser512_c;
logic [KEEP_WIDTH-1:0] rq_cc_tkeep_c;
logic [DATA_WIDTH-1:0] rq_cc_tdata_c;
logic                  rq_cc_is_rq_c;
pcie_cc_desc_t         cc_desc_nxt_c;
logic [127:0]          rq_cc_desc_r;
pcie_rq_desc_t         rq_desc_r;
pcie_cc_desc_t         cc_desc_r;
logic [1:0]            is_sop_c;
logic [1:0]            is_sop0_ptr_c;
logic [1:0]            is_sop1_ptr_c;
logic [1:0]            is_eop_c;
logic [3:0]            is_eop0_ptr_c;
logic [3:0]            is_eop1_ptr_c;
logic [1:0]            sop_slot_c;
logic [1:0]            eop_slot_c;
logic [7:0]            first_be_slot_c;
logic [7:0]            last_be_slot_c;
logic [1:0]            tph_present_slot_c;
logic [3:0]            tph_type_slot_c;
logic [15:0]           tph_st_tag_slot_c;
logic [5:0]            seq_num_slot0_c;
logic [5:0]            seq_num_slot1_c;
logic                  header_update_c;
logic                  header_sel_c;// straddle mode only, select which header is active
logic                  header_4dw_c;
logic [3:0]            req_type_r;
logic                  cpl_sc_c;
logic                  cpl_ur_c;
logic                  cpl_ca_c;
logic                  cpl_status_ur_ca_c;
logic                  cpl_status_err_c;

logic                  rq_cc_straddle_r;
logic                  rq_cc_dword_align_r;
logic                  rq_cc_last_r;
pcie_rq_tuser512_t     rq_cc_tuser512_r;
logic [KEEP_WIDTH-1:0] rq_cc_tkeep_r;
logic [DATA_WIDTH-1:0] rq_cc_tdata_r;
logic [DATA_WIDTH-1:0] rq_cc_tdata_r2;
logic [DATA_WIDTH-1:0] rq_cc_tdata_r3;
logic                  rq_cc_is_rq_r;
logic [1:0]            is_sop_r;
logic [1:0]            is_sop0_ptr_r;
logic [1:0]            is_sop1_ptr_r;
logic [1:0]            is_eop_r;
logic [3:0]            is_eop0_ptr_r;
logic [3:0]            is_eop1_ptr_r;
logic                  header_sel_r;
logic [DW_WIDTH-1:0]   payload_offset_r;
logic [1:0]            sop_slot_r;
logic [1:0]            eop_slot_r;
logic [7:0]            first_be_slot_r;
logic [7:0]            last_be_slot_r;
logic [1:0]            tph_present_slot_r;
logic [3:0]            tph_type_slot_r;
logic [15:0]           tph_st_tag_slot_r;
logic [5:0]            seq_num_slot0_r;
logic [5:0]            seq_num_slot1_r;

assign rq_cc_straddle_c = rq_cc_is_rq_c ? RQ_STRADDLE : CC_STRADDLE;
assign rq_cc_dword_align_c = rq_cc_is_rq_c ? RQ_DWORD_ALIGN : CC_DWORD_ALIGN;
assign rq_cc_tready = rq_cc_tready_c;
assign rq_cc_tvalid_c = rq_cc_tvalid;
assign rq_cc_tlast_c = rq_cc_tlast;
assign rq_cc_tuser512_c = rq_cc_tuser;
assign rq_cc_tkeep_c = rq_cc_tkeep;
assign rq_cc_tdata_c = rq_cc_tdata;
assign rq_cc_is_rq_c = rq_cc_is_rq;
assign cc_desc_nxt_c = CC_STRADDLE ? (header_sel_c ? rq_cc_tdata_c[511:256] : rq_cc_tdata_c[255:0]) : ((DATA_WIDTH == 64) ? {2{rq_cc_tdata_c}} : rq_cc_tdata_c);
assign rq_desc_r = rq_cc_desc_r;
assign cc_desc_r = rq_cc_desc_r;
assign is_sop_c = rq_cc_tuser512_c.is_sop;
assign is_sop0_ptr_c = rq_cc_tuser512_c.is_sop0_ptr;
assign is_sop1_ptr_c = rq_cc_tuser512_c.is_eop0_ptr;
assign is_eop_c = rq_cc_tuser512_c.is_eop;
assign is_eop0_ptr_c = rq_cc_tuser512_c.is_eop0_ptr;
assign is_eop1_ptr_c = rq_cc_tuser512_c.is_eop1_ptr;
assign req_type_r = rq_desc_r.rq_desc_dw.dw2[14:11];
assign sop_slot_c[0] = (is_sop_c[0] & ~is_sop0_ptr_c[1]) | is_sop_c[1];
assign sop_slot_c[1] = (is_sop_c[0] & is_sop0_ptr_c[1]) | is_sop_c[1];
assign eop_slot_c[0] = (is_eop_c[0] & ~is_eop0_ptr_c[3]) | is_eop_c[1];
assign eop_slot_c[1] = (is_eop_c[0] & is_eop0_ptr_c[3]) | is_eop_c[1];
assign first_be_slot_c[3:0] = rq_cc_tuser512_c.first_be[3:0];
assign first_be_slot_c[7:4] = is_sop_c[1] ? rq_cc_tuser512_c.first_be[7:4] : rq_cc_tuser512_c.first_be[3:0];
assign last_be_slot_c[3:0] = rq_cc_tuser512_c.last_be[3:0];
assign last_be_slot_c[7:4] = is_sop_c[1] ? rq_cc_tuser512_c.last_be[7:4] : rq_cc_tuser512_c.last_be[3:0];
assign tph_present_slot_c[0] = rq_cc_tuser512_c.tph_present[0];
assign tph_present_slot_c[1] = is_sop_c[1] ? rq_cc_tuser512_c.tph_present[1] : rq_cc_tuser512_c.tph_present[0];
assign tph_type_slot_c[1:0] = rq_cc_tuser512_c.tph_type[1:0];
assign tph_type_slot_c[3:2] = is_sop_c[1] ? rq_cc_tuser512_c.tph_type[3:2] : rq_cc_tuser512_c.tph_type[1:0];
assign tph_st_tag_slot_c[7:0] = rq_cc_tuser512_c.tph_st_tag[7:0];
assign tph_st_tag_slot_c[15:8] = is_sop_c[1] ? rq_cc_tuser512_c.tph_st_tag[15:8] : rq_cc_tuser512_c.tph_st_tag[7:0];
assign seq_num_slot0_c = rq_cc_tuser512_c.seq_num0;
assign seq_num_slot1_c = is_sop_c[1] ? rq_cc_tuser512_c.seq_num1 : rq_cc_tuser512_c.seq_num0;

always_comb begin
    rq_cc_desc_r = 0;
    if ((DATA_WIDTH == 512) & rq_cc_straddle_r)
        rq_cc_desc_r = header_sel_r ? rq_cc_tdata_r[511:256] : rq_cc_tdata_r[255:0];
    else begin
        if (DATA_WIDTH == 64) begin
            if (rq_cc_is_rq_r)
                rq_cc_desc_r = {rq_cc_tdata_r2, rq_cc_tdata_r3};
            else begin
                rq_cc_desc_r = CC_DWORD_ALIGN ? {rq_cc_tdata_r, rq_cc_tdata_r2} : {rq_cc_tdata_r2, rq_cc_tdata_r3};
            end
        end else if (DATA_WIDTH == 128) begin
            if (rq_cc_is_rq_r)
                rq_cc_desc_r = rq_cc_tdata_r2;
            else
                rq_cc_desc_r = rq_cc_tdata_r;
        end else if ((DATA_WIDTH == 256) | (DATA_WIDTH == 512)) begin
            rq_cc_desc_r = rq_cc_tdata_r;
        end
    end
end

always_ff @(posedge user_clk) begin
    if (rq_cc_tready_c) begin
        rq_cc_straddle_r <= rq_cc_straddle_c;
        rq_cc_dword_align_r <= rq_cc_dword_align_c;
        rq_cc_last_r <= rq_cc_tlast_c;
        rq_cc_tuser512_r <= rq_cc_tuser512_c;
        rq_cc_tkeep_r <= rq_cc_tkeep_c;
        rq_cc_tdata_r <= rq_cc_tdata_c;
        rq_cc_tdata_r2 <= rq_cc_tdata_r;
        rq_cc_tdata_r3 <= rq_cc_tdata_r2;
        rq_cc_is_rq_r <= rq_cc_is_rq_c;
        is_sop_r <= is_sop_c;
        is_sop0_ptr_r <= is_sop0_ptr_c;
        is_sop1_ptr_r <= is_sop1_ptr_c;
        is_eop_r <= is_eop_c;
        is_eop0_ptr_r <= is_eop0_ptr_c;
        is_eop1_ptr_r <= is_eop1_ptr_c;
        sop_slot_r <= sop_slot_c;
        eop_slot_r <= eop_slot_c;
        first_be_slot_r <= first_be_slot_c;
        last_be_slot_r <= last_be_slot_c;
        tph_present_slot_r <= tph_present_slot_c;
        tph_type_slot_r <= tph_type_slot_c;
        tph_st_tag_slot_r <= tph_st_tag_slot_c;
        seq_num_slot0_r <= seq_num_slot0_c;
        seq_num_slot1_r <= seq_num_slot1_c;
    end
end

always_ff @(posedge user_clk) begin
    if (user_rst)
        {sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_xmit_r, sm_xmit2_r} <= 5'b10000;
    else
        {sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_xmit_r, sm_xmit2_r} <= {sm_idle_c, sm_header_half_c, sm_header_wait_c, sm_xmit_c, sm_xmit2_c};
end

always_comb begin
    sm_idle_c = sm_idle_r;
    sm_header_half_c = sm_header_half_r;
    sm_header_wait_c = sm_header_wait_r;
    sm_xmit_c = sm_xmit_r;
    sm_xmit2_c = sm_xmit2_r;
    header_update_c = 0;
    header_sel_c = 0;
    unique case (1)
        sm_idle_r: begin
            if (rq_cc_tvalid_c) begin
                sm_idle_c = 0;
            end
            // new tlp come in, is copied to other state
            //----------------copy begin----------------
            if (rq_cc_tvalid_c) begin
                header_update_c = 1;
                if (rq_cc_straddle_c) begin
                    if (is_sop_c[1])
                        sm_xmit2_c = 1;
                    else
                        sm_xmit_c = 1;
                end else if (DATA_WIDTH == 64) begin
                    if (rq_cc_tlast_c)// rq_cc_discontinue
                        sm_xmit_c = 1;
                    else
                        sm_header_half_c = 1;
                end else if (DATA_WIDTH == 128) begin
                    if (rq_cc_is_rq_c) begin// rq
                        if (rq_cc_tlast_c)
                            sm_xmit_c = 1;
                        else
                            sm_header_wait_c = 1;
                    end else begin// cc
                        if (rq_cc_dword_align_c)
                            sm_xmit_c = 1;
                        else begin
                            if (rq_cc_tlast_c)
                                sm_xmit_c = 1;
                            else
                                sm_header_wait_c = 1;
                        end
                    end
                end else if (DATA_WIDTH == 256) begin
                    if (rq_cc_dword_align_c)
                        sm_xmit_c = 1;
                    else begin
                        if (rq_cc_tlast_c)
                            sm_xmit_c = 1;
                        else
                            sm_header_wait_c = 1;
                    end
                end else if (DATA_WIDTH == 512) begin
                    sm_xmit_c = 1;
                end
            end else begin
                sm_idle_c = 1;
            end
            //----------------copy end----------------
        end
        sm_header_half_r: begin// 64b half header
            sm_header_half_c = 0;
            if (rq_cc_is_rq_r) begin// rq
                if (rq_cc_tlast_c)
                    sm_xmit_c = 1;
                else
                    sm_header_wait_c = 1;
            end else begin// cc
                if (rq_cc_dword_align_r)
                    sm_xmit_c = 1;
                else begin
                    if (rq_cc_tlast_c)
                        sm_xmit_c = 1;
                    else
                        sm_header_wait_c = 1;
                end
            end
        end
        sm_header_wait_r: begin// 64b, 128b or 256b address align
            sm_header_wait_c = 0;
            sm_xmit_c = 1;
        end
        sm_xmit_r: begin
            if (rq_cc_tlp_rdy) begin
                if (rq_cc_straddle_r) begin
                    // xmit end in 1 beat
                    if (payload_offset_r[DW_WIDTH-1] ? eop_slot_r[1] : (|eop_slot_r))
                    begin
                        sm_xmit_c = 0;
                        //----------------copy begin----------------
                        if (rq_cc_tvalid_c) begin
                            header_update_c = 1;
                            if (rq_cc_straddle_c) begin
                                if (is_sop_c[1])
                                    sm_xmit2_c = 1;
                                else
                                    sm_xmit_c = 1;
                            end else if (DATA_WIDTH == 64) begin
                                if (rq_cc_tlast_c)// rq_cc_discontinue
                                    sm_xmit_c = 1;
                                else
                                    sm_header_half_c = 1;
                            end else if (DATA_WIDTH == 128) begin
                                if (rq_cc_is_rq_c) begin// rq
                                    if (rq_cc_tlast_c)
                                        sm_xmit_c = 1;
                                    else
                                        sm_header_wait_c = 1;
                                end else begin// cc
                                    if (rq_cc_dword_align_c)
                                        sm_xmit_c = 1;
                                    else begin
                                        if (rq_cc_tlast_c)
                                            sm_xmit_c = 1;
                                        else
                                            sm_header_wait_c = 1;
                                    end
                                end
                            end else if (DATA_WIDTH == 256) begin
                                if (rq_cc_dword_align_c)
                                    sm_xmit_c = 1;
                                else begin
                                    if (rq_cc_tlast_c)
                                        sm_xmit_c = 1;
                                    else
                                        sm_header_wait_c = 1;
                                end
                            end else if (DATA_WIDTH == 512) begin
                                sm_xmit_c = 1;
                            end
                        end else begin
                            sm_idle_c = 1;
                        end
                        //----------------copy end----------------
                    end
                    // xmit end in 2 beats
                    else if (is_eop_c[0] & (is_eop0_ptr_c < payload_offset_r)) begin
                        if (~is_sop_c[0]) begin
                            sm_xmit_c = 0;
                            sm_idle_c = 1;
                        end else begin
                            header_update_c = 1;
                            header_sel_c = 1;
                        end
                    end
                    // xmit end in 2 beats
                    else if (is_eop_c[0] & ~(is_eop0_ptr_c < payload_offset_r)) begin
                        if (is_sop_c[0]) begin
                            sm_xmit_c = 0;
                            sm_xmit2_c = 1;
                        end
                    end
                end else begin// address or dword but no straddle
                    if (rq_cc_last_r) begin
                        sm_xmit_c = 0;
                        //----------------copy begin----------------
                        if (rq_cc_tvalid_c) begin
                            header_update_c = 1;
                            if (rq_cc_straddle_c) begin
                                if (is_sop_c[1])
                                    sm_xmit2_c = 1;
                                else
                                    sm_xmit_c = 1;
                            end else if (DATA_WIDTH == 64) begin
                                if (rq_cc_tlast_c)// rq_cc_discontinue
                                    sm_xmit_c = 1;
                                else
                                    sm_header_half_c = 1;
                            end else if (DATA_WIDTH == 128) begin
                                if (rq_cc_is_rq_c) begin// rq
                                    if (rq_cc_tlast_c)
                                        sm_xmit_c = 1;
                                    else
                                        sm_header_wait_c = 1;
                                end else begin// cc
                                    if (rq_cc_dword_align_c)
                                        sm_xmit_c = 1;
                                    else begin
                                        if (rq_cc_tlast_c)
                                            sm_xmit_c = 1;
                                        else
                                            sm_header_wait_c = 1;
                                    end
                                end
                            end else if (DATA_WIDTH == 256) begin
                                if (rq_cc_dword_align_c)
                                    sm_xmit_c = 1;
                                else begin
                                    if (rq_cc_tlast_c)
                                        sm_xmit_c = 1;
                                    else
                                        sm_header_wait_c = 1;
                                end
                            end else if (DATA_WIDTH == 512) begin
                                sm_xmit_c = 1;
                            end
                        end else begin
                            sm_idle_c = 1;
                        end
                        //----------------copy end----------------
                    end else if (rq_cc_tlast_c) begin
                        if (~rq_cc_tkeep_c[payload_offset_r]) begin
                            sm_xmit_c = 0;
                            sm_idle_c = 1;
                        end
                    end
                end
            end
        end
        sm_xmit2_r: begin// straddle
            header_sel_c = 1;
            if (rq_cc_tlp_rdy) begin
                sm_xmit2_c = 0;
                sm_xmit_c = 1;
                header_update_c = 1;
            end
        end
    endcase
end

assign rq_cc_tready_c = sm_idle_r | sm_header_half_r | sm_header_wait_r | (sm_xmit_r & rq_cc_tlp_rdy);
assign rq_cc_tlp_vld = sm_xmit_r | sm_xmit2_r;
assign rq_cc_tlp_data = {rq_cc_tdata_c, rq_cc_tdata_r} >> {payload_offset_r, 5'b0};
assign rq_cc_discontinue = (rq_cc_straddle_r ? (|eop_slot_r) : rq_cc_last_r) ? rq_cc_tuser512_r.discontinue : (rq_cc_tuser512_r.discontinue | rq_cc_tuser512_c.discontinue);
assign rq_cc_tlp_seq_num = header_sel_r ? seq_num_slot1_r : seq_num_slot0_r;
assign rq_cc_seq_num_vld = pcie_rq_seq_num_vld;
assign rq_cc_seq_num = pcie_rq_seq_num;
assign rq_cc_tlp_is_rq = rq_cc_is_rq_r;
assign rq_cc_req_type_err = req_type_r == 4'd15;
assign rq_cc_cpl_status_ur_ca = cpl_status_ur_ca_c;
assign rq_cc_cpl_status_err = cpl_status_err_c;
assign cpl_sc_c = cc_desc_r.cpl_status == 3'b000;
assign cpl_ur_c = cc_desc_r.cpl_status == 3'b001;
assign cpl_ca_c = cc_desc_r.cpl_status == 3'b100;
assign cpl_status_ur_ca_c = cpl_ur_c | cpl_ca_c;
assign cpl_status_err_c = ~(cpl_sc_c | cpl_ur_c | cpl_ca_c);

always_comb begin
    rq_cc_tlp_eop = 0;
    if (rq_cc_straddle_r) begin
        if (payload_offset_r[DW_WIDTH-1])
            rq_cc_tlp_eop = eop_slot_r[1] | (is_eop_c[0] & (is_eop0_ptr_c < payload_offset_r));
        else
            rq_cc_tlp_eop = eop_slot_r[1] | eop_slot_r[0] | (is_eop_c[0] & (is_eop0_ptr_c < payload_offset_r));
    end else begin
        rq_cc_tlp_eop = rq_cc_last_r | ~rq_cc_tkeep_c[payload_offset_r];
    end
end

always_ff @(posedge user_clk) begin
    if (user_rst)
        rq_cc_tlp_sop <= 1;
    else if (rq_cc_tlp_vld & rq_cc_tlp_rdy)
        rq_cc_tlp_sop <= rq_cc_tlp_eop;
end

always_ff @(posedge user_clk) begin
    if (header_update_c)
        header_sel_r <= header_sel_c;
end

always_comb begin
    rq_cc_tlp_header = 0;
    rq_cc_force_ecrc = 0;
    header_4dw_c = 0;
    if (rq_cc_is_rq_r) begin
        case (req_type_r)
            4'd0, 4'd1, 4'd4, 4'd5, 4'd6, 4'd7: begin// mem, atomic, locked
                header_4dw_c = |rq_desc_r.rq_desc_dw.dw1;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_mem.force_ecrc;
                // dw0
                rq_cc_tlp_header.dw0[31] = 0;
                case (req_type_r)
                    4'd0, 4'd7:             rq_cc_tlp_header.dw0[30] = 0;
                    4'd1, 4'd4, 4'd5, 4'd6: rq_cc_tlp_header.dw0[30] = 1;
                endcase
                rq_cc_tlp_header.dw0[29] = header_4dw_c ? 1 : 0;
                case (req_type_r)
                    4'd0: rq_cc_tlp_header.dw0[28:24] = 5'b00000;
                    4'd1: rq_cc_tlp_header.dw0[28:24] = 5'b00000;
                    4'd4: rq_cc_tlp_header.dw0[28:24] = 5'b01100;
                    4'd5: rq_cc_tlp_header.dw0[28:24] = 5'b01101;
                    4'd6: rq_cc_tlp_header.dw0[28:24] = 5'b01110;
                    4'd7: rq_cc_tlp_header.dw0[28:24] = 5'b00001;
                endcase
                rq_cc_tlp_header.dw0[22:20] = rq_desc_r.rq_desc_mem.tc;
                {rq_cc_tlp_header.dw0[18], rq_cc_tlp_header.dw0[13:12]} = rq_desc_r.rq_desc_mem.attr;
                rq_cc_tlp_header.dw0[16] = header_sel_r ? tph_present_slot_r[1] : tph_present_slot_r[0];
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_mem.ep;
                rq_cc_tlp_header.dw0[11:10] = rq_desc_r.rq_desc_mem.at;
                rq_cc_tlp_header.dw0[9:0] = rq_desc_r.rq_desc_mem.dword_count[9:0];
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = ((req_type_r == 4'd1) & rq_cc_tlp_header.dw0[16]) ? // tph
                                        (header_sel_r ? tph_st_tag_slot_r[15:8] : tph_st_tag_slot_r[7:0]) : rq_desc_r.rq_desc_mem.tag;
                rq_cc_tlp_header.dw1[7:0] = ((req_type_r != 4'd1) & rq_cc_tlp_header.dw0[16]) ? // tph
                                       (header_sel_r ? tph_st_tag_slot_r[15:8] : tph_st_tag_slot_r[7:0]) :
                                       (header_sel_r ? {last_be_slot_r[7:4], first_be_slot_r[7:4]} : {last_be_slot_r[3:0], first_be_slot_r[3:0]});
                // dw2, dw3
                {rq_cc_tlp_header.dw2, rq_cc_tlp_header.dw3} = header_4dw_c ? {rq_desc_r.rq_desc_mem.addr[63:2], header_sel_r ? tph_type_slot_r[3:2] : tph_type_slot_r[1:0]} :
                                                    {rq_desc_r.rq_desc_mem.addr[31:2], header_sel_r ? tph_type_slot_r[3:2] : tph_type_slot_r[1:0], 32'b0};
            end
            4'd2, 4'd3: begin// io
                header_4dw_c = 0;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_mem.force_ecrc;
                // dw0
                case (req_type_r)
                    4'd2: rq_cc_tlp_header.dw0[31:24] = 8'b000_00010;
                    4'd3: rq_cc_tlp_header.dw0[31:24] = 8'b010_00010;
                endcase
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_mem.ep;
                rq_cc_tlp_header.dw0[9:0] = 1;
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = rq_desc_r.rq_desc_mem.tag;
                rq_cc_tlp_header.dw1[7:0] = {4'b0, header_sel_r ? first_be_slot_r[7:4] : first_be_slot_r[3:0]};
                // dw2, dw3
                {rq_cc_tlp_header.dw2, rq_cc_tlp_header.dw3} = {rq_desc_r.rq_desc_mem.addr[31:2], 2'b0, 32'b0};
            end
            4'd8, 4'd9, 4'd10, 4'd11: begin// cfg
                header_4dw_c = 0;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_cfg.force_ecrc;
                // dw0
                case (req_type_r)
                    4'd8:  rq_cc_tlp_header.dw0[31:24] = 8'b000_00100;
                    4'd9:  rq_cc_tlp_header.dw0[31:24] = 8'b000_00101;
                    4'd10: rq_cc_tlp_header.dw0[31:24] = 8'b010_00100;
                    4'd11: rq_cc_tlp_header.dw0[31:24] = 8'b010_00101;
                endcase
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_cfg.ep;
                rq_cc_tlp_header.dw0[9:0] = 1;
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = rq_desc_r.rq_desc_cfg.tag;
                rq_cc_tlp_header.dw1[7:0] = {4'b0, header_sel_r ? first_be_slot_r[7:4] : first_be_slot_r[3:0]};
                // dw2
                rq_cc_tlp_header.dw2[31:16]  = rq_desc_r.rq_desc_cfg.cpl_id;
                rq_cc_tlp_header.dw2[11:8]  = rq_desc_r.rq_desc_cfg.ext_reg;
                rq_cc_tlp_header.dw2[7:2]  = rq_desc_r.rq_desc_cfg.reg_num;
            end
            4'd12: begin// msg
                header_4dw_c = 1;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_msg.force_ecrc;
                // dw0
                rq_cc_tlp_header.dw0[31] = 0;
                rq_cc_tlp_header.dw0[29] = 1;
                rq_cc_tlp_header.dw0[28:24] = {2'b10, rq_desc_r.rq_desc_msg.msg_routing};
                rq_cc_tlp_header.dw0[22:20] = rq_desc_r.rq_desc_msg.tc;
                rq_cc_tlp_header.dw0[18] = rq_desc_r.rq_desc_msg.attr[2];
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_msg.ep;
                rq_cc_tlp_header.dw0[9:0] = rq_desc_r.rq_desc_msg.dword_count[9:0];
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = rq_desc_r.rq_desc_msg.tag;
                rq_cc_tlp_header.dw1[7:0] = rq_desc_r.rq_desc_msg.msg_code;
                case (rq_desc_r.rq_desc_msg.msg_code)
                    8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27: begin// intx
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b100;
                        // if (ari_cap)
                        //     rq_cc_tlp_header.dw1[23:16] = 0;
                        // else
                        //     rq_cc_tlp_header.dw1[18:16] = 0;
                    end
                    8'h14, 8'h18, 8'h19, 8'h1b: begin// pme
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // case (rq_desc_r.rq_desc_msg.msg_code)
                        //     8'h14: rq_cc_tlp_header.dw0[26:24] = 3'b100;
                        //     8'h18: rq_cc_tlp_header.dw0[26:24] = 3'b000;
                        //     8'h19: rq_cc_tlp_header.dw0[26:24] = 3'b011;
                        //     8'h1b: rq_cc_tlp_header.dw0[26:24] = 3'b101;
                        // endcase
                    end
                    8'h30, 8'h31, 8'h33: begin// error
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b000;
                    end
                    8'h00: begin// unlock
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b011;
                        // if (ari_cap)
                        //     rq_cc_tlp_header.dw1[23:16] = 0;
                        // else
                        //     rq_cc_tlp_header.dw1[18:16] = 0;
                    end
                    8'h50: begin// sspl
                        rq_cc_tlp_header.dw0[30] = 1;
                        // rq_cc_tlp_header.dw0[9:0] = 1;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b100;
                    end
                    8'h10: begin// ltr
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b100;
                        rq_cc_tlp_header.dw3 = {rq_desc_r.rq_desc_msg.no_snoop_latency, rq_desc_r.rq_desc_msg.snoop_latency};
                    end
                    8'h12: begin// obff
                        rq_cc_tlp_header.dw0[30] = 0;
                        // rq_cc_tlp_header.dw0[9:0] = 0;
                        // rq_cc_tlp_header.dw0[22:20] = 0;
                        // rq_cc_tlp_header.dw0[26:24] = 3'b100;
                        rq_cc_tlp_header.dw3[3:0] = rq_desc_r.rq_desc_msg.obff_code;
                    end
                endcase
            end
            4'd13: begin// vd msg
                header_4dw_c = 1;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_vd_msg.force_ecrc;
                // dw0
                rq_cc_tlp_header.dw0[31] = 0;
                rq_cc_tlp_header.dw0[30] = (rq_desc_r.rq_desc_vd_msg.dword_count == 0) ? 0 : 1;
                rq_cc_tlp_header.dw0[29] = 1;
                rq_cc_tlp_header.dw0[28:24] = {2'b10, rq_desc_r.rq_desc_vd_msg.msg_routing};
                rq_cc_tlp_header.dw0[22:20] = rq_desc_r.rq_desc_vd_msg.tc;
                {rq_cc_tlp_header.dw0[18], rq_cc_tlp_header.dw0[13:12]} = rq_desc_r.rq_desc_vd_msg.attr;
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_vd_msg.ep;
                rq_cc_tlp_header.dw0[9:0] = rq_desc_r.rq_desc_vd_msg.dword_count[9:0];
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = rq_desc_r.rq_desc_vd_msg.tag;
                rq_cc_tlp_header.dw1[7:0] = rq_desc_r.rq_desc_vd_msg.msg_code;
                // dw2
                rq_cc_tlp_header.dw2[31:16] = rq_desc_r.rq_desc_vd_msg.dest_id;
                rq_cc_tlp_header.dw2[15:0] = rq_desc_r.rq_desc_vd_msg.vdr_id;
                // dw3
                rq_cc_tlp_header.dw3 = rq_desc_r.rq_desc_vd_msg.vdr_hdr_bytes;
            end
            4'd14: begin// ats msg
                header_4dw_c = 1;
                rq_cc_force_ecrc = rq_desc_r.rq_desc_ats_msg.force_ecrc;
                // dw0
                rq_cc_tlp_header.dw0[31:28] = 3'b001;
                rq_cc_tlp_header.dw0[28:24] = {2'b10, rq_desc_r.rq_desc_ats_msg.msg_routing};
                rq_cc_tlp_header.dw0[22:20] = rq_desc_r.rq_desc_ats_msg.tc;
                {rq_cc_tlp_header.dw0[18], rq_cc_tlp_header.dw0[13:12]} = rq_desc_r.rq_desc_ats_msg.attr;
                rq_cc_tlp_header.dw0[14] = rq_desc_r.rq_desc_ats_msg.ep;
                rq_cc_tlp_header.dw0[9:0] = rq_desc_r.rq_desc_ats_msg.dword_count[9:0];
                // dw1
                rq_cc_tlp_header.dw1[31:16] = rq_desc_r.rq_desc_mem.req_id_en ? rq_desc_r.rq_desc_mem.req_id :
                                             (ari_cap ? {bus_num, rq_desc_r.rq_desc_mem.req_id[7:0]} : {bus_num, dev_num, rq_desc_r.rq_desc_mem.req_id[2:0]});
                rq_cc_tlp_header.dw1[15:8] = rq_desc_r.rq_desc_ats_msg.tag;
                rq_cc_tlp_header.dw1[7:0] = rq_desc_r.rq_desc_ats_msg.msg_code;
                // dw2, dw3
                {rq_cc_tlp_header.dw3, rq_cc_tlp_header.dw2} = rq_desc_r.rq_desc_ats_msg.tl_hdr_bytes;
            end
            4'd15: begin// reserved
                rq_cc_tlp_header = 0;
            end
        endcase
    end else begin
        rq_cc_force_ecrc = cc_desc_r.force_ecrc;
        header_4dw_c = 0;
        // dw0
        case ({(cc_desc_r.dword_count != 0), cc_desc_r.locked})
            2'b00: rq_cc_tlp_header.dw0[31:24] = {8'b000_01010};
            2'b10: rq_cc_tlp_header.dw0[31:24] = {8'b010_01010};
            2'b01: rq_cc_tlp_header.dw0[31:24] = {8'b000_01011};
            2'b11: rq_cc_tlp_header.dw0[31:24] = {8'b010_01011};
        endcase
        rq_cc_tlp_header.dw0[22:20] = cc_desc_r.tc;
        {rq_cc_tlp_header.dw0[18], rq_cc_tlp_header.dw0[13:12]} = cc_desc_r.attr;
        rq_cc_tlp_header.dw0[14] = cc_desc_r.ep;
        rq_cc_tlp_header.dw0[11:10] = cc_desc_r.at;
        rq_cc_tlp_header.dw0[9:0] = cc_desc_r.dword_count[9:0];
        // dw1
        rq_cc_tlp_header.dw1[31:16] = cc_desc_r.cpl_id_en ? cc_desc_r.cpl_id :
                                     (ari_cap ? {bus_num, cc_desc_r.cpl_id[7:0]} : {bus_num, dev_num, cc_desc_r.cpl_id[2:0]});
        rq_cc_tlp_header.dw1[15:13] = cc_desc_r.cpl_status;
        rq_cc_tlp_header.dw1[11:0] = cc_desc_r.byte_count[11:0];
        // dw2
        rq_cc_tlp_header.dw2[31:16] = cc_desc_r.req_id;
        rq_cc_tlp_header.dw2[15:8] = cc_desc_r.tag;
        rq_cc_tlp_header.dw2[6:0] = cc_desc_r.addr;
    end
end

always_ff @(posedge user_clk) begin
    if (header_update_c) begin
        if (rq_cc_straddle_c) begin
            if (rq_cc_is_rq_c)
                payload_offset_r <= header_sel_c ? 12 : 4;
            else
                payload_offset_r <= header_sel_c ? 11 : 3;
        end else begin
            if (rq_cc_is_rq_c) begin
                if (RQ_DWORD_ALIGN)
                    payload_offset_r <= ((DATA_WIDTH == 64) | (DATA_WIDTH == 128)) ? 0 : 4;
                else begin
                    if (DATA_WIDTH == 512)
                        payload_offset_r <= 4 + rq_cc_tuser512_c.addr_offset[1:0];
                    else
                        payload_offset_r <= rq_cc_tuser512_c.addr_offset[2:0];
                end
            end else begin
                if (CC_DWORD_ALIGN)
                    payload_offset_r <= (DATA_WIDTH == 64) ? 1 : 3;
                else
                    payload_offset_r <= (DATA_WIDTH == 512) ? (4 + cc_desc_nxt_c.addr[3:2]) : cc_desc_nxt_c.addr[4:2];
            end
        end
    end
end

assign busy = ~sm_idle_r;

endmodule
