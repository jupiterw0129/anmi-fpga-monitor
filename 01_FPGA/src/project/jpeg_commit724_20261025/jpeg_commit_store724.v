// One in-flight encoded frame. An immutable final verdict is accepted once,
// only for its matching frame ID; successful codec completion alone cannot
// make data visible. A bad verdict discards the store before any publication.
module jpeg_commit_store724 #(
    parameter ADDR_WIDTH=12
)(
    input wire clk, rst_n,
    input wire frame_begin,
    input wire [31:0] frame_id,
    input wire decision_valid,
    input wire [31:0] decision_frame_id,
    input wire decision_good,
    output wire rejected_frame,
    output wire frame_approved,
    output reg [31:0] decision_mismatch_count,
    output reg [31:0] decision_duplicate_count,
    input wire [7:0] s_data,
    input wire s_valid, s_last,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_valid,
    input wire m_ready,
    output wire m_last,
    output wire [31:0] oversize_count, busy_drop_count
);
    reg active, decided, approved, aborted;
    reg [31:0] active_id;
    wire matching=active && !decided && decision_frame_id==active_id;
    // A begin and verdict cannot refer to two frames in a single cycle.
    // Verdict for the new frame is accepted from the following cycle onward.
    wire accept_decision=decision_valid && matching && !frame_begin;
    assign rejected_frame=accept_decision && !decision_good;
    assign frame_approved=active && decided && approved && !aborted;
    wire store_reset_n=rst_n && !aborted && !rejected_frame;
    wire stored_valid, stored_last;
    assign m_valid=stored_valid && frame_approved;
    assign m_last=stored_last;
    jpeg_frame_to_axis128 #(.ADDR_WIDTH(ADDR_WIDTH)) store (
        .clk(clk),.rst_n(store_reset_n),
        .s_data(s_data),.s_valid(s_valid && active),.s_last(s_last),
        .m_data(m_data),.m_keep(m_keep),.m_valid(stored_valid),
        .m_ready(m_ready && frame_approved),.m_last(stored_last),
        .oversize_count(oversize_count),.busy_drop_count(busy_drop_count)
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active<=0; decided<=0; approved<=0; aborted<=0; active_id<=0;
            decision_mismatch_count<=0; decision_duplicate_count<=0;
        end else begin
            if (frame_begin) begin
                active<=1; decided<=0; approved<=0; aborted<=0; active_id<=frame_id;
            end else begin
                if (accept_decision) begin
                    decided<=1; approved<=decision_good;
                    if (!decision_good) aborted<=1;
                end
                if (m_valid && m_ready && m_last) active<=0;
            end
            if (decision_valid) begin
                if (frame_begin || !active || decision_frame_id!=active_id)
                    decision_mismatch_count<=decision_mismatch_count+1'b1;
                else if (decided)
                    decision_duplicate_count<=decision_duplicate_count+1'b1;
            end
        end
    end
endmodule
