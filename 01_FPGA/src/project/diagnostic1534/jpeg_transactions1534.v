// Continuous RGB4 frames may enter while older JPEG/COMMIT data drains.
// Eight identities retain early/late source verdicts. Wire IDs never rewind on
// source/codec recovery. Only session reset may reset an advertised transport.
module jpeg_transactions760 #(
    parameter WIDTH=1920,HEIGHT=1080,QUALITY=50,
    parameter INPUT_BITS=9,OUTPUT_BITS=8,TIMEOUT_CYCLES=125000000
)(
    input wire user_clk,codec_clk,reset_n,source_fault,
    input wire [6:0] requested_quality,
    output wire mode_frame_valid,output reg [31:0] mode_frame_wire_id,
    input wire frame_begin,input wire [31:0] begin_frame_id,
    input wire [95:0] rgb4_data,input wire [31:0] source_frame_id,
    input wire rgb4_valid,rgb4_sof,rgb4_eol,output wire rgb4_ready,
    input wire verdict_valid,input wire [31:0] verdict_id,
    input wire verdict_good,input wire [31:0] verdict_reason,
    output wire [127:0] packet_data,output wire [15:0] packet_keep,
    output wire packet_valid,packet_last,input wire packet_ready,
    output reg [31:0] packet_frame_id,
    output wire committed,aborted,recovering,
    output reg [31:0] admitted_count,committed_count,aborted_count,fault_count,
    output reg [31:0] ignored_verdicts,discarded_count,
    output wire [3:0] queued_frames,
    output wire [(INPUT_BITS>12 ? INPUT_BITS : 12):0] input_used,
    output wire [OUTPUT_BITS-1:0] output_used,
    output reg [31:0] first_fault_code,first_fault_occupancy,queue_peaks
);
    localparam GROUPS=WIDTH*HEIGHT/4,LINE_GROUPS=WIDTH/4;
    reg [31:0] source_ids[0:7],wire_ids[0:7];
    reg [31:0] verdict_reasons[0:7];
    reg [7:0] occupied,known,good,rgb_started;
    reg [2:0] head,tail;
    reg [3:0] count;
    reg [31:0] next_wire_id;
    reg input_open;
    reg [31:0] input_id;
    reg [23:0] group_index;
    reg [12:0] column;
    reg recovering_reg,abort_pending;
    reg [5:0] recovery_wait;
    reg [31:0] recovery_wire_id;
    reg verdict_sent,head_eoi;
    assign recovering=recovering_reg;
    assign queued_frames=count;
    wire codec_ready,codec_fault;
    wire [127:0] jpeg_data;
    wire [15:0] jpeg_keep;
    wire [31:0] jpeg_id;
    wire jpeg_valid,jpeg_sof,jpeg_last,jpeg_ready;
    wire codec_reset_n=reset_n && !recovering_reg;
    wire ingress=!recovering_reg && (input_open || rgb4_sof);
    wire candidate=rgb4_valid && ingress;
    // Capacity was reserved at RAW begin; the eighth admitted frame must still
    // be allowed to emit its delayed RGB SOF when the metadata queue is full.
    assign rgb4_ready=!recovering_reg && codec_ready && (input_open || rgb4_sof);
    wire duplicate_source;
    wire push=frame_begin && !recovering_reg && count<8 && !duplicate_source;
    wire accepted=candidate && rgb4_ready;
    assign duplicate_source=(occupied[0]&&source_ids[0]==begin_frame_id) ||
        (occupied[1]&&source_ids[1]==begin_frame_id) || (occupied[2]&&source_ids[2]==begin_frame_id) ||
        (occupied[3]&&source_ids[3]==begin_frame_id) || (occupied[4]&&source_ids[4]==begin_frame_id) ||
        (occupied[5]&&source_ids[5]==begin_frame_id) || (occupied[6]&&source_ids[6]==begin_frame_id) ||
        (occupied[7]&&source_ids[7]==begin_frame_id);
    reg rgb_identity_valid,rgb_identity_used;
    always @* begin
        rgb_identity_valid=push && begin_frame_id==source_frame_id;
        rgb_identity_used=0;
        for(integer k=0;k<8;k=k+1)if(occupied[k] && source_ids[k]==source_frame_id)begin
            rgb_identity_valid=1;rgb_identity_used=rgb_started[k];
        end
    end
    // Reuse the reserved source-to-wire identity, including same-cycle admission.
    // This event refers to RGB acceptance, never a polled/latest frame counter.
    always @* begin
        mode_frame_wire_id=next_wire_id;
        for(integer k=0;k<8;k=k+1)
            if(occupied[k] && source_ids[k]==source_frame_id)
                mode_frame_wire_id=wire_ids[k];
    end
    wire shape_fault=candidate && (rgb4_sof ? input_open || !rgb_identity_valid || rgb_identity_used || rgb4_eol!=(LINE_GROUPS==1) :
        source_frame_id!=input_id || rgb4_eol!=(column==LINE_GROUPS-1));
    wire overflow_fault=candidate && !rgb4_ready;
    wire active,start_ready,transport_ready,flush,transaction_done;
    wire output_mismatch=jpeg_valid && count!=0 && !head_eoi && jpeg_id!=source_ids[head];
    reg verdict_match;
    integer scan;
    always @* begin
        verdict_match=push && verdict_id==begin_frame_id;
        for(integer k=0;k<8;k=k+1)if(occupied[k] && source_ids[k]==verdict_id)verdict_match=1;
    end
    wire bad_verdict=verdict_valid && verdict_match && !verdict_good;
    wire fault_now=!recovering_reg && (source_fault || codec_fault || shape_fault || overflow_fault || output_mismatch || bad_verdict || aborted || (frame_begin && (count==8 || duplicate_source)));
    assign mode_frame_valid=accepted && rgb4_sof && !fault_now;
    // Passive session diagnostics. All samples are in user_clk: output_used
    // is already the read-side count with synchronized crossing pointers.
    // Code bits 0..8: source, codec, shape, overflow, output identity,
    // bad verdict, transport abort, queue full, duplicate admission.
    // Bits 12..9 preserve the rejected source geometry reason (zero if absent).
    // Bits 31..13 hold the RGB group index at the first fault.
    wire [8:0] fault_causes={frame_begin && duplicate_source,
        frame_begin && count==8,aborted,bad_verdict,output_mismatch,
        overflow_fault,shape_fault,codec_fault,source_fault};
    wire [14:0] input_sample=input_used;
    wire [7:0] output_sample=output_used;
    always @(posedge user_clk or negedge reset_n)begin
        if(!reset_n)begin first_fault_code<=0;first_fault_occupancy<=0;queue_peaks<=0;end
        else begin
            if(input_sample>queue_peaks[14:0])queue_peaks[14:0]<=input_sample;
            if(output_sample>queue_peaks[22:15])queue_peaks[22:15]<=output_sample;
            if(fault_now && first_fault_code==0)begin
                first_fault_code<={group_index[18:0],bad_verdict ? verdict_reason[3:0] : 4'd0,fault_causes};
                first_fault_occupancy<={5'd0,count,output_sample,input_sample};
            end
        end
    end
    wire normal_start=!recovering_reg && count!=0 && jpeg_valid && jpeg_sof && jpeg_id==source_ids[head];
    wire forced_start=recovering_reg && abort_pending;
    wire start=(normal_start || forced_start) && !active && start_ready;
    wire [31:0] start_id=forced_start ? recovery_wire_id : wire_ids[head];
    wire send_verdict=!recovering_reg && active && count!=0 && known[head] && !verdict_sent;
    assign jpeg_ready=!recovering_reg && active && count!=0 && jpeg_id==source_ids[head] && transport_ready;
    jpeg_cdc748 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.QUALITY(QUALITY),.INPUT_BITS(INPUT_BITS),.OUTPUT_BITS(OUTPUT_BITS)) codec(
        .user_clk(user_clk),.codec_clk(codec_clk),.reset_n(codec_reset_n),
        .requested_quality(requested_quality),
        .rgb4_data(rgb4_data),.source_frame_id(source_frame_id),.rgb4_valid(candidate),
        .rgb4_sof(rgb4_sof),.rgb4_eol(rgb4_eol),.rgb4_ready(codec_ready),
        .jpeg_data(jpeg_data),.jpeg_keep(jpeg_keep),.jpeg_frame_id(jpeg_id),
        .jpeg_sof(jpeg_sof),.jpeg_last(jpeg_last),.jpeg_valid(jpeg_valid),.jpeg_ready(jpeg_ready),
        .fault(codec_fault),.input_used(input_used),.output_used(output_used));
    jpeg_segment733 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) transport(
        .clk(user_clk),.reset(!reset_n),.start_valid(start),.start_id(start_id),.start_ready(start_ready),
        .verdict_valid(send_verdict),.verdict_id(packet_frame_id),.verdict_good(good[head]),.verdict_reason(verdict_reasons[head]),
        .abort_valid(recovering_reg || fault_now),.abort_reason(32'd3),
        .s_data(jpeg_data),.s_keep(jpeg_keep),.s_valid(jpeg_valid && !recovering_reg && count!=0 && jpeg_id==source_ids[head]),
        .s_sof(jpeg_sof),.s_last(jpeg_last),.s_ready(transport_ready),
        .m_data(packet_data),.m_keep(packet_keep),.m_valid(packet_valid),.m_ready(packet_ready),.m_last(packet_last),
        .active(active),.flush(flush),.transaction_done(transaction_done),.committed(committed),.aborted(aborted),.ignored_verdicts());
    always @(posedge user_clk or negedge reset_n)begin
        if(!reset_n)begin
            occupied<=0;known<=0;good<=0;rgb_started<=0;head<=0;tail<=0;count<=0;next_wire_id<=0;
            input_open<=0;input_id<=0;group_index<=0;column<=0;recovering_reg<=0;abort_pending<=0;recovery_wait<=0;recovery_wire_id<=0;
            packet_frame_id<=0;verdict_sent<=0;head_eoi<=0;
            admitted_count<=0;committed_count<=0;aborted_count<=0;fault_count<=0;ignored_verdicts<=0;discarded_count<=0;
            for(scan=0;scan<8;scan=scan+1)begin source_ids[scan]<=0;wire_ids[scan]<=0;verdict_reasons[scan]<=0;end
        end else begin
            if(committed)committed_count<=committed_count+1'b1;
            if(aborted)aborted_count<=aborted_count+1'b1;
            if(start)begin packet_frame_id<=start_id;verdict_sent<=0;head_eoi<=0;end
            if(send_verdict)verdict_sent<=1;
            if(jpeg_valid && jpeg_ready && jpeg_last)head_eoi<=1;
            if(fault_now)begin
                recovering_reg<=1;recovery_wait<=31;fault_count<=fault_count+1'b1;
                // Retain the advertised transaction; unadvertised queued IDs become gaps.
                abort_pending<=!transaction_done && (active || count!=0);
                recovery_wire_id<=active ? packet_frame_id : wire_ids[head];
                discarded_count<=discarded_count+count-(transaction_done ? 1'b1 : 1'b0);
                occupied<=0;known<=0;good<=0;rgb_started<=0;head<=0;tail<=0;count<=0;
                input_open<=0;group_index<=0;column<=0;
            end else if(recovering_reg)begin
                if(transaction_done)abort_pending<=0;
                if(!abort_pending && !active)begin
                    if(recovery_wait==0)begin recovering_reg<=0;head_eoi<=0;end
                    else recovery_wait<=recovery_wait-1'b1;
                end
            end else begin
                if(verdict_valid)begin
                    if(!verdict_match)ignored_verdicts<=ignored_verdicts+1'b1;
                    for(scan=0;scan<8;scan=scan+1)if(occupied[scan] && source_ids[scan]==verdict_id && !known[scan])begin
                        known[scan]<=1;good[scan]<=verdict_good;verdict_reasons[scan]<=verdict_reason;
                    end
                end
                if(push)begin
                    source_ids[tail]<=begin_frame_id;wire_ids[tail]<=next_wire_id;occupied[tail]<=1;rgb_started[tail]<=0;
                    known[tail]<=verdict_valid && verdict_id==begin_frame_id;
                    good[tail]<=verdict_good;verdict_reasons[tail]<=verdict_reason;
                    tail<=tail+1'b1;next_wire_id<=next_wire_id+1'b1;admitted_count<=admitted_count+1'b1;
                end
                if(accepted && rgb4_sof)begin
                    for(scan=0;scan<8;scan=scan+1)if(occupied[scan] && source_ids[scan]==source_frame_id)rgb_started[scan]<=1;
                    if(push && begin_frame_id==source_frame_id)rgb_started[tail]<=1;
                    input_id<=source_frame_id;input_open<=GROUPS!=1;group_index<=1;
                    column<=LINE_GROUPS==1 ? 0 : 1;
                end else if(accepted)begin
                    group_index<=group_index+1'b1;
                    if(column==LINE_GROUPS-1)column<=0;else column<=column+1'b1;
                    if(group_index==GROUPS-1)input_open<=0;
                end
                if(transaction_done)begin occupied[head]<=0;known[head]<=0;rgb_started[head]<=0;head<=head+1'b1;head_eoi<=0;end
                case({push,transaction_done})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
            end
        end
    end
endmodule
