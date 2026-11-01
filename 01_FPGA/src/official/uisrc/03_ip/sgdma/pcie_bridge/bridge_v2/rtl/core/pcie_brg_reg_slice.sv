module pcie_brg_reg_slice #(
    parameter MODE = "FWD",// "FWD", "BWD", "FUL", "BYP"
    parameter WIDTH = 1
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             src_vld,
    output logic             src_rdy,
    input  logic [WIDTH-1:0] src_pld,
    output logic             dst_vld,
    input  logic             dst_rdy,
    output logic [WIDTH-1:0] dst_pld
);

generate
    if (MODE == "FWD") begin: reg_slice_forward
        always_ff @(posedge clk) begin
            if (rst)
                dst_vld <= 0;
            else if (src_vld)
                dst_vld <= 1;
            else if (dst_rdy)
                dst_vld <= 0;
        end

        always_ff @(posedge clk) begin
            if (~dst_vld | dst_rdy)
                dst_pld <= src_pld;
        end

        assign src_rdy = ~dst_vld | dst_rdy;

    end else if (MODE == "BWD") begin: reg_slice_backward
        logic [WIDTH-1:0] pld_r;

        always_ff @(posedge clk) begin
            if (rst)
                src_rdy <= 1;
            else if (dst_rdy)
                src_rdy <= 1;
            else if (src_vld)
                src_rdy <= 0;
        end

        always_ff @(posedge clk) begin
            if (src_rdy)
                pld_r <= src_pld;
        end

        assign dst_vld = ~src_rdy | src_vld;
        assign dst_pld = src_rdy ? src_pld : pld_r;

    end else if (MODE == "FUL") begin: reg_slice_full
        logic vld_int;
        logic rdy_int;
        logic [WIDTH-1:0] pld_int;

        pcie_brg_reg_slice #(
            .MODE("BWD"),
            .WIDTH(WIDTH)
        ) reg_slice_bwd(
            .clk(clk),
            .rst(rst),
            .src_vld(src_vld),
            .src_rdy(src_rdy),
            .src_pld(src_pld),
            .dst_vld(vld_int),
            .dst_rdy(rdy_int),
            .dst_pld(pld_int)
        );

        pcie_brg_reg_slice #(
            .MODE("FWD"),
            .WIDTH(WIDTH)
        ) reg_slice_fwd(
            .clk(clk),
            .rst(rst),
            .src_vld(vld_int),
            .src_rdy(rdy_int),
            .src_pld(pld_int),
            .dst_vld(dst_vld),
            .dst_rdy(dst_rdy),
            .dst_pld(dst_pld)
        );

    end else begin: reg_slice_bypass
        assign src_rdy = dst_rdy;
        assign dst_vld = src_vld;
        assign dst_pld = src_pld;

    end
endgenerate


endmodule
