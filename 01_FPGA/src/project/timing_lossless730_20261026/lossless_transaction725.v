// Backpressured RGB4 transaction core. Camera admission/CDC ownership is external.
module lossless_transaction725 #(
    parameter WIDTH=1280,HEIGHT=720,TIMEOUT_CYCLES=125000000
)(
    input wire clk,reset,start_valid,input wire [31:0] start_id,output wire start_ready,
    input wire verdict_valid,input wire [31:0] verdict_id,input wire verdict_good,
    input wire [31:0] verdict_reason,input wire abort_valid,input wire [31:0] abort_reason,
    input wire [95:0] s_data,input wire s_valid,s_sof,s_last,output wire s_ready,
    output wire [127:0] m_data,output wire [15:0] m_keep,output wire m_valid,
    input wire m_ready,output wire m_last,active,transaction_done,committed,aborted,
    output wire [31:0] ignored_verdicts
);
    wire flush,encoder_ready;wire pipeline_reset=reset || flush || !active;
    reg input_finished,shape_fault;reg [31:0] input_groups;
    wire input_bad=s_valid && s_ready &&
        (s_sof!=(input_groups==0) || s_last!=(input_groups==WIDTH*HEIGHT/4-1));
    always @(posedge clk)begin
        if(reset || !active)begin input_finished<=0;input_groups<=0;shape_fault<=0;end
        else if(s_valid && s_ready)begin
            input_groups<=input_groups+1'b1;if(s_last)input_finished<=1;
            if(input_bad)shape_fault<=1;
        end
    end
    wire [103:0] token_data;wire [3:0] token_bytes;
    wire token_valid,token_ready,token_sof,token_last;
    wire [127:0] packed_data;wire [15:0] packed_keep;
    wire packed_valid,packed_ready,packed_sof,packed_last;
    assign s_ready=active && !flush && !input_finished && encoder_ready;
    predictive_rgb4 encoder(.clk(clk),.reset(pipeline_reset),.s_data(s_data),
        .s_valid(s_valid && active && !flush && !input_finished && !input_bad),.s_ready(encoder_ready),.s_sof(s_sof),.s_last(s_last),
        .m_data(token_data),.m_bytes(token_bytes),.m_valid(token_valid),.m_ready(token_ready),.m_sof(token_sof),.m_last(token_last));
    token_axis128 packer(.clk(clk),.reset(pipeline_reset),.s_data(token_data),.s_bytes(token_bytes),
        .s_valid(token_valid),.s_ready(token_ready),.s_sof(token_sof),.s_last(token_last),
        .m_data(packed_data),.m_keep(packed_keep),.m_valid(packed_valid),.m_ready(packed_ready),.m_sof(packed_sof),.m_last(packed_last));
    // Break packer count/keep -> transport length/CRC control timing.
    // Clear provisional buffered data on abort; the transport retains wire state.
    // Two-entry elastic buffer: readiness depends only on registered occupancy.
    // Immediate transport cancellation still blocks consumption on bad_now.
    // This removes transport.s_ready -> packer reservoir combinational timing.
    // Keep the queue head in flops: no asynchronous indexed RAM read on output.
    reg [145:0] stage_head,stage_tail;
    reg [1:0] stage_count;
    wire [127:0] stage_data=stage_head[127:0];
    wire [15:0] stage_keep=stage_head[143:128];
    wire stage_sof=stage_head[144];
    wire stage_last=stage_head[145];
    wire stage_valid=stage_count!=0;
    wire stage_ready;
    assign packed_ready=stage_count!=2;
    wire stage_push=packed_valid && packed_ready;
    wire stage_pop=stage_valid && stage_ready;
    wire [145:0] stage_input={packed_last,packed_sof,packed_keep,packed_data};
    always @(posedge clk)begin
        if(pipeline_reset)stage_count<=0;
        else begin
            if(stage_push)begin
                if(stage_count==0 || stage_pop)stage_head<=stage_input;
                else stage_tail<=stage_input;
            end else if(stage_pop && stage_count==2)stage_head<=stage_tail;
            case({stage_push,stage_pop})
                2'b10:stage_count<=stage_count+1'b1;
                2'b01:stage_count<=stage_count-1'b1;
            endcase
        end
    end
    segment_transaction725 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) transport(
        .clk(clk),.reset(reset),.start_valid(start_valid),.start_id(start_id),.start_ready(start_ready),
        .verdict_valid(verdict_valid),.verdict_id(verdict_id),.verdict_good(verdict_good),.verdict_reason(verdict_reason),
        .abort_valid(abort_valid || shape_fault),.abort_reason(shape_fault ? 32'd2 : abort_reason),.s_data(stage_data),.s_keep(stage_keep),
        .s_valid(stage_valid),.s_sof(stage_sof),.s_last(stage_last),.s_ready(stage_ready),
        .m_data(m_data),.m_keep(m_keep),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),
        .active(active),.flush(flush),.transaction_done(transaction_done),.committed(committed),.aborted(aborted),.ignored_verdicts(ignored_verdicts));
endmodule
