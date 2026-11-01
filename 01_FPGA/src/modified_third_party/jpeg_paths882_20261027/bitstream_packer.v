// SPDX-License-Identifier: Apache-2.0
// Commons Clause v1.0 applies — commercial use requires written permission. Contact: hello@bard0.com
// Copyright (c) 2026 Leonardo Capossio — bard0 design
//
// ============================================================================
// Bitstream Packer
// ============================================================================
// Accumulates variable-length Huffman codes into a byte-aligned output stream.
// Handles JPEG byte stuffing (0xFF -> 0xFF 0x00).
//
// Features:
//   - 64-bit accumulator for variable-length codes (up to 32 bits)
//   - JPEG byte stuffing (0xFF -> 0xFF 0x00)
//   - Backpressure to Huffman encoder (bp_ready output)
//   - Restart marker insertion (pad + 0xFF + 0xD0-0xD7)
//   - Frame byte counting (reported via byte_count output)
//   - Flush at end of frame (pad with 1-bits to byte boundary)
//
// Input:  Variable-length code words (up to 32 bits) with length
// Output: 8-bit byte stream via AXI4-Stream
// ============================================================================

module bitstream_packer (
    /* verilator coverage_off */
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_bits,
    input  wire [5:0]  in_len,
    input  wire        in_flush,
    input  wire        in_restart,
    output wire        bp_ready,
    output reg         out_valid,
    output reg  [7:0]  out_data,
    output reg         out_last,
    input  wire        out_ready,
    output reg  [31:0] byte_count
    /* verilator coverage_on */
);

    // ========================================================================
    // Bit accumulator
    // ========================================================================
    /* verilator coverage_off */
    reg [63:0] aligned_code;
    reg [5:0] aligned_len;
    reg pending_restart,pending_flush;
    reg [63:0] bit_buf;
    reg [6:0]  bit_cnt;
    reg        need_stuff;
    reg [2:0] state;
    reg [2:0] rst_counter;
    /* verilator coverage_on */

    // State machine for restart marker and flush
    localparam S_NORMAL     = 3'd0;
    localparam S_RST_PAD    = 3'd1;
    localparam S_RST_DRAIN  = 3'd2;
    localparam S_RST_FF     = 3'd3;
    localparam S_RST_MARKER = 3'd4;
    localparam S_FLUSH_PAD  = 3'd5;
    localparam S_FLUSH_LAST = 3'd6;
    localparam S_ALIGN = 3'd7;

    // An accepted code is aligned first, then accumulated on the next edge.
    // Holding the accumulator on the accept edge keeps its alignment exact.
    // Requests coincident with acceptance are retained until that code merges.
    // Exact registered predicate of the next bit count. Readiness has the
    // same cycle semantics while no counter comparator reaches Huffman.
    reg capacity_ready;
    assign bp_ready = (state == S_NORMAL) && capacity_ready;
    wire out_free = !out_valid || out_ready;
    wire [63:0] merged = bit_buf | aligned_code;
    // ========================================================================
    // Main logic
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            aligned_code<=0;aligned_len<=0;pending_restart<=0;pending_flush<=0;
            bit_buf     <= 64'd0;
            bit_cnt     <= 7'd0; capacity_ready <= ((7'd0) <= 7'd32);
            out_valid   <= 1'b0;
            out_data    <= 8'd0;
            out_last    <= 1'b0;
            need_stuff  <= 1'b0;
            state       <= S_NORMAL;
            rst_counter <= 3'd0;
            byte_count  <= 32'd0;
        end else begin
            // Default: deassert valid when downstream accepts
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                out_last  <= 1'b0;
            end

            case (state)
                // ==============================================================
                // NORMAL: Accept input, output bytes
                // ==============================================================
                S_NORMAL: begin
                    if(in_valid && bp_ready)begin
                        aligned_code<=({in_bits,32'd0} >> bit_cnt);
                        aligned_len<=in_len;
                        pending_restart<=in_restart;pending_flush<=in_flush;
                        state<=S_ALIGN;
                    end else begin
                        if(need_stuff && out_free)begin
                            out_valid<=1;out_data<=0;need_stuff<=0;byte_count<=byte_count+1'b1;
                        end else if(bit_cnt>=8 && !need_stuff && out_free)begin
                            out_valid<=1;out_data<=bit_buf[63:56];
                            bit_buf<={bit_buf[55:0],8'd0};bit_cnt<=bit_cnt-7'd8; capacity_ready <= ((bit_cnt-7'd8) <= 7'd32);
                            byte_count<=byte_count+1'b1;
                            if(bit_buf[63:56]==8'hff)need_stuff<=1;
                        end
                        if(in_restart)state<=S_RST_PAD;
                        else if(in_flush)state<=S_FLUSH_PAD;
                    end
                end
                S_ALIGN:begin
                    bit_buf<=merged;bit_cnt<=bit_cnt+{1'b0,aligned_len}; capacity_ready <= ((bit_cnt+{1'b0,aligned_len}) <= 7'd32);
                    if(need_stuff && out_free)begin
                        out_valid<=1;out_data<=0;need_stuff<=0;byte_count<=byte_count+1'b1;
                    end else if(bit_cnt>=8 && !need_stuff && out_free)begin
                        out_valid<=1;out_data<=bit_buf[63:56];
                        bit_buf<={merged[55:0],8'd0};bit_cnt<=bit_cnt-7'd8+{1'b0,aligned_len}; capacity_ready <= ((bit_cnt-7'd8+{1'b0,aligned_len}) <= 7'd32);
                        byte_count<=byte_count+1'b1;
                        if(bit_buf[63:56]==8'hff)need_stuff<=1;
                    end
                    pending_restart<=0;pending_flush<=0;
                    if(pending_restart || in_restart)state<=S_RST_PAD;
                    else if(pending_flush || in_flush)state<=S_FLUSH_PAD;
                    else state<=S_NORMAL;
                end

                // ==============================================================
                // RESTART: Pad bits to byte boundary
                // ==============================================================
                S_RST_PAD: begin
                    if (!out_valid || out_ready) begin
                        if (need_stuff) begin
                            // Emit the stuff byte first
                            out_valid  <= 1'b1;
                            out_data   <= 8'h00;
                            need_stuff <= 1'b0;
                            byte_count <= byte_count + 32'd1;
                        end else if (bit_cnt > 7'd0) begin
                            // Pad partial byte with 1s
                            if (bit_cnt < 7'd8) begin
                                bit_buf[63:56] <= bit_buf[63:56] | (8'hFF >> bit_cnt[2:0]);
                                bit_cnt <= 7'd8; capacity_ready <= ((7'd8) <= 7'd32);
                            end
                            state <= S_RST_DRAIN;
                        end else begin
                            state <= S_RST_FF;
                        end
                    end
                end

                // ==============================================================
                // RESTART: Drain remaining bytes
                // ==============================================================
                S_RST_DRAIN: begin
                    if (!out_valid || out_ready) begin
                        if (need_stuff) begin
                            out_valid  <= 1'b1;
                            out_data   <= 8'h00;
                            need_stuff <= 1'b0;
                            byte_count <= byte_count + 32'd1;
                        end else if (bit_cnt >= 7'd8) begin
                            out_valid  <= 1'b1;
                            out_data   <= bit_buf[63:56];
                            bit_buf    <= {bit_buf[55:0], 8'd0};
                            bit_cnt    <= bit_cnt - 7'd8; capacity_ready <= ((bit_cnt - 7'd8) <= 7'd32);
                            byte_count <= byte_count + 32'd1;
                            if (bit_buf[63:56] == 8'hFF)
                                need_stuff <= 1'b1;
                        end else if (bit_cnt > 7'd0) begin
                            // Pad the final 1-7 leftover bits to a byte boundary
                            // with 1s and emit them as the last entropy byte
                            // before the marker.  Reached when the restart arrived
                            // with >=8 bits pending (S_RST_PAD only pads a wholly
                            // sub-byte residual); without this the leftover bits
                            // were dropped.  Stay in S_RST_DRAIN with bit_cnt=0 so
                            // the need_stuff check above emits an 0x00 next cycle
                            // if the padded byte is 0xFF.
                            out_valid  <= 1'b1;
                            out_data   <= bit_buf[63:56] | (8'hFF >> bit_cnt[2:0]);
                            byte_count <= byte_count + 32'd1;
                            bit_buf    <= 64'd0;
                            bit_cnt    <= 7'd0; capacity_ready <= ((7'd0) <= 7'd32);
                            if ((bit_buf[63:56] | (8'hFF >> bit_cnt[2:0])) == 8'hFF)
                                need_stuff <= 1'b1;
                        end else begin
                            state <= S_RST_FF;
                        end
                    end
                end

                // ==============================================================
                // RESTART: Emit 0xFF marker prefix
                // ==============================================================
                S_RST_FF: begin
                    if (!out_valid || out_ready) begin
                        out_valid  <= 1'b1;
                        out_data   <= 8'hFF;
                        need_stuff <= 1'b0; // Next byte is marker, not stuffing
                        byte_count <= byte_count + 32'd1;
                        state      <= S_RST_MARKER;
                    end
                end

                // ==============================================================
                // RESTART: Emit RST marker (0xD0 + counter)
                // ==============================================================
                S_RST_MARKER: begin
                    if (!out_valid || out_ready) begin
                        out_valid   <= 1'b1;
                        out_data    <= {5'b11010, rst_counter};
                        byte_count  <= byte_count + 32'd1;
                        rst_counter <= rst_counter + 3'd1; // Wraps 0-7 automatically
                        state       <= S_NORMAL;
                        // Reset bit accumulator for new segment
                        bit_buf <= 64'd0;
                        bit_cnt <= 7'd0; capacity_ready <= ((7'd0) <= 7'd32);
                    end
                end

                // ==============================================================
                // FLUSH: Pad and drain (end of frame)
                // ==============================================================
                S_FLUSH_PAD: begin
                    if (!out_valid || out_ready) begin
                        if (need_stuff) begin
                            out_valid  <= 1'b1;
                            out_data   <= 8'h00;
                            need_stuff <= 1'b0;
                            byte_count <= byte_count + 32'd1;
                        end else if (bit_cnt >= 7'd8) begin
                            // Drain full bytes
                            out_valid  <= 1'b1;
                            out_data   <= bit_buf[63:56];
                            bit_buf    <= {bit_buf[55:0], 8'd0};
                            bit_cnt    <= bit_cnt - 7'd8; capacity_ready <= ((bit_cnt - 7'd8) <= 7'd32);
                            byte_count <= byte_count + 32'd1;
                            if (bit_buf[63:56] == 8'hFF)
                                need_stuff <= 1'b1;
                        end else if (bit_cnt > 7'd0) begin
                            // Pad partial byte with 1s and output
                            out_valid  <= 1'b1;
                            out_data   <= bit_buf[63:56] | (8'hFF >> bit_cnt[2:0]);
                            byte_count <= byte_count + 32'd1;
                            bit_buf    <= 64'd0;
                            bit_cnt    <= 7'd0; capacity_ready <= ((7'd0) <= 7'd32);
                            // Check for 0xFF
                            if ((bit_buf[63:56] | (8'hFF >> bit_cnt[2:0])) == 8'hFF)
                                need_stuff <= 1'b1;
                            else
                                state <= S_FLUSH_LAST;
                        end else begin
                            // No bits left, go to last
                            state <= S_FLUSH_LAST;
                        end
                    end
                end

                // ==============================================================
                // FLUSH: Signal end of frame
                // ==============================================================
                S_FLUSH_LAST: begin
                    if (!out_valid || out_ready) begin
                        if (need_stuff) begin
                            out_valid  <= 1'b1;
                            out_data   <= 8'h00;
                            need_stuff <= 1'b0;
                            byte_count <= byte_count + 32'd1;
                        end else begin
                            out_last <= 1'b1;
                            out_valid <= 1'b1;
                            out_data <= 8'h00; // Dummy byte with tlast
                            state <= S_NORMAL;
                            // Reset for next frame
                            bit_buf     <= 64'd0;
                            bit_cnt     <= 7'd0; capacity_ready <= ((7'd0) <= 7'd32);
                            rst_counter <= 3'd0;
                        end
                    end
                end

                default: state <= S_NORMAL;
            endcase
        end
    end

endmodule
