// ============================================================================
// pack4_rgb24_to_128.v — 4-pixel parallel RGB24 packer (128b→128b tight-pack)
//
// Purpose:
//   Converts 128-bit demosaic output (4 × {8'h00, R, G, B} = 4 × 32b)
//   into tightly-packed 128-bit RGB24 stream (no per-pixel padding).
//   Designed for x1 Gen2 PCIe with DATA_WIDTH=128.
//
// Input:  128-bit AXI-Stream from ISP (4 pixels × 32b with 8b padding each)
// Output: 128-bit AXI-Stream packed RGB24 (16 bytes per beat)
//
// Packing scheme:
//   Each input beat provides 12 bytes (4 pixels × 3 RGB bytes, padding stripped).
//   Output beat = 16 bytes.
//   LCM(12, 16) = 48 bytes → 4 inputs produce 3 outputs.
//
//   State cycle (byte_offset):
//     offset  0: accept 12B → fill bytes  0-11, no output     → offset 12
//     offset 12: accept 12B → fill bytes 12-15 + 8B carry, EMIT → offset  8
//     offset  8: accept 12B → fill bytes  8-15 + 4B carry, EMIT → offset  4
//     offset  4: accept 12B → fill bytes  4-15, exact fit, EMIT → offset  0
//
// Supports full backpressure (m_tready → s_tready).
// On line end (s_tlast), flushes partial output beat with zero-padding.
// ============================================================================
`timescale 1ns / 1ps

module pack4_rgb24_to_128 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,
    input  wire [12:0]  frame_height,

    // Input: 128-bit from ISP FIFO
    //   [31:0]   = pixel 0: {8'h00, R[7:0], G[7:0], B[7:0]}
    //   [63:32]  = pixel 1
    //   [95:64]  = pixel 2
    //   [127:96] = pixel 3
    input  wire [127:0] s_tdata,
    input  wire         s_tvalid,
    output wire         s_tready,
    input  wire         s_tlast,    // line end from ISP
    input  wire         s_tuser,    // frame start (SOF)

    // Output: 128-bit packed RGB24
    output reg  [127:0] m_tdata,
    output reg          m_tvalid,
    input  wire         m_tready,
    output reg          m_tlast,        // line end marker
    output reg          m_frame_last,   // frame end marker
    output reg          sof,
    output reg          eof,
    output wire [31:0]  frame_count_out
);

    // ── Pixel extraction (strip 8-bit padding, reorder to BGR for little-endian) ──
    // Demosaic output: {8'h00, R[23:16], G[15:8], B[7:0]}
    // Reorder to {B, G, R} → memory order: byte0=R, byte1=G, byte2=B (V4L2_PIX_FMT_RGB24)
    wire [23:0] pix0 = {s_tdata[7:0],   s_tdata[15:8],  s_tdata[23:16]};
    wire [23:0] pix1 = {s_tdata[39:32], s_tdata[47:40], s_tdata[55:48]};
    wire [23:0] pix2 = {s_tdata[71:64], s_tdata[79:72], s_tdata[87:80]};
    wire [23:0] pix3 = {s_tdata[103:96],s_tdata[111:104],s_tdata[119:112]};

    // 12 bytes of pixel data per input beat (LSB-first in memory)
    wire [95:0] new_bytes = {pix3, pix2, pix1, pix0};

    // ── State ──
    reg [31:0]  frame_count;
    reg [4:0]   byte_offset;    // current write position: 0, 4, 8, 12
    reg [127:0] accum;          // byte accumulator for next output word
    reg [12:0]  line_count;
    reg         sof_pending;
    reg         flush_pending;
    reg         flush_is_frame_last;

    assign frame_count_out = frame_count;

    // ── Flow control ──
    wire output_free   = !m_tvalid || m_tready;
    wire will_emit     = (byte_offset != 5'd0);  // offsets 4, 8, 12 all emit
    wire accept_input  = s_tvalid && s_tready;
    wire final_line = frame_height != 13'd0 &&
                      (s_tuser ? 13'd0 : line_count) == frame_height - 1'b1;
    // Backpressure: stall input when output can't be emitted or flush pending
    assign s_tready = enable && !flush_pending &&
                      (will_emit ? output_free : 1'b1);

    // ── Main sequential logic ──
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count         <= 32'd0;
            byte_offset         <= 5'd0;
            accum               <= 128'd0;
            line_count          <= 13'd0;
            sof_pending         <= 1'b0;
            flush_pending       <= 1'b0;
            flush_is_frame_last <= 1'b0;
            m_tdata             <= 128'd0;
            m_tvalid            <= 1'b0;
            m_tlast             <= 1'b0;
            m_frame_last        <= 1'b0;
            sof                 <= 1'b0;
            eof                 <= 1'b0;
        end else begin
            // ── Clear output when accepted ──
            if (m_tvalid && m_tready) begin
                if (m_frame_last)
                    frame_count <= frame_count + 1'b1;
                m_tvalid     <= 1'b0;
                m_tlast      <= 1'b0;
                m_frame_last <= 1'b0;
                sof          <= 1'b0;
                eof          <= 1'b0;
            end

            if (!enable) begin
                byte_offset         <= 5'd0;
                accum               <= 128'd0;
                line_count          <= 13'd0;
                sof_pending         <= 1'b0;
                flush_pending       <= 1'b0;
                flush_is_frame_last <= 1'b0;
                m_tvalid            <= 1'b0;
                m_tlast             <= 1'b0;
                m_frame_last        <= 1'b0;
                sof                 <= 1'b0;
                eof                 <= 1'b0;
            end else if (flush_pending && output_free) begin
                // ── Flush partial beat at line end ──
                if (byte_offset != 5'd0) begin
                    m_tdata      <= accum;
                    m_tvalid     <= 1'b1;
                    m_tlast      <= 1'b1;
                    m_frame_last <= flush_is_frame_last;
                    sof          <= sof_pending;
                    eof          <= flush_is_frame_last;
                    sof_pending  <= 1'b0;
                    accum        <= 128'd0;
                    byte_offset  <= 5'd0;
                end
                flush_pending       <= 1'b0;
                flush_is_frame_last <= 1'b0;
            end else if (accept_input) begin
                // ── Frame boundary ──
                if (s_tuser) begin
                    line_count  <= 13'd0;
                    sof_pending <= 1'b1;
                end
                if (s_tlast)
                    line_count <= final_line ? 13'd0 :
                                  (s_tuser ? 13'd1 : line_count + 1'b1);

                // ── Insert 12 bytes at byte_offset, emit when full ──
                case (byte_offset)
                    5'd0: begin
                        // 12 bytes at positions 0-11, no output
                        accum[95:0]  <= new_bytes;
                        byte_offset  <= 5'd12;
                    end
                    5'd12: begin
                        // 12 bytes at positions 12-23:
                        //   4 bytes fill accum[127:96], 8 bytes carry
                        m_tdata      <= {new_bytes[31:0], accum[95:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= 1'b0;
                        m_frame_last <= 1'b0;
                        sof          <= sof_pending;
                        eof          <= 1'b0;
                        sof_pending  <= 1'b0;
                        accum        <= {64'd0, new_bytes[95:32]};
                        byte_offset  <= 5'd8;
                    end
                    5'd8: begin
                        // 12 bytes at positions 8-19:
                        //   8 bytes fill accum[127:64], 4 bytes carry
                        m_tdata      <= {new_bytes[63:0], accum[63:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= 1'b0;
                        m_frame_last <= 1'b0;
                        sof          <= sof_pending;
                        eof          <= 1'b0;
                        sof_pending  <= 1'b0;
                        accum        <= {96'd0, new_bytes[95:64]};
                        byte_offset  <= 5'd4;
                    end
                    5'd4: begin
                        // 12 bytes at positions 4-15: exact fit, all 16 bytes filled
                        m_tdata      <= {new_bytes[95:0], accum[31:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= s_tlast;  // piggyback line-end on exact-fit emit
                        m_frame_last <= s_tlast && final_line;
                        sof          <= sof_pending;
                        eof          <= s_tlast && final_line;
                        sof_pending  <= 1'b0;
                        accum        <= 128'd0;
                        byte_offset  <= 5'd0;
                    end
                    default: begin
                        byte_offset <= 5'd0;
                        accum       <= 128'd0;
                    end
                endcase

                // ── Line end → trigger flush ──
                if (s_tlast) begin
                    flush_pending <= 1'b1;
                    flush_is_frame_last <= final_line;
                end
            end
        end
    end

endmodule
