module pcie_brg_bdf_dec#(
    parameter CFG_PF_NUM = 4,
    parameter CORE_PF_NUM = 4
) (
    input  logic ari_cap,
    input  logic [7:0] bus_num,
    input  logic [4:0] dev_num,
    input  logic [15:0] bdf_num,
    output logic [7:0] func_num
);

logic func_pf;
logic [7:0] pf_id;
logic [7:0] vf_id;

assign func_pf = bdf_num[7:0] < CFG_PF_NUM;
assign pf_id = bdf_num[7:0];

always_comb begin
    func_num = 0;
    vf_id = 0;
    if (func_pf) begin
        func_num = pf_id;
    end else begin
        if (~ari_cap | (CORE_PF_NUM > 128)) begin
            vf_id = bdf_num-bus_num*256-256;
            func_num = CFG_PF_NUM+vf_id;
        end else if (CORE_PF_NUM <= 8) begin
            vf_id = bdf_num-bus_num*256-8;
            func_num = CFG_PF_NUM+vf_id;
        end else if (CORE_PF_NUM <= 32) begin
            vf_id = bdf_num-bus_num*256-32;
            func_num = CFG_PF_NUM+vf_id;
        end else if (CORE_PF_NUM <= 64) begin
            vf_id = bdf_num-bus_num*256-64;
            func_num = CFG_PF_NUM+vf_id;
        end else begin
            vf_id = bdf_num-bus_num*256-128;
            func_num = CFG_PF_NUM+vf_id;
        end
    end
end

endmodule
