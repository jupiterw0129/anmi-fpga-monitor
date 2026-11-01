// Observe CRC-accepted RAW events before configured geometry can reject them.
// Only FS -> whole RAW rows -> FE, without abort, yields a measurement.
// Measurements never automatically become acceptance configuration.
module raw_raster_observer724 (
    input wire clk,reset_n,
    input wire transfer,is_start,is_end,is_abort,is_eol,
    input wire [3:0] index,
    output reg [31:0] read_data
);
    reg active,overflowed;
    reg [15:0] rows,column,minimum,maximum;
    reg [31:0] total;
    reg [31:0] complete_count,abort_count,missing_end_count;
    reg [31:0] last_rows,last_range,last_total,stable_count;
    reg last_valid;
    wire pixel=transfer && !is_start && !is_end && !is_abort;
    wire complete=active && !overflowed && rows!=0 && column==0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            active<=0;overflowed<=0;rows<=0;column<=0;minimum<=16'hffff;maximum<=0;total<=0;
            complete_count<=0;abort_count<=0;missing_end_count<=0;
            last_rows<=0;last_range<=0;last_total<=0;stable_count<=0;last_valid<=0;
        end else if(transfer) begin
            if(is_start) begin
                if(active) begin missing_end_count<=missing_end_count+1'b1;stable_count<=0;last_valid<=0;end
                active<=1;overflowed<=0;rows<=0;column<=0;minimum<=16'hffff;maximum<=0;total<=0;
            end else if(is_abort) begin
                if(active) abort_count<=abort_count+1'b1;
                active<=0;stable_count<=0;last_valid<=0;
            end else if(is_end) begin
                if(complete) begin
                    complete_count<=complete_count+1'b1;
                    last_rows<={16'd0,rows};last_range<={maximum,minimum};last_total<=total;last_valid<=1;
                    if(last_valid && last_rows=={16'd0,rows} && last_range=={maximum,minimum} &&
                       minimum==maximum && last_total==total)
                        stable_count<=stable_count==32'hffffffff ? stable_count : stable_count+1'b1;
                    else stable_count<=minimum==maximum ? 32'd1 : 32'd0;
                end else begin
                    stable_count<=0;last_valid<=0;
                    if(active) abort_count<=abort_count+1'b1;
                end
                active<=0;
            end else if(pixel && active) begin
                if(column==16'hffff || total==32'hffffffff) overflowed<=1;
                total<=total+1'b1;
                if(is_eol) begin
                    if(rows==16'hffff) overflowed<=1;
                    rows<=rows+1'b1;column<=0;
                    if(column+1'b1<minimum) minimum<=column+1'b1;
                    if(column+1'b1>maximum) maximum<=column+1'b1;
                end else column<=column+1'b1;
            end
        end
    end
    always @* case(index)
        0:read_data=32'h52415724;
        1:read_data=complete_count;
        2:read_data=last_rows;
        3:read_data=last_range;
        4:read_data=last_total;
        5:read_data=stable_count;
        6:read_data=abort_count;
        7:read_data=missing_end_count;
        8:read_data={29'd0,overflowed,active,last_valid};
        default:read_data=0;
    endcase
endmodule
