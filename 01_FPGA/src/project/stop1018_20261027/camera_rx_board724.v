// Isolated byte-to-validated-RAW candidate. Source raster configuration must
// come from measured sensor mode timing, independently of the crop rectangle.
module camera_rx_board724 #(
    parameter MAX_BYTES=8192, QUEUE_BITS=4, FIFO_BITS=12
)(
    input wire source_clk, source_reset_n, enable,
    input wire [31:0] input_data,
    input wire input_valid,
    input wire dest_clk, dest_reset_n,
    input wire stop_requested,output wire admission_stopped,
    input wire [15:0] cfg_beats_per_line, cfg_lines_per_frame,
    output wire [39:0] pixel_data,
    output wire pixel_valid,
    input wire pixel_ready,
    input wire [3:0] observation_index,
    output wire [31:0] observation_data,
    output wire pixel_sof, pixel_eol,
    output wire [31:0] pixel_frame_id,
    output wire frame_begin,
    output wire [31:0] begin_frame_id,
    output wire pipeline_abort,
    output wire pipeline_reset_n,
    output wire decision_valid,
    input wire decision_ready,
    output wire [31:0] decision_frame_id,
    output wire decision_good,
    output wire [3:0] decision_reason,
    output wire [31:0] good_count, bad_count, orphan_count,
    output wire packet_done,sync_wait,header_attempt,header_valid,
    output wire header_bad, filter_bad, crc_bad, truncated, overflow, queue_overflow
);
    wire [39:0] raw_data;
    wire raw_valid,raw_ready,raw_sof,raw_eol,raw_abort,raw_end,raw_start;
    wire validation_reset_n;
    // Two elastic slots break the geometry/ISP ready path before it reaches
    // the RAW decoder and the CDC FIFO RAM prefetch address logic.
    reg [44:0] skid [0:1];
    reg write_index,read_index;
    reg [1:0] skid_count;
    wire [44:0] held=skid[read_index];
    wire geometry_ready,admission_ready,admission_valid;
    camera_admission1018 admission (
        .clk(dest_clk),.reset_n(validation_reset_n),.stop_requested(stop_requested),
        .s_valid(skid_count!=0),.s_ready(admission_ready),
        .s_frame_start(held[0]),.s_frame_end(held[1]),.s_abort(held[2]),
        .m_valid(admission_valid),.m_ready(geometry_ready),.stopped(admission_stopped));
    wire push=raw_valid && raw_ready;
    wire pop=skid_count!=0 && admission_ready;
    assign raw_ready=skid_count!=2;
    always @(posedge dest_clk or negedge validation_reset_n) begin
        if (!validation_reset_n) begin write_index<=0; read_index<=0; skid_count<=0; end
        else begin
            if (push) begin
                skid[write_index]<={raw_data,raw_sof,raw_eol,raw_abort,raw_end,raw_start};
                write_index<=!write_index;
            end
            if (pop) read_index<=!read_index;
            case ({push,pop})
                2'b10: skid_count<=skid_count+1'b1;
                2'b01: skid_count<=skid_count-1'b1;
            endcase
        end
    end
    // Every downstream identity consumer must share this reset epoch.
    assign pipeline_reset_n=validation_reset_n;
    // Same shared reset and synchronizer as receiver destination, including
    // source-only reset and disable; no orphaned identity survives a CDC flush.
    board_reset_release validation_release(dest_clk,
        source_reset_n && dest_reset_n && enable,validation_reset_n);
    csi_geometry_rx724 #(.MAX_BYTES(MAX_BYTES),.QUEUE_BITS(QUEUE_BITS),.FIFO_BITS(FIFO_BITS)) rx (
        .source_clk(source_clk),.source_reset_n(source_reset_n),.enable(enable),
        .input_data(input_data),.input_valid(input_valid),
        .packet_done(packet_done),.sync_wait(sync_wait),.header_attempt(header_attempt),.header_valid(header_valid),
        .header_bad(header_bad),.filter_bad(filter_bad),.crc_bad(crc_bad),
        .truncated(truncated),.overflow(overflow),.queue_overflow(queue_overflow),
        .dest_clk(dest_clk),.dest_reset_n(dest_reset_n),.output_data(raw_data),
        .output_valid(raw_valid),.output_ready(raw_ready),.output_sof(raw_sof),
        .output_eol(raw_eol),.output_abort(raw_abort),.output_frame_end(raw_end),
        .output_frame_start(raw_start)
    );
    raw_raster_observer724 raster_observer (
        .clk(dest_clk),.reset_n(validation_reset_n),.transfer(pop),
        .is_start(held[0]),.is_end(held[1]),.is_abort(held[2]),.is_eol(held[3]),
        .index(observation_index),.read_data(observation_data)
    );
    csi_frame_geometry724 geometry (
        .clk(dest_clk),.reset_n(validation_reset_n),
        .cfg_beats_per_line(cfg_beats_per_line),.cfg_lines_per_frame(cfg_lines_per_frame),
        .s_data(held[44:5]),.s_valid(admission_valid),.s_ready(geometry_ready),
        .s_sof(held[4]),.s_eol(held[3]),.s_abort(held[2]),.s_frame_end(held[1]),.s_frame_start(held[0]),
        .pixel_data(pixel_data),.pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
        .pixel_sof(pixel_sof),.pixel_eol(pixel_eol),.pixel_frame_id(pixel_frame_id),
        .frame_begin(frame_begin),.begin_frame_id(begin_frame_id),.pipeline_abort(pipeline_abort),
        .decision_valid(decision_valid),.decision_ready(decision_ready),
        .decision_frame_id(decision_frame_id),.decision_good(decision_good),.decision_reason(decision_reason),
        .good_count(good_count),.bad_count(bad_count),.orphan_count(orphan_count)
    );
endmodule
