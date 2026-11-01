// Stop only between complete source frames. Never cut an admitted raster.
// All signals belong to the receiver destination/user clock domain.
module camera_admission1018 (
    input wire clk,reset_n,stop_requested,
    input wire s_valid,output wire s_ready,
    input wire s_frame_start,s_frame_end,s_abort,
    output wire m_valid,input wire m_ready,
    output wire stopped
);
    reg in_frame;
    wire pass_frame=in_frame || !stop_requested;
    assign m_valid=s_valid && pass_frame;
    assign s_ready=pass_frame ? m_ready : 1'b1;
    assign stopped=stop_requested && !in_frame;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)in_frame<=0;
        else if(m_valid && m_ready)begin
            // A second FS before FE remains visible to geometry, which must
            // reject the incomplete frame rather than hide it during stop.
            if(s_frame_start)in_frame<=1;
            else if(s_frame_end || s_abort)in_frame<=0;
        end
    end
endmodule
