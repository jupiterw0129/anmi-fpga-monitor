module pcie_brg_bdf_enc#(
    parameter CFG_PF_NUM = 4,
    parameter CORE_PF_NUM = 4
) (
    input  logic ari_cap,
    input  logic [7:0] bus_num,
    input  logic [4:0] dev_num,
    input  logic [7:0] func_num,
    output logic [15:0] bdf_num
);

logic func_pf;
logic [7:0] pf_id;
logic [7:0] vf_id;

assign func_pf = func_num < CFG_PF_NUM;
assign pf_id = func_num;
assign vf_id = func_num - CFG_PF_NUM;

always_comb begin
    bdf_num = 0;
    if (func_pf) begin
        bdf_num = {bus_num, pf_id};
    end else begin
        if (~ari_cap | (CORE_PF_NUM > 128))
            bdf_num = bus_num*256+vf_id+256;
        else if (CORE_PF_NUM <= 8)
            bdf_num = bus_num*256+vf_id+8;
        else if (CORE_PF_NUM <= 32)
            bdf_num = bus_num*256+vf_id+32;
        else if (CORE_PF_NUM <= 64)
            bdf_num = bus_num*256+vf_id+64;
        else
            bdf_num = bus_num*256+vf_id+128;
    end
end

endmodule
