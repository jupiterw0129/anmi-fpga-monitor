// The source identity owns ISP/FIFO/transport until a terminal packet transfers.
// Source reset/disable aborts the transaction; it never resets a stalled packet.
module camera_owned_lossless725 #(
    parameter WIDTH=1920,HEIGHT=1080,FIFO_BITS=10,WAIT_CYCLES=12500000,EXTERNAL_ISP=0
)(
    input wire clk,reset_n,source_reset_n,enable,
    input wire [95:0] ext_isp_data,input wire ext_isp_valid,ext_isp_last,ext_isp_user,ext_isp_ready,
    input wire [2:0] ext_active_mask,input wire [1:0] ext_active_advanced,ext_active_morphology,
    input wire [7:0] ext_active_threshold,
    output wire external_reset_n,external_raw_valid,external_raw_sof,external_raw_eol,
    output wire [39:0] external_raw_data,
    output wire [12:0] external_width,external_height,
    output wire [14:0] external_crop_start,external_crop_end,external_crop_horizontal,
    output wire [2:0] external_mask,output wire [1:0] external_advanced,external_morphology,
    output wire [7:0] external_threshold,
    input wire [12:0] cfg_img_width,cfg_img_height,
    input wire [14:0] cfg_crop_v_start,cfg_crop_v_end,cfg_crop_h_end,
    input wire [2:0] cfg_preprocess_mask,
    input wire [1:0] cfg_advanced_mode,cfg_morphology_mode,
    input wire [7:0] cfg_advanced_threshold,
    input wire frame_begin,input wire [31:0] begin_frame_id,
    input wire [39:0] raw_data,input wire raw_valid,raw_sof,raw_eol,
    output wire raw_ready,input wire [31:0] raw_frame_id,
    input wire decision_valid,input wire [31:0] decision_frame_id,
    input wire decision_good,input wire [3:0] decision_reason,
    output wire [127:0] packet_data,output wire [15:0] packet_keep,
    output wire packet_valid,packet_last,input wire packet_ready,
    output wire [31:0] packet_frame_id,source_owner_id,output wire busy,
    output reg [31:0] admitted_count,skipped_count,rejected_count,completed_count,
    output reg [31:0] overflow_count,shape_count,epoch_abort_count,
    output wire [31:0] ignored_verdicts,
    output reg [FIFO_BITS+1:0] high_water,
    output wire [2:0] preprocess_active_mask,
    output wire [1:0] advanced_active_mode,morphology_active_mode,
    output wire [7:0] advanced_active_threshold
);
    localparam SETTLE=0,FREE=1,ACTIVE=2,DEPTH=1<<FIFO_BITS;
    reg [1:0] state;reg recovering;reg [5:0] settle_cycles;
    reg [31:0] owner_id,wire_id,groups;reg [15:0] column;
    reg local_bad;reg [31:0] local_reason;
    reg [12:0] width,height;
    reg [14:0] crop_start,crop_end,crop_horizontal;
    reg [2:0] mask;reg [1:0] advanced,morphology;reg [7:0] threshold;
    wire owned=state==ACTIVE;
    wire core_start_ready,core_active,core_done,core_committed,core_aborted,core_ready;
    wire admit=state==FREE && source_reset_n && enable && frame_begin &&
        cfg_img_width==WIDTH && cfg_img_height==HEIGHT && core_start_ready;
    wire matching_verdict=owned && decision_valid && decision_frame_id==owner_id;
    wire source_bad=matching_verdict && !decision_good;
    wire epoch_bad=owned && (!source_reset_n || !enable);
    wire [95:0] isp_data;wire isp_valid,isp_last,isp_user,isp_ready;
    reg [97:0] memory[0:DEPTH-1];
    reg [FIFO_BITS-1:0] write_address,read_address;
    reg [FIFO_BITS:0] count;reg [97:0] output_word;reg output_valid;
    wire fifo_full=count==DEPTH;
    wire fifo_overflow=owned && !local_bad && isp_valid && fifo_full;
    wire shape_bad=owned && !local_bad && isp_valid &&
        (groups>=WIDTH*HEIGHT/4 || isp_user!=(groups==0) || isp_last!=(column==WIDTH/4-1));
    wire abort_now=epoch_bad || fifo_overflow || shape_bad;
    wire known_bad=local_bad || source_bad || abort_now;
    wire feed_raw=owned && source_reset_n && raw_frame_id==owner_id && !known_bad;
    // FIFO/shape events must latch before resetting the ISP that produced them.
    wire isp_reset_n=reset_n && source_reset_n && !(state==SETTLE && recovering) &&
        !(owned && (local_bad || source_bad || epoch_bad));
    assign raw_ready=feed_raw ? isp_ready : 1'b1;
    assign packet_frame_id=wire_id;
    assign source_owner_id=owner_id;
    // SETTLE with the source held in reset owns no frame or wire packet.
    // Report only an admitted transaction, including its stalled terminal.
    // Admission still requires FREE and a live source after 64 settle clocks.
    assign busy=owned || core_active;
    assign external_reset_n=isp_reset_n;
    assign external_raw_data=raw_data;
    assign external_raw_valid=raw_valid && feed_raw;
    assign external_raw_sof=raw_sof && raw_valid && feed_raw;
    assign external_raw_eol=raw_eol && raw_valid && feed_raw;
    assign external_width=width;assign external_height=height;
    assign external_crop_start=crop_start;assign external_crop_end=crop_end;
    assign external_crop_horizontal=crop_horizontal;assign external_mask=mask;
    assign external_advanced=advanced;assign external_morphology=morphology;
    assign external_threshold=threshold;
    generate if(EXTERNAL_ISP)begin:external_isp
        assign isp_data=ext_isp_data;assign isp_valid=ext_isp_valid;
        assign isp_last=ext_isp_last;assign isp_user=ext_isp_user;assign isp_ready=ext_isp_ready;
        assign preprocess_active_mask=ext_active_mask;assign advanced_active_mode=ext_active_advanced;
        assign morphology_active_mode=ext_active_morphology;assign advanced_active_threshold=ext_active_threshold;
    end else begin:internal_isp
    camera_isp724 isp(
        .user_clk(clk),.user_rst_n(isp_reset_n),.mipi_tdata(raw_data),
        .mipi_tvalid(raw_valid && feed_raw),.mipi_tlast(raw_eol && raw_valid && feed_raw),
        .mipi_tuser(raw_sof && raw_valid && feed_raw),.mipi_tready(isp_ready),
        .cfg_img_width(width),.cfg_img_height(height),.cfg_crop_v_start(crop_start),
        .cfg_crop_v_end(crop_end),.cfg_crop_h_end(crop_horizontal),.cfg_preprocess_mask(mask),
        .cfg_advanced_mode(advanced),.cfg_morphology_mode(morphology),.cfg_advanced_threshold(threshold),
        .preprocess_active_mask(preprocess_active_mask),.advanced_active_mode(advanced_active_mode),
        .morphology_active_mode(morphology_active_mode),.advanced_active_threshold(advanced_active_threshold),
        .output_data(isp_data),.output_valid(isp_valid),.output_last(isp_last),.output_user(isp_user));
    end endgenerate
    wire fifo_clear=!owned || known_bad || !core_active;
    wire advance_output=!output_valid || core_ready;
    wire read_word=!fifo_clear && advance_output && count!=0;
    wire write_word=!fifo_clear && isp_valid && !fifo_full;
    wire [FIFO_BITS-1:0] ram_read_address=read_word ? read_address : ~write_address;
    always @(posedge clk)begin
        if(write_word)memory[write_address]<={groups==WIDTH*HEIGHT/4-1,isp_user,isp_data};
        if(read_word)output_word<=memory[ram_read_address];
    end
    always @(posedge clk)begin
        if(!reset_n || fifo_clear)begin write_address<=0;read_address<=0;count<=0;output_valid<=0;end
        else begin
            if(write_word)write_address<=write_address+1'b1;
            if(read_word)read_address<=read_address+1'b1;
            case({write_word,read_word})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
            if(advance_output)output_valid<=read_word;
        end
    end
    lossless_transaction725 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.TIMEOUT_CYCLES(WAIT_CYCLES)) codec(
        .clk(clk),.reset(!reset_n),.start_valid(admit),.start_id(admitted_count),.start_ready(core_start_ready),
        .verdict_valid(matching_verdict),.verdict_id(wire_id),.verdict_good(decision_good),
        .verdict_reason({28'd0,decision_reason}),.abort_valid(owned && (local_bad || abort_now)),
        .abort_reason(local_bad ? local_reason : epoch_bad ? 32'd8 : fifo_overflow ? 32'd3 : 32'd2),
        .s_data(output_word[95:0]),.s_valid(output_valid && !fifo_clear),.s_sof(output_word[96]),
        .s_last(output_word[97]),.s_ready(core_ready),.m_data(packet_data),.m_keep(packet_keep),
        .m_valid(packet_valid),.m_ready(packet_ready),.m_last(packet_last),.active(core_active),
        .transaction_done(core_done),.committed(core_committed),.aborted(core_aborted),.ignored_verdicts(ignored_verdicts));
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=SETTLE;recovering<=1;settle_cycles<=0;owner_id<=0;wire_id<=0;local_bad<=0;local_reason<=0;
            groups<=0;column<=0;width<=WIDTH;height<=HEIGHT;crop_start<=0;crop_end<=0;crop_horizontal<=0;
            mask<=0;advanced<=0;morphology<=0;threshold<=0;
            admitted_count<=0;skipped_count<=0;rejected_count<=0;completed_count<=0;
            overflow_count<=0;shape_count<=0;epoch_abort_count<=0;high_water<=0;
        end else begin
            if(state==SETTLE)begin
                settle_cycles<=settle_cycles+1'b1;
                if(settle_cycles==63 && source_reset_n)begin state<=FREE;recovering<=0;end
            end
            if(frame_begin)begin
                if(admit)begin
                    state<=ACTIVE;owner_id<=begin_frame_id;wire_id<=admitted_count;local_bad<=0;local_reason<=0;groups<=0;column<=0;
                    admitted_count<=admitted_count+1'b1;
                    width<=cfg_img_width;height<=cfg_img_height;crop_start<=cfg_crop_v_start;
                    crop_end<=cfg_crop_v_end;crop_horizontal<=cfg_crop_h_end;
                    mask<=cfg_preprocess_mask;advanced<=cfg_advanced_mode;morphology<=cfg_morphology_mode;threshold<=cfg_advanced_threshold;
                end else skipped_count<=skipped_count+1'b1;
            end
            if(owned)begin
                if({1'b0,count}+output_valid>high_water)high_water<={1'b0,count}+output_valid;
                if(isp_valid && !known_bad)begin
                    groups<=groups+1'b1;column<=isp_last ? 0 : column+1'b1;
                end
                if((abort_now || source_bad) && !local_bad)begin
                    local_bad<=1;
                    local_reason<=source_bad ? (decision_reason==0 ? 32'd1 : {28'd0,decision_reason}) : epoch_bad ? 32'd8 : fifo_overflow ? 32'd3 : 32'd2;
                    if(epoch_bad)epoch_abort_count<=epoch_abort_count+1'b1;
                    else if(fifo_overflow)overflow_count<=overflow_count+1'b1;
                    else if(shape_bad)shape_count<=shape_count+1'b1;
                end
                if(core_done)begin
                    state<=SETTLE;settle_cycles<=0;recovering<=core_aborted;
                    if(core_committed)completed_count<=completed_count+1'b1;
                    else rejected_count<=rejected_count+1'b1;
                end
            end
        end
    end
endmodule
