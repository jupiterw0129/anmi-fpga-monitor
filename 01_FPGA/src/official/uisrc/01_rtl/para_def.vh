// para_def.vh ¡ª Phase 9: IMX415 Camera + TPG via PCIe (AXI4-Stream mode)
// Same compile defines as Phase 8 (proven on CU06 board)

// `define     DMA_BYPA_EN
`define     AXI4ST_BUS_EN
//`define     AXI4MM_BUS_EN
`define     AXI4L_MBUS_EN
//`define     AXI4L_SBUS_EN
//`define     CFG_MGMT_EN 
// `define     DSC_BYPASS_C2H_CHL0_EN
// `define     DSC_BYPASS_C2H_CHL1_EN
// `define     DSC_BYPASS_C2H_CHL2_EN
// `define     DSC_BYPASS_C2H_CHL3_EN
// `define     DSC_BYPASS_H2C_CHL0_EN
// `define     DSC_BYPASS_H2C_CHL1_EN
// `define     DSC_BYPASS_H2C_CHL2_EN
// `define     DSC_BYPASS_H2C_CHL3_EN
`define     USR_IRQ_EN
`define     MSI_EN 1'b1
