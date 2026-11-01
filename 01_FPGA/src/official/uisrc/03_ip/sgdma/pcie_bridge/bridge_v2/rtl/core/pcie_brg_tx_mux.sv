`include "pcie_brg_def.svh"

module pcie_brg_tx_mux#(
    parameter SYNC_CLOCK = 1,
    parameter DATA_WIDTH = 512,
    // infer
    parameter KEEP_WIDTH = DATA_WIDTH/32,
    parameter DW_WIDTH = $clog2(KEEP_WIDTH)
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk2,
    input logic core_rst,

    input logic [7:0] bus_num,
    input logic [4:0] dev_num,
    // ur tlp
    output logic ur_np_tlp_rdy,
    input  logic ur_np_tlp_vld,
    input  pcie_tlp_header_t ur_np_tlp_header,
    // msix
    output logic msix_rdy,
    input  logic msix_vld,
    input  pcie_tlp_header_t msix_header,
    input  logic [31:0] msix_data,
    // msg
    output logic xmit_msg_rdy,
    input  logic xmit_msg_vld,
    input  logic xmit_msg_err,
    input  pcie_tlp_header_t xmit_msg_header,
    input  logic [31:0] xmit_msg_data,
    // rq cc
    output logic rq_cc_tlp_rdy,
    input  logic rq_cc_tlp_vld,
    input  logic rq_cc_tlp_sop,
    input  logic rq_cc_tlp_eop,
    input  pcie_tlp_header_t rq_cc_tlp_header,
    input  logic [DATA_WIDTH-1:0] rq_cc_tlp_data,
    input  logic rq_cc_discontinue,
    input  logic rq_cc_force_ecrc,
    input  logic [5:0] rq_cc_tlp_seq_num,
    input  logic rq_cc_tlp_is_rq,
    input  logic rq_cc_req_type_err,
    input  logic rq_cc_cpl_status_ur_ca,
    input  logic rq_cc_cpl_status_err,
    output logic pcie_rq_seq_num_vld,
    output logic [5:0] pcie_rq_seq_num,

    output logic tlp_vld,
    input  logic tlp_rdy,
    output logic tlp_header_vld,
    input  logic tlp_header_rdy,
    output pcie_tlp_header_t tlp_header,
    output logic tlp_force_ecrc,
    output logic tlp_header_err,
    input  logic tlp_data_rd,
    output logic [DATA_WIDTH-1:0] tlp_data,
    output logic tlp_data_discontinue,

    output logic busy
);

localparam HEADER_FIFO_WIDTH = $bits(pcie_tlp_header_t) + 1 + 1;
localparam HEADER_FIFO_DEPTH = 16;
localparam HEADER_FIFO_AFULL = HEADER_FIFO_DEPTH - 4;

localparam DATA_FIFO_WIDTH = DATA_WIDTH+1;
localparam DATA_FIFO_DEPTH = 512;
localparam DATA_FIFO_AFULL = DATA_FIFO_DEPTH - 4;

localparam TX_FIFO_WIDTH = HEADER_FIFO_WIDTH + DATA_FIFO_WIDTH;
localparam TX_FIFO_DEPTH = 8;

logic [HEADER_FIFO_WIDTH-1:0] header_fifo_wdata;
logic [HEADER_FIFO_WIDTH-1:0] header_fifo_rdata;
logic header_fifo_wr;
logic header_fifo_rd;
logic header_fifo_afull;
logic header_fifo_vld;

logic [DATA_FIFO_WIDTH-1:0] data_fifo_wdata;
logic [DATA_FIFO_WIDTH-1:0] data_fifo_rdata;
logic data_fifo_wr;
logic data_fifo_rd;
logic data_fifo_afull;
logic data_fifo_vld;

logic [TX_FIFO_WIDTH-1:0] tx_fifo_wdata;
logic [TX_FIFO_WIDTH-1:0] tx_fifo_rdata;
logic tx_fifo_wr;
logic tx_fifo_rd;
logic tx_fifo_full;
logic tx_fifo_vld;

pcie_brg_fifo #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .MEM_TYPE("dram"),
    .WIDTH(HEADER_FIFO_WIDTH),
    .DEPTH(HEADER_FIFO_DEPTH),
    .AFULL(HEADER_FIFO_AFULL),
    .REG_OUT(0),
    .RD_PFCH(1)
) header_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(header_fifo_wr),
    .wdata(header_fifo_wdata),
    .full(),
    .afull(header_fifo_afull),
    .oflow(),
    .rclk(core_clk2),
    .rrst(core_rst),
    .rd(header_fifo_rd),
    .rdata(header_fifo_rdata),
    .empty(),
    .vld(header_fifo_vld),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .MEM_TYPE("bram"),
    .WIDTH(DATA_FIFO_WIDTH),
    .DEPTH(DATA_FIFO_DEPTH),
    .AFULL(DATA_FIFO_AFULL),
    .REG_OUT(1),
    .RD_PFCH(0)
) data_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(data_fifo_wr),
    .wdata(data_fifo_wdata),
    .full(),
    .afull(data_fifo_afull),
    .oflow(),
    .rclk(core_clk2),
    .rrst(core_rst),
    .rd(data_fifo_rd),
    .rdata(data_fifo_rdata),
    .empty(),
    .vld(data_fifo_vld),
    .uflow()
);

pcie_brg_fifo #(
    .SYNC_CLOCK(SYNC_CLOCK),
    .MEM_TYPE("dram"),
    .WIDTH(TX_FIFO_WIDTH),
    .DEPTH(TX_FIFO_DEPTH),
    .AFULL(0),
    .REG_OUT(0),
    .RD_PFCH(1)
) mux_fifo(
    .wclk(user_clk),
    .wrst(user_rst),
    .wr(tx_fifo_wr),
    .wdata(tx_fifo_wdata),
    .full(tx_fifo_full),
    .afull(),
    .oflow(),
    .rclk(core_clk2),
    .rrst(core_rst),
    .rd(tx_fifo_rd),
    .rdata(tx_fifo_rdata),
    .empty(),
    .vld(tx_fifo_vld),
    .uflow()
);

logic rq_cc_tlp_with_data;
logic [9:0] rq_cc_tlp_len_m1;
logic [9-DW_WIDTH:0] rq_cc_cycle_count;
logic [9-DW_WIDTH:0] rq_cc_cycle_counter;
logic [9-DW_WIDTH:0] rq_cc_cycle_counter_nxt;
logic xmit_rdy_cdc;
logic xmit_rdy;
logic rq_cc_xmit_end;
logic header_rq_cc_vld;

logic sm_header_r, sm_rq_cc_r, sm_rq_cc_pad_r, sm_rq_cc_drop_r;
logic sm_header_c, sm_rq_cc_c, sm_rq_cc_pad_c, sm_rq_cc_drop_c;

assign rq_cc_tlp_with_data = rq_cc_tlp_header.dw0[30];
assign rq_cc_tlp_len_m1 = rq_cc_tlp_header.dw0[9:0] - 1;
assign rq_cc_cycle_count = rq_cc_tlp_len_m1 >> DW_WIDTH;

assign ur_np_tlp_rdy = xmit_rdy & sm_header_r;
assign msix_rdy = xmit_rdy & sm_header_r & ~ur_np_tlp_vld;
assign xmit_msg_rdy = xmit_rdy & sm_header_r & ~ur_np_tlp_vld & ~msix_vld;
assign rq_cc_tlp_rdy = (xmit_rdy & ((sm_header_r & ~ur_np_tlp_vld & ~msix_vld & ~xmit_msg_vld) | sm_rq_cc_r)) | sm_rq_cc_drop_r;
assign header_rq_cc_vld = sm_header_r & ~ur_np_tlp_vld & ~msix_vld & ~xmit_msg_vld & rq_cc_tlp_vld;
assign tlp_vld = SYNC_CLOCK ? tx_fifo_vld : 0;
assign xmit_rdy = SYNC_CLOCK ? ~tx_fifo_full : xmit_rdy_cdc;
assign tx_fifo_rd = SYNC_CLOCK ? (tlp_vld & tlp_rdy) : 0;

always_ff @(posedge user_clk) begin
    rq_cc_cycle_counter <= rq_cc_cycle_counter_nxt;
end

always_ff @(posedge user_clk) begin
    if (user_rst)
        {sm_header_r, sm_rq_cc_r, sm_rq_cc_pad_r, sm_rq_cc_drop_r} <= 4'b1000;
    else
        {sm_header_r, sm_rq_cc_r, sm_rq_cc_pad_r, sm_rq_cc_drop_r} <= {sm_header_c, sm_rq_cc_c, sm_rq_cc_pad_c, sm_rq_cc_drop_c};
end

always_comb begin
    sm_header_c = sm_header_r;
    sm_rq_cc_c = sm_rq_cc_r;
    sm_rq_cc_pad_c = sm_rq_cc_pad_r;
    sm_rq_cc_drop_c = sm_rq_cc_drop_r;
    rq_cc_cycle_counter_nxt = rq_cc_cycle_counter;
    rq_cc_xmit_end = 0;
    unique case(1)
        sm_header_r: begin
            rq_cc_cycle_counter_nxt = rq_cc_cycle_count;
            if (xmit_rdy) begin
                if (ur_np_tlp_vld | msix_vld | xmit_msg_vld) begin
                    // next state is still sm_header
                end else if (rq_cc_tlp_vld) begin
                    sm_header_c = 0;
                    if (header_rq_cc_vld) begin// xmit rq cc
                        if (~rq_cc_tlp_with_data | (rq_cc_cycle_count == 0)) begin// should only 1 cycle
                            rq_cc_xmit_end = 1;
                            if (rq_cc_tlp_eop)
                                sm_header_c = 1;
                            else
                                sm_rq_cc_drop_c = 1;
                        end else begin
                            if (rq_cc_tlp_eop)
                                sm_rq_cc_pad_c = 1;
                            else
                                sm_rq_cc_c = 1;
                        end
                    end
                end
            end
        end
        sm_rq_cc_r: begin
            if (xmit_rdy) begin
                rq_cc_cycle_counter_nxt = rq_cc_cycle_counter - 1;
                case ({rq_cc_tlp_eop, (rq_cc_cycle_counter == 1)})
                    2'b01: begin
                        sm_rq_cc_c = 0;
                        sm_rq_cc_drop_c = 1;
                        rq_cc_xmit_end = 1;
                    end
                    2'b10: begin
                        sm_rq_cc_c = 0;
                        sm_rq_cc_pad_c = 1;
                    end
                    2'b11: begin
                        sm_rq_cc_c = 0;
                        sm_header_c = 1;
                        rq_cc_xmit_end = 1;
                    end
                endcase
            end
        end
        sm_rq_cc_pad_r: begin
            if (xmit_rdy) begin
                rq_cc_cycle_counter_nxt = rq_cc_cycle_counter - 1;
                if (rq_cc_cycle_counter == 1) begin
                    sm_rq_cc_pad_c = 0;
                    sm_header_c = 1;
                    rq_cc_xmit_end = 1;
                end
            end
        end
        sm_rq_cc_drop_r: begin
            if (rq_cc_tlp_eop) begin
                sm_rq_cc_drop_c = 0;
                sm_header_c = 1;
            end
        end
    endcase
end

always_ff @(posedge user_clk) begin
    pcie_rq_seq_num_vld <= sm_header_r & rq_cc_tlp_vld & rq_cc_tlp_rdy & rq_cc_tlp_is_rq;
    pcie_rq_seq_num <= rq_cc_tlp_seq_num;
    if (user_rst)
        pcie_rq_seq_num_vld <= 0;
end

pcie_tlp_header_t header_fifo_wdata_tlp_header_c;
logic header_fifo_wdata_force_ecrc_c;
logic header_fifo_wdata_header_err_c;
logic [DATA_WIDTH-1:0] data_fifo_pld_c;
logic data_fifo_discontinue_c;

pcie_tlp_header_t header_fifo_wdata_tlp_header_r;
logic header_fifo_wdata_force_ecrc_r;
logic header_fifo_wdata_header_err_r;
logic [DATA_WIDTH-1:0] data_fifo_pld_r;
logic data_fifo_discontinue_r;

assign header_fifo_wdata = {header_fifo_wdata_tlp_header_r, header_fifo_wdata_force_ecrc_r, header_fifo_wdata_header_err_r};
assign data_fifo_wdata = {data_fifo_discontinue_r, data_fifo_pld_r};
assign tx_fifo_wdata = {header_fifo_wdata_tlp_header_c, header_fifo_wdata_force_ecrc_c, header_fifo_wdata_header_err_c, data_fifo_discontinue_c, data_fifo_pld_c};

always_ff @(posedge user_clk) begin
    if (user_rst)
        xmit_rdy_cdc <= 0;
    else
        xmit_rdy_cdc <= ~(header_fifo_afull | data_fifo_afull);
end

always_ff @(posedge user_clk) begin
    header_fifo_wdata_tlp_header_r <= header_fifo_wdata_tlp_header_c;
    header_fifo_wdata_force_ecrc_r <= header_fifo_wdata_force_ecrc_c;
    header_fifo_wdata_header_err_r <= header_fifo_wdata_header_err_c;
    data_fifo_pld_r <= data_fifo_pld_c;
    data_fifo_discontinue_r <= data_fifo_discontinue_c;
end

assign tx_fifo_wr = SYNC_CLOCK ? (((sm_header_r & (ur_np_tlp_vld | msix_vld | xmit_msg_vld | rq_cc_tlp_vld)) | sm_rq_cc_r | sm_rq_cc_pad_r) & xmit_rdy) : 0;

generate
    if (SYNC_CLOCK) begin: header_fifo_wr_no_cdc// write header in first cycle
        always_ff @(posedge user_clk) begin
            header_fifo_wr <= sm_header_r & (ur_np_tlp_vld | msix_vld | xmit_msg_vld | rq_cc_tlp_vld) & xmit_rdy;
            if (user_rst)
                header_fifo_wr <= 0;
        end
    end else begin: header_fifo_wr_cdc// write header in last cycle
        always_ff @(posedge user_clk) begin
            if (user_rst)
                header_fifo_wr <= 0;
            else
                header_fifo_wr <= (ur_np_tlp_vld & ur_np_tlp_rdy) | (msix_vld & msix_rdy) | (xmit_msg_vld & xmit_msg_rdy) | rq_cc_xmit_end;
        end
    end
endgenerate

always_ff @(posedge user_clk) begin
    data_fifo_wr <= (sm_header_r & ((msix_vld & msix_rdy) | (xmit_msg_vld & xmit_msg_rdy & xmit_msg_header.dw0[30]) | (rq_cc_tlp_vld & rq_cc_tlp_rdy & rq_cc_tlp_with_data))) |
                    (sm_rq_cc_r & xmit_rdy) | (sm_rq_cc_pad_r & xmit_rdy);
    if (user_rst)
        data_fifo_wr <= 0;
end

always_comb begin
    header_fifo_wdata_tlp_header_c = header_fifo_wdata_tlp_header_r;
    header_fifo_wdata_force_ecrc_c = header_fifo_wdata_force_ecrc_r;
    header_fifo_wdata_header_err_c = header_fifo_wdata_header_err_r;
    if (sm_header_r) begin
        if (ur_np_tlp_vld) begin
            header_fifo_wdata_tlp_header_c = 0;
            header_fifo_wdata_tlp_header_c.dw0[31:24] = 8'b000_01010;
            header_fifo_wdata_tlp_header_c.dw0[22:20] = ur_np_tlp_header.dw0[22:20];// tc
            header_fifo_wdata_tlp_header_c.dw0[18] = ur_np_tlp_header.dw0[18];// attr
            header_fifo_wdata_tlp_header_c.dw0[13:12] = ur_np_tlp_header.dw0[13:12];// attr
            header_fifo_wdata_tlp_header_c.dw0[11:10] = ur_np_tlp_header.dw0[11:10];// at
            header_fifo_wdata_tlp_header_c.dw0[9:0] = 0;// length
            header_fifo_wdata_tlp_header_c.dw1[31:16] = {bus_num, dev_num, 3'b0};// cpl id
            header_fifo_wdata_tlp_header_c.dw1[15:13] = 3'b001;// cpl status
            header_fifo_wdata_tlp_header_c.dw1[11:0] = 0;// byte count
            header_fifo_wdata_tlp_header_c.dw2[31:16] = ur_np_tlp_header.dw1[31:16];// req id
            header_fifo_wdata_tlp_header_c.dw2[15:8] = ur_np_tlp_header.dw1[15:8];// tag
            header_fifo_wdata_tlp_header_c.dw2[6:0] = ur_np_tlp_header.dw0[29] ? {ur_np_tlp_header.dw3[6:2], 2'b0} : {ur_np_tlp_header.dw2[6:2], 2'b0};// lower address
            header_fifo_wdata_force_ecrc_c = 0;
            header_fifo_wdata_header_err_c = 0;
        end else if (msix_vld) begin
            header_fifo_wdata_tlp_header_c = msix_header;
            header_fifo_wdata_force_ecrc_c = 0;
            header_fifo_wdata_header_err_c = 0;
        end else if (xmit_msg_vld) begin
            header_fifo_wdata_tlp_header_c = xmit_msg_header;
            header_fifo_wdata_force_ecrc_c = 0;
            header_fifo_wdata_header_err_c = xmit_msg_err;
        end else if (rq_cc_tlp_vld) begin
            header_fifo_wdata_tlp_header_c = rq_cc_tlp_header;
            header_fifo_wdata_force_ecrc_c = rq_cc_force_ecrc;
            header_fifo_wdata_header_err_c = rq_cc_tlp_is_rq ? rq_cc_req_type_err : rq_cc_cpl_status_err;
        end
    end
end

always_comb begin
    data_fifo_discontinue_c = data_fifo_discontinue_r;
    unique case (1)
        sm_header_r: data_fifo_discontinue_c = header_rq_cc_vld & (rq_cc_discontinue | sm_rq_cc_drop_c);
        sm_rq_cc_r: data_fifo_discontinue_c = rq_cc_discontinue;
        sm_rq_cc_pad_r: data_fifo_discontinue_c = 1;
    endcase
end

always_comb begin
    data_fifo_pld_c = 0;
    if (sm_header_r) begin
        if (ur_np_tlp_vld)
            data_fifo_pld_c = 0;
        else if (msix_vld)
            data_fifo_pld_c = msix_data;
        else if (xmit_msg_vld)
            data_fifo_pld_c = xmit_msg_data;
        else if (rq_cc_tlp_vld)
            data_fifo_pld_c = rq_cc_tlp_data;
    end else if (sm_rq_cc_r) begin
        data_fifo_pld_c = rq_cc_tlp_data;
    end
end

always_comb begin
    if (SYNC_CLOCK) begin
        {tlp_header, tlp_force_ecrc, tlp_header_err, tlp_data_discontinue, tlp_data} = tx_fifo_rdata;
    end else begin
        {tlp_header, tlp_force_ecrc, tlp_header_err} = header_fifo_rdata;
        {tlp_data_discontinue, tlp_data} = data_fifo_rdata;
    end
end

assign tlp_header_vld = SYNC_CLOCK ? 0 : header_fifo_vld;
assign header_fifo_rd = SYNC_CLOCK ? 0 : (tlp_header_vld & tlp_header_rdy);
assign data_fifo_rd = SYNC_CLOCK ? 0 : tlp_data_rd;

assign busy = SYNC_CLOCK ? tx_fifo_vld : (header_fifo_vld | data_fifo_vld);

endmodule
