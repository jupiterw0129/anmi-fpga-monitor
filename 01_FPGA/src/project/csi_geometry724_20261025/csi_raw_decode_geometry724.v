// Elastic RAW10/RAW12 unpacker. Pixel, frame-end and frame-abort transfers
// share valid/ready; consumers must handle both control flags, never ignore them.
module csi_raw_decode_geometry724 (
    input wire clock, reset_n,
    input wire [63:0] token_data,
    input wire token_valid,
    output wire token_ready,
    output reg [39:0] output_data,
    output reg output_valid,
    input wire output_ready,
    output reg output_sof, output_eol, output_abort, output_frame_end, output_frame_start
);
    localparam WAIT=0, LINE=1, ABORT=2;
    reg [1:0] state;
    reg frame_active, pending_sof, emitted_any;
    reg raw12;
    reg [15:0] line_bytes, received_bytes, emitted_bytes;
    reg input_finished;
    reg [71:0] pending, next_pending;
    reg [3:0] count, next_count;
    wire [23:0] header=token_data[63:40];
    wire [1:0] kind=token_data[39:38];
    wire first=token_data[37], last=token_data[36];
    wire [3:0] keep=token_data[35:32];
    wire [31:0] data=token_data[31:0];
    wire is_raw=header[5:0]==6'h2b || header[5:0]==6'h2c;
    wire fs=kind==1 && header[5:0]==0;
    wire fe=kind==1 && header[5:0]==1;
    wire slot=!output_valid || output_ready;
    wire start_line=state==WAIT && token_valid && kind==0 && first &&
        frame_active && is_raw;
    wire [3:0] group_bytes=raw12 ? 6 : 5;
    wire emit_group=state==LINE && count>=group_bytes && slot;
    wire accept=token_valid && token_ready;
    reg [2:0] valid_bytes;
    reg [31:0] masked_data;
    always @* begin
        valid_bytes=0; masked_data=0;
        case (keep)
            4'b0001: begin valid_bytes=1; masked_data={24'd0,data[7:0]}; end
            4'b0011: begin valid_bytes=2; masked_data={16'd0,data[15:0]}; end
            4'b0111: begin valid_bytes=3; masked_data={8'd0,data[23:0]}; end
            4'b1111: begin valid_bytes=4; masked_data=data; end
        endcase
        next_pending=pending;
        next_count=count;
        if (emit_group) begin
            next_pending=pending>>(group_bytes*8);
            next_count=count-group_bytes;
        end
        if (accept && state==LINE) begin
            next_pending=next_pending | ({40'd0,masked_data}<<(next_count*8));
            next_count=next_count+valid_bytes;
        end
    end
    assign token_ready=state==WAIT ?
        (!start_line && !(fs && frame_active) && ((!fs && !(fe && frame_active)) || slot)) :
        state==LINE ? (!input_finished && count<=5 && kind==0) : 1'b0;
    wire bad_line_header=header[23:8]==0 ||
        (header[5:0]==6'h2c ? header[23:8]%6!=0 : header[23:8]%5!=0);
    wire bad_beat=valid_bytes==0 || (first && received_bytes!=0) ||
        header[23:8]!=line_bytes || header[5:0]!=(raw12 ? 6'h2c : 6'h2b) ||
        ({1'b0,received_bytes}+valid_bytes>{1'b0,line_bytes}) ||
        (last!=({1'b0,received_bytes}+valid_bytes=={1'b0,line_bytes}));
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state<=WAIT; frame_active<=0; pending_sof<=0; emitted_any<=0;
            raw12<=0; line_bytes<=0; received_bytes<=0; emitted_bytes<=0;
            input_finished<=0; pending<=0; count<=0;
            output_data<=0; output_valid<=0; output_sof<=0; output_eol<=0;
            output_abort<=0; output_frame_end<=0; output_frame_start<=0;
        end else begin
            if (output_valid && output_ready) output_valid<=0;
            if (state==ABORT && slot) begin
                output_data<=0; output_valid<=1; output_sof<=0; output_eol<=0;
                output_abort<=1; output_frame_end<=0; output_frame_start<=0;
                frame_active<=0; pending_sof<=0; emitted_any<=0;
                state<=WAIT; pending<=0; count<=0;
            end else if (state==WAIT) begin
                if (token_valid && fs && frame_active) state<=ABORT;
                else if (start_line) begin
                    if (bad_line_header) state<=ABORT;
                    else begin
                        state<=LINE; raw12<=header[5:0]==6'h2c;
                        line_bytes<=header[23:8]; received_bytes<=0;
                        emitted_bytes<=0; input_finished<=0; pending<=0; count<=0;
                    end
                end else if (accept) begin
                    if (fs) begin
                        frame_active<=1; pending_sof<=1; emitted_any<=0;
                        output_data<=0; output_valid<=1; output_sof<=0; output_eol<=0;
                        output_abort<=0; output_frame_end<=0; output_frame_start<=1;
                    end
                    else if (kind==2 && frame_active) state<=ABORT;
                    else if (fe && frame_active) begin
                        if (!emitted_any) state<=ABORT;
                        else begin
                            output_data<=0; output_valid<=1; output_sof<=0; output_eol<=0;
                            output_abort<=0; output_frame_end<=1; output_frame_start<=0;
                            frame_active<=0; pending_sof<=0;
                        end
                    end
                end
            end else if (state==LINE) begin
                pending<=next_pending; count<=next_count;
                if (emit_group) begin
                    if (raw12) begin
                        output_data[9:0]<={pending[7:0],pending[19:18]};
                        output_data[19:10]<={pending[15:8],pending[23:22]};
                        output_data[29:20]<={pending[31:24],pending[43:42]};
                        output_data[39:30]<={pending[39:32],pending[47:46]};
                    end else begin
                        output_data[9:0]<={pending[7:0],pending[33:32]};
                        output_data[19:10]<={pending[15:8],pending[35:34]};
                        output_data[29:20]<={pending[23:16],pending[37:36]};
                        output_data[39:30]<={pending[31:24],pending[39:38]};
                    end
                    output_valid<=1; output_sof<=pending_sof;
                    output_eol<=emitted_bytes+group_bytes==line_bytes;
                    output_abort<=0; output_frame_end<=0; output_frame_start<=0;
                    pending_sof<=0; emitted_any<=1;
                    emitted_bytes<=emitted_bytes+group_bytes;
                end
                if (accept) begin
                    received_bytes<=received_bytes+valid_bytes;
                    if (last) input_finished<=1;
                    if (bad_beat) state<=ABORT;
                end
                if (!input_finished && token_valid && kind!=0) state<=ABORT;
                if (input_finished && count==0) state<=WAIT;
            end
        end
    end
endmodule
