// Validate the complete uncropped RAW raster, not the cropped ISP dimensions.
// FS, FE and abort are ordered control transfers from csi_geometry_rx724.
// All state changes require a transfer. Final verdict is elastic and immutable.
module csi_frame_geometry724 (
    input wire clk, reset_n,
    input wire [15:0] cfg_beats_per_line, cfg_lines_per_frame,
    input wire [39:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_sof, s_eol, s_abort, s_frame_end, s_frame_start,
    output wire [39:0] pixel_data,
    output wire pixel_valid,
    input wire pixel_ready,
    output wire pixel_sof, pixel_eol,
    output wire [31:0] pixel_frame_id,
    output reg frame_begin,
    output reg [31:0] begin_frame_id,
    output reg pipeline_abort,
    output reg decision_valid,
    input wire decision_ready,
    output reg [31:0] decision_frame_id,
    output reg decision_good,
    output reg [3:0] decision_reason,
    output reg [31:0] good_count, bad_count, orphan_count
);
    // Reasons: 0 good, 1 decoder abort, 2 missing FE, 3 invalid config,
    // 4 SOF mismatch, 5 line length mismatch, 6 too many lines, 7 short frame.
    reg active, seen_pixel;
    reg [31:0] next_id, active_id;
    reg [15:0] beats, lines, column, row;
    wire control=s_frame_start || s_frame_end || s_abort;
    wire room=(!decision_valid || decision_ready) && !pipeline_abort;
    wire [3:0] pixel_reason=(beats==0 || lines==0) ? 4'd3 :
        (s_sof != !seen_pixel) ? 4'd4 :
        (row>=lines) ? 4'd6 :
        (s_eol != (column==beats-1'b1)) ? 4'd5 : 4'd0;
    // An erroneous beat is consumed as a control event, never exposed to ISP.
    assign s_ready=room && (control || !active || pixel_reason!=0 || pixel_ready);
    assign pixel_valid=s_valid && room && active && !control && pixel_reason==0;
    assign pixel_data=s_data;
    assign pixel_sof=s_sof;
    assign pixel_eol=s_eol;
    assign pixel_frame_id=active_id;
    wire transfer=s_valid && s_ready;
    task reject_frame;
        input [3:0] reason;
        begin
            decision_valid<=1; decision_frame_id<=active_id;
            decision_good<=0; decision_reason<=reason;
            bad_count<=bad_count+1'b1; pipeline_abort<=1;
            active<=0;
        end
    endtask
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active<=0; seen_pixel<=0; next_id<=0; active_id<=0;
            beats<=0; lines<=0; column<=0; row<=0;
            frame_begin<=0; begin_frame_id<=0; pipeline_abort<=0;
            decision_valid<=0; decision_frame_id<=0; decision_good<=0; decision_reason<=0;
            good_count<=0; bad_count<=0; orphan_count<=0;
        end else begin
            frame_begin<=0; pipeline_abort<=0;
            if (decision_valid && decision_ready) decision_valid<=0;
            if (transfer) begin
                if (s_frame_start) begin
                    if (active) reject_frame(4'd2);
                    active_id<=next_id; next_id<=next_id+1'b1;
                    frame_begin<=1; begin_frame_id<=next_id;
                    active<=1; seen_pixel<=0; column<=0; row<=0;
                    beats<=cfg_beats_per_line; lines<=cfg_lines_per_frame;
                    // Invalid configuration still allocates an identity; its
                    // negative verdict is generated on its first pixel/end.
                end else if (active) begin
                    if (s_abort) reject_frame(4'd1);
                    else if (beats==0 || lines==0) reject_frame(4'd3);
                    else if (s_frame_end) begin
                        if (!seen_pixel || column!=0 || row!=lines) reject_frame(4'd7);
                        else begin
                            decision_valid<=1; decision_frame_id<=active_id;
                            decision_good<=1; decision_reason<=0;
                            good_count<=good_count+1'b1; active<=0;
                        end
                    end else if (pixel_reason!=0) reject_frame(pixel_reason);
                    else begin
                        seen_pixel<=1;
                        if (s_eol) begin column<=0; row<=row+1'b1; end
                        else column<=column+1'b1;
                    end
                end else if (!s_frame_end && !s_abort) orphan_count<=orphan_count+1'b1;
            end
        end
    end
endmodule
