`include "pcie_brg_def.svh"

module pcie_brg_fifo #(
    parameter SYNC_CLOCK = 1,
    parameter MEM_TYPE = "dram",
    parameter WIDTH = 16,
    parameter DEPTH = 8,
    parameter AFULL = 4,
    parameter REG_OUT = 0,
    parameter RD_PFCH = 0
) (
    input  logic wclk,
    input  logic wrst,
    input  logic wr,
    input  logic [WIDTH-1:0] wdata,
    output logic full,
    output logic afull,
    output logic oflow,
    input  logic rclk,
    input  logic rrst,
    input  logic rd,
    output logic [WIDTH-1:0] rdata,
    output logic empty,// used only when RD_PFCH=0
    output logic vld,// used only when RD_PFCH=1
    output logic uflow
);

localparam PTR_WIDTH = $clog2(DEPTH);

logic [PTR_WIDTH-1:0] wptr;
logic [PTR_WIDTH-1:0] rptr;
logic [PTR_WIDTH:0] wptr_ext;
logic [PTR_WIDTH:0] rptr_ext;
logic [PTR_WIDTH:0] wptr_ext_nxt;
logic [PTR_WIDTH:0] rptr_ext_nxt;
logic [PTR_WIDTH:0] wptr_ext_sync;
logic [PTR_WIDTH:0] rptr_ext_sync;
logic [PTR_WIDTH:0] wcnt;
logic [PTR_WIDTH:0] wcnt_c;
logic [PTR_WIDTH:0] wcnt_r;
logic [PTR_WIDTH-1:0] rptr_nxt;
logic full_c;
logic full_r;
logic [PTR_WIDTH:0] wcnt_r1;
logic rd_r1;

assign wptr = wptr_ext[PTR_WIDTH-1:0];
assign rptr = rptr_ext[PTR_WIDTH-1:0];
assign wptr_ext_nxt = wptr_ext + wr;
assign rptr_ext_nxt = rptr_ext + rd;
assign wcnt = SYNC_CLOCK ? wcnt_r : wcnt_c;
assign wcnt_c = wptr_ext - rptr_ext_sync;
assign rptr_nxt = rptr_ext_nxt[PTR_WIDTH-1:0];
assign full = SYNC_CLOCK ? full_c : full_r;
assign full_c = wcnt[PTR_WIDTH];
assign oflow = wr & full;
assign uflow = rd & empty;

always_ff @(posedge wclk) begin
    if (SYNC_CLOCK)
        wcnt_r <= wcnt + wr - rd;
    else
        wcnt_r <= wptr_ext_nxt - rptr_ext_sync;
    if (wrst)
        wcnt_r <= 0;
end

always_ff @(posedge wclk) begin
    wptr_ext <= wptr_ext_nxt;
    if (wrst)
        wptr_ext <= 0;
end

always_ff @(posedge wclk) begin
    if (wrst)
        full_r <= 0;
    else
        full_r <= (wptr_ext_nxt[PTR_WIDTH] != rptr_ext_sync[PTR_WIDTH]) & (wptr_ext_nxt[PTR_WIDTH-1:0] == rptr_ext_sync[PTR_WIDTH-1:0]);
end

always_ff @(posedge wclk) begin
    afull <= wcnt >= (AFULL - 1);
end

always_ff @(posedge rclk) begin
    rptr_ext <= rptr_ext_nxt;
    if (rrst)
        rptr_ext <= 0;
end

always_ff @(posedge rclk) begin
    if (rrst)
        empty <= 1;
    else
        empty <= rptr_ext_nxt == wptr_ext_sync;
end

always_ff @(posedge rclk) begin
    wcnt_r1 <= wptr_ext_sync - rptr_ext;
    rd_r1 <= rd;
    if (rrst) begin
        rd_r1 <= 0;
    end
end

always_ff @(posedge rclk) begin
    if (rrst)
        vld <= 0;
    else if (SYNC_CLOCK) begin
        if (REG_OUT)
            vld <= ~((wcnt_r == 0) | ((wcnt_r == 1) & rd));
        else
            vld <= rptr_ext_nxt != wptr_ext;
    end else begin
        // vld <= ~(((wptr_ext_sync - rptr_ext) == 0) | (((wptr_ext_sync - rptr_ext) == 1) & rd));
        vld <= ~(((wcnt_r1 == 2) & rd_r1 & rd) | ((wcnt_r1 == 1) & (rd_r1 | rd)) | (wcnt_r1 == 0));
    end
end

generate
    if (SYNC_CLOCK) begin: ptr_no_cdc
        assign wptr_ext_sync = wptr_ext;
        assign rptr_ext_sync = rptr_ext;

    end else begin: ptr_cdc
        pcie_brg_cdc_gray #(
            .REG_OUT(1),
            .WIDTH(PTR_WIDTH+1)
        ) cdc_wptr(
            .src_clk(wclk),
            .src_in(wptr_ext),
            .dst_clk(rclk),
            .dst_out(wptr_ext_sync)
        );

        pcie_brg_cdc_gray #(
            .REG_OUT(1),
            .WIDTH(PTR_WIDTH+1)
        ) cdc_rptr(
            .src_clk(rclk),
            .src_in(rptr_ext),
            .dst_clk(wclk),
            .dst_out(rptr_ext_sync)
        );

    end
endgenerate

generate
    if (MEM_TYPE == "dram") begin: mem_dram
        logic [WIDTH-1:0] mem [DEPTH-1:0];/* fehdl force_ram=1, ram_style="dram" */
        always_ff @(posedge wclk) begin
            if (wr) begin
                mem[wptr] <= wdata;
            end
        end
        if (REG_OUT) begin: mem_dram_output_reg
            always_ff @(posedge rclk) begin
                if (RD_PFCH)
                    rdata <= mem[rptr_nxt];
                else begin
                    if (rd)
                        rdata <= mem[rptr];
                end
            end
        end else begin: mem_dram_output_no_reg
            assign rdata = mem[rptr];
        end
    end else begin: mem_eram
         logic [WIDTH-1:0] mem [DEPTH-1:0];
        always_ff @(posedge wclk) begin
            if (wr) begin
                mem[wptr] <= wdata;
            end
        end
        if (REG_OUT) begin: mem_eram_output_reg
            always_ff @(posedge rclk) begin
                if (RD_PFCH)
                    rdata <= mem[rptr_nxt];
                else begin
                    if (rd)
                        rdata <= mem[rptr];
                end
            end
        end else begin: mem_eram_output_no_reg
            assign rdata = mem[rptr];
        end
    end
endgenerate

endmodule
