// Exact centered separable 3x3 Gaussian on luminance, kernel [1 2 1]^T
// [1 2 1]/16, floor once after vertical sum. Clamp all four image borders.
// Four pixels per beat. Two synchronous 40-bit line RAMs. End-of-frame
// replicated-row drain takes WIDTH/4 cycles; input_ready advertises it.
module gaussian_gray1069 #(
    parameter WIDTH=1920, HEIGHT=1080
)(
    input wire clk,reset_n,
    input wire [31:0] input_gray,
    input wire input_valid,input_user,input_last,
    output wire input_ready,
    output reg [95:0] output_data,
    output reg output_valid,
    input wire output_ready,
    output reg output_user,output_last
);
    localparam WORDS=WIDTH/4;
    localparam AB=$clog2(WORDS);
    reg live;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) live<=0; else live<=1;
    // 下游背压时保持输出及窗口状态；不得只停像素而继续推进标记。
    wire advance=!output_valid || output_ready;
    reg pending_valid,pending_last,pending_user;
    reg [31:0] pending_gray;
    reg [7:0] pending_left;
    reg [AB-1:0] pending_col,input_col;
    reg [15:0] pending_row,input_row;
    reg [7:0] prior_pixel;
    reg frame_draining;
    assign input_ready=live && advance && !frame_draining;
    wire take=input_valid && input_ready;
    wire emit_horizontal=pending_valid && (pending_last || take);
    wire [7:0] right_pixel=pending_last ? pending_gray[31:24] : input_gray[7:0];
    wire [47:0] pixels={right_pixel,pending_gray,pending_left};
    wire [39:0] horizontal;
    genvar p;
    generate for(p=0;p<4;p=p+1) begin: horizontal_lanes
        assign horizontal[p*10+:10]={2'd0,pixels[p*8+:8]}+
            {1'd0,pixels[(p+1)*8+:8],1'b0}+{2'd0,pixels[(p+2)*8+:8]};
    end endgenerate

    // 横向加权结果保留10位，两行缓存供纵向累加，最后统一取整。
    reg [39:0] previous_row[0:WORDS-1], second_row[0:WORDS-1];
    reg flush_active;
    reg [AB-1:0] flush_col;
    wire memory_emit=flush_active || emit_horizontal;
    wire [AB-1:0] memory_col=flush_active ? flush_col : pending_col;
    reg stage_valid,stage_last,stage_user,stage_flush,stage_first;
    reg [39:0] top,middle,bottom;
    always @(posedge clk) begin
        if(live && advance && memory_emit) begin
            top<=second_row[memory_col];
            middle<=previous_row[memory_col];
            if(!flush_active) begin
                second_row[memory_col]<=previous_row[memory_col];
                previous_row[memory_col]<=horizontal;
            end
        end
    end
    integer lane;
    reg [11:0] total;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            pending_valid<=0; pending_last<=0; pending_user<=0;
            pending_gray<=0; pending_left<=0; pending_col<=0; input_col<=0;
            pending_row<=0; input_row<=0; prior_pixel<=0;
            frame_draining<=0; flush_active<=0; flush_col<=0;
            stage_valid<=0; stage_last<=0; stage_user<=0;
            stage_flush<=0; stage_first<=0; bottom<=0;
            output_valid<=0; output_last<=0; output_user<=0; output_data<=0;
        end else if(advance) begin
            output_valid<=stage_valid;
            if(stage_valid) begin
                output_last<=stage_last;
                output_user<=stage_user;
                for(lane=0;lane<4;lane=lane+1) begin
                    total={2'd0,(stage_first ? middle[lane*10+:10] : top[lane*10+:10])}+
                        {1'd0,middle[lane*10+:10],1'b0}+
                        {2'd0,(stage_flush ? middle[lane*10+:10] : bottom[lane*10+:10])};
                    output_data[lane*24+:24]<={3{total[11:4]}};
                end
            end
            stage_valid<=live && memory_emit && (flush_active || pending_row!=0);
            if(live && memory_emit) begin
                stage_last<=memory_col==WORDS-1;
                stage_user<=!flush_active && pending_row==1 && memory_col==0;
                stage_first<=!flush_active && pending_row==1;
                stage_flush<=flush_active;
                bottom<=horizontal;
            end
            if(emit_horizontal) begin
                pending_valid<=0;
                if(pending_row==HEIGHT-1 && pending_last) begin
                    flush_active<=1; flush_col<=0;
                end
            end
            if(take) begin
                pending_valid<=1;
                pending_gray<=input_gray;
                pending_user<=input_user;
                pending_last<=input_last;
                pending_left<=(input_user || input_col==0) ? input_gray[7:0] : prior_pixel;
                prior_pixel<=input_gray[31:24];
                pending_col<=input_user ? 0 : input_col;
                pending_row<=input_user ? 0 : input_row;
                if(input_last) begin
                    input_col<=0;
                    input_row<=input_user ? 1 : input_row+1'b1;
                    if(input_row==HEIGHT-1) frame_draining<=1;
                end else input_col<=input_user ? 1 : input_col+1'b1;
                if(input_user) input_row<=0;
            end
            if(flush_active) begin
                if(flush_col==WORDS-1) begin
                    flush_active<=0; frame_draining<=0;
                end else flush_col<=flush_col+1'b1;
            end
        end
    end
endmodule
