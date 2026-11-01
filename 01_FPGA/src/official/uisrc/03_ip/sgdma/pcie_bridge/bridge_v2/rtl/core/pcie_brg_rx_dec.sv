`include "pcie_brg_def.svh"

module pcie_brg_rx_dec #(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    parameter WIDTH_CONV_BUF_DEPTH = 2,
    parameter CORE_PF_NUM = 4,
    parameter LEGACY_DEVICE = 0,
    parameter EP_MODE = 1,
    parameter NP_BUF_DEPTH = 32,

    parameter KEEP_WIDTH = DATA_WIDTH/32,
    parameter DW_WIDTH = $clog2(KEEP_WIDTH)
) (
    input  logic user_clk,
    input  logic user_rst,
    input  logic core_clk2,
    input  logic core_rst,

    output logic tlp_vld,
    input  logic tlp_rdy,
    output logic tlp_header_vld,
    input  logic tlp_header_rdy,
    output pcie_tlp_header_t tlp_header,
    output logic [47:0] tlp_bardec,
    output logic [CORE_PF_NUM+7:0] tlp_mchit,
    output logic [KEEP_WIDTH-1:0] tlp_valid,
    output logic tlp_ur,
    output logic tlp_np,
    output logic tlp_msg_route,
    output logic tlp_is_cq,
    output logic tlp_eop,
    output logic [9-DW_WIDTH:0] tlp_cycle_m1,
    input  logic tlp_data_rd,
    output logic [DATA_WIDTH-1:0] tlp_data,
    output logic tlp_discontinue,
    input  logic np_dec,
    // core rx
    core_tl_rx_if.slv core_tl_rx,

    output logic busy
);

logic rx_vld_c;
logic rx_rdy_c;
logic rx_sop_c;
logic rx_eop_c;
logic [DATA_WIDTH-1:0] rx_data_c;
logic [KEEP_WIDTH-1:0] rx_valid_c;
logic [47:0] rx_bardec_c;
logic [CORE_PF_NUM+7:0] rx_mchit_c;
logic [7:0] rx_err_c;

logic rx_vld_r;
logic rx_sop_r;
logic rx_eop_r;
logic [DATA_WIDTH-1:0] rx_data_r;
logic [KEEP_WIDTH-1:0] rx_valid_r;
logic [47:0] rx_bardec_r;
logic [CORE_PF_NUM+7:0] rx_mchit_r;
logic [7:0] rx_err_r;
pcie_tlp_header_t rx_header_r;

logic rx_rdy;
logic rx_rdy_cdc;
logic rx_ur_nxt;
logic rx_ur_r;
logic rx_np_nxt;
logic rx_np_r;
logic rx_msg_route_nxt;
logic rx_msg_route_r;
logic rx_tlp_is_cq_nxt;
logic rx_tlp_is_cq_r;
logic [7:0] fmt_type_c;
logic [7:0] msg_code_c;
logic [9:0] rx_tlp_len_c;
logic rx_header_4dw;
logic rx_header_4dw_c;
logic rx_header_4dw_r;
logic rx_sop_r1;// use in 64b, 128b
logic rx_sop_r2;// use in 64b
logic [DATA_WIDTH-1:0] rx_data_r1;// use in 64b
logic rx_eop_int;
logic [9-DW_WIDTH:0] rx_cycle_m1;

assign rx_vld_c = |rx_valid_c;
assign rx_rdy_c = ~rx_vld_r | rx_rdy;
assign rx_sop_c = core_tl_rx.rx_sop;
assign rx_eop_c = core_tl_rx.rx_eop;
assign rx_data_c = core_tl_rx.rx_data;
assign rx_valid_c = core_tl_rx.rx_valid;
assign rx_bardec_c = core_tl_rx.rx_bardec;
assign rx_mchit_c = core_tl_rx.rx_mchit;
assign rx_err_c = core_tl_rx.rx_err;
assign fmt_type_c = rx_data_c[DATA_WIDTH-1:DATA_WIDTH-8];
assign msg_code_c = rx_data_c[DATA_WIDTH-57:DATA_WIDTH-64];
assign rx_tlp_len_c = rx_data_c[DATA_WIDTH-23:DATA_WIDTH-32];
assign rx_header_4dw_c = fmt_type_c[5];
assign rx_header_4dw = rx_sop_c ? rx_header_4dw_c : rx_header_4dw_r;
assign core_tl_rx.rx_wait = ~rx_rdy_c;

always_comb begin
    rx_ur_nxt = 0;
    rx_np_nxt = 0;
    rx_msg_route_nxt = 0;
    rx_tlp_is_cq_nxt = 1;
    if ((fmt_type_c[7:3] == 5'b001_10) | (fmt_type_c[7:3] == 5'b011_10)) begin// msg, msgd
        rx_ur_nxt = 1;
        case (msg_code_c)
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,// intx
            8'h14, 8'h18, 8'h19, 8'h1b,// pme
            8'h30, 8'h31, 8'h33,// error
            8'h00,// unlock
            8'h50,// sspl
            8'h10,// ltr
            8'h12,// obff
            8'h7e, 8'h7f,// vd_msg
            8'h01, 8'h02, 8'h04, 8'h05:// ats
            begin// these messages are supported
                rx_ur_nxt = 0;
            end
        endcase
        rx_msg_route_nxt = rx_tlp_len_c == 1;
    end else begin
        case (fmt_type_c)
            8'b000_00000, 8'b001_00000: begin// mrd
                rx_ur_nxt = 0;
                rx_np_nxt = 1;
            end
            8'b000_00001, 8'b001_00001: begin// mrdlk
                rx_ur_nxt = LEGACY_DEVICE ? 0 : 1;
                rx_np_nxt = 1;
            end
            8'b010_00000, 8'b011_00000: begin// mwr
                rx_ur_nxt = 0;
            end
            8'b000_00010, 8'b010_00010: begin// iord, iowr
                rx_ur_nxt = 0;
                rx_np_nxt = 1;
            end
            8'b000_00100, 8'b010_00100: begin// cfg type0, supported in request
                rx_ur_nxt = EP_MODE ? 1 : 0;
                rx_np_nxt = 1;
            end
            8'b000_00101, 8'b010_00101: begin// cfg type1, supported in request
                rx_ur_nxt = EP_MODE ? 1 : 0;
                rx_np_nxt = 1;
            end
            8'b000_01010, 8'b010_01010: begin// cpl, cpld
                rx_ur_nxt = 0;
                rx_tlp_is_cq_nxt = 0;
            end
            8'b000_01011, 8'b010_01011: begin// cpllk, cpldlk
                rx_ur_nxt = LEGACY_DEVICE ? 0 : 1;
                rx_tlp_is_cq_nxt = 0;
            end
            8'b010_01100, 8'b011_01100: begin// fetchadd
                rx_ur_nxt = 0;
                rx_np_nxt = 1;
            end
            8'b010_01101, 8'b011_01101: begin// swap
                rx_ur_nxt = 0;
                rx_np_nxt = 1;
            end
            8'b010_01110, 8'b011_01110: begin// cas
                rx_ur_nxt = 0;
                rx_np_nxt = 1;
            end
            default: begin
                rx_ur_nxt = 1;
            end
        endcase
    end
end

always_ff @(posedge core_clk2) begin
    if (~rx_vld_r | rx_rdy) begin
        rx_sop_r <= rx_sop_c;
        rx_eop_r <= rx_eop_c;
        rx_data_r <= rx_data_c;
        rx_valid_r <= rx_valid_c;
        rx_bardec_r <= rx_bardec_c;
        rx_mchit_r <= rx_mchit_c;
        rx_err_r <= rx_err_c;
        rx_sop_r1 <= rx_sop_r;
        rx_sop_r2 <= rx_sop_r1;
        rx_data_r1 <= rx_data_r;
        rx_cycle_m1 <= rx_sop_c ? 0 : (rx_cycle_m1 + 1);
        if (rx_sop_c) begin
            rx_header_4dw_r <= rx_header_4dw_c;
            rx_ur_r <= rx_ur_nxt;
            rx_np_r <= rx_np_nxt;
            rx_msg_route_r <= rx_msg_route_nxt;
            rx_tlp_is_cq_r <= rx_tlp_is_cq_nxt;
        end
        if (~rx_vld_c) begin
            rx_vld_r <= 0;
        end else if ((DATA_WIDTH == 64) & rx_sop_c) begin
            rx_vld_r <= 0;
        end else if (rx_sop_c | ~rx_eop_c) begin
            rx_vld_r <= 1;
        end else begin
            rx_vld_r <= ~rx_eop_int;
        end
        if (DATA_WIDTH == 64) begin
            if (rx_sop_c)
                rx_header_r[127:64] <= rx_data_c;
            if (rx_sop_r)
                rx_header_r[63:0] <= rx_data_c;
        end else begin
            if (rx_sop_c)
                rx_header_r <= rx_data_c[DATA_WIDTH-1:DATA_WIDTH-128];
        end
    end
    if (core_rst) begin
        rx_vld_r <= 0;
    end
end

// if SYNC_CLOCK=0, valid_dw_m1 indicates the actual dwords in last cycle
// rx fifo is used when SYNC_CLOCK=1, otherwise header and data fifo
localparam HEADER_FIFO_WIDTH = $bits(pcie_tlp_header_t) + 48 + (CORE_PF_NUM + 8) + KEEP_WIDTH + 5 + (10-DW_WIDTH);// header + bardec + mchit + valid + discontinue + ur + np + msg_route + is_cq + cycle_m1;
localparam HEADER_FIFO_DEPTH = 16;
localparam HEADER_FIFO_AFULL = HEADER_FIFO_DEPTH - 4;

localparam DATA_FIFO_WIDTH = DATA_WIDTH + 1;// data + eop;
localparam DATA_FIFO_DEPTH = 512;
localparam DATA_FIFO_AFULL = DATA_FIFO_DEPTH - 4;

localparam RX_FIFO_WIDTH = HEADER_FIFO_WIDTH + DATA_FIFO_WIDTH;
localparam RX_FIFO_DEPTH = 8;

logic header_fifo_wr;
logic header_fifo_rd;
logic [HEADER_FIFO_WIDTH-1:0] header_fifo_wdata;
logic [HEADER_FIFO_WIDTH-1:0] header_fifo_rdata;
logic header_fifo_afull;
logic header_fifo_vld;

logic data_fifo_wr;
logic data_fifo_rd;
logic [DATA_FIFO_WIDTH-1:0] data_fifo_wdata;
logic [DATA_FIFO_WIDTH-1:0] data_fifo_rdata;
logic data_fifo_afull;
logic data_fifo_vld;

logic rx_fifo_wr;
logic rx_fifo_rd;
logic [RX_FIFO_WIDTH-1:0] rx_fifo_wdata;
logic [RX_FIFO_WIDTH-1:0] rx_fifo_rdata;
logic rx_fifo_full;
logic rx_fifo_vld;

pcie_brg_fifo #(
    .SYNC_CLOCK(0),
    .MEM_TYPE("dram"),
    .WIDTH(HEADER_FIFO_WIDTH),
    .DEPTH(HEADER_FIFO_DEPTH),
    .AFULL(HEADER_FIFO_AFULL),
    .REG_OUT(0),
    .RD_PFCH(1)
) header_fifo(
    .wclk(core_clk2),
    .wrst(core_rst),
    .wr(header_fifo_wr),
    .wdata(header_fifo_wdata),
    .full(),
    .afull(header_fifo_afull),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(header_fifo_rd),
    .rdata(header_fifo_rdata),
    .empty(),
    .vld(header_fifo_vld),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(0),
    .MEM_TYPE("bram"),
    .WIDTH(DATA_FIFO_WIDTH),
    .DEPTH(DATA_FIFO_DEPTH),
    .AFULL(DATA_FIFO_AFULL),
    .REG_OUT(1),
    .RD_PFCH(0)
) data_fifo(
    .wclk(core_clk2),
    .wrst(core_rst),
    .wr(data_fifo_wr),
    .wdata(data_fifo_wdata),
    .full(),
    .afull(data_fifo_afull),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(data_fifo_rd),
    .rdata(data_fifo_rdata),
    .empty(),
    .vld(),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(1),
    .MEM_TYPE("dram"),
    .WIDTH(RX_FIFO_WIDTH),
    .DEPTH(RX_FIFO_DEPTH),
    .AFULL(0),
    .REG_OUT(0),
    .RD_PFCH(1)
) rx_fifo(
    .wclk(core_clk2),
    .wrst(core_rst),
    .wr(rx_fifo_wr),
    .wdata(rx_fifo_wdata),
    .full(rx_fifo_full),
    .afull(),
    .oflow(),
    .rclk(user_clk),
    .rrst(user_rst),
    .rd(rx_fifo_rd),
    .rdata(rx_fifo_rdata),
    .empty(),
    .vld(rx_fifo_vld),
    .uflow()
);

logic [KEEP_WIDTH*2-1:0] rx_valid_concat;
logic [DATA_WIDTH*2-1:0] rx_data_concat;
logic [KEEP_WIDTH-1:0] rx_valid_int;
logic [DATA_WIDTH-1:0] rx_data_int;
logic rx_discontinue_int;
logic [KEEP_WIDTH-1:0] rx_valid_c_rev;
logic [KEEP_WIDTH-1:0] rx_valid_r_rev;
logic [DATA_WIDTH-1:0] rx_data_c_rev;
logic [DATA_WIDTH-1:0] rx_data_r_rev;
pcie_tlp_header_t rx_header;

assign rx_header = SYNC_CLOCK ? ((DATA_WIDTH == 64) ? {rx_data_r1, rx_data_r} : rx_data_r[DATA_WIDTH-1:DATA_WIDTH-128]) : rx_header_r;
assign header_fifo_wdata = {rx_header, rx_bardec_r, rx_mchit_r, rx_valid_int, rx_discontinue_int, rx_ur_r, rx_np_r, rx_msg_route_r, rx_tlp_is_cq_r, rx_cycle_m1};
assign data_fifo_wdata = {rx_data_int, rx_eop_int};
assign rx_fifo_wdata = {header_fifo_wdata, data_fifo_wdata};
assign rx_valid_concat = rx_eop_r ? rx_valid_r_rev : {rx_valid_c_rev, rx_valid_r_rev};
assign rx_data_concat = {rx_data_c_rev, rx_data_r_rev};
assign tlp_vld = SYNC_CLOCK ? rx_fifo_vld : 0;
assign rx_rdy = SYNC_CLOCK ? ~rx_fifo_full : rx_rdy_cdc;
assign rx_fifo_wr = SYNC_CLOCK ? (rx_vld_r & rx_rdy) : 0;
assign rx_fifo_rd = SYNC_CLOCK ? (tlp_vld & tlp_rdy) : 0;
assign tlp_header_vld = SYNC_CLOCK ? 0 : header_fifo_vld;
assign header_fifo_rd = SYNC_CLOCK ? 0 : tlp_header_rdy;
assign data_fifo_rd = SYNC_CLOCK ? 0 : tlp_data_rd;

always_comb begin
    if (SYNC_CLOCK) begin
        {tlp_header, tlp_bardec, tlp_mchit, tlp_valid, tlp_discontinue, tlp_ur, tlp_np, tlp_msg_route, tlp_is_cq, tlp_cycle_m1, tlp_data, tlp_eop} = rx_fifo_rdata;
    end else begin
        {tlp_header, tlp_bardec, tlp_mchit, tlp_valid, tlp_discontinue, tlp_ur, tlp_np, tlp_msg_route, tlp_is_cq, tlp_cycle_m1} = header_fifo_rdata;
        {tlp_data, tlp_eop} = data_fifo_rdata;
    end
end

always_comb begin
    rx_eop_int = 0;
    if (DATA_WIDTH == 64)
        rx_eop_int = rx_header_4dw_r ? rx_eop_r : ((rx_eop_r & rx_valid_c_rev[1]) | (~rx_eop_r & rx_eop_c & ~rx_valid_c_rev[1]));
    else if (DATA_WIDTH == 128)
        rx_eop_int = rx_header_4dw_r ? rx_eop_r : ((rx_eop_r & rx_valid_c_rev[3]) | (rx_eop_c & ~rx_valid_c_rev[3]));
    else
        rx_eop_int = rx_eop_r | (rx_eop_c & ~rx_valid_c_rev[3]);
end

always_comb begin
    header_fifo_wr = rx_eop_int;
    data_fifo_wr = 0;
    rx_valid_int = 0;
    rx_data_int = 0;
    if (DATA_WIDTH == 64) begin
        data_fifo_wr = rx_header_4dw_r ? (~rx_sop_r & ~rx_sop_r1) : (~rx_sop_r & rx_valid_r_rev[1]);
        rx_valid_int = rx_header_4dw_r ? rx_valid_concat : (rx_valid_concat >> 1);
        rx_data_int = rx_header_4dw_r ? rx_data_concat : (rx_data_concat >> 32);
    end else if (DATA_WIDTH == 128) begin
        data_fifo_wr = rx_header_4dw_r ? (~rx_sop_r) : rx_valid_r_rev[3];
        rx_valid_int = rx_header_4dw_r ? rx_valid_concat : (rx_valid_concat >> 3);
        rx_data_int = rx_header_4dw_r ? rx_data_concat : (rx_data_concat >> (3*32));
    end else begin
        data_fifo_wr = rx_header_4dw_r ? rx_valid_r_rev[4] : rx_valid_r_rev[3];
        rx_valid_int = rx_header_4dw_r ? (rx_valid_concat >> 4) : (rx_valid_concat >> 3);
        rx_data_int = rx_header_4dw_r ? (rx_data_concat >> (4*32)) : (rx_data_concat >> (3*32));
    end
    if (SYNC_CLOCK) begin
        header_fifo_wr = 0;
        data_fifo_wr = 0;
    end else begin
        if (~(rx_vld_r & rx_rdy)) begin
            header_fifo_wr = 0;
            data_fifo_wr = 0;
        end
    end
end

integer i0;
always_comb begin
    for (i0=0; i0<KEEP_WIDTH; i0=i0+1) begin
        rx_valid_c_rev[i0] = rx_valid_c[KEEP_WIDTH-1-i0];
        rx_valid_r_rev[i0] = rx_valid_r[KEEP_WIDTH-1-i0];
    end
end

integer i1;
always_comb begin
    for (i1=0; i1<DATA_WIDTH/8; i1=i1+1) begin
        rx_data_c_rev[i1*8+:8] = rx_data_c[(DATA_WIDTH/8-1-i1)*8+:8];
        rx_data_r_rev[i1*8+:8] = rx_data_r[(DATA_WIDTH/8-1-i1)*8+:8];
    end
end

always_ff @(posedge core_clk2) begin
    if (rx_vld_c) begin
        if (rx_sop_c)
            rx_discontinue_int <= |rx_err_c;
        else
            rx_discontinue_int <= rx_discontinue_int | (|rx_err_c);
    end
end

always_ff @(posedge core_clk2) begin
    if (core_rst)
        rx_rdy_cdc <= 0;
    else
        rx_rdy_cdc <= ~(header_fifo_afull | data_fifo_afull);
end

// mask np
localparam NP_PTR_WIDTH = $clog2(NP_BUF_DEPTH);
localparam NP_UNCERTAINTY = WIDTH_CONV_BUF_DEPTH+4+8;// width conv buf + 4 output pipeline + 8 internal pipeline

logic np_inc;
logic np_dec_d1;
logic [NP_PTR_WIDTH:0] np_cnt;

always_ff @(posedge core_clk2) begin
    if (core_rst) begin
        np_inc <= 0;
        np_dec_d1 <= 0;
    end else begin
        np_inc <= rx_vld_c & rx_rdy_c & rx_sop_c & rx_np_nxt;
        np_dec_d1 <= np_dec;
    end
end

generate
    if (SYNC_CLOCK) begin: np_wptr_no_cdc

        always_ff @(posedge core_clk2) begin
            if (core_rst) begin
                np_cnt <= 0;
                core_tl_rx.rx_masknp <= 0;
            end else begin
                np_cnt <= np_cnt + np_inc - np_dec_d1;
                core_tl_rx.rx_masknp <= np_cnt >= (NP_BUF_DEPTH - NP_UNCERTAINTY);
            end
        end

    end else begin: np_wptr_cdc

        logic [NP_PTR_WIDTH:0] np_wptr;
        logic [NP_PTR_WIDTH:0] np_rptr;
        logic [NP_PTR_WIDTH:0] np_rptr_sync;

        assign np_cnt = np_wptr - np_rptr_sync;

        always_ff @(posedge user_clk) begin
            if (user_rst)
                np_rptr <= 0;
            else
                np_rptr <= np_rptr + np_dec_d1;
        end

        always_ff @(posedge core_clk2) begin
            if (core_rst) begin
                np_wptr <= 0;
                core_tl_rx.rx_masknp <= 0;
            end else begin
                np_wptr <= np_wptr + np_inc;
                core_tl_rx.rx_masknp <= np_cnt >= (NP_BUF_DEPTH - NP_UNCERTAINTY);
            end
        end

        pcie_brg_cdc_gray #(
            .REG_OUT(1),
            .WIDTH(NP_PTR_WIDTH+1)
        ) cdc_np_wptr(
            .src_clk(user_clk),
            .src_in(np_rptr),
            .dst_clk(core_clk2),
            .dst_out(np_rptr_sync)
        );
    end
endgenerate

assign busy = rx_vld_r | (SYNC_CLOCK ? rx_fifo_vld : (header_fifo_vld | data_fifo_vld)) | (np_cnt != 0);

endmodule
