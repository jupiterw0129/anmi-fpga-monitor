module rx_delay_config714 (
    input wire clock,
    input wire reset_n,
    input wire write_pulse,
    input wire idle,
    input wire [3:0] write_strobes,
    input wire [31:0] write_data,
    output reg [5:0] delay_config
);
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            delay_config <= 0;
        else if (write_pulse && idle && write_strobes[0] && write_data[31:6] == 0)
            delay_config <= write_data[5:0];
    end
endmodule
