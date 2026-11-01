// Drop-in experimental replacement for shared_iddr_reset711d.
// Store asserted reset as 1 so the active-high PAD reset can use Q directly.
// The external active-low interface and three-edge release delay are retained.
module shared_iddr_reset711d (
    input wire serial_clock,
    input wire async_reset_n,
    output wire reset_n
);
    (* async_reg = "true", dont_touch = "true" *) reg [2:0] release_sync;
    always @(posedge serial_clock or negedge async_reset_n) begin
        if (!async_reset_n)
            release_sync <= 3'b111;
        else
            release_sync <= {release_sync[1:0], 1'b0};
    end
    assign reset_n = ~release_sync[2];
endmodule
