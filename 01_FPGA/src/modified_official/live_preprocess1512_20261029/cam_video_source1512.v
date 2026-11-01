// =============================================================================
// cam_video_source.v — IMX415 Camera Video Source (drop-in replacement for tpg_gen)
// =============================================================================
// Pipeline:
//   mipi_csi_rx (40b @ user_clk via internal sfifo CDC)
//     → image_correction (crop to active region)
//       → ui_BLC (black level correction, offset=50)
//         → ui_top_demosaic (RAW10 Bayer → 128b RGB)
//           → data128_96 → ui_awb (Gray World AWB) → data96_128
//             → FIFO (rate decoupling)
//               → pack4_rgb24_to_512 (128b→512b, 4 pixels/clk, backpressure)
//
// Output interface: 128-bit AXI-Stream + sof/eof/frame_count.
// Matched to x1 Gen2 PCIe DATA_WIDTH=128.
// No DDR buffering — pure streaming with frame-drop on DMA backpressure.
// =============================================================================
`timescale 1ns / 1ps

module cam_video_source_board774 #(
    parameter LL_WIDTH=1920,LL_HEIGHT=1080,
    parameter MIPI_LAN     = 4,
    parameter DEVICE       = "PH2",
    parameter BAYER_MODE   = "RGGB"
)(
    // System clock (PCIe user_clk, ~250-300MHz)
    input wire codec_clk,
    output wire jpeg_busy,
    output wire [31:0] jpeg_admitted,jpeg_committed,jpeg_aborted,jpeg_faults,
    input  wire          user_clk,
    input  wire          user_rst_n,
    input  wire          enable,
    input wire jpeg_stop_requested,
    output wire jpeg_admission_stopped,jpeg_stop_ready,
    input  wire [2:0]    cfg_preprocess_mask,
    output wire [2:0]    preprocess_active_mask,
    input wire [1:0] cfg_advanced_mode,
    input wire [1:0] cfg_bayer_phase,output wire [1:0] active_bayer_phase,
    input wire [1:0] cfg_morphology_mode,
    output wire [1:0] morphology_active_mode,
    output wire mode_frame_valid,output wire [31:0] mode_frame_wire_id,
    input wire [7:0] cfg_advanced_threshold,
    output wire [1:0] advanced_active_mode,
    output wire [7:0] advanced_active_threshold,

    // Runtime resolution parameters (from BAR registers)
    input  wire [12:0]   cfg_img_width,      // Active image width  (e.g. 1920, 3840, 1280)
    input  wire [12:0]   cfg_img_height,     // Active image height (e.g. 1080, 2160, 720)
    input  wire [14:0]   cfg_crop_v_start,   // Crop: first valid line (exclusive >)
    input  wire [14:0]   cfg_crop_v_end,     // Crop: last  valid line (exclusive <)
    input  wire [14:0]   cfg_crop_h_end,     // Crop: h beats per line (exclusive <)

    // MIPI CSI-2 physical interface
    input  wire          mipi_ref_clock,     // PHY reference clock
    input  wire          mipi_clk_hs_rx_p,   // MIPI clock lane (P)
    input  wire [MIPI_LAN-1:0] mipi_data_hs_p, // MIPI data lanes (P)

    // Frame control
    input  wire          frame_request,      // Tie to 1 for camera mode

    // AXI-Stream 128-bit output (matched to x1 Gen2 DATA_WIDTH=128)
    output wire [127:0]  m_tdata,
    output wire          m_tvalid,
    input  wire          m_tready,
    output wire          m_tlast,
    output wire          m_frame_last,
    output wire          sof,
    output wire          eof,
    output wire [31:0]   frame_count_out,
    input wire [15:0] cfg_source_beats,cfg_source_lines,
    input wire [6:0] requested_quality,
    input wire [3:0] observation_index,owner_index,
    output wire [31:0] observation_data,
    output reg [31:0] owner_data,
    output wire [127:0] committed_data,
    output wire [15:0] committed_keep,
    output wire committed_valid,committed_last,
    input wire committed_ready,
    output wire [31:0] committed_frame_id,
    output wire [6:0] active_quality,
    output reg [31:0] committed_oversize_count,committed_fault_count,
    output wire [31:0] committed_busy_count,committed_diagnostic,committed_quality_diagnostic,
    input wire lossless_mode,session_reset_n,
    output wire [127:0] ll_packet_data,output wire [15:0] ll_packet_keep,
    output wire ll_packet_valid,ll_packet_last,input wire ll_packet_ready,
    output wire ll_busy,output wire [31:0] ll_admitted,ll_skipped,ll_completed,ll_rejected,
    output wire [31:0] ll_overflow,ll_shape,ll_epoch,ll_wire_id,ll_source_id,
    output wire [11:0] ll_high_water,
    output wire [95:0] lossless_data,
    output wire lossless_valid,
    output wire lossless_sof,
    output wire lossless_eol,
    input  wire          jpeg_mode,
    output wire [95:0]   jpeg_tdata,
    output wire          jpeg_tvalid,
    input  wire          jpeg_tready,
    output wire          jpeg_tlast,
    output wire          jpeg_tuser,
    output wire          jpeg_input_overflow,

    // Status / debug
    input  wire          debug_button,       // Board debug button (MIPI delay)
    output wire          mipi_div_clk_out,   // Divided HS clock (debug)
    output wire          auto_delay_done,    // MIPI PHY auto delay calibration done
    output wire          mipi_tvalid_out,    // MIPI receiver raw tvalid (for debug)
    output wire [7:0]    dbg_mipi,           // MIPI 内部调试总线（hs_div_clk 域）
    output wire [7:0]    dbg_delay,          // delay 调试总线（hs_div_clk 域）
    output wire [5:0]    dbg_best_len,
    input wire [5:0] delay_config,
    input wire diag_capture,
    input wire [7:0] diag_index,
    output wire [31:0] diag_data,
    output wire [31:0]   mipi_fifo_overflow_count
);

    // ================================================================

    wire checked_mode=jpeg_mode || lossless_mode;
    wire ll_isp_reset,ll_raw_valid,ll_raw_sof,ll_raw_eol;
    wire [39:0] ll_raw_data;
    wire [12:0] ll_width,ll_height;
    wire [14:0] ll_crop_start,ll_crop_end,ll_crop_horizontal;
    wire [2:0] ll_mask;wire [1:0] ll_advanced,ll_morphology;wire [7:0] ll_threshold;
    wire jpeg_checked_ready;
    wire [3:0] decision_reason;
    wire legacy_reset_n=!jpeg_mode && (lossless_mode ? ll_isp_reset : user_rst_n);
    wire raw_output_reset_n=user_rst_n && !checked_mode;
    wire [2:0] legacy_preprocess_active_mask,jpeg_mask;
    wire [1:0] legacy_advanced_active_mode,legacy_morphology_active_mode,jpeg_advanced,jpeg_morphology;
    wire [7:0] legacy_advanced_active_threshold,jpeg_threshold;
    wire [31:0] legacy_frame_count_out;
    wire legacy_sof,legacy_eof,legacy_jpeg_input_overflow;
    wire [31:0] byte_data;
    wire byte_valid,byte_reset_n,checked_packet_done,checked_sync_wait,checked_attempt,checked_header,checked_bad;
    wire [39:0] checked_data;
    wire checked_valid,checked_ready,checked_sof,checked_eol,checked_begin,checked_reset_n;
    wire [31:0] checked_id,checked_begin_id,decision_id;
    wire decision_valid,decision_good;
    wire [31:0] source_good,source_bad,source_orphan;
    wire [31:0] admitted,skipped,rejected,completed,timeouts,codec_oversize,codec_busy,codec_fault;
    wire codec_fault_event,codec_oversize_event;
    wire owned_overflow;
    assign preprocess_active_mask=jpeg_mode ? jpeg_mask : legacy_preprocess_active_mask;
    assign advanced_active_mode=jpeg_mode ? jpeg_advanced : legacy_advanced_active_mode;
    assign morphology_active_mode=jpeg_mode ? jpeg_morphology : legacy_morphology_active_mode;
    assign advanced_active_threshold=jpeg_mode ? jpeg_threshold : legacy_advanced_active_threshold;
    assign frame_count_out=jpeg_mode ? admitted : legacy_frame_count_out;
    assign sof=jpeg_mode ? checked_begin : legacy_sof;
    assign eof=jpeg_mode ? committed_valid && committed_ready && committed_last : legacy_eof;
    assign jpeg_input_overflow=jpeg_mode ? owned_overflow : legacy_jpeg_input_overflow;
    assign committed_busy_count=skipped;
    camera_rx_board724 checked_receiver (
        .source_clk(mipi_div_clk_out),.source_reset_n(byte_reset_n),.enable(enable && checked_mode),
        .stop_requested(jpeg_mode && jpeg_stop_requested),.admission_stopped(jpeg_admission_stopped),
        .input_data(byte_data),.input_valid(byte_valid),.dest_clk(user_clk),.dest_reset_n(user_rst_n),
        .cfg_beats_per_line(cfg_source_beats),.cfg_lines_per_frame(cfg_source_lines),
        .pixel_data(checked_data),.pixel_valid(checked_valid),.pixel_ready(checked_ready),
        .pixel_sof(checked_sof),.pixel_eol(checked_eol),.pixel_frame_id(checked_id),
        .frame_begin(checked_begin),.begin_frame_id(checked_begin_id),.pipeline_abort(),.pipeline_reset_n(checked_reset_n),
        .decision_valid(decision_valid),.decision_ready(1'b1),.decision_frame_id(decision_id),.decision_good(decision_good),
        .decision_reason(decision_reason),.good_count(source_good),.bad_count(source_bad),.orphan_count(source_orphan),
        .packet_done(checked_packet_done),.sync_wait(checked_sync_wait),.header_attempt(checked_attempt),
        .header_valid(checked_header),.header_bad(checked_bad),.filter_bad(),.crc_bad(),.truncated(),.overflow(),.queue_overflow(),
        .observation_index(observation_index),.observation_data(observation_data)
    );
    wire [31:0] first_fault_code913,first_fault_occupancy913,queue_peaks913;
    wire jpeg_committed_event,jpeg_aborted_event,jpeg_recovering;
    camera_stream774 #(.WIDTH(1920),.HEIGHT(1080),.QUALITY(50)) owner (
        .requested_quality(requested_quality),
        .cfg_bayer_phase(cfg_bayer_phase),.active_bayer_phase(active_bayer_phase),
        .user_clk(user_clk),.codec_clk(codec_clk),.reset_n(user_rst_n),
        .source_ok(checked_reset_n && enable && jpeg_mode),
        .stop_requested(jpeg_stop_requested),.admission_stopped(jpeg_admission_stopped),.stop_ready(jpeg_stop_ready),
        .frame_begin(checked_begin && jpeg_mode),.begin_id(checked_begin_id),
        .raw_data(checked_data),.raw_valid(checked_valid && jpeg_mode),.raw_ready(jpeg_checked_ready),
        .raw_sof(checked_sof),.raw_eol(checked_eol),.raw_id(checked_id),
        .verdict_valid(decision_valid && jpeg_mode),.verdict_id(decision_id),
        .verdict_good(decision_good),.verdict_reason({28'd0,decision_reason}),
        .cfg_crop_start(cfg_crop_v_start),.cfg_crop_end(cfg_crop_v_end),.cfg_crop_horizontal(cfg_crop_h_end),
        .cfg_mask(cfg_preprocess_mask),.cfg_advanced(cfg_advanced_mode),
        .cfg_morphology(cfg_morphology_mode),.cfg_threshold(cfg_advanced_threshold),
        .packet_data(committed_data),.packet_keep(committed_keep),.packet_valid(committed_valid),
        .packet_last(committed_last),.packet_ready(committed_ready),.packet_frame_id(committed_frame_id),
        .mode_frame_valid(mode_frame_valid),.mode_frame_wire_id(mode_frame_wire_id),
        .active_mask(jpeg_mask),.active_advanced(jpeg_advanced),.active_morphology(jpeg_morphology),.active_threshold(jpeg_threshold),
        .committed(jpeg_committed_event),.aborted(jpeg_aborted_event),.recovering(jpeg_recovering),.busy(jpeg_busy),
        .admitted_count(admitted),.committed_count(completed),.aborted_count(rejected),.fault_count(codec_fault),
        .first_fault_code(first_fault_code913),.first_fault_occupancy(first_fault_occupancy913),.queue_peaks(queue_peaks913)
    );
    assign jpeg_admitted=admitted;
    assign jpeg_committed=completed;
    assign jpeg_aborted=rejected;
    assign jpeg_faults=codec_fault;
    assign skipped=0;assign timeouts=0;assign codec_oversize=0;assign codec_busy=0;
    // Legacy output reports requested Q; it is not an encoded-frame readback.
    assign active_quality=requested_quality;
    assign owned_overflow=1'b0;assign codec_fault_event=1'b0;assign codec_oversize_event=1'b0;
    assign committed_diagnostic=codec_fault;
    // No per-commit quality readback is advertised on this legacy diagnostic.
    assign committed_quality_diagnostic=0;
    wire         mipi_tready;
    wire [95:0]  preprocess_tdata;
    wire         preprocess_tvalid;
    wire         preprocess_tlast;
    wire         preprocess_tuser;
    wire [39:0]  mipi_tdata;
    wire         mipi_tvalid;
    wire         mipi_tlast;
    wire         mipi_tuser;
    // Legacy-only two-entry elasticity: CSI readiness depends on registered count.
    // Checked JPEG/lossless byte stream and its owner do not pass through here.
    reg [41:0] legacy_raw_head,legacy_raw_tail;
    reg [1:0] legacy_raw_count;
    wire legacy_raw_ready=legacy_raw_count!=2;
    wire legacy_raw_valid=legacy_raw_count!=0;
    wire legacy_raw_push=mipi_tvalid && legacy_raw_ready;
    wire legacy_raw_pop=legacy_raw_valid && mipi_tready;
    wire [41:0] legacy_raw_input={mipi_tuser,mipi_tlast,mipi_tdata};
    always @(posedge user_clk or negedge raw_output_reset_n) begin
        if(!raw_output_reset_n)legacy_raw_count<=0;
        else begin
            if(legacy_raw_push)begin
                if(legacy_raw_count==0 || legacy_raw_pop)legacy_raw_head<=legacy_raw_input;
                else legacy_raw_tail<=legacy_raw_input;
            end else if(legacy_raw_pop && legacy_raw_count==2)legacy_raw_head<=legacy_raw_tail;
            case({legacy_raw_push,legacy_raw_pop})
                2'b10:legacy_raw_count<=legacy_raw_count+1'b1;
                2'b01:legacy_raw_count<=legacy_raw_count-1'b1;
            endcase
        end
    end
    // The checked lossless owner accepts RAW into two registered slots.
    // ISP ready no longer feeds back through owner/raster/geometry in one cycle.
    wire ll_raw_buffer_reset_n=legacy_reset_n && lossless_mode;
    reg [41:0] ll_raw_head,ll_raw_tail;
    reg [1:0] ll_raw_count;
    wire ll_raw_ready=ll_raw_count!=2;
    wire ll_buffer_valid=ll_raw_count!=0;
    wire ll_buffer_push=ll_raw_valid && ll_raw_ready;
    wire ll_buffer_pop=ll_buffer_valid && mipi_tready;
    wire [41:0] ll_buffer_input={ll_raw_sof,ll_raw_eol,ll_raw_data};
    always @(posedge user_clk or negedge ll_raw_buffer_reset_n) begin
        if(!ll_raw_buffer_reset_n)ll_raw_count<=0;
        else begin
            if(ll_buffer_push)begin
                if(ll_raw_count==0 || ll_buffer_pop)ll_raw_head<=ll_buffer_input;
                else ll_raw_tail<=ll_buffer_input;
            end else if(ll_buffer_pop && ll_raw_count==2)ll_raw_head<=ll_raw_tail;
            case({ll_buffer_push,ll_buffer_pop})
                2'b10:ll_raw_count<=ll_raw_count+1'b1;
                2'b01:ll_raw_count<=ll_raw_count-1'b1;
            endcase
        end
    end
    wire ll_checked_ready;
    assign checked_ready=lossless_mode ? ll_checked_ready : jpeg_checked_ready;
    camera_owned_lossless725 #(.WIDTH(LL_WIDTH),.HEIGHT(LL_HEIGHT),.EXTERNAL_ISP(1)) lossless_owner(
        .clk(user_clk),.reset_n(session_reset_n),.source_reset_n(checked_reset_n && user_rst_n),
        .enable(enable && lossless_mode && cfg_source_beats!=0 && cfg_source_lines!=0),
        .cfg_img_width(cfg_img_width),.cfg_img_height(cfg_img_height),
        .cfg_crop_v_start(cfg_crop_v_start),.cfg_crop_v_end(cfg_crop_v_end),.cfg_crop_h_end(cfg_crop_h_end),
        .cfg_preprocess_mask(cfg_preprocess_mask),.cfg_advanced_mode(cfg_advanced_mode),
        .cfg_morphology_mode(cfg_morphology_mode),.cfg_advanced_threshold(cfg_advanced_threshold),
        .frame_begin(checked_begin && lossless_mode),.begin_frame_id(checked_begin_id),
        .raw_data(checked_data),.raw_valid(checked_valid && lossless_mode),.raw_sof(checked_sof),.raw_eol(checked_eol),
        .raw_frame_id(checked_id),.raw_ready(ll_checked_ready),
        .decision_valid(decision_valid && lossless_mode),.decision_frame_id(decision_id),
        .decision_good(decision_good),.decision_reason(decision_reason),
        .ext_isp_data(preprocess_tdata),.ext_isp_valid(preprocess_tvalid),.ext_isp_last(preprocess_tlast),
        .ext_isp_user(preprocess_tuser),.ext_isp_ready(ll_raw_ready),
        .ext_active_mask(legacy_preprocess_active_mask),.ext_active_advanced(legacy_advanced_active_mode),
        .ext_active_morphology(legacy_morphology_active_mode),.ext_active_threshold(legacy_advanced_active_threshold),
        .external_reset_n(ll_isp_reset),.external_raw_data(ll_raw_data),.external_raw_valid(ll_raw_valid),
        .external_raw_sof(ll_raw_sof),.external_raw_eol(ll_raw_eol),
        .external_width(ll_width),.external_height(ll_height),
        .external_crop_start(ll_crop_start),.external_crop_end(ll_crop_end),.external_crop_horizontal(ll_crop_horizontal),
        .external_mask(ll_mask),.external_advanced(ll_advanced),.external_morphology(ll_morphology),.external_threshold(ll_threshold),
        .packet_data(ll_packet_data),.packet_keep(ll_packet_keep),.packet_valid(ll_packet_valid),
        .packet_last(ll_packet_last),.packet_ready(ll_packet_ready),.busy(ll_busy),
        .admitted_count(ll_admitted),.skipped_count(ll_skipped),.completed_count(ll_completed),.rejected_count(ll_rejected),
        .overflow_count(ll_overflow),.shape_count(ll_shape),.epoch_abort_count(ll_epoch),
        .packet_frame_id(ll_wire_id),.source_owner_id(ll_source_id),.high_water(ll_high_water),
        .ignored_verdicts(),.preprocess_active_mask(),.advanced_active_mode(),.morphology_active_mode(),.advanced_active_threshold()
    );
    // Capture fault events on the finish/reset edge, never poll counters
    // that are cleared immediately when the owner releases the codec.
    always @(posedge user_clk or negedge user_rst_n) begin
        if(!user_rst_n) begin committed_oversize_count<=0;committed_fault_count<=0;end
        else begin
            if(codec_oversize_event) committed_oversize_count<=committed_oversize_count+1'b1;
            committed_fault_count<=codec_fault;
        end
    end
    always @* case(owner_index)
        4:owner_data=admitted;
        5:owner_data=skipped;
        6:owner_data=rejected;
        7:owner_data=completed;
        8:owner_data=timeouts;
        9:owner_data=source_good;
        10:owner_data=source_bad;
        11:owner_data=source_orphan;
        12:owner_data=committed_frame_id;
        13:owner_data=first_fault_code913;
        14:owner_data=first_fault_occupancy913;
        15:owner_data=queue_peaks913;
        default:owner_data=0;
    endcase
    // Internal wires
    // ================================================================

    // mipi_csi_rx → image_correction
    assign       mipi_tvalid_out = jpeg_mode ? checked_valid : mipi_tvalid;

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
    wire [127:0] preprocess_tdata_128;
    wire         fifo_full, fifo_empty;

    // FIFO output → pack4_rgb24_to_512
    wire [127:0] fifo_tdata;
    wire         fifo_tvalid;
    wire         fifo_tlast;
    wire         fifo_tuser;
    wire         fifo_tready;
    wire         pack_tready;

    // ---- Pipeline diagnostic sticky flags (injected into frame_count upper byte) ----
    reg mipi_tuser_ever, mipi_tlast_ever;
    reg crop_tuser_ever, crop_tlast_ever;
    reg demo_tuser_ever, demo_tlast_ever;
    reg awb_tuser_ever,  awb_tlast_ever;
    reg pack_sof_ever,   pack_eof_ever;
    always @(posedge user_clk or negedge legacy_reset_n) begin
        if (!legacy_reset_n) begin
            mipi_tuser_ever <= 1'b0; mipi_tlast_ever <= 1'b0;
            crop_tuser_ever <= 1'b0; crop_tlast_ever <= 1'b0;
            demo_tuser_ever <= 1'b0; demo_tlast_ever <= 1'b0;
            awb_tuser_ever  <= 1'b0; awb_tlast_ever  <= 1'b0;
            pack_sof_ever   <= 1'b0; pack_eof_ever   <= 1'b0;
        end else begin
            if (mipi_tuser)  mipi_tuser_ever <= 1'b1;
            if (mipi_tlast)  mipi_tlast_ever <= 1'b1;
            if (crop_tuser)  crop_tuser_ever <= 1'b1;
            if (crop_tlast)  crop_tlast_ever <= 1'b1;
            if (demo_tuser)  demo_tuser_ever <= 1'b1;
            if (demo_tlast)  demo_tlast_ever <= 1'b1;
            if (awb_tuser)   awb_tuser_ever  <= 1'b1;
            if (awb_tlast)   awb_tlast_ever  <= 1'b1;
            if (legacy_sof)         pack_sof_ever   <= 1'b1;
            if (legacy_eof)         pack_eof_ever   <= 1'b1;
        end
    end
    wire [31:0] raw_frame_count;

    // ================================================================
    // 1. MIPI CSI-2 Receiver
    //    CDC: internal sfifo bridges hs_rx_clk → m_axis_video_aclk (user_clk)
    // ================================================================
    mipi_csi_rx_shared724 #(
        .MIPI_LAN   (MIPI_LAN),
        .DEVICE     (DEVICE)
    ) u_mipi_csi_rx (
        .I_jpeg_select(checked_mode),.I_checked_packet_done(checked_packet_done),.I_checked_sync_wait(checked_sync_wait),
        .I_checked_header_attempt(checked_attempt),.I_checked_header_valid(checked_header),.I_checked_header_bad(checked_bad),
        .O_byte_data(byte_data),.O_byte_valid(byte_valid),.O_byte_reset_n(byte_reset_n),
        .I_debug_button         (debug_button),
        .I_ref_clock            (mipi_ref_clock),
        .I_clk_hs_rx_p          (mipi_clk_hs_rx_p),
        .I_reset_n              (user_rst_n),
        .I_hs_data_p            (mipi_data_hs_p),
        .I_enable               (enable),
        .I_raw12_mode           (cfg_img_width != 13'd3840),
        .O_hs_div_clk           (mipi_div_clk_out),
        // Output clock domain = user_clk (key CDC point!)
        .m_axis_video_aclk      (user_clk),
        .m_axis_video_aresetn   (user_rst_n),
        .m_axis_video_tready    (checked_mode ? 1'b1 : legacy_raw_ready),
        .m_axis_video_tuser     (mipi_tuser),
        .m_axis_video_tlast     (mipi_tlast),
        .m_axis_video_tvalid    (mipi_tvalid),
        .m_axis_video_tdata     (mipi_tdata),
        .O_auto_delay_done      (auto_delay_done),
        .O_dbg_mipi             (dbg_mipi),
        .O_dbg_delay            (dbg_delay),
        .O_dbg_best_len         (dbg_best_len),
        .I_delay_config(delay_config), .I_diag_capture(diag_capture), .I_diag_index(diag_index), .O_diag_data(diag_data),
        .O_fifo_overflow_count  (mipi_fifo_overflow_count)
    );

    // ================================================================
    // 2. Image Correction (spatial crop to IMG_WIDTH × IMG_HEIGHT)
    // ================================================================
    image_correction #(
        .DATA_WIDTH     (40),
        .TDEST_WIDTH    (10)
    ) u_image_correction (
        .I_clk          (user_clk),
        .I_rst_n        (legacy_reset_n),
        // Runtime crop parameters
        .I_v_start      ((lossless_mode ? ll_crop_start : cfg_crop_v_start)),
        .I_v_end        ((lossless_mode ? ll_crop_end : cfg_crop_v_end)),
        .I_h_end        ((lossless_mode ? ll_crop_horizontal : cfg_crop_h_end)),
        // Input from MIPI Rx
        .I_raw_tdata    ((lossless_mode ? ll_raw_head[39:0] : legacy_raw_head[39:0])),
        .I_raw_tdest    (10'd0),
        .I_raw_tlast    ((lossless_mode ? ll_buffer_valid && ll_raw_head[40] : legacy_raw_valid && legacy_raw_head[40])),
        .I_raw_tvalid   ((lossless_mode ? ll_buffer_valid : legacy_raw_valid)),
        .I_raw_tuser    ((lossless_mode ? ll_buffer_valid && ll_raw_head[41] : legacy_raw_valid && legacy_raw_head[41])),
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
        .I_rst_n    (legacy_reset_n),
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
        .requested_phase(2'd0),.active_phase(),
        .I_clk              (user_clk),
        .I_rst_n            (legacy_reset_n),
        // Runtime resolution
        .I_img_width        ((lossless_mode ? ll_width : cfg_img_width)),
        .I_img_height       ((lossless_mode ? ll_height : cfg_img_height)),
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
        .I_rst_n    (legacy_reset_n),
        .I_img_width ((lossless_mode ? ll_width : cfg_img_width)),
        .I_img_height((lossless_mode ? ll_height : cfg_img_height)),
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
        .I_rst_n    (legacy_reset_n),
        .I_img_width ((lossless_mode ? ll_width : cfg_img_width)),
        .I_img_height((lossless_mode ? ll_height : cfg_img_height)),
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
        .I_rst_n    (legacy_reset_n),
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
        .I_rst_n    (legacy_reset_n),
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
        .I_rst_n    (legacy_reset_n),
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
        .I_rst_n    (legacy_reset_n),
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

    morphology_extended_preprocess u_preprocess (
        .clk             (user_clk),
        .reset_n         (legacy_reset_n),
        .requested_mask  ((lossless_mode ? ll_mask : cfg_preprocess_mask)),
        .requested_morphology((lossless_mode ? ll_width : cfg_img_width) == 1280 && (lossless_mode ? ll_height : cfg_img_height) == 720 ? (lossless_mode ? ll_morphology : cfg_morphology_mode) : 2'd0),
        .active_morphology(legacy_morphology_active_mode),
        .requested_mode((lossless_mode ? ll_advanced : cfg_advanced_mode) == 2'd3 && ((lossless_mode ? ll_width : cfg_img_width) != 1280 || (lossless_mode ? ll_height : cfg_img_height) != 720) ? 2'd0 : (lossless_mode ? ll_advanced : cfg_advanced_mode)), .requested_threshold((lossless_mode ? ll_threshold : cfg_advanced_threshold)),
        .active_mode(legacy_advanced_active_mode), .active_threshold(legacy_advanced_active_threshold),
        .active_mask     (legacy_preprocess_active_mask),
        .input_data      (sat_tdata),
        .input_valid     (sat_tvalid),
        .input_ready     (sat_tready),
        .input_last      (sat_tlast),
        .input_user      (sat_tuser),
        .output_data     (preprocess_tdata),
        .output_valid    (preprocess_tvalid),
        .output_ready    (lossless_mode || ~fifo_full),
        .output_last     (preprocess_tlast),
        .output_user     (preprocess_tuser)
    );

    ui_data96_128 u_data96_128 (
        .I_tdata    (preprocess_tdata),
        .O_tdata    (preprocess_tdata_128)
    );

    // ================================================================
    // 4b. Rate-decoupling FIFO (AWB → pack4)
    //     Demosaic outputs 480 beats/line at 1 beat/clk.
    //     pack4 processes 4 pixels/clk (same as demosaic output rate).
    //     FIFO absorbs bursts when downstream stalls (DMA descriptor).
    // ================================================================
    assign lossless_data = preprocess_tdata;
    assign lossless_valid = lossless_mode && preprocess_tvalid;
    assign lossless_sof = preprocess_tuser;
    assign lossless_eol = preprocess_tlast;
    wire [129:0] fifo_rd_data;

    assign fifo_tdata   = fifo_rd_data[127:0];
    assign fifo_tlast   = fifo_rd_data[128];
    assign fifo_tuser   = fifo_rd_data[129];
    assign fifo_tvalid  = ~fifo_empty;
    assign fifo_tready  = jpeg_mode ? jpeg_tready : pack_tready;
    assign jpeg_tvalid  = jpeg_mode && fifo_tvalid;
    assign jpeg_tlast   = fifo_tlast;
    assign jpeg_tuser   = fifo_tuser;
    assign jpeg_tdata   = {fifo_tdata[119:96], fifo_tdata[87:64],
                           fifo_tdata[55:32], fifo_tdata[23:0]};
    assign legacy_jpeg_input_overflow = preprocess_tvalid && fifo_full && !lossless_mode;

    sync_fifo_130 #(
        .ADDR_WIDTH (10)       // 1024 entries, enough for 960-beat 4K line burst
    ) u_demo_fifo (
        .clk      (user_clk),
        .rst_n    (raw_output_reset_n),
        .wr_data  ({preprocess_tuser, preprocess_tlast, preprocess_tdata_128}),
        .wr_en    (preprocess_tvalid & ~fifo_full & ~lossless_mode),
        .full     (fifo_full),
        .rd_data  (fifo_rd_data),
        .rd_en    (fifo_tready & ~fifo_empty),
        .empty    (fifo_empty)
    );

    // ================================================================
    // 5. pack4_rgb24_to_128 — 4-pixel parallel RGB24 packer (128b→128b)
    //    Strips per-pixel padding and tight-packs RGB24 for 128b DMA.
    //    4 inputs (48B) → 3 outputs (48B), LCM(12,16)=48.
    // ================================================================
    pack4_rgb24_to_128 u_pack4 (
        .clk            (user_clk),
        .rst_n          (raw_output_reset_n),
        .enable         (enable),
        .frame_height   (cfg_img_height),
        // Input from FIFO (128b AXI-Stream)
        .s_tdata        (fifo_tdata),
        .s_tvalid       (fifo_tvalid && !jpeg_mode),
        .s_tready       (pack_tready),
        .s_tlast        (fifo_tlast),
        .s_tuser        (fifo_tuser),
        // 512-bit AXI-Stream output
        .m_tdata        (m_tdata),
        .m_tvalid       (m_tvalid),
        .m_tready       (m_tready),
        .m_tlast        (m_tlast),
        .m_frame_last   (m_frame_last),
        .sof            (legacy_sof),
        .eof            (legacy_eof),
        .frame_count_out(raw_frame_count)
    );

    // Inject diagnostic sticky flags into legacy_frame_count_out[31:24]
    // F[31]: mipi_tuser_ever  F[30]: mipi_tlast_ever
    // F[29]: crop_tuser_ever  F[28]: crop_tlast_ever
    // F[27]: demo_tuser_ever  F[26]: demo_tlast_ever
    // F[25]: awb_tuser_ever   F[24]: awb_tlast_ever
    // F[23:0]: actual frame count
    assign legacy_frame_count_out = {
        mipi_tuser_ever, mipi_tlast_ever,
        crop_tuser_ever, crop_tlast_ever,
        demo_tuser_ever, demo_tlast_ever,
        awb_tuser_ever,  awb_tlast_ever,
        raw_frame_count[23:0]
    };

endmodule
