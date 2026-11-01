module rgb4_to_jpeg_pixels #(
    parameter ADDR_WIDTH = 4
) (
    input wire clk,
    input wire rst_n,
    input wire [95:0] s_tdata,
    input wire s_tvalid,
    output wire s_tready,
    input wire s_tlast,
    input wire s_tuser,
    output wire [23:0] m_tdata,
    output wire m_tvalid,
    input wire m_tready,
    output wire m_tlast,
    output wire m_tuser
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    reg [97:0] storage [0:DEPTH-1];
    reg [97:0] head;
    reg [97:0] next_data;
    reg [97:0] last_write_data;
    reg [ADDR_WIDTH-1:0] last_write_addr;
    reg last_write_valid;
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH:0] count;
    reg [1:0] pixel_index;

    wire pixel_fire = m_tvalid && m_tready;
    wire beat_pop = pixel_fire && pixel_index == 2'd3;
    wire beat_push = s_tvalid && s_tready;
    wire [ADDR_WIDTH-1:0] next_read_addr = read_ptr + 1'b1;

    assign m_tvalid = count != 0;
    assign s_tready = count != DEPTH || beat_pop;
    assign m_tdata = head[pixel_index*24 +: 24];
    assign m_tuser = m_tvalid && head[97] && pixel_index == 2'd0;
    assign m_tlast = m_tvalid && head[96] && pixel_index == 2'd3;

    always @(posedge clk) begin
        if (beat_push)
            storage[write_ptr] <= {s_tuser, s_tlast, s_tdata};
        next_data <= storage[next_read_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
            read_ptr <= 0;
            count <= 0;
            pixel_index <= 0;
            head <= 0;
            last_write_valid <= 0;
            last_write_data <= 0;
            last_write_addr <= 0;
        end else begin
            last_write_valid <= beat_push;
            if (beat_push) begin
                last_write_data <= {s_tuser, s_tlast, s_tdata};
                last_write_addr <= write_ptr;
                write_ptr <= write_ptr + 1'b1;
            end
            if (beat_push && count == 0)
                head <= {s_tuser, s_tlast, s_tdata};
            else if (beat_pop) begin
                if (count == 1) begin
                    if (beat_push)
                        head <= {s_tuser, s_tlast, s_tdata};
                end else if (last_write_valid && last_write_addr == next_read_addr)
                    head <= last_write_data;
                else
                    head <= next_data;
            end
            if (pixel_fire) begin
                pixel_index <= pixel_index + 1'b1;
                if (beat_pop)
                    read_ptr <= read_ptr + 1'b1;
            end
            case ({beat_push, beat_pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
