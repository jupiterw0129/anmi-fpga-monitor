// Four pixels/clock. Gray and equalized gray are parallel outputs of the
// same accepted RGB beat. Equalization uses CDF(k)*255/(WIDTH*HEIGHT), floor,
// from the most recently completed histogram, latched only at frame start.
// The first frame is identity. No full-frame image store is needed.
// Contract: WIDTH>=8 divisible by 4, HEIGHT>=2 complete lines, user on first beat,
// last on every line. Minimum frame length 280 accepted beats. Startup clears
// histogram RAM in 512 cycles. Processing never stalls for CDF generation.
module gray_histeq1065 #(
    parameter WIDTH=1920,
    parameter HEIGHT=1080,
    parameter COUNT_BITS=20
) (
    input wire clk, reset_n,
    input wire [95:0] input_data,
    input wire input_valid,
    output wire input_ready,
    input wire input_user, input_last,
    output reg [95:0] gray_data, equal_data,
    output reg [95:0] rgb_data,
    output reg output_valid,
    input wire output_ready,
    output reg output_user, output_last,
    output reg initialized,
    output reg mapping_valid,
    output reg protocol_error,
    output reg [31:0] completed_histograms
);
    localparam PIXELS=WIDTH*HEIGHT;
    reg [8:0] init_bin;
    // 双组直方图分离当前帧统计与上一帧CDF生成，映射在帧首生效。
    reg collect_bank;
    reg [15:0] row, word_column;
    reg in_frame;
    wire advance=!output_valid || output_ready;
    wire take=input_valid && input_ready;
    assign input_ready=initialized && advance;

    function [7:0] luma;
        input [23:0] rgb;
        reg [15:0] sum;
        begin
            sum=rgb[23:16]*16'd77+rgb[15:8]*16'd150+rgb[7:0]*16'd29;
            luma=sum[15:8];
        end
    endfunction
    wire [31:0] gray;
    genvar p;
    generate for(p=0;p<4;p=p+1) begin: gray_lanes
        assign gray[p*8+:8]=luma(input_data[p*24+:24]);
    end endgenerate

    // One-cycle drain before reading the just-finished histogram permits the
    // lane RAM's last pending update to commit.
    reg scan_busy, scan_bank, scan_pending;
    reg [1:0] drain;
    reg [8:0] scan_index;
    reg [7:0] pending_bin;
    wire scan_read=scan_busy && drain==0 && scan_index<256;
    wire lane_clear=!initialized || scan_read;
    wire lane_clear_bank=!initialized ? init_bin[8] : scan_bank;
    wire [7:0] lane_clear_bin=!initialized ? init_bin[7:0] : scan_index[7:0];
    wire [COUNT_BITS-1:0] lane_count[0:3];
    generate for(p=0;p<4;p=p+1) begin: hist_lanes
        histogram_lane1065 #(.COUNT_BITS(COUNT_BITS)) histogram(
            .clk(clk),.reset_n(reset_n),
            .collect_valid(take),.collect_bank(collect_bank),
            .collect_gray(gray[p*8+:8]),
            .clear_valid(reset_n && lane_clear),.clear_bank(lane_clear_bank),
            .clear_bin(lane_clear_bin),.scan_valid(scan_read),
            .scan_bank(scan_bank),.scan_bin(scan_index[7:0]),
            .scan_count(lane_count[p]));
    end endgenerate

    reg [7:0] lut0[0:255];
    reg [7:0] lut1[0:255];
    reg lut_active, lut_write, lut_ready, lut_ready_bank;
    reg [31:0] cumulative;
    reg count_valid,cdf_valid,scale_valid;
    reg [31:0] count_sum,cdf_value;
    reg [7:0] count_bin,cdf_bin,scale_bin;
    reg [39:0] scaled_cdf;
    wire [31:0] cumulative_next=cumulative+count_sum;
    // Eight restoring-division stages produce the exact 8-bit quotient;
    // each stage compares/subtracts a constant, no long inferred divider.
    reg [7:0] divide_valid;
    reg [39:0] remainder[0:7];
    reg [7:0] quotient[0:7], divide_bin[0:7];
    genvar d;
    generate for(d=0;d<8;d=d+1) begin: normalize
        localparam [39:0] THRESHOLD=40'd1*PIXELS*(1<<(7-d));
        wire [39:0] source_remainder;
        wire [7:0] source_quotient,source_bin;
        wire source_valid;
        if(d==0) begin: first
            assign source_remainder=scaled_cdf;
            assign source_quotient=0;
            assign source_bin=scale_bin;
            assign source_valid=scale_valid;
        end else begin: following
            assign source_remainder=remainder[d-1];
            assign source_quotient=quotient[d-1];
            assign source_bin=divide_bin[d-1];
            assign source_valid=divide_valid[d-1];
        end
        always @(posedge clk or negedge reset_n) begin
            if(!reset_n) begin
                divide_valid[d]<=0;
                remainder[d]<=0; quotient[d]<=0; divide_bin[d]<=0;
            end else begin
                divide_valid[d]<=source_valid;
                if(source_valid) begin
                    divide_bin[d]<=source_bin;
                    if(source_remainder>=THRESHOLD) begin
                        remainder[d]<=source_remainder-THRESHOLD;
                        quotient[d]<=source_quotient | (8'd1<<(7-d));
                    end else begin
                        remainder[d]<=source_remainder;
                        quotient[d]<=source_quotient;
                    end
                end
            end
        end
    end endgenerate
    wire mapping_complete=divide_valid[7] && divide_bin[7]==255;
    wire current_lut=(input_user && lut_ready) ? lut_ready_bank : lut_active;
    wire use_mapping=mapping_valid || (input_user && lut_ready);
    integer lane;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            initialized<=0; init_bin<=0; collect_bank<=0;
            row<=0; word_column<=0; in_frame<=0;
            scan_busy<=0; scan_bank<=0; scan_pending<=0;
            drain<=0; scan_index<=0; pending_bin<=0;
            lut_active<=0; lut_write<=1; lut_ready<=0; lut_ready_bank<=0;
            cumulative<=0; mapping_valid<=0; protocol_error<=0;
            count_valid<=0; cdf_valid<=0; scale_valid<=0;
            count_sum<=0; cdf_value<=0; scaled_cdf<=0;
            count_bin<=0; cdf_bin<=0; scale_bin<=0;
            completed_histograms<=0;
            output_valid<=0; output_user<=0; output_last<=0;
            gray_data<=0; equal_data<=0; rgb_data<=0;
        end else begin
            count_valid<=scan_pending;
            if(scan_pending) begin
                count_sum<=({12'd0,lane_count[0]}+{12'd0,lane_count[1]})+
                    ({12'd0,lane_count[2]}+{12'd0,lane_count[3]});
                count_bin<=pending_bin;
            end
            cdf_valid<=count_valid;
            if(count_valid) begin
                cumulative<=cumulative_next;
                cdf_value<=cumulative_next;
                cdf_bin<=count_bin;
                if(count_bin==255 && cumulative_next!=PIXELS) protocol_error<=1;
            end
            scale_valid<=cdf_valid;
            if(cdf_valid) begin
                scaled_cdf<=({8'd0,cdf_value}<<8)-cdf_value;
                scale_bin<=cdf_bin;
            end
            if(divide_valid[7]) begin
                if(lut_write) lut1[divide_bin[7]]<=quotient[7];
                else lut0[divide_bin[7]]<=quotient[7];
                if(mapping_complete) begin
                    scan_busy<=0; lut_ready<=1; lut_ready_bank<=lut_write;
                    completed_histograms<=completed_histograms+1'b1;
                end
            end
            if(!initialized) begin
                if(init_bin==511) initialized<=1;
                else init_bin<=init_bin+1'b1;
            end
            if(advance) begin
                output_valid<=take;
                if(take) begin
                    rgb_data<=input_data;
                    output_user<=input_user;
                    output_last<=input_last;
                    for(lane=0;lane<4;lane=lane+1) begin
                        gray_data[lane*24+:24]<={3{gray[lane*8+:8]}};
                        equal_data[lane*24+:24]<=!use_mapping ?
                            {3{gray[lane*8+:8]}} : current_lut ?
                            {3{lut1[gray[lane*8+:8]]}} :
                            {3{lut0[gray[lane*8+:8]]}};
                    end
                end
            end
            if(scan_busy) begin
                if(drain!=0) drain<=drain-1'b1;
                else begin
                    scan_pending<=scan_read;
                    if(scan_read) begin
                        pending_bin<=scan_index[7:0];
                        scan_index<=scan_index+1'b1;
                    end
                end
            end else scan_pending<=0;
            if(take) begin
                if(input_user) begin
                    if(in_frame) protocol_error<=1;
                    row<=0;
                    word_column<=1;
                    in_frame<=1;
                    if(lut_ready) begin
                        lut_active<=lut_ready_bank;
                        lut_ready<=mapping_complete;
                        mapping_valid<=1;
                    end
                    if(input_last != (WIDTH==4)) protocol_error<=1;
                end else begin
                    if(!in_frame) protocol_error<=1;
                    if(input_last != (word_column==WIDTH/4-1)) protocol_error<=1;
                    word_column<=word_column+1'b1;
                end
                if(input_last) begin
                    word_column<=0;
                    row<=row+1'b1;
                    if(row==HEIGHT-1) begin
                        in_frame<=0;
                        collect_bank<=!collect_bank;
                        if(scan_busy) protocol_error<=1;
                        else begin
                            scan_busy<=1; scan_bank<=collect_bank;
                            scan_index<=0; drain<=2;
                            cumulative<=0;
                            // Active LUT is stable throughout a frame.
                            // An older result awaiting the immediately next
                            // SOF owns !lut_active; reserve the other LUT.
                            lut_write<=lut_ready ? !lut_ready_bank : !lut_active;
                        end
                    end
                end
            end
        end
    end
endmodule
