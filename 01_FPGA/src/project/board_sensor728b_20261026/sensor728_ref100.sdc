# 728 primitive PLL candidate; complete IO/CDC signoff remains pending.
create_clock -name camera_ref100 -period 10.0 -waveform {0 5} [get_ports {mipi_ref_clk_p}]
create_clock -name sys_clk -period 40 -waveform {0 20} [get_ports {sys_clk}]
create_clock -name mipi_hs_clk -period 2.24466891 [get_ports {mipi_clk_hs_rx_p}]
derive_clocks

set_clock_groups -asynchronous \
    -group [get_clocks {u_sgdma_pll/pll_inst.clkc[0] u_sgdma_pll/pll_inst.clkc[1]}] \
    -group [get_clocks {camera_ref100 u_ui_pll/pll_inst.clkc[0] u_ui_pll/pll_inst.clkc[2]}] \
    -group [get_clocks {*pcie_user_clk*}] \
    -group [get_clocks {sys_clk}] \
    -group [get_clocks {mipi_hs_clk}]

