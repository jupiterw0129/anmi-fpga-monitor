// Checked RAW -> actual ISP -> independent frame identities -> streaming JPG2.
// source_ok is a user-clock-domain level. Only session reset clears transport.
module camera_stream774 #(
    parameter WIDTH=1920,HEIGHT=1080,QUALITY=50
)(
    input wire user_clk,codec_clk,reset_n,source_ok,
    input wire [6:0] requested_quality,
    input wire stop_requested,admission_stopped,output wire stop_ready,
    input wire frame_begin,input wire [31:0] begin_id,
    input wire [39:0] raw_data,input wire raw_valid,raw_sof,raw_eol,
    input wire [31:0] raw_id,output wire raw_ready,
    input wire verdict_valid,verdict_good,input wire [31:0] verdict_id,verdict_reason,
    input wire [14:0] cfg_crop_start,cfg_crop_end,cfg_crop_horizontal,
    input wire [2:0] cfg_mask,input wire [1:0] cfg_advanced,cfg_morphology,
    input wire [7:0] cfg_threshold,
    input wire [1:0] cfg_bayer_phase,output wire [1:0] active_bayer_phase,
    output wire [127:0] packet_data,output wire [15:0] packet_keep,
    output wire packet_valid,packet_last,input wire packet_ready,
    output wire [31:0] packet_frame_id,
    output wire [2:0] active_mask,
    output wire [1:0] active_advanced,active_morphology,
    output wire mode_frame_valid,output wire [31:0] mode_frame_wire_id,
    output wire [7:0] active_threshold,
    output wire committed,aborted,recovering,busy,
    output wire [31:0] admitted_count,committed_count,aborted_count,fault_count,
    output wire [31:0] first_fault_code,first_fault_occupancy,queue_peaks
);
    reg source_was_ok;
    reg [5:0] settle;
    reg [14:0] crop_start,crop_end,crop_horizontal;
    reg [2:0] mask;reg [1:0] advanced,morphology;reg [7:0] threshold;reg [1:0] bayer_phase;
    wire [3:0] pending_raw,pending_rgb,queued;
    // Distinct registers prevent the ISP reset tree from also driving the
    // transaction's tag/abort combinational cone. They assert asynchronously
    // on session reset and take the same user-domain run decision each edge.
    // Source faults still reach transactions immediately; advertised packets
    // and COMMIT/ABORT decisions are not pipelined or reset here.
    (* dont_touch="true" *) reg pipeline_go,isp_reset_n,tags_reset_n;
    wire next_pipeline_go=source_ok && !recovering && settle==63;
    always @(posedge user_clk or negedge reset_n)begin
        if(!reset_n)begin pipeline_go<=0;isp_reset_n<=0;tags_reset_n<=0;end
        else begin
            pipeline_go<=next_pipeline_go;
            isp_reset_n<=next_pipeline_go;
            tags_reset_n<=next_pipeline_go;
        end
    end
    wire isp_ready;
    wire [95:0] isp_data;
    wire isp_valid,isp_sof,isp_eol,rgb_ready;
    wire [31:0] rgb_id;
    wire tag_fault;
    wire begin_valid=frame_begin && pipeline_go;
    wire source_event;
    camera_stop_guard1018 stop_guard(
        .clk(user_clk),.reset_n(reset_n),.source_ok(source_ok),
        .source_event(source_was_ok && !source_ok),.stop_requested(stop_requested),
        .admission_stopped(admission_stopped),.busy(busy),
        .forwarded_source_event(source_event),.stop_ready(stop_ready));
    // Buffer payload, identity and raster flags as one handshake unit. The
    // receiver's metadata RAM now ends at these registers instead of feeding
    // the tag/fault/transport decision in the same user-clock cycle.
    (* dont_touch="true" *) reg [39:0] raw_hold_data;
    (* dont_touch="true" *) reg [31:0] raw_hold_id;
    (* dont_touch="true" *) reg raw_hold_valid,raw_hold_sof,raw_hold_eol;
    wire raw_hold_ready=!raw_hold_valid || isp_ready;
    assign raw_ready=pipeline_go ? raw_hold_ready : 1'b1;
    always @(posedge user_clk or negedge isp_reset_n)begin
        if(!isp_reset_n)begin
            raw_hold_data<=0;raw_hold_id<=0;raw_hold_valid<=0;raw_hold_sof<=0;raw_hold_eol<=0;
        end else if(raw_hold_ready)begin
            raw_hold_valid<=raw_valid;
            if(raw_valid)begin
                raw_hold_data<=raw_data;raw_hold_id<=raw_id;
                raw_hold_sof<=raw_sof;raw_hold_eol<=raw_eol;
            end
        end
    end
    assign busy=queued!=0 || pending_raw!=0 || pending_rgb!=0 || recovering;
    always @(posedge user_clk or negedge reset_n)begin
        if(!reset_n)begin
            source_was_ok<=0;settle<=0;
            crop_start<=35;crop_end<=HEIGHT+36;crop_horizontal<=WIDTH/4+1;
            mask<=0;advanced<=0;morphology<=0;threshold<=128;bayer_phase<=0;
        end else begin
            source_was_ok<=source_ok;
            if(!source_ok || recovering)settle<=0;
            else if(settle!=63)settle<=settle+1'b1;
            // Only the required 1080p selector may follow live requests.
            // required_preprocess1070 latches it at an accepted input SOF;
            // it drains both parallel branches before admitting the next SOF.
            if(WIDTH==1920 && HEIGHT==1080)morphology<=cfg_morphology;
            // All other configuration remains held while frames are in flight.
            if(queued==0 && pending_raw==0 && pending_rgb==0 && !begin_valid)begin
                crop_start<=cfg_crop_start;crop_end<=cfg_crop_end;crop_horizontal<=cfg_crop_horizontal;
                mask<=cfg_mask;advanced<=cfg_advanced;morphology<=cfg_morphology;threshold<=cfg_threshold;bayer_phase<=cfg_bayer_phase;
            end
        end
    end
    camera_tags766 tags(
        .clk(user_clk),.reset_n(tags_reset_n),.frame_begin(begin_valid),.begin_id(begin_id),
        .raw_fire(raw_hold_valid && isp_ready && pipeline_go),.raw_sof(raw_hold_sof),.raw_id(raw_hold_id),
        .rgb_valid(isp_valid && pipeline_go),.rgb_sof(isp_sof),.rgb_id(rgb_id),.fault(tag_fault),
        .pending_raw(pending_raw),.pending_rgb(pending_rgb));
    camera_isp724 isp(
        .cfg_bayer_phase(bayer_phase),.active_bayer_phase(active_bayer_phase),
        .user_clk(user_clk),.user_rst_n(isp_reset_n),.mipi_tdata(raw_hold_data),
        .mipi_tvalid(raw_hold_valid && pipeline_go),.mipi_tlast(raw_hold_eol && raw_hold_valid && pipeline_go),
        .mipi_tuser(raw_hold_sof && raw_hold_valid && pipeline_go),.mipi_tready(isp_ready),
        .cfg_img_width(WIDTH[12:0]),.cfg_img_height(HEIGHT[12:0]),
        .cfg_crop_v_start(crop_start),.cfg_crop_v_end(crop_end),.cfg_crop_h_end(crop_horizontal),
        .cfg_preprocess_mask(mask),.cfg_advanced_mode(advanced),.cfg_morphology_mode(morphology),
        .cfg_advanced_threshold(threshold),.preprocess_active_mask(active_mask),.advanced_active_mode(active_advanced),
        .morphology_active_mode(active_morphology),.advanced_active_threshold(active_threshold),
        .output_data(isp_data),.output_valid(isp_valid),.output_user(isp_sof),.output_last(isp_eol));
    jpeg_transactions760 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.QUALITY(QUALITY),.INPUT_BITS(14)) transactions(
        .user_clk(user_clk),.codec_clk(codec_clk),.reset_n(reset_n),
        .source_fault(source_event || (tag_fault && pipeline_go)),
        .requested_quality(requested_quality),
        .mode_frame_valid(mode_frame_valid),.mode_frame_wire_id(mode_frame_wire_id),
        .frame_begin(begin_valid),.begin_frame_id(begin_id),.rgb4_data(isp_data),.source_frame_id(rgb_id),
        .rgb4_valid(isp_valid && pipeline_go),.rgb4_sof(isp_sof),.rgb4_eol(isp_eol),.rgb4_ready(rgb_ready),
        .verdict_valid(verdict_valid && source_ok),.verdict_id(verdict_id),.verdict_good(verdict_good),.verdict_reason(verdict_reason),
        .packet_data(packet_data),.packet_keep(packet_keep),.packet_valid(packet_valid),.packet_last(packet_last),
        .packet_ready(packet_ready),.packet_frame_id(packet_frame_id),.committed(committed),.aborted(aborted),.recovering(recovering),
        .admitted_count(admitted_count),.committed_count(committed_count),.aborted_count(aborted_count),.fault_count(fault_count),
        .ignored_verdicts(),.discarded_count(),.queued_frames(queued),.input_used(),.output_used(),
        .first_fault_code(first_fault_code),.first_fault_occupancy(first_fault_occupancy),.queue_peaks(queue_peaks));
endmodule
