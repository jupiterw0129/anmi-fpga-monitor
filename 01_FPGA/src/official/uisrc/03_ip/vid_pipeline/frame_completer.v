`timescale 1ns / 1ps
// ============================================================================
// frame_completer.v  ¡ª "Frame Guardian" (UVC-inspired flush mode)
//
// When upstream packer drops a frame mid-stream, this module sends a single
// zero beat with tlast=1 to terminate the SGDMA packet cleanly, then returns
// to transparent pass-through.
//
// Why 1-beat flush instead of full-frame padding:
//   PAD mode (old): sends ~97200 zero beats ¡ú 33ms ¡ú blocks next frame ¡ú
//                   cascading drop ¡ú black screen
//   FLUSH mode:     sends 1 zero beat       ¡ú 4ns  ¡ú next frame intact ¡ú
//                   no cascade, driver detects short packet ¡ú hold prev frame
//
// Detection: in_frame=1 and s_tvalid stays low for TIMEOUT_CYCLES clocks.
//   TIMEOUT_CYCLES must exceed max MIPI h-blank gap (~24?s for IMX415 1080p30)
//   but be much shorter than frame period (~33ms@30fps).
//
// Resource: ~30 LUTs, 0 BRAM
// ============================================================================

module frame_completer #(
    parameter DATA_WIDTH     = 512,
    parameter TIMEOUT_CYCLES = 16384   // ~65?s at 250MHz (> h-blank ~24?s)
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI-Stream slave (from upstream packer/FIFO)
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    output wire                    s_tready,
    input  wire                    s_tlast,     // frame-last from packer

    // AXI-Stream master (to SGDMA C2H)
    output wire [DATA_WIDTH-1:0]   m_tdata,
    output wire                    m_tvalid,
    input  wire                    m_tready,
    output wire                    m_tlast,     // frame-last / flush-last to SGDMA

    // Debug
    output reg  [31:0]             drop_count   // frames terminated by flush
);

    // ©¤©¤ States ©¤©¤
    localparam ST_PASS  = 1'b0;
    localparam ST_FLUSH = 1'b1;

    reg  state;
    reg  in_frame;   // 1 = received ¡Ý1 beat without s_tlast (mid-frame)

    localparam TIMEOUT_W = $clog2(TIMEOUT_CYCLES + 1);
    reg [TIMEOUT_W-1:0] idle_cnt;

    // ©¤©¤ Output MUX ©¤©¤
    //   PASS:  transparent
    //   FLUSH: 1 zero beat, tvalid=1, tlast=1
    assign m_tdata  = (state == ST_FLUSH) ? {DATA_WIDTH{1'b0}} : s_tdata;
    assign m_tvalid = (state == ST_FLUSH) ? 1'b1               : s_tvalid;
    assign m_tlast  = (state == ST_FLUSH) ? 1'b1               : s_tlast;
    assign s_tready = (state == ST_FLUSH) ? 1'b0               : m_tready;

    // ©¤©¤ Handshake in PASS mode ©¤©¤
    wire pass_fire = s_tvalid & m_tready;  // s_tready == m_tready in PASS

    // ©¤©¤ State Machine ©¤©¤
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_PASS;
            in_frame   <= 1'b0;
            idle_cnt   <= {TIMEOUT_W{1'b0}};
            drop_count <= 32'd0;
        end else begin
            case (state)
                // ©¤©¤ Transparent pass-through ©¤©¤
                ST_PASS: begin
                    if (pass_fire) begin
                        idle_cnt <= {TIMEOUT_W{1'b0}};
                        if (s_tlast)
                            in_frame <= 1'b0;   // frame complete
                        else
                            in_frame <= 1'b1;   // mid-frame
                    end else if (in_frame && !s_tvalid) begin
                        // Mid-frame + source idle ¡ú count toward timeout
                        if (idle_cnt >= TIMEOUT_CYCLES - 1) begin
                            // Timeout ¡ú frame was dropped ¡ú flush
                            state      <= ST_FLUSH;
                            drop_count <= drop_count + 32'd1;
                            idle_cnt   <= {TIMEOUT_W{1'b0}};
                        end else begin
                            idle_cnt <= idle_cnt + 1'b1;
                        end
                    end else begin
                        idle_cnt <= {TIMEOUT_W{1'b0}};
                    end
                end

                // ©¤©¤ Flush: send 1 zero beat with tlast, then back to PASS ©¤©¤
                ST_FLUSH: begin
                    if (m_tready) begin
                        state    <= ST_PASS;
                        in_frame <= 1'b0;
                    end
                    // m_tvalid=1, m_tdata=0, m_tlast=1 (combinational)
                    // s_tready=0 (block upstream for exactly 1 clock)
                end
            endcase
        end
    end

endmodule
