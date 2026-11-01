/*===========================================*\
Filename         : m_usr_irq.v
Project name     : native2axim_subsys_exam
Description      : Generate msi or msix interrupt.
Called by        : native2axim_app.v
Email            : bingsong.wang@anlogic.com
modified         : v1.0 Initial version.20231020
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/
module usr_irq #(
    parameter USR_INT_NUM = 4,
    parameter MSIX_EN = 0,
    parameter MSI_EN = 0
) (
    input   wire    user_clk,
    input   wire    user_rstn,

    // input   wire         irq_set,
    // input   wire         irq_clr,
    // input   wire   [3:0] irq_num_lo,
    // input   wire   [3:0] irq_num_hi,
    input   wire   [31:0]   usr_irq_req_i,  
    output  wire   [31:0]   usr_irq_evt_o,

    output  reg    [USR_INT_NUM:0]  usr_irq_req_o,
    input   wire   [USR_INT_NUM:0]  usr_irq_ack_i
);

reg [USR_INT_NUM:0] usr_irq_ack_d1;
wire [USR_INT_NUM:0] usr_irq_ack_fall;
reg [USR_INT_NUM:0] usr_irq_evt;

always @(posedge user_clk) begin
    usr_irq_ack_d1 <= usr_irq_ack_i;
end

assign usr_irq_ack_fall = ~usr_irq_ack_i & usr_irq_ack_d1;

genvar i0;
generate
    for (i0=0;i0<USR_INT_NUM;i0=i0+1) begin
        reg  [1:0] s_state;
        wire [1:0] s_idle  = 2'd0;
        wire [1:0] s_req   = 2'd1;
        wire [1:0] s_wait1 = 2'd2;
        wire [1:0] s_wait2 = 2'd3;

        always @(posedge user_clk or negedge user_rstn) begin
            if (~user_rstn)
                usr_irq_req_o[i0] <= 0;
            else
                usr_irq_req_o[i0] <= ((s_state == s_req) | (s_state == s_wait1)) & usr_irq_evt[i0];
        end

        always @(posedge user_clk or negedge user_rstn) begin
            if (~user_rstn)
                s_state <= s_idle;
            else begin
                case (s_state)
                    s_idle: begin
                        if (usr_irq_evt[i0]) begin
                            s_state <= s_req;
                        end
                    end
                    s_req: begin
                        if (usr_irq_ack_fall[i0]) begin // usr irq has been sent to pcie
                            s_state <= s_wait1;
                        end
                    end
                    s_wait1: begin
                        if (~usr_irq_evt[i0]) begin
                            if (MSIX_EN | MSI_EN)
                                s_state <= s_idle;
                            else
                                s_state <= s_wait2;
                        end
                    end
                    s_wait2: begin // wait a second ack if intx
                        if (usr_irq_ack_fall[i0])
                            s_state <= s_idle;
                    end
                endcase
            end
        end
    end
endgenerate

// genvar i1;
// generate
//     for (i1=0;i1<USR_INT_NUM;i1=i1+1) begin
//         always @(posedge user_clk or negedge user_rstn) begin
//             if (~user_rstn)
//                 usr_irq_evt[i1] <= 0;
//             else if (irq_clr & (i1 >= irq_num_lo) & (i1 <= irq_num_hi))
//                 usr_irq_evt[i1] <= 0;
//             else if (irq_set & (i1 >= irq_num_lo) & (i1 <= irq_num_hi))
//                 usr_irq_evt[i1] <= 1;
//         end
//     end
// endgenerate
genvar i1;
generate
    for (i1=0;i1<USR_INT_NUM;i1=i1+1) begin
        always @(posedge user_clk or negedge user_rstn) begin
            if (~user_rstn)
                usr_irq_evt[i1] <= 0;
            else if ( !usr_irq_req_i[i1] )
                usr_irq_evt[i1] <= 0;
            else if ( usr_irq_req_i[i1] )
                usr_irq_evt[i1] <= 1;
        end
    end
endgenerate

assign usr_irq_evt_o = usr_irq_evt;

endmodule
