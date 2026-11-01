module csi_rx_10bit_unpack (
    input wire I_clock,
    input wire I_reset_n,
    input wire I_enable,
    input wire I_line_in,
    input wire I_raw12,
    input wire [2:0] I_valid_bytes,
    input wire [31:0] I_data_in,
    input wire I_din_valid,
    output reg [39:0] O_data_out,
    output reg O_dout_valid
);
    reg [71:0] pending_bytes;
    reg [3:0] byte_count;
    reg [71:0] merged_bytes;
    reg [3:0] merged_count;
    reg [39:0] unpacked_data;
    reg unpacked_valid;
    wire [3:0] group_bytes = I_raw12 ? 4'd6 : 4'd5;
    reg [31:0] masked_input;

    always @(*) begin
        case (I_valid_bytes)
            3'd1: masked_input = {24'd0, I_data_in[7:0]};
            3'd2: masked_input = {16'd0, I_data_in[15:0]};
            3'd3: masked_input = {8'd0, I_data_in[23:0]};
            3'd4: masked_input = I_data_in;
            default: masked_input = 32'd0;
        endcase
        merged_bytes = pending_bytes;
        merged_count = byte_count;
        if (I_din_valid && I_valid_bytes >= 1 && I_valid_bytes <= 4) begin
            merged_bytes = pending_bytes | ({40'd0, masked_input} << (byte_count * 8));
            merged_count = byte_count + {1'b0, I_valid_bytes};
        end
    end

    always @(posedge I_clock or negedge I_reset_n) begin
        if (!I_reset_n) begin
            pending_bytes <= 72'd0;
            byte_count <= 4'd0;
            unpacked_data <= 40'd0;
            unpacked_valid <= 1'b0;
            O_data_out <= 40'd0;
            O_dout_valid <= 1'b0;
        end else begin
            O_data_out <= unpacked_data;
            O_dout_valid <= unpacked_valid && I_enable;
            unpacked_valid <= 1'b0;
            if (!I_enable || I_line_in) begin
                pending_bytes <= 72'd0;
                byte_count <= 4'd0;
                unpacked_data <= 40'd0;
                if (!I_enable) begin
                    O_data_out <= 40'd0;
                    O_dout_valid <= 1'b0;
                end
            end else if (merged_count >= group_bytes) begin
                if (I_raw12) begin
                    unpacked_data[9:0] <= {merged_bytes[7:0], merged_bytes[19:18]};
                    unpacked_data[19:10] <= {merged_bytes[15:8], merged_bytes[23:22]};
                    unpacked_data[29:20] <= {merged_bytes[31:24], merged_bytes[43:42]};
                    unpacked_data[39:30] <= {merged_bytes[39:32], merged_bytes[47:46]};
                    pending_bytes <= merged_bytes >> 48;
                end else begin
                    unpacked_data[9:0] <= {merged_bytes[7:0], merged_bytes[33:32]};
                    unpacked_data[19:10] <= {merged_bytes[15:8], merged_bytes[35:34]};
                    unpacked_data[29:20] <= {merged_bytes[23:16], merged_bytes[37:36]};
                    unpacked_data[39:30] <= {merged_bytes[31:24], merged_bytes[39:38]};
                    pending_bytes <= merged_bytes >> 40;
                end
                byte_count <= merged_count - group_bytes;
                unpacked_valid <= 1'b1;
            end else begin
                pending_bytes <= merged_bytes;
                byte_count <= merged_count;
            end
        end
    end
endmodule
