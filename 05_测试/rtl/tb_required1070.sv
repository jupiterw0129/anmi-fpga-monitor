`timescale 1ns/1ps
module tb_required1070;
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
    reg [95:0] inputs[0:3071],grays[0:3071],equals[0:3071],gaussian[0:3071];
    reg [1:0] flags[0:3071];
    integer i,received=0,mode,gap;
    reg [95:0] expected;
    reg [31:0] random_state=32'h8b53217a;
    reg stalls=0,held=0;
    reg [97:0] held_data;
    required_preprocess1070 #(.WIDTH(64),.HEIGHT(24)) dut(.*);
    always @(negedge clk) begin
        random_state=random_state^(random_state<<13);
        random_state=random_state^(random_state>>17);
        random_state=random_state^(random_state<<5);
        output_ready=!stalls || random_state[1:0]!=0;
    end
    always @(posedge clk) if(reset_n) begin
        if(protocol_error) $fatal(1,"protocol_error");
        if(held && {output_data,output_user,output_last} !== held_data)
            $fatal(1,"output changed under backpressure");
        held=output_valid && !output_ready;
        held_data={output_data,output_user,output_last};
        if(output_valid && output_ready) begin
            mode=(received/384)%4;
            case(mode)
                0: expected=inputs[received];
                1: expected=grays[received];
                2: expected=gaussian[received];
                3: expected=equals[received];
            endcase
            if(output_data !== expected || {output_user,output_last} !== flags[received]) begin
                $display("FAIL beat=%0d mode=%0d actual=%h expected=%h flags=%b expected=%b",
                    received,mode,output_data,expected,{output_user,output_last},flags[received]);
                $fatal(1);
            end
            received=received+1;
        end
    end
    initial begin
        $readmemh("input.hex",inputs); $readmemh("gray.hex",grays);
        $readmemh("equal.hex",equals); $readmemh("gaussian.hex",gaussian);
        $readmemh("flags.hex",flags);
        repeat(3) @(negedge clk); reset_n=1;
        wait(initialized); @(negedge clk);
        for(i=0;i<3072;i=i+1) begin
            if(i==2304 || i==2688) begin
                input_valid=0;
                repeat(300) @(negedge clk);
                stalls=1;
            end
            if(stalls) begin
                input_valid=0; gap=random_state%3;
                repeat(gap) @(negedge clk);
            end
            input_data=inputs[i]; {input_user,input_last}=flags[i];
            // Exercise mid-frame mode changes: only SOF may apply them.
            requested_mode=i%384==0 ? (i/384)%4 : random_state[1:0];
            input_valid=1;
            @(posedge clk); while(!input_ready) @(posedge clk);
            @(negedge clk);
        end
        input_valid=0; wait(received==3072);
        repeat(300) @(negedge clk);
        if(completed_histograms!=8) $fatal(1,"histograms=%0d",completed_histograms);
        $display("PASS required1070 pixels=%0d all four modes, frame-atomic control, parallel histograms=%0d",received*4,completed_histograms);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
