module csi_rx_clock_det (
    input wire I_ref_clock,
    input wire I_ext_clock,
    input wire I_enable,
    input wire I_reset_in,
    output wire O_reset_out
);
    wire ref_reset_n;
    wire ext_reset_n;
    board_reset_release ref_release (I_ref_clock, I_reset_in, ref_reset_n);
    board_reset_release ext_release (I_ext_clock, I_reset_in, ext_reset_n);
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] enable_sync;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] probe_sync;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] reply_sync;
    reg probe;
    reg reply;
    reg [7:0] fail_count;
    reg [1:0] good_replies;
    reg clock_alive;

    always @(posedge I_ext_clock or negedge ext_reset_n) begin
        if (!ext_reset_n) begin
            probe_sync <= 2'b00;
            reply <= 1'b0;
        end else begin
            probe_sync <= {probe_sync[0], probe};
            reply <= probe_sync[1];
        end
    end

    always @(posedge I_ref_clock or negedge ref_reset_n) begin
        if (!ref_reset_n) begin
            enable_sync <= 2'b00;
            reply_sync <= 2'b00;
            probe <= 1'b1;
            fail_count <= 8'd0;
            good_replies <= 2'd0;
            clock_alive <= 1'b0;
        end else begin
            enable_sync <= {enable_sync[0], I_enable};
            reply_sync <= {reply_sync[0], reply};
            if (!enable_sync[1]) begin
                fail_count <= 8'd0;
                good_replies <= 2'd0;
                clock_alive <= 1'b0;
                if (reply_sync[1] == probe)
                    probe <= ~probe;
            end else if (reply_sync[1] == probe) begin
                probe <= ~probe;
                fail_count <= 8'd0;
                if (good_replies < 2'd2)
                    good_replies <= good_replies + 1'b1;
                if (good_replies >= 2'd1)
                    clock_alive <= 1'b1;
            end else if (fail_count < 8'd250) begin
                fail_count <= fail_count + 1'b1;
            end else begin
                clock_alive <= 1'b0;
                good_replies <= 2'd0;
            end
        end
    end

    board_reset_release byte_release (
        I_ext_clock, I_reset_in & clock_alive, O_reset_out
    );
endmodule
