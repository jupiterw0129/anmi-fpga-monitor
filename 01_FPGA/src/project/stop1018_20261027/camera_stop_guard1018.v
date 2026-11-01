// A deliberate source disable is safe only after admission stopped AND the
// owner drained. Keep that proof across receiver reset caused by disable.
module camera_stop_guard1018 (
    input wire clk,reset_n,source_ok,source_event,
    input wire stop_requested,admission_stopped,busy,
    output wire forwarded_source_event,stop_ready
);
    reg armed;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)armed<=0;
        else if(!stop_requested || busy || (source_ok && !admission_stopped))armed<=0;
        else if(source_ok && admission_stopped)armed<=1;
    end
    assign stop_ready=armed && stop_requested && admission_stopped && !busy;
    assign forwarded_source_event=source_event && !(armed && stop_requested && !busy);
endmodule
