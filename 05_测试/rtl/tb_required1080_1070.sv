`timescale 1ns/1ps
module tb_required1080_1070;
    reg clk=0; always #4 clk=~clk;
    reg reset_n=0;
    reg [1:0] requested_mode=0;
    wire [1:0] active_mode;
    reg [95:0] input_data=0;
    reg input_valid=0,input_user=0,input_last=0,output_ready=1;
    wire input_ready,output_valid,output_user,output_last;
    wire [95:0] output_data;
    wire initialized,protocol_error;
    wire [31:0] completed_histograms;
    integer f,y,x,received=0,frame_out,pos,cycles=0,start_cycle;
    reg [7:0] expected;
    required_preprocess1070 dut(.*);
    always @(posedge clk) begin
        cycles=cycles+1;
        if(reset_n) begin
            if(protocol_error) $fatal(1,"protocol error");
            if(output_valid && output_ready) begin
                frame_out=received/518400; pos=received%518400;
                expected=frame_out==0 || frame_out==2 ? 17 : frame_out==1 ? 33 : 255;
                if(output_data !== {12{expected}} || output_user !== (pos==0) ||
                    output_last !== (pos%480==479))
                    $fatal(1,"pixel/marker mismatch beat=%0d data=%h",received,output_data);
                received=received+1;
            end
        end
    end
    initial begin
        repeat(3) @(negedge clk); reset_n=1;
        wait(initialized); @(negedge clk); start_cycle=cycles;
        for(f=0;f<4;f=f+1) begin
            requested_mode=f;
            input_data=f%2==1 ? {12{8'd33}} : {12{8'd17}};
            for(y=0;y<1080;y=y+1) for(x=0;x<480;x=x+1) begin
                input_valid=1;
                input_user=(y==0 && x==0); input_last=(x==479);
                @(posedge clk); while(!input_ready) @(posedge clk);
                @(negedge clk);
            end
        end
        input_valid=0; wait(received==2073600);
        wait(!dut.frame_busy);
        @(negedge clk);
        if(completed_histograms!=4) $fatal(1,"histograms=%0d",completed_histograms);
        if(cycles-start_cycle>2076500) $fatal(1,"throughput regression cycles=%0d",cycles-start_cycle);
        $display("PASS required1080_1070 frames=4 pixels=%0d cycles=%0d all modes, line/frame markers, interframe drain",received*4,cycles-start_cycle);
        $finish;
    end
    initial begin #30000000; $fatal(1,"timeout"); end
endmodule
