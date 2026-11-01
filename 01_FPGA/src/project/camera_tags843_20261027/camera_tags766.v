// RAW admission precedes delayed ISP RGB SOF. Retain both read positions;
// a newer frame_begin must never relabel the current RAW or RGB frame.
module camera_tags766(
    input wire clk,reset_n,
    input wire frame_begin,input wire [31:0] begin_id,
    input wire raw_fire,raw_sof,input wire [31:0] raw_id,
    input wire rgb_valid,rgb_sof,
    output wire [31:0] rgb_id,
    output wire fault,
    output wire [3:0] pending_raw,pending_rgb
);
    // Independent shift queues expose both current identities directly.
    // Only admissions and SOFs move them; per-pixel fault timing is unchanged.
    reg [31:0] raw_tags[0:7],rgb_tags[0:7];
    reg [3:0] raw_count,rgb_count;
    (* dont_touch="true" *) reg raw_nonempty,rgb_nonempty;
    reg [31:0] raw_active_id,rgb_active_id;
    reg raw_active,rgb_active;
    assign pending_raw=raw_count;
    assign pending_rgb=rgb_count;
    wire push=frame_begin && rgb_count<8;
    wire raw_start=raw_fire && raw_sof;
    wire rgb_start=rgb_valid && rgb_sof;
    wire raw_has_tag=raw_nonempty || push;
    wire rgb_has_tag=rgb_nonempty || push;
    wire [31:0] next_raw_id=raw_nonempty ? raw_tags[0] : begin_id;
    wire [31:0] next_rgb_id=rgb_nonempty ? rgb_tags[0] : begin_id;
    // RGB SOF may coincide with its RAW SOF, but must never precede it.
    wire rgb_raw_started=rgb_count>raw_count || (raw_start && raw_has_tag && raw_id==next_rgb_id);
    assign rgb_id=rgb_sof ? next_rgb_id : rgb_active_id;
    assign fault=(frame_begin && !push) ||
        (raw_fire && (raw_sof ? !raw_has_tag || raw_id!=next_raw_id : !raw_active || raw_id!=raw_active_id)) ||
        (rgb_valid && (rgb_sof ? !rgb_has_tag || !rgb_raw_started : !rgb_active));
    integer k;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            raw_count<=0;rgb_count<=0;raw_nonempty<=0;rgb_nonempty<=0;
            raw_active<=0;rgb_active<=0;raw_active_id<=0;rgb_active_id<=0;
            for(k=0;k<8;k=k+1)begin raw_tags[k]<=0;rgb_tags[k]<=0;end
        end else if(!fault)begin
            case({push,raw_start})
                2'b10:raw_nonempty<=1;
                2'b01:raw_nonempty<=raw_count!=1;
            endcase
            case({push,rgb_start})
                2'b10:rgb_nonempty<=1;
                2'b01:rgb_nonempty<=rgb_count!=1;
            endcase
            for(k=0;k<8;k=k+1)begin
                if(raw_start && raw_nonempty)begin
                    if(k<7)raw_tags[k]<=raw_tags[k+1];
                    else raw_tags[k]<=0;
                end
                if(rgb_start && rgb_nonempty)begin
                    if(k<7)rgb_tags[k]<=rgb_tags[k+1];
                    else rgb_tags[k]<=0;
                end
                // A simultaneous push into an empty popped queue is consumed
                // by the existing begin_id bypass, so no entry is stored.
                if(push && !(raw_start && raw_count==0) &&
                   raw_count-(raw_start ? 1'b1 : 1'b0)==k)raw_tags[k]<=begin_id;
                if(push && !(rgb_start && rgb_count==0) &&
                   rgb_count-(rgb_start ? 1'b1 : 1'b0)==k)rgb_tags[k]<=begin_id;
            end
            if(raw_start)begin raw_active<=1;raw_active_id<=next_raw_id;end
            if(rgb_start)begin rgb_active<=1;rgb_active_id<=next_rgb_id;end
            case({push,raw_start})2'b10:raw_count<=raw_count+1'b1;2'b01:raw_count<=raw_count-1'b1;endcase
            case({push,rgb_start})2'b10:rgb_count<=rgb_count+1'b1;2'b01:rgb_count<=rgb_count-1'b1;endcase
        end
    end
endmodule
