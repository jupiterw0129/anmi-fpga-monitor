
`timescale 1ns/1ps
/*===========================================*\
Filename        :sgdma_subsys.v
Project name    :sgdma_subsys_tst
Description     :      sgdma ip   pcie_phy
Called by       :sgdma_subsys_tst.v
Email           :bingsong.wang@anlogic.com
Modified        :v1.0          2021-03-19
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/
module usr_axi4st_lp#(
    parameter   DLY         = 1,
    parameter   ODATA_WIDTH = 128, 
    parameter   OKEEP_WIDTH = ODATA_WIDTH/8, 
    parameter   ONBYTE_WIDTH= $clog2(OKEEP_WIDTH)
    )(
    input   wire    usr_rst_n,
    input   wire    usr_clk,
    // input   wire    s0_axis_c2h_run_i,
    // input   wire    m0_axis_h2c_run_i,

    output  wire    fifo_rdy_o,
    input   wire    fifo_we_i,
    input   wire    [ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1-1:0]  fifo_di_i,
    
    output  wire    fifo_valid_o,
    input   wire    fifo_re_i,
    output  wire    [ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1-1:0]  fifo_dout_o
);
localparam PKT_FIFO_DATA_WIDTH = ODATA_WIDTH+OKEEP_WIDTH+OKEEP_WIDTH+1;
localparam PKT_FIFO_ADDR_WIDTH = 4 ;//$clog2(64*1024/OKEEP_WIDTH)
localparam AL_FULL_NUM         = 8 ;
localparam PKT_FIFO_NUM        = 1 ;//1;//64*1024/(OKEEP_WIDTH*512);

(*max_fanout = 20*)reg  [3:0]                     pkt_fifo_rst;
generate begin : APP_LP_FIFO_BLK
    genvar i;
    reg     [PKT_FIFO_NUM-1:0]          fifo_we;
    reg     [PKT_FIFO_NUM-1:0]          fifo_we_pipe;

    reg     [PKT_FIFO_NUM-1:0]          fifo_we_pipe1;
    reg     [PKT_FIFO_DATA_WIDTH-1:0]   fifo_di_pipe1 [PKT_FIFO_NUM-1:0];

    reg     [PKT_FIFO_DATA_WIDTH-1:0]   fifo_di [PKT_FIFO_NUM-1:0];
    reg     [PKT_FIFO_DATA_WIDTH-1:0]   fifo_di_pipe [PKT_FIFO_NUM-1:0];
    reg     [PKT_FIFO_NUM-1:0]          fifo_re;
    wire    [PKT_FIFO_NUM-1:0]          fifo_valid;
    wire    [PKT_FIFO_NUM-1:0]          fifo_afull_flag;
    wire    [PKT_FIFO_NUM-1:0]          fifo_full_flag;
    wire    [PKT_FIFO_DATA_WIDTH-1:0]   fifo_dout [PKT_FIFO_NUM-1:0];
    assign  fifo_dout_o = fifo_dout[PKT_FIFO_NUM-1];
    assign  fifo_valid_o= fifo_valid[PKT_FIFO_NUM-1];
    assign  fifo_rdy_o  = !fifo_afull_flag[0];

    for(i=0;i<PKT_FIFO_NUM;i=i+1) begin : FIFO_LOOP_BLK
        sfifo #(
            .RESOURCE_TYPE      ("dram"),//bram(high_speed)
            .DATA_WIDTH_W       ( PKT_FIFO_DATA_WIDTH ),
            .DATA_WIDTH_R       ( PKT_FIFO_DATA_WIDTH ),
            .ADDR_WIDTH_W       ( PKT_FIFO_ADDR_WIDTH ),
            .ADDR_WIDTH_R       ( PKT_FIFO_ADDR_WIDTH ),
            .AL_FULL_NUM        ( AL_FULL_NUM         ), 
            .SHOW_AHEAD_EN      ( 1                   )
        ) u_pkt_fifo(
            .rst                (pkt_fifo_rst[3]),  //asynchronous port,active hight
            .clk                (usr_clk        ),  //common clock for write and read
            .we                 (fifo_we_pipe1[i]),  //write enable,active hight
            .di                 (fifo_di_pipe1[i]),  //write data
            .re                 (fifo_re[i]     ),  //read enable,active hight
            .dout               (fifo_dout[i]   ),  //read data
            .valid              (fifo_valid[i]  ),  //read data valid flag
            .full_flag          (fifo_full_flag[i]),  //fifo full flag
            .empty_flag         (),  //fifo empty flag
            .afull              (fifo_afull_flag[i]),  //fifo almost full flag
            .aempty             (),  //fifo almost empty flag
            .wrusedw            (),  //stored data number in fifo
            .rdusedw            ()//available data number for read
            );

        always @(posedge usr_clk or negedge usr_rst_n) begin
            if (!usr_rst_n)
                fifo_we[i]  <= 1'b0;
            else 
                fifo_we[i]  <= (i==0) ? fifo_we_i : fifo_re[i-1];
        end 
        always @(posedge usr_clk or negedge usr_rst_n) begin
            if (!usr_rst_n)
                fifo_di[i]  <= 'b0;
            else 
                fifo_di[i]  <= (i==0) ? fifo_di_i : fifo_dout[i-1];
        end 

        always @(posedge usr_clk ) begin
            fifo_we_pipe[i] <= fifo_we[i];
            fifo_di_pipe[i] <= fifo_di[i];

            fifo_we_pipe1[i] <= fifo_we_pipe[i];
            fifo_di_pipe1[i] <= fifo_di_pipe[i];            
        end        

        always @(*) begin
            if (!usr_rst_n)
                fifo_re[i]  = 'b0;
            else 
                fifo_re[i]  = (i==PKT_FIFO_NUM-1) ? (fifo_re_i & fifo_valid[PKT_FIFO_NUM-1]) : (fifo_valid[i] && !fifo_afull_flag[i+1]);
        end  

    end 
end 
endgenerate

always @(posedge usr_clk or negedge usr_rst_n) begin
    if (!usr_rst_n)
        pkt_fifo_rst <= 4'b1111;
    else 
        pkt_fifo_rst <= {pkt_fifo_rst[2:0],1'b0};
end 

endmodule
