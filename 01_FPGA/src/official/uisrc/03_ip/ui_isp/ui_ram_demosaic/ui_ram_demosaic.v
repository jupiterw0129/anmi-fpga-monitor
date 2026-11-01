
`timescale 1ns/1ps
// ===========================================================================
// $Version    : v0.1
// $Date       : 2022/07/11
// $Description: top of Embedded RAM/ROM IP code 
// ===========================================================================
//************************************************************
module ui_ram_demosaic (
    //Dual port RAM
    input clka, 
    input [(1 - 1):0] wea, 
    input [(33 - 1):0] dia, 
    input [(11 - 1):0] addra, 
    output [(33 - 1):0] doa, 
    // port B
    input clkb, 
    input [(1 - 1):0] web, 
    input [(33 - 1):0] dib, 
    input [(11 - 1):0] addrb, 
    output [(33 - 1):0] dob)  /* fehdl keep_hierarchy=true */ ;
    //--------------------------------------------------------------------------------------------
    //-------------internal parameter and signals definition below---------------
    //--------------------------------------------------------------------------------------------
    //-------------parameter definition 
    //-------------signals definition
    //--------------------------------------------------------------------------------------------
    //--------------------fuctional codes below---------------------------------
    //--------------------------------------------------------------------------------------------
    //not at ecc mode, inst <USERNAME>_eram_infter.v
    ui_ram_demosaic_eram_infer #(.MODE("SDP"),
            .BYTE_SIZE(1),
            .INIT_FILE("NONE"),
            .FILL_REMAIN(0),
            .USE_BYTE_WEA(0),
            .DATAWIDTH_A(33),
            .WEA_WIDTH(1),
            .REGMODE_A("NOREG"),
            .WRITEMODE_A("WRITETHROUGH"),
            .ADDRWIDTH_A(11),
            .USE_BYTE_WEB(0),
            .DATAWIDTH_B(33),
            .WEB_WIDTH(1),
            .REGMODE_B("NOREG"),
            .WRITEMODE_B("READBEFOREWRITE"),
            .ADDRWIDTH_B(11)) inst (//single port ROM
            //True Dual port RAM
            .clka(clka), 
                .rsta(1'b0), 
                .cea(1'b1), 
                .ocea(1'b1), 
                .wea(wea), 
                .dia(dia), 
                .addra(addra), 
                .doa(doa), 
                .clkb(clkb), 
                .rstb(1'b0), 
                .ceb(1'b1), 
                .oceb(1'b1), 
                .web(web), 
                .dib(dib), 
                .addrb(addrb), 
                .dob(dob), 
                .ecc_sbiterrinj(1'b0), 
                .ecc_dbiterrinj(1'b0), 
                .ecc_pipece(1'b0), 
                .ecc_sbiterr(), 
                .ecc_dbiterr(), 
                .ecc_erraddr()) ; 
endmodule



//************************************************************
module ui_ram_demosaic_eram_infer (clka, 
        rsta, 
        cea, 
        ocea, 
        wea, 
        dia, 
        addra, 
        doa, 
        clkb, 
        rstb, 
        ceb, 
        oceb, 
        web, 
        dib, 
        addrb, 
        dob, 
        ecc_sbiterrinj, 
        ecc_dbiterrinj, 
        ecc_pipece, 
        ecc_sbiterr, 
        ecc_dbiterr, 
        ecc_erraddr) ;
    //parameter
    parameter MODE = "DP" ; //SP, SDP, DP
    parameter BYTE_SIZE = 8 ; //8, 9, 10
    parameter USE_BYTE_WEA = 0 ; //0,1, use Byte Writes or not
    parameter DATAWIDTH_A = 32 ; //A WIDTH
    parameter WEA_WIDTH = ((USE_BYTE_WEA == 0) ? 1 : (DATAWIDTH_A / BYTE_SIZE)) ; //wea port width
    parameter REGMODE_A = "NOREG" ; //OUTREG, NOREG
    parameter RESETMODE_A = "SYNC" ; //SYNC, ASYNC
    parameter INITVAL_A = {DATAWIDTH_A{1'b0}} ; //A initial value or reset value
    parameter WRITEMODE_A = "NORMAL" ; //NORMAL, WRITETHROUGH, READBEFOREWRITE
    parameter ADDRWIDTH_A = 5 ; //A ADDR WIDTH
    parameter DATADEPTH_A = (2 ** ADDRWIDTH_A) ; //A DEPTH
    parameter SSROVERCE_A = "ENABLE" ; //ENABLE, DISABLE
    parameter USE_BYTE_WEB = 0 ; //0,1, use Byte Writes or not
    parameter DATAWIDTH_B = DATAWIDTH_A ; //B WIDTH
    parameter WEB_WIDTH = ((USE_BYTE_WEB == 0) ? 1 : (DATAWIDTH_B / BYTE_SIZE)) ; //web port width
    parameter REGMODE_B = "NOREG" ; //OUTREG, NOREG
    parameter RESETMODE_B = "SYNC" ; //SYNC, ASYNC
    parameter INITVAL_B = {DATAWIDTH_B{1'b0}} ; //B initial value or reset value
    parameter WRITEMODE_B = "NORMAL" ; //NORMAL, WRITETHROUGH, READBEFOREWRITE
    parameter ADDRWIDTH_B = ADDRWIDTH_A ; //B ADDR WIDTH
    parameter DATADEPTH_B = (2 ** ADDRWIDTH_B) ; //A DEPTH
    parameter SSROVERCE_B = "ENABLE" ; //ENABLE, DISABLE
    parameter INIT_FILE = "NONE" ; //memory initialization file, can be "NONE" or surpport .dat/.txt file with binary data
    parameter FILL_REMAIN = {DATAWIDTH_A{1'b0}} ; 
    //input 
    input clka, 
        rsta, 
        cea, 
        ocea ; 
    input [(WEA_WIDTH - 1):0] wea ; 
    input [(DATAWIDTH_A - 1):0] dia ; 
    input [(ADDRWIDTH_A - 1):0] addra ; 
    input clkb, 
        rstb, 
        ceb, 
        oceb ; 
    input [(WEB_WIDTH - 1):0] web ; 
    input [(DATAWIDTH_B - 1):0] dib ; 
    input [(ADDRWIDTH_B - 1):0] addrb ; 
    input ecc_sbiterrinj ; 
    input ecc_dbiterrinj ; 
    input ecc_pipece ; 
    //output
    output [(DATAWIDTH_A - 1):0] doa ; 
    output [(DATAWIDTH_B - 1):0] dob ; 
    output ecc_sbiterr ; 
    output ecc_dbiterr ; 
    output [8:0] ecc_erraddr ; 
    // check parameters
    //integer fp;
    localparam MIN_WIDTH = ((DATAWIDTH_A > DATAWIDTH_B) ? DATAWIDTH_B : DATAWIDTH_A) ; 
    localparam MAX_DEPTH = ((DATADEPTH_A > DATADEPTH_B) ? DATADEPTH_A : DATADEPTH_B) ; 
    localparam WIDTHRATIO_A = (DATAWIDTH_A / MIN_WIDTH) ; 
    localparam WIDTHRATIO_B = (DATAWIDTH_B / MIN_WIDTH) ; 
    (* ram_style="bram(min_area)" *) reg [(MIN_WIDTH - 1):0] memory [(MAX_DEPTH - 1):0] ;  /* fehdl force_ram=1 */ 
    reg [(DATAWIDTH_A - 1):0] doa_tmp = INITVAL_A ; 
    reg [(DATAWIDTH_B - 1):0] dob_tmp = INITVAL_B ; 
    reg [(DATAWIDTH_A - 1):0] doa_tmp2 = INITVAL_A ; 
    reg [(DATAWIDTH_B - 1):0] dob_tmp2 = INITVAL_B ; 
    integer i, 
        j ; 
    //Initial value
    initial
        begin
            for (i = 0 ; (i < 128) ; i = (i + 1))
                begin
                    for (j = 0 ; (j < 8192) ; j = (j + 1))
                        begin
                            if ((((i * 8192) + j) < MAX_DEPTH)) 
                                begin
                                    memory[((i * 8192) + j)] = FILL_REMAIN ;
                                end
                            else
                                begin
                                    j = 8192 ;
                                    i = 128 ;
                                end
                        end
                end
            if ((INIT_FILE[31:0] == ".dat")) 
                $readmemb (INIT_FILE,
                        memory) ;
            else
                if ((INIT_FILE[31:0] == "dath")) 
                    $readmemh (INIT_FILE,
                            memory) ;
        end
    task  write_a(
        input reg [(ADDRWIDTH_A - 1):0] addr, 
            
        input reg [(DATAWIDTH_A - 1):0] data, 
            
        input reg [(WEA_WIDTH - 1):0] we) ; 
        integer i, 
            j ; 
        begin
            if ((USE_BYTE_WEA != 0)) 
                begin
                    for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                        begin
                            for (j = 0 ; (j < (WEA_WIDTH / WIDTHRATIO_A)) ; j = (j + 1))
                                begin
                                    if (we[(((i * WEA_WIDTH) / WIDTHRATIO_A) + j)]) 
                                        begin
                                            memory[((addr * WIDTHRATIO_A) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] <=  data[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] ;
                                        end
                                end
                        end
                end
            else
                begin
                    if (we) 
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                begin
                                    memory[((addr * WIDTHRATIO_A) + i)] <=  data[(i * MIN_WIDTH) +: MIN_WIDTH] ;
                                end
                        end
                end
        end
    endtask
    task  write_b(
        input reg [(ADDRWIDTH_B - 1):0] addr, 
            
        input reg [(DATAWIDTH_B - 1):0] data, 
            
        input reg [(WEB_WIDTH - 1):0] we) ; 
        integer i, 
            j ; 
        begin
            if ((USE_BYTE_WEB != 0)) 
                begin
                    for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                        begin
                            for (j = 0 ; (j < (WEB_WIDTH / WIDTHRATIO_B)) ; j = (j + 1))
                                begin
                                    if (we[(((i * WEB_WIDTH) / WIDTHRATIO_B) + j)]) 
                                        begin
                                            memory[((addr * WIDTHRATIO_B) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] <=  data[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] ;
                                        end
                                end
                        end
                end
            else
                begin
                    if (we) 
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                begin
                                    memory[((addr * WIDTHRATIO_B) + i)] <=  data[(i * MIN_WIDTH) +: MIN_WIDTH] ;
                                end
                        end
                end
        end
    endtask
    task  read_a(
        input reg [(ADDRWIDTH_A - 1):0] addr, 
            
        input reg [(DATAWIDTH_A - 1):0] data, 
            
        input reg [(WEA_WIDTH - 1):0] we) ; 
        integer i, 
            j ; 
        if ((USE_BYTE_WEA != 0)) 
            begin
                if ((WRITEMODE_A == "NORMAL")) 
                    begin
                        for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                            begin
                                for (j = 0 ; (j < (WEA_WIDTH / WIDTHRATIO_A)) ; j = (j + 1))
                                    begin
                                        if ((!we[(((i * WEA_WIDTH) / WIDTHRATIO_A) + j)])) 
                                            begin
                                                doa_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  memory[((addr * WIDTHRATIO_A) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] ;
                                            end
                                    end
                            end
                    end
                else
                    if ((WRITEMODE_A == "WRITETHROUGH")) 
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                begin
                                    for (j = 0 ; (j < (WEA_WIDTH / WIDTHRATIO_A)) ; j = (j + 1))
                                        begin
                                            if (we[(((i * WEA_WIDTH) / WIDTHRATIO_A) + j)]) 
                                                begin
                                                    doa_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  data[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] ;
                                                end
                                            else
                                                begin
                                                    doa_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  memory[((addr * WIDTHRATIO_A) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] ;
                                                end
                                        end
                                end
                        end
                    else
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                begin
                                    doa_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_A) + i)] ;
                                end
                        end
            end
        else
            begin
                if ((WRITEMODE_A == "NORMAL")) 
                    begin
                        if ((!we[0])) 
                            begin
                                for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                    begin
                                        doa_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_A) + i)] ;
                                    end
                            end
                    end
                else
                    if ((WRITEMODE_A == "WRITETHROUGH")) 
                        begin
                            if (we[0]) 
                                begin
                                    doa_tmp <=  data ;
                                end
                            else
                                begin
                                    for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                        begin
                                            doa_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_A) + i)] ;
                                        end
                                end
                        end
                    else
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_A) ; i = (i + 1))
                                begin
                                    doa_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_A) + i)] ;
                                end
                        end
            end
    endtask
    task  read_b(
        input reg [(ADDRWIDTH_B - 1):0] addr, 
            
        input reg [(DATAWIDTH_B - 1):0] data, 
            
        input reg [(WEB_WIDTH - 1):0] we) ; 
        integer i, 
            j ; 
        if ((USE_BYTE_WEB != 0)) 
            begin
                if ((WRITEMODE_B == "NORMAL")) 
                    begin
                        for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                            begin
                                for (j = 0 ; (j < (WEB_WIDTH / WIDTHRATIO_B)) ; j = (j + 1))
                                    begin
                                        if ((!we[(((i * WEB_WIDTH) / WIDTHRATIO_B) + j)])) 
                                            begin
                                                dob_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  memory[((addr * WIDTHRATIO_B) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] ;
                                            end
                                    end
                            end
                    end
                else
                    if ((WRITEMODE_B == "WRITETHROUGH")) 
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                begin
                                    for (j = 0 ; (j < (WEB_WIDTH / WIDTHRATIO_B)) ; j = (j + 1))
                                        begin
                                            if (we[(((i * WEB_WIDTH) / WIDTHRATIO_B) + j)]) 
                                                begin
                                                    dob_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  data[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] ;
                                                end
                                            else
                                                begin
                                                    dob_tmp[((i * MIN_WIDTH) + (j * BYTE_SIZE)) +: BYTE_SIZE] <=  memory[((addr * WIDTHRATIO_B) + i)][(j * BYTE_SIZE) +: BYTE_SIZE] ;
                                                end
                                        end
                                end
                        end
                    else
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                begin
                                    dob_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_B) + i)] ;
                                end
                        end
            end
        else
            begin
                if ((WRITEMODE_B == "NORMAL")) 
                    begin
                        if ((!we[0])) 
                            begin
                                for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                    begin
                                        dob_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_B) + i)] ;
                                    end
                            end
                    end
                else
                    if ((WRITEMODE_B == "WRITETHROUGH")) 
                        begin
                            if (we[0]) 
                                begin
                                    dob_tmp <=  data ;
                                end
                            else
                                begin
                                    for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                        begin
                                            dob_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_B) + i)] ;
                                        end
                                end
                        end
                    else
                        begin
                            for (i = 0 ; (i < WIDTHRATIO_B) ; i = (i + 1))
                                begin
                                    dob_tmp[(MIN_WIDTH * i) +: MIN_WIDTH] <=  memory[((addr * WIDTHRATIO_B) + i)] ;
                                end
                        end
            end
    endtask
    //write data
    always
        @(posedge clka)
        begin
            if (cea) 
                begin
                    write_a (addra,
                            dia,
                            wea) ;
                end
        end
    always
        @(posedge clkb)
        begin
            if (ceb) 
                begin
                    if ((MODE == "DP")) 
                        begin
                            write_b (addrb,
                                    dib,
                                    web) ;
                        end
                end
        end
    reg rsta_p1 = 1, 
        rsta_p2 = 1 ; 
    wire rsta_p3 = ((rsta_p2 | rsta_p1) | rsta) ; 
    always
        @(posedge clka or 
            posedge rsta)
        begin
            if (rsta) 
                begin
                    rsta_p1 <=  1 ;
                end
            else
                begin
                    rsta_p1 <=  0 ;
                end
        end
    always
        @(negedge clka)
        begin
            rsta_p2 <=  rsta_p1 ;
        end
    //read data
    wire sync_rsta = ((RESETMODE_A == "SYNC") && rsta) ; 
    wire async_rsta = ((RESETMODE_A == "ASYNC") ? rsta : ((RESETMODE_A == "ARSR") ? rsta_p3 : 0)) ; 
    wire ssroverce_a = ((SSROVERCE_A == "ENABLE") && sync_rsta) ; 
    wire ceoverssr_a = ((SSROVERCE_A == "DISABLE") && sync_rsta) ; 
    always
        @(posedge clka or 
            posedge async_rsta)
        begin
            if (async_rsta) 
                begin
                    doa_tmp2 <=  INITVAL_A ;
                end
            else
                if (ssroverce_a) 
                    begin
                        doa_tmp2 <=  INITVAL_A ;
                    end
                else
                    if (ocea) 
                        begin
                            if (ceoverssr_a) 
                                begin
                                    doa_tmp2 <=  INITVAL_A ;
                                end
                            else
                                begin
                                    doa_tmp2 <=  doa_tmp ;
                                end
                        end
        end
    always
        @(posedge clka or 
            posedge async_rsta)
        begin
            if (async_rsta) 
                begin
                    doa_tmp <=  INITVAL_A ;
                end
            else
                if (sync_rsta) 
                    begin
                        doa_tmp <=  INITVAL_A ;
                    end
                else
                    begin
                        if (cea) 
                            begin
                                if (((MODE == "SP") || (MODE == "DP"))) 
                                    begin
                                        read_a (addra,
                                                dia,
                                                wea) ;
                                    end
                            end
                    end
        end
    reg rstb_p1 = 1, 
        rstb_p2 = 1 ; 
    wire rstb_p3 = ((rstb_p1 | rstb_p2) | rstb) ; 
    always
        @(posedge clkb or 
            posedge rstb)
        begin
            if (rstb) 
                begin
                    rstb_p1 <=  1 ;
                end
            else
                begin
                    rstb_p1 <=  0 ;
                end
        end
    always
        @(negedge clkb)
        begin
            rstb_p2 <=  rstb_p1 ;
        end
    wire sync_rstb = ((RESETMODE_B == "SYNC") && rstb) ; 
    wire async_rstb = ((RESETMODE_B == "ASYNC") ? rstb : ((RESETMODE_B == "ARSR") ? rstb_p3 : 0)) ; 
    wire ssroverce_b = ((SSROVERCE_B == "ENABLE") && sync_rstb) ; 
    wire ceoverssr_b = ((SSROVERCE_B == "DISABLE") && sync_rstb) ; 
    always
        @(posedge clkb or 
            posedge async_rstb)
        begin
            if (async_rstb) 
                begin
                    dob_tmp2 <=  INITVAL_B ;
                end
            else
                if (ssroverce_b) 
                    begin
                        dob_tmp2 <=  INITVAL_B ;
                    end
                else
                    if (oceb) 
                        begin
                            if (ceoverssr_b) 
                                begin
                                    dob_tmp2 <=  INITVAL_B ;
                                end
                            else
                                begin
                                    dob_tmp2 <=  dob_tmp ;
                                end
                        end
        end
    always
        @(posedge clkb or 
            posedge async_rstb)
        begin
            if (async_rstb) 
                begin
                    dob_tmp <=  INITVAL_B ;
                end
            else
                if (sync_rstb) 
                    begin
                        dob_tmp <=  INITVAL_B ;
                    end
                else
                    begin
                        if (ceb) 
                            begin
                                if ((MODE == "DP")) 
                                    begin
                                        read_b (addrb,
                                                dib,
                                                web) ;
                                    end
                                else
                                    if ((MODE == "SDP")) 
                                        begin
                                            read_b (addrb,
                                                    dib,
                                                    1'b0) ;
                                        end
                            end
                    end
        end
    assign doa = ((REGMODE_A == "OUTREG") ? doa_tmp2 : doa_tmp) ; 
    assign dob = ((REGMODE_B == "OUTREG") ? dob_tmp2 : dob_tmp) ; 
endmodule


