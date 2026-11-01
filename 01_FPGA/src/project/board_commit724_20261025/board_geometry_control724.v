// New BAR region 0x100..0x17c; old 0x40..0xfc decoding stays separate.
module board_geometry_control724 (
    input wire clk,reset_n,idle,
    input wire write_enable,
    input wire [6:0] write_address,read_address,
    input wire [31:0] write_data,
    input wire [3:0] write_strobe,
    output reg [15:0] beats_per_line,lines_per_frame,
    output wire configured,
    input wire [31:0] observation_data,owner_data,
    output wire [3:0] observation_index,owner_index,
    output reg [31:0] read_data
);
    assign configured=beats_per_line!=0 && lines_per_frame!=0;
    assign observation_index=read_address[5:2];
    assign owner_index=read_address[5:2];
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin beats_per_line<=0;lines_per_frame<=0;end
        else if(write_enable && idle) begin
            if(write_address==7'h04) begin
                if(write_strobe[0]) beats_per_line[7:0]<=write_data[7:0];
                if(write_strobe[1]) beats_per_line[15:8]<=write_data[15:8];
            end
            if(write_address==7'h08) begin
                if(write_strobe[0]) lines_per_frame[7:0]<=write_data[7:0];
                if(write_strobe[1]) lines_per_frame[15:8]<=write_data[15:8];
            end
        end
    end
    always @* begin
        read_data=0;
        if(read_address>=7'h40) read_data=observation_data;
        else if(read_address>=7'h10) read_data=owner_data;
        else case(read_address)
            7'h00:read_data=32'h47454f24;
            7'h04:read_data={16'd0,beats_per_line};
            7'h08:read_data={16'd0,lines_per_frame};
            7'h0c:read_data={30'd0,idle,configured};
            default:read_data=0;
        endcase
    end
endmodule
