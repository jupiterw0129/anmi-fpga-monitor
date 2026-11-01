// Streaming JPG2 quality control. Q writes are sampled at accepted RGB SOF.
module board_jpg2_control774 (
    input wire clk,reset_n,
    input wire write_enable,input wire [15:0] write_address,
    input wire [31:0] write_data,input wire [3:0] write_strobe,
    input wire [15:0] read_address,output reg [31:0] read_data,
    input wire capture_enabled,input wire [1:0] camera_mode,
    input wire geometry_configured,lossless_mode,lossless_busy,jpeg_busy,
    input wire admission_stopped,stop_ready,output reg stop_requested,
    input wire [31:0] admitted,committed,aborted,faults,
    output reg jpeg_enabled,output reg [6:0] requested_quality,
    output wire config_idle,output reg reset_request
);
    reg [31:0] denied_writes;
    reg [3:0] denied_reason;
    wire transport_idle=!capture_enabled && !lossless_mode && !lossless_busy && !jpeg_busy;
    assign config_idle=transport_idle && !jpeg_enabled;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin requested_quality<=50;stop_requested<=0;jpeg_enabled<=0;reset_request<=0;denied_writes<=0;denied_reason<=0;end
        else begin
            reset_request<=0;
            if(write_enable && write_strobe[0])begin
                case(write_address)
                    16'h00a4:begin
                        if(!transport_idle)begin denied_writes<=denied_writes+1'b1;denied_reason<=1;end
                        else if(write_data[0] && (camera_mode!=0 || !geometry_configured))begin
                            denied_writes<=denied_writes+1'b1;denied_reason<=2;
                        end else if(jpeg_enabled!=write_data[0])begin
                            jpeg_enabled<=write_data[0];reset_request<=1;stop_requested<=0;
                        end
                    end
                    16'h01f4:begin
                        if(write_data[0])begin
                            if(!jpeg_enabled || lossless_mode)begin
                                denied_writes<=denied_writes+1'b1;denied_reason<=6;
                            end else stop_requested<=1;
                        end else if(capture_enabled || jpeg_busy)begin
                            denied_writes<=denied_writes+1'b1;denied_reason<=6;
                        end else stop_requested<=0;
                    end
                    16'h0090:begin
                        if(write_data[1:0]!=0)begin denied_writes<=denied_writes+1'b1;denied_reason<=4;end
                    end
                    16'h00d4:begin
                        if(write_data!=0)begin denied_writes<=denied_writes+1'b1;denied_reason<=4;end
                    end
                    16'h0060:begin
                        if(write_data[0] && (!jpeg_enabled || !geometry_configured))begin
                            denied_writes<=denied_writes+1'b1;denied_reason<=5;
                        end
                    end
                    16'h00c4:begin
                        // No codec reset on a valid Q change; in-flight frames retain their Q.
                        if(write_strobe!=4'hf || write_data<1 || write_data>100)begin denied_writes<=denied_writes+1'b1;denied_reason<=3;end
                        else requested_quality<=write_data[6:0];
                    end
                    default:begin end
                endcase
            end
        end
    end
    always @* begin
        read_data=0;
        case(read_address)
            16'h01c0:read_data=32'h3247504a; // Little-endian bytes JPG2.
            16'h01c4:read_data=32'h00010000; // BAR ABI version1.
            // bit4: runtime per-frame Q. No CBR capability is claimed.
            16'h01c8:read_data=32'h0000001f;
            16'h01cc:read_data={28'd0,config_idle,reset_request,jpeg_busy,jpeg_enabled};
            16'h01d0:read_data={25'd0,requested_quality};
            16'h01d4:read_data=admitted;
            16'h01d8:read_data=committed;
            16'h01dc:read_data=aborted;
            16'h01e0:read_data=faults;
            16'h01e4:read_data=denied_writes;
            16'h01e8:read_data={28'd0,denied_reason};
            // Profile restrictions are separate from the existing JPG2 ABI.
            16'h01ec:read_data=32'h00000001; // bit0: JPEG-only profile.
            16'h01f4:read_data={29'd0,stop_ready,admission_stopped,stop_requested};
            16'h01f0:read_data=32'h00000001; // supported camera modes: bit0 only.

            default:begin end
        endcase
    end
endmodule
