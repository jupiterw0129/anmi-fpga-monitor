module token_axis128 (
    input wire clk,
    input wire reset,
    input wire [103:0] s_data,
    input wire [3:0] s_bytes,
    input wire s_valid,
    output wire s_ready,
    input wire s_sof,
    input wire s_last,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_valid,
    input wire m_ready,
    output wire m_sof,
    output wire m_last
);
    reg [255:0] reservoir;
    reg [5:0] count;
    reg ending, first;
    wire pop = m_valid && m_ready;
    wire push = s_valid && s_ready;
    wire [5:0] remaining_count = pop ? (count > 16 ? count - 16 : 0) : count;
    wire [255:0] remaining_data = pop ? (count > 16 ? reservoir >> 128 : 0) : reservoir;
    wire [255:0] incoming = {152'd0,s_data} << {remaining_count[4:0],3'b000};

    assign m_valid = count >= 16 || (ending && count != 0);
    assign m_last = ending && count <= 16;
    assign m_sof = first;
    assign m_data = reservoir[127:0];
    assign m_keep = count >= 16 ? 16'hffff : ((17'd1 << count[3:0]) - 1);
    assign s_ready = !ending && (count <= 16 || pop);

    always @(posedge clk) begin
        if (reset) begin
            reservoir <= 0;
            count <= 0;
            ending <= 0;
            first <= 0;
        end else begin
            reservoir <= remaining_data | (push ? incoming : 256'd0);
            count <= remaining_count + (push ? s_bytes : 0);
            if (pop) first <= 0;
            if (pop && m_last) ending <= 0;
            if (push) begin
                if (s_sof) first <= 1;
                if (s_last) ending <= 1;
            end
        end
    end
endmodule
