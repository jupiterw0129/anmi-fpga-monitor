// One of four independent pixel-lane histograms. Two banks permit collection
// of frame N+1 while the CDF engine reads and clears frame N. Read-first RAM;
// explicit forwarding handles consecutive identical gray levels.
module histogram_lane1065 #(
    parameter COUNT_BITS = 20
) (
    input wire clk, reset_n,
    input wire collect_valid, collect_bank,
    input wire [7:0] collect_gray,
    input wire clear_valid, clear_bank,
    input wire [7:0] clear_bin,
    input wire scan_valid, scan_bank,
    input wire [7:0] scan_bin,
    output wire [COUNT_BITS-1:0] scan_count
);
    (* ram_style = "dram" *) reg [COUNT_BITS-1:0] bank0 [0:255];
    (* ram_style = "dram" *) reg [COUNT_BITS-1:0] bank1 [0:255];
    reg pending, pending_bank;
    reg [7:0] pending_bin;
    reg [COUNT_BITS-1:0] read0, read1;
    reg last_scan_bank;
    wire [COUNT_BITS-1:0] read_count=pending_bank ? read1 : read0;
    assign scan_count=last_scan_bank ? read1 : read0;
    reg written, written_bank;
    reg [7:0] written_bin;
    reg [COUNT_BITS-1:0] written_count;
    wire [COUNT_BITS-1:0] next_count =
        ((written && written_bank == pending_bank && written_bin == pending_bin)
            ? written_count : read_count) + 1'b1;

    // RAMs deliberately have no reset; owner clears all bins before admitting
    // pixels. Collection and scan/clear must address different banks.
    // Expose exactly one synchronous read and one write port per bank.
    // Two separate conditional reads of each array infer multiport flops in
    // TD even though collection and scanning never select the same bank.
    wire read_enable0=(collect_valid && !collect_bank) || (scan_valid && !scan_bank);
    wire read_enable1=(collect_valid && collect_bank) || (scan_valid && scan_bank);
    wire [7:0] address0=(scan_valid && !scan_bank) ? scan_bin : collect_gray;
    wire [7:0] address1=(scan_valid && scan_bank) ? scan_bin : collect_gray;
    wire clear0=clear_valid && !clear_bank;
    wire clear1=clear_valid && clear_bank;
    wire write0=clear0 || (reset_n && pending && !pending_bank);
    wire write1=clear1 || (reset_n && pending && pending_bank);
    wire [7:0] write_address0=clear0 ? clear_bin : pending_bin;
    wire [7:0] write_address1=clear1 ? clear_bin : pending_bin;
    always @(posedge clk) begin
        if(read_enable0) read0<=bank0[address0];
        if(write0) bank0[write_address0]<=clear0 ? {COUNT_BITS{1'b0}} : next_count;
        if(read_enable1) read1<=bank1[address1];
        if(write1) bank1[write_address1]<=clear1 ? {COUNT_BITS{1'b0}} : next_count;
        if(scan_valid) last_scan_bank<=scan_bank;
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending <= 0;
            pending_bank <= 0;
            pending_bin <= 0;
            written <= 0;
            written_bank <= 0;
            written_bin <= 0;
            written_count <= 0;
        end else begin
            pending <= collect_valid;
            if (collect_valid) begin
                pending_bank <= collect_bank;
                pending_bin <= collect_gray;
            end
            written <= pending;
            if (pending) begin
                written_bank <= pending_bank;
                written_bin <= pending_bin;
                written_count <= next_count;
            end
        end
    end
endmodule
