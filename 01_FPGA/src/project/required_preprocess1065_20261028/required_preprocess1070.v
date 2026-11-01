// Parallel branches run for every accepted beat, even when bypass is selected.
// Frame-atomic mode 0=RGB, 1=gray, 2=Gaussian(gray), 3=equalized gray.
// Both branches finish each frame before admitting the next frame. No image
// frame store or serial reuse of an arithmetic unit between algorithms.
module required_preprocess1070 #(
    parameter WIDTH=1920, HEIGHT=1080
)(
    input wire clk,reset_n,
    input wire [1:0] requested_mode,
    output reg [1:0] active_mode,
    input wire [95:0] input_data,
    input wire input_valid,input_user,input_last,
    output wire input_ready,
    output wire [95:0] output_data,
    output wire output_valid,
    input wire output_ready,
    output wire output_user,output_last,
    output wire initialized,protocol_error,
    output wire [31:0] completed_histograms
);
    reg frame_busy,input_finished,hist_finished,gauss_finished;
    reg [15:0] input_row,hist_row,gauss_row;
    wire hist_ready,gauss_ready;
    wire hist_valid,hist_user,hist_last,gauss_valid,gauss_user,gauss_last;
    wire [95:0] gray_data,equal_data,rgb_data,gauss_data;
    wire mapping_valid;
    wire take=input_valid && input_ready;
    wire allow_input=!input_finished;
    wire hist_take_ready=(active_mode==2) || output_ready;
    wire gauss_take_ready=(active_mode!=2) || output_ready;
    wire hist_end=hist_valid && hist_take_ready && hist_last && hist_row==HEIGHT-1;
    wire gauss_end=gauss_valid && gauss_take_ready && gauss_last && gauss_row==HEIGHT-1;
    wire [31:0] gray;
    function [7:0] luma;
        input [23:0] rgb;
        reg [15:0] sum;
        begin
            sum=rgb[23:16]*16'd77+rgb[15:8]*16'd150+rgb[7:0]*16'd29;
            luma=sum[15:8];
        end
    endfunction
    genvar p;
    generate for(p=0;p<4;p=p+1) begin: gray_lanes
        assign gray[p*8+:8]=luma(input_data[p*24+:24]);
    end endgenerate
    // 两分支同时接收同一拍，避免未选中的分支落后后破坏行帧对齐。
    assign input_ready=allow_input && hist_ready && gauss_ready;
    gray_histeq1065 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) histogram(
        .clk(clk),.reset_n(reset_n),.input_data(input_data),
        .input_valid(input_valid && allow_input && gauss_ready),
        .input_ready(hist_ready),.input_user(input_user),.input_last(input_last),
        .rgb_data(rgb_data),.gray_data(gray_data),.equal_data(equal_data),
        .output_valid(hist_valid),.output_ready(hist_take_ready),
        .output_user(hist_user),.output_last(hist_last),
        .initialized(initialized),.mapping_valid(mapping_valid),
        .protocol_error(protocol_error),.completed_histograms(completed_histograms));
    gaussian_gray1069 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) gaussian(
        .clk(clk),.reset_n(reset_n),.input_gray(gray),
        .input_valid(input_valid && allow_input && hist_ready),
        .input_ready(gauss_ready),.input_user(input_user),.input_last(input_last),
        .output_data(gauss_data),.output_valid(gauss_valid),
        .output_ready(gauss_take_ready),.output_user(gauss_user),.output_last(gauss_last));
    assign output_data=active_mode==0 ? rgb_data : active_mode==1 ? gray_data :
        active_mode==2 ? gauss_data : equal_data;
    assign output_valid=active_mode==2 ? gauss_valid : hist_valid;
    assign output_user=active_mode==2 ? gauss_user : hist_user;
    assign output_last=active_mode==2 ? gauss_last : hist_last;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            active_mode<=0; frame_busy<=0; input_finished<=0;
            hist_finished<=0; gauss_finished<=0;
            input_row<=0; hist_row<=0; gauss_row<=0;
        end else begin
            if(take) begin
                if(input_user) begin
                    // 只在帧首握手成功时锁存模式，帧内请求留到下一帧。
                    active_mode<=requested_mode; frame_busy<=1;
                    input_row<=0;
                end
                if(input_last) begin
                    input_row<=input_row+1'b1;
                    if(input_row==HEIGHT-1) input_finished<=1;
                end
            end
            if(hist_valid && hist_take_ready && hist_last) begin
                hist_row<=hist_row+1'b1;
                if(hist_end) hist_finished<=1;
            end
            if(gauss_valid && gauss_take_ready && gauss_last) begin
                gauss_row<=gauss_row+1'b1;
                if(gauss_end) gauss_finished<=1;
            end
            if(frame_busy && input_finished && (hist_finished || hist_end) &&
                (gauss_finished || gauss_end)) begin
                frame_busy<=0; input_finished<=0;
                hist_finished<=0; gauss_finished<=0;
                input_row<=0; hist_row<=0; gauss_row<=0;
            end
        end
    end
endmodule
