`timescale 1ns / 1ps
// ============================================================================
// axis_stream_fifo.v
// Synchronous AXI-Stream FIFO with configurable depth.
//
// Purpose: Absorb brief tready drops from SGDMA C2H engine (inter-transfer
//          gap, PCIe backpressure, descriptor boundary transitions) so that
//          upstream packer never sees a stall.
//
// Architecture: Simple pointer-based FIFO using inferred block RAM.
//   - Write when s_tvalid & s_tready (FIFO not full)
//   - Read  when m_tvalid & m_tready (FIFO not empty)
//   - First-Word Fall-Through (show-ahead): m_tdata/m_tlast reflect
//     the next entry without needing a read cycle first.
//
// Resource estimate (512-bit data + 1-bit tlast, 256 deep):
//   ~29 BRAM18 on Anlogic PH2A  (covers ~44?s SGDMA gap at 1080p)
// ============================================================================

module axis_stream_fifo #(
    parameter DATA_WIDTH = 512,
    parameter DEPTH      = 256,         // power of 2
    parameter ADDR_BITS  = 8            // log2(DEPTH)
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI-Stream slave (input)
    input  wire [DATA_WIDTH-1:0]   s_tdata,
    input  wire                    s_tvalid,
    output wire                    s_tready,
    input  wire                    s_tlast,

    // AXI-Stream master (output)
    output wire [DATA_WIDTH-1:0]   m_tdata,
    output wire                    m_tvalid,
    input  wire                    m_tready,
    output wire                    m_tlast,

    // Status (optional)
    output wire [ADDR_BITS:0]      fill_level
);

    // ----------------------------------------------------------------
    // Storage: data + tlast packed together
    // ----------------------------------------------------------------
    localparam MEM_WIDTH = DATA_WIDTH + 1;  // data + tlast

    reg [MEM_WIDTH-1:0] mem [0:DEPTH-1];

    // ----------------------------------------------------------------
    // Pointers (one extra bit for full/empty disambiguation)
    // ----------------------------------------------------------------
    reg [ADDR_BITS:0] wr_ptr;
    reg [ADDR_BITS:0] rd_ptr;

    wire [ADDR_BITS-1:0] wr_addr = wr_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr = rd_ptr[ADDR_BITS-1:0];

    // ----------------------------------------------------------------
    // Status
    // ----------------------------------------------------------------
    wire ptr_match = (wr_ptr[ADDR_BITS-1:0] == rd_ptr[ADDR_BITS-1:0]);
    wire phase_eq  = (wr_ptr[ADDR_BITS]     == rd_ptr[ADDR_BITS]);

    wire empty = ptr_match &&  phase_eq;
    wire full  = ptr_match && !phase_eq;

    assign fill_level = wr_ptr - rd_ptr;

    // ----------------------------------------------------------------
    // Handshake
    // ----------------------------------------------------------------
    wire wr_en = s_tvalid & s_tready;
    wire rd_en = m_tvalid & m_tready;

    assign s_tready = !full;

    // ----------------------------------------------------------------
    // Write logic
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= {s_tlast, s_tdata};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= {(ADDR_BITS+1){1'b0}};
        else if (wr_en)
            wr_ptr <= wr_ptr + 1'b1;
    end

    // ----------------------------------------------------------------
    // Read logic (First-Word Fall-Through)
    //
    // We use a registered output stage to meet timing.
    // When the FIFO transitions from empty to non-empty, we load
    // the output register. When the output is consumed (rd_en),
    // we load the next entry if available.
    // ----------------------------------------------------------------
    reg [MEM_WIDTH-1:0] out_reg;
    reg                 out_valid;

    assign m_tdata  = out_reg[DATA_WIDTH-1:0];
    assign m_tlast  = out_reg[MEM_WIDTH-1];
    assign m_tvalid = out_valid;

    // Internal read pointer: tracks FIFO consumption
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= {(ADDR_BITS+1){1'b0}};
        else if (!out_valid && !empty) begin
            // Output register empty, FIFO has data ¡ú load
            rd_ptr <= rd_ptr + 1'b1;
        end else if (out_valid && m_tready && !empty) begin
            // Output consumed and FIFO has more ¡ú load next
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reg   <= {MEM_WIDTH{1'b0}};
            out_valid <= 1'b0;
        end else if (!out_valid && !empty) begin
            // First word fall-through: load from FIFO
            out_reg   <= mem[rd_addr];
            out_valid <= 1'b1;
        end else if (out_valid && m_tready) begin
            if (!empty) begin
                // Load next word
                out_reg   <= mem[rd_addr];
                out_valid <= 1'b1;
            end else begin
                // FIFO exhausted
                out_valid <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Assertions (simulation only)
    // ----------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n) begin
            if (wr_en && full)
                $display("%m WARNING: write to full FIFO at time %0t", $time);
            if (rd_en && empty && !out_valid)
                $display("%m WARNING: read from empty FIFO at time %0t", $time);
        end
    end
    // synthesis translate_on

endmodule
