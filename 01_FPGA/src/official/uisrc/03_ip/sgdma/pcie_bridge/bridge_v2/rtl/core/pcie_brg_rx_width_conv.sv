`include "pcie_brg_def.svh"

module pcie_brg_rx_width_conv#(
    parameter DATA_WIDTH = 512,
    parameter CORE_DATA_WIDTH = DATA_WIDTH,
    parameter BUF_DEPTH = 2,
    parameter CORE_PF_NUM = 4
) (
    input  logic core_clk,
    input  logic core_clk2,
    input  logic core_rst,

    core_tl_rx_if.mst core_tl_rx_int,
    core_tl_rx_if.slv core_tl_rx,

    output logic busy
);

generate
    if (DATA_WIDTH == CORE_DATA_WIDTH) begin: no_rx_width_conv

        assign core_tl_rx_int.rx_sop = core_tl_rx.rx_sop;
        assign core_tl_rx_int.rx_eop = core_tl_rx.rx_eop;
        assign core_tl_rx_int.rx_data = core_tl_rx.rx_data;
        assign core_tl_rx_int.rx_valid = core_tl_rx.rx_valid;
        assign core_tl_rx_int.rx_bardec = core_tl_rx.rx_bardec;
        assign core_tl_rx_int.rx_mchit = core_tl_rx.rx_mchit;
        assign core_tl_rx_int.rx_err = core_tl_rx.rx_err;
        assign core_tl_rx.rx_masknp = core_tl_rx_int.rx_masknp;
        assign core_tl_rx.rx_wait = core_tl_rx_int.rx_wait;

        assign busy = 0;

    end else begin: rx_width_conv

        always_ff @(posedge core_clk) begin
            core_tl_rx.rx_masknp <= core_tl_rx_int.rx_masknp;
        end

        localparam BUF_PTR_WIDTH = $clog2(BUF_DEPTH);
        localparam BUF_DATA_WIDTH = (DATA_WIDTH > CORE_DATA_WIDTH) ? DATA_WIDTH : CORE_DATA_WIDTH;
        localparam SEG_NUM = (DATA_WIDTH > CORE_DATA_WIDTH) ? (DATA_WIDTH / CORE_DATA_WIDTH) : (CORE_DATA_WIDTH / DATA_WIDTH);
        localparam SEG_NUM_WIDTH = $clog2(SEG_NUM);

        logic [BUF_DEPTH-1:0] buf_sop;
        logic [BUF_DATA_WIDTH-1:0] buf_data [BUF_DEPTH-1:0];
        logic [BUF_DATA_WIDTH/32-1:0] buf_valid [BUF_DEPTH-1:0];
        logic [47:0] buf_bardec [BUF_DEPTH-1:0];
        logic [CORE_PF_NUM+7:0] buf_mchit [BUF_DEPTH-1:0];
        logic [7:0] buf_err [BUF_DEPTH-1:0];

        logic [BUF_PTR_WIDTH:0] buf_wptr;
        logic [BUF_PTR_WIDTH:0] buf_rptr;
        logic [BUF_PTR_WIDTH:0] buf_wptr_nxt;
        logic [BUF_PTR_WIDTH:0] buf_rptr_nxt;
        logic buf_vld;
        logic buf_full;
        logic [SEG_NUM_WIDTH-1:0] seg_ptr;

        assign buf_full = buf_wptr == (buf_rptr ^ {1'b1, {BUF_PTR_WIDTH{1'b0}}});
        assign buf_vld = buf_wptr != buf_rptr;

        always_ff @(posedge core_clk) begin
            buf_wptr <= buf_wptr_nxt;
            if (core_rst) begin
                buf_wptr <= 0;
            end
        end

        always_ff @(posedge core_clk2) begin
            buf_rptr <= buf_rptr_nxt;
            if (core_rst)
                buf_rptr <= 0;
        end

        always_ff @(posedge core_clk2) begin
            busy <= (DATA_WIDTH == CORE_DATA_WIDTH) ? 0 : buf_vld;
        end

        logic rx_vld_c;
        logic rx_rdy_c;
        logic rx_sop_c;
        logic rx_eop_c;
        logic [CORE_DATA_WIDTH-1:0] rx_data_c;
        logic [CORE_DATA_WIDTH/32-1:0] rx_valid_c;
        logic [47:0] rx_bardec_c;
        logic [CORE_PF_NUM+7:0] rx_mchit_c;
        logic [7:0] rx_err_c;

        logic rx_vld_r;
        logic rx_rdy_r;
        logic rx_sop_r;
        logic rx_eop_r;
        logic [CORE_DATA_WIDTH-1:0] rx_data_r;
        logic [CORE_DATA_WIDTH/32-1:0] rx_valid_r;
        logic [47:0] rx_bardec_r;
        logic [CORE_PF_NUM+7:0] rx_mchit_r;
        logic [7:0] rx_err_r;

        assign core_tl_rx.rx_wait = ~rx_rdy_c;
        assign rx_vld_c = |core_tl_rx.rx_valid;
        assign rx_sop_c = core_tl_rx.rx_sop;
        assign rx_eop_c = core_tl_rx.rx_eop;
        assign rx_data_c = core_tl_rx.rx_data;
        assign rx_valid_c = core_tl_rx.rx_valid;
        assign rx_bardec_c = core_tl_rx.rx_bardec;
        assign rx_mchit_c = core_tl_rx.rx_mchit;
        assign rx_err_c = core_tl_rx.rx_err;
        assign rx_rdy_r = ~buf_full;

        pcie_brg_reg_slice #(
            .MODE("BWD"),
            .WIDTH(1+1+CORE_DATA_WIDTH+CORE_DATA_WIDTH/32+48+CORE_PF_NUM+8+8)
        ) rx_reg_slice(
            .clk(core_clk),
            .rst(core_rst),
            .src_vld(rx_vld_c),
            .src_rdy(rx_rdy_c),
            .src_pld({rx_sop_c, rx_eop_c, rx_data_c, rx_valid_c, rx_bardec_c, rx_mchit_c, rx_err_c}),
            .dst_vld(rx_vld_r),
            .dst_rdy(rx_rdy_r),
            .dst_pld({rx_sop_r, rx_eop_r, rx_data_r, rx_valid_r, rx_bardec_r, rx_mchit_r, rx_err_r})
        );

        if (DATA_WIDTH < CORE_DATA_WIDTH) begin: rx_width_conv_down

            logic [SEG_NUM-1:0] buf_seg_eop [BUF_DEPTH-1:0];
            logic [SEG_NUM-1:0] seg_eop;

            assign core_tl_rx_int.rx_sop = buf_vld & buf_sop[buf_rptr[BUF_PTR_WIDTH-1:0]] & (&seg_ptr);
            assign core_tl_rx_int.rx_eop = buf_vld & buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr];
            assign core_tl_rx_int.rx_data = buf_data[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr*DATA_WIDTH+:DATA_WIDTH];
            assign core_tl_rx_int.rx_valid = buf_vld ? (buf_valid[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr*(DATA_WIDTH/32)+:(DATA_WIDTH/32)]) : 0;
            assign core_tl_rx_int.rx_bardec = buf_bardec[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_mchit = buf_mchit[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_err[1:0] = core_tl_rx_int.rx_eop ? buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][1:0] : 0;
            assign core_tl_rx_int.rx_err[7] = core_tl_rx_int.rx_eop ? buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][7] : 0;
            assign core_tl_rx_int.rx_err[2] = buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][2];
            assign core_tl_rx_int.rx_err[6:3] = 0;

            integer i;
            always_comb begin
                for (i=0; i<SEG_NUM; i=i+1) begin
                    if (i == 0)
                        seg_eop[i] = 1;
                    else
                        seg_eop[i] = ~|rx_valid_r[(i-1)*(DATA_WIDTH/32)+:(DATA_WIDTH/32)];
                end
                if (~rx_eop_r)
                    seg_eop = 0;
            end

            always_comb begin
                buf_wptr_nxt = buf_wptr;
                if (rx_vld_r & rx_rdy_r)
                    buf_wptr_nxt = buf_wptr+1;
            end

            always_ff @(posedge core_clk) begin
                if (rx_vld_r & rx_rdy_r) begin
                    buf_sop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_sop_r;
                    buf_seg_eop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= seg_eop;
                    buf_data[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_data_r;
                    buf_valid[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_valid_r;
                    buf_bardec[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_bardec_r;
                    buf_mchit[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_mchit_r;
                    buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_err_r;
                end
            end

            always_comb begin
                buf_rptr_nxt = buf_rptr;
                if ((|core_tl_rx_int.rx_valid) & ~core_tl_rx_int.rx_wait) begin
                    if ((seg_ptr == 0) | buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr])
                        buf_rptr_nxt = buf_rptr+1;
                end
            end

            always_ff @(posedge core_clk2) begin
                if ((|core_tl_rx_int.rx_valid) & ~core_tl_rx_int.rx_wait) begin
                    if (buf_seg_eop[buf_rptr[BUF_PTR_WIDTH-1:0]][seg_ptr]) begin
                        seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                    end else begin
                        seg_ptr <= seg_ptr-1;
                    end
                end
                if (core_rst) begin
                    seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                end
            end

        end else begin: rx_width_conv_up

            logic [BUF_DEPTH-1:0] buf_eop;
            logic [SEG_NUM-1:0] buf_seg_vld [BUF_DEPTH-1:0];
            logic rx_err_bit2_seen;

            assign core_tl_rx_int.rx_sop = buf_vld & buf_sop[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_eop = buf_vld & buf_eop[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_data = buf_data[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_bardec = buf_bardec[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_mchit = buf_mchit[buf_rptr[BUF_PTR_WIDTH-1:0]];
            assign core_tl_rx_int.rx_err[1:0] = buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][1:0];
            assign core_tl_rx_int.rx_err[7] = buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][7];
            assign core_tl_rx_int.rx_err[2] = buf_err[buf_rptr[BUF_PTR_WIDTH-1:0]][2];
            assign core_tl_rx_int.rx_err[6:3] = 0;

            integer j;
            always_comb begin
                for (j=0; j<SEG_NUM; j=j+1) begin
                    if (buf_vld & buf_seg_vld[buf_rptr[BUF_PTR_WIDTH-1:0]][j])
                        core_tl_rx_int.rx_valid[j*(CORE_DATA_WIDTH/32)+:(CORE_DATA_WIDTH/32)] = buf_valid[buf_rptr[BUF_PTR_WIDTH-1:0]][j*(CORE_DATA_WIDTH/32)+:(CORE_DATA_WIDTH/32)];
                    else
                        core_tl_rx_int.rx_valid[j*(CORE_DATA_WIDTH/32)+:(CORE_DATA_WIDTH/32)] = 0;
                end
            end

            always_comb begin
                buf_wptr_nxt = buf_wptr;
                if (rx_vld_r & rx_rdy_r) begin
                    if ((seg_ptr == 0) | rx_eop_r)
                        buf_wptr_nxt = buf_wptr+1;
                end
            end

            always_ff @(posedge core_clk) begin
                if (rx_vld_r & rx_rdy_r) begin
                    if ((seg_ptr == 0) | rx_eop_r) begin
                        seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                        buf_seg_vld[buf_wptr[BUF_PTR_WIDTH-1:0]] <= {SEG_NUM{1'b1}} << seg_ptr;
                        buf_eop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_eop_r;
                    end else begin
                        seg_ptr <= seg_ptr-1;
                    end
                    if (&seg_ptr) begin
                        buf_sop[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_eop_r;
                    end
                    buf_data[buf_wptr[BUF_PTR_WIDTH-1:0]][seg_ptr*CORE_DATA_WIDTH+:CORE_DATA_WIDTH] <= rx_data_r;
                    buf_valid[buf_wptr[BUF_PTR_WIDTH-1:0]][seg_ptr*(CORE_DATA_WIDTH/32)+:(CORE_DATA_WIDTH/32)] <= rx_valid_r;
                    buf_bardec[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_bardec_r;
                    buf_mchit[buf_wptr[BUF_PTR_WIDTH-1:0]] <= rx_mchit_r;
                    buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]][1:0] <= rx_eop_r ? rx_err_r[1:0] : 0;
                    buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]][7] <= rx_eop_r ? rx_err_r[7] : 0;
                    buf_err[buf_wptr[BUF_PTR_WIDTH-1:0]][2] <= (&seg_ptr) ? rx_err_r[2] : (rx_err_bit2_seen | rx_err_r[2]);
                    rx_err_bit2_seen <= (&seg_ptr) ? 0 : (rx_err_bit2_seen | rx_err_r[2]);
                end
                if (core_rst) begin
                    seg_ptr <= {SEG_NUM_WIDTH{1'b1}};
                end
            end

            always_comb begin
                buf_rptr_nxt = buf_rptr;
                if ((|core_tl_rx_int.rx_valid) & ~core_tl_rx_int.rx_wait)
                    buf_rptr_nxt = buf_rptr+1;
            end

        end

    end

endgenerate

endmodule
