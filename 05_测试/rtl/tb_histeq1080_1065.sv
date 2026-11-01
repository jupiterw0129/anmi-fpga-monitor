`timescale 1ns/1ps
module tb_histeq1080_1065;
    reg clk=0; always #4 clk=~clk;
    reg reset_n=0;
    reg [95:0] input_data=0;
    reg input_valid=0,input_user=0,input_last=0,output_ready=1;
    wire input_ready,output_valid,output_user,output_last;
    wire [95:0] gray_data,equal_data,rgb_data;
    wire initialized,mapping_valid,protocol_error;
    wire [31:0] completed_histograms;
    integer f,y,x,received=0,frame_out,pos;
    reg [7:0] expected_gray,expected_equal;
    gray_histeq1065 dut(.*);
    always @(posedge clk) if(reset_n) begin
        if(protocol_error) $fatal(1,"protocol error");
        if(output_valid && output_ready) begin
            frame_out=received/518400;
            pos=received%518400;
            expected_gray=frame_out==1 ? 33 : 17;
            expected_equal=frame_out==0 ? 17 : frame_out==1 ? 255 : 0;
            if(gray_data !== {12{expected_gray}} || equal_data !== {12{expected_equal}} ||
                output_user !== (pos==0) || output_last !== (pos%480==479))
                $fatal(1,"pixel/marker mismatch beat=%0d gray=%h equal=%h",received,gray_data,equal_data);
            received=received+1;
        end
    end
    initial begin
        repeat(3) @(negedge clk);
        reset_n=1; wait(initialized); @(negedge clk);
        for(f=0;f<3;f=f+1) begin
            input_data=f==1 ? {12{8'd33}} : {12{8'd17}};
            for(y=0;y<1080;y=y+1) for(x=0;x<480;x=x+1) begin
                input_valid=1;
                input_user=(y==0 && x==0); input_last=(x==479);
                @(posedge clk);
                if(!input_ready) $fatal(1,"sustained stream stalled");
                @(negedge clk);
            end
            input_valid=0;
            repeat(300) @(negedge clk);
        end
        if(received!=1555200 || completed_histograms!=3)
            $fatal(1,"count mismatch outputs=%0d histograms=%0d",received,completed_histograms);
        $display("PASS hist1080 pixels=%0d beats=%0d histograms=%0d, 4 pixels each clock without stalls",
            received*4,received,completed_histograms);
        $finish;
    end
    initial begin #20000000; $fatal(1,"timeout"); end
endmodule
