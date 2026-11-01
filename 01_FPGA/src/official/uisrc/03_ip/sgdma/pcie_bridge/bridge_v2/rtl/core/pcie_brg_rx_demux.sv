`include "pcie_brg_def.svh"

module pcie_brg_rx_demux #(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter CORE_PF_NUM = 4,
    parameter RECV_MSG_EN = 1,
    parameter NP_BUF_DEPTH = 32,
    //
    parameter KEEP_WIDTH = DATA_WIDTH/32,
    parameter DW_WIDTH = $clog2(KEEP_WIDTH)
) (
    input  logic user_clk,
    input  logic user_rst,

    input  logic tlp_vld,
    output logic tlp_rdy,
    input  logic tlp_header_vld,
    output logic tlp_header_rdy,
    input  pcie_tlp_header_t tlp_header,
    input  logic [47:0] tlp_bardec,
    input  logic [CORE_PF_NUM+7:0] tlp_mchit,
    input  logic [KEEP_WIDTH-1:0] tlp_valid,
    input  logic tlp_ur,
    input  logic tlp_np,
    input  logic tlp_msg_route,
    input  logic tlp_is_cq,
    input  logic tlp_eop,
    input  logic [9-DW_WIDTH:0] tlp_cycle_m1,
    output logic tlp_data_rd,
    input  logic [DATA_WIDTH-1:0] tlp_data,
    input  logic tlp_discontinue,
    output logic np_dec,
    // ur np tlp
    input  logic ur_np_tlp_rdy,
    output logic ur_np_tlp_vld,
    output pcie_tlp_header_t ur_np_tlp_header,
    // recv msg
    output logic msg_vld,
    input  logic msg_rdy,
    output pcie_tlp_header_t msg_header,
    output logic [31:0] msg_data,
    // cq rc
    output logic cq_rc_tlp_vld,
    input  logic cq_rc_tlp_rdy,
    output logic cq_rc_tlp_header_vld,
    input  logic cq_rc_tlp_header_rdy,
    output pcie_tlp_header_t cq_rc_tlp_header,
    output logic [47:0] cq_rc_tlp_bardec,
    output logic [CORE_PF_NUM+7:0] cq_rc_tlp_mchit,
    output logic [KEEP_WIDTH-1:0] cq_rc_tlp_valid,
    output logic cq_rc_tlp_is_cq,
    output logic cq_rc_tlp_is_np,
    output logic cq_rc_tlp_eop,
    output logic [9-DW_WIDTH:0] cq_rc_tlp_cycle_m1,
    input  logic cq_rc_tlp_data_rd,
    input  logic cq_rc_tlp_data_rd_eop,
    output logic [DATA_WIDTH-1:0] cq_rc_tlp_data,
    output logic cq_rc_tlp_discontinue,
    input  logic cq_rc_np_mask,

    output logic busy
);

// np header fifo and data fifo is used in async mode
// np fifo is used in sync mode, pack header and data
localparam NP_FIFO_DEPTH = (DATA_WIDTH == 512) ? NP_BUF_DEPTH : (NP_BUF_DEPTH * 256 / DATA_WIDTH);
localparam NP_HEADER_FIFO_DEPTH = NP_FIFO_DEPTH;
localparam NP_DATA_FIFO_DEPTH = (DATA_WIDTH == 512) ? NP_HEADER_FIFO_DEPTH : (NP_HEADER_FIFO_DEPTH * 256 / DATA_WIDTH);// max 8dw in atomic request

localparam NP_HEADER_FIFO_WIDTH = $bits(pcie_tlp_header_t) + 48 + (CORE_PF_NUM + 8) + KEEP_WIDTH + 1 + (10-DW_WIDTH);// header + bardec + mchit + valid + discontinue + cycle_m1;
localparam NP_DATA_FIFO_WIDTH = DATA_WIDTH + 1;// data + eop;
localparam NP_FIFO_WIDTH = NP_HEADER_FIFO_WIDTH + NP_DATA_FIFO_WIDTH;

logic [NP_HEADER_FIFO_WIDTH-1:0] np_header_fifo_wdata;
logic [NP_HEADER_FIFO_WIDTH-1:0] np_header_fifo_rdata;
logic np_header_fifo_wr;
logic np_header_fifo_rd;
logic np_header_fifo_vld;

logic [NP_DATA_FIFO_WIDTH-1:0] np_data_fifo_wdata;
logic [NP_DATA_FIFO_WIDTH-1:0] np_data_fifo_rdata;
logic np_data_fifo_wr;
logic np_data_fifo_rd;
logic np_data_fifo_full;// if this fifo overflow, it is uncorrectable error
logic np_data_fifo_vld;

logic [NP_FIFO_WIDTH-1:0] np_fifo_wdata;
logic [NP_FIFO_WIDTH-1:0] np_fifo_rdata;
logic np_fifo_wr;
logic np_fifo_rd;
logic np_fifo_full;
logic np_fifo_vld;

pcie_tlp_header_t np_tlp_header;
logic [47:0] np_tlp_bardec;
logic [CORE_PF_NUM+7:0] np_tlp_mchit;
logic [KEEP_WIDTH-1:0] np_tlp_valid;
logic [9-DW_WIDTH:0] np_tlp_cycle_m1;
logic [DATA_WIDTH-1:0] np_tlp_data;
logic np_tlp_discontinue;
logic np_tlp_eop;

pcie_brg_fifo #(
    .SYNC_CLOCK(0),
    .MEM_TYPE("dram"),
    .WIDTH(NP_HEADER_FIFO_WIDTH),
    .DEPTH(NP_HEADER_FIFO_DEPTH),
    .AFULL(0),
    .REG_OUT(0),
    .RD_PFCH(1)
) np_header_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(np_header_fifo_wr),
    .wdata(np_header_fifo_wdata),
    .full(),
    .afull(),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(np_header_fifo_rd),
    .rdata(np_header_fifo_rdata),
    .empty(),
    .vld(np_header_fifo_vld),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(0),
    .MEM_TYPE("dram"),
    .WIDTH(NP_DATA_FIFO_WIDTH),
    .DEPTH(NP_DATA_FIFO_DEPTH),
    .AFULL(0),
    .REG_OUT(1),
    .RD_PFCH(0)
) np_data_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(np_data_fifo_wr),
    .wdata(np_data_fifo_wdata),
    .full(np_data_fifo_full),
    .afull(),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(np_data_fifo_rd),
    .rdata(np_data_fifo_rdata),
    .empty(),
    .vld(np_data_fifo_vld),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(1),
    .MEM_TYPE("dram"),
    .WIDTH(NP_FIFO_WIDTH),
    .DEPTH(NP_FIFO_DEPTH),
    .AFULL(0),
    .REG_OUT(0),
    .RD_PFCH(1)
) np_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(np_fifo_wr),
    .wdata(np_fifo_wdata),
    .full(np_fifo_full),
    .afull(),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(np_fifo_rd),
    .rdata(np_fifo_rdata),
    .empty(),
    .vld(np_fifo_vld),
    .uflow()
);

logic tlp_ur_np;
logic tlp_ur_p_cpl;
logic tlp_msg;
logic tlp_sr_np;
logic tlp_data_rd_c;
logic tlp_data_rd_r;
logic tlp_cycle_m1_r;
logic tlp_cycle_m1_nxt;
logic cq_rc_mux_np;
logic cq_rc_mux_np_c;
logic cq_rc_mux_np_r;
logic ur_np_tlp_vld_nxt;
pcie_tlp_header_t ur_np_tlp_header_nxt;

logic sm_header_r, sm_cq_rc_r, sm_misc_r, sm_misc_wait_r, sm_misc_wait2_r;
logic sm_header_c, sm_cq_rc_c, sm_misc_c, sm_misc_wait_c, sm_misc_wait2_c;

logic sm_misc_ur_np_r, sm_misc_ur_p_cpl_r, sm_misc_msg_r, sm_misc_np_r, sm_misc_sop_r;
logic sm_misc_ur_np_c, sm_misc_ur_p_cpl_c, sm_misc_msg_c, sm_misc_np_c, sm_misc_sop_c;

logic [2:0] sm_misc_dly;
logic [2:0] sm_misc_ur_np_dly;
logic [2:0] sm_misc_msg_dly;
logic [2:0] sm_misc_np_dly;
logic [2:0] sm_misc_sop_dly;

pcie_tlp_header_t tlp_header_dly0;
pcie_tlp_header_t tlp_header_dly1;
pcie_tlp_header_t tlp_header_dly2;
logic [2:0] [47:0] tlp_bardec_dly;
logic [2:0] [CORE_PF_NUM+7:0] tlp_mchit_dly;
logic [2:0] [KEEP_WIDTH-1:0] tlp_valid_dly;
logic [2:0] tlp_discontinue_dly;
logic [2:0] [9-DW_WIDTH:0] tlp_cycle_m1_dly;

assign tlp_ur_np = tlp_np & tlp_ur;
assign tlp_ur_p_cpl = ~tlp_np & tlp_ur;
assign tlp_msg = RECV_MSG_EN & tlp_msg_route & ~tlp_ur;
assign tlp_sr_np = tlp_np & ~tlp_ur;
assign tlp_data_rd = SYNC_CLOCK ? 0 : tlp_data_rd_r;
assign sm_misc_dly[0] = sm_misc_r;
assign sm_misc_ur_np_dly[0] = sm_misc_ur_np_r;
assign sm_misc_msg_dly[0] = sm_misc_msg_r;
assign sm_misc_np_dly[0] = sm_misc_np_r;
assign sm_misc_sop_dly[0] = sm_misc_sop_r;
assign tlp_header_dly0 = tlp_header;
assign tlp_bardec_dly[0] = tlp_bardec;
assign tlp_mchit_dly[0] = tlp_mchit;
assign tlp_valid_dly[0] = tlp_valid;
assign tlp_discontinue_dly[0] = tlp_discontinue;
assign tlp_cycle_m1_dly[0] = tlp_cycle_m1;
assign ur_np_tlp_vld_nxt = sm_misc_dly[0] & sm_misc_ur_np_dly[0] & sm_misc_sop_dly[0];
assign ur_np_tlp_header_nxt = tlp_header_dly0;
assign msg_vld = SYNC_CLOCK ? (sm_misc_dly[0] & sm_misc_msg_dly[0]) : (sm_misc_dly[2] & sm_misc_msg_dly[2]);
assign msg_header = SYNC_CLOCK ? tlp_header_dly0 : tlp_header_dly2;
assign msg_data = tlp_data[31:0];
assign cq_rc_mux_np = sm_header_r ? cq_rc_mux_np_c : cq_rc_mux_np_r;
assign cq_rc_mux_np_c = SYNC_CLOCK ? np_fifo_vld : np_header_fifo_vld;
assign np_header_fifo_wr = SYNC_CLOCK ? 0 : (sm_misc_dly[2] & sm_misc_np_dly[2] & sm_misc_sop_dly[2]);
assign np_header_fifo_wdata = SYNC_CLOCK ? 0 : {tlp_header_dly2, tlp_bardec_dly[2], tlp_mchit_dly[2], tlp_valid_dly[2], tlp_discontinue_dly[2], tlp_cycle_m1_dly[2]};
assign np_data_fifo_wr = SYNC_CLOCK ? 0 : (sm_misc_dly[2] & sm_misc_np_dly[2] & tlp_valid_dly[2][0]);
assign np_data_fifo_wdata = SYNC_CLOCK ? 0 : {tlp_data, tlp_eop};
assign np_fifo_wr = SYNC_CLOCK ? (sm_misc_dly[0] & sm_misc_np_dly[0]) : 0;
assign np_fifo_wdata = SYNC_CLOCK ? {tlp_header_dly0, tlp_bardec_dly[0], tlp_mchit_dly[0], tlp_valid_dly[0], tlp_discontinue_dly[0], tlp_cycle_m1_dly[0], tlp_data, tlp_eop} : 0;
assign np_header_fifo_rd = SYNC_CLOCK ? 0 : (cq_rc_tlp_header_vld & sm_header_r & cq_rc_mux_np_c & cq_rc_tlp_header_rdy);
assign np_data_fifo_rd = SYNC_CLOCK ? 0 : (cq_rc_mux_np & cq_rc_tlp_data_rd);
assign np_fifo_rd = SYNC_CLOCK ? (cq_rc_tlp_vld & cq_rc_mux_np & cq_rc_tlp_rdy) : 0;
assign {np_tlp_header, np_tlp_bardec, np_tlp_mchit, np_tlp_valid, np_tlp_discontinue, np_tlp_cycle_m1, np_tlp_data, np_tlp_eop} = SYNC_CLOCK ? np_fifo_rdata : {np_header_fifo_rdata, np_data_fifo_rdata};

always_ff @(posedge user_clk) begin
    if (user_rst)
        tlp_data_rd_r <= 0;
    else
        tlp_data_rd_r <= SYNC_CLOCK ? 0 : tlp_data_rd_c;
end

always_ff @(posedge user_clk) begin
    sm_misc_ur_np_r <= sm_misc_ur_np_c;
    sm_misc_ur_p_cpl_r <= sm_misc_ur_p_cpl_c;
    sm_misc_msg_r <= sm_misc_msg_c;
    sm_misc_np_r <= sm_misc_np_c;
    sm_misc_sop_r <= sm_misc_sop_c;
end

always_ff @(posedge user_clk) begin
    sm_misc_dly[2:1] <= sm_misc_dly[1:0];
    sm_misc_ur_np_dly[2:1] <= sm_misc_ur_np_dly[1:0];
    sm_misc_msg_dly[2:1] <= sm_misc_msg_dly[1:0];
    sm_misc_np_dly[2:1] <= sm_misc_np_dly[1:0];
    sm_misc_sop_dly[2:1] <= sm_misc_sop_dly[1:0];
    tlp_header_dly1 <= tlp_header_dly0;
    tlp_header_dly2 <= tlp_header_dly1;
    tlp_bardec_dly[2] <= tlp_bardec_dly[1];
    tlp_bardec_dly[1] <= tlp_bardec_dly[0];
    tlp_mchit_dly[2] <= tlp_mchit_dly[1];
    tlp_mchit_dly[1] <= tlp_mchit_dly[0];
    tlp_valid_dly[2] <= tlp_valid_dly[1];
    tlp_valid_dly[1] <= tlp_valid_dly[0];
    tlp_discontinue_dly[2:1] <= tlp_discontinue_dly[1:0];
    tlp_cycle_m1_dly[2] <= tlp_cycle_m1_dly[1];
    tlp_cycle_m1_dly[1] <= tlp_cycle_m1_dly[0];
    if (user_rst) begin
        sm_misc_dly[2:1] <= 0;
    end
end

always_ff @(posedge user_clk) begin
    if (ur_np_tlp_vld_nxt) begin
        ur_np_tlp_vld <= 1;
        ur_np_tlp_header <= ur_np_tlp_header_nxt;
    end else if (ur_np_tlp_vld & ur_np_tlp_rdy) begin
        ur_np_tlp_vld <= 0;
    end
    if (user_rst)
        ur_np_tlp_vld <= 0;
end

always_ff @(posedge user_clk) begin
    if (sm_header_r)
        cq_rc_mux_np_r <= cq_rc_mux_np_c;
end

always_ff @(posedge user_clk) begin
    tlp_cycle_m1_r <= tlp_cycle_m1_nxt;
end

always_ff @(posedge user_clk) begin
    if (user_rst)
        {sm_header_r, sm_cq_rc_r, sm_misc_r, sm_misc_wait_r, sm_misc_wait2_r} <= 5'b10000;
    else
        {sm_header_r, sm_cq_rc_r, sm_misc_r, sm_misc_wait_r, sm_misc_wait2_r} <= {sm_header_c, sm_cq_rc_c, sm_misc_c, sm_misc_wait_c, sm_misc_wait2_c};
end

always_comb begin
    sm_header_c = sm_header_r;
    sm_cq_rc_c = sm_cq_rc_r;
    sm_misc_c = sm_misc_r;
    sm_misc_wait_c = sm_misc_wait_r;
    sm_misc_wait2_c = sm_misc_wait2_r;
    sm_misc_ur_np_c = sm_misc_ur_np_r;
    sm_misc_ur_p_cpl_c = sm_misc_ur_p_cpl_r;
    sm_misc_msg_c = sm_misc_msg_r;
    sm_misc_np_c = sm_misc_np_r;
    tlp_header_rdy = 0;
    tlp_data_rd_c = 0;
    tlp_rdy = 0;
    sm_misc_sop_c = 1;
    tlp_cycle_m1_nxt = tlp_cycle_m1_r;
    cq_rc_tlp_vld = 0;
    cq_rc_tlp_header_vld = 0;
    unique case (1)
        sm_header_r: begin
            tlp_cycle_m1_nxt = tlp_cycle_m1;
            if ((SYNC_CLOCK ? tlp_vld : tlp_header_vld) & (tlp_ur_np | tlp_ur_p_cpl | tlp_msg | (tlp_sr_np & cq_rc_np_mask))) begin
                sm_misc_ur_np_c = tlp_ur_np;
                sm_misc_ur_p_cpl_c = tlp_ur_p_cpl;
                sm_misc_msg_c = tlp_msg;
                sm_misc_np_c = tlp_sr_np;
                if (tlp_ur_np & ~ur_np_tlp_vld) begin
                    sm_header_c = 0;
                    sm_misc_c = 1;
                end
                if (tlp_ur_p_cpl) begin
                    sm_header_c = 0;
                    sm_misc_c = 1;
                end
                if (tlp_msg & msg_rdy) begin
                    sm_header_c = 0;
                    sm_misc_c = 1;
                end
                if (tlp_sr_np & cq_rc_np_mask) begin
                    sm_header_c = 0;
                    sm_misc_c = 1;
                end
            end else begin// cq rc
                tlp_header_rdy = SYNC_CLOCK ? 0 : cq_rc_tlp_header_rdy;
                tlp_data_rd_c = SYNC_CLOCK ? 0 : cq_rc_tlp_data_rd;
                tlp_rdy = SYNC_CLOCK ? cq_rc_tlp_rdy : 0;
                if (SYNC_CLOCK) begin
                    cq_rc_tlp_vld = tlp_vld | (np_fifo_vld & ~cq_rc_np_mask);
                    if (cq_rc_tlp_vld & cq_rc_tlp_rdy & ~cq_rc_tlp_eop) begin
                        sm_header_c = 0;
                        sm_cq_rc_c = 1;
                    end
                end else begin
                    cq_rc_tlp_header_vld = tlp_header_vld | (np_header_fifo_vld & ~cq_rc_np_mask);
                    if (cq_rc_tlp_header_vld & cq_rc_tlp_header_rdy & cq_rc_tlp_valid[0] & ~cq_rc_tlp_data_rd_eop) begin
                        sm_header_c = 0;
                        sm_cq_rc_c = 1;
                    end
                end
            end
        end
        sm_cq_rc_r: begin
            cq_rc_tlp_vld = SYNC_CLOCK ? 1 : 0;
            tlp_header_rdy = SYNC_CLOCK ? 0 : cq_rc_tlp_header_rdy;
            tlp_data_rd_c = SYNC_CLOCK ? 0 : cq_rc_tlp_data_rd;
            tlp_rdy = SYNC_CLOCK ? cq_rc_tlp_rdy : 0;
            if (SYNC_CLOCK) begin
                if (cq_rc_tlp_rdy & cq_rc_tlp_eop) begin
                    sm_cq_rc_c = 0;
                    sm_header_c = 1;
                end
            end else begin
                if (cq_rc_tlp_data_rd & cq_rc_tlp_data_rd_eop) begin
                    sm_cq_rc_c = 0;
                    sm_header_c = 1;
                end
            end
        end
        sm_misc_r: begin
            sm_misc_sop_c = 0;
            tlp_cycle_m1_nxt = tlp_cycle_m1_r - 1;
            tlp_header_rdy = SYNC_CLOCK ? 0 : sm_misc_sop_r;
            tlp_data_rd_c = SYNC_CLOCK ? 0 : (sm_misc_sop_r ? tlp_valid[0] : 1);
            tlp_rdy = SYNC_CLOCK;
            if (SYNC_CLOCK) begin
                if (tlp_eop) begin
                    sm_misc_c = 0;
                    sm_header_c = 1;
                end
            end else begin
                if (tlp_cycle_m1_r == 0) begin
                    sm_misc_c = 0;
                    sm_misc_wait_c = 1;
                end
            end
        end
        sm_misc_wait_r: begin
            sm_misc_wait_c = 0;
            sm_misc_wait2_c = 1;
        end
        sm_misc_wait2_r: begin
            sm_misc_wait2_c = 0;
            sm_header_c = 1;
        end
    endcase
end

always_comb begin
    if (cq_rc_mux_np) begin
        cq_rc_tlp_header = np_tlp_header;
        cq_rc_tlp_bardec = np_tlp_bardec;
        cq_rc_tlp_mchit = np_tlp_mchit;
        cq_rc_tlp_valid = np_tlp_valid;
        cq_rc_tlp_discontinue = np_tlp_discontinue;
        cq_rc_tlp_cycle_m1 = np_tlp_cycle_m1;
        cq_rc_tlp_data = np_tlp_data;
        cq_rc_tlp_eop = np_tlp_eop;
        cq_rc_tlp_is_cq = 1;
        cq_rc_tlp_is_np = 1;
    end else begin
        cq_rc_tlp_header = tlp_header;
        cq_rc_tlp_bardec = tlp_bardec;
        cq_rc_tlp_mchit = tlp_mchit;
        cq_rc_tlp_valid = tlp_valid;
        cq_rc_tlp_discontinue = tlp_discontinue;
        cq_rc_tlp_cycle_m1 = tlp_cycle_m1;
        cq_rc_tlp_data = tlp_data;
        cq_rc_tlp_eop = tlp_eop;
        cq_rc_tlp_is_cq = tlp_is_cq;
        cq_rc_tlp_is_np = tlp_np;
    end
end

assign np_dec = (SYNC_CLOCK ? (sm_header_r & cq_rc_tlp_vld & cq_rc_tlp_rdy & ((np_fifo_vld & ~cq_rc_np_mask) | tlp_np)) :
                              (cq_rc_tlp_header_vld & cq_rc_tlp_header_rdy & ((np_header_fifo_vld & ~cq_rc_np_mask) | tlp_np)))
                | (ur_np_tlp_vld & ur_np_tlp_rdy);

assign busy = ~sm_header_r | (SYNC_CLOCK ? np_fifo_vld : (np_header_fifo_vld | np_data_fifo_vld));

endmodule
