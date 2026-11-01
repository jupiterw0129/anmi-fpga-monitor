`include "pcie_brg_def.svh"

module pcie_brg_tx_width_conv#(
    parameter DATA_WIDTH = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter BUF_DEPTH = 2
) (
    input  logic core_clk,
    input  logic core_clk2,
    input  logic core_rst,

    core_tl_tx_if.slv core_tl_tx_int,
    core_tl_tx_if.mst core_tl_tx,

    output logic busy
);

generate
    if (DATA_WIDTH == CORE_DATA_WIDTH) begin: no_tx_width_conv

        assign core_tl_tx.tx_sop = core_tl_tx_int.tx_sop;
        assign core_tl_tx.tx_eop = core_tl_tx_int.tx_eop;
        assign core_tl_tx.tx_data = core_tl_tx_int.tx_data;
        assign core_tl_tx.tx_valid = core_tl_tx_int.tx_valid;
        assign core_tl_tx.tx_err = core_tl_tx_int.tx_err;
        assign core_tl_tx.tx_stream = core_tl_tx_int.tx_stream;
        assign core_tl_tx_int.tx_wait = core_tl_tx.tx_wait;
        assign core_tl_tx_int.tx_credits = core_tl_tx.tx_credits;

        assign busy = 0;

    end else begin: tx_width_conv

        always_ff @(posedge core_clk2) begin
            core_tl_tx_int.tx_credits <= core_tl_tx.tx_credits;
        end

        localparam BUF_PTR_WIDTH = $clog2(BUF_DEPTH);
        localparam BUF_DATA_WIDTH = (DATA_WIDTH > CORE_DATA_WIDTH) ? DATA_WIDTH : CORE_DATA_WIDTH;
        localparam SEG_NUM = (DATA_WIDTH > CORE_DATA_WIDTH) ? (DATA_WIDTH / CORE_DATA_WIDTH) : (CORE_DATA_WIDTH / DATA_WIDTH);
        localparam SEG_NUM_WIDTH = $clog2(SEG_NUM);

        logic [BUF_DEPTH-1:0] buf_sop;
        logic [BUF_DATA_WIDTH-1:0] buf_data [BUF_DEPTH-1:0];
        logic [BUF_DATA_WIDTH/32-1:0] buf_valid [BUF_DEPTH-1:0];
        logic [7:0] buf_err [BUF_DEPTH-1:0];
        logic [BUF_DEPTH-1:0] buf_stream;

        logic [BUF_PTR_WIDTH:0] buf_wptr;
        logic [BUF_PTR_WIDTH:0] buf_rptr;
        logic [BUF_PTR_WIDTH:0] buf_wptr_nxt;
        logic [BUF_PTR_WIDTH:0] buf_rptr_nxt;
        logic buf_vld;
        logic buf_full;
        logic [SEG_NUM_WIDTH-1:0] seg_ptr;

        assign buf_full = buf_wptr == (buf_rptr ^ {1'b1, {BUF_PTR_WIDTH{1'b0}}});
        assign buf_vld = buf_wptr != buf_rptr;

        always_ff @(posedge core_clk2) begin
            buf_wptr <= buf_wptr_nxt;
            if (core_rst) begin
                buf_wptr <= 0;
            end
        end

        always_ff @(posedge core_clk) begin
            buf_rptr <= buf_rptr_nxt;
            if (core_rst) begin
                buf_rptr <= 0;
            end
        end

        always_ff @(posedge core_clk2) begin
            busy <= (DATA_WIDTH == CORE_DATA_WIDTH) ? 0 : buf_vld;
        end

        logic tx_vld_c;
        logic tx_rdy_c;
        logic tx_sop_c;
        logic tx_eop_c;
        logic [CORE_DATA_WIDTH-1:0] tx_data_c;
        logic [CORE_DATA_WIDTH/32-1:0] tx_valid_c;
        logic [7:0] tx_err_c;
        logic tx_stream_c;

        logic tx_vld_r;
        logic tx_rdy_r;
        logic tx_sop_r;
        logic tx_eop_r;
        logic [CORE_DATA_WIDTH-1:0] tx_data_r;
        logic [CORE_DATA_WIDTH/32-1:0] tx_valid_r;
        logic [7:0] tx_err_r;
        logic tx_stream_r;

        assign core_tl_tx_int.tx_wait = buf_full;
        assign tx_vld_c = buf_vld;
        assign tx_rdy_r = ~core_tl_tx.tx_wait;
        assign core_tl_tx.tx_sop = tx_vld_r & tx_sop_r;
        assign core_tl_tx.tx_eop = tx_vld_r & tx_eop_r;
        assign core_tl_tx.tx_data = tx_data_r;
        assign core_tl_tx.tx_valid = tx_vld_r ? tx_valid_r : 0;
        assign core_tl_tx.tx_err = tx_err_r;
        assign core_tl_tx.tx_stream = tx_stream_r;

        pcie_brg_reg_slice #(
            .MODE("FWD"),
            .WIDTH(1+1+CORE_DATA_WIDTH+CORE_DATA_WIDTH/32+8+1)
        ) tx_reg_slice(
            .clk(core_clk),
            .rst(core_rst),
            .src_vld(tx_vld_c),
            .src_rdy(tx_rdy_c),
            .src_pld({tx_sop_c, tx_eop_c, tx_data_c, tx_valid_c, tx_err_c, tx_stream_c}),
            .dst_vld(tx_vld_r),
            .dst_rdy(tx_rdy_r),
            .dst_pld({tx_sop_r, tx_eop_r, tx_data_r, tx_valid_r, tx_err_r, tx_stream_r})
        );

        if (DATA_WIDTH > CORE_DATA_WIDTH) begin: tx_width_conv_down

            logic [SEG_NUM-1:0] buf_seg_eop [BUF_DEPTH-1:0];
            logic [SEG_NUM-1:0] seg_eop;

            assign tx_sop_c = buf_sop[buf_rptr[BUF_PTR_WIDTH-1:0]] & (&seg_ptr);
            assign tx_eop_c = buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr];
            assign tx_data_c = buf_data[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr*CORE_DATA_WIDTH+:CORE_DATA_WIDTH];
            assign tx_valid_c = buf_valid[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr*(CORE_DATA_WIDTH/32)+:(CORE_DATA_WIDTH/32)];
            assign tx_err_c = tx_sop_c ? buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]] : 0;
            assign tx_stream_c = tx_sop_c ? buf_stream[buf_rptr[BUF_PTR_WIDTH-1:0]] : 0;

            integer i;
            always_comb begin
                for (i=0; i<SEG_NUM; i=i+1) begin
                    if (i == 0)
                        seg_eop[i] = 1;
                    else
                        seg_eop[i] = ~|core_tl_tx_int.tx_valid[(i-1)*(DATA_WIDTH/32)+:(DATA_WIDTH/32)];
                end
                if (~core_tl_tx_int.tx_eop)
                    seg_eop = 0;
            end

            always_comb begin
                buf_wptr_nxt = buf_wptr;
                if ((|core_tl_tx_int.tx_valid) & ~core_tl_tx_int.tx_wait)
                    buf_wptr_nxt = buf_wptr+1;
            end

            always_ff @(posedge core_clk2) begin
                if ((|core_tl_tx_int.tx_valid) & ~core_tl_tx_int.tx_wait) begin
                    buf_sop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_sop;
                    buf_seg_eop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= seg_eop;
                    buf_data[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_data;
                    buf_valid[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_valid;
                    buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_err;
                    buf_stream[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_stream;
                end
            end

            always_comb begin
                buf_rptr_nxt = buf_rptr;
                if (tx_vld_c & tx_rdy_c) begin
                    if ((seg_ptr == 0) | buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr])
                        buf_rptr_nxt = buf_rptr+1;
                end
            end

            always_ff @(posedge core_clk) begin
                if (tx_vld_c & tx_rdy_c) begin
                    if (buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr])
                        seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                    else
                        seg_ptr <= seg_ptr-1;
                end
                if (core_rst) begin
                    seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                end
            end

        end else begin: tx_width_conv_up

            logic [BUF_DEPTH-1:0] buf_eop;
            logic [SEG_NUM-1:0] buf_seg_vld [BUF_DEPTH-1:0];

            assign tx_sop_c = buf_sop[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign tx_eop_c = buf_eop[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign tx_data_c = buf_data[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign tx_err_c = tx_sop_c ? buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]] : 0;
            assign tx_stream_c = tx_sop_c ? buf_stream[buf_rptr[BUF_PTR_WIDTH-1:0]] : 0;

            integer j;
            always_comb begin
                for (j=0; j<SEG_NUM; j=j+1) begin
                    if (buf_vld & buf_seg_vld[buf_rptr[BUF_PTR_WIDTH-1:0]][j])
                        tx_valid_c[j*(DATA_WIDTH/32)+:(DATA_WIDTH/32)] = buf_valid[buf_rptr[BUF_PTR_WIDTH-1:0]][j*(DATA_WIDTH/32)+:(DATA_WIDTH/32)];
                    else
                        tx_valid_c[j*(DATA_WIDTH/32)+:(DATA_WIDTH/32)] = 0;
                end
            end

            always_comb begin
                buf_wptr_nxt = buf_wptr;
                if ((|core_tl_tx_int.tx_valid) & ~core_tl_tx_int.tx_wait) begin
                    if ((seg_ptr == 0) | core_tl_tx_int.tx_eop)
                        buf_wptr_nxt = buf_wptr+1;
                end
            end

            always_ff @(posedge core_clk2) begin
                if ((|core_tl_tx_int.tx_valid) & ~core_tl_tx_int.tx_wait) begin
                    if ((seg_ptr == 0) | core_tl_tx_int.tx_eop) begin
                        seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                        buf_seg_vld[buf_wptr[BUF_PTR_WIDTH-1:0]] <= {SEG_NUM{1'b1}} << seg_ptr;
                        buf_eop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_eop;
                    end else begin
                        seg_ptr <= seg_ptr-1;
                    end
                    if (&seg_ptr) begin
                        buf_sop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_sop;
                    end
                    buf_data[buf_wptr[BUF_PTR_WIDTH-1:0]][seg_ptr*DATA_WIDTH+:DATA_WIDTH] <= core_tl_tx_int.tx_data;
                    buf_valid[buf_wptr[BUF_PTR_WIDTH-1:0]][seg_ptr*(DATA_WIDTH/32)+:(DATA_WIDTH/32)] <= core_tl_tx_int.tx_valid;
                    if (&seg_ptr) begin
                        buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_sop ? core_tl_tx_int.tx_err : 0;
                        buf_stream[buf_wptr[BUF_PTR_WIDTH-1:0]] <= core_tl_tx_int.tx_sop ? core_tl_tx_int.tx_stream : 0;
                    end
                end
                if (core_rst) begin
                    seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                end
            end

            always_comb begin
                buf_rptr_nxt = buf_rptr;
                if (tx_vld_c & tx_rdy_c)
                    buf_rptr_nxt = buf_rptr+1;
            end

        end

    end

endgenerate

endmodule
