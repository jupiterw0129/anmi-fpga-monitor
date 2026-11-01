`include "pcie_brg_def.svh"

module pcie_brg_cfg_flow_ctrl #(
    parameter SYNC_CLOCK = 1
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_rst,

    input logic [95:0] core_tl_tx_credits,
    cfg_fc_if.mst cfg_fc
);

logic [31:0] credits_p;
logic [31:0] credits_np;
logic [31:0] credits_cpl;

logic [7:0]  cfg_fc_ph_nxt;
logic [11:0] cfg_fc_pd_nxt;
logic [7:0]  cfg_fc_nph_nxt;
logic [11:0] cfg_fc_npd_nxt;
logic [7:0]  cfg_fc_cplh_nxt;
logic [11:0] cfg_fc_cpld_nxt;

assign {credits_cpl, credits_np, credits_p} = core_tl_tx_credits;

always_comb begin
    cfg_fc_ph_nxt   = credits_p[27]   ? 8'h80   : ((credits_p[26:16] > 8'h7f)     ? 8'h7f   : credits_p[26:16]);
    cfg_fc_pd_nxt   = credits_p[15]   ? 12'h800 : ((credits_p[14:0]  > 12'h7ff)   ? 12'h7ff : credits_p[14:0]);
    cfg_fc_nph_nxt  = credits_np[27]  ? 8'h80   : ((credits_np[26:16] > 8'h7f)    ? 8'h7f   : credits_np[26:16]);
    cfg_fc_npd_nxt  = credits_np[15]  ? 12'h800 : ((credits_np[14:0]  > 12'h7ff)  ? 12'h7ff : credits_np[14:0]);
    cfg_fc_cplh_nxt = credits_cpl[27] ? 8'h80   : ((credits_cpl[26:16] > 8'h7f)   ? 8'h7f   : credits_cpl[26:16]);
    cfg_fc_cpld_nxt = credits_cpl[15] ? 12'h800 : ((credits_cpl[14:0]  > 12'h7ff) ? 12'h7ff : credits_cpl[14:0]);
end

generate
    if (SYNC_CLOCK) begin: cfg_fc_no_cdc
        always_ff @(posedge user_clk) begin
            cfg_fc.cfg_fc_ph   <= cfg_fc_ph_nxt;
            cfg_fc.cfg_fc_pd   <= cfg_fc_pd_nxt;
            cfg_fc.cfg_fc_nph  <= cfg_fc_nph_nxt;
            cfg_fc.cfg_fc_npd  <= cfg_fc_npd_nxt;
            cfg_fc.cfg_fc_cplh <= cfg_fc_cplh_nxt;
            cfg_fc.cfg_fc_cpld <= cfg_fc_cpld_nxt;
        end
    end else begin: cfg_fc_cdc
        pcie_brg_cdc_bus_sync #(.WIDTH(8))  cdc_bus_sync_cfg_fc_ph    (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_ph_nxt),   .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_ph));
        pcie_brg_cdc_bus_sync #(.WIDTH(12)) cdc_bus_sync_cfg_fc_pd    (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_pd_nxt),   .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_pd));
        pcie_brg_cdc_bus_sync #(.WIDTH(8))  cdc_bus_sync_cfg_fc_nph   (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_nph_nxt),  .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_nph));
        pcie_brg_cdc_bus_sync #(.WIDTH(12)) cdc_bus_sync_cfg_fc_npd   (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_npd_nxt),  .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_npd));
        pcie_brg_cdc_bus_sync #(.WIDTH(8))  cdc_bus_sync_cfg_fc_cplh  (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_cplh_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_cplh));
        pcie_brg_cdc_bus_sync #(.WIDTH(12)) cdc_bus_sync_cfg_fc_cpld  (.src_clk(core_clk), .src_rst(core_rst), .src_in(cfg_fc_cpld_nxt), .dst_clk(user_clk), .dst_rst(user_rst), .dst_out(cfg_fc.cfg_fc_cpld));
    end
endgenerate

endmodule
