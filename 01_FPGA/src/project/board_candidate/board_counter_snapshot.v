module board_counter_snapshot (
    input wire source_clk,
    input wire source_reset_n,
    input wire [31:0] source_data,
    input wire dest_clk,
    input wire dest_reset_n,
    output reg [31:0] dest_data,
    output reg dest_valid
);
    wire shared_reset_n = source_reset_n & dest_reset_n;
    wire source_local_reset_n;
    wire dest_local_reset_n;
    board_reset_release source_release (source_clk, shared_reset_n, source_local_reset_n);
    board_reset_release dest_release (dest_clk, shared_reset_n, dest_local_reset_n);
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] request_sync;
    (* async_reg = "true", dont_touch = "true" *) reg [1:0] acknowledge_sync;
    reg request;
    reg acknowledge;
    reg [31:0] held_data;
    reg pending;

    always @(posedge source_clk or negedge source_local_reset_n) begin
        if (!source_local_reset_n) begin
            request_sync <= 2'b00;
            acknowledge <= 1'b0;
            held_data <= 32'd0;
        end else begin
            request_sync <= {request_sync[0], request};
            if (request_sync[1] != acknowledge) begin
                held_data <= source_data;
                acknowledge <= request_sync[1];
            end
        end
    end

    always @(posedge dest_clk or negedge dest_local_reset_n) begin
        if (!dest_local_reset_n) begin
            acknowledge_sync <= 2'b00;
            request <= 1'b0;
            pending <= 1'b0;
            dest_data <= 32'd0;
            dest_valid <= 1'b0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge};
            dest_valid <= 1'b0;
            if (!pending) begin
                request <= ~request;
                pending <= 1'b1;
            end else if (acknowledge_sync[1] == request) begin
                dest_data <= held_data;
                dest_valid <= 1'b1;
                pending <= 1'b0;
            end
        end
    end
endmodule
