// =============================================================================
// serializer_128to24.v ¡ª 4:1 Pixel Serializer
// =============================================================================
// Demosaic outputs 128-bit (4 pixels ¡Á {8'b0, R[7:0], G[7:0], B[7:0]}) per beat.
// stdvid_nobp_packer expects 24-bit (1 pixel ¡Á {R, G, B}) per beat.
//
// Pixel layout in 128-bit input:
//   [31:0]   = pixel 0 = {8'b0, R0, G0, B0}
//   [63:32]  = pixel 1 = {8'b0, R1, G1, B1}
//   [95:64]  = pixel 2 = {8'b0, R2, G2, B2}
//   [127:96] = pixel 3 = {8'b0, R3, G3, B3}
//
// Timing: 4 output cycles per input beat, zero-bubble back-to-back.
// AXI-Stream handshake on input; stdvid-style (de/user/last) on output.
// =============================================================================
`timescale 1ns / 1ps

module serializer_128to24 (
    input  wire          clk,
    input  wire          rst_n,

    // Input: AXI-Stream 128-bit from demosaic
    input  wire [127:0]  s_tdata,
    input  wire          s_tvalid,
    output wire          s_tready,
    input  wire          s_tuser,       // SOF (frame start)
    input  wire          s_tlast,       // EOL (line end)

    // Output: stdvid-style 24-bit to packer
    output reg  [23:0]   src_data,
    output reg           src_de,
    output reg           src_user,      // SOF on first pixel of frame
    output reg           src_last       // EOL on last pixel of line
);

    reg [1:0]    cnt;           // pixel index within group (0-3)
    reg [127:0]  data_reg;     // latched 128-bit group
    reg          user_reg;     // latched tuser
    reg          last_reg;     // latched tlast
    reg          busy;         // serializing in progress

    // Accept new 128-bit word only when not busy
    assign s_tready = ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            cnt      <= 2'd0;
            data_reg <= 128'd0;
            user_reg <= 1'b0;
            last_reg <= 1'b0;
            src_data <= 24'd0;
            src_de   <= 1'b0;
            src_user <= 1'b0;
            src_last <= 1'b0;
        end
        else if (!busy) begin
            // Idle: waiting for new data
            if (s_tvalid) begin
                // Latch the 128-bit group and sideband signals
                data_reg <= s_tdata;
                user_reg <= s_tuser;
                last_reg <= s_tlast;
                busy     <= 1'b1;
                cnt      <= 2'd1;
                // Emit pixel 0 immediately
                src_data <= s_tdata[23:0];
                src_de   <= 1'b1;
                src_user <= s_tuser;   // SOF only on first pixel
                src_last <= 1'b0;      // never EOL on first pixel of group
            end
            else begin
                src_de   <= 1'b0;
                src_user <= 1'b0;
                src_last <= 1'b0;
            end
        end
        else begin
            // Busy: emit pixels 1, 2, 3
            case (cnt)
                2'd1: begin
                    src_data <= data_reg[55:32];
                    src_de   <= 1'b1;
                    src_user <= 1'b0;
                    src_last <= 1'b0;
                    cnt      <= 2'd2;
                end
                2'd2: begin
                    src_data <= data_reg[87:64];
                    src_de   <= 1'b1;
                    src_user <= 1'b0;
                    src_last <= 1'b0;
                    cnt      <= 2'd3;
                end
                2'd3: begin
                    src_data <= data_reg[119:96];
                    src_de   <= 1'b1;
                    src_user <= 1'b0;
                    src_last <= last_reg;  // EOL on last pixel of group
                    busy     <= 1'b0;
                    cnt      <= 2'd0;
                end
                default: begin
                    src_de   <= 1'b0;
                    busy     <= 1'b0;
                    cnt      <= 2'd0;
                end
            endcase
        end
    end

endmodule
