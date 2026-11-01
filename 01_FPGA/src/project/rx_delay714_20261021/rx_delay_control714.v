module rx_delay_control714 #(
    parameter SETTLE_CYCLES = 256,
    parameter MEASURE_CYCLES = 32768,
    parameter MIN_GOOD_HEADERS = 4,
    parameter MIN_EYE_TAPS = 3
)(
    input wire clock,
    input wire reset_n,
    input wire [5:0] config_async,
    input wire header_good,
    input wire header_bad,
    output reg [5:0] delay_value,
    output reg delay_load,
    output reg done,
    output reg success,
    output reg manual_active,
    output reg [5:0] best_length
);
    localparam BOOT = 0, SETTLE = 1, MEASURE = 2, SCORE = 3, APPLY = 4, HOLD = 5;
    (* async_reg = "true", dont_touch = "true" *) reg [5:0] config_meta;
    (* async_reg = "true", dont_touch = "true" *) reg [5:0] config_sync;
    reg [2:0] state;
    reg [15:0] timer;
    reg [15:0] good_count;
    reg [15:0] bad_count;
    reg [4:0] scan_tap;
    reg [4:0] run_start;
    reg [5:0] run_length;
    reg [4:0] best_start;
    wire passing = good_count >= MIN_GOOD_HEADERS && bad_count <= good_count;
    wire [5:0] extended_run = run_length + 1'b1;

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            config_meta <= 0;
            config_sync <= 0;
        end else begin
            config_meta <= config_async;
            config_sync <= config_meta;
        end
    end

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state <= BOOT;
            timer <= 0;
            good_count <= 0;
            bad_count <= 0;
            scan_tap <= 0;
            run_start <= 0;
            run_length <= 0;
            best_start <= 0;
            best_length <= 0;
            delay_value <= 0;
            delay_load <= 0;
            done <= 0;
            success <= 0;
            manual_active <= 0;
        end else begin
            delay_load <= 0;
            case (state)
                BOOT: begin
                    if (timer == 3) begin
                        timer <= 0;
                        manual_active <= config_sync[5];
                        delay_value <= {1'b0, config_sync[5] ? config_sync[4:0] : 5'd0};
                        delay_load <= 1;
                        state <= SETTLE;
                    end else timer <= timer + 1'b1;
                end
                SETTLE: begin
                    if (timer == SETTLE_CYCLES - 1) begin
                        timer <= 0;
                        good_count <= 0;
                        bad_count <= 0;
                        if (manual_active) begin
                            done <= 1;
                            state <= HOLD;
                        end else state <= MEASURE;
                    end else timer <= timer + 1'b1;
                end
                MEASURE: begin
                    if (header_good && good_count != 16'hffff) good_count <= good_count + 1'b1;
                    if (header_bad && bad_count != 16'hffff) bad_count <= bad_count + 1'b1;
                    if (timer == MEASURE_CYCLES - 1) begin
                        timer <= 0;
                        state <= SCORE;
                    end else timer <= timer + 1'b1;
                end
                SCORE: begin
                    if (passing) begin
                        if (run_length == 0) run_start <= scan_tap;
                        run_length <= extended_run;
                        if (extended_run > best_length) begin
                            best_start <= run_length == 0 ? scan_tap : run_start;
                            best_length <= extended_run;
                        end
                    end else run_length <= 0;
                    if (scan_tap == 31) state <= APPLY;
                    else begin
                        scan_tap <= scan_tap + 1'b1;
                        delay_value <= {1'b0, scan_tap + 5'd1};
                        delay_load <= 1;
                        state <= SETTLE;
                    end
                end
                APPLY: begin
                    success <= best_length >= MIN_EYE_TAPS;
                    delay_value <= best_length >= MIN_EYE_TAPS ?
                                   {1'b0, best_start} + {1'b0, best_length[5:1]} : 6'd16;
                    delay_load <= 1;
                    done <= 1;
                    state <= HOLD;
                end
                HOLD: state <= HOLD;
                default: state <= BOOT;
            endcase
        end
    end
endmodule
