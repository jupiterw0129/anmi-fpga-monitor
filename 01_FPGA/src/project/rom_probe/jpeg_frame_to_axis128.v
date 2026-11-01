module jpeg_frame_to_axis128 #(
    parameter ADDR_WIDTH = 12
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] s_data,
    input wire s_valid,
    input wire s_last,
    output reg [127:0] m_data,
    output reg [15:0] m_keep,
    output reg m_valid,
    input wire m_ready,
    output reg m_last,
    output reg [31:0] oversize_count,
    output reg [31:0] busy_drop_count
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam CAPTURE = 2'd0;
    localparam DRAIN = 2'd1;
    localparam DROP = 2'd2;
    reg [1:0] state;
    reg [127:0] memory [0:DEPTH-1];
    reg [127:0] pending_data;
    reg [127:0] assembled;
    reg [3:0] byte_index;
    reg [ADDR_WIDTH:0] write_addr;
    reg [ADDR_WIDTH:0] read_addr;
    reg [ADDR_WIDTH:0] frame_words;
    reg [15:0] final_keep;
    reg drop_inflight;
    reg drop_is_busy;
    wire commit_word = s_valid && (byte_index == 15 || s_last);
    wire write_word = state == CAPTURE && commit_word && write_addr != DEPTH;

    always @* begin
        assembled = pending_data;
        assembled[byte_index*8 +: 8] = s_data;
    end

    always @(posedge clk) begin
        if (write_word)
            memory[write_addr[ADDR_WIDTH-1:0]] <= assembled;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= CAPTURE;
            pending_data <= 0;
            byte_index <= 0;
            write_addr <= 0;
            read_addr <= 0;
            frame_words <= 0;
            final_keep <= 0;
            drop_inflight <= 0;
            drop_is_busy <= 0;
            m_data <= 0;
            m_keep <= 0;
            m_valid <= 0;
            m_last <= 0;
            oversize_count <= 0;
            busy_drop_count <= 0;
        end else begin
            case (state)
                CAPTURE: begin
                    if (s_valid) begin
                        if (commit_word) begin
                            if (write_addr == DEPTH) begin
                                oversize_count <= oversize_count + 1'b1;
                                drop_is_busy <= 0;
                                state <= s_last ? CAPTURE : DROP;
                                write_addr <= 0;
                            end else if (s_last) begin
                                frame_words <= write_addr + 1'b1;
                                final_keep <= 16'hffff >> (15-byte_index);
                                read_addr <= 0;
                                state <= DRAIN;
                            end else
                                write_addr <= write_addr + 1'b1;
                            pending_data <= 0;
                            byte_index <= 0;
                        end else begin
                            pending_data[byte_index*8 +: 8] <= s_data;
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end
                DRAIN: begin
                    if (s_valid) begin
                        drop_inflight <= !s_last;
                        if (s_last)
                            busy_drop_count <= busy_drop_count + 1'b1;
                    end
                    if (!m_valid) begin
                        m_data <= memory[read_addr[ADDR_WIDTH-1:0]];
                        m_keep <= read_addr == frame_words-1'b1 ? final_keep : 16'hffff;
                        m_last <= read_addr == frame_words-1'b1;
                        m_valid <= 1;
                    end else if (m_ready) begin
                        m_valid <= 0;
                        if (m_last) begin
                            write_addr <= 0;
                            pending_data <= 0;
                            byte_index <= 0;
                            state <= (s_valid && !s_last) || (drop_inflight && !(s_valid && s_last)) ? DROP : CAPTURE;
                            drop_is_busy <= 1;
                        end else
                            read_addr <= read_addr + 1'b1;
                    end
                end
                DROP: begin
                    if (s_valid && s_last) begin
                        state <= CAPTURE;
                        drop_inflight <= 0;
                        if (drop_is_busy)
                            busy_drop_count <= busy_drop_count + 1'b1;
                    end
                end
                default: state <= CAPTURE;
            endcase
        end
    end
endmodule
