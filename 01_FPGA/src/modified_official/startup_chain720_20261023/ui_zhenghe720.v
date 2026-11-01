// Candidate for the 32-bit Bayer line normalizer used by demosaic.
// Publish a line only after EOL. Two 1024-word banks share the existing
// 2048x32 RAM, so an incomplete line can never be read as a complete one.
// Camera input is non-stalling and must leave at least one idle cycle/line.
// data_complete_delay remains an interface parameter; latency is now one line.
module ui_zhenghe #(
    parameter [8:0] DATA_WIDTH = 96,
    parameter [8:0] data_complete_delay = 50
)(
    input I_clk,
    input I_rst_n,
    input [12:0] I_img_width,
    input I_tlast,
    input I_tuser,
    input [DATA_WIDTH-1:0] I_tdata,
    input I_tvalid,
    output reg O_tlast,
    output reg O_tuser,
    output [DATA_WIDTH-1:0] O_tdata,
    output reg O_tvalid
);
    reg write_bank, read_bank;
    reg [9:0] write_column, read_column;
    reg [1:0] complete, line_sof;
    reg [10:0] line_length [0:1];
    reg input_sof, reading;
    wire [9:0] input_column = I_tuser ? 10'd0 : write_column;
    wire [10:0] write_address = {write_bank, input_column};
    wire [10:0] read_address = {read_bank, read_column};
    wire [31:0] ram_data;
    assign O_tdata = ram_data;

    ui_ram_zhenghe ram (
        .clka(I_clk), .wea(I_tvalid && I_rst_n), .addra(write_address), .dia(I_tdata),
        .clkb(I_clk), .addrb(read_address), .dob(ram_data)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            write_bank <= 0; read_bank <= 0;
            write_column <= 0; read_column <= 0;
            complete <= 0; line_sof <= 0;
            line_length[0] <= 0; line_length[1] <= 0;
            input_sof <= 0; reading <= 0;
            O_tlast <= 0; O_tuser <= 0; O_tvalid <= 0;
        end else begin
            O_tvalid <= reading;
            O_tuser <= reading && read_column == 0 && line_sof[read_bank];
            O_tlast <= reading && {1'b0, read_column} == line_length[read_bank] - 1'b1;
            if (I_tuser) begin
                input_sof <= 1;
                write_column <= 0;
            end
            if (I_tvalid) begin
                if (I_tlast) begin
                    line_length[write_bank] <= {1'b0, input_column} + 1'b1;
                    line_sof[write_bank] <= I_tuser || input_sof;
                    complete[write_bank] <= 1;
                    write_bank <= ~write_bank;
                    write_column <= 0;
                    input_sof <= 0;
                end else write_column <= input_column + 1'b1;
            end
            if (!reading) begin
                if (complete[read_bank]) begin
                    reading <= 1;
                    read_column <= 0;
                end
            end else if ({1'b0, read_column} == line_length[read_bank] - 1'b1) begin
                reading <= 0;
                read_column <= 0;
                complete[read_bank] <= 0;
                read_bank <= ~read_bank;
            end else read_column <= read_column + 1'b1;
        end
    end

    // synthesis translate_off
    always @(posedge I_clk) begin
        if (I_rst_n && I_tvalid) begin
            if (complete[write_bank]) $fatal(1, "LINE_BANK_OVERRUN");
            if (I_img_width < 4 || I_img_width > 4096 || I_img_width[1:0] != 0)
                $fatal(1, "UNSUPPORTED_LINE_GEOMETRY");
            if (I_tlast && {1'b0, input_column} + 1 != I_img_width / 4)
                $fatal(1, "INPUT_LINE_LENGTH_MISMATCH");
        end
    end
    // synthesis translate_on
endmodule
