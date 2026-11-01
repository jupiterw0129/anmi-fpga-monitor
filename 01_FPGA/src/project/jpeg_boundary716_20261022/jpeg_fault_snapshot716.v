module jpeg_fault_snapshot716 (
    input wire clk,
    input wire reset_n,
    input wire [3:0] read_index,
    input wire [2:0] state,
    input wire [9:0] row,
    input wire [8:0] column,
    input wire [5:0] reasons,
    input wire fault,
    input wire accepted,
    input wire source_valid,
    input wire source_user,
    input wire source_last,
    input wire queue_ready,
    input wire packet_valid,
    input wire packet_ready,
    input wire packet_last,
    output reg [31:0] read_data
);
    reg [31:0] cycles, fault_count, source_frames, admitted_frames, completed_frames;
    reg [31:0] first_reasons, first_geometry, first_stream, first_cycle;
    reg [31:0] last_reasons, last_geometry, last_cycle;
    reg seen_fault;
    wire [31:0] geometry = {10'd0, state, row, column};
    wire [31:0] stream = {24'd0, packet_last, packet_ready, packet_valid,
                         queue_ready, accepted, source_last, source_user, source_valid};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycles <= 0;
            fault_count <= 0;
            source_frames <= 0;
            admitted_frames <= 0;
            completed_frames <= 0;
            seen_fault <= 0;
            first_reasons <= 0;
            first_geometry <= 0;
            first_stream <= 0;
            first_cycle <= 0;
            last_reasons <= 0;
            last_geometry <= 0;
            last_cycle <= 0;
        end else begin
            cycles <= cycles + 1'b1;
            if (source_valid && source_user)
                source_frames <= source_frames + 1'b1;
            if (accepted && source_user && !fault)
                admitted_frames <= admitted_frames + 1'b1;
            if (packet_valid && packet_ready && packet_last)
                completed_frames <= completed_frames + 1'b1;
            if (fault) begin
                seen_fault <= 1;
                fault_count <= fault_count + 1'b1;
                last_reasons <= {26'd0, reasons};
                last_geometry <= geometry;
                last_cycle <= cycles;
                if (!seen_fault) begin
                    first_reasons <= {26'd0, reasons};
                    first_geometry <= geometry;
                    first_stream <= stream;
                    first_cycle <= cycles;
                end
            end
        end
    end

    always @* begin
        case (read_index)
            0: read_data = 32'h4a444716;
            1: read_data = 32'd1;
            2: read_data = {21'd0, seen_fault, reasons, fault, state};
            3: read_data = fault_count;
            4: read_data = first_reasons;
            5: read_data = first_geometry;
            6: read_data = first_stream;
            7: read_data = first_cycle;
            8: read_data = last_reasons;
            9: read_data = last_geometry;
            10: read_data = source_frames;
            11: read_data = admitted_frames;
            12: read_data = completed_frames;
            13: read_data = cycles;
            14: read_data = last_cycle;
            15: read_data = 32'h0000003f;
            default: read_data = 0;
        endcase
    end
endmodule
