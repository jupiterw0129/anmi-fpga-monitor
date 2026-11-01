`include "pcie_brg_def.svh"

module pcie_brg_cfg_status#(
    parameter SYNC_CLOCK = 1,
    parameter VF_NUM = 252
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_rst,

    core_tl_access_if.slv core_tl_access,
    input logic [1:0] pl_equ_phase,
    input logic [4:0] tl_ltssm,
    input logic pl_link_up,
    input logic [95:0] core_tl_tx_credits,

    cfg_status_if.mst cfg_status,
    output logic [VF_NUM-1:0] core_tl_msix_vf_enable,
    output logic [VF_NUM-1:0] core_tl_msix_vf_mask,
    output logic [7:0] bus_num,
    output logic [4:0] dev_num
);

logic [1:0] phy_link_status_nxt;
logic [2:0] tl_negotiated_width_nxt;
logic [1:0] tl_current_speed_nxt;
logic [5:0] tl_ltssm_state_nxt;
logic [3:0] tfc_nph_av_nxt;
logic [3:0] tfc_npd_av_nxt;
logic [1:0] pl_link_down_sync2user;

assign core_tl_msix_vf_enable = 0;// todo
assign core_tl_msix_vf_mask = 0;
assign cfg_status.cfg_phy_link_down = pl_link_down_sync2user[1];

always_comb begin// todo, note clock to sync
    phy_link_status_nxt = {2{pl_link_up}};
end

always_comb begin
    tl_negotiated_width_nxt = 0;
    case (core_tl_access.tl_cfg_negotiated_width)
        4'b0001: tl_negotiated_width_nxt = 3'b000;
        4'b0010: tl_negotiated_width_nxt = 3'b001;
        4'b0100: tl_negotiated_width_nxt = 3'b010;
        4'b1000: tl_negotiated_width_nxt = 3'b011;
    endcase
end

always_comb begin
    tl_current_speed_nxt = 0;
    case (core_tl_access.tl_cfg_current_link_speed)
        3'b001: tl_current_speed_nxt = 2'b00;
        3'b010: tl_current_speed_nxt = 2'b01;
        3'b011: tl_current_speed_nxt = 2'b10;
        3'b100: tl_current_speed_nxt = 2'b11;
    endcase
end

always_comb begin
    tl_ltssm_state_nxt = 0;
    case (tl_ltssm)
        5'h00: tl_ltssm_state_nxt = 6'h00;// detect.quiet
        5'h01: tl_ltssm_state_nxt = 6'h01;// detect.active
        5'h02: tl_ltssm_state_nxt = 6'h02;// polling.active
        5'h03: tl_ltssm_state_nxt = 6'h03;// polling.compliance
        5'h04: tl_ltssm_state_nxt = 6'h04;// polling.configuration
        5'h05: tl_ltssm_state_nxt = 6'h05;// config.linkwidthstart
        5'h06: tl_ltssm_state_nxt = 6'h06;// config.linkwidthacccept
        5'h07: tl_ltssm_state_nxt = 6'h08;// config.lanenumwait
        5'h08: tl_ltssm_state_nxt = 6'h07;// config.lanenumaccept
        5'h09: tl_ltssm_state_nxt = 6'h09;// config.complete
        5'h0a: tl_ltssm_state_nxt = 6'h0a;// config.idle
        5'h0b: tl_ltssm_state_nxt = 6'h0b;// recover.receiverlock
        5'h0c: begin// recover.equalization
            case (pl_equ_phase)// todo
                2'b00: tl_ltssm_state_nxt = 6'h28;
                2'b01: tl_ltssm_state_nxt = 6'h29;
                2'b10: tl_ltssm_state_nxt = 6'h2a;
                2'b11: tl_ltssm_state_nxt = 6'h2b;
            endcase
        end
        5'h0d: tl_ltssm_state_nxt = 6'h0c;// recover.speed
        5'h0e: tl_ltssm_state_nxt = 6'h0d;// recover.receiverconfig
        5'h0f: tl_ltssm_state_nxt = 6'h0e;// recover.idle
        5'h10: tl_ltssm_state_nxt = 6'h10;// l0
        5'h11: tl_ltssm_state_nxt = 6'h11;// l0s *add this state
        5'h12: tl_ltssm_state_nxt = 6'h17;// l1.entry
        5'h13: tl_ltssm_state_nxt = 6'h18;// l1.idle
        5'h14: tl_ltssm_state_nxt = 6'h00;// l2.idle/l2.transmit wake *should not entry this state
        5'h15: tl_ltssm_state_nxt = 6'h00;// reserved
        5'h16: tl_ltssm_state_nxt = 6'h20;// disable
        5'h17: tl_ltssm_state_nxt = 6'h21;// loopback.entry
        5'h18: tl_ltssm_state_nxt = 6'h22;// loopback.active
        5'h19: tl_ltssm_state_nxt = 6'h23;// loopback.exit
        5'h1a: tl_ltssm_state_nxt = 6'h27;// hotreset
    endcase
end

always_comb begin
    tfc_nph_av_nxt = 0;
    if ((core_tl_tx_credits[59:48] >> 4) != 0)
        tfc_nph_av_nxt = 4'b1111;
    else
        tfc_nph_av_nxt = core_tl_tx_credits[51:48];
end

always_comb begin
    tfc_npd_av_nxt = 0;
    if ((core_tl_tx_credits[47:32] >> 4) != 0)
        tfc_npd_av_nxt = 4'b1111;
    else
        tfc_npd_av_nxt = core_tl_tx_credits[35:32];
end

always_ff @(posedge user_clk or posedge user_rst) begin
    if (user_rst)
        pl_link_down_sync2user <= 0;
    else
        pl_link_down_sync2user <= {pl_link_down_sync2user[0], ~pl_link_up};
end

generate
    if (SYNC_CLOCK) begin: cfg_status_no_cdc// FIXME signal from pinshare
        pcie_brg_cdc_sync #(.REG_IN(1), .WIDTH(2)) cdc_sync_phy_link_status(.src_clk(core_clk), .src_in(phy_link_status_nxt), .dst_clk(user_clk), .dst_out(cfg_status.cfg_phy_link_status));
        assign cfg_status.cfg_max_payload = core_tl_access.tl_cfg_max_payload_size;
        assign cfg_status.cfg_max_read_req = core_tl_access.tl_cfg_max_read_request_size;
        assign cfg_status.cfg_function_status = 0;
        assign cfg_status.cfg_vf_status = 0;
        assign cfg_status.cfg_function_power_state = 0;
        assign cfg_status.cfg_vf_power_state = 0;
        assign cfg_status.cfg_link_power_state = 0;
        assign cfg_status.cfg_local_error_out = 0;
        assign cfg_status.cfg_local_error_valid = 0;
        assign cfg_status.cfg_rx_pm_state = 0;
        assign cfg_status.cfg_tx_pm_state = 0;
        pcie_brg_cdc_bus_sync #(.WIDTH(6)) cdc_bus_sync_ltssm_state(.src_clk(core_clk), .src_rst(core_rst), .src_in(tl_ltssm_state_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_ltssm_state));
        assign cfg_status.cfg_rcb_status = {4{core_tl_access.tl_cfg_read_completion_boundary}};
        assign cfg_status.cfg_dpa_substate_change = 0;
        assign cfg_status.cfg_obff_enable = 0;
        assign cfg_status.cfg_pl_status_change = 0;
        assign cfg_status.cfg_tph_requester_enable = 0;
        assign cfg_status.cfg_tph_st_mode = 0;
        assign cfg_status.cfg_vf_tph_requester_enable = 0;
        assign cfg_status.cfg_vf_tph_st_mode = 0;
        always_ff @(posedge user_clk) begin
            cfg_status.cfg_negotiated_width <= tl_negotiated_width_nxt;
            cfg_status.cfg_current_speed <= tl_current_speed_nxt;
            cfg_status.pcie_tfc_nph_av <= tfc_nph_av_nxt;
            cfg_status.pcie_tfc_npd_av <= tfc_npd_av_nxt;
        end

        assign {bus_num, dev_num} = core_tl_access.tl_cfg_busdev;

    end else begin: cfg_status_cdc
        pcie_brg_cdc_sync #(.REG_IN(1), .WIDTH(2)) cdc_sync_phy_link_status(.src_clk(core_clk), .src_in(phy_link_status_nxt), .dst_clk(user_clk), .dst_out(cfg_status.cfg_phy_link_status));
        pcie_brg_cdc_bus_sync #(.WIDTH(3)) cdc_bus_sync_negotiated_width(.src_clk(core_clk), .src_rst(core_rst), .src_in(tl_negotiated_width_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_negotiated_width));
        pcie_brg_cdc_bus_sync #(.WIDTH(2)) cdc_bus_sync_current_speed(.src_clk(core_clk), .src_rst(core_rst), .src_in(tl_current_speed_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_current_speed));
        pcie_brg_cdc_bus_sync #(.WIDTH(2)) cdc_bus_sync_mps(.src_clk(core_clk), .src_rst(core_rst), .src_in(core_tl_access.tl_cfg_max_payload_size), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_max_payload));
        pcie_brg_cdc_bus_sync #(.WIDTH(3)) cdc_bus_sync_mrrs(.src_clk(core_clk), .src_rst(core_rst), .src_in(core_tl_access.tl_cfg_max_read_request_size), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_max_read_req));
        assign cfg_status.cfg_function_status = 0;
        assign cfg_status.cfg_vf_status = 0;
        assign cfg_status.cfg_function_power_state = 0;
        assign cfg_status.cfg_vf_power_state = 0;
        assign cfg_status.cfg_link_power_state = 0;
        assign cfg_status.cfg_local_error_out = 0;
        assign cfg_status.cfg_local_error_valid = 0;
        assign cfg_status.cfg_rx_pm_state = 0;
        assign cfg_status.cfg_tx_pm_state = 0;
        pcie_brg_cdc_bus_sync #(.WIDTH(6)) cdc_bus_sync_ltssm_state(.src_clk(core_clk), .src_rst(core_rst), .src_in(tl_ltssm_state_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.cfg_ltssm_state));
        pcie_brg_cdc_sync #(.REG_IN(1), .WIDTH(4)) cdc_sync_rcb(.src_in({4{core_tl_access.tl_cfg_read_completion_boundary}}), .dst_clk(user_clk), .dst_out(cfg_status.cfg_rcb_status));
        assign cfg_status.cfg_dpa_substate_change = 0;
        assign cfg_status.cfg_obff_enable = 0;
        assign cfg_status.cfg_pl_status_change = 0;
        assign cfg_status.cfg_tph_requester_enable = 0;
        assign cfg_status.cfg_tph_st_mode = 0;
        assign cfg_status.cfg_vf_tph_requester_enable = 0;
        assign cfg_status.cfg_vf_tph_st_mode = 0;
        pcie_brg_cdc_bus_sync #(.WIDTH(4)) cdc_bus_sync_nph_av(.src_clk(core_clk), .src_rst(core_rst), .src_in(tfc_nph_av_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.pcie_tfc_nph_av));
        pcie_brg_cdc_bus_sync #(.WIDTH(4)) cdc_bus_sync_npd_av(.src_clk(core_clk), .src_rst(core_rst), .src_in(tfc_npd_av_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_status.pcie_tfc_npd_av));

        pcie_brg_cdc_bus_sync #(.WIDTH(13)) cdc_bus_sync_bus_dev(.src_clk(core_clk), .src_rst(core_rst), .src_in(core_tl_access.tl_cfg_busdev), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out({bus_num, dev_num}));

    end
endgenerate

endmodule
