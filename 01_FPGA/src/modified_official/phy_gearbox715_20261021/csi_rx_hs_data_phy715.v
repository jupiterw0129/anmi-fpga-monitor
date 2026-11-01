`timescale 1 ps / 1 ps
module csi_rx_hs_data_phy715 (
    input wire I_rxclk,
    input wire I_rxclk_div_x2,
    input wire I_rxclk_div_x4,
    input wire I_reset_n,
    input wire I_iddr_reset_n,
    input wire I_hs_data_p,
    input wire [5:0] I_delay_value,
    input wire I_delay_vaild,
    output wire [7:0] O_rx_data,
    output wire O_delay_data_val
);
    wire delayed_data;
    wire [3:0] sampled_nibble;
    reg [3:0] previous_nibble;
    reg [7:0] sampled_byte;
    reg [7:0] paired_byte;
    wire byte_reset_n;
    reg [3:0] warmup;

    board_reset_release byte_release (
        I_rxclk, I_reset_n & I_iddr_reset_n, byte_reset_n
    );

    PH1_LOGIC_DYNAMIC_IDELAY #(.WIDTH(5)) delay_input (
        .i(I_hs_data_p), .indly_en(1'b1),
        .in_dly(I_delay_value[4:0]), .o(delayed_data)
    );

    PH1_LOGIC_IDDRx2l #(.ASYNCRST("ENABLE")) sample_input (
        .q3(sampled_nibble[3]), .q2(sampled_nibble[2]),
        .q1(sampled_nibble[1]), .q0(sampled_nibble[0]),
        .sclk(I_rxclk_div_x4),
        .d(delayed_data), .rst(~I_iddr_reset_n)
    );

    always @(posedge I_rxclk_div_x2) begin
        previous_nibble <= sampled_nibble;
        paired_byte <= {sampled_nibble, previous_nibble};
    end

    always @(posedge I_rxclk)
        sampled_byte <= paired_byte;

    always @(posedge I_rxclk or negedge byte_reset_n) begin
        if (!byte_reset_n)
            warmup <= 4'b0000;
        else
            warmup <= {warmup[2:0], 1'b1};
    end

    assign O_delay_data_val = warmup[3];
    assign O_rx_data = warmup[3] ? sampled_byte : 8'b0;
endmodule

