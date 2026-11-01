// ============================================================================
// pack4_rgb24_to_512.v ¡ª 4-pixel parallel RGB24 packer (128b¡ú512b)
//
// Purpose:
//   Replaces serializer_128to24 + stdvid_nobp_packer for 4K throughput.
//   Processes 4 pixels/clock (12 bytes) vs. 1 pixel/clock (3 bytes),
//   giving 4¡Á throughput margin at 250 MHz user_clk.
//
// Input:  128-bit AXI-Stream from demosaic (4 pixels ¡Á {8'h00, R, G, B})
// Output: 512-bit AXI-Stream packed RGB24 (64 bytes per beat)
//
// Packing scheme:
//   Each input beat provides 12 bytes (4 pixels ¡Á 3 RGB bytes, padding stripped).
//   64 bytes / 12 bytes = 5 full inputs + 4 remainder bytes.
//   The 16-input / 3-output pattern repeats exactly: LCM(12,64)=192 bytes.
//
//   Byte offset cycle: 0¡ú12¡ú24¡ú36¡ú48¡ú60*¡ú8¡ú20¡ú32¡ú44¡ú56*¡ú4¡ú16¡ú28¡ú40¡ú52*¡ú0¡ú...
//   Outputs (*) at offsets 60 (carry 8), 56 (carry 4), 52 (carry 0).
//
// Supports full backpressure (m_tready ¡ú s_tready).
// On line end (s_tlast), flushes partial output beat with zero-padding.
// ============================================================================
`timescale 1ns / 1ps

module pack4_rgb24_to_512 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,

    // Input: 128-bit from demosaic FIFO
    //   [31:0]   = pixel 0: {8'h00, R[7:0], G[7:0], B[7:0]}
    //   [63:32]  = pixel 1
    //   [95:64]  = pixel 2
    //   [127:96] = pixel 3
    input  wire [127:0] s_tdata,
    input  wire         s_tvalid,
    output wire         s_tready,
    input  wire         s_tlast,    // line end from demosaic
    input  wire         s_tuser,    // frame start (SOF)

    // Output: 512-bit packed RGB24
    output reg  [511:0] m_tdata,
    output reg          m_tvalid,
    input  wire         m_tready,
    output reg          m_tlast,        // line end marker
    output reg          m_frame_last,   // frame end marker
    output reg          sof,
    output reg          eof,
    output wire [31:0]  frame_count_out
);

    // ©¤©¤ Pixel extraction (strip 8-bit padding from each 32-bit pixel) ©¤©¤
    // Demosaic output: {8'h00, R[23:16], G[15:8], B[7:0]}
    // Reorder to {B, G, R} so that in little-endian memory: byte0=R, byte1=G, byte2=B
    // This matches V4L2_PIX_FMT_RGB24 (memory order R, G, B).
    wire [23:0] pix0 = {s_tdata[7:0],   s_tdata[15:8],  s_tdata[23:16]};
    wire [23:0] pix1 = {s_tdata[39:32], s_tdata[47:40], s_tdata[55:48]};
    wire [23:0] pix2 = {s_tdata[71:64], s_tdata[79:72], s_tdata[87:80]};
    wire [23:0] pix3 = {s_tdata[103:96],s_tdata[111:104],s_tdata[119:112]};

    // 12 bytes of pixel data per input beat (LSB-first in memory)
    wire [95:0] new_bytes = {pix3, pix2, pix1, pix0};

    // ©¤©¤ State ©¤©¤
    reg [31:0]  frame_count;
    reg [6:0]   byte_offset;    // current write position in accumulator (0..60, multiples of 4)
    reg [511:0] accum;          // byte accumulator for next output word
    reg         in_frame;
    reg         sof_pending;
    reg         flush_pending;  // partial beat flush on line end
    reg         flush_is_frame_last;

    assign frame_count_out = frame_count;

    // ©¤©¤ Flow control ©¤©¤
    wire output_free   = !m_tvalid || m_tready;
    wire will_emit     = (byte_offset == 7'd52) || (byte_offset == 7'd56) || (byte_offset == 7'd60);
    wire accept_input  = s_tvalid && s_tready;
    // Backpressure: stall input when output can't be emitted or flush pending
    assign s_tready = enable && !flush_pending &&
                      (will_emit ? output_free : 1'b1);

    // ©¤©¤ Main sequential logic ©¤©¤
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count        <= 32'd0;
            byte_offset        <= 7'd0;
            accum              <= 512'd0;
            in_frame           <= 1'b0;
            sof_pending        <= 1'b0;
            flush_pending      <= 1'b0;
            flush_is_frame_last <= 1'b0;
            m_tdata            <= 512'd0;
            m_tvalid           <= 1'b0;
            m_tlast            <= 1'b0;
            m_frame_last       <= 1'b0;
            sof                <= 1'b0;
            eof                <= 1'b0;
        end else begin
            // ©¤©¤ Clear output when accepted ©¤©¤
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
                byte_offset        <= 7'd0;
                accum              <= 512'd0;
                in_frame           <= 1'b0;
                sof_pending        <= 1'b0;
                flush_pending      <= 1'b0;
                flush_is_frame_last <= 1'b0;
                m_tvalid           <= 1'b0;
                m_tlast            <= 1'b0;
                m_frame_last       <= 1'b0;
                sof                <= 1'b0;
                eof                <= 1'b0;
            end else if (flush_pending && output_free) begin
                // ©¤©¤ Flush partial beat at line end ©¤©¤
                if (byte_offset != 7'd0) begin
                    m_tdata      <= accum;
                    m_tvalid     <= 1'b1;
                    m_tlast      <= 1'b1;
                    m_frame_last <= flush_is_frame_last;
                    sof          <= sof_pending;
                    eof          <= flush_is_frame_last;
                    sof_pending  <= 1'b0;
                    accum        <= 512'd0;
                    byte_offset  <= 7'd0;
                end
                flush_pending      <= 1'b0;
                flush_is_frame_last <= 1'b0;
            end else if (accept_input) begin
                // ©¤©¤ Frame boundary ©¤©¤
                if (s_tuser) begin
                    if (in_frame)
                        flush_is_frame_last <= 1'b1;
                    in_frame    <= 1'b1;
                    sof_pending <= 1'b1;
                end

                // ©¤©¤ Insert 12 bytes at byte_offset, emit at 52/56/60 ©¤©¤
                case (byte_offset)
                    7'd0: begin
                        accum[95:0]   <= new_bytes;
                        byte_offset   <= 7'd12;
                    end
                    7'd4: begin
                        accum[127:32] <= new_bytes;
                        byte_offset   <= 7'd16;
                    end
                    7'd8: begin
                        accum[159:64] <= new_bytes;
                        byte_offset   <= 7'd20;
                    end
                    7'd12: begin
                        accum[191:96] <= new_bytes;
                        byte_offset   <= 7'd24;
                    end
                    7'd16: begin
                        accum[223:128] <= new_bytes;
                        byte_offset    <= 7'd28;
                    end
                    7'd20: begin
                        accum[255:160] <= new_bytes;
                        byte_offset    <= 7'd32;
                    end
                    7'd24: begin
                        accum[287:192] <= new_bytes;
                        byte_offset    <= 7'd36;
                    end
                    7'd28: begin
                        accum[319:224] <= new_bytes;
                        byte_offset    <= 7'd40;
                    end
                    7'd32: begin
                        accum[351:256] <= new_bytes;
                        byte_offset    <= 7'd44;
                    end
                    7'd36: begin
                        accum[383:288] <= new_bytes;
                        byte_offset    <= 7'd48;
                    end
                    7'd40: begin
                        accum[415:320] <= new_bytes;
                        byte_offset    <= 7'd52;
                    end
                    7'd44: begin
                        accum[447:352] <= new_bytes;
                        byte_offset    <= 7'd56;
                    end
                    7'd48: begin
                        accum[479:384] <= new_bytes;
                        byte_offset    <= 7'd60;
                    end
                    // ©¤©¤ Output-producing states ©¤©¤
                    7'd52: begin
                        // 12 bytes at offset 52 fills bytes 52-63 exactly ¡ú emit, no carry
                        m_tdata      <= {new_bytes, accum[415:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= 1'b0;
                        m_frame_last <= 1'b0;
                        sof          <= sof_pending;
                        eof          <= 1'b0;
                        sof_pending  <= 1'b0;
                        accum        <= 512'd0;
                        byte_offset  <= 7'd0;
                    end
                    7'd56: begin
                        // 12 bytes at offset 56: 8 fit (56-63), 4 carry
                        m_tdata      <= {new_bytes[63:0], accum[447:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= 1'b0;
                        m_frame_last <= 1'b0;
                        sof          <= sof_pending;
                        eof          <= 1'b0;
                        sof_pending  <= 1'b0;
                        accum        <= {480'd0, new_bytes[95:64]};
                        byte_offset  <= 7'd4;
                    end
                    7'd60: begin
                        // 12 bytes at offset 60: 4 fit (60-63), 8 carry
                        m_tdata      <= {new_bytes[31:0], accum[479:0]};
                        m_tvalid     <= 1'b1;
                        m_tlast      <= 1'b0;
                        m_frame_last <= 1'b0;
                        sof          <= sof_pending;
                        eof          <= 1'b0;
                        sof_pending  <= 1'b0;
                        accum        <= {448'd0, new_bytes[95:32]};
                        byte_offset  <= 7'd8;
                    end
                    default: begin
                        // Should never reach here ¡ª reset offset
                        byte_offset <= 7'd0;
                        accum       <= 512'd0;
                    end
                endcase

                // ©¤©¤ Line end ¡ú trigger flush ©¤©¤
                if (s_tlast)
                    flush_pending <= 1'b1;
            end
        end
    end

endmodule
