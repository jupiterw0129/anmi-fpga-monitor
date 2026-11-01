// One admitted source identity owns every ISP stage, RGB FIFO and JPEG encoder
// until completion/rejection. Other source frames drain and are explicitly
// counted as skips. No newer CSI ID can relabel a delayed RGB SOF.
module camera_owned_board724 #(
    parameter WIDTH=1280, HEIGHT=720, OWNER_TIMEOUT=24'hffffff
)(
    input wire clk,reset_n,enable,
    input wire [12:0] cfg_img_width,cfg_img_height,
    input wire [14:0] cfg_crop_v_start,cfg_crop_v_end,cfg_crop_h_end,
    input wire [2:0] cfg_preprocess_mask,
    input wire [1:0] cfg_advanced_mode,cfg_morphology_mode,
    input wire [7:0] cfg_advanced_threshold,
    input wire [6:0] requested_quality,
    input wire frame_begin,
    input wire [31:0] begin_frame_id,
    input wire [39:0] raw_data,
    input wire raw_valid,raw_sof,raw_eol,
    output wire raw_ready,
    input wire [31:0] raw_frame_id,
    input wire decision_valid,
    output wire decision_ready,
    input wire [31:0] decision_frame_id,
    input wire decision_good,
    output wire [127:0] packet_data,
    output wire [15:0] packet_keep,
    output wire packet_valid,packet_last,
    input wire packet_ready,
    output wire [31:0] packet_frame_id,
    output reg [31:0] admitted_count,skipped_count,rejected_count,completed_count,timeout_count,
    output wire [31:0] oversize_count,busy_drop_count,input_fault_count,
    output wire [2:0] preprocess_active_mask,
    output wire [1:0] advanced_active_mode,morphology_active_mode,
    output wire [7:0] advanced_active_threshold,
    output wire [6:0] active_quality,
    output wire overflow_event,codec_fault_event,codec_oversize_event,
    input wire [3:0] diagnostic_index,
    output wire [31:0] diagnostic_data,quality_diagnostic_data
);
    localparam SETTLE=0,FREE=1,ACTIVE=2;
    reg [1:0] state;
    reg recovering;
    reg [5:0] settle_cycles;
    reg [31:0] owner_id;
    reg verdict_known,verdict_good,codec_started,codec_done,local_bad;
    reg [23:0] timer;
    reg [12:0] img_width,img_height;
    reg [14:0] crop_v_start,crop_v_end,crop_h_end;
    reg [2:0] mask;
    reg [1:0] advanced,morphology;
    reg [7:0] threshold;
    reg [6:0] quality;
    wire owned=state==ACTIVE;
    wire matching_verdict=owned && decision_valid && decision_frame_id==owner_id && !verdict_known;
    wire source_bad=matching_verdict && !decision_good;
    wire known_bad=local_bad || (verdict_known && !verdict_good);
    wire frame_available,frame_admitted,frame_finished,frame_approved;
    wire timed_out=owned && !frame_approved && timer>=OWNER_TIMEOUT;
    wire [95:0] isp_data;
    wire isp_valid,isp_last,isp_user,isp_ready;
    wire fifo_full,fifo_empty;
    wire [129:0] fifo_data;
    wire fifo_overflow=owned && isp_valid && fifo_full;
    assign overflow_event=fifo_overflow && !local_bad;
    // Flush invalid line/frame state; preserve AWB gain history after good
    // frames. No upstream error belonging to another identity resets a drain.
    wire isp_reset_request=reset_n && !(state==SETTLE && recovering) &&
        !(owned && (known_bad || source_bad || fifo_overflow || timed_out));
    // Local ISP reset is registered; RAW gating and codec/FIFO cancellation
    // remain immediate. Global source reset still asserts asynchronously.
    reg isp_reset_n;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)isp_reset_n<=1'b0;
        else isp_reset_n<=isp_reset_request;
    end
    wire feed_raw=owned && raw_frame_id==owner_id && !known_bad && !source_bad && !timed_out;
    assign raw_ready=feed_raw ? isp_ready : 1'b1;
    assign decision_ready=1'b1;
    assign packet_frame_id=owner_id;
    camera_isp724 isp (
        .user_clk(clk),.user_rst_n(isp_reset_n),.mipi_tdata(raw_data),
        .mipi_tvalid(raw_valid && feed_raw),
        .mipi_tlast(raw_eol && raw_valid && feed_raw),
        .mipi_tuser(raw_sof && raw_valid && feed_raw),.mipi_tready(isp_ready),
        .cfg_img_width(img_width),.cfg_img_height(img_height),
        .cfg_crop_v_start(crop_v_start),.cfg_crop_v_end(crop_v_end),.cfg_crop_h_end(crop_h_end),
        .cfg_preprocess_mask(mask),.cfg_advanced_mode(advanced),.cfg_morphology_mode(morphology),
        .cfg_advanced_threshold(threshold),.preprocess_active_mask(preprocess_active_mask),
        .advanced_active_mode(advanced_active_mode),.morphology_active_mode(morphology_active_mode),
        .advanced_active_threshold(advanced_active_threshold),
        .output_data(isp_data),.output_valid(isp_valid),.output_last(isp_last),.output_user(isp_user)
    );
    wire [127:0] padded_rgb={8'd0,isp_data[95:72],8'd0,isp_data[71:48],8'd0,isp_data[47:24],8'd0,isp_data[23:0]};
    wire codec_reset_n=reset_n && owned;
    wire fifo_reset_n=codec_reset_n && !known_bad && !source_bad && !timed_out;
    sync_fifo_130 #(.ADDR_WIDTH(10)) rgb_fifo (
        .clk(clk),.rst_n(fifo_reset_n),.wr_data({isp_user,isp_last,padded_rgb}),
        .wr_en(owned && isp_valid && !fifo_full && !known_bad),.full(fifo_full),
        .rd_data(fifo_data),.rd_en(!fifo_empty),.empty(fifo_empty)
    );
    wire [95:0] rgb_data={fifo_data[119:96],fifo_data[87:64],fifo_data[55:32],fifo_data[23:0]};
    // The verdict may predate RGB SOF by arbitrarily many cycles; replay starts
    // only after the actual codec admission edge, and delivers exactly once.
    reg verdict_sent;
    wire replay_valid=owned && codec_started && verdict_known && !verdict_sent;
    wire cancel=owned && (local_bad || timed_out);
    camera_jpeg_codec_board724 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.WATCHDOG_LIMIT(OWNER_TIMEOUT)) codec (
        .fault_event(codec_fault_event),.oversize_event(codec_oversize_event),
        .clk(clk),.rst_n(codec_reset_n),.cancel_frame(cancel),
        .frame_available(frame_available),.frame_admitted(frame_admitted),
        .frame_finished(frame_finished),.frame_approved_out(frame_approved),
        .source_frame_id(owner_id),.decision_valid(replay_valid),
        .decision_frame_id(owner_id),.decision_good(verdict_good),
        .decision_mismatch_count(),.decision_duplicate_count(),
        .requested_quality(quality),.active_quality(active_quality),
        .rgb4_data(rgb_data),.rgb4_valid(owned && !fifo_empty && !known_bad && !source_bad),
        .rgb4_ready(),.rgb4_last(fifo_data[128]),.rgb4_user(fifo_data[129]),
        .input_overflow(fifo_overflow),
        .packet_data(packet_data),.packet_keep(packet_keep),.packet_valid(packet_valid),
        .packet_ready(packet_ready),.packet_last(packet_last),
        .oversize_count(oversize_count),.busy_drop_count(busy_drop_count),.input_fault_count(input_fault_count),
        .diagnostic_index(diagnostic_index),.diagnostic_data(diagnostic_data),.quality_diagnostic_data(quality_diagnostic_data)
    );
    wire owner_finished=owned && (timed_out ||
        ((verdict_known || matching_verdict) &&
         (codec_done || frame_finished || (!codec_started && (known_bad || source_bad)))));
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state<=SETTLE; recovering<=1; settle_cycles<=0; owner_id<=0;
            verdict_known<=0; verdict_good<=0; codec_started<=0; codec_done<=0; local_bad<=0;
            verdict_sent<=0; timer<=0;
            // The legacy demosaic initializes its line width immediately
            // after reset, before the first admitted RAW frame arrives.
            img_width<=WIDTH; img_height<=HEIGHT; crop_v_start<=0; crop_v_end<=0; crop_h_end<=0;
            mask<=0; advanced<=0; morphology<=0; threshold<=0; quality<=0;
            admitted_count<=0; skipped_count<=0; rejected_count<=0; completed_count<=0; timeout_count<=0;
        end else begin
            if(state==SETTLE) begin
                settle_cycles<=settle_cycles+1'b1;
                if(settle_cycles==63) begin state<=FREE; recovering<=0; end
            end
            if(frame_begin) begin
                if(state==FREE && enable && cfg_img_width==WIDTH && cfg_img_height==HEIGHT) begin
                    state<=ACTIVE; owner_id<=begin_frame_id; timer<=0;
                    verdict_known<=0; verdict_good<=0; codec_started<=0; codec_done<=0;
                    local_bad<=0; verdict_sent<=0; admitted_count<=admitted_count+1'b1;
                    img_width<=cfg_img_width; img_height<=cfg_img_height;
                    crop_v_start<=cfg_crop_v_start; crop_v_end<=cfg_crop_v_end; crop_h_end<=cfg_crop_h_end;
                    mask<=cfg_preprocess_mask; advanced<=cfg_advanced_mode; morphology<=cfg_morphology_mode;
                    threshold<=cfg_advanced_threshold; quality<=requested_quality;
                end else skipped_count<=skipped_count+1'b1;
            end
            if(owned) begin
                if(!frame_approved && timer!=24'hffffff) timer<=timer+1'b1;
                if(matching_verdict) begin verdict_known<=1; verdict_good<=decision_good; end
                if(frame_admitted) codec_started<=1;
                if(frame_finished) codec_done<=1;
                if(replay_valid) verdict_sent<=1;
                if(fifo_overflow || (frame_finished && !(packet_valid && packet_ready && packet_last))) local_bad<=1;
                if(owner_finished) begin
                    state<=SETTLE; settle_cycles<=0;
                    recovering<=known_bad || source_bad || timed_out ||
                        !(packet_valid && packet_ready && packet_last);
                    if(packet_valid && packet_ready && packet_last) completed_count<=completed_count+1'b1;
                    else rejected_count<=rejected_count+1'b1;
                    if(timed_out) timeout_count<=timeout_count+1'b1;
                    local_bad<=0;
                end
            end
        end
    end
endmodule
