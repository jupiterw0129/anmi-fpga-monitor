module predictive_rgb4 (
    input wire clk,
    input wire reset,
    input wire [95:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_sof,
    input wire s_last,
    output reg [103:0] m_data,
    output reg [3:0] m_bytes,
    output reg m_valid,
    input wire m_ready,
    output reg m_sof,
    output reg m_last
);
    reg [23:0] previous;
    reg [7:0] residual [0:11];
    reg [7:0] stage_residual [0:11];
    reg [7:0] difference;
    reg [7:0] predictor;
    reg [3:0] width;
    reg [3:0] stage_width;
    reg stage_valid, stage_sof, stage_last;
    wire output_ready = !m_valid || m_ready;
    wire stage_ready = !stage_valid || output_ready;
    reg [95:0] packed_residual;
    integer lane;
    reg [7:0] residual_union;

    assign s_ready = stage_ready;

    always @* begin
        predictor = 0;
        difference = 0;
        for (lane = 0; lane < 12; lane = lane + 1) begin
            predictor = lane < 3 ? (s_sof ? 8'd0 : previous[(lane%3)*8 +: 8]) : s_data[(lane-3)*8 +: 8];
            difference = s_data[lane*8 +: 8] - predictor;
            residual[lane] = {difference[6:0],1'b0} ^ {8{difference[7]}};
        end
        residual_union = (residual[0] | residual[1] | residual[2]) |
                         (residual[3] | residual[4] | residual[5]) |
                         (residual[6] | residual[7] | residual[8]) |
                         (residual[9] | residual[10] | residual[11]);
        casez (residual_union)
            8'b1???????: width = 8;
            8'b01??????: width = 7;
            8'b001?????: width = 6;
            8'b0001????: width = 5;
            8'b00001???: width = 4;
            8'b000001??: width = 3;
            8'b0000001?: width = 2;
            8'b00000001: width = 1;
            default: width = 0;
        endcase
    end

    always @* begin
        packed_residual = 0;
        case (stage_width)
            1: for (integer index=0; index<12; index=index+1) packed_residual[index +: 1] = stage_residual[index][0:0];
            2: for (integer index=0; index<12; index=index+1) packed_residual[index*2 +: 2] = stage_residual[index][1:0];
            3: for (integer index=0; index<12; index=index+1) packed_residual[index*3 +: 3] = stage_residual[index][2:0];
            4: for (integer index=0; index<12; index=index+1) packed_residual[index*4 +: 4] = stage_residual[index][3:0];
            5: for (integer index=0; index<12; index=index+1) packed_residual[index*5 +: 5] = stage_residual[index][4:0];
            6: for (integer index=0; index<12; index=index+1) packed_residual[index*6 +: 6] = stage_residual[index][5:0];
            7: for (integer index=0; index<12; index=index+1) packed_residual[index*7 +: 7] = stage_residual[index][6:0];
            8: for (integer index=0; index<12; index=index+1) packed_residual[index*8 +: 8] = stage_residual[index];
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            previous <= 0;
            stage_valid <= 0;
            stage_width <= 0;
            stage_sof <= 0;
            stage_last <= 0;
            m_valid <= 0;
            m_data <= 0;
            m_bytes <= 0;
            m_sof <= 0;
            m_last <= 0;
            for (integer index=0; index<12; index=index+1) stage_residual[index] <= 0;
        end else begin
            if (stage_ready) begin
                stage_valid <= s_valid;
                if (s_valid) begin
                    previous <= s_data[95:72];
                    stage_width <= width;
                    stage_sof <= s_sof;
                    stage_last <= s_last;
                    for (integer index=0; index<12; index=index+1) stage_residual[index] <= residual[index];
                end
            end
            if (output_ready) begin
                m_valid <= stage_valid;
                if (stage_valid) begin
                    m_data <= {packed_residual,4'ha,stage_width};
                    case (stage_width)
                        0: m_bytes <= 1;
                        1: m_bytes <= 3;
                        2: m_bytes <= 4;
                        3: m_bytes <= 6;
                        4: m_bytes <= 7;
                        5: m_bytes <= 9;
                        6: m_bytes <= 10;
                        7: m_bytes <= 12;
                        8: m_bytes <= 13;
                        default: m_bytes <= 0;
                    endcase
                    m_sof <= stage_sof;
                    m_last <= stage_last;
                end
            end
        end
    end
endmodule
