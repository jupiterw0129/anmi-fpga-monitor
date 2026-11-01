// P4R2 mode is stable until its terminal packet has transferred.
// Camera/video reset is NOT a transport reset. Bit 1 explicitly clears a session.
module board_lossless_control725(
    input wire clk,reset_n,global_enable,jpeg_mode,
    input wire [1:0] camera_mode,
    input wire write_enable,input wire [7:0] write_address,
    input wire [31:0] write_data,input wire [3:0] write_strobe,
    input wire [8:0] read_address,output reg [31:0] read_data,
    input wire busy,input wire [31:0] admitted,skipped,completed,rejected,
    input wire [31:0] overflow_count,shape_count,epoch_count,
    input wire [31:0] wire_id,source_id,input wire [11:0] high_water,
    output reg mode,output reg session_clear,
    output reg [31:0] session_generation,denied_writes
);
    wire request=write_enable && write_address==8'hd4 && write_strobe[0];
    wire idle=!global_enable && !busy && !jpeg_mode && camera_mode==0;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin mode<=0;session_clear<=0;session_generation<=0;denied_writes<=0;end
        else begin
            session_clear<=0;
            if(request)begin
                if(idle && !session_clear)begin
                    mode<=write_data[0];
                    if(write_data[1])begin session_clear<=1;session_generation<=session_generation+1'b1;end
                end else denied_writes<=denied_writes+1'b1;
            end
        end
    end
    always @* case(read_address)
        9'h0d4:read_data={31'd0,mode};
        9'h0d8:read_data={28'd0,busy,1'b0,1'b0,mode};
        9'h0dc:read_data=admitted+skipped;
        9'h0e0:read_data=admitted;
        9'h0e4:read_data=completed;
        9'h0e8:read_data=skipped;
        9'h0ec:read_data=rejected;
        9'h0f0:read_data=overflow_count;
        9'h0f4:read_data=shape_count;
        9'h0f8:read_data={20'd0,high_water};
        9'h0fc:read_data=32'h32523450;
        9'h180:read_data=32'h4c4c5325;
        9'h184:read_data=32'h0000003f;
        9'h188:read_data=session_generation;
        9'h18c:read_data=denied_writes;
        9'h190:read_data=rejected;
        9'h194:read_data=epoch_count;
        9'h198:read_data=wire_id;
        9'h19c:read_data=source_id;
        default:read_data=0;
    endcase
endmodule
