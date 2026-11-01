module rx_snapshot714 (
    input wire source_clk,
    input wire source_reset_n,
    input wire [1023:0] source_data,
    input wire dest_clk,
    input wire dest_reset_n,
    input wire capture,
    input wire [7:0] index,
    output reg [31:0] read_data
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
    reg [1023:0] held_data;
    reg [1023:0] dest_data;
    reg pending;
    reg valid;
    reg [31:0] generation;
    always @(posedge source_clk or negedge source_local_reset_n) begin
        if (!source_local_reset_n) begin
            request_sync <= 0;
            acknowledge <= 0;
            held_data <= 0;
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
            acknowledge_sync <= 0;
            request <= 0;
            pending <= 0;
            valid <= 0;
            generation <= 0;
            dest_data <= 0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge};
            if (capture && !pending) begin
                request <= ~request;
                pending <= 1;
                valid <= 0;
            end else if (pending && acknowledge_sync[1] == request) begin
                dest_data <= held_data;
                pending <= 0;
                valid <= 1;
                generation <= generation + 1'b1;
            end
        end
    end
    always @(*) begin
        read_data = 0;
        case (index)
            0: read_data = 32'h52583714;
            1: read_data = {29'd0, dest_local_reset_n, pending, valid};
            2: read_data = generation;
            3: read_data = 32;
            default: if (index >= 4 && index < 36 && valid)
                read_data = dest_data[(index-4)*32 +: 32];
        endcase
    end
endmodule
