`timescale 1ns/1ps
module tb_gray_histeq1065;
    reg clk=0; always #4 clk=~clk;
    reg reset_n=0;
    reg [95:0] input_data=0;
    reg input_valid=0,input_user=0,input_last=0,output_ready=1;
    wire input_ready, output_valid,output_user,output_last;
    wire initialized,mapping_valid,protocol_error;
    wire [31:0] completed_histograms;
    wire [95:0] gray_data,equal_data,rgb_data;
    reg [95:0] inputs[0:3071],grays[0:3071],equals[0:3071];
    reg [1:0] flags[0:3071];
    integer sent=0,received=0,i,gap;
    reg random_stalls=0;
    reg [31:0] random_state=32'hf167259a;
    reg held=0;
    reg [193:0] held_payload;
    gray_histeq1065 #(.WIDTH(64),.HEIGHT(24)) dut(.*);
    always @(negedge clk) begin
        random_state=random_state^(random_state<<13);
        random_state=random_state^(random_state>>17);
        random_state=random_state^(random_state<<5);
        output_ready=!random_stalls || random_state[1:0]!=0;
    end
    always @(posedge clk) if(reset_n) begin
        if(held && {gray_data,equal_data,output_user,output_last} !== held_payload)
            $fatal(1,"output changed while stalled");
        held=output_valid && !output_ready;
        held_payload={gray_data,equal_data,output_user,output_last};
        if(output_valid && output_ready) begin
            if(received>=3072) $fatal(1,"extra output");
            if(gray_data !== grays[received] || equal_data !== equals[received] ||
                {output_user,output_last} !== flags[received]) begin
                $display("FAIL beat=%0d gray=%h expected=%h equal=%h expected=%h flags=%b expected=%b",
                    received,gray_data,grays[received],equal_data,equals[received],
                    {output_user,output_last},flags[received]);
                $fatal(1);
            end
            received=received+1;
        end
        if(protocol_error) $fatal(1,"protocol_error");
    end
    initial begin
        $readmemh("input.hex",inputs); $readmemh("gray.hex",grays);
        $readmemh("equal.hex",equals); $readmemh("flags.hex",flags);
        repeat(3) @(negedge clk);
        reset_n=1;
        wait(initialized); @(negedge clk);
        for(i=0;i<3072;i=i+1) begin
            if(i==2304 || i==2688) begin
                input_valid=0;
                repeat(300) @(negedge clk);
                random_stalls=1;
            end
            if(random_stalls) begin
                gap=random_state%3;
                input_valid=0;
                repeat(gap) @(negedge clk);
            end
            input_data=inputs[i]; input_valid=1;
            {input_user,input_last}=flags[i];
            @(posedge clk);
            while(!input_ready) @(posedge clk);
            sent=sent+1;
            @(negedge clk);
        end
        input_valid=0;
        wait(received==3072);
        repeat(300) @(negedge clk);
        if(completed_histograms!=8) $fatal(1,"histograms=%0d",completed_histograms);
        $display("PASS gray_histeq1065 beats=%0d pixels=%0d histograms=%0d",received,received*4,completed_histograms);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
