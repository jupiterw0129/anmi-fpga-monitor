`include "pcie_brg_def.svh"

module pcie_brg_cfg_mgmt#(
    parameter SYNC_CLOCK = 1,
    parameter PF_NUM = 4,
    parameter VF_NUM = 252,
    parameter EP_MODE = 1
) (
    input logic user_clk,
    input logic user_rst,
    input logic core_clk,
    input logic core_rst,

    cfg_mgmt_if.slv cfg_mgmt,
    core_tl_cfg_if.mst core_tl_cfg
);

localparam K_SPACE   = 32'h1000;
localparam K_STRIDE  = 288;
localparam PF_SPACE  = 32'h4000;
localparam VF_SPACE  = 32'h8000;
localparam PF_STRIDE = 32'h1000;
localparam VF_STRIDE = 32'h10;
localparam TYPE1_RO_ADDR = PF_SPACE;// type 1 read-only address

logic [9:0] cfg_mgmt_addr;
logic [7:0] cfg_mgmt_function_number;
logic cfg_mgmt_write;
logic [31:0] cfg_mgmt_write_data;
logic [3:0] cfg_mgmt_byte_enable;
logic cfg_mgmt_read;
logic cfg_mgmt_debug_access;

logic [31:0] cfg_addr;
logic [31:0] cfg_addr_d1;
logic [31:0] cfg_addr_k;
logic [31:0] cfg_addr_pf;
logic [31:0] cfg_addr_vf;
logic        cfg_addr_hit;
logic [11:0] cfg_k_mask;
logic [11:0] cfg_pf_mask;
logic [11:0] cfg_vf_mask;

assign cfg_k_mask  = 12'h1ff;
assign cfg_pf_mask = 12'hfff;
assign cfg_vf_mask = 12'hf;

always_ff @(posedge core_clk) begin
    cfg_addr_d1 <= cfg_addr;
end

integer i0;
always_comb begin
    cfg_addr_k = 0;
    for (i0=0; i0<PF_NUM; i0=i0+1) begin
        if (cfg_mgmt_function_number == i0)
            cfg_addr_k = K_SPACE+i0*K_STRIDE+({cfg_mgmt_addr, 2'b0} & cfg_k_mask);
    end
end

integer i1;
always_comb begin
    cfg_addr_pf = 0;
    for (i1=0; i1<PF_NUM; i1=i1+1) begin
        if (cfg_mgmt_function_number == i1)
            cfg_addr_pf = PF_SPACE+i1*PF_STRIDE+({cfg_mgmt_addr, 2'b0} & cfg_pf_mask);
    end
end

integer i2;
always_comb begin
    cfg_addr_vf = 0;
    for (i2=0; i2<VF_NUM; i2=i2+1) begin
        if ((cfg_mgmt_function_number - PF_NUM) == i2)
            cfg_addr_vf = VF_SPACE+i2*VF_STRIDE+({cfg_mgmt_addr, 2'b0} & cfg_vf_mask);
    end
end

always_comb begin
    cfg_addr_hit = 0;
    cfg_addr = 0;
    if (cfg_mgmt_debug_access) begin
        if (EP_MODE) begin
            cfg_addr_hit = 0;
        end else begin
            cfg_addr_hit = (cfg_mgmt_function_number < PF_NUM) & ({cfg_mgmt_addr, 2'b0} < K_STRIDE);
            cfg_addr = cfg_addr_k;
        end
    end else if (cfg_mgmt_function_number < PF_NUM) begin
        cfg_addr_hit = {cfg_mgmt_addr, 2'b0} < PF_STRIDE;
        cfg_addr = cfg_addr_pf;
    end else if (cfg_mgmt_function_number < (PF_NUM+VF_NUM)) begin
        cfg_addr_hit = {cfg_mgmt_addr, 2'b0} < VF_STRIDE;
        cfg_addr = cfg_addr_vf;
    end
end

localparam CFG_IDLE = 2'h0;
localparam CFG_SETUP = 2'h1;
localparam CFG_ACCESS = 2'h2;
localparam CFG_DROP = 2'h3;

logic [1:0] cfg_state, cfg_nstate;
logic cfg_mgmt_read_write;

always_ff @(posedge core_clk) begin
    if (core_rst)
        cfg_state <= CFG_IDLE;
    else
        cfg_state <= cfg_nstate;
end

always_comb begin
    cfg_nstate = cfg_state;
    case (cfg_state)
        CFG_IDLE: begin
            if (cfg_mgmt_read_write)
                cfg_nstate = cfg_addr_hit ? CFG_SETUP : CFG_DROP;
        end
        CFG_SETUP: begin
            cfg_nstate = CFG_ACCESS;
        end
        CFG_ACCESS: begin
            if (core_tl_cfg.tl_cfg_pready)
                cfg_nstate = CFG_IDLE;
        end
        CFG_DROP: begin
            cfg_nstate = CFG_IDLE;
        end
    endcase
end

assign core_tl_cfg.tl_cfg_prst = core_rst;
assign core_tl_cfg.tl_cfg_penable = cfg_state == CFG_ACCESS;
assign core_tl_cfg.tl_cfg_psel = (cfg_state == CFG_SETUP) | (cfg_state == CFG_ACCESS);
assign core_tl_cfg.tl_cfg_pwrite = cfg_mgmt_write;
assign core_tl_cfg.tl_cfg_pprot = 0;
assign core_tl_cfg.tl_cfg_paddr = cfg_addr_d1;
assign core_tl_cfg.tl_cfg_pstrb = cfg_mgmt_byte_enable;
assign core_tl_cfg.tl_cfg_pwdata = cfg_mgmt_write_data;

generate
    if (SYNC_CLOCK) begin: cfg_no_cdc

        assign cfg_mgmt_addr = cfg_mgmt.cfg_mgmt_addr;
        assign cfg_mgmt_function_number = cfg_mgmt.cfg_mgmt_function_number;
        assign cfg_mgmt_write = cfg_mgmt.cfg_mgmt_write;
        assign cfg_mgmt_write_data = cfg_mgmt.cfg_mgmt_write_data;
        assign cfg_mgmt_byte_enable = cfg_mgmt.cfg_mgmt_byte_enable;
        assign cfg_mgmt_read = cfg_mgmt.cfg_mgmt_read;
        assign cfg_mgmt_debug_access = cfg_mgmt.cfg_mgmt_debug_access;
        assign cfg_mgmt_read_write = cfg_mgmt_write | cfg_mgmt_read;

        always_ff @(posedge user_clk) begin
            if (user_rst) begin
                cfg_mgmt.cfg_mgmt_read_write_done <= 0;
            end else begin
                cfg_mgmt.cfg_mgmt_read_write_done <= (core_tl_cfg.tl_cfg_penable & core_tl_cfg.tl_cfg_pready) | (cfg_state == CFG_DROP);
            end
            if (core_tl_cfg.tl_cfg_penable & core_tl_cfg.tl_cfg_pready) begin
                cfg_mgmt.cfg_mgmt_read_data <= core_tl_cfg.tl_cfg_prdata;
            end
        end

    end else begin: cfg_cdc

        logic cfg_mgmt_send;
        logic cfg_mgmt_req;
        logic cfg_mgmt_req_d1;
        logic tl_cfg_send;
        logic tl_cfg_req;
        logic tl_cfg_req_d1;
        logic [31:0] core_tl_cfg_prdata;

        assign cfg_mgmt_read_write = cfg_mgmt_req & ~cfg_mgmt_req_d1;

        always_ff @(posedge user_clk) begin
            if (user_rst)
                cfg_mgmt_send <= 0;
            else if ((cfg_mgmt.cfg_mgmt_write | cfg_mgmt.cfg_mgmt_read) & ~tl_cfg_req)
                cfg_mgmt_send <= 1;
            else if (tl_cfg_req)
                cfg_mgmt_send <= 0;
        end

        always_ff @(posedge core_clk) begin
            if (core_rst)
                tl_cfg_send <= 0;
            else if ((core_tl_cfg.tl_cfg_penable & core_tl_cfg.tl_cfg_pready) | (cfg_state == CFG_DROP))
                tl_cfg_send <= 1;
            else if (~cfg_mgmt_req)
                tl_cfg_send <= 0;
        end

        always_ff @(posedge user_clk) begin
            if (user_rst)
                cfg_mgmt.cfg_mgmt_read_write_done <= 0;
            else
                cfg_mgmt.cfg_mgmt_read_write_done <= tl_cfg_req & ~tl_cfg_req_d1;
        end

        always_ff @(posedge core_clk) begin
            cfg_mgmt_req_d1 <= cfg_mgmt_req;
        end

        always_ff @(posedge user_clk) begin
            tl_cfg_req_d1 <= tl_cfg_req;
        end

        always_ff @(posedge core_clk) begin
            if (core_tl_cfg.tl_cfg_penable & core_tl_cfg.tl_cfg_pready)
                core_tl_cfg_prdata <= core_tl_cfg.tl_cfg_prdata;
        end

        pcie_brg_cdc_handshake #(
            .WIDTH(10+8+1+32+4+1+1)
        ) cdc_cfg_mgmt(
            .src_clk(user_clk),
            .src_in({cfg_mgmt.cfg_mgmt_addr, cfg_mgmt.cfg_mgmt_function_number, cfg_mgmt.cfg_mgmt_write, cfg_mgmt.cfg_mgmt_write_data, cfg_mgmt.cfg_mgmt_byte_enable, cfg_mgmt.cfg_mgmt_read, cfg_mgmt.cfg_mgmt_debug_access}),
            .src_send(cfg_mgmt_send),
            .src_recv(),

            .dst_clk(core_clk),
            .dst_out({cfg_mgmt_addr, cfg_mgmt_function_number, cfg_mgmt_write, cfg_mgmt_write_data, cfg_mgmt_byte_enable, cfg_mgmt_read, cfg_mgmt_debug_access}),
            .dst_req(cfg_mgmt_req),
            .dst_ack()
        );

        pcie_brg_cdc_handshake #(
            .WIDTH(32)
        ) cdc_tl_cfg(
            .src_clk(core_clk),
            .src_in(core_tl_cfg_prdata),
            .src_send(tl_cfg_send),
            .src_recv(),

            .dst_clk(user_clk),
            .dst_out(cfg_mgmt.cfg_mgmt_read_data),
            .dst_req(tl_cfg_req),
            .dst_ack()
        );

    end
endgenerate

endmodule
