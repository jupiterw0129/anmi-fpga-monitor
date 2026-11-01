
`timescale 1ns/1ps
module jpeg_input_fifo820 #(parameter DATA_WIDTH_W = 8, 
        parameter DATA_WIDTH_R = 8, 
        parameter ADDR_WIDTH_W = 8, 
        parameter ADDR_WIDTH_R = 8, 
        parameter AL_FULL_NUM = 8, 
        parameter AL_EMPTY_NUM = 8, 
        parameter SHOW_AHEAD_EN = 1'b0, 
        parameter //SHOWAHEAD mode enable
        OUTREG_EN //OUTREG, NOREG
         = "NOREG") (
    //independent clock mode,fixed as asynchronous reset
    input rst,  //asynchronous port,active hight
    input clkw,  //write clock
    input clkr,  //read clock
    input we,  //write enable,active hight
    input [(DATA_WIDTH_W - 1):0] di,  //write data
    input re,  //read enable,active hight
    output [(DATA_WIDTH_R - 1):0] dout,  //read data
    output reg valid,  //read data valid flag
    output full_flag,  //fifo full flag
    output empty_flag,  //fifo empty flag
    output afull,  //fifo almost full flag
    output aempty,  //fifo almost empty flag
    output [(ADDR_WIDTH_W - 1):0] wrusedw,  //stored data number in fifo
    output [(ADDR_WIDTH_R - 1):0] rdusedw //available data number for read      
        )  /* fehdl keep_hierarchy="true" */ ;
    //--------------------------------------------------------------------------------------------
    //-------------internal parameter and signals definition below---------------
    //--------------------------------------------------------------------------------------------
    //-------------parameter definition 
    localparam FULL_NUM = {ADDR_WIDTH_W{1'b1}} ; 
    //-------------signals definition
    reg asy_w_rst0 ; 
    reg asy_w_rst1 ; 
    reg asy_r_rst0 ; 
    reg asy_r_rst1 ; 
    reg rd_rst ; 
    reg wr_rst ; 
    wire [(ADDR_WIDTH_R - 1):0] rd_to_wr_addr ; // read address synchronized to write clock domain
    wire [(ADDR_WIDTH_W - 1):0] wr_to_rd_addr ; // write address synchronized to read clock domain
    // Registered successor avoids subtraction/carry in the RAM write enable.
    (* dont_touch="true" *) reg [ADDR_WIDTH_W-1:0] write_successor872;
    reg [(ADDR_WIDTH_W - 1):0] wr_addr ; // current write address
    reg [(ADDR_WIDTH_R - 1):0] rd_addr ; // current write address
    wire wr_en_s ; 
    wire rd_en_s ; 
    wire core_full ;
    wire core_empty ;
    reg read_present ;
    wire prefetch_ready ;
    wire [(DATA_WIDTH_R - 1):0] ram_dout ;
    reg [(ADDR_WIDTH_W - 1):0] shift_rdaddr ; 
    reg [(ADDR_WIDTH_R - 1):0] shift_wraddr ; 
    wire [(ADDR_WIDTH_W - 1):0] wr_addr_diff ; // the difference between read and write address(synchronized to write clock domain)
    wire [(ADDR_WIDTH_R - 1):0] rd_addr_diff ; // the difference between read and write address(synchronized to read clock domain)
    reg empty_flag_r1 ; 
    reg empty_flag_r2 ; 
    reg re_r1 ; 
    reg re_r2 ; 
    //--------------------------------------------------------------------------------------------
    //--------------------fuctional codes below---------------------------------
    //--------------------------------------------------------------------------------------------
    // =============================================
    // reset control logic below;
    // =============================================
    //Asynchronous reset synchronous release on the write side
    always
        @(posedge clkw or 
            posedge rst)
        begin
            if (rst) 
                begin
                    asy_w_rst0 <=  1'b1 ;
                    asy_w_rst1 <=  1'b1 ;
                end
            else
                begin
                    asy_w_rst0 <=  1'b0 ;
                    asy_w_rst1 <=  asy_w_rst0 ;
                end
        end
    //Asynchronous reset synchronous release on the read side
    always
        @(posedge clkr or 
            posedge rst)
        begin
            if (rst) 
                begin
                    asy_r_rst0 <=  1'b1 ;
                    asy_r_rst1 <=  1'b1 ;
                end
            else
                begin
                    asy_r_rst0 <=  1'b0 ;
                    asy_r_rst1 <=  asy_r_rst0 ;
                end
        end
    always @(posedge clkr)
        rd_rst <= asy_r_rst1;
    always @(posedge clkw)
        wr_rst <= asy_w_rst1;
    // =============================================
    // address generate logic below;
    // =============================================
    // write and read ram enable
    assign wr_en_s = ((!core_full) & we & (!wr_rst)) ; 
    // This dedicated instance supports equal-width FWFT/NOREG only.
    // Pointer credit moves only when the consumer accepts advertised data.
    assign rd_en_s = re && !rd_rst && read_present;
    (* dont_touch="true" *) reg read_request;
    (* dont_touch="true" *) reg [ADDR_WIDTH_R-1:0] fetch_address;
    initial begin
        if(!SHOW_AHEAD_EN || OUTREG_EN!="NOREG" ||
           ADDR_WIDTH_R!=ADDR_WIDTH_W || DATA_WIDTH_R!=DATA_WIDTH_W)
            $fatal(1,"FIFO820 requires equal-width FWFT/NOREG");
    end
    wire [ADDR_WIDTH_R-1:0] next_read_address=rd_addr+1'b1;
    wire [ADDR_WIDTH_R-1:0] requested_address=rd_en_s ? next_read_address : rd_addr;
    wire available_now=shift_wraddr!=rd_addr;
    // A request is registered before reaching RAM address/chip-select inputs.
    // The output slot is reserved until its read completes and is consumed.
    // At most one RAM read is pending; two clocks per group suffice for the
    // downstream four-clock RGB4 consumer.
    assign prefetch_ready=!rd_rst && !read_request &&
        (!read_present || rd_en_s) && shift_wraddr!=requested_address;
    always @(posedge clkr)begin
        if(rd_rst)begin
            read_request<=0;fetch_address<=0;read_present<=0;
        end else begin
            read_request<=prefetch_ready;
            // Address may track continuously; registered read_request alone
            // selects the matching old address at the following RAM edge.
            fetch_address<=requested_address;
            if(read_request)read_present<=1;
            else if(rd_en_s)read_present<=0;
        end
    end
    // Data is unspecified while empty/reset; empty_flag/valid retain reset
    // gating. Keep reset out of the RAM-data path into the reserved slot.
    assign dout = ram_dout;
    always @(posedge clkw)begin
        if(wr_rst)write_successor872<=1;
        else if(wr_en_s)write_successor872<=write_successor872+1'b1;
    end
    // generate write fifo address
    always
        @(posedge clkw)
        begin
            if ((wr_rst == 1'b1)) 
                wr_addr <=  'b0 ;
            else
                if (wr_en_s) 
                    wr_addr <=  (wr_addr + 1) ;
        end
    // generate rd fifo address
    always
        @(posedge clkr)
        begin
            if ((rd_rst == 1'b1)) 
                rd_addr <=  'b0 ;
            else
                if (rd_en_s) 
                    rd_addr <=  (rd_addr + 1) ;
        end
    always
        @(*)
        begin
            if ((ADDR_WIDTH_R >= ADDR_WIDTH_W)) 
                begin
                    shift_rdaddr = (rd_to_wr_addr >> (ADDR_WIDTH_R - ADDR_WIDTH_W)) ;
                    shift_wraddr = (wr_to_rd_addr << (ADDR_WIDTH_R - ADDR_WIDTH_W)) ;
                end
            else
                begin
                    shift_rdaddr = (rd_to_wr_addr << (ADDR_WIDTH_W - ADDR_WIDTH_R)) ;
                    shift_wraddr = (wr_to_rd_addr >> (ADDR_WIDTH_W - ADDR_WIDTH_R)) ;
                end
        end
    // two's complement format
    assign wr_addr_diff = (wr_addr - shift_rdaddr) ; // the count of data writen to fifo
    assign rd_addr_diff = (shift_wraddr - rd_addr) ; // the count of data available for read
    // =============================================
    // generate all output flag and count below;
    // ============================================= 
    // generate fifo full_flag indicator
    // Equal-width FIFO reserves one address: full iff write+1 == synced read.
    assign core_full = write_successor872 == shift_rdaddr; 
    assign full_flag = core_full;
    // generate fifo afull indicator
    assign afull = ((wr_addr_diff >= AL_FULL_NUM) ? 1'b1 : 1'b0) ; 
    // generate fifo empty_flag indicator
    assign core_empty = !available_now; 
    assign empty_flag = rd_rst | !read_present;
    // generate fifo aempty indicator
    assign aempty = ((rd_addr_diff <= AL_EMPTY_NUM) ? 1'b1 : 1'b0) ; 
    // the count of data writen to fifo 
    assign wrusedw = wr_addr_diff ; 
    // the count of data available for read
    assign rdusedw = rd_addr_diff ; 
    // delay empty_flag for 2cycle
    always
        @(posedge clkr)
        begin
            if ((rd_rst == 1'b1)) 
                begin
                    empty_flag_r1 <=  1'b1 ;
                    empty_flag_r2 <=  1'b1 ;
                end
            else
                begin
                    empty_flag_r1 <=  empty_flag ;
                    empty_flag_r2 <=  empty_flag_r1 ;
                end
        end
    // delay rd_en_s for 2cycle
    always
        @(posedge clkr)
        begin
            if ((rd_rst == 1'b1)) 
                begin
                    re_r1 <=  1'b0 ;
                    re_r2 <=  1'b0 ;
                end
            else
                begin
                    re_r1 <=  rd_en_s ;
                    re_r2 <=  re_r1 ;
                end
        end
    // generate data output valid flag
    always
        @(*)
        begin
            if ((SHOW_AHEAD_EN && (OUTREG_EN == "NOREG"))) 
                valid = (!empty_flag) ;
            else
                if (((!SHOW_AHEAD_EN) && (OUTREG_EN == "OUTREG"))) 
                    valid = (re_r2 & (!empty_flag_r2)) ;
                else
                    valid = (re_r1 & (!empty_flag_r1)) ;
        end
    // =============================================
    // instance logic below;
    // =============================================
    // fifo read address synchronous to write clock domain using gray code
    fifo_cross_domain_addr_process_al_0322d65db018 #(.ADDR_WIDTH(ADDR_WIDTH_R)) rd_to_wr_cross_inst (.primary_asreset_i(asy_r_rst1), 
                .secondary_asreset_i(wr_rst), 
                .primary_clk_i(clkr), 
                .secondary_clk_i(clkw), 
                .primary_addr_i(rd_addr), 
                .secondary_addr_o(rd_to_wr_addr)) ; 
    // fifo write address synchronous to read clock domain using gray code
    fifo_cross_domain_addr_process_al_0322d65db018 #(.ADDR_WIDTH(ADDR_WIDTH_W)) wr_to_rd_cross_inst (.primary_asreset_i(asy_w_rst1), 
                .secondary_asreset_i(rd_rst), 
                .primary_clk_i(clkw), 
                .secondary_clk_i(clkr), 
                .primary_addr_i(wr_addr), 
                .secondary_addr_o(wr_to_rd_addr)) ; 
    ram_infer_0322d65db018 #(.DATAWIDTH_A(DATA_WIDTH_W),
            .ADDRWIDTH_A(ADDR_WIDTH_W),
            .DATAWIDTH_B(DATA_WIDTH_R),
            .ADDRWIDTH_B(ADDR_WIDTH_R),
            .MODE("SDP"),
            .REGMODE_B(OUTREG_EN),
            .RESETMODE_A("NONE"),
            .RESETMODE_B("NONE")) ram_inst (.clka(clkw), 
                .rsta(wr_rst), 
                .cea(1'b1), 
                .wea(wr_en_s), 
                .ocea(1'b0), 
                .dia(di), 
                .addra(wr_addr), 
                .clkb(clkr), 
                .rstb(rd_rst), 
                .ceb(read_request),
                .web(1'b0), 
                .oceb(1'b1), 
                .addrb(fetch_address), 
                .dob(ram_dout)) ; 
endmodule
