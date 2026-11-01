// ============================================================================
// param_tpg.v - Phase 11 全局参数与寄存器地址
// (历史文件名保留兼容性，TPG 已在 phase11 中移除)
// ============================================================================

// AXI-Stream 数据宽度
`define AXI_DATA_WIDTH      512
`define AXI_DATA_BYTES      64      // 512 / 8

// RGB24 像素格式
`define BPP                 3       // bytes per pixel

// PCIe user clock (Hz) — 安路 PH2A Gen3 x4
`define USER_CLK_FREQ       250_000_000

// SGDMA descriptor 对齐 (beats)
`define DESC_ALIGN_BEATS    256     // 16384B / 64B

// Header
`define HEADER_BEATS        1       // 64B = 1 beat
`define HEADER_MAGIC        32'h56494430    // "VID0"
`define HEADER_VERSION      16'h0002        // Phase 8

// 默认分辨率
`define DEFAULT_WIDTH       3840
`define DEFAULT_HEIGHT      2160

// 默认帧率
`define DEFAULT_FPS         30

// 图案选择
`define PATTERN_COLORBAR    4'd0
`define PATTERN_COUNTER     4'd1
`define PATTERN_MOVING_BAR  4'd2
`define PATTERN_SOLID       4'd3

// 寄存器地址偏移 (User BAR)
`define REG_TPG_STATUS      8'h40
`define REG_WIDTH           8'h44
`define REG_HEIGHT          8'h48
`define REG_PIXEL_FORMAT    8'h4C
`define REG_FRAME_COUNT     8'h50
`define REG_FPS_CONFIG      8'h54
`define REG_BYTES_PER_FRAME 8'h58
`define REG_VERSION         8'h5C
`define REG_CTRL            8'h60
`define REG_PADDED_BYTES    8'h64
`define REG_DROP_COUNT      8'h68
`define REG_PATTERN_SEL     8'h6C
`define REG_DELIVERED_COUNT 8'h70

// Debug registers (Phase 8 hardware debugging)
`define REG_DBG_STATE       8'h74
`define REG_DBG_PIX_CNT     8'h78
`define REG_DBG_DMA_BEAT    8'h7C
