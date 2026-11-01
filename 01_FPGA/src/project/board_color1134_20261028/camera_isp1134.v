// Production crop/BLC/demosaic/AWB/cut/gamma/contrast/brightness/saturation
// and morphology instances, extracted from frozen camera 722.
module camera_isp724 #(parameter BAYER_MODE="RGGB") (
    input wire user_clk,user_rst_n,
    input wire [39:0] mipi_tdata,
    input wire mipi_tvalid,mipi_tlast,mipi_tuser,
    output wire mipi_tready,
    input wire [12:0] cfg_img_width,cfg_img_height,
    input wire [14:0] cfg_crop_v_start,cfg_crop_v_end,cfg_crop_h_end,
    input wire [2:0] cfg_preprocess_mask,
    input wire [1:0] cfg_advanced_mode,cfg_morphology_mode,
    input wire [7:0] cfg_advanced_threshold,
    input wire [1:0] cfg_bayer_phase,output wire [1:0] active_bayer_phase,
    output wire [2:0] preprocess_active_mask,
    output wire [1:0] advanced_active_mode,morphology_active_mode,
    output wire [7:0] advanced_active_threshold,
    output wire [95:0] output_data,
    output wire output_valid,output_last,output_user
);
    // image_correction → ui_BLC
    wire [39:0]  crop_tdata;
    wire [9:0]   crop_tdest;
    wire         crop_tvalid;
    wire         crop_tlast;
    wire         crop_tuser;
    wire         crop_tready;

    // ui_BLC → ui_top_demosaic
    wire [39:0]  blc_tdata;
    wire [9:0]   blc_tdest;
    wire         blc_tvalid;
    wire         blc_tlast;
    wire         blc_tuser;
    wire         blc_tready;

    // ui_top_demosaic → AWB chain → FIFO → pack4_rgb24_to_512
    wire [127:0] demo_tdata;
    wire         demo_tvalid;
    wire         demo_tlast;
    wire         demo_tuser;
    wire         demo_tready;

    // AWB internal signals
    wire [95:0]  demo_tdata_96;     // demosaic 128b → 96b (strip padding)
    wire [95:0]  awb_tdata;         // AWB 96b output
    wire         awb_tvalid;
    wire         awb_tlast;
    wire         awb_tuser;
    wire         awb_tready;

    // Image Cut output (edge pixel zeroing)
    wire [95:0]  cut_tdata;
    wire         cut_tvalid;
    wire         cut_tlast;
    wire         cut_tuser;
    wire         cut_tready;

    // Gamma correction output
    wire [95:0]  gamma_tdata;
    wire         gamma_tvalid;
    wire         gamma_tlast;
    wire         gamma_tuser;
    wire         gamma_tready;

    // Contrast adjustment output
    wire [95:0]  contrast_tdata;
    wire         contrast_tvalid;
    wire         contrast_tlast;
    wire         contrast_tuser;
    wire         contrast_tready;

    // Brightness adjustment output
    wire [95:0]  bright_tdata;
    wire         bright_tvalid;
    wire         bright_tlast;
    wire         bright_tuser;
    wire         bright_tready;

    // Saturation adjustment output
    wire [95:0]  sat_tdata;
    wire         sat_tvalid;
    wire         sat_tlast;
    wire         sat_tuser;
    wire         sat_tready;
    wire [95:0]  preprocess_tdata;
    wire         preprocess_tvalid;
    wire         preprocess_tlast;
    wire         preprocess_tuser;
    wire [127:0] preprocess_tdata_128;
    wire         fifo_full, fifo_empty;

    image_correction #(
        .DATA_WIDTH     (40),
        .TDEST_WIDTH    (10)
    ) u_image_correction (
        .I_clk          (user_clk),
        .I_rst_n        (user_rst_n),
        // Runtime crop parameters
        .I_v_start      (cfg_crop_v_start),
        .I_v_end        (cfg_crop_v_end),
        .I_h_end        (cfg_crop_h_end),
        // Input from MIPI Rx
        .I_raw_tdata    (mipi_tdata),
        .I_raw_tdest    (10'd0),
        .I_raw_tlast    (mipi_tlast),
        .I_raw_tvalid   (mipi_tvalid),
        .I_raw_tuser    (mipi_tuser),
        .I_raw_tready   (mipi_tready),
        // Output to BLC
        .O_raw_tdata    (crop_tdata),
        .O_raw_tdest    (crop_tdest),
        .O_raw_tlast    (crop_tlast),
        .O_raw_tvalid   (crop_tvalid),
        .O_raw_tuser    (crop_tuser),
        .O_raw_tready   (crop_tready)
    );

    // ================================================================
    // 3. Black Level Correction (BLC)
    // ================================================================
    ui_BLC #(
        .Black_level_offset_r0  (10'd50),
        .Black_level_offset_r1  (10'd50),
        .Black_level_offset_r2  (10'd50),
        .Black_level_offset_r3  (10'd50)
    ) u_blc (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        // Input from image_correction
        .I_tdata    (crop_tdata),
        .I_tdest    (crop_tdest),
        .I_tlast    (crop_tlast),
        .I_tvalid   (crop_tvalid),
        .I_tuser    (crop_tuser),
        .I_tready   (crop_tready),
        // Output to demosaic
        .O_tdata    (blc_tdata),
        .O_tdest    (blc_tdest),
        .O_tlast    (blc_tlast),
        .O_tvalid   (blc_tvalid),
        .O_tuser    (blc_tuser),
        .O_tready   (blc_tready)
    );

    // ================================================================
    // 4. Demosaic (RAW10 Bayer → 128-bit RGB)
    //    128b = 4 pixels × {8'b0, R[7:0], G[7:0], B[7:0]}
    //    Uses 3 BRAM line buffers (ui_ram_demosaic × 2 + ui_ram_zhenghe × 1)
    // ================================================================
    ui_top_demosaic #(
        .data_complete_delay    (50),
        .BAYER_MODE             (BAYER_MODE)
    ) u_demosaic (
        .requested_phase(cfg_bayer_phase),.active_phase(active_bayer_phase),
        .I_clk              (user_clk),
        .I_rst_n            (user_rst_n),
        // Runtime resolution
        .I_img_width        (cfg_img_width),
        .I_img_height       (cfg_img_height),
        // Input from BLC
        .I_axi4s_tdata      (blc_tdata),
        .I_axi4s_tdest      (blc_tdest),
        .I_axi4s_tlast      (blc_tlast),
        .I_axi4s_tvalid     (blc_tvalid),
        .I_axi4s_tuser      (blc_tuser),
        .I_axi4s_tready     (blc_tready),
        // Output to AWB chain
        .O_tdata            (demo_tdata),
        .O_tvalid           (demo_tvalid),
        .O_tlast            (demo_tlast),
        .O_tuser            (demo_tuser),
        .O_tready           (demo_tready)
    );

    // ================================================================
    // 4a. Auto White Balance (AWB) — Gray World algorithm
    //     Pipeline: demosaic(128b) → data128_96 → AWB(96b) → data96_128 → (128b)
    //     Uses divider IP (50-cycle latency) + signal_delay BRAM for data sync.
    //     Gain updated every 4 frames. G channel = reference, R/B adjusted.
    // ================================================================

    // 128b → 96b: strip per-pixel 8-bit padding from demosaic output
    ui_data128_96 u_data128_96 (
        .I_tdata    (demo_tdata),
        .O_tdata    (demo_tdata_96)
    );

    // AWB core (Gray World, 96-bit 4-pixel parallel)
    ui_awb #(
        .IMG_HEIGHT (2160),
        .IMG_WIDTH  (3840)
    ) u_awb (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_img_width (cfg_img_width),
        .I_img_height(cfg_img_height),
        .I_tlast    (demo_tlast),
        .I_tuser    (demo_tuser),
        .I_tdata    (demo_tdata_96),
        .I_tvalid   (demo_tvalid),
        .I_tready   (demo_tready),
        .O_tlast    (awb_tlast),
        .O_tuser    (awb_tuser),
        .O_tdata    (awb_tdata),
        .O_tvalid   (awb_tvalid),
        .O_tready   (awb_tready)
    );

    // ================================================================
    // 4b. Image Cut — zero out edge pixels to remove demosaic boundary artifacts
    //     SKIP_COLS_left=1 → zeros first 4 pixels (1 beat at 4-pixel parallel)
    // ================================================================
    ui_image_cut #(
        .IMG_WIDTH      (3840),
        .IMG_HEIGHT     (2160),
        .DATA_WIDTH     (96),
        .SKIP_ROWS_top  (0),
        .SKIP_ROWS_bottom(0),
        .SKIP_COLS_left (1),
        .SKIP_COLS_right(0)
    ) u_image_cut (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_img_width (cfg_img_width),
        .I_img_height(cfg_img_height),
        .I_tlast    (awb_tlast),
        .I_tuser    (awb_tuser),
        .I_tdata    (awb_tdata),
        .I_tvalid   (awb_tvalid),
        .I_tready   (awb_tready),
        .O_tlast    (cut_tlast),
        .O_tuser    (cut_tuser),
        .O_tdata    (cut_tdata),
        .O_tvalid   (cut_tvalid),
        .O_tready   (cut_tready)
    );

    // ================================================================
    // 4c. Gamma Correction (γ = 2.2)
    //     LUT-based per-channel correction, 4-pixel parallel
    // ================================================================
    ui_gamma #(
        .GAMMA_10x  (22)
    ) u_gamma (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_tlast    (cut_tlast),
        .I_tuser    (cut_tuser),
        .I_tdata    (cut_tdata),
        .I_tvalid   (cut_tvalid),
        .I_tready   (cut_tready),
        .O_tlast    (gamma_tlast),
        .O_tuser    (gamma_tuser),
        .O_tdata    (gamma_tdata),
        .O_tvalid   (gamma_tvalid),
        .O_tready   (gamma_tready)
    );

    // ================================================================
    // 4d. Contrast Adjustment (level=140, 128=no change)
    // ================================================================
    ui_Contrast_adj #(
        .contrast_level (140)
    ) u_contrast (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_tlast    (gamma_tlast),
        .I_tuser    (gamma_tuser),
        .I_tdata    (gamma_tdata),
        .I_tvalid   (gamma_tvalid),
        .I_tready   (gamma_tready),
        .O_tlast    (contrast_tlast),
        .O_tuser    (contrast_tuser),
        .O_tdata    (contrast_tdata),
        .O_tvalid   (contrast_tvalid),
        .O_tready   (contrast_tready)
    );

    // ================================================================
    // 4e. Brightness Adjustment (+5 offset)
    // ================================================================
    ui_Brightness_adj #(
        .BRIGHTNESS_ADD   (5),
        .BRIGHTNESS_MINUS (0)
    ) u_brightness (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_tlast    (contrast_tlast),
        .I_tuser    (contrast_tuser),
        .I_tdata    (contrast_tdata),
        .I_tvalid   (contrast_tvalid),
        .I_tready   (contrast_tready),
        .O_tlast    (bright_tlast),
        .O_tuser    (bright_tuser),
        .O_tdata    (bright_tdata),
        .O_tvalid   (bright_tvalid),
        .O_tready   (bright_tready)
    );

    // ================================================================
    // 4f. Saturation Adjustment (level=130, 128=no change)
    // ================================================================
    ui_Saturation_adj #(
        .ADJUST_VAL (130)
    ) u_saturation (
        .I_clk      (user_clk),
        .I_rst_n    (user_rst_n),
        .I_tlast    (bright_tlast),
        .I_tuser    (bright_tuser),
        .I_tdata    (bright_tdata),
        .I_tvalid   (bright_tvalid),
        .I_tready   (bright_tready),
        .O_tlast    (sat_tlast),
        .O_tuser    (sat_tuser),
        .O_tdata    (sat_tdata),
        .O_tvalid   (sat_tvalid),
        .O_tready   (sat_tready)
    );

    wire required_1080;
    assign required_1080=(cfg_img_width==1920 && cfg_img_height==1080);
    wire required_input_ready;
    wire [1:0] legacy_morphology_active_mode,required_active_mode;
    wire [95:0] required_data;
    wire required_valid,required_last,required_user;
    wire required_initialized,required_error;
    wire [31:0] required_histograms;

    morphology_extended_preprocess u_preprocess (
        .clk             (user_clk),
        .reset_n         (user_rst_n),
        .requested_mask  (cfg_preprocess_mask),
        .requested_morphology(cfg_img_width == 1280 && cfg_img_height == 720 ? cfg_morphology_mode : 2'd0),
        .active_morphology(legacy_morphology_active_mode),
        .requested_mode(cfg_advanced_mode == 2'd3 && (cfg_img_width != 1280 || cfg_img_height != 720) ? 2'd0 : cfg_advanced_mode), .requested_threshold(cfg_advanced_threshold),
        .active_mode(advanced_active_mode), .active_threshold(advanced_active_threshold),
        .active_mask     (preprocess_active_mask),
        .input_data      (sat_tdata),
        .input_valid     (sat_tvalid),
        .input_ready     (sat_tready),
        .input_last      (sat_tlast),
        .input_user      (sat_tuser),
        .output_data     (preprocess_tdata),
        .output_valid    (preprocess_tvalid),
        .output_ready    (required_input_ready || !required_1080),
        .output_last     (preprocess_tlast),
        .output_user     (preprocess_tuser)
    );


    // Preserve legacy modes; enable the three required hardware branches at
    // 1080p. Morphology selector was previously suppressed for this resolution:
    // its values now select RGB / gray / Gaussian(gray) / equalized gray.
    required_preprocess1070 u_required (
        .clk(user_clk),.reset_n(user_rst_n && required_1080),
        .requested_mode(cfg_morphology_mode),.active_mode(required_active_mode),
        .input_data(preprocess_tdata),.input_valid(preprocess_tvalid && required_1080),
        .input_ready(required_input_ready),.input_user(preprocess_tuser),.input_last(preprocess_tlast),
        .output_data(required_data),.output_valid(required_valid),.output_ready(1'b1),
        .output_user(required_user),.output_last(required_last),
        .initialized(required_initialized),.protocol_error(required_error),
        .completed_histograms(required_histograms));
    assign morphology_active_mode=required_1080 ? required_active_mode : legacy_morphology_active_mode;
    // Register all96pixel bits and all three control bits together. The
    // downstream codec accepts every clock; upstream ready behavior is unchanged.
    (* dont_touch = "true" *) reg [95:0] output_data1134;
    (* dont_touch = "true" *) reg output_valid1134,output_last1134,output_user1134;
    always @(posedge user_clk or negedge user_rst_n) begin
        if(!user_rst_n) begin
            output_data1134<=0;output_valid1134<=0;output_last1134<=0;output_user1134<=0;
        end else begin
            output_data1134<=required_1080 ? required_data : preprocess_tdata;
            output_valid1134<=required_1080 ? required_valid : preprocess_tvalid;
            output_last1134<=required_1080 ? required_last : preprocess_tlast;
            output_user1134<=required_1080 ? required_user : preprocess_tuser;
        end
    end
    assign output_data=output_data1134;
    assign output_valid=output_valid1134;
    assign output_last=output_last1134;
    assign output_user=output_user1134;
endmodule
