//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_reset_sync.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2025-09-01 17:12:32
//  Create        : 2022-06-02 14:50:26
//  Description   :
//                  pcie reset sync logic
///////////////////////////////////////////////////////////////


`resetall

module ph2_pcie_rst_sync#(
    parameter   LTSSM_VAULE = 6'h10
)(
    input   wire                clk         ,
    input   wire                rst         ,
    input   wire    [5:0]       tl_ltssm    ,
    input   wire                pl_link_up  ,
    output  wire                rstn_sync
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================
    reg         pl_link_up_dly;
    reg [5:0]   tl_ltssm_dly;
    reg [10:0]  rst_dly;
    reg         rst_d1;
    reg         rst_d2;



// ====================================================================
// Main Code
// ====================================================================

always@(posedge clk or posedge rst)
begin
    if(rst) begin
        pl_link_up_dly <= 1'b0;
        tl_ltssm_dly   <= 6'd0;
    end else begin
        pl_link_up_dly <= pl_link_up;
        tl_ltssm_dly   <= tl_ltssm;
    end
end

// delay time for link negotiation is turely finish, in some situation,
// the pl_link and tl_ltssm meet the conditicons at the same time in
// only few cycle, bucause the link speed change.
always@(posedge clk or posedge rst)
begin
    if(rst)
       rst_dly <= 11'd0;
    else if( pl_link_up_dly == 1'b1 && tl_ltssm_dly == LTSSM_VAULE  )
       rst_dly <= (rst_dly[10] == 1'b0) ? rst_dly + 1'b1 : rst_dly;
    else
       rst_dly <= 11'd0;
end


// async rst , sync release
always@(posedge clk or posedge rst)
begin
    if(rst) begin
        rst_d1 <= 1'b0;
        rst_d2 <= 1'b0;
    end else begin
        rst_d1 <= rst_dly[10];
        rst_d2 <= rst_d1;
    end
end

assign  rstn_sync = rst_d2;

/*synthesis translate_off*/
initial begin
    forever begin
        @(posedge rst_dly[10])
            $display("%0t logic info : ph2 pcie has link up", $realtime);
    end
    forever begin
        @(posedge rst)
            $display("%0t logic info : ph2 pcie has rst", $realtime);
    end
end
/*synthesis translate_on*/

endmodule
