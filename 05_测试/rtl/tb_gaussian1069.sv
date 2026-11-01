`timescale 1ns/1ps
module tb_gaussian1069;
    reg clk=0; always #4 clk=~clk;
    reg reset_n=0;
    reg [31:0] input_gray=0;
    reg input_valid=0,input_user=0,input_last=0,output_ready=1;
    wire input_ready,output_valid,output_user,output_last;
    wire [95:0] output_data;
    reg [95:0] grays[0:3071],expected[0:3071];
    reg [1:0] flags[0:3071];
    integer i,lane,received=0,gap;
    reg [31:0] random_state=32'h3872b5a1;
    reg random_stalls=0,held=0;
    reg [97:0] held_data;
    gaussian_gray1069 #(.WIDTH(64),.HEIGHT(24)) dut(.*);
    always @(negedge clk) begin
        random_state=random_state^(random_state<<13);
        random_state=random_state^(random_state>>17);
        random_state=random_state^(random_state<<5);
        output_ready=!random_stalls || random_state[2:0]!=0;
    end
    always @(posedge clk) if(reset_n) begin
        if(held && {output_data,output_user,output_last} !== held_data)
            $fatal(1,"stalled output changed");
        held=output_valid && !output_ready;
        held_data={output_data,output_user,output_last};
        if(output_valid && output_ready) begin
            if(received>=3072) $fatal(1,"extra output");
            if(output_data !== expected[received] || {output_user,output_last} !== flags[received]) begin
                $display("FAIL beat=%0d actual=%h expected=%h flags=%b expected=%b",
                    received,output_data,expected[received],{output_user,output_last},flags[received]);
                $fatal(1);
            end
            received=received+1;
        end
    end
    initial begin
        $readmemh("gray.hex",grays); $readmemh("gaussian.hex",expected);
        $readmemh("flags.hex",flags);
        repeat(3) @(negedge clk); reset_n=1;
        @(negedge clk);
        for(i=0;i<3072;i=i+1) begin
            if(i>=1536) random_stalls=1;
            if(random_stalls) begin
                input_valid=0; gap=random_state%3;
                repeat(gap) @(negedge clk);
            end
            for(lane=0;lane<4;lane=lane+1) input_gray[lane*8+:8]=grays[i][lane*24+:8];
            input_valid=1; {input_user,input_last}=flags[i];
            @(posedge clk); while(!input_ready) @(posedge clk);
            @(negedge clk);
        end
        input_valid=0;
        wait(received==3072);
        repeat(20) @(negedge clk);
        $display("PASS gaussian1069 pixels=%0d centered kernel, all clamp borders, consecutive frames and stalls",received*4);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
