`timescale 1ns/1ps
module tb_histogram_lane1065;
    reg clk=0;
    always #4 clk=~clk;
    reg reset_n=0, collect_valid=0, collect_bank=0;
    reg clear_valid=0, clear_bank=0, scan_valid=0, scan_bank=0;
    reg [7:0] clear_bin=0, scan_bin=0;
    reg [7:0] gray[0:3];
    wire [19:0] counts[0:3];
    integer reference_counts[0:2047];
    integer checks=0, pixels=0, i,j,epoch,cycle,idx;
    reg [31:0] random_state=32'h1b73a254;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin: lanes
        histogram_lane1065 dut(clk,reset_n,collect_valid,collect_bank,
            gray[lane],clear_valid,clear_bank,clear_bin,
            scan_valid,scan_bank,scan_bin,counts[lane]);
    end endgenerate
    task tick;
        integer p, address;
        integer expected[0:3];
        begin
            for(p=0;p<4;p=p+1) begin
                address=p*512+scan_bank*256+scan_bin;
                expected[p]=reference_counts[address];
            end
            @(posedge clk); #1;
            for(p=0;p<4;p=p+1) begin
                if(scan_valid) begin
                    if(counts[p] !== expected[p]) begin
                        $display("FAIL lane=%0d bank=%0d bin=%0d actual=%0d expected=%0d",
                            p,scan_bank,scan_bin,counts[p],expected[p]);
                        $fatal(1);
                    end
                    checks=checks+1;
                end
                if(collect_valid) begin
                    address=p*512+collect_bank*256+gray[p];
                    reference_counts[address]=reference_counts[address]+1;
                    pixels=pixels+1;
                end
                if(clear_valid)
                    reference_counts[p*512+clear_bank*256+clear_bin]=0;
            end
            @(negedge clk);
        end
    endtask
    initial begin
        for(i=0;i<2048;i=i+1) reference_counts[i]=0;
        for(i=0;i<4;i=i+1) gray[i]=0;
        repeat(3) @(negedge clk);
        reset_n=1;
        clear_valid=1;
        for(j=0;j<2;j=j+1) begin
            clear_bank=j;
            for(i=0;i<256;i=i+1) begin clear_bin=i; tick; end
        end
        clear_valid=0;
        for(epoch=0;epoch<12;epoch=epoch+1) begin
            collect_bank=epoch%2;
            for(cycle=0;cycle<4096;cycle=cycle+1) begin
                random_state=random_state^(random_state<<13);
                random_state=random_state^(random_state>>17);
                random_state=random_state^(random_state<<5);
                collect_valid=(cycle<2048 || random_state[3:0]!=0);
                // All four lanes hit one bin; consecutive equal-bin writes;
                // alternating bins; then random values, with input bubbles.
                for(j=0;j<4;j=j+1)
                    if(cycle<1024) gray[j]=epoch;
                    else if(cycle<2048) gray[j]=cycle%2;
                    else gray[j]=(random_state>>(j*8));
                scan_bank=!collect_bank;
                scan_valid=(cycle>=4 && cycle<260);
                scan_bin=cycle-4;
                clear_valid=scan_valid;
                clear_bank=scan_bank;
                clear_bin=scan_bin;
                tick;
            end
            collect_valid=0; scan_valid=0; clear_valid=0;
            repeat(3) tick;
        end
        // Validate every final bin after pipeline drain.
        scan_valid=1;
        for(j=0;j<2;j=j+1) begin
            scan_bank=j;
            for(i=0;i<256;i=i+1) begin scan_bin=i; tick; end
        end
        scan_valid=0;
        // Asynchronous reset discards an outstanding uncommitted update;
        // the owner's startup clear restores deterministic state.
        reset_n=0; tick; reset_n=1;
        clear_valid=1;
        for(j=0;j<2;j=j+1) begin
            clear_bank=j;
            for(i=0;i<256;i=i+1) begin clear_bin=i; tick; end
        end
        clear_valid=0; scan_valid=1;
        for(j=0;j<2;j=j+1) begin
            scan_bank=j;
            for(i=0;i<256;i=i+1) begin scan_bin=i; tick; end
        end
        $display("PASS histogram_lane1065 pixels=%0d checked_bins=%0d",pixels,checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
