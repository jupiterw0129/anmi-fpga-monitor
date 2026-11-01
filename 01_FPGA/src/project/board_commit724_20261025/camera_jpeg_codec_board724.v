module camera_jpeg_codec_board724 #(
    parameter WIDTH=1280,
    parameter HEIGHT=720,
    parameter WATCHDOG_LIMIT=24'hffffff
)(
    input wire cancel_frame,
    output wire frame_available,frame_admitted,frame_finished,frame_approved_out,
    output wire fault_event,oversize_event,
    input wire [31:0] source_frame_id,
    input wire decision_valid,
    input wire [31:0] decision_frame_id,
    input wire decision_good,
    output wire [31:0] decision_mismatch_count,
    output wire [31:0] decision_duplicate_count,

    output wire [31:0] quality_diagnostic_data,
    input wire [3:0] diagnostic_index,
    output wire [31:0] diagnostic_data,
    input wire clk,
    input wire rst_n,
    input wire [6:0] requested_quality,
    output reg [6:0] active_quality,
    input wire [95:0] rgb4_data,
    input wire rgb4_valid,
    output wire rgb4_ready,
    input wire rgb4_last,
    input wire rgb4_user,
    input wire input_overflow,
    output wire [127:0] packet_data,
    output wire [15:0] packet_keep,
    output wire packet_valid,
    input wire packet_ready,
    output wire packet_last,
    output reg [31:0] oversize_count,
    output wire [31:0] busy_drop_count,
    output reg [31:0] input_fault_count
);
    wire aw_valid;
    wire w_valid;
    wire [4:0] config_addr;
    wire [31:0] config_data;
    wire config_ready;
    wire [6:0] configured_quality;
    wire [31:0] encoder_quality_debug;
    wire config_error;
    wire config_bvalid;
    wire [1:0] config_bresp;
    wire queue_pixel_ready;
    wire aw_ready;
    wire w_ready;
    wire [23:0] pixel_data;
    wire pixel_valid;
    wire pixel_ready;
    wire pixel_last;
    wire pixel_user;
    wire [7:0] jpeg_data;
    wire jpeg_valid;
    wire jpeg_last;
    localparam RESET = 3'd0, IDLE = 3'd1, CAPTURE = 3'd2;
    localparam FINISH = 3'd3, DRAIN = 3'd4;
    reg [2:0] state;
    reg [5:0] startup;
    reg [8:0] column;
    reg [9:0] row;
    reg [23:0] watchdog;
    reg [16:0] jpeg_bytes;
    reg [31:0] admission_drops;
    reg discard_store;
    wire [31:0] store_drops;
    wire [31:0] store_oversize;
    wire queue_ready;
    wire codec_rst_n = rst_n && state != RESET;
    wire admitting = state == CAPTURE || (state == IDLE && rgb4_user);
    wire accepted = rgb4_valid && admitting;
    wire bad_shape = accepted &&
        (rgb4_last != (column == WIDTH/4-1) ||
         (state == CAPTURE && rgb4_user));
    wire rejected_frame;
    wire frame_approved;
    wire timed_out=watchdog>=WATCHDOG_LIMIT;
    // Once an approved complete frame is draining, unrelated later camera
    // faults cannot retract an already advertised AXI transfer.
    wire input_fault;
    // Expose pre-reset events. Polling per-owner counters loses increments
    // when frame_finished resets the codec on the same clock edge.
    assign fault_event=state!=RESET && input_fault;
    assign oversize_event=state!=RESET && !input_fault && jpeg_valid && jpeg_last && jpeg_bytes>=65536;
    assign frame_available=state==IDLE;
    assign frame_admitted=state==IDLE && rgb4_valid && rgb4_user && !input_fault;
    assign frame_approved_out=frame_approved;
    assign frame_finished=state!=RESET && (input_fault ||
        (jpeg_valid && jpeg_last && jpeg_bytes>=65536) ||
        (state==DRAIN && packet_valid && packet_ready && packet_last));
    assign input_fault = (cancel_frame && !frame_approved &&
        (state==CAPTURE || state==FINISH || state==DRAIN)) || ((state == CAPTURE || state == FINISH || accepted) &&
        (input_overflow || config_error || (accepted && !queue_ready) || bad_shape || timed_out)) ||
        ((state == CAPTURE || state == FINISH || state == DRAIN) && rejected_frame) ||
        (state == DRAIN && !frame_approved && timed_out);
    wire [5:0] diagnostic_reasons = {
        timed_out, accepted && state == CAPTURE && rgb4_user,
        accepted && (rgb4_last != (column == WIDTH/4-1)),
        accepted && !queue_ready, config_error, input_overflow
    };
    jpeg_fault_snapshot716 diagnostic (
        .clk(clk), .reset_n(rst_n), .read_index(diagnostic_index), .read_data(diagnostic_data),
        .state(state), .row(row), .column(column), .reasons(diagnostic_reasons), .fault(input_fault),
        .accepted(accepted), .source_valid(rgb4_valid), .source_user(rgb4_user), .source_last(rgb4_last),
        .queue_ready(queue_ready), .packet_valid(packet_valid), .packet_ready(packet_ready), .packet_last(packet_last)
    );
    assign rgb4_ready = 1'b1;
    assign busy_drop_count = admission_drops + store_drops;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;
            startup <= 0;
            column <= 0;
            row <= 0;
            watchdog <= 0;
            jpeg_bytes <= 0;
            admission_drops <= 0;
            input_fault_count <= 0;
            oversize_count <= 0;
            discard_store <= 1;
            active_quality <= 7'd75;
        end else begin
            if (accepted && rgb4_user && !input_fault)
                active_quality <= requested_quality == 0 ? 7'd1 :
                                  requested_quality > 100 ? 7'd100 : requested_quality;
            if (rgb4_valid && rgb4_user && state != IDLE)
                admission_drops <= admission_drops + 1'b1;
            if (state == RESET) begin
                startup <= startup + 1'b1;
                if (startup == 31) begin
                    state <= IDLE;
                    column <= 0;
                    row <= 0;
                    watchdog <= 0;
                    jpeg_bytes <= 0;
                    discard_store <= 0;
                end
            end else if (input_fault) begin
                state <= RESET;
                startup <= 0;
                input_fault_count <= input_fault_count + 1'b1;
                discard_store <= 1;
            end else begin
                if (state == CAPTURE || state == FINISH || (state == DRAIN && !frame_approved))
                    watchdog <= watchdog + 1'b1;
                if (accepted) begin
                    state <= CAPTURE;
                    if (column == WIDTH/4-1) begin
                        column <= 0;
                        row <= row + 1'b1;
                        if (row == HEIGHT-1)
                            state <= FINISH;
                    end else
                        column <= column + 1'b1;
                end
                if (jpeg_valid) begin
                    if (jpeg_bytes != 17'h1ffff)
                        jpeg_bytes <= jpeg_bytes + 1'b1;
                    if (jpeg_last) begin
                        if (jpeg_bytes >= 65536) begin
                            oversize_count <= oversize_count + 1'b1;
                            state <= RESET;
                            startup <= 0;
                            discard_store <= 1;
                        end else
                            state <= DRAIN;
                    end
                end
                if (state == DRAIN && packet_valid && packet_ready && packet_last) begin
                    state <= RESET;
                    startup <= 0;
                end
            end
        end
    end

    jpeg_quality_config configuration (
        .clk(clk), .rst_n(codec_rst_n),
        .frame_accept(accepted && rgb4_user && !input_fault),
        .requested_quality(requested_quality), .active_quality(configured_quality),
        .ready(config_ready), .error(config_error),
        .awaddr(config_addr), .awvalid(aw_valid), .awready(aw_ready),
        .wdata(config_data), .wvalid(w_valid), .wready(w_ready),
        .bvalid(config_bvalid), .bresp(config_bresp)
    );

    assign queue_pixel_ready = pixel_ready && config_ready;

    rgb4_to_jpeg_pixels #(.ADDR_WIDTH(12)) input_queue (
        .clk(clk), .rst_n(codec_rst_n),
        .s_tdata(rgb4_data), .s_tvalid(accepted && !input_fault),
        .s_tready(queue_ready), .s_tlast(rgb4_last), .s_tuser(rgb4_user),
        .m_tdata(pixel_data), .m_tvalid(pixel_valid),
        .m_tready(queue_pixel_ready), .m_tlast(pixel_last), .m_tuser(pixel_user)
    );

    mjpegzero_enc_top723 #(
        .IMG_WIDTH(WIDTH), .IMG_HEIGHT(HEIGHT), .RGB_INPUT(1), .LITE_MODE(0)
    ) encoder (
        .frame_quality_config(active_quality), .quality_debug(encoder_quality_debug),
        .clk(clk), .rst_n(codec_rst_n),
        .s_axis_vid_tdata(pixel_data), .s_axis_vid_tvalid(pixel_valid && config_ready),
        .s_axis_vid_tready(pixel_ready), .s_axis_vid_tlast(pixel_last),
        .s_axis_vid_tuser(pixel_user),
        .m_axis_jpg_tdata(jpeg_data), .m_axis_jpg_tvalid(jpeg_valid),
        .m_axis_jpg_tlast(jpeg_last),
        .s_axi_awaddr(config_addr), .s_axi_awvalid(aw_valid), .s_axi_awready(aw_ready),
        .s_axi_wdata(config_data), .s_axi_wstrb(4'hf),
        .s_axi_wvalid(w_valid), .s_axi_wready(w_ready),
        .s_axi_bresp(config_bresp), .s_axi_bvalid(config_bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(5'd0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b0)
    );

    jpeg_quality_snapshot723 quality_snapshot (
        .clk(clk), .reset_n(rst_n), .read_index(diagnostic_index), .read_data(quality_diagnostic_data),
        .requested_quality(requested_quality), .active_quality(active_quality),
        .configured_quality(configured_quality), .config_ready(config_ready), .config_error(config_error),
        .encoder_debug(encoder_quality_debug), .jpeg_data(jpeg_data),
        .jpeg_valid(jpeg_valid), .jpeg_last(jpeg_last), .jpeg_bytes(jpeg_bytes)
    );

    jpeg_commit_store724 output_queue (
        .frame_begin(state == IDLE && rgb4_valid && rgb4_user), .frame_id(source_frame_id),
        .decision_valid(decision_valid), .decision_frame_id(decision_frame_id),
        .decision_good(decision_good), .rejected_frame(rejected_frame),
        .frame_approved(frame_approved),
        .decision_mismatch_count(decision_mismatch_count),
        .decision_duplicate_count(decision_duplicate_count),
        .clk(clk), .rst_n(rst_n && !discard_store),
        .s_data(jpeg_data), .s_valid(jpeg_valid), .s_last(jpeg_last),
        .m_data(packet_data), .m_keep(packet_keep),
        .m_valid(packet_valid), .m_ready(packet_ready), .m_last(packet_last),
        .oversize_count(store_oversize), .busy_drop_count(store_drops)
    );
endmodule
