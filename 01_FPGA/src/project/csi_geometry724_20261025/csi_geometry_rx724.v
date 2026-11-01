// Aligned CSI bytes -> ordered packet tokens -> actual board FIFO -> RAW10.
// All output transfers, including abort/end controls, use the same handshake.
// This module is not a drop-in replacement for the old pixel-only interface.
module csi_geometry_rx724 #(
    parameter MAX_BYTES=8192,
    parameter QUEUE_BITS=4,
    parameter FIFO_BITS=13
)(
    input wire source_clk, source_reset_n, enable,
    input wire [31:0] input_data,
    input wire input_valid,
    output wire packet_done, sync_wait, header_attempt, header_valid,
    output wire header_bad, filter_bad, crc_bad, truncated, overflow, queue_overflow,
    input wire dest_clk, dest_reset_n,
    output wire [39:0] output_data,
    output wire output_valid,
    input wire output_ready,
    output wire output_sof, output_eol, output_abort, output_frame_end, output_frame_start
);
    wire shared_reset_n=source_reset_n && dest_reset_n && enable;
    wire source_release_n, dest_release_n;
    board_reset_release source_release(source_clk,shared_reset_n,source_release_n);
    board_reset_release dest_release(dest_clk,shared_reset_n,dest_release_n);
    wire [63:0] source_token, fifo_token;
    reg [63:0] dest_token;
    reg dest_valid;
    wire source_valid, source_ready, fifo_valid, dest_ready;
    wire fifo_ready=!dest_valid || dest_ready;
    // Break the RAM read-to-decode combinational path at the destination clock.
    always @(posedge dest_clk or negedge dest_release_n) begin
        if (!dest_release_n) begin dest_valid<=0; dest_token<=0; end
        else if (fifo_ready) begin
            dest_valid<=fifo_valid;
            if (fifo_valid) dest_token<=fifo_token;
        end
    end
    csi_ordered_packets724 #(.MAX_BYTES(MAX_BYTES),.QUEUE_BITS(QUEUE_BITS)) ordered (
        .clock(source_clk),.reset_n(source_release_n),.enable(1'b1),
        .input_data(input_data),.input_valid(input_valid),
        .packet_done(packet_done),.sync_wait(sync_wait),
        .header_attempt(header_attempt),.header_valid(header_valid),
        .header_bad(header_bad),.filter_bad(filter_bad),.crc_bad(crc_bad),
        .truncated(truncated),.overflow(overflow),.queue_overflow(queue_overflow),
        .token_data(source_token),.token_valid(source_valid),.token_ready(source_ready)
    );
    csi_token_cdc724 #(.ADDR_BITS(FIFO_BITS)) crossing (
        .source_clk(source_clk),.source_reset_n(source_release_n),
        .source_data(source_token),.source_valid(source_valid),.source_ready(source_ready),
        .dest_clk(dest_clk),.dest_reset_n(dest_release_n),
        .dest_data(fifo_token),.dest_valid(fifo_valid),.dest_ready(fifo_ready)
    );
    csi_raw_decode_geometry724 decode (
        .clock(dest_clk),.reset_n(dest_release_n),
        .token_data(dest_token),.token_valid(dest_valid),.token_ready(dest_ready),
        .output_data(output_data),.output_valid(output_valid),.output_ready(output_ready),
        .output_sof(output_sof),.output_eol(output_eol),
        .output_abort(output_abort),.output_frame_end(output_frame_end),.output_frame_start(output_frame_start)
    );
endmodule
