// ============================================================================
// vid_frame_gate.v ¡ª Frame-level gating for DMA-safe video streaming
//
// Problem solved:
//   Without DDR frame buffer, when DMA can't keep up (e.g. 1080p@60fps),
//   partial frames enter the FIFO and produce "mixed frames" (data from
//   two sensor frames merged into one DMA transfer).  The driver can't
//   distinguish these from good frames, causing visible flicker.
//
// Solution:
//   At each frame's SOF, check downstream FIFO fill level.
//   - If FIFO has enough room for a full frame ¡ú pass entire frame through
//   - If FIFO is too full ¡ú drop entire frame silently (consume & discard)
//
//   This guarantees every frame entering the DMA path is complete and
//   single-source.  Dropped frames are invisible (display holds previous
//   frame).  Effective frame rate auto-adapts to DMA throughput.
//
// Integration point:
//   cam_video_source ¡ú [vid_frame_gate] ¡ú vid_drop_detect ¡ú FIFO ¡ú SGDMA
//
// Resource: ~40 LUTs, 0 BRAM
// ============================================================================
`timescale 1ns / 1ps

module vid_frame_gate #(
    parameter DATA_WIDTH     = 512,
    parameter FILL_BITS      = 12,      // width of fifo_fill_level
    parameter GATE_THRESHOLD = 1024     // drop frame if FIFO fill >= this
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Upstream: from cam_video_source pack4 output
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    output wire                    s_tready,
    input  wire                    s_tlast,       // line-last from pack4
    input  wire                    s_frame_last,  // frame-last from pack4
    input  wire                    s_sof,         // start-of-frame pulse

    // Downstream: to vid_drop_detect / FIFO
    output wire [DATA_WIDTH-1:0]   m_tdata,
    output wire                    m_tvalid,
    output wire                    m_frame_last,

    // FIFO fill level (from axis_stream_fifo)
    input  wire [FILL_BITS-1:0]    fifo_fill_level,

    // Debug / status
    output reg  [31:0]             gate_drop_count,  // frames gated (dropped)
    output reg  [31:0]             gate_pass_count    // frames passed through
);

    // ©¤©¤ Gate state ©¤©¤
    // Decided once per frame at SOF, held until frame_last
    localparam ST_IDLE     = 2'd0;   // waiting for SOF
    localparam ST_PASS     = 2'd1;   // passing current frame
    localparam ST_DROP     = 2'd2;   // dropping current frame
    localparam ST_WAIT_SOF = 2'd3;   // post-drop: wait for next SOF to gate

    reg [1:0] state;

    // ©¤©¤ Combinational gate decision on SOF cycle ©¤©¤
    // Suppress the very first beat when gate will drop (state hasn't latched yet)
    wire sof_will_drop = (state == ST_IDLE) && s_sof && s_tvalid &&
                         (fifo_fill_level >= GATE_THRESHOLD[FILL_BITS-1:0]);

    // ST_WAIT_SOF: pass the SOF beat through if fill is low (combinational path)
    wire sof_will_pass_from_wait = (state == ST_WAIT_SOF) && s_sof && s_tvalid &&
                                   (fifo_fill_level < GATE_THRESHOLD[FILL_BITS-1:0]);

    wire dropping = (state == ST_DROP) ||
                    ((state == ST_WAIT_SOF) && !sof_will_pass_from_wait) ||
                    sof_will_drop;

    // ©¤©¤ Output mux ©¤©¤
    // PASS: transparent forward
    // DROP: consume upstream (s_tready=1) but suppress downstream (m_tvalid=0)
    assign m_tdata      = s_tdata;
    assign m_tvalid     = dropping ? 1'b0 : s_tvalid;
    assign m_frame_last = dropping ? 1'b0 : s_frame_last;

    // Upstream always accepted: in PASS mode downstream controls,
    // in DROP mode we sink data immediately
    // In PASS/IDLE mode, s_tready follows downstream implicit ready
    // (vid_drop_detect has no tready input; it uses downstream_ready
    //  from FIFO.  So we always accept from pack4 ¡ª same as current design.)
    assign s_tready = 1'b1;

    // ©¤©¤ State machine ©¤©¤
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            gate_drop_count <= 32'd0;
            gate_pass_count <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Wait for SOF to make gate decision
                    if (s_sof && s_tvalid) begin
                        if (fifo_fill_level >= GATE_THRESHOLD[FILL_BITS-1:0]) begin
                            state           <= ST_DROP;
                            gate_drop_count <= gate_drop_count + 1'b1;
                        end else begin
                            state           <= ST_PASS;
                            gate_pass_count <= gate_pass_count + 1'b1;
                        end
                    end
                end

                ST_PASS: begin
                    // Pass entire frame; return to IDLE on frame_last
                    if (s_tvalid && s_frame_last)
                        state <= ST_IDLE;
                end

                ST_DROP: begin
                    // Drop entire frame; on frame_last, enter ST_WAIT_SOF
                    // to prevent data leak from next frame (whose SOF may
                    // have been consumed during ST_DROP).
                    if (s_tvalid && s_frame_last)
                        state <= ST_WAIT_SOF;
                end

                ST_WAIT_SOF: begin
                    // Post-drop: wait for next SOF to make fresh gate decision.
                    // Drops all data until SOF arrives (prevents partial frames).
                    // Combinational path (sof_will_pass_from_wait) ensures the
                    // SOF beat itself passes when fill is low.
                    if (s_tvalid && s_sof) begin
                        if (fifo_fill_level >= GATE_THRESHOLD[FILL_BITS-1:0]) begin
                            state           <= ST_DROP;
                            gate_drop_count <= gate_drop_count + 1'b1;
                        end else begin
                            state           <= ST_PASS;
                            gate_pass_count <= gate_pass_count + 1'b1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
