// =============================================================================
// sync_fifo_130.v ¡ª Synchronous FWFT FIFO (single clock domain)
// =============================================================================
// Width: 130 bits (128-bit data + tuser + tlast)
// Depth: 2^ADDR_WIDTH entries, inferred as BRAM
// First-Word Fall-Through: rd_data shows head of queue immediately.
// AXI-Stream compatible: tvalid = !empty, rd_en = handshake (tvalid && tready).
// =============================================================================
`timescale 1ns / 1ps

module sync_fifo_130 #(
    parameter ADDR_WIDTH = 9   // depth = 2^ADDR_WIDTH = 512
)(
    input  wire          clk,
    input  wire          rst_n,

    // Write side (from demosaic)
    input  wire [129:0]  wr_data,
    input  wire          wr_en,      // assert when data valid && !full
    output wire          full,

    // Read side (to serializer)
    output wire [129:0]  rd_data,    // head of queue (combinational)
    input  wire          rd_en,      // assert to consume current head
    output wire          empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Dual-port inference: write port + read port
    reg [129:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH:0] wr_ptr;   // extra MSB for full/empty detection
    reg [ADDR_WIDTH:0] rd_ptr;

    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    // Combinational read (FWFT) ¡ª shows data at current rd_ptr
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // Write pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= 0;
        else if (wr_en && !full)
            wr_ptr <= wr_ptr + 1'b1;
    end

    // Write data
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Read pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= 0;
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1'b1;
    end

endmodule
