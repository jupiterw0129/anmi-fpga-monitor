// ============================================================================
// vid_drop_detect.v ¡ª Frame drop detector with debounced tlast injection
//
// Detects when vid_tvalid goes low mid-frame for longer than DROP_IDLE_THRESH
// consecutive cycles (distinguishing normal H-blank gaps from actual drops).
// On detection, injects a single zero+tlast beat to cleanly terminate the
// partial packet in the downstream FIFO.
//
// Key design points:
//   - Uses persistent `drop_pending` flag, not a 1-cycle pulse, so the
//     injection correctly waits for downstream_ready before completing
//   - Counter only increments while in-frame AND tvalid is low
//   - Counter resets on any accepted data beat or after injection completes
//   - H-blank gaps (typically 7k-15k cycles) pass through harmlessly when
//     threshold is set high enough (e.g., 50,000 = 200?s @ 250MHz)
//
// Ports:
//   Input:  vid_tdata, vid_tvalid, vid_frame_last, downstream_ready
//   Output: out_tdata, out_tvalid, out_tlast, drop_pulse
// ============================================================================
`timescale 1ns / 1ps

module vid_drop_detect #(
    parameter DATA_WIDTH       = 512,
    parameter DROP_IDLE_THRESH = 50000  // cycles (~200us@250MHz) before declaring drop
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Video packer output (upstream)
    input  wire [DATA_WIDTH-1:0]    vid_tdata,
    input  wire                     vid_tvalid,
    input  wire                     vid_frame_last,

    // Downstream ready (from FIFO)
    input  wire                     downstream_ready,

    // Muxed output (to FIFO)
    output wire [DATA_WIDTH-1:0]    out_tdata,
    output wire                     out_tvalid,
    output wire                     out_tlast,

    // Status
    output reg                      drop_pulse       // high for 1 cycle after injection accepted
);

    // ©¤©¤ Counter width ©¤©¤
    localparam CNT_WIDTH = $clog2(DROP_IDLE_THRESH + 1);

    reg                    vid_in_frame;
    reg  [CNT_WIDTH-1:0]   idle_cnt;
    reg                    drop_pending;    // persistent until injection accepted

    // ©¤©¤ State machine ©¤©¤
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vid_in_frame <= 1'b0;
            idle_cnt     <= {CNT_WIDTH{1'b0}};
            drop_pending <= 1'b0;
            drop_pulse   <= 1'b0;
        end else begin
            drop_pulse <= 1'b0;             // default: no pulse
            if (drop_pending) begin
                // Waiting for downstream to accept the injection beat
                if (downstream_ready) begin
                    drop_pulse   <= 1'b1;   // pulse on acceptance
                    drop_pending <= 1'b0;
                    vid_in_frame <= 1'b0;
                    idle_cnt     <= {CNT_WIDTH{1'b0}};
                end
                // else: hold pending, ignore incoming vid data
            end else if (vid_frame_last && vid_tvalid && downstream_ready) begin
                // Normal frame end
                vid_in_frame <= 1'b0;
                idle_cnt     <= {CNT_WIDTH{1'b0}};
            end else if (vid_tvalid && downstream_ready) begin
                // Data beat accepted
                vid_in_frame <= 1'b1;
                idle_cnt     <= {CNT_WIDTH{1'b0}};
            end else if (vid_in_frame && !vid_tvalid) begin
                // In frame, tvalid low ¡ª count idle cycles
                if (idle_cnt >= DROP_IDLE_THRESH[CNT_WIDTH-1:0])
                    drop_pending <= 1'b1;       // threshold reached ¡ú inject
                else
                    idle_cnt <= idle_cnt + {{(CNT_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end

    // ©¤©¤ Output mux ©¤©¤
    assign out_tdata  = drop_pending ? {DATA_WIDTH{1'b0}} : vid_tdata;
    assign out_tvalid = drop_pending ? 1'b1               : vid_tvalid;
    assign out_tlast  = drop_pending ? 1'b1               : vid_frame_last;

endmodule
