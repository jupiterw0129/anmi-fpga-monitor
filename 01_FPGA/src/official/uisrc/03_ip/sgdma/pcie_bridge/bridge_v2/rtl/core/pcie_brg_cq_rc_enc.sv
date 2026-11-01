`include "pcie_brg_def.svh"

module pcie_brg_cq_rc_enc#(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter CQ_DWORD_ALIGN = 1,
    parameter RC_DWORD_ALIGN = 1,
    parameter CQ_STRADDLE = 0,
    parameter RC_STRADDLE = 0,
    parameter CFG_PF_NUM = 4,
    parameter CORE_PF_NUM = 4,

    parameter KEEP_WIDTH = DATA_WIDTH/32,
    parameter DW_WIDTH = $clog2(KEEP_WIDTH)
) (
    input  logic user_clk,
    input  logic user_rst,

    input  logic cq_rc_tlp_vld,
    output logic cq_rc_tlp_rdy,
    input  logic cq_rc_tlp_header_vld,
    output logic cq_rc_tlp_header_rdy,
    input  pcie_tlp_header_t cq_rc_tlp_header,
    input  logic [47:0] cq_rc_tlp_bardec,
    input  logic [CORE_PF_NUM+7:0] cq_rc_tlp_mchit,
    input  logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid,
    input  logic cq_rc_tlp_is_cq,
    input  logic cq_rc_tlp_is_np,
    input  logic cq_rc_tlp_eop,
    input  logic [9-DW_WIDTH:0] cq_rc_tlp_cycle_m1,
    output logic cq_rc_tlp_data_rd,
    output logic cq_rc_tlp_data_rd_eop,
    input  logic [DATA_WIDTH-1:0] cq_rc_tlp_data,
    input  logic cq_rc_tlp_discontinue,
    output logic cq_rc_np_mask,

    input  logic cq_rc_tready,
    output logic cq_rc_tvalid,
    output logic cq_rc_tlast,
    output pcie_cq_tuser512_t cq_rc_tuser,
    output logic [KEEP_WIDTH-1:0] cq_rc_tkeep,
    output logic [DATA_WIDTH-1:0] cq_rc_tdata,
    output logic cq_rc_is_cq,
    input  logic [1:0] np_req,
    output logic [5:0] np_req_count,

    output logic busy
);

pcie_cq_tuser512_t cq_rc_tuser_int;
logic cq_rc_tlast_int;
logic [KEEP_WIDTH-1:0] cq_rc_tkeep_int;
logic [DATA_WIDTH-1:0] cq_rc_tdata_int;
logic cq_rc_is_cq_int;

logic [DATA_WIDTH-1:0] cq_rc_tdata_r_int;
logic [DATA_WIDTH-1:0] cq_rc_tdata_r1_int;
pcie_cq_tuser512_t cq_rc_tuser_dly0;
pcie_cq_tuser512_t cq_rc_tuser_dly1;
logic [1:0] cq_rc_tlast_dly;
logic [1:0] [KEEP_WIDTH-1:0] cq_rc_tkeep_dly;
logic [1:0] cq_rc_is_cq_dly;
logic cq_rc_tlp_data_rd_d1;

logic sm_idle_c, sm_header_half_c, sm_header_wait_c, sm_recv_c, sm_ext_c, sm_recv2_c;
logic sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_recv_r, sm_ext_r, sm_recv2_r;

pcie_tlp_header_t cq_rc_tlp_header_r;
pcie_tlp_header_t cq_rc_tlp_header_r1;
logic [47:0] cq_rc_tlp_bardec_r;
logic [CORE_PF_NUM+7:0] cq_rc_tlp_mchit_r;
logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid_r;
logic cq_rc_tlp_is_cq_r;
logic cq_rc_tlp_with_data_r;
logic cq_rc_tlp_with_data_r1;
logic cq_rc_tlp_eop_r;
logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid_r1;
logic cq_rc_tlp_header_mwr_r;
logic cq_rc_tlp_header_mwr_r1;
logic cq_rc_tlp_header_mrd_atomic_r;
logic cq_rc_tlp_header_mrd_atomic_r1;

logic [DATA_WIDTH-1:0] cq_rc_tlp_data_r;
logic [DATA_WIDTH-1:0] cq_rc_tlp_data_r1;
logic cq_rc_tlp_discontinue_r;

logic cq_rc_tlp_with_data_c;
logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid_c;
logic cq_rc_straddle;
logic cq_rc_dword_align;
logic cq_rc_tlp_end;
logic [DW_WIDTH-1:0] payload_offset;
logic [7:0] fmt_type;

logic recv_vld;
logic recv_rdy;
logic cq_rc_straddle_r;
logic cq_rc_dword_align_r;

logic recv_vld_d1;
logic recv_rdy_d1;
logic cq_rc_tlp_header_rdy_d1;
logic sm_idle_r1, sm_header_half_r1, sm_header_wait_r1, sm_recv_r1, sm_ext_r1, sm_recv2_r1;

logic [9-DW_WIDTH:0] cq_rc_cycle_counter_r;
logic cq_rc_end_c;
logic cq_rc_end_r;
logic cq_rc_end_c_async;
logic cq_rc_end_r_async;
logic [DW_WIDTH-1:0] payload_offset_nxt;
logic [DW_WIDTH-1:0] payload_offset_r;
logic [DW_WIDTH-1:0] payload_offset_r1;
logic cq_rc_tlp_sop;
logic recv2_straddle;
pcie_tlp_header_t tlp_header_r;
pcie_tlp_header_t tlp_header_r1;
logic [1:0] cq_rc_is_sop_nxt;
logic [1:0] cq_rc_is_sop_r;
logic [1:0] cq_rc_is_sop_r1;
logic [1:0] cq_rc_is_eop_nxt;
logic [1:0] cq_rc_is_eop_r;
logic [1:0] cq_rc_is_eop_r1;
logic cq_rc_is_sop_pld_nxt;
logic cq_rc_is_sop_pld_r;
logic cq_rc_is_sop_pld_r1;
logic cq_rc_is_sop_pld_sticky;
logic cq_rc_is_sop_pld_delay_nxt;
logic cq_rc_is_sop_pld_delay_r;
logic [KEEP_WIDTH-1:0] cq_rc_tkeep_r;
logic [KEEP_WIDTH-1:0] cq_rc_tkeep_r1;
logic [DATA_WIDTH/8-1:0] byte_en_r;
logic [DATA_WIDTH/8-1:0] byte_en_r1;
logic [3:0] eop_ptr_r;
logic [3:0] eop_ptr_r1;
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_sop_dword_align;// header + data
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_sop_addr_align;
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_eop_r;// data
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_middle_r;
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_middle_pld_r;
logic [KEEP_WIDTH*3-1:0] cq_rc_tlp_valid_middle_pld_r1;
logic [1:0] [1:0] cq_rc_is_sop_dly;
logic [1:0] [1:0] cq_rc_is_sop_r1_dly;
logic [1:0] cq_rc_tlp_is_cq_dly;

assign cq_rc_tuser_dly0 = cq_rc_tuser_int;
assign cq_rc_tlast_dly[0] = cq_rc_tlast_int;
assign cq_rc_tkeep_dly[0] = cq_rc_tkeep_int;
assign cq_rc_is_cq_dly[0] = cq_rc_is_cq_int;
assign cq_rc_tlp_with_data_c = cq_rc_tlp_valid[0];
assign cq_rc_tlp_valid_c = SYNC_CLOCK ? cq_rc_tlp_valid : (cq_rc_tlp_end ? cq_rc_tlp_valid : {KEEP_WIDTH{1'b1}});
assign cq_rc_straddle = cq_rc_tlp_is_cq ? CQ_STRADDLE : RC_STRADDLE;
assign cq_rc_dword_align = cq_rc_tlp_is_cq ? CQ_DWORD_ALIGN : RC_DWORD_ALIGN;
assign cq_rc_tlp_end = SYNC_CLOCK ? cq_rc_tlp_eop : (cq_rc_tlp_cycle_m1 == 0);
assign fmt_type = cq_rc_tlp_header.dw0[31:24];
assign cq_rc_end_c = SYNC_CLOCK ? cq_rc_tlp_eop : cq_rc_end_c_async;
assign cq_rc_end_r = SYNC_CLOCK ? cq_rc_tlp_eop_r : cq_rc_end_r_async;
assign recv2_straddle = ~cq_rc_tlp_discontinue_r & (cq_rc_tlp_is_cq == cq_rc_tlp_is_cq_r);
assign cq_rc_tlp_valid_sop_dword_align = (DATA_WIDTH == 64) ? (cq_rc_tlp_is_cq ? {cq_rc_tlp_valid, 2'b11} : {cq_rc_tlp_valid, 1'b1}):
                                                              (cq_rc_tlp_is_cq ? {cq_rc_tlp_valid, 4'b1111} : {cq_rc_tlp_valid, 3'b111});
assign cq_rc_tlp_valid_sop_addr_align = ({cq_rc_tlp_valid, {KEEP_WIDTH{1'b1}}} << payload_offset) >> KEEP_WIDTH;
assign cq_rc_tlp_valid_eop_r = ({cq_rc_tlp_valid, {KEEP_WIDTH{1'b1}}} << payload_offset_r) >> KEEP_WIDTH;
assign cq_rc_tlp_valid_middle_r = ({cq_rc_tlp_valid_r, (|cq_rc_is_sop_r) ? {KEEP_WIDTH{1'b1}} : cq_rc_tlp_valid_r1} << payload_offset_r) >> KEEP_WIDTH;
assign cq_rc_tlp_valid_middle_pld_r = ({cq_rc_tlp_valid_r, (|cq_rc_is_sop_r) ? {KEEP_WIDTH{1'b0}} : cq_rc_tlp_valid_r1} << payload_offset_r) >> KEEP_WIDTH;
assign cq_rc_tlp_valid_middle_pld_r1 = (cq_rc_tlp_valid_r1 << payload_offset_r1) >> KEEP_WIDTH;
assign cq_rc_is_sop_dly[0] = cq_rc_is_sop_r;
assign cq_rc_is_sop_r1_dly[0] = cq_rc_is_sop_r1;
assign cq_rc_tlp_is_cq_dly[0] = cq_rc_tlp_is_cq_r;

// this signal is used in address align mode
always_comb begin
    payload_offset = 0;
    if (DATA_WIDTH == 512) begin
        if (cq_rc_tlp_is_cq) begin
            payload_offset = 4;
            case (fmt_type)
                8'b010_00000, 8'b010_00010: begin// mwr, iowr, 32bit address
                    payload_offset = 4 + cq_rc_tlp_header.dw2[3:2];
                end
                8'b011_00000: begin// mwr, 64bit address
                    payload_offset = 4 + cq_rc_tlp_header.dw3[3:2];
                end
            endcase
        end else begin
            payload_offset = 4 + cq_rc_tlp_header.dw2[3:2];
        end
    end else begin
        if (cq_rc_tlp_is_cq) begin
            case (fmt_type)
                8'b010_00000, 8'b010_00010: begin
                    payload_offset = cq_rc_tlp_header.dw2[4:2];
                end
                8'b011_00000: begin
                    payload_offset = cq_rc_tlp_header.dw3[4:2];
                end
            endcase
        end else begin
            payload_offset = cq_rc_tlp_header.dw2[4:2];
        end
    end
end

always_comb begin
    payload_offset_nxt = 0;
    if (cq_rc_dword_align) begin
        if (sm_recv2_r & recv2_straddle)
            payload_offset_nxt = cq_rc_tlp_is_cq ? 12 : 11;
        else if (DATA_WIDTH == 64)
            payload_offset_nxt = cq_rc_tlp_is_cq ? 0 : 1;
        else if (DATA_WIDTH == 128)
            payload_offset_nxt = cq_rc_tlp_is_cq ? 0 : 3;
        else
            payload_offset_nxt = cq_rc_tlp_is_cq ? 4 : 3;
    end else begin
        payload_offset_nxt = payload_offset;
    end
end

always_ff @(posedge user_clk) begin
    cq_rc_tuser_dly1 <= cq_rc_tuser_dly0;
    cq_rc_tlast_dly[1] <= cq_rc_tlast_dly[0];
    cq_rc_tkeep_dly[1] <= cq_rc_tkeep_dly[0];
    cq_rc_is_cq_dly[1] <= cq_rc_is_cq_dly[0];
    cq_rc_is_sop_dly[1] <= cq_rc_is_sop_dly[0];
    cq_rc_is_sop_r1_dly[1] <= cq_rc_is_sop_r1_dly[0];
    cq_rc_tlp_is_cq_dly[1] <= cq_rc_tlp_is_cq_dly[0];
    cq_rc_tlp_data_rd_d1 <= cq_rc_tlp_data_rd;
end

always_ff @(posedge user_clk) begin
    if (SYNC_CLOCK) begin
        cq_rc_end_c_async <= 0;
        cq_rc_end_r_async <= 0;
        cq_rc_cycle_counter_r <= 0;
    end else begin
        if (cq_rc_tlp_header_vld & cq_rc_tlp_header_rdy) begin
            cq_rc_end_c_async <= cq_rc_tlp_cycle_m1 == 1;
            cq_rc_end_r_async <= cq_rc_tlp_cycle_m1 == 0;
            cq_rc_cycle_counter_r <= cq_rc_tlp_cycle_m1;
        end else if (cq_rc_tlp_data_rd) begin
            cq_rc_end_c_async <= cq_rc_cycle_counter_r == 1;
            cq_rc_end_r_async <= cq_rc_cycle_counter_r == 0;
            cq_rc_cycle_counter_r <= cq_rc_cycle_counter_r - 1;
        end
    end
end

always_ff @(posedge user_clk) begin
    if (SYNC_CLOCK) begin
        if (user_rst)
            cq_rc_tlp_sop <= 1;
        else if (cq_rc_tlp_vld & cq_rc_tlp_rdy)
            cq_rc_tlp_sop <= cq_rc_tlp_eop;
    end else begin
        cq_rc_tlp_sop <= 0;
    end
end

always_ff @(posedge user_clk) begin
    recv_vld_d1 <= recv_vld;
    recv_rdy_d1 <= recv_rdy;
    cq_rc_tlp_header_rdy_d1 <= cq_rc_tlp_header_rdy;
    {sm_idle_r1, sm_header_half_r1, sm_header_wait_r1, sm_recv_r1, sm_ext_r1, sm_recv2_r1} <= {sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_recv_r, sm_ext_r, sm_recv2_r};
end

always_ff @(posedge user_clk) begin
    if (SYNC_CLOCK ? (cq_rc_tlp_vld & cq_rc_tlp_rdy & cq_rc_tlp_sop) : (cq_rc_tlp_header_vld & cq_rc_tlp_header_rdy)) begin
        payload_offset_r <= payload_offset_nxt;
        cq_rc_straddle_r <= cq_rc_straddle;
        cq_rc_dword_align_r <= cq_rc_dword_align;

        cq_rc_tlp_header_r <= cq_rc_tlp_header;
        cq_rc_tlp_header_r1 <= cq_rc_tlp_header_r;
        cq_rc_tlp_bardec_r <= cq_rc_tlp_bardec;
        cq_rc_tlp_mchit_r <= cq_rc_tlp_mchit;
        cq_rc_tlp_is_cq_r <= cq_rc_tlp_is_cq;
        cq_rc_tlp_discontinue_r <= cq_rc_tlp_discontinue;
        cq_rc_tlp_header_mwr_r <= (cq_rc_tlp_header.dw0[31:24] == 8'h40) | (cq_rc_tlp_header.dw0[31:24] == 8'h60);
        cq_rc_tlp_header_mwr_r1 <= cq_rc_tlp_header_mwr_r;
        cq_rc_tlp_header_mrd_atomic_r <= (cq_rc_tlp_header.dw0[31:24] == 8'h4c) | (cq_rc_tlp_header.dw0[31:24] == 8'h6c) | (cq_rc_tlp_header.dw0[31:24] == 8'h4d) | (cq_rc_tlp_header.dw0[31:24] == 8'h6d) | (cq_rc_tlp_header.dw0[31:24] == 8'h4e) | (cq_rc_tlp_header.dw0[31:24] == 8'h6e);
        cq_rc_tlp_header_mrd_atomic_r1 <= cq_rc_tlp_header_mrd_atomic_r;
    end
    if (SYNC_CLOCK) begin
        if (cq_rc_tlp_rdy) begin
            cq_rc_tlp_valid_r <= cq_rc_tlp_valid_c;
            cq_rc_tlp_with_data_r <= cq_rc_tlp_with_data_c;
            cq_rc_tlp_eop_r <= cq_rc_tlp_eop;
            cq_rc_tlp_data_r <= cq_rc_tlp_data;
        end else if (recv_rdy & recv_vld & ~(sm_header_half_r | sm_header_wait_r)) begin
            cq_rc_tlp_valid_r <= 0;
        end
        if (recv_rdy) begin
            cq_rc_tlp_valid_r1 <= cq_rc_tlp_valid_r;
            cq_rc_tlp_with_data_r1 <= cq_rc_tlp_with_data_r;
            cq_rc_tlp_data_r1 <= cq_rc_tlp_data_r;
            cq_rc_is_sop_r1 <= cq_rc_is_sop_r;
            cq_rc_is_eop_r1 <= cq_rc_is_eop_r;
            cq_rc_is_sop_pld_r1 <= cq_rc_is_sop_pld_r;
            payload_offset_r1 <= payload_offset_r;
        end
    end else begin
        cq_rc_tlp_eop_r <= 0;
        cq_rc_tlp_data_r <= 0;
        if (cq_rc_tlp_header_rdy) begin
            cq_rc_tlp_with_data_r <= cq_rc_tlp_with_data_c;
        end
        if (cq_rc_tlp_header_rdy | cq_rc_tlp_data_rd) begin
            cq_rc_tlp_valid_r <= cq_rc_tlp_valid_c;
        end else if (recv_rdy_d1 & recv_vld_d1 & ~(sm_header_half_r1 | sm_header_wait_r1)) begin
            cq_rc_tlp_valid_r <= 0;
        end
        if (recv_rdy_d1) begin
            cq_rc_tlp_valid_r1 <= cq_rc_tlp_valid_r;
            cq_rc_tlp_data_r1 <= cq_rc_tlp_data_r;
            cq_rc_is_sop_r1 <= cq_rc_is_sop_r;
            cq_rc_is_eop_r1 <= cq_rc_is_eop_r;
            cq_rc_is_sop_pld_r1 <= cq_rc_is_sop_pld_r;
        end
        if (cq_rc_tlp_header_rdy_d1) begin
            cq_rc_tlp_with_data_r1 <= cq_rc_tlp_with_data_r;
        end
    end
end

always_ff @(posedge user_clk) begin
    cq_rc_is_sop_r <= cq_rc_is_sop_nxt;
    cq_rc_is_eop_r <= cq_rc_is_eop_nxt;
    cq_rc_is_sop_pld_r <= cq_rc_is_sop_pld_nxt;
    cq_rc_is_sop_pld_delay_r <= cq_rc_is_sop_pld_delay_nxt;
end

always_ff @(posedge user_clk) begin
    if (user_rst)
        {sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_recv_r, sm_ext_r, sm_recv2_r} <= 6'b100000;
    else
        {sm_idle_r, sm_header_half_r, sm_header_wait_r, sm_recv_r, sm_ext_r, sm_recv2_r} <= {sm_idle_c, sm_header_half_c, sm_header_wait_c, sm_recv_c, sm_ext_c, sm_recv2_c};
end

always_comb begin
    sm_idle_c = sm_idle_r;
    sm_header_half_c = sm_header_half_r;
    sm_header_wait_c = sm_header_wait_r;
    sm_recv_c = sm_recv_r;
    sm_ext_c = sm_ext_r;
    sm_recv2_c = sm_recv2_r;
    cq_rc_is_sop_nxt = cq_rc_is_sop_r;
    cq_rc_is_eop_nxt = cq_rc_is_eop_r;
    cq_rc_is_sop_pld_nxt = cq_rc_is_sop_pld_r;
    cq_rc_is_sop_pld_delay_nxt = cq_rc_is_sop_pld_delay_r;
    cq_rc_tlp_header_rdy = 0;
    cq_rc_tlp_data_rd = 0;
    cq_rc_tlp_data_rd_eop = 0;
    unique case (1)
        sm_idle_r: begin
            if (SYNC_CLOCK ? cq_rc_tlp_vld : cq_rc_tlp_header_vld) begin
                sm_idle_c = 0;
            end
            // new tlp come in, is copied to other state
            //----------------copy begin----------------
            if (SYNC_CLOCK ? cq_rc_tlp_vld : cq_rc_tlp_header_vld) begin
                cq_rc_is_sop_nxt = 2'b01;
                cq_rc_is_eop_nxt = 2'b00;
                cq_rc_is_sop_pld_nxt = 1;
                cq_rc_is_sop_pld_delay_nxt = 0;
                cq_rc_tlp_header_rdy = SYNC_CLOCK ? 0 : 1;
                cq_rc_tlp_data_rd = SYNC_CLOCK ? 0 : cq_rc_tlp_with_data_c;
                cq_rc_tlp_data_rd_eop = SYNC_CLOCK ? 0 : cq_rc_tlp_end;
                if (cq_rc_straddle) begin
                    if (cq_rc_tlp_end) begin
                        if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else if (~cq_rc_tlp_valid_sop_dword_align[16]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b10;
                        end else begin
                            sm_recv2_c = 1;
                        end
                    end else
                        sm_recv_c = 1;
                end else if (DATA_WIDTH == 64) begin
                    sm_header_half_c = 1;
                    cq_rc_is_sop_pld_nxt = 0;
                    cq_rc_tlp_data_rd = 0;
                end else if (DATA_WIDTH == 128) begin
                    if (cq_rc_dword_align) begin
                        if (cq_rc_tlp_end) begin
                            if (~cq_rc_tlp_valid_sop_dword_align[4]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b01;
                            end else begin
                                sm_ext_c = 1;
                            end
                            if (cq_rc_tlp_is_cq) begin
                                cq_rc_tlp_data_rd = 0;
                            end
                        end else begin
                            sm_recv_c = 1;
                        end
                        cq_rc_is_sop_pld_nxt = ~cq_rc_tlp_is_cq;
                        cq_rc_is_sop_pld_delay_nxt = cq_rc_tlp_is_cq;
                    end else begin
                        if (cq_rc_tlp_end & ~cq_rc_tlp_with_data_c) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_header_wait_c = 1;
                        end
                        cq_rc_is_sop_pld_nxt = 0;
                        cq_rc_is_sop_pld_delay_nxt = 1;
                        cq_rc_tlp_data_rd = 0;
                    end
                end else if (DATA_WIDTH == 256) begin
                    if (cq_rc_dword_align) begin
                        if (cq_rc_tlp_end) begin
                            if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b01;
                            end else begin
                                sm_ext_c = 1;
                            end
                        end else
                            sm_recv_c = 1;
                    end else begin
                        if (cq_rc_tlp_end & ~cq_rc_tlp_with_data_c) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_header_wait_c = 1;
                            cq_rc_is_sop_pld_nxt = 0;
                        end
                        cq_rc_tlp_data_rd = 0;
                    end
                end else if (DATA_WIDTH == 512) begin
                    if (cq_rc_dword_align) begin
                        if (cq_rc_tlp_end) begin
                            if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b01;
                            end else if (~cq_rc_tlp_valid_sop_dword_align[16]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b10;
                            end else begin
                                sm_ext_c = 1;
                            end
                        end else
                            sm_recv_c = 1;
                    end else begin
                        if (cq_rc_tlp_end) begin
                            if (~cq_rc_tlp_valid_sop_addr_align[8]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b01;
                            end else if (~cq_rc_tlp_valid_sop_addr_align[16]) begin
                                sm_recv_c = 1;
                                cq_rc_is_eop_nxt = 2'b10;
                            end else begin
                                sm_ext_c = 1;
                            end
                        end else
                            sm_recv_c = 1;
                    end
                end
            end else begin
                sm_idle_c = 1;
            end
            //----------------copy end----------------
        end
        sm_header_half_r: begin
            if (recv_rdy) begin
                sm_header_half_c = 0;
                cq_rc_is_sop_nxt = 2'b00;
                cq_rc_is_sop_pld_nxt = 0;
                cq_rc_tlp_data_rd_eop = SYNC_CLOCK ? 0 : cq_rc_end_c_async;
                if (cq_rc_dword_align) begin
                    if (cq_rc_tlp_end) begin
                        if (~cq_rc_tlp_valid_sop_dword_align[2]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_ext_c = 1;
                        end
                    end else begin
                        sm_recv_c = 1;
                    end
                    cq_rc_is_sop_pld_nxt = ~cq_rc_tlp_is_cq;
                    cq_rc_is_sop_pld_delay_nxt = cq_rc_tlp_is_cq;
                    cq_rc_tlp_data_rd = SYNC_CLOCK ? 0 : (cq_rc_tlp_is_cq ? 0 : cq_rc_tlp_valid_sop_dword_align[1]);
                end else begin
                    if (cq_rc_tlp_end & ~cq_rc_tlp_with_data_c) begin
                        sm_recv_c = 1;
                        cq_rc_is_eop_nxt = 2'b01;
                    end else begin
                        sm_header_wait_c = 1;
                    end
                    cq_rc_is_sop_pld_nxt = 0;
                    cq_rc_is_sop_pld_delay_nxt = 1;
                end
            end
        end
        sm_header_wait_r: begin
            if (recv_rdy) begin
                sm_header_wait_c = 0;
                sm_recv_c = 1;
                cq_rc_is_sop_nxt = 2'b00;
                cq_rc_is_eop_nxt = cq_rc_end_r ? 2'b01 : 2'b00;
                cq_rc_is_sop_pld_nxt = 1;
            end
        end
        sm_recv_r: begin
            if (recv_rdy) begin
                sm_recv_c = 0;
                cq_rc_is_sop_nxt = 2'b00;
                cq_rc_is_sop_pld_nxt = cq_rc_is_sop_pld_delay_r;
                cq_rc_tlp_data_rd = 1;
                cq_rc_tlp_data_rd_eop = SYNC_CLOCK ? 0 : cq_rc_end_c_async;
                if (cq_rc_end_r) begin
                    cq_rc_tlp_data_rd = 0;
                    //----------------copy begin----------------
                    if (SYNC_CLOCK ? cq_rc_tlp_vld : cq_rc_tlp_header_vld) begin
                        cq_rc_is_sop_nxt = 2'b01;
                        cq_rc_is_eop_nxt = 2'b00;
                        cq_rc_is_sop_pld_nxt = 1;
                        cq_rc_is_sop_pld_delay_nxt = 0;
                        cq_rc_tlp_header_rdy = SYNC_CLOCK ? 0 : 1;
                        cq_rc_tlp_data_rd = SYNC_CLOCK ? 0 : cq_rc_tlp_with_data_c;
                        cq_rc_tlp_data_rd_eop = SYNC_CLOCK ? 0 : cq_rc_tlp_end;
                        if (cq_rc_straddle) begin
                            if (cq_rc_tlp_end) begin
                                if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                                    sm_recv_c = 1;
                                    cq_rc_is_eop_nxt = 2'b01;
                                end else if (~cq_rc_tlp_valid_sop_dword_align[16]) begin
                                    sm_recv_c = 1;
                                    cq_rc_is_eop_nxt = 2'b10;
                                end else begin
                                    sm_recv2_c = 1;
                                end
                            end else
                                sm_recv_c = 1;
                        end else if (DATA_WIDTH == 64) begin
                            sm_header_half_c = 1;
                            cq_rc_is_sop_pld_nxt = 0;
                            cq_rc_tlp_data_rd = 0;
                        end else if (DATA_WIDTH == 128) begin
                            if (cq_rc_dword_align) begin
                                if (cq_rc_tlp_end) begin
                                    if (~cq_rc_tlp_valid_sop_dword_align[4]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b01;
                                    end else begin
                                        sm_ext_c = 1;
                                    end
                                    if (cq_rc_tlp_is_cq) begin
                                        cq_rc_tlp_data_rd = 0;
                                    end
                                end else begin
                                    sm_recv_c = 1;
                                end
                                cq_rc_is_sop_pld_nxt = ~cq_rc_tlp_is_cq;
                                cq_rc_is_sop_pld_delay_nxt = cq_rc_tlp_is_cq;
                            end else begin
                                if (cq_rc_tlp_end & ~cq_rc_tlp_with_data_c) begin
                                    sm_recv_c = 1;
                                    cq_rc_is_eop_nxt = 2'b01;
                                end else begin
                                    sm_header_wait_c = 1;
                                end
                                cq_rc_is_sop_pld_nxt = 0;
                                cq_rc_is_sop_pld_delay_nxt = 1;
                                cq_rc_tlp_data_rd = 0;
                            end
                        end else if (DATA_WIDTH == 256) begin
                            if (cq_rc_dword_align) begin
                                if (cq_rc_tlp_end) begin
                                    if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b01;
                                    end else begin
                                        sm_ext_c = 1;
                                    end
                                end else
                                    sm_recv_c = 1;
                            end else begin
                                if (cq_rc_tlp_end & ~cq_rc_tlp_with_data_c) begin
                                    sm_recv_c = 1;
                                    cq_rc_is_eop_nxt = 2'b01;
                                end else begin
                                    sm_header_wait_c = 1;
                                    cq_rc_is_sop_pld_nxt = 0;
                                end
                                cq_rc_tlp_data_rd = 0;
                            end
                        end else if (DATA_WIDTH == 512) begin
                            if (cq_rc_dword_align) begin
                                if (cq_rc_tlp_end) begin
                                    if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b01;
                                    end else if (~cq_rc_tlp_valid_sop_dword_align[16]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b10;
                                    end else begin
                                        sm_ext_c = 1;
                                    end
                                end else
                                    sm_recv_c = 1;
                            end else begin
                                if (cq_rc_tlp_end) begin
                                    if (~cq_rc_tlp_valid_sop_addr_align[8]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b01;
                                    end else if (~cq_rc_tlp_valid_sop_addr_align[16]) begin
                                        sm_recv_c = 1;
                                        cq_rc_is_eop_nxt = 2'b10;
                                    end else begin
                                        sm_ext_c = 1;
                                    end
                                end else
                                    sm_recv_c = 1;
                            end
                        end
                    end else begin
                        sm_idle_c = 1;
                    end
                    //----------------copy end----------------
                end else if (cq_rc_end_c) begin
                    if (DATA_WIDTH == 64) begin
                        if (~cq_rc_tlp_valid_eop_r[2]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_ext_c = 1;
                        end
                    end else if (DATA_WIDTH == 128) begin
                        if (~cq_rc_tlp_valid_eop_r[4]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_ext_c = 1;
                        end
                    end else if (DATA_WIDTH == 256) begin
                        if (~cq_rc_tlp_valid_eop_r[8]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_ext_c = 1;
                        end
                    end else if (DATA_WIDTH == 512) begin
                        if (~cq_rc_tlp_valid_eop_r[8]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else if (~cq_rc_tlp_valid_eop_r[16]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b10;
                        end else if (~cq_rc_tlp_valid_eop_r[24]) begin
                            if (cq_rc_straddle_r)
                                sm_recv2_c = 1;
                            else
                                sm_ext_c = 1;
                        end else begin
                            sm_ext_c = 1;
                        end
                    end
                end else begin
                    sm_recv_c = 1;
                end
            end
        end
        sm_ext_r: begin
            if (recv_rdy) begin
                sm_ext_c = 0;
                cq_rc_is_sop_nxt = 2'b00;
                cq_rc_is_sop_pld_nxt = cq_rc_is_sop_pld_delay_r;
                if (~cq_rc_tlp_valid_middle_r[8]) begin
                    sm_recv_c = 1;
                    cq_rc_is_eop_nxt = 2'b01;
                end else begin
                    sm_recv_c = 1;
                    cq_rc_is_eop_nxt = 2'b10;
                end
            end
        end
        sm_recv2_r: begin// straddle
            if (recv_rdy) begin
                sm_recv2_c = 0;
                cq_rc_is_sop_nxt = 2'b00;
                cq_rc_tlp_data_rd = 0;
                if ((SYNC_CLOCK ? cq_rc_tlp_vld : cq_rc_tlp_header_vld) & recv2_straddle) begin
                    cq_rc_is_sop_nxt = 2'b10;
                    cq_rc_is_sop_pld_nxt = 1;
                    cq_rc_tlp_header_rdy = SYNC_CLOCK ? 0 : 1;
                    cq_rc_tlp_data_rd = SYNC_CLOCK ? 0 : cq_rc_tlp_with_data_c;
                    cq_rc_tlp_data_rd_eop = SYNC_CLOCK ? 0 : cq_rc_end_c_async;
                    if (cq_rc_tlp_end) begin
                        if (~cq_rc_tlp_valid_sop_dword_align[8]) begin
                            sm_recv_c = 1;
                            cq_rc_is_eop_nxt = 2'b11;
                        end else if (~cq_rc_tlp_valid_sop_dword_align[16]) begin
                            sm_recv2_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end else begin
                            sm_ext_c = 1;
                            cq_rc_is_eop_nxt = 2'b01;
                        end
                    end else begin
                        sm_recv_c = 1;
                    end
                end else begin
                    if (~cq_rc_tlp_valid_middle_r[8]) begin
                        sm_idle_c = 1;
                        cq_rc_is_eop_nxt = 2'b01;
                    end else begin
                        sm_idle_c = 1;
                        cq_rc_is_eop_nxt = 2'b10;
                    end
                end
            end
        end
    endcase
end

logic tlp_with_data_r;
logic tlp_header_4dw_r;
logic tlp_header_4dw_r1;
logic [7:0] fmt_type_r;
logic [7:0] fmt_type_r1;
pcie_cq_desc_t cq_desc_c;
pcie_rc_desc_t rc_desc_c;
logic [7:0] msg_code_r;
logic [10:0] dword_count_r;
logic fmt_type_mrd_r;
logic fmt_type_mrd_r1;
logic fmt_type_mwr_r;
logic fmt_type_mwr_r1;
logic fmt_type_atomic_r;
logic fmt_type_atomic_r1;
logic tlp_header_mwr_r;
logic tlp_header_mwr_r1;
logic tlp_header_mrd_atomic_r;
logic tlp_header_mrd_atomic_r1;
logic [DATA_WIDTH*2-1:0] cq_rc_tdata_concat_int;
logic cq_rc_tdata_straddle;
logic [1:0] cq_rc_eop_pld;
logic [3:0] first_be_r;// FIXME rc
logic [3:0] first_be_r1;
logic [3:0] last_be_r;// FIXME rc
logic [3:0] last_be_r1;
logic byte_en_vld_r;
pcie_cq_desc_t cq_desc_dly0;
pcie_cq_desc_t cq_desc_dly1;
pcie_rc_desc_t rc_desc_dly0;
pcie_rc_desc_t rc_desc_dly1;
logic [1:0] [DW_WIDTH-1:0] payload_offset_dly;
logic cq_rc_tlp_is_cq_int;
logic cq_rc_dword_align_int;
logic [1:0] cq_rc_is_sop_r_int;
logic [1:0] cq_rc_is_sop_r1_int;// only use in 64b
pcie_cq_desc_t cq_desc_int;
pcie_rc_desc_t rc_desc_int;
logic [DW_WIDTH-1:0] payload_offset_int;
logic [DATA_WIDTH-1:0] cq_rc_tlp_data_int;
logic [9:0] rc_length_m1_r;
logic [11:0] rc_byte_count_m1_r;
logic [11:0] rc_byte_offset_r;

assign recv_vld = sm_header_half_r | sm_header_wait_r | sm_recv_r | sm_ext_r | sm_recv2_r;
assign cq_rc_tlp_rdy = SYNC_CLOCK ? (sm_idle_r | (sm_recv2_r & recv_rdy & recv2_straddle) | (sm_recv_r & recv_rdy)) : 0;
assign cq_rc_tlast_int = ~cq_rc_straddle_r & sm_recv_r & cq_rc_end_r;
assign cq_rc_tkeep_int = cq_rc_straddle_r ? {KEEP_WIDTH{1'b1}} : cq_rc_tkeep_r;
assign cq_rc_is_cq_int = cq_rc_tlp_is_cq_r;
assign tlp_header_r = cq_rc_tlp_header_r;
assign tlp_header_r1 = cq_rc_tlp_header_r1;
assign tlp_with_data_r = tlp_header_r.dw0[30];
assign tlp_header_4dw_r = tlp_header_r.dw0[29];
assign tlp_header_4dw_r1 = tlp_header_r1.dw0[29];
assign fmt_type_r = tlp_header_r.dw0[31:24];
assign fmt_type_r1 = tlp_header_r1.dw0[31:24];
assign msg_code_r = cq_rc_tlp_header_r.dw1[7:0];
assign dword_count_r = {(tlp_with_data_r & (tlp_header_r.dw0[9:0] == 0)), tlp_header_r.dw0[9:0]};
assign fmt_type_mrd_r = (fmt_type_r == 8'h00) | (fmt_type_r == 8'h20) | (fmt_type_r == 8'h01) | (fmt_type_r == 8'h21);
assign fmt_type_mrd_r1 = (fmt_type_r == 8'h00) | (fmt_type_r == 8'h20) | (fmt_type_r == 8'h01) | (fmt_type_r == 8'h21);
assign fmt_type_mwr_r = (fmt_type_r == 8'h40) | (fmt_type_r == 8'h60);
assign fmt_type_mwr_r1 = (fmt_type_r1 == 8'h40) | (fmt_type_r1 == 8'h60);
assign fmt_type_atomic_r = (fmt_type_r == 8'h4c) | (fmt_type_r == 8'h6c) | (fmt_type_r == 8'h4d) | (fmt_type_r == 8'h6d) | (fmt_type_r == 8'h4e) | (fmt_type_r == 8'h6e);
assign fmt_type_atomic_r1 = (fmt_type_r1 == 8'h4c) | (fmt_type_r1 == 8'h6c) | (fmt_type_r1 == 8'h4d) | (fmt_type_r1 == 8'h6d) | (fmt_type_r1 == 8'h4e) | (fmt_type_r1 == 8'h6e);
assign tlp_header_mwr_r = fmt_type_mwr_r;
assign tlp_header_mwr_r1 = fmt_type_mwr_r1;
assign tlp_header_mrd_atomic_r = fmt_type_mrd_r | fmt_type_atomic_r;
assign tlp_header_mrd_atomic_r1 = fmt_type_mrd_r1 | fmt_type_atomic_r1;
assign byte_en_vld_r = cq_rc_is_sop_pld_r | (~cq_rc_is_sop_r & cq_rc_is_sop_pld_sticky);
assign cq_desc_dly0 = cq_desc_c;
assign rc_desc_dly0 = rc_desc_c;
assign payload_offset_dly[0] = payload_offset_r;
assign cq_rc_tlp_is_cq_int = SYNC_CLOCK ? cq_rc_tlp_is_cq_dly[0] : cq_rc_tlp_is_cq_dly[1];
assign cq_rc_dword_align_int = cq_rc_tlp_is_cq_int ? CQ_DWORD_ALIGN : RC_DWORD_ALIGN;
assign cq_rc_is_sop_r_int = SYNC_CLOCK ? cq_rc_is_sop_dly[0] : cq_rc_is_sop_dly[1];
assign cq_rc_is_sop_r1_int = SYNC_CLOCK ? cq_rc_is_sop_r1_dly[0] : cq_rc_is_sop_r1_dly[1];
assign cq_desc_int = SYNC_CLOCK ? cq_desc_dly0 : cq_desc_dly1;
assign rc_desc_int = SYNC_CLOCK ? rc_desc_dly0 : rc_desc_dly1;
assign payload_offset_int = SYNC_CLOCK ? payload_offset_r : payload_offset_dly[1];
assign cq_rc_tlp_data_int = SYNC_CLOCK ? cq_rc_tlp_data_r : cq_rc_tlp_data;
assign rc_length_m1_r = tlp_header_r.dw0[9:0]-1;
assign rc_byte_count_m1_r = tlp_header_r.dw1[11:0]-1;
assign rc_byte_offset_r = tlp_header_r.dw2[1:0] + rc_byte_count_m1_r;

always_comb begin
    cq_rc_tkeep_r = 0;
    unique case (1)
        sm_idle_r: cq_rc_tkeep_r = 0;
        sm_header_half_r: cq_rc_tkeep_r = 'h3;
        sm_header_wait_r: cq_rc_tkeep_r = (DATA_WIDTH == 64) ? (cq_rc_tlp_is_cq_r ? 'h3 : 'h1) : (cq_rc_tlp_is_cq_r ? 'hf : 'h7);
        sm_recv_r: cq_rc_tkeep_r = cq_rc_tlp_valid_middle_r;
        sm_ext_r: cq_rc_tkeep_r = cq_rc_tlp_valid_middle_r;
        sm_recv2_r: cq_rc_tkeep_r = cq_rc_tlp_valid_middle_r;
    endcase
end

always_comb begin
    cq_rc_tkeep_r1 = cq_rc_tlp_valid_middle_pld_r1;
end

integer i0;
always_comb begin
    eop_ptr_r = 0;
    for (i0=0; i0<KEEP_WIDTH; i0=i0+1) begin
        if (cq_rc_tkeep_r[i0])
            eop_ptr_r = i0;
    end
end

integer i1;
always_comb begin
    eop_ptr_r1 = 0;
    for (i1=0; i1<KEEP_WIDTH; i1=i1+1) begin
        if (cq_rc_tkeep_r1[i1])
            eop_ptr_r1 = i1;
    end
end

integer i2;
always_comb begin
    byte_en_r = 0;
    if (byte_en_vld_r) begin
        for (i2=0; i2<KEEP_WIDTH; i2=i2+1) begin
            if (cq_rc_tlp_valid_middle_pld_r[i2]) begin// middle
                byte_en_r[i2*4+:4] = 4'hf;
            end else begin
                byte_en_r[i2*4+:4] = 4'h0;
            end
            if ((cq_rc_is_sop_r[1] ? cq_rc_is_eop_r[1] : |cq_rc_is_eop_r)) begin// eop
                if (i2 == KEEP_WIDTH-1) begin
                    if (cq_rc_tlp_valid_middle_pld_r[i2])
                        byte_en_r[i2*4+:4] = last_be_r;
                end else begin
                    if (cq_rc_tlp_valid_middle_pld_r[i2] & ~cq_rc_tlp_valid_middle_pld_r[i2+1])
                        byte_en_r[i2*4+:4] = last_be_r;
                end
            end
            if (cq_rc_is_sop_pld_r) begin// sop
                if (i2 == 0) begin
                    if (cq_rc_tlp_valid_middle_pld_r[i2])
                        byte_en_r[i2*4+:4] = first_be_r;
                end else begin
                    if (cq_rc_tlp_valid_middle_pld_r[i2] & ~cq_rc_tlp_valid_middle_pld_r[i2-1])
                        byte_en_r[i2*4+:4] = first_be_r;
                end
            end
        end
    end
end

integer i3;
always_comb begin
    byte_en_r1 = 0;
    for (i3=0; i3<KEEP_WIDTH; i3=i3+1) begin
        if (cq_rc_tlp_valid_middle_pld_r1[i3]) begin// middle
            byte_en_r1[i3*4+:4] = 4'hf;
        end else begin
            byte_en_r1[i3*4+:4] = 4'h0;
        end
        if (1) begin// eop
            if (i3 == KEEP_WIDTH-1) begin
                if (cq_rc_tlp_valid_middle_pld_r1[i3])
                    byte_en_r1[i3*4+:4] = last_be_r1;
            end else begin
                if (cq_rc_tlp_valid_middle_pld_r1[i3] & ~cq_rc_tlp_valid_middle_pld_r1[i3+1])
                    byte_en_r1[i3*4+:4] = last_be_r1;
            end
        end
        if (cq_rc_is_sop_pld_r1) begin// sop
            if (i3 == 0) begin
                if (cq_rc_tlp_valid_middle_pld_r1[i3])
                    byte_en_r1[i3*4+:4] = first_be_r1;
            end else begin
                if (cq_rc_tlp_valid_middle_pld_r1[i3] & ~cq_rc_tlp_valid_middle_pld_r1[i3-1])
                    byte_en_r1[i3*4+:4] = first_be_r1;
            end
        end
    end
end

always_comb begin
    first_be_r = 4'hf;
    last_be_r = 4'hf;
    if (tlp_header_mwr_r | tlp_header_mrd_atomic_r) begin
        first_be_r = tlp_header_r.dw1[3:0];
        last_be_r = tlp_header_r.dw1[7:4];
    end
end

always_comb begin
    first_be_r1 = 4'hf;
    last_be_r1 = 4'hf;
    if (tlp_header_mwr_r1 | tlp_header_mrd_atomic_r1) begin
        first_be_r1 = tlp_header_r1.dw1[3:0];
        last_be_r1 = tlp_header_r1.dw1[7:4];
    end
end

always_comb begin
    cq_rc_tdata_concat_int = 0;
    if (DATA_WIDTH == 64) begin
        if (cq_rc_is_sop_r1_int[0]) begin
            if (cq_rc_tlp_is_cq_int)
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_desc_int[127:64]};
            else
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, rc_desc_int[95:64], 32'b0};
        end else begin
            cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_rc_tlp_data_r1};
        end
    end else if (DATA_WIDTH == 128) begin
        if (cq_rc_is_sop_r_int[0]) begin
            if (cq_rc_tlp_is_cq_int)
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_desc_int};
            else
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, rc_desc_int, 32'b0};
        end else begin
            cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_rc_tlp_data_r1};
        end
    end else if (DATA_WIDTH == 256) begin
        if (cq_rc_is_sop_r_int[0]) begin
            if (cq_rc_tlp_is_cq_int)
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_desc_int, 128'b0};
            else
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, rc_desc_int, 160'b0};
        end else begin
            cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_rc_tlp_data_r1};
        end
    end else if (DATA_WIDTH == 512) begin
        if (|cq_rc_is_sop_r_int) begin
            if (cq_rc_dword_align_int)
                cq_rc_tdata_concat_int = cq_rc_tlp_is_cq_int ? {cq_rc_tlp_data_int, cq_desc_int, 384'b0} : {cq_rc_tlp_data_int, rc_desc_int, 416'b0};
            else
                cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, 512'b0};
        end else begin
            cq_rc_tdata_concat_int = {cq_rc_tlp_data_int, cq_rc_tlp_data_r1};
        end
    end
end

always_comb begin
    cq_rc_tdata_r_int = 0;
    if (DATA_WIDTH == 64) begin
        if (cq_rc_is_sop_r_int[0]) begin
            cq_rc_tdata_r_int = cq_rc_tlp_is_cq_int ? cq_desc_int[63:0] : rc_desc_int[63:0];
        end else begin
            if (cq_rc_is_sop_r1_int[0] & ~cq_rc_dword_align_int)
                cq_rc_tdata_r_int = cq_rc_tlp_is_cq_int ? cq_desc_int[127:64] : rc_desc_int[95:64];
            else
                cq_rc_tdata_r_int = (cq_rc_tdata_concat_int << {payload_offset_int, 5'b0}) >> DATA_WIDTH;
        end
    end else if ((DATA_WIDTH == 128) | (DATA_WIDTH == 256)) begin
        if (cq_rc_is_sop_r_int[0] & ~cq_rc_dword_align_int)
            cq_rc_tdata_r_int = cq_rc_tlp_is_cq_int ? cq_desc_int : rc_desc_int;
        else
            cq_rc_tdata_r_int = (cq_rc_tdata_concat_int << {payload_offset_int, 5'b0}) >> DATA_WIDTH;
    end else if (DATA_WIDTH == 512) begin
        if (|cq_rc_is_sop_r_int & ~cq_rc_dword_align_int) begin
            if (cq_rc_tlp_is_cq_int)
                cq_rc_tdata_r_int = ((cq_rc_tdata_concat_int << {payload_offset_int, 5'b0}) >> DATA_WIDTH) | cq_desc_int;
            else
                cq_rc_tdata_r_int = ((cq_rc_tdata_concat_int << {payload_offset_int, 5'b0}) >> DATA_WIDTH) | rc_desc_int;
        end else begin
            cq_rc_tdata_r_int = (cq_rc_tdata_concat_int << {payload_offset_int, 5'b0}) >> DATA_WIDTH;
        end
    end
end

always_comb begin
    cq_rc_tdata_r1_int = (cq_rc_tlp_data_r1 << {payload_offset_r1, 5'b0}) >> DATA_WIDTH;
end

always_comb begin
    if ((DATA_WIDTH == 512) & cq_rc_is_sop_r[1])// straddle
        cq_rc_tdata_int = {cq_rc_tdata_r_int[DATA_WIDTH-1:DATA_WIDTH/2], cq_rc_tdata_r1_int[DATA_WIDTH/2-1:0]};
    else
        cq_rc_tdata_int = cq_rc_tdata_r_int;
end

always_comb begin
    cq_rc_tuser_int = 0;
    cq_rc_tuser_int.is_sop[0] = |cq_rc_is_sop_r;
    cq_rc_tuser_int.is_sop[1] = &cq_rc_is_sop_r;
    cq_rc_tuser_int.is_eop[0] = |cq_rc_is_eop_r;
    cq_rc_tuser_int.is_eop[1] = &cq_rc_is_eop_r;
    cq_rc_tuser_int.discontinue = cq_rc_tlp_discontinue_r;
    cq_rc_tuser_int.is_sop0_ptr = cq_rc_is_sop_r[0] ? 2'b00 : 2'b10;
    cq_rc_tuser_int.is_sop1_ptr = 2'b10;
    cq_rc_tuser_int.is_eop0_ptr = cq_rc_is_sop_r[1] ? eop_ptr_r1 : eop_ptr_r;
    cq_rc_tuser_int.is_eop1_ptr = eop_ptr_r;
    cq_rc_tuser_int.byte_en = cq_rc_is_sop_r[1] ? {byte_en_r[DATA_WIDTH/8-1:DATA_WIDTH/8/2], byte_en_r1[DATA_WIDTH/8/2-1:0]} : byte_en_r;
    if (cq_rc_is_sop_r[1]) begin// straddle
        if (tlp_header_mwr_r1 | tlp_header_mrd_atomic_r1) begin
            cq_rc_tuser_int.first_be[3:0] = tlp_header_r1.dw1[3:0];
            cq_rc_tuser_int.last_be[3:0] = tlp_header_r1.dw1[7:4];
            cq_rc_tuser_int.tph_present[0] = tlp_header_r1.dw0[16];
            cq_rc_tuser_int.tph_type[1:0] = tlp_header_4dw_r1 ? tlp_header_r1.dw3[1:0] : tlp_header_r1.dw2[1:0];
            cq_rc_tuser_int.tph_st_tag[7:0] = tlp_header_mwr_r1 ? tlp_header_r1.dw1[15:8] : tlp_header_r1.dw1[7:0];
        end else begin
            cq_rc_tuser_int.first_be[3:0] = 4'hf;
            cq_rc_tuser_int.last_be[3:0] = cq_rc_tlp_with_data_r1 ? 4'hf : 4'h0;
        end
        if (tlp_header_mwr_r | tlp_header_mrd_atomic_r) begin
            cq_rc_tuser_int.first_be[7:4] = tlp_header_r.dw1[3:0];
            cq_rc_tuser_int.last_be[7:4] = tlp_header_r.dw1[7:4];
            cq_rc_tuser_int.tph_present[1] = tlp_header_r.dw0[16];
            cq_rc_tuser_int.tph_type[3:2] = tlp_header_4dw_r ? tlp_header_r.dw3[1:0] : tlp_header_r.dw2[1:0];
            cq_rc_tuser_int.tph_st_tag[15:8] = tlp_header_mwr_r ? tlp_header_r.dw1[15:8] : tlp_header_r.dw1[7:0];
        end else begin
            cq_rc_tuser_int.first_be[7:4] = 4'hf;
            cq_rc_tuser_int.last_be[7:4] = cq_rc_tlp_with_data_r ? 4'hf : 4'h0;
        end
    end else begin
        if (tlp_header_mwr_r | tlp_header_mrd_atomic_r) begin
            cq_rc_tuser_int.first_be[3:0] = tlp_header_r.dw1[3:0];
            cq_rc_tuser_int.last_be[3:0] = tlp_header_r.dw1[7:4];
            cq_rc_tuser_int.tph_present[0] = tlp_header_r.dw0[16];
            cq_rc_tuser_int.tph_type[1:0] = tlp_header_4dw_r ? tlp_header_r.dw3[1:0] : tlp_header_r.dw2[1:0];
            cq_rc_tuser_int.tph_st_tag[7:0] = tlp_header_mwr_r ? tlp_header_r.dw1[15:8] : tlp_header_r.dw1[7:0];
        end else begin
            cq_rc_tuser_int.first_be[3:0] = 4'hf;
            cq_rc_tuser_int.last_be[3:0] = cq_rc_tlp_with_data_r ? 4'hf : 4'h0;
        end
    end
end

always_comb begin
    cq_desc_c = 0;
    rc_desc_c = 0;
    // cq
    if ((fmt_type_r[7:3] == 5'b001_10) | (fmt_type_r[7:3] == 5'b011_10)) begin// msg
        case (msg_code_r)
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,// intx
            8'h14, 8'h18, 8'h19, 8'h1b,// pme
            8'h30, 8'h31, 8'h33,// error
            8'h00,// unlock
            8'h50,// sspl
            8'h10,// ltr
            8'h12: // obff
            begin// msg
                if (msg_code_r == 8'h10)
                    {cq_desc_c.cq_desc_msg.no_snoop_latency, cq_desc_c.cq_desc_msg.snoop_latency} = tlp_header_r.dw3;
                if (msg_code_r == 8'h12)
                    cq_desc_c.cq_desc_msg.obff_code = tlp_header_r.dw3[3:0];
                cq_desc_c.cq_desc_msg.dword_count = dword_count_r;
                cq_desc_c.cq_desc_msg.req_type = 4'd12;
                cq_desc_c.cq_desc_msg.req_id = tlp_header_r.dw1[31:16];
                cq_desc_c.cq_desc_msg.tag = tlp_header_r.dw1[15:8];
                cq_desc_c.cq_desc_msg.msg_code = tlp_header_r.dw1[7:0];
                cq_desc_c.cq_desc_msg.msg_routing = fmt_type_r[2:0];
                cq_desc_c.cq_desc_msg.tc = tlp_header_r.dw0[22:20];
                cq_desc_c.cq_desc_msg.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
            end
            8'h7e, 8'h7f: begin// vd_msg
                cq_desc_c.cq_desc_vd_msg.dest_id = tlp_header_r.dw2[31:16];
                cq_desc_c.cq_desc_vd_msg.vdr_id = tlp_header_r.dw2[15:0];
                cq_desc_c.cq_desc_vd_msg.vdr_hdr_bytes = tlp_header_r.dw3;
                cq_desc_c.cq_desc_vd_msg.dword_count = dword_count_r;
                cq_desc_c.cq_desc_vd_msg.req_type = 4'd13;
                cq_desc_c.cq_desc_vd_msg.req_id = tlp_header_r.dw1[31:16];
                cq_desc_c.cq_desc_vd_msg.tag = tlp_header_r.dw1[15:8];
                cq_desc_c.cq_desc_vd_msg.msg_code = tlp_header_r.dw1[7:0];
                cq_desc_c.cq_desc_vd_msg.msg_routing = fmt_type_r[2:0];
                cq_desc_c.cq_desc_vd_msg.tc = tlp_header_r.dw0[22:20];
                cq_desc_c.cq_desc_vd_msg.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
            end
            8'h01, 8'h02, 8'h04, 8'h05: begin// ats:invld req, invld cpl, page req, prg resp
                cq_desc_c.cq_desc_ats_msg.tl_hdr_bytes = {tlp_header_r.dw3, tlp_header_r.dw2};
                cq_desc_c.cq_desc_ats_msg.dword_count = dword_count_r;
                cq_desc_c.cq_desc_ats_msg.req_type = 4'd14;
                cq_desc_c.cq_desc_ats_msg.req_id = tlp_header_r.dw1[31:16];
                cq_desc_c.cq_desc_ats_msg.tag = tlp_header_r.dw1[15:8];
                cq_desc_c.cq_desc_ats_msg.msg_code = tlp_header_r.dw1[7:0];
                cq_desc_c.cq_desc_ats_msg.msg_routing = fmt_type_r[2:0];
                cq_desc_c.cq_desc_ats_msg.tc = tlp_header_r.dw0[22:20];
                cq_desc_c.cq_desc_ats_msg.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
            end
        endcase
    end else begin
        case (fmt_type_r)
            8'h00, 8'h20, 8'h40, 8'h60, 8'h01, 8'h21, 8'h02, 8'h42, 8'h4c, 8'h6c, 8'h4d, 8'h6d, 8'h4e, 8'h6e: begin// mem, locked, io, atomic
                cq_desc_c.cq_desc_mem.at = tlp_header_r.dw0[11:10];
                cq_desc_c.cq_desc_mem.addr = tlp_header_4dw_r ? {tlp_header_r.dw2, tlp_header_r.dw3[31:2]} : tlp_header_r.dw2[31:2];
                cq_desc_c.cq_desc_mem.dword_count = dword_count_r;
                case (fmt_type_r)
                    8'h00, 8'h20: cq_desc_c.cq_desc_mem.req_type = 4'd0;
                    8'h40, 8'h60: cq_desc_c.cq_desc_mem.req_type = 4'd1;
                    8'h02       : cq_desc_c.cq_desc_mem.req_type = 4'd2;
                    8'h42       : cq_desc_c.cq_desc_mem.req_type = 4'd3;
                    8'h01, 8'h21: cq_desc_c.cq_desc_mem.req_type = 4'd7;
                    8'h4c, 8'h6c: cq_desc_c.cq_desc_mem.req_type = 4'd4;
                    8'h4d, 8'h6d: cq_desc_c.cq_desc_mem.req_type = 4'd5;
                    8'h4e, 8'h6e: cq_desc_c.cq_desc_mem.req_type = 4'd6;
                endcase
                cq_desc_c.cq_desc_mem.req_id = tlp_header_r.dw1[31:16];
                cq_desc_c.cq_desc_mem.tag = tlp_header_r.dw1[15:8];
                cq_desc_c.cq_desc_mem.tgt_func = cq_rc_tlp_bardec_r[31] ? cq_rc_tlp_bardec_r[23:16] : (cq_rc_tlp_bardec_r[23:16] + CFG_PF_NUM);
                begin
                    if (cq_rc_tlp_bardec_r[0]) cq_desc_c.cq_desc_mem.bar_id = 0;
                    else if (cq_rc_tlp_bardec_r[1]) cq_desc_c.cq_desc_mem.bar_id = 1;
                    if (cq_rc_tlp_bardec_r[2]) cq_desc_c.cq_desc_mem.bar_id = 2;
                    else if (cq_rc_tlp_bardec_r[3]) cq_desc_c.cq_desc_mem.bar_id = 3;
                    if (cq_rc_tlp_bardec_r[4]) cq_desc_c.cq_desc_mem.bar_id = 4;
                    else if (cq_rc_tlp_bardec_r[5]) cq_desc_c.cq_desc_mem.bar_id = 5;
                    if (cq_rc_tlp_bardec_r[6]) cq_desc_c.cq_desc_mem.bar_id = 6;
                end
                cq_desc_c.cq_desc_mem.bar_apt = 0;// FIXME this signal can not get directly
                cq_desc_c.cq_desc_mem.tc = tlp_header_r.dw0[22:20];
                cq_desc_c.cq_desc_mem.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
            end
            8'h04, 8'h44, 8'h05, 8'h45: begin// cfg
                cq_desc_c.cq_desc_cfg.reg_num = tlp_header_r.dw2[7:2];
                cq_desc_c.cq_desc_cfg.ext_reg = tlp_header_r.dw2[11:8];
                cq_desc_c.cq_desc_cfg.dword_count = dword_count_r;
                case (fmt_type_r)
                    8'h04: cq_desc_c.cq_desc_cfg.req_type = 4'd8;
                    8'h44: cq_desc_c.cq_desc_cfg.req_type = 4'd9;
                    8'h05: cq_desc_c.cq_desc_cfg.req_type = 4'd10;
                    8'h45: cq_desc_c.cq_desc_cfg.req_type = 4'd11;
                endcase
                cq_desc_c.cq_desc_cfg.req_id = tlp_header_r.dw1[31:16];
                cq_desc_c.cq_desc_cfg.tag = tlp_header_r.dw1[15:8];
                cq_desc_c.cq_desc_cfg.cpl_id = tlp_header_r.dw2[31:16];
                cq_desc_c.cq_desc_cfg.tc = tlp_header_r.dw0[22:20];
                cq_desc_c.cq_desc_cfg.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
            end
        endcase
    end
    // rc
    rc_desc_c.addr = tlp_header_r.dw2[6:0];
    if (tlp_header_r.dw0[14]) begin
        rc_desc_c.err_code = 1;
    end else if (tlp_header_r.dw1[15:13] != 0) begin
        rc_desc_c.err_code = 2;
    end else if (~cq_rc_tlp_valid_r[0]) begin
        rc_desc_c.err_code = 3;
    end
    rc_desc_c.byte_count = {(tlp_header_r.dw1[11:0] == 0), tlp_header_r.dw1[11:0]};
    rc_desc_c.locked = fmt_type_r[0];
    rc_desc_c.req_cpl = rc_byte_offset_r[11:2] == rc_length_m1_r;
    rc_desc_c.dword_count = {(tlp_header_r.dw0[9:0] == 0), tlp_header_r.dw0[9:0]};
    rc_desc_c.cpl_status = tlp_header_r.dw1[15:13];
    rc_desc_c.ep = tlp_header_r.dw0[14];
    rc_desc_c.req_id = tlp_header_r.dw2[31:16];
    rc_desc_c.tag = tlp_header_r.dw2[15:8];
    rc_desc_c.cpl_id = tlp_header_r.dw1[31:16];
    rc_desc_c.tc = tlp_header_r.dw0[22:20];
    rc_desc_c.attr = {tlp_header_r.dw0[18], tlp_header_r.dw0[13:12]};
end

always_ff @(posedge user_clk) begin
    cq_desc_dly1 <= cq_desc_dly0;
    rc_desc_dly1 <= rc_desc_dly0;
    payload_offset_dly[1] <= payload_offset_dly[0];
end

always_ff @(posedge user_clk) begin
    if (cq_rc_is_sop_pld_r)
        cq_rc_is_sop_pld_sticky <= 1;
    else if (|cq_rc_is_sop_r)
        cq_rc_is_sop_pld_sticky <= 0;
end

localparam CQ_RC_FIFO_WIDTH = 1 + $bits(pcie_cq_tuser512_t) + KEEP_WIDTH + DATA_WIDTH + 1;

logic cq_rc_fifo_wr;
logic cq_rc_fifo_rd;
logic [CQ_RC_FIFO_WIDTH-1:0] cq_rc_fifo_wdata;
logic [CQ_RC_FIFO_WIDTH-1:0] cq_rc_fifo_rdata;
logic cq_rc_fifo_afull;
logic cq_rc_fifo_vld;

logic cq_rc_fifo_wdata_tlast;
pcie_cq_tuser512_t cq_rc_fifo_wdata_tuser;
logic [KEEP_WIDTH-1:0] cq_rc_fifo_wdata_tkeep;
logic [DATA_WIDTH-1:0] cq_rc_fifo_wdata_tdata;
logic cq_rc_fifo_wdata_is_cq;

pcie_brg_fifo #(
    .SYNC_CLOCK(1),
    .MEM_TYPE("dram"),
    .WIDTH(CQ_RC_FIFO_WIDTH),
    .DEPTH(16),
    .AFULL(12),
    .REG_OUT(0),
    .RD_PFCH(1)
) cq_rc_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(cq_rc_fifo_wr),
    .wdata(cq_rc_fifo_wdata),
    .full(),
    .afull(cq_rc_fifo_afull),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(cq_rc_fifo_rd),
    .rdata(cq_rc_fifo_rdata),
    .empty(),
    .vld(cq_rc_fifo_vld),
    .uflow()
);

logic [1:0] recv_dly;

assign recv_dly[0] = recv_vld & recv_rdy;
assign cq_rc_fifo_wr = SYNC_CLOCK ? recv_dly[0] : recv_dly[1];
assign recv_rdy = ~cq_rc_fifo_afull;
assign cq_rc_tvalid = cq_rc_fifo_vld;
assign cq_rc_fifo_rd = cq_rc_tvalid & cq_rc_tready;
assign cq_rc_fifo_wdata = {cq_rc_fifo_wdata_tlast, cq_rc_fifo_wdata_tuser, cq_rc_fifo_wdata_tkeep, cq_rc_fifo_wdata_tdata, cq_rc_fifo_wdata_is_cq};
assign {cq_rc_tlast, cq_rc_tuser, cq_rc_tkeep, cq_rc_tdata, cq_rc_is_cq} = cq_rc_fifo_rdata;

always_comb begin
    if (SYNC_CLOCK) begin
        cq_rc_fifo_wdata_tlast = cq_rc_tlast_dly[0];
        cq_rc_fifo_wdata_tuser = cq_rc_tuser_dly0;
        cq_rc_fifo_wdata_tkeep = cq_rc_tkeep_dly[0];
        cq_rc_fifo_wdata_tdata = cq_rc_tdata_int;
        cq_rc_fifo_wdata_is_cq = cq_rc_is_cq_dly[0];
    end else begin
        cq_rc_fifo_wdata_tlast = cq_rc_tlast_dly[1];
        cq_rc_fifo_wdata_tuser = cq_rc_tuser_dly1;
        cq_rc_fifo_wdata_tkeep = cq_rc_tkeep_dly[1];
        cq_rc_fifo_wdata_tdata = cq_rc_tdata_int;
        cq_rc_fifo_wdata_is_cq = cq_rc_is_cq_dly[1];
    end
end

always_ff @(posedge user_clk) begin
    recv_dly[1] <= recv_dly[0];
    if (user_rst) begin
        recv_dly[1] <= 0;
    end
end

// np req
logic pcie_np_dec;
logic [5:0] np_req_count_nxt;

assign np_req_count_nxt = (np_req_count + np_req[0] + ((DATA_WIDTH == 512) & np_req[1]) - pcie_np_dec);

always_ff @(posedge user_clk) begin
    if (user_rst)
        pcie_np_dec <= 0;
    else if (SYNC_CLOCK ? (cq_rc_tlp_vld & cq_rc_tlp_rdy & cq_rc_tlp_sop) : (cq_rc_tlp_header_vld & cq_rc_tlp_header_rdy))
        pcie_np_dec <= cq_rc_tlp_is_np;
end

always_ff @(posedge user_clk) begin
    if (user_rst) begin
        np_req_count <= 0;
        cq_rc_np_mask <= 1;
    end else begin
        np_req_count <= (np_req_count_nxt >= 32) ? 32 : np_req_count_nxt;
        cq_rc_np_mask <= np_req_count_nxt == 0;
    end
end

assign busy = ~sm_idle_r;

endmodule
