`include "pcie_brg_def.svh"

module pcie_brg_int#(
    parameter SYNC_CLOCK = 1,
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter MSI_EN = 1,
    parameter MSIX_EN = 1
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_rst,

    input logic ari_cap,
    input logic [7:0] bus_num,
    input logic [4:0] dev_num,

    cfg_legacy_int_if.slv cfg_legacy_int,
    cfg_msi_int_if.slv cfg_msi_int,
    cfg_msix_int_if.slv cfg_msix_int,
    core_tl_int_if.mst core_tl_int,
    core_tl_cfg_msix_if.slv core_tl_cfg_msix,
    input logic [VF_NUM-1:0] core_tl_msix_vf_enable,
    input logic [VF_NUM-1:0] core_tl_msix_vf_mask,

    input  logic msix_rdy,
    output logic msix_vld,
    output pcie_tlp_header_t msix_header,
    output logic [31:0] msix_data,

    output logic busy
);

assign core_tl_int.tl_int_pincontrol = 0;// not support rp or switch
assign core_tl_int.tl_int_vfmsi_enable_mask_sel = 0;

// intx
// plda core send intx message on rise or false edge of interrupt status internally, so ack can not be derived
logic [PF_NUM-1:0] cfg_int_pend_r;
logic [3:0] [3:0] cfg_int_dly;
logic [3:0] cfg_int_rise;
logic [3:0] cfg_int_fall;

integer i0;
always_ff @(posedge user_clk) begin
    if (user_rst) begin
        cfg_int_pend_r <= 0;
        cfg_legacy_int.cfg_interrupt_sent <= 0;
        cfg_int_dly <= 0;
        cfg_int_rise <= 0;
        cfg_int_fall <= 0;
    end else begin
        cfg_int_pend_r <= cfg_legacy_int.cfg_interrupt_pending;
        cfg_legacy_int.cfg_interrupt_sent <= (|cfg_int_rise) | (|cfg_int_fall);
        for (i0=0; i0<4; i0=i0+1) begin
            cfg_int_dly[i0] <= {cfg_int_dly[i0], cfg_legacy_int.cfg_interrupt_int[i0]};
            cfg_int_rise[i0] <= cfg_int_dly[i0][3] & ~cfg_int_dly[i0][2];
            cfg_int_fall[i0] <= ~cfg_int_dly[i0][3] & cfg_int_dly[i0][2];
        end
    end
end

generate
    if (SYNC_CLOCK) begin: intx_no_cdc
        assign core_tl_int.tl_int_status = cfg_int_pend_r;

    end else begin: intx_cdc
        pcie_brg_cdc_sync # (
            .REG_IN(0),
            .WIDTH(PF_NUM)
        ) cdc_sync_intx_status(
            .src_clk(user_clk),
            .src_in(cfg_int_pend_r),
            .dst_clk(core_clk),
            .dst_out(core_tl_int.tl_int_status)
        );
    end
endgenerate

// msi
logic msi_int_sent_c;
generate
    if (MSI_EN) begin: msi_enable
        assign cfg_msi_int.cfg_interrupt_msi_fail = 0;// FIXME check enable and PVM

        logic cfg_msi_int_req_or;
        logic cfg_msi_int_req_or_d1;
        logic cfg_msi_int_req_nxt;
        logic [4:0] cfg_msi_int_num_nxt;

        assign cfg_msi_int_req_or = |cfg_msi_int.cfg_interrupt_msi_int;
        assign cfg_msi_int_req_nxt = cfg_msi_int_req_or & ~cfg_msi_int_req_or_d1;

        integer i1;
        always_comb begin
            cfg_msi_int_num_nxt = 0;
            for (i1=0; i1<32; i1=i1+1) begin
                cfg_msi_int_num_nxt = cfg_msi_int_num_nxt | ({5{cfg_msi_int.cfg_interrupt_msi_int[i1]}} & i1);
            end
        end

        always_ff @(posedge user_clk) begin
            if (user_rst)
                cfg_msi_int_req_or_d1 <= 0;
            else
                cfg_msi_int_req_or_d1 <= cfg_msi_int_req_or;
        end

        if (SYNC_CLOCK) begin: msi_enable_no_cdc
            logic [PF_NUM-1:0] pf_msi_mask_update;
            assign msi_int_sent_c = (|core_tl_int.tl_int_msiack) | core_tl_int.tl_int_vfmsiack;
            // pf
            genvar i2;
            for (i2=0; i2<PF_NUM; i2=i2+1) begin: msi_enable_no_cdc_pf
                // req
                always_ff @(posedge user_clk) begin
                    core_tl_int.tl_int_msireq[i2] <= cfg_msi_int_req_nxt & (cfg_msi_int.cfg_interrupt_msi_function_number == i2);
                    core_tl_int.tl_int_msinum[i2*5+:5] <= cfg_msi_int_num_nxt;
                    if (user_rst) begin
                        core_tl_int.tl_int_msireq[i2] <= 0;
                    end
                end
                // enable
                always_ff @(posedge user_clk) begin
                    cfg_msi_int.cfg_interrupt_msi_enable[i2] <= core_tl_int.tl_int_msi_enable[i2];
                    cfg_msi_int.cfg_interrupt_msi_mmenable[i2*3+:3] <= core_tl_int.tl_int_msi_multi_enable[i2*3+:3];
                end
                // pending
                always_ff @(posedge user_clk) begin
                    if (cfg_msi_int.cfg_interrupt_msi_pending_status_data_enable & (cfg_msi_int.cfg_interrupt_msi_pending_status_function_number == i2)) begin
                        core_tl_int.tl_int_pf_msi_pending[i2] <= cfg_msi_int.cfg_interrupt_msi_pending_status;
                    end
                    if (user_rst) begin
                        core_tl_int.tl_int_pf_msi_pending[i2] <= 0;
                    end
                end
                // mask
                logic [31:0] core_tl_int_pf_msi_mask_c;
                logic [31:0] core_tl_int_pf_msi_mask_r;
                assign core_tl_int_pf_msi_mask_c = core_tl_int.tl_int_pf_msi_mask[i2];
                always_ff @(posedge user_clk) begin
                    core_tl_int_pf_msi_mask_r <= core_tl_int_pf_msi_mask_c;
                    pf_msi_mask_update[i2] <= core_tl_int_pf_msi_mask_c != core_tl_int_pf_msi_mask_r;
                end
            end
            // mask
            always_ff @(posedge user_clk) begin
                cfg_msi_int.cfg_interrupt_msi_mask_update <= |pf_msi_mask_update;
                cfg_msi_int.cfg_interrupt_msi_data <= core_tl_int.tl_int_pf_msi_mask[cfg_msi_int.cfg_interrupt_msi_select];
                if (user_rst)
                    cfg_msi_int.cfg_interrupt_msi_mask_update <= 0;
            end

            // vf
            // req
            always_ff @(posedge user_clk) begin
                core_tl_int.tl_int_vfmsireq <= cfg_msi_int_req_nxt & ~(cfg_msi_int.cfg_interrupt_msi_function_number < PF_NUM);
                core_tl_int.tl_int_vfmsinum <= cfg_msi_int_num_nxt;
                core_tl_int.tl_int_vfmsifid[15:8] <= 0;
                core_tl_int.tl_int_vfmsifid[7:0] <= cfg_msi_int.cfg_interrupt_msi_function_number - PF_NUM;
                if (user_rst) begin
                    core_tl_int.tl_int_vfmsireq <= 0;
                end
            end

        end else begin: msi_enable_cdc
            logic cfg_msi_int_src_send_r;
            logic [7:0] cfg_msi_int_func_r;
            logic [4:0] cfg_msi_int_num_r;
            logic cfg_msi_int_src_recv;
            logic cfg_msi_int_src_recv_d1;
            always_ff @(posedge user_clk) begin
                if (cfg_msi_int_req_nxt) begin
                    cfg_msi_int_src_send_r <= 1;
                    cfg_msi_int_func_r <= cfg_msi_int.cfg_interrupt_msi_function_number;
                    cfg_msi_int_num_r <= cfg_msi_int_num_nxt;
                end else if (cfg_msi_int_src_recv)
                    cfg_msi_int_src_send_r <= 0;
                if (user_rst)
                    cfg_msi_int_src_send_r <= 0;
            end

            assign msi_int_sent_c = ~cfg_msi_int_src_recv & cfg_msi_int_src_recv_d1;
            always_ff @(posedge user_clk) begin
                if (user_rst)
                    cfg_msi_int_src_recv_d1 <= 0;
                else
                    cfg_msi_int_src_recv_d1 <= cfg_msi_int_src_recv;
            end

            logic core_tl_int_msi_req;
            logic core_tl_int_msi_ack;
            logic [7:0] core_tl_int_msi_func;
            logic [4:0] core_tl_int_msi_num;
            logic core_tl_int_msi_req_d1;

            pcie_brg_cdc_handshake #(
              .WIDTH(8+5)
            ) cdc_handshake_msi_int(
              .src_clk(user_clk),
              .src_in({cfg_msi_int_func_r, cfg_msi_int_num_r}),
              .src_send(cfg_msi_int_src_send_r),
              .src_recv(cfg_msi_int_src_recv),
              .dst_clk(core_clk),
              .dst_out({core_tl_int_msi_func, core_tl_int_msi_num}),
              .dst_req(core_tl_int_msi_req),
              .dst_ack(core_tl_int_msi_ack)
            );

            always_ff @(posedge core_clk) begin
                if (core_rst)
                    core_tl_int_msi_req_d1 <= 0;
                else
                    core_tl_int_msi_req_d1 <= core_tl_int_msi_req;
            end

            always_ff @(posedge core_clk) begin
                if (core_rst)
                    core_tl_int_msi_ack <= 0;
                else if ((|core_tl_int.tl_int_msiack) | core_tl_int.tl_int_vfmsiack)
                    core_tl_int_msi_ack <= 1;
                else if (~core_tl_int_msi_req)
                    core_tl_int_msi_ack <= 0;
            end

            // pf
            logic [PF_NUM-1:0] pf_msi_mask_update;
            genvar i3;
            for (i3=0; i3<PF_NUM; i3=i3+1) begin: msi_enable_cdc_pf
                // req
                always_ff @(posedge core_clk) begin
                    core_tl_int.tl_int_msireq[i3] <= core_tl_int_msi_req & ~core_tl_int_msi_req_d1 & (core_tl_int_msi_func == i3);
                    if (core_rst) begin
                        core_tl_int.tl_int_msireq[i3] <= 0;
                    end
                end
                assign core_tl_int.tl_int_msinum[i3*5+:5] = core_tl_int_msi_num;
                // enable
                pcie_brg_cdc_sync # (
                    .REG_IN(0),
                    .WIDTH(4)
                ) cdc_sync_msi_enable(
                    .src_clk(core_clk),
                    .src_in({core_tl_int.tl_int_msi_enable[i3], core_tl_int.tl_int_msi_multi_enable[i3*3+:3]}),
                    .dst_clk(user_clk),
                    .dst_out({cfg_msi_int.cfg_interrupt_msi_enable[i3], cfg_msi_int.cfg_interrupt_msi_mmenable[i3*3+:3]})
                );
                // pending
                logic cfg_msi_int_pending_status_r;
                always_ff @(posedge user_clk) begin
                    if (cfg_msi_int.cfg_interrupt_msi_pending_status_data_enable & (cfg_msi_int.cfg_interrupt_msi_pending_status_function_number == i3)) begin
                        cfg_msi_int_pending_status_r <= cfg_msi_int.cfg_interrupt_msi_pending_status;
                    end
                    if (user_rst) begin
                        cfg_msi_int_pending_status_r <= 0;
                    end
                end
                pcie_brg_cdc_sync # (
                    .REG_IN(0),
                    .WIDTH(32)
                ) cdc_sync_pf_msi_pending(
                    .src_clk(user_clk),
                    .src_in(cfg_msi_int_pending_status_r),
                    .dst_clk(core_clk),
                    .dst_out(core_tl_int.tl_int_pf_msi_pending[i3])
                );
                // mask
                logic [31:0] core_tl_int_pf_msi_mask_c;
                logic [31:0] core_tl_int_pf_msi_mask_r;
                assign core_tl_int_pf_msi_mask_c = core_tl_int.tl_int_pf_msi_mask[i3];
                always_ff @(posedge user_clk) begin
                    core_tl_int_pf_msi_mask_r <= core_tl_int_pf_msi_mask_c;
                    pf_msi_mask_update[i3] <= core_tl_int_pf_msi_mask_c != core_tl_int_pf_msi_mask_r;
                end
            end
            // mask
            logic [PF_NUM-1:0] [31:0] core_tl_int_pf_msi_mask;
            pcie_brg_cdc_sync # (
                .REG_IN(0),
                .WIDTH(PF_NUM*32)
            ) cdc_sync_pf_msi_mask(
                .src_clk(core_clk),
                .src_in(core_tl_int.tl_int_pf_msi_mask),
                .dst_clk(user_clk),
                .dst_out(core_tl_int_pf_msi_mask)
            );
            always_ff @(posedge user_clk) begin
                cfg_msi_int.cfg_interrupt_msi_mask_update <= |pf_msi_mask_update;
                cfg_msi_int.cfg_interrupt_msi_data <= core_tl_int_pf_msi_mask[cfg_msi_int.cfg_interrupt_msi_select];
                if (user_rst)
                    cfg_msi_int.cfg_interrupt_msi_mask_update <= 0;
            end

            // vf
            // req
            always_ff @(posedge user_clk) begin
                core_tl_int.tl_int_vfmsireq <= core_tl_int_msi_req & ~core_tl_int_msi_req_d1 & ~(core_tl_int_msi_func < PF_NUM);
                core_tl_int.tl_int_vfmsifid[15:8] <= 0;
                core_tl_int.tl_int_vfmsifid[7:0] <= core_tl_int_msi_func - PF_NUM;
                if (user_rst) begin
                    core_tl_int.tl_int_vfmsireq <= 0;
                end
            end
            assign core_tl_int.tl_int_vfmsinum = core_tl_int_msi_num;
        end

    end else begin: msi_disable
        assign cfg_msi_int.cfg_interrupt_msi_enable = 0;
        assign cfg_msi_int.cfg_interrupt_msi_mmenable = 0;
        assign cfg_msi_int.cfg_interrupt_msi_fail = 0;
        assign cfg_msi_int.cfg_interrupt_msi_mask_update = 0;
        assign cfg_msi_int.cfg_interrupt_msi_data = 0;
        assign core_tl_int.tl_int_msireq = 0;
        assign core_tl_int.tl_int_msinum = 0;
        assign core_tl_int.tl_int_pf_msi_pending = 0;
        assign core_tl_int.tl_int_vfmsireq = 0;
        assign core_tl_int.tl_int_vfmsinum = 0;
        assign core_tl_int.tl_int_vfmsifid = 0;
        assign msi_int_sent_c = 0;
    end
endgenerate

// msix
assign cfg_msix_int.cfg_interrupt_msix_vec_pending_status = 0;

logic msix_int_sent_c;
logic msix_int;
logic msix_int_d1;
logic msix_int_req;
logic msix_int_ack;
pcie_tlp_header_t msix_int_header;
logic [31:0] msix_int_data;
pcie_tlp_header_t msix_int_header_nxt;
logic msix_int_header_4dw_nxt;
logic [15:0] msix_int_bdf_num_c;

assign msix_int_header_4dw_nxt = |cfg_msix_int.cfg_interrupt_msix_addr[63:32];
assign msix_int = cfg_msix_int.cfg_interrupt_msix_int;

// same pf num
pcie_brg_bdf_enc#(
    .CFG_PF_NUM(PF_NUM),
    .CORE_PF_NUM(PF_NUM)
) msix_int_bdf_map(
    .ari_cap(ari_cap),
    .bus_num(bus_num),
    .dev_num(dev_num),
    .func_num(cfg_msi_int.cfg_interrupt_msi_function_number),
    .bdf_num(msix_int_bdf_num_c)
);

always_comb begin
    msix_int_header_nxt = 0;
    msix_int_header_nxt.dw0[31:24] = msix_int_header_4dw_nxt ? 8'b011_00000 : 8'b010_00000;
    msix_int_header_nxt.dw0[9:0] = 1;
    msix_int_header_nxt.dw1[31:16] = msix_int_bdf_num_c;
    msix_int_header_nxt.dw1[15:8] = 0;// FIXME where is tag from
    msix_int_header_nxt.dw1[7:0] = 8'hff;
    if (msix_int_header_4dw_nxt)
        {msix_int_header_nxt.dw2, msix_int_header_nxt.dw3} = {cfg_msix_int.cfg_interrupt_msix_addr[63:2], 2'b0};
    else
        msix_int_header_nxt.dw2 = {cfg_msix_int.cfg_interrupt_msix_addr[31:2], 2'b0};
end

always_ff @(posedge user_clk) begin
    msix_int_d1 <= msix_int;
    if (msix_int & ~msix_int_d1) begin
        msix_int_req <= 1;
        msix_int_header <= msix_int_header_nxt;
        msix_int_data <= cfg_msix_int.cfg_interrupt_msix_data;
    end else if (msix_int_ack) begin
        msix_int_req <= 0;
    end
    if (user_rst) begin
        msix_int_d1 <= 0;
        msix_int_req <= 0;
    end
end

generate
    if (MSIX_EN) begin: msix_enable
        assign msix_vld = msix_int_req;
        assign msix_header = msix_int_header;
        assign msix_data = msix_int_data;
        assign msix_int_ack = msix_rdy;
        assign msix_int_sent_c = msix_int_req & msix_int_ack;

        if (SYNC_CLOCK) begin: msix_enable_no_cdc
            assign cfg_msix_int.cfg_interrupt_msix_enable = core_tl_cfg_msix.tl_cfg_msix_enable;
            assign cfg_msix_int.cfg_interrupt_msix_mask = core_tl_cfg_msix.tl_cfg_msix_function_mask;
            assign cfg_msix_int.cfg_interrupt_msix_vf_enable = core_tl_msix_vf_enable;
            assign cfg_msix_int.cfg_interrupt_msix_vf_mask = core_tl_msix_vf_mask;

        end else begin: msix_enable_cdc
            pcie_brg_cdc_sync # (
                .REG_IN(0),
                .WIDTH(PF_NUM+PF_NUM+VF_NUM+VF_NUM)
            ) cdc_sync_msix_enable_mask(
                .src_clk(core_clk),
                .src_in({core_tl_cfg_msix.tl_cfg_msix_enable, core_tl_cfg_msix.tl_cfg_msix_function_mask, core_tl_msix_vf_enable, core_tl_msix_vf_mask}),
                .dst_clk(user_clk),
                .dst_out({cfg_msix_int.cfg_interrupt_msix_enable, cfg_msix_int.cfg_interrupt_msix_mask, cfg_msix_int.cfg_interrupt_msix_vf_enable, cfg_msix_int.cfg_interrupt_msix_vf_mask})
            );
        end

    end else begin: msix_disable
        assign msix_vld = 0;
        assign msix_header = 0;
        assign msix_data = 0;
        assign msix_int_ack = 0;
        assign msix_int_sent_c = 0;
    end
endgenerate

always_ff @(posedge user_clk) begin
    if (user_rst)
        cfg_msi_int.cfg_interrupt_msi_sent <= 0;
    else
        cfg_msi_int.cfg_interrupt_msi_sent <= msi_int_sent_c | msix_int_sent_c;
end

// only msix
assign busy = msix_vld;

endmodule
