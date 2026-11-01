module jpeg_quality_config (
    input wire clk,
    input wire rst_n,
    input wire frame_accept,
    input wire [6:0] requested_quality,
    output reg [6:0] active_quality,
    output wire ready,
    output wire error,
    output wire [4:0] awaddr,
    output wire awvalid,
    input wire awready,
    output wire [31:0] wdata,
    output wire wvalid,
    input wire wready,
    input wire bvalid,
    input wire [1:0] bresp
);
    localparam WAIT_FRAME = 3'd0, WRITE_QUALITY = 3'd1, QUALITY_RESPONSE = 3'd2;
    localparam WRITE_ENABLE = 3'd3, ENABLE_RESPONSE = 3'd4, READY = 3'd5, ERROR = 3'd6;
    reg [2:0] state;
    reg address_sent;
    reg data_sent;
    wire writing = state == WRITE_QUALITY || state == WRITE_ENABLE;
    assign ready = state == READY;
    assign error = state == ERROR;
    assign awaddr = state == WRITE_QUALITY ? 5'h0c : 5'h00;
    assign wdata = state == WRITE_QUALITY ? {25'd0, active_quality} : 32'd1;
    assign awvalid = writing && !address_sent;
    assign wvalid = writing && !data_sent;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_FRAME;
            active_quality <= 7'd75;
            address_sent <= 1'b0;
            data_sent <= 1'b0;
        end else begin
            case (state)
                WAIT_FRAME: begin
                    if (frame_accept) begin
                        active_quality <= requested_quality == 0 ? 7'd1 :
                                          requested_quality > 100 ? 7'd100 : requested_quality;
                        state <= WRITE_QUALITY;
                    end
                end
                WRITE_QUALITY, WRITE_ENABLE: begin
                    if (awvalid && awready)
                        address_sent <= 1'b1;
                    if (wvalid && wready)
                        data_sent <= 1'b1;
                    if ((address_sent || awready) && (data_sent || wready))
                        state <= state == WRITE_QUALITY ? QUALITY_RESPONSE : ENABLE_RESPONSE;
                end
                QUALITY_RESPONSE, ENABLE_RESPONSE: begin
                    if (bvalid) begin
                        address_sent <= 1'b0;
                        data_sent <= 1'b0;
                        if (bresp != 2'b00)
                            state <= ERROR;
                        else
                            state <= state == QUALITY_RESPONSE ? WRITE_ENABLE : READY;
                    end
                end
                default: begin
                    state <= state;
                end
            endcase
        end
    end
endmodule
