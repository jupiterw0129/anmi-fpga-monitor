// Dedicated BAR ABI for required 1080p preprocessing; all signals are user_clk.
// One request may be outstanding. Ack names the first accepted RGB wire frame
// observed with the requested mode; COMMIT must still be checked by the host.
module live_preprocess1512 (
    input wire clk,reset_n,write_enable,
    input wire [15:0] write_address,read_address,
    input wire [31:0] write_data,input wire [3:0] write_strobe,
    output reg [31:0] read_data,
    input wire config_idle,live_allowed,
    input wire [1:0] baseline_mode,output wire [1:0] requested_mode,
    input wire frame_valid,input wire [31:0] frame_wire_id,
    input wire [1:0] frame_mode
);
    reg override_valid,pending,ack_valid;
    reg [1:0] live_mode,ack_mode;
    reg [31:0] request_sequence,ack_sequence,ack_frame,denied;
    assign requested_mode=override_valid ? live_mode : baseline_mode;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            override_valid<=0;pending<=0;ack_valid<=0;live_mode<=0;ack_mode<=0;
            request_sequence<=0;ack_sequence<=0;ack_frame<=0;denied<=0;
        end else begin
            if(pending && frame_valid && frame_mode==live_mode)begin
                pending<=0;ack_valid<=1;ack_mode<=frame_mode;
                ack_sequence<=request_sequence;ack_frame<=frame_wire_id;
            end
            // A stopped baseline write cancels any unacknowledged request.
            // Sequence counters persist until PCIe user reset, so stale acks
            // cannot accidentally acknowledge a new capture session.
            if(write_enable && write_address==16'h00cc && config_idle && write_strobe[0])begin
                override_valid<=0;pending<=0;ack_valid<=0;
            end
            if(write_enable && write_address==16'h0200)begin
                if(!live_allowed || pending || write_strobe!=4'hf || write_data>3)
                    denied<=denied+1'b1;
                else begin
                    override_valid<=1;live_mode<=write_data[1:0];pending<=1;ack_valid<=0;
                    request_sequence<=request_sequence+1'b1;
                end
            end
        end
    end
    always @*begin
        read_data=0;
        case(read_address)
            16'h0200:read_data={30'd0,requested_mode};
            16'h0204:read_data=32'h3150504c; // LPP1; check exact marker before writing.
            16'h0208:read_data={27'd0,live_allowed,override_valid,ack_valid,pending,1'b0};
            16'h020c:read_data=request_sequence;
            16'h0210:read_data=ack_sequence;
            16'h0214:read_data=ack_frame;
            16'h0218:read_data={30'd0,ack_mode};
            16'h021c:read_data=denied;
        endcase
    end
endmodule
