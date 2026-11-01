// Four aligned bytes/cycle, little-endian lane order. Store then release only
// after header ECC and full payload/footer CRC agree. Same clock on both ports.
// Integration must carry packet_header alongside data and order short packets.
module csi_packet_guard_frame724 #(
    parameter MAX_BYTES = 8192,
    parameter VC_ID = 0,
    parameter IDLE_TIMEOUT = 32
)(
    input wire clock, reset_n, enable,
    input wire [31:0] input_data,
    input wire input_valid,
    output reg [23:0] packet_header,
    output wire header_attempt,
    output wire header_valid,
    output wire sync_wait,
    output reg packet_done,
    output reg packet_good,
    output reg header_bad,
    output reg filter_bad,
    output reg crc_bad,
    output reg truncated,
    output reg overflow,
    output reg short_valid,
    output reg [23:0] short_header,
    output wire [31:0] output_data,
    output reg [3:0] output_keep,
    output reg output_valid,
    input wire output_ready,
    output reg output_last,
    output reg [23:0] output_header
);
    localparam WORDS = (MAX_BYTES+3)/4;
    localparam ADDR_BITS = $clog2(WORDS);
    localparam FREE=0, WRITING=1, READY=2, READING=3;
    localparam WAIT_HEADER=0, RECEIVE=1, DRAIN=2;
    (* ram_style = "bram" *) reg [31:0] memory0 [0:WORDS-1];
    (* ram_style = "bram" *) reg [31:0] memory1 [0:WORDS-1];
    reg [31:0] bank_data0, bank_data1;
    reg output_bank;
    assign output_data = output_bank ? bank_data1 : bank_data0;
    reg [1:0] state0, state1;
    reg [1:0] rx_state;
    reg write_bank, read_bank;
    reg [15:0] length0, length1, rx_length;
    reg [23:0] header0, header1;
    reg [16:0] rx_position;
    reg [15:0] crc, crc_next;
    reg [7:0] footer_low, footer_low_next;
    reg [31:0] idle_cycles;
    reg reading;
    reg [16:0] read_position;
    reg [15:0] read_length;
    wire [7:0] expected_ecc;
    csi_rx_hdr_ecc header_ecc(.data(input_data[23:0]), .ecc(expected_ecc));
    wire ecc_ok = input_data[31:24] == expected_ecc;
    wire vc_ok = input_data[7:6] == VC_ID;
    wire [5:0] kind = input_data[5:0];
    wire is_short = kind <= 3;
    wire is_long = kind == 6'h12 || kind == 6'h2b || kind == 6'h2c || kind == 6'h37;
    assign header_attempt = enable && rx_state==WAIT_HEADER && input_valid;
    assign header_valid = header_attempt && ecc_ok && vc_ok && (is_short || is_long);
    assign sync_wait = rx_state==WAIT_HEADER;
    wire bank_free = write_bank ? state1==FREE : state0==FREE;
    wire write_word = enable && rx_state==RECEIVE && input_valid && rx_position<rx_length;
    wire issue_read = enable && reading && (!output_valid || output_ready);
    wire [16:0] output_remaining = {1'b0,read_length}-read_position;
    wire [ADDR_BITS-1:0] write_address = rx_position[ADDR_BITS+1:2];
    wire [ADDR_BITS-1:0] read_address = read_position[ADDR_BITS+1:2];

    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] byte_value;
        reg [15:0] value;
        integer bit_index;
        begin
            value = previous ^ {8'd0,byte_value};
            for (bit_index=0;bit_index<8;bit_index=bit_index+1)
                value = value[0] ? (value>>1)^16'h8408 : value>>1;
            crc_byte = value;
        end
    endfunction

    integer lane;
    reg footer_complete, footer_matches;
    always @* begin
        crc_next = crc;
        footer_low_next = footer_low;
        footer_complete = 0;
        footer_matches = 0;
        for (lane=0;lane<4;lane=lane+1) begin
            if (rx_position+lane < rx_length)
                crc_next = crc_byte(crc_next,input_data[lane*8 +: 8]);
            else if (rx_position+lane == rx_length)
                footer_low_next = input_data[lane*8 +: 8];
            else if (rx_position+lane == {1'b0,rx_length}+1) begin
                footer_complete = 1;
                footer_matches = {input_data[lane*8 +: 8],footer_low_next} == crc_next;
            end
        end
    end

    // No reset on RAM arrays or RAM output, to infer embedded RAM.
    always @(posedge clock) begin
        if (write_word) begin
            if (write_bank) memory1[write_address] <= input_data;
            else memory0[write_address] <= input_data;
        end
        if (issue_read) begin
            output_bank <= read_bank;
            if (read_bank) bank_data1 <= memory1[read_address];
            else bank_data0 <= memory0[read_address];
        end
    end

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state0<=FREE; state1<=FREE; rx_state<=WAIT_HEADER;
            write_bank<=0; read_bank<=0; length0<=0; length1<=0;
            header0<=0; header1<=0; rx_length<=0; rx_position<=0;
            crc<=16'hffff; footer_low<=0; idle_cycles<=0;
            reading<=0; read_position<=0; read_length<=0;
            output_valid<=0; output_keep<=0; output_last<=0; output_header<=0;
            packet_header<=0;
            packet_done<=0; packet_good<=0; header_bad<=0; filter_bad<=0;
            crc_bad<=0; truncated<=0; overflow<=0; short_valid<=0; short_header<=0;
        end else begin
            packet_done<=0; packet_good<=0; header_bad<=0; filter_bad<=0;
            crc_bad<=0; truncated<=0; overflow<=0; short_valid<=0;
            if (!enable) begin
                rx_state<=WAIT_HEADER; state0<=FREE; state1<=FREE;
                write_bank<=0; read_bank<=0; reading<=0; output_valid<=0;
                output_keep<=0; output_last<=0; idle_cycles<=0;
            end else begin
                if (output_valid && output_ready) begin
                    output_valid<=0;
                    if (output_last) begin
                        if (read_bank) state1<=FREE; else state0<=FREE;
                        read_bank<=!read_bank;
                    end
                end
                if (!reading && !output_valid && (read_bank ? state1==READY : state0==READY)) begin
                    reading<=1;
                    read_position<=0;
                    read_length<=read_bank ? length1 : length0;
                    output_header<=read_bank ? header1 : header0;
                    if (read_bank) state1<=READING; else state0<=READING;
                end
                if (issue_read) begin
                    output_valid<=1;
                    output_last<=(output_remaining<=4);
                    case (output_remaining)
                        1: output_keep<=4'b0001;
                        2: output_keep<=4'b0011;
                        3: output_keep<=4'b0111;
                        default: output_keep<=4'b1111;
                    endcase
                    read_position<=read_position+4;
                    if (output_remaining<=4) reading<=0;
                end
                case (rx_state)
                    WAIT_HEADER: if (input_valid) begin
                        packet_header<=input_data[23:0];
                        if (!ecc_ok) begin header_bad<=1; packet_done<=1; rx_state<=DRAIN; end
                        else if (!vc_ok || !(is_short || is_long)) begin
                            filter_bad<=1; packet_done<=1; rx_state<=DRAIN;
                        end else if (is_short) begin
                            short_valid<=1; short_header<=input_data[23:0];
                            packet_done<=1; rx_state<=DRAIN;
                        end else if (input_data[23:8]>MAX_BYTES || !bank_free) begin
                            overflow<=1; packet_done<=1; rx_state<=DRAIN;
                        end else begin
                            rx_length<=input_data[23:8]; rx_position<=0;
                            crc<=16'hffff; footer_low<=0; idle_cycles<=0;
                            if (write_bank) begin
                                state1<=WRITING; header1<=input_data[23:0]; length1<=input_data[23:8];
                            end else begin
                                state0<=WRITING; header0<=input_data[23:0]; length0<=input_data[23:8];
                            end
                            rx_state<=RECEIVE;
                        end
                    end
                    RECEIVE: if (input_valid) begin
                        idle_cycles<=0; crc<=crc_next; footer_low<=footer_low_next;
                        rx_position<=rx_position+4;
                        if (footer_complete) begin
                            packet_done<=1; rx_state<=DRAIN;
                            if (footer_matches) begin
                                packet_good<=1;
                                if (rx_length!=0) begin
                                    if (write_bank) state1<=READY; else state0<=READY;
                                    write_bank<=!write_bank;
                                end else begin
                                    if (write_bank) state1<=FREE; else state0<=FREE;
                                end
                            end else begin
                                crc_bad<=1;
                                if (write_bank) state1<=FREE; else state0<=FREE;
                            end
                        end
                    end else if (idle_cycles==IDLE_TIMEOUT-1) begin
                        truncated<=1; packet_done<=1; rx_state<=DRAIN;
                        if (write_bank) state1<=FREE; else state0<=FREE;
                    end else idle_cycles<=idle_cycles+1;
                    DRAIN: if (!input_valid) rx_state<=WAIT_HEADER;
                    default: rx_state<=WAIT_HEADER;
                endcase
            end
        end
    end
endmodule
