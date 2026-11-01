`include "pcie_brg_def.svh"

module pcie_brg_cfg_ctrl#(
    parameter SYNC_CLOCK = 1,
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter EP_MODE = 1
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_rst,

    cfg_ctrl_if.slv cfg_ctrl,
    output logic pl_ltssm_enable,
    input logic [7:0] bus_num,
    input logic [4:0] dev_num
);

assign cfg_ctrl.cfg_hot_reset_out = 0;
pcie_brg_cdc_sync #(.REG_IN(1), .WIDTH(1)) cdc_sync_pl_ltssm_enable(.src_clk(user_clk), .src_in(cfg_ctrl.cfg_link_training_enable), .dst_clk(core_clk), .dst_out(pl_ltssm_enable));
assign cfg_ctrl.cfg_bus_number = bus_num;
assign cfg_ctrl.cfg_dev_number = dev_num;

endmodule
