`include "pcie_brg_def.svh"

module pcie_brg_tx_enc#(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512
) (
    input  logic core_clk2,
    input  logic core_rst,
    // tlp header and data
    input  logic tlp_vld,
    output logic tlp_rdy,
    input  logic tlp_header_vld,
    output logic tlp_header_rdy,
    input  pcie_tlp_header_t tlp_header,
    input  logic tlp_force_ecrc,
    input  logic tlp_header_err,
    output logic tlp_data_rd,
    input  logic [DATA_WIDTH-1:0] tlp_data,
    input  logic tlp_data_discontinue,
    // core tx
    core_tl_tx_if.mst core_tl_tx,
    // credits
    output logic [95:0] core_tl_tx_credits,

    output logic busy
);

localparam KEEP_WIDTH = DATA_WIDTH/32;
localparam DW_WIDTH = $clog2(KEEP_WIDTH);

logic tx_rdy;
logic [10:0] tx_dw_m1_c;
logic [10:0] tx_dw_m1_r;
logic [10-DW_WIDTH:0] tx_cycle_m1_c;
logic [10-DW_WIDTH:0] tx_cycle_m1_r;
pcie_tlp_header_t tlp_header_c;
logic tlp_header_4dw_c;
logic tlp_with_data_c;
logic tlp_header_err_c;
logic tlp_force_ecrc_c;
logic tlp_header_td_c;
logic tlp_header_4dw_r;
logic tlp_with_data_r;
logic tlp_header_err_r;
logic tlp_force_ecrc_r;
logic tlp_header_td_r;
pcie_tlp_header_t tlp_header_r;
logic [9:0] tlp_data_len_m1_c;
logic [9-DW_WIDTH:0] tlp_data_cycle_m1_c;
logic [9-DW_WIDTH:0] tlp_data_cycle_m1_r;
logic tlp_rd_end_r;
logic tlp_rd_end_nxt;
logic tlp_data_rd_nxt;
logic tlp_end_c;
logic [9:0] tlp_data_len;

logic sm_header_c, sm_header2_c, sm_data_c;
logic sm_header_r, sm_header2_r, sm_data_r;

assign tx_dw_m1_c = (tlp_header_4dw_c ? 3 : 2) + (tlp_with_data_c ? {(tlp_data_len == 0), tlp_data_len[9:0]} : 0);
assign tx_cycle_m1_c = tx_dw_m1_c >> DW_WIDTH;
assign tlp_data_len_m1_c = tlp_data_len - 1;
assign tlp_data_cycle_m1_c = tlp_data_len_m1_c >> DW_WIDTH;
assign tlp_header_c = tlp_header;
assign tlp_header_4dw_c = tlp_header.dw0[29];
assign tlp_with_data_c = tlp_header.dw0[30];
assign tlp_header_err_c = tlp_header_err;
assign tlp_force_ecrc_c = tlp_force_ecrc;
assign tlp_header_td_c = tlp_header_c.dw0[15];
assign tlp_data_len = tlp_header_c.dw0[9:0];

always_ff @(posedge core_clk2) begin
    if (sm_header_r)
        tx_dw_m1_r <= tx_dw_m1_c;
end

always_ff @(posedge core_clk2) begin
    if (sm_header_r)
        tx_cycle_m1_r <= tx_cycle_m1_c;
    else if (tx_rdy)
        tx_cycle_m1_r <= tx_cycle_m1_r - 1;
end

always_ff @(posedge core_clk2) begin
    if (sm_header_r) begin
        tlp_header_r <= tlp_header_c;
        tlp_header_4dw_r <= tlp_header_4dw_c;
        tlp_with_data_r <= tlp_with_data_c;
        tlp_header_err_r <= tlp_header_err_c;
        tlp_force_ecrc_r <= tlp_force_ecrc_c;
        tlp_header_td_r <= tlp_header_td_c;
    end
end

always_ff @(posedge core_clk2) begin
    if (core_rst)
        tlp_data_rd <= 0;
    else
        tlp_data_rd <= SYNC_CLOCK ? 0 : tlp_data_rd_nxt;
end

always_ff @(posedge core_clk2) begin
    if (sm_header_r)
        tlp_rd_end_r <= (tlp_data_cycle_m1_c == 0) & tlp_data_rd_nxt;
    else begin
        if ((tlp_data_cycle_m1_r == 1) & tlp_data_rd_nxt)
            tlp_rd_end_r <= 1;
    end
end

always_ff @(posedge core_clk2) begin
    if (sm_header_r)
        tlp_data_cycle_m1_r <= tlp_data_cycle_m1_c;
    else if (tlp_data_rd_nxt)
        tlp_data_cycle_m1_r <= tlp_data_cycle_m1_r - 1;
end

always_ff @(posedge core_clk2) begin
    if (core_rst)
        {sm_header_r, sm_header2_r, sm_data_r} <= 3'b100;
    else
        {sm_header_r, sm_header2_r, sm_data_r} <= {sm_header_c, sm_header2_c, sm_data_c};
end

always_comb begin
    tlp_data_rd_nxt = 0;
    unique case (1)
        sm_header_r: begin
            if (DATA_WIDTH == 64)
                tlp_data_rd_nxt = 0;
            else if (DATA_WIDTH == 128)
                tlp_data_rd_nxt = (SYNC_CLOCK ? 1 : tlp_header_rdy) & tlp_with_data_c & ~tlp_header_4dw_c;
            else
                tlp_data_rd_nxt = (SYNC_CLOCK ? 1 : tlp_header_rdy) & tlp_with_data_c;
        end
        sm_header2_r: begin
            tlp_data_rd_nxt = tx_rdy & tlp_with_data_r & ~tlp_header_4dw_r;
        end
        sm_data_r: begin
            tlp_data_rd_nxt = tx_rdy & tlp_with_data_r & ~tlp_rd_end_r;
        end
    endcase
end

always_comb begin
    tlp_rdy = 0;
    if (SYNC_CLOCK) begin
        unique case (1)
            sm_header_r: tlp_rdy = tx_rdy;
            sm_header2_r: tlp_rdy = tx_rdy;
            sm_data_r: tlp_rdy = tx_rdy & ~tlp_rd_end_r;
        endcase
    end
end

always_comb begin
    if (sm_header_r)
        tlp_end_c = tx_cycle_m1_c == 0;
    else
        tlp_end_c = tx_cycle_m1_r == 1;
end

always_comb begin
    tlp_header_rdy = 0;
    sm_header_c = sm_header_r;
    sm_header2_c = sm_header2_r;
    sm_data_c = sm_data_r;
    unique case (1)
        sm_header_r: begin
            if (tx_rdy) begin
                if (SYNC_CLOCK ? tlp_vld : tlp_header_vld) begin
                    sm_header_c = 0;
                    if (DATA_WIDTH == 64) begin
                        sm_header2_c = 1;
                    end else begin
                        if (tx_cycle_m1_c == 0)
                            sm_header_c = 1;
                        else
                            sm_data_c = 1;
                    end
                end
                if (SYNC_CLOCK ? 0 : tlp_header_vld) begin
                    tlp_header_rdy = 1;
                end
            end
        end
        sm_header2_r: begin
            if (tx_rdy) begin
                sm_header2_c = 0;
                if (tx_cycle_m1_r == 1) begin
                    sm_header_c = 1;
                end else begin
                    sm_data_c = 1;
                end
            end
        end
        sm_data_r: begin
            if (tx_rdy) begin
                if (tx_cycle_m1_r == 1) begin
                    sm_data_c = 0;
                    sm_header_c = 1;
                end
            end
        end
    endcase
end

localparam TX_FIFO_WIDTH = 1+1+DATA_WIDTH+DATA_WIDTH/32+8;

logic tx_fifo_wr;
logic tx_fifo_rd;
logic [TX_FIFO_WIDTH-1:0] tx_fifo_wdata;
logic [TX_FIFO_WIDTH-1:0] tx_fifo_rdata;
logic tx_fifo_afull;
logic tx_fifo_vld;

logic tx_fifo_wdata_sop;
logic tx_fifo_wdata_eop;
logic [DATA_WIDTH-1:0] tx_fifo_wdata_data;
logic [KEEP_WIDTH-1:0] tx_fifo_wdata_valid;
logic [7:0] tx_fifo_wdata_err;
logic tx_fifo_rdata_sop;
logic tx_fifo_rdata_eop;
logic [DATA_WIDTH-1:0] tx_fifo_rdata_data;
logic [DATA_WIDTH/32-1:0] tx_fifo_rdata_valid;
logic [7:0] tx_fifo_rdata_err;

pcie_brg_fifo #(
    .SYNC_CLOCK(1),
    .MEM_TYPE("dram"),
    .WIDTH(TX_FIFO_WIDTH),
    .DEPTH(16),
    .AFULL(12),
    .REG_OUT(1),
    .RD_PFCH(1)
) tx_fifo(
    .wclk(core_clk2),
    .wrst(core_rst),
    .wr(tx_fifo_wr),
    .wdata(tx_fifo_wdata),
    .full(),
    .afull(tx_fifo_afull),
    .oflow(),
    .rclk(core_clk2),
    .rrst(core_rst),
    .rd(tx_fifo_rd),
    .rdata(tx_fifo_rdata),
    .empty(),
    .vld(tx_fifo_vld),
    .uflow()
);

logic [2:0] tx_dly;
logic [2:0] tx_header_dly;
logic [2:0] tx_header2_dly;
logic [2:0] tx_data_dly;
logic [2:0] tx_end_dly;
logic [2:0] [KEEP_WIDTH-1:0] tx_valid_dly;
logic [2:0] tlp_header_4dw_dly;
logic [2:0] tlp_with_data_dly;
logic [2:0] tlp_header_err_dly;
logic [2:0] tlp_force_ecrc_dly;
logic [2:0] tlp_header_td_dly;
logic [2:0] tlp_rd_end_r_dly;
pcie_tlp_header_t tlp_header_dly0;
pcie_tlp_header_t tlp_header_dly1;
pcie_tlp_header_t tlp_header_dly2;
logic [DATA_WIDTH-1:0] tx_data_pld;
logic [DATA_WIDTH-1:0] tx_data_pld_d1;
logic [DATA_WIDTH-1:0] tx_data_pld_rev;
logic [DATA_WIDTH-1:0] tx_data_pld_d1_rev;
logic tx_discontinue_c;
logic tx_discontinue_r;
logic tx_discontinue;
logic tx_force_ecrc;
logic [DW_WIDTH-1:0] tx_valid_dw_c;
logic tx_header_int;
logic tx_header2_int;
logic tx_data_int;
logic tlp_header_4dw_int;
pcie_tlp_header_t tlp_header_int;

assign tx_dly[0] = ((sm_header_r & (SYNC_CLOCK ? tlp_vld : tlp_header_vld)) | sm_header2_r | sm_data_r) & tx_rdy;
assign tx_header_dly[0] = sm_header_r;
assign tx_header2_dly[0] = sm_header2_r;
assign tx_data_dly[0] = sm_data_r;
assign tx_end_dly[0] = tlp_end_c;
assign tlp_header_4dw_dly[0] = sm_header_r ? tlp_header_4dw_c : tlp_header_4dw_r;
assign tlp_with_data_dly[0] = sm_header_r ? tlp_with_data_c : tlp_with_data_r;
assign tlp_header_err_dly[0] = sm_header_r ? tlp_header_err_c : tlp_header_err_r;
assign tlp_force_ecrc_dly[0] = sm_header_r ? tlp_force_ecrc_c : tlp_force_ecrc_r;
assign tlp_header_td_dly[0] = sm_header_r ? tlp_header_td_c : tlp_header_td_r;
assign tlp_rd_end_r_dly[0] = tlp_rd_end_r;
assign tlp_header_dly0 = sm_header_r ? tlp_header_c : tlp_header_r;
assign tx_valid_dw_c = tx_end_dly[0] ? (sm_header_r ? tx_dw_m1_c : tx_dw_m1_r) : {DW_WIDTH{1'b1}};
assign tx_header_int = SYNC_CLOCK ? tx_header_dly[0] : tx_header_dly[2];
assign tx_header2_int = SYNC_CLOCK ? tx_header2_dly[0] : tx_header2_dly[2];
assign tx_data_int = SYNC_CLOCK ? tx_data_dly[0] : tx_data_dly[2];
assign tlp_header_4dw_int = SYNC_CLOCK ? tlp_header_4dw_dly[0] : tlp_header_4dw_dly[2];
assign tlp_header_int = SYNC_CLOCK ? tlp_header_dly0 : tlp_header_dly2;

assign tx_data_pld = tlp_data;
assign tx_fifo_wdata = {tx_fifo_wdata_sop, tx_fifo_wdata_eop, tx_fifo_wdata_data, tx_fifo_wdata_valid, tx_fifo_wdata_err};
assign {tx_fifo_rdata_sop, tx_fifo_rdata_eop, tx_fifo_rdata_data, tx_fifo_rdata_valid, tx_fifo_rdata_err} = tx_fifo_rdata;
assign core_tl_tx.tx_sop = tx_fifo_rdata_sop & tx_fifo_vld;
assign core_tl_tx.tx_eop = tx_fifo_rdata_eop & tx_fifo_vld;
assign core_tl_tx.tx_data = tx_fifo_rdata_data;
assign core_tl_tx.tx_valid = tx_fifo_rdata_valid & {DATA_WIDTH/32{tx_fifo_vld}};
assign core_tl_tx.tx_err = tx_fifo_rdata_err & {8{tx_fifo_vld}};
assign core_tl_tx.tx_stream = 0;
assign core_tl_tx_credits = core_tl_tx.tx_credits;
assign tx_fifo_rd = tx_fifo_vld & ~core_tl_tx.tx_wait;

always_comb begin
    if (SYNC_CLOCK) begin
        tx_discontinue_c = tx_header_dly[0] ? (tlp_header_err_dly[0] | tlp_data_discontinue) : (tlp_data_discontinue & ~tlp_rd_end_r_dly[0]);
        tx_discontinue = tx_header_dly[0] ? tx_discontinue_c : (tx_discontinue_c | tx_discontinue_r);
        tx_force_ecrc = tx_header_dly[0] ? tlp_force_ecrc_dly[0] : 0;
        tx_fifo_wr = tx_dly[0];
        tx_fifo_wdata_sop = tx_header_dly[0];
        tx_fifo_wdata_eop = tx_end_dly[0];
        tx_fifo_wdata_valid = tx_valid_dly[0];
    end else begin
        tx_discontinue_c = tx_header_dly[2] ? (tlp_header_err_dly[2] | tlp_data_discontinue) : (tlp_data_discontinue & ~tlp_rd_end_r_dly[2]);
        tx_discontinue = tx_header_dly[2] ? tx_discontinue_c : (tx_discontinue_c | tx_discontinue_r);
        tx_force_ecrc = tx_header_dly[2] ? tlp_force_ecrc_dly[2] : 0;
        tx_fifo_wr = tx_dly[2];
        tx_fifo_wdata_sop = tx_header_dly[2];
        tx_fifo_wdata_eop = tx_end_dly[2];
        tx_fifo_wdata_valid = tx_valid_dly[2];
    end
end

integer i0;
always_comb begin
    for (i0=0; i0<KEEP_WIDTH; i0=i0+1) begin
        tx_valid_dly[0][KEEP_WIDTH-1-i0] = i0 <= tx_valid_dw_c;
    end
end

integer i1;
always_comb begin
    tx_data_pld_rev = 0;
    tx_data_pld_d1_rev = 0;
    for (i1=0; i1<DATA_WIDTH/8; i1=i1+1) begin
        tx_data_pld_rev[i1*8+:8] = tx_data_pld[(DATA_WIDTH/8-1-i1)*8+:8];
        tx_data_pld_d1_rev[i1*8+:8] = tx_data_pld_d1[(DATA_WIDTH/8-1-i1)*8+:8];
    end
end

always_comb begin
    tx_fifo_wdata_data = 0;
    unique case (1)
        tx_header_int: begin
            if (DATA_WIDTH == 64)
                tx_fifo_wdata_data = tlp_header_int[127:64];
            else if (DATA_WIDTH == 128)
                tx_fifo_wdata_data = tlp_header_4dw_int ? tlp_header_int : {tlp_header_int[127:32], tx_data_pld_rev[127:96]};
            else if (DATA_WIDTH == 256)
                tx_fifo_wdata_data = tlp_header_4dw_int ? {tlp_header_int, tx_data_pld_rev[255:128]} : {tlp_header_int[127:32], tx_data_pld_rev[255:96]};
            else if (DATA_WIDTH == 512)
                tx_fifo_wdata_data = tlp_header_4dw_int ? {tlp_header_int, tx_data_pld_rev[511:128]} : {tlp_header_int[127:32], tx_data_pld_rev[511:96]};
        end
        tx_header2_int: tx_fifo_wdata_data = tlp_header_4dw_int ? tlp_header_int[63:0] : {tlp_header_int[63:32], tx_data_pld_rev[63:32]};
        tx_data_int: begin
            if (DATA_WIDTH == 64)
                tx_fifo_wdata_data = tlp_header_4dw_int ? tx_data_pld_rev : {tx_data_pld_d1_rev[31:0], tx_data_pld_rev[63:32]};
            else if (DATA_WIDTH == 128)
                tx_fifo_wdata_data = tlp_header_4dw_int ? tx_data_pld_rev : {tx_data_pld_d1_rev[95:0], tx_data_pld_rev[127:96]};
            else if (DATA_WIDTH == 256)
                tx_fifo_wdata_data = tlp_header_4dw_int ? {tx_data_pld_d1_rev[127:0], tx_data_pld_rev[255:128]} : {tx_data_pld_d1_rev[95:0], tx_data_pld_rev[255:96]};
            else if (DATA_WIDTH == 512)
                tx_fifo_wdata_data = tlp_header_4dw_int ? {tx_data_pld_d1_rev[127:0], tx_data_pld_rev[511:128]} : {tx_data_pld_d1_rev[95:0], tx_data_pld_rev[511:96]};
        end
    endcase
end

always_comb begin
    tx_fifo_wdata_err = 0;
    if (SYNC_CLOCK) begin
        if (tx_fifo_wdata_sop) begin
            tx_fifo_wdata_err[4:3] = tlp_force_ecrc_dly[0] ? (tlp_header_td_dly[0] ? 2'b01 : 2'b10) : 2'b00;
        end
        if (tx_fifo_wdata_eop) begin
            tx_fifo_wdata_err[0] = tx_discontinue;
        end
    end else begin
        if (tx_fifo_wdata_sop) begin
            tx_fifo_wdata_err[4:3] = tlp_force_ecrc_dly[2] ? (tlp_header_td_dly[2] ? 2'b01 : 2'b10) : 2'b00;
        end
        if (tx_fifo_wdata_eop) begin
            tx_fifo_wdata_err[0] = tx_discontinue;
        end
    end
end

always_ff @(posedge core_clk2) begin
    if (core_rst)
        tx_rdy <= 0;
    else
        tx_rdy <= ~tx_fifo_afull;
end

always_ff @(posedge core_clk2) begin
    tx_dly[2:1] <= tx_dly[1:0];
    tx_header_dly[2:1] <= tx_header_dly[1:0];
    tx_header2_dly[2:1] <= tx_header2_dly[1:0];
    tx_data_dly[2:1] <= tx_data_dly[1:0];
    tx_end_dly[2:1] <= tx_end_dly[1:0];
    tx_valid_dly[1] <= tx_valid_dly[0];
    tx_valid_dly[2] <= tx_valid_dly[1];
    tlp_header_4dw_dly[2:1] <= tlp_header_4dw_dly[1:0];
    tlp_with_data_dly[2:1] <= tlp_with_data_dly[1:0];
    tlp_header_err_dly[2:1] <= tlp_header_err_dly[1:0];
    tlp_force_ecrc_dly[2:1] <= tlp_force_ecrc_dly[1:0];
    tlp_header_td_dly[2:1] <= tlp_header_td_dly[1:0];
    tlp_rd_end_r_dly[2:1] <= tlp_rd_end_r_dly[1:0];
    tlp_header_dly1 <= tlp_header_dly0;
    tlp_header_dly2 <= tlp_header_dly1;
    if (SYNC_CLOCK ? tx_dly[0] : tx_dly[1]) begin
        tx_data_pld_d1 <= tx_data_pld;
        tx_discontinue_r <= tx_discontinue;
    end
    if (core_rst)
        tx_dly[2:1] <= 0;
end

assign busy = tx_fifo_vld;

endmodule
