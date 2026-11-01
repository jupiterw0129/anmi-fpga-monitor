`include "pcie_brg_def.svh"

module pcie_brg_xmit_msg#(
    parameter XMIT_MSG_EN = 1,
    parameter CFG_PF_NUM = 4,
    parameter CORE_PF_NUM = 4
) (
    input logic user_clk,
    input logic user_rst,

    input logic ari_cap,
    input logic [7:0] bus_num,
    input logic [4:0] dev_num,
    cfg_xmit_msg_if.slv cfg_xmit_msg,

    input  logic xmit_msg_rdy,
    output logic xmit_msg_vld,
    output logic xmit_msg_err,
    output pcie_tlp_header_t xmit_msg_header,// msg header is 4 dw
    output logic [31:0] xmit_msg_data,

    output logic busy
);

logic [15:0] pf0_req_id;// user clk
logic [15:0] pf1_req_id;
logic [15:0] vf0_req_id;
logic [15:0] vf1_req_id;
logic [15:0] vf2_req_id;
logic [15:0] vf3_req_id;
logic [15:0] vf4_req_id;
logic [15:0] vf5_req_id;

logic xmit_msg_req_r;
logic xmit_msg_err_r;
logic xmit_msg_with_data_r;
pcie_tlp_header_t xmit_msg_header_r;
logic [31:0] xmit_msg_data_r;
logic xmit_msg_ack;
logic [7:0] xmit_msg_pme_function_r;
logic [2:0] xmit_msg_pme_function_sel_r;

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
pf0_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(0), .bdf_num(pf0_req_id));

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
pf1_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(1), .bdf_num(pf1_req_id));

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
vf0_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(CFG_PF_NUM+0), .bdf_num(vf0_req_id));

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
vf1_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(CFG_PF_NUM+1), .bdf_num(vf1_req_id));

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
vf2_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(CFG_PF_NUM+2), .bdf_num(vf2_req_id));

pcie_brg_bdf_enc#(.CFG_PF_NUM(CFG_PF_NUM), .CORE_PF_NUM(CORE_PF_NUM))
vf3_bdf(.ari_cap(ari_cap), .bus_num(bus_num), .dev_num(dev_num), .func_num(CFG_PF_NUM+3), .bdf_num(vf3_req_id));

enum logic [1:0] {
    sm_idle, sm_xmit, sm_pme, sm_pme_xmit
} sm_xmit_r;

always_ff @(posedge user_clk) begin
    case (sm_xmit_r)
        sm_idle: begin
            xmit_msg_header_r <= 0;
            xmit_msg_err_r <= 0;
            xmit_msg_with_data_r <= 0;
            xmit_msg_data_r <= 0;
            xmit_msg_pme_function_sel_r <= 0;
            if(cfg_xmit_msg.cfg_msg_transmit) begin
                sm_xmit_r <= sm_xmit;
                case (cfg_xmit_msg.cfg_msg_transmit_type)
                    3'd0: begin// ltr
                        xmit_msg_header_r.dw0[31:24] <= 8'b001_10100;
                        xmit_msg_header_r.dw1[31:16] <= pf0_req_id;
                        xmit_msg_header_r.dw1[15:8] <= 0;// FIXME where is tag from?
                        xmit_msg_header_r.dw1[7:0] <= 8'b0001_0000;
                        xmit_msg_header_r.dw3[31:16] <= {cfg_xmit_msg.cfg_msg_transmit_data[31], 2'b0, cfg_xmit_msg.cfg_msg_transmit_data[28:16]};
                        xmit_msg_header_r.dw3[15:0] <= {cfg_xmit_msg.cfg_msg_transmit_data[15], 2'b0, cfg_xmit_msg.cfg_msg_transmit_data[12:0]};
                    end
                    3'd1: begin// obff
                        xmit_msg_header_r.dw0[31:24] <= 8'b001_10100;
                        xmit_msg_header_r.dw1[31:16] <= pf0_req_id;
                        xmit_msg_header_r.dw1[15:8] <= 0;// FIXME
                        xmit_msg_header_r.dw1[7:0] <= 8'b0001_0010;
                        xmit_msg_header_r.dw3[3:0] <= cfg_xmit_msg.cfg_msg_transmit_data[3:0];
                    end
                    3'd2: begin// sspl
                        xmit_msg_with_data_r <= 1;
                        xmit_msg_header_r.dw0[31:24] <= 8'b001_10100;
                        xmit_msg_header_r.dw0[9:0] <= 1;
                        xmit_msg_header_r.dw1[31:16] <= pf0_req_id;
                        xmit_msg_header_r.dw1[15:8] <= 0;// FIXME
                        xmit_msg_header_r.dw1[7:0] <= 8'b0101_0000;
                        xmit_msg_data_r[9:0] <= cfg_xmit_msg.cfg_msg_transmit_data[9:0];
                    end
                    3'd3: begin// pm pme
                        sm_xmit_r <= sm_pme;
                        xmit_msg_pme_function_r <= {cfg_xmit_msg.cfg_msg_transmit_data[9:4], cfg_xmit_msg.cfg_msg_transmit_data[1:0]};
                    end
                    default: begin
                        xmit_msg_err_r <= 1;
                    end
                endcase
            end
        end
        sm_xmit: begin
            if (xmit_msg_ack)
                sm_xmit_r <= sm_idle;
        end
        sm_pme: begin
            xmit_msg_pme_function_sel_r <= xmit_msg_pme_function_sel_r + 1;
            sm_xmit_r <= xmit_msg_pme_function_r[xmit_msg_pme_function_sel_r] ? sm_pme_xmit : ((xmit_msg_pme_function_sel_r == 3'd7) ? sm_idle : sm_xmit);
            case (xmit_msg_pme_function_sel_r)
                3'd0: xmit_msg_header_r.dw1[31:16] <= pf0_req_id;
                3'd1: xmit_msg_header_r.dw1[31:16] <= pf1_req_id;
                3'd2: xmit_msg_header_r.dw1[31:16] <= vf0_req_id;
                3'd3: xmit_msg_header_r.dw1[31:16] <= vf1_req_id;
                3'd4: xmit_msg_header_r.dw1[31:16] <= vf2_req_id;
                3'd5: xmit_msg_header_r.dw1[31:16] <= vf3_req_id;
                3'd6: xmit_msg_header_r.dw1[31:16] <= vf4_req_id;
                3'd7: xmit_msg_header_r.dw1[31:16] <= vf5_req_id;
            endcase
            xmit_msg_header_r.dw0[31:24] <= 8'b001_10000;
            xmit_msg_header_r.dw1[15:8] <= 0;// FIXME
            xmit_msg_header_r.dw1[7:0] <= 8'b0001_1000;
        end
        sm_pme_xmit: begin
            if (xmit_msg_ack)
                sm_xmit_r <= (xmit_msg_pme_function_sel_r == 3'd7) ? sm_idle : sm_pme;
        end
    endcase
    if (user_rst)
        sm_xmit_r <= sm_idle;
end

assign xmit_msg_req_r = (sm_xmit_r == sm_xmit) | (sm_xmit_r == sm_pme_xmit);

generate
    if (XMIT_MSG_EN) begin: xmit_msg_enable
        assign xmit_msg_ack = xmit_msg_rdy;
        assign xmit_msg_vld = xmit_msg_req_r;
        assign xmit_msg_err = xmit_msg_err_r;
        assign xmit_msg_header = xmit_msg_header_r;
        assign xmit_msg_data = xmit_msg_data_r;
        always_ff @(posedge user_rst) begin
            cfg_xmit_msg.cfg_msg_transmit_done <= xmit_msg_ack;
        end
    end else begin: xmit_msg_disable
        assign xmit_msg_ack = 0;
        assign xmit_msg_vld = 0;
        assign xmit_msg_err = 0;
        assign xmit_msg_header = 0;
        assign xmit_msg_data = 0;
        assign cfg_xmit_msg.cfg_msg_transmit_done = 0;
    end
endgenerate

assign busy = sm_xmit_r != sm_idle;

endmodule
