// ============================================================================
// param_imx415.v - Phase 9 IMX415 Camera 扩展参数
// ============================================================================
// 在 TD 项目中与 param_tpg.v 一同 GlobalInclude
// ============================================================================

// ─── Camera 寄存器地址 ───
`define REG_SOURCE_SEL      8'h80   // R/W: bit[0] = 0:TPG, 1:Camera
`define REG_CAM_STATUS      8'h84   // R: bit[0]=I2C done, [1]=MIPI div_clk, [2]=cam SOF seen
`define REG_CAM_FRAME_COUNT 8'h88   // R: camera frame count (32-bit)
`define REG_CAM_ERROR       8'h8C   // R: {3'd0, cam_width[12:0], 3'd0, cam_height[12:0]}
`define REG_CAM_MODE        8'h90   // R/W: bit[1:0] = 0:1080p, 1:4K, 2:720p
`define REG_DROP_DETECT_CNT 8'h94   // R: vid_drop_detect trigger count
`define REG_AE_GAIN        8'h98   // R/W: bit[7:0] = AE gain (0-240, default 100 = 30dB)
`define REG_GATE_DROP_CNT  8'h9C   // R: vid_frame_gate dropped frame count
`define REG_GATE_PASS_CNT  8'hA0   // R: vid_frame_gate passed frame count

// ─── 版本标识 ───
`define PHASE9_VERSION      32'h5644_0013   // "VD" + Phase 10, v19: cleanup diagnostic bits

// ─── MCLK / I2C ───
`define CAM_I2C_CLK_DIV     16'd269         // 27MHz / (269+1) = 100kHz I2C
