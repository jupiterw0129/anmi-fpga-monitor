`include "pcie_brg_def.svh"

module pcie_brg_recv_msg #(
    parameter RECV_MSG_EN = 1
) (
    input  logic user_clk,
    input  logic user_rst,

    input  logic msg_vld,
    output logic msg_rdy,
    input  pcie_tlp_header_t msg_header,
    input  logic [31:0] msg_data,

    cfg_recv_msg_if.mst cfg_recv_msg,
    output logic recv_msg_err,

    output logic busy
);

enum logic [4:0] {
    err_cor, err_nonfatal, err_fatal, err_assert_inta, err_deassert_inta, err_assert_intb, err_deassert_intb, err_assert_intc, err_deassert_intc, err_assert_intd, err_deassert_intd,
    pm_pme, pme_to_ack, pme_turn_off, pm_active_state_nak, set_slot_power_limit, ltr, obff, unlock, vendor_defined_type0, vendor_defined_type1,
    ats_invalid_request, ats_invalid_completion, ats_page_request, ats_prg_response, reserved
} recv_type_c;

logic [7:0] err_data;
logic [7:0] intx_data;
logic [7:0] pm_data;
logic [7:0] sspl_data;
logic [7:0] ltr_data;
logic [7:0] obff_data;
logic [7:0] unlock_data;
logic [7:0] vd_type_data;
logic [7:0] ats_data;

logic recv_idle;
logic [2:0] recv_counter;
pcie_tlp_header_t msg_header_r;
logic [31:0] msg_data_r;
logic msg_with_data_r;

assign msg_rdy = RECV_MSG_EN ? recv_idle : 0;

always_comb begin
    case (msg_header_r.dw1[7:0])
        // err
        8'b0011_0000: recv_type_c = err_cor;
        8'b0011_0001: recv_type_c = err_nonfatal;
        8'b0011_0011: recv_type_c = err_fatal;
        // intx
        8'b0010_0000: recv_type_c = err_assert_inta;
        8'b0010_0001: recv_type_c = err_assert_intb;
        8'b0010_0010: recv_type_c = err_assert_intc;
        8'b0010_0011: recv_type_c = err_assert_intd;
        8'b0010_0100: recv_type_c = err_deassert_inta;
        8'b0010_0101: recv_type_c = err_deassert_intb;
        8'b0010_0110: recv_type_c = err_deassert_intc;
        8'b0010_0111: recv_type_c = err_deassert_intd;
        // pm
        8'b0001_0100: recv_type_c = pm_active_state_nak;
        8'b0001_1000: recv_type_c = pm_pme;
        8'b0001_1001: recv_type_c = pme_turn_off;
        8'b0001_1011: recv_type_c = pme_to_ack;
        // sspl
        8'b0101_0000: recv_type_c = set_slot_power_limit;
        // ltr
        8'b0001_0000: recv_type_c = ltr;
        // obff
        8'b0001_0010: recv_type_c = obff;
        // unlock
        8'b0000_0000: recv_type_c = unlock;
        // vendor defined type0
        8'b0111_1110: recv_type_c = vendor_defined_type0;
        // vendor defined type1
        8'b0111_1111: recv_type_c = vendor_defined_type1;
        // ats
        8'b0000_0001: recv_type_c = ats_invalid_request;
        8'b0000_0010: recv_type_c = ats_invalid_completion;
        8'b0000_0100: recv_type_c = ats_page_request;
        8'b0000_0101: recv_type_c = ats_prg_response;
        // reserved
        default: recv_type_c = reserved;
    endcase
end

always_comb begin
    err_data = 0;
    intx_data = 0;
    pm_data = 0;
    sspl_data = 0;
    ltr_data = 0;
    obff_data = 0;
    unlock_data = 0;
    vd_type_data = 0;
    ats_data = 0;
    case (recv_counter)
        3'd0: err_data = msg_header_r.dw1[31:24];
        3'd1: err_data = msg_header_r.dw1[23:16];
    endcase
    case (recv_counter)
        3'd0: intx_data = msg_header_r.dw1[31:24];
        3'd1: intx_data = msg_header_r.dw1[23:16];
    endcase
    case (recv_counter)
        3'd0: sspl_data = msg_header_r.dw1[31:24];
        3'd1: sspl_data = msg_header_r.dw1[23:16];
        3'd2: sspl_data = msg_data_r[7:0];
        3'd3: sspl_data = msg_data_r[15:8];
        3'd4: sspl_data = msg_data_r[23:16];
        3'd5: sspl_data = msg_data_r[31:24];
    endcase
    case (recv_counter)
        3'd0: ltr_data = msg_header_r.dw1[31:24];
        3'd1: ltr_data = msg_header_r.dw1[23:16];
        3'd2: ltr_data = msg_header_r.dw3[7:0];
        3'd3: ltr_data = msg_header_r.dw3[15:8];
        3'd4: ltr_data = msg_header_r.dw3[23:16];
        3'd5: ltr_data = msg_header_r.dw3[31:24];
    endcase
    case (recv_counter)
        3'd0: obff_data = msg_header_r.dw1[31:24];
        3'd1: obff_data = msg_header_r.dw1[23:16];
        3'd2: obff_data = msg_header_r.dw3[7:0];
    endcase
    case (recv_counter)
        3'd0: unlock_data = msg_header_r.dw1[31:24];
        3'd1: unlock_data = msg_header_r.dw1[23:16];
    endcase
    case (recv_counter)
        3'd0: vd_type_data = msg_header_r.dw1[31:24];
        3'd1: vd_type_data = msg_header_r.dw1[23:16];
        3'd2: vd_type_data = msg_header_r.dw2[7:0];
        3'd3: vd_type_data = msg_header_r.dw2[15:8];
        3'd4: vd_type_data = msg_data_r[7:0];
        3'd5: vd_type_data = msg_data_r[15:8];
        3'd6: vd_type_data = msg_data_r[23:16];
        3'd7: vd_type_data = msg_data_r[31:24];
    endcase
    case (recv_counter)
        3'd0: ats_data = msg_header_r.dw1[31:24];
        3'd1: ats_data = msg_header_r.dw1[23:16];
    endcase
end

generate
    if (RECV_MSG_EN) begin: recv_msg_enable
        always_ff @(posedge user_clk) begin
            recv_msg_err <= ~recv_idle & (recv_type_c == reserved);
            cfg_recv_msg.cfg_msg_received <= ~recv_idle & ~(recv_type_c == reserved);
            cfg_recv_msg.cfg_msg_received_type <= recv_type_c;
            case (recv_type_c)
                err_cor, err_nonfatal, err_fatal:                      cfg_recv_msg.cfg_msg_received_data <= err_data;
                err_assert_inta, err_deassert_inta, err_assert_intb, err_deassert_intb, err_assert_intc, err_deassert_intc, err_assert_intd, err_deassert_intd: cfg_recv_msg.cfg_msg_received_data <= intx_data;
                pm_pme, pme_to_ack, pme_turn_off, pm_active_state_nak: cfg_recv_msg.cfg_msg_received_data <= pm_data;
                set_slot_power_limit:                                  cfg_recv_msg.cfg_msg_received_data <= sspl_data;
                ltr:                                                   cfg_recv_msg.cfg_msg_received_data <= ltr_data;
                obff:                                                  cfg_recv_msg.cfg_msg_received_data <= obff_data;
                unlock:                                                cfg_recv_msg.cfg_msg_received_data <= unlock_data;
                vendor_defined_type0, vendor_defined_type1:            cfg_recv_msg.cfg_msg_received_data <= vd_type_data;
                ats_invalid_request, ats_invalid_completion, ats_page_request, ats_prg_response: cfg_recv_msg.cfg_msg_received_data <= ats_data;
                default:                                               cfg_recv_msg.cfg_msg_received_data <= 0;
            endcase
            if (user_rst) begin
                recv_msg_err <= 0;
                cfg_recv_msg.cfg_msg_received <= 0;
            end
        end
    end else begin: recv_msg_disable
        assign recv_msg_err = 0;
        assign cfg_recv_msg.cfg_msg_received = 0;
        assign cfg_recv_msg.cfg_msg_received_type = 0;
        assign cfg_recv_msg.cfg_msg_received_data = 0;
    end
endgenerate

always_ff @(posedge user_clk) begin
    if (user_rst) begin
        recv_idle <= 1;
    end else if (recv_idle) begin
        if (msg_vld)
            recv_idle <= 0;
    end else begin
        case (recv_type_c)
            err_cor, err_nonfatal, err_fatal: begin
                if (recv_counter == 1) recv_idle <= 1;
            end
            err_assert_inta, err_deassert_inta, err_assert_intb, err_deassert_intb, err_assert_intc, err_deassert_intc, err_assert_intd, err_deassert_intd: begin
                if (recv_counter == 1) recv_idle <= 1;
            end
            pm_pme, pme_to_ack, pme_turn_off, pm_active_state_nak: begin
                if (recv_counter == 1) recv_idle <= 1;
            end
            set_slot_power_limit: begin
                if (recv_counter == 5) recv_idle <= 1;
            end
            ltr: begin
                if (recv_counter == 5) recv_idle <= 1;
            end
            obff: begin
                if (recv_counter == 2) recv_idle <= 1;
            end
            unlock: begin
                if (recv_counter == 1) recv_idle <= 1;
            end
            vendor_defined_type0, vendor_defined_type1: begin
                if (msg_with_data_r) begin
                    if (recv_counter == 7) recv_idle <= 1;
                end else begin
                    if (recv_counter == 3) recv_idle <= 1;
                end
            end
            ats_invalid_request, ats_invalid_completion, ats_page_request, ats_prg_response: begin
                if (recv_counter == 1) recv_idle <= 1;
            end
            reserved: begin
                if (recv_counter == 0) recv_idle <= 1;
            end
        endcase
    end
end

always_ff @(posedge user_clk) begin
    if (recv_idle) begin
        msg_header_r <= msg_header;
        msg_data_r <= msg_data;
        msg_with_data_r <= msg_header.dw0[30];
        recv_counter <= 0;
    end else begin
        recv_counter <= recv_counter + 1;
    end
end

assign busy = ~recv_idle;

endmodule
