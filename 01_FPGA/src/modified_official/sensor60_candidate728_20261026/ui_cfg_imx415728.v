module ui_cfg_imx415 #(
    parameter CLK_DIV = 16'd269
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire [1:0] I_cam_mode,
    input wire I_ae_req,
    input wire [7:0] I_ae_data,
    output wire O_cam_scl,
    inout wire IO_cam_sda,
    output reg O_cfg_done,
    output reg O_ae_cfg_done,
    output reg O_bus_error
);
    localparam PREPARE = 3'd0, LAUNCH = 3'd1, WAIT_BUSY = 3'd2;
    localparam WAIT_DONE = 3'd3, ADVANCE = 3'd4, SETTLE = 3'd5;
    localparam IDLE = 3'd6, FAILED = 3'd7;
    reg [2:0] state;
    reg [1:0] phase, active_mode;
    reg [8:0] register_index;
    wire [31:0] register_data;
    wire [7:0] register_size;
    reg [31:0] write_data;
    reg request;
    reg [21:0] wait_count;
    reg [19:0] settle_count;
    wire bus_busy, bus_error;
    wire transaction_active = state == LAUNCH || state == WAIT_BUSY || state == WAIT_DONE;

    ui_imx415reg registers(active_mode, register_index, register_data, register_size);
    ui_i2c #(.WMEN_LEN(4), .RMEN_LEN(1), .CLK_DIV(CLK_DIV)) X_ui_i2c (
        .I_clk(I_clk), .I_rstn(I_rst_n), .O_iic_scl(O_cam_scl),
        .IO_iic_sda(IO_cam_sda), .I_wr_data(write_data), .I_wr_cnt(8'd4),
        .O_rd_data(), .I_rd_cnt(8'd0), .I_iic_mode(1'b0),
        .I_iic_req(request), .O_iic_busy(bus_busy), .O_iic_bus_error(bus_error)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state <= PREPARE;
            phase <= 2'd0;
            active_mode <= 2'd0;
            register_index <= 9'd0;
            write_data <= 32'd0;
            request <= 1'b0;
            wait_count <= 22'd0;
            settle_count <= 20'd0;
            O_cfg_done <= 1'b0;
            O_ae_cfg_done <= 1'b1;
            O_bus_error <= 1'b0;
        end else begin
            if (bus_error) begin
                O_bus_error <= 1'b1;
                O_cfg_done <= 1'b0;
            end
            if (I_cam_mode != active_mode)
                O_cfg_done <= 1'b0;
            if (I_cam_mode != active_mode && !transaction_active && !bus_busy) begin
                active_mode <= I_cam_mode;
                register_index <= 9'd0;
                phase <= 2'd0;
                request <= 1'b0;
                wait_count <= 22'd0;
                settle_count <= 20'd0;
                O_cfg_done <= 1'b0;
                O_ae_cfg_done <= 1'b1;
                O_bus_error <= 1'b0;
                state <= PREPARE;
            end else begin
                case (state)
                    PREPARE: begin
                        request <= 1'b0;
                        case (phase)
                            2'd0: write_data <= {register_data[7:0], register_data[15:8], register_data[23:16], 8'h34};
                            2'd1: write_data <= 32'h00003034;
                            2'd2: write_data <= 32'h00023034;
                            2'd3: write_data <= {I_ae_data, 24'h903034};
                        endcase
                        state <= LAUNCH;
                    end
                    LAUNCH: begin
                        if (!bus_busy) begin
                            request <= 1'b1;
                            wait_count <= 22'd0;
                            state <= WAIT_BUSY;
                        end
                    end
                    WAIT_BUSY: begin
                        wait_count <= wait_count + 1'b1;
                        if (bus_busy) begin
                            request <= 1'b0;
                            wait_count <= 22'd0;
                            state <= WAIT_DONE;
                        end else if (wait_count == 22'd2700000) begin
                            request <= 1'b0;
                            O_bus_error <= 1'b1;
                            O_cfg_done <= 1'b0;
                            state <= FAILED;
                        end
                    end
                    WAIT_DONE: begin
                        wait_count <= wait_count + 1'b1;
                        if (!bus_busy) begin
                            if (O_bus_error || bus_error)
                                state <= FAILED;
                            else
                                state <= ADVANCE;
                        end else if (wait_count == 22'd2700000) begin
                            O_bus_error <= 1'b1;
                            O_cfg_done <= 1'b0;
                            state <= FAILED;
                        end
                    end
                    ADVANCE: begin
                        case (phase)
                            2'd0: begin
                                if (register_index + 1'b1 == {1'b0, register_size}) begin
                                    phase <= 2'd1;
                                    state <= PREPARE;
                                end else begin
                                    register_index <= register_index + 1'b1;
                                    state <= PREPARE;
                                end
                            end
                            2'd1: begin
                                settle_count <= 20'd0;
                                state <= SETTLE;
                            end
                            2'd2: begin
                                O_cfg_done <= 1'b1;
                                state <= IDLE;
                            end
                            2'd3: begin
                                O_ae_cfg_done <= 1'b1;
                                state <= IDLE;
                            end
                        endcase
                    end
                    SETTLE: begin
                        if (settle_count == 20'd647999) begin
                            phase <= 2'd2;
                            state <= PREPARE;
                        end else
                            settle_count <= settle_count + 1'b1;
                    end
                    IDLE: begin
                        if (I_ae_req) begin
                            O_ae_cfg_done <= 1'b0;
                            phase <= 2'd3;
                            state <= PREPARE;
                        end
                    end
                    FAILED: begin
                        request <= 1'b0;
                        O_cfg_done <= 1'b0;
                        O_ae_cfg_done <= 1'b1;
                    end
                    default: state <= FAILED;
                endcase
            end
        end
    end
endmodule
