
`timescale 1ns/1ps

//`pragma protect begin
module ram_wrapper #(
    parameter DLY                = 1, 
    parameter RESOURCE_TYPE      = "bram", 
    parameter MODE               = "DP",         //SP, SDP, DP
    parameter BYTE_SIZE          = 8,            //8, 9, 10

    parameter USE_BYTE_WEA       = 0,              //0,1, use Byte Writes or not
    parameter DATAWIDTH_A        = 32,             //A WIDTH
    parameter WEA_WIDTH          = USE_BYTE_WEA == 0 ? 1 : DATAWIDTH_A/BYTE_SIZE,   //wea port width
    parameter REGMODE_A          = "NOREG",        //OUTREG, NOREG
    parameter RESETMODE_A        = "SYNC",        //SYNC, ASYNC, ARSR
    parameter INITVAL_A          = {DATAWIDTH_A{1'b0}}, //A initial value or reset value
    parameter WRITEMODE_A        = "NORMAL",       //NORMAL, WRITETHROUGH, READBEFOREWRITE
    parameter ADDRWIDTH_A        = 5,              //A ADDR WIDTH
    parameter DATADEPTH_A        = 2**ADDRWIDTH_A, //A DEPTH
    parameter SSROVERCE_A        = "ENABLE",       //ENABLE, DISABLE

    parameter USE_BYTE_WEB       = USE_BYTE_WEA,   //0,1, use Byte Writes or not
    parameter DATAWIDTH_B        = DATAWIDTH_A,    //B WIDTH
    parameter WEB_WIDTH          = USE_BYTE_WEB     == 0 ? 1 : DATAWIDTH_B/BYTE_SIZE,   //web port width
    parameter REGMODE_B          = "NOREG",        //OUTREG, NOREG
    parameter RESETMODE_B        = "SYNC",         //SYNC, ASYNC, ARSR
    parameter INITVAL_B          = {DATAWIDTH_B{1'b0}}, //B initial value or reset value
    parameter WRITEMODE_B        = "NORMAL",       //NORMAL, WRITETHROUGH, READBEFOREWRITE
    parameter ADDRWIDTH_B        = ADDRWIDTH_A,    //B ADDR WIDTH
    parameter DATADEPTH_B        = 2**ADDRWIDTH_B, //A DEPTH
    parameter SSROVERCE_B        = "ENABLE",       //ENABLE, DISABLE

    parameter INIT_FILE          = "NONE", //memory initialization file, can be "NONE" or surpport .dat/.txt file with binary data
    parameter FILL_REMAIN        = {DATAWIDTH_A{1'b0}}
  )(
    input clka, rsta, cea, ocea,
    input [WEA_WIDTH-1:0] wea,
    input [DATAWIDTH_A-1:0] dia,
    input [ADDRWIDTH_A-1:0] addra,

    input clkb, rstb, ceb, oceb,
    input [WEB_WIDTH-1:0] web,
    input [DATAWIDTH_B-1:0] dib,
    input [ADDRWIDTH_B-1:0] addrb,
    //output
    output [DATAWIDTH_A-1:0] doa,
    output [DATAWIDTH_B-1:0] dob
    ) ;

    eram_infer #(
            .DLY            (DLY         ),
            .RESOURCE_TYPE  (RESOURCE_TYPE),
            .MODE           (MODE        ),
            .BYTE_SIZE      (BYTE_SIZE   ),
            .USE_BYTE_WEA   (USE_BYTE_WEA),
            .DATAWIDTH_A    (DATAWIDTH_A ),
            .WEA_WIDTH      (WEA_WIDTH   ),
            .REGMODE_A      (REGMODE_A   ),
            .RESETMODE_A    (RESETMODE_A ),
            .INITVAL_A      (INITVAL_A   ),
            .WRITEMODE_A    (WRITEMODE_A ),
            .ADDRWIDTH_A    (ADDRWIDTH_A ),
            .DATADEPTH_A    (DATADEPTH_A ),
            .SSROVERCE_A    (SSROVERCE_A ),
            .USE_BYTE_WEB   (USE_BYTE_WEB),
            .DATAWIDTH_B    (DATAWIDTH_B ),
            .WEB_WIDTH      (WEB_WIDTH   ),
            .REGMODE_B      (REGMODE_B   ),
            .RESETMODE_B    (RESETMODE_B ),
            .INITVAL_B      (INITVAL_B   ),
            .WRITEMODE_B    (WRITEMODE_B ),
            .ADDRWIDTH_B    (ADDRWIDTH_B ),
            .DATADEPTH_B    (DATADEPTH_B ),
            .SSROVERCE_B    (SSROVERCE_B )
            ) 
    inst (//single port ROM
            //simple Dual port RAM
            .clka(clka), 
            .rsta(rsta), 
            .cea(cea),
            .ocea(ocea), 
            .wea(wea),
            // .we(we), 
            .dia(dia), 
            .addra(addra), 
            .doa(doa), 
            .clkb(clkb), 
            .rstb(rstb), 
            .ceb(ceb),
            .oceb(oceb), 
            .web(web),
            .dib(dib),
            .addrb(addrb), 
            .dob(dob)) ; 
endmodule


module eram_infer(clka, rsta, cea, ocea, wea, dia, addra, doa,
           clkb, rstb ,ceb, oceb, web, dib, addrb, dob
           // ecc_sbiterrinj, ecc_dbiterrinj, ecc_pipece,
           // ecc_sbiterr, ecc_dbiterr, ecc_erraddr
           );
//parameter
parameter DLY                = 1;
parameter RESOURCE_TYPE      = "bram";
parameter MODE               = "DP";         //SP, SDP, DP
parameter BYTE_SIZE          = 8;            //8, 9, 10

parameter USE_BYTE_WEA       = 0;              //0,1, use Byte Writes or not
parameter DATAWIDTH_A        = 32;             //A WIDTH
parameter WEA_WIDTH          = USE_BYTE_WEA == 0 ? 1 : DATAWIDTH_A/BYTE_SIZE;   //wea port width
parameter REGMODE_A          = "NOREG";        //OUTREG, NOREG
parameter RESETMODE_A        = "SYNC";         //SYNC, ASYNC, ARSR
parameter INITVAL_A          = {DATAWIDTH_A{1'b0}}; //A initial value or reset value
parameter WRITEMODE_A        = "NORMAL";       //NORMAL, WRITETHROUGH, READBEFOREWRITE
parameter ADDRWIDTH_A        = 5;              //A ADDR WIDTH
parameter DATADEPTH_A        = 2**ADDRWIDTH_A; //A DEPTH
parameter SSROVERCE_A        = "ENABLE";       //ENABLE, DISABLE

parameter USE_BYTE_WEB       = USE_BYTE_WEA;   //0,1, use Byte Writes or not
parameter DATAWIDTH_B        = DATAWIDTH_A;    //B WIDTH
parameter WEB_WIDTH          = USE_BYTE_WEB     == 0 ? 1 : DATAWIDTH_B/BYTE_SIZE;   //web port width
parameter REGMODE_B          = "NOREG";        //OUTREG, NOREG
parameter RESETMODE_B        = "SYNC";         //SYNC, ASYNC, ARSR
parameter INITVAL_B          = {DATAWIDTH_B{1'b0}}; //B initial value or reset value
parameter WRITEMODE_B        = "NORMAL";       //NORMAL, WRITETHROUGH, READBEFOREWRITE
parameter ADDRWIDTH_B        = ADDRWIDTH_A;    //B ADDR WIDTH
parameter DATADEPTH_B        = 2**ADDRWIDTH_B; //A DEPTH
parameter SSROVERCE_B        = "ENABLE";       //ENABLE, DISABLE

parameter INIT_FILE          = "NONE"; //memory initialization file, can be "NONE" or surpport .dat/.txt file with binary data
parameter FILL_REMAIN        = {DATAWIDTH_A{1'b0}};
//input 
input clka, rsta, cea, ocea;
input [WEA_WIDTH-1:0] wea;
input [DATAWIDTH_A-1:0] dia;
input [ADDRWIDTH_A-1:0] addra;

input clkb, rstb, ceb, oceb;
input [WEB_WIDTH-1:0] web;
input [DATAWIDTH_B-1:0] dib;
input [ADDRWIDTH_B-1:0] addrb;

// input ecc_sbiterrinj;
// input ecc_dbiterrinj;
// input ecc_pipece;

//output
output [DATAWIDTH_A-1:0] doa;
output [DATAWIDTH_B-1:0] dob;
// output ecc_sbiterr;
// output ecc_dbiterr;
// output [8:0] ecc_erraddr;


// check parameters
// synthesis translate_off
integer memfile;
initial begin
  if(INIT_FILE != "NONE") begin
    memfile = $fopen(INIT_FILE, "r");
    if(memfile == 0) begin
      $display("ERROR: Problem opening INIT_FILE.\n");
      $finish;
    end else begin
      $fclose(memfile);
    end
  end
  if(DATAWIDTH_A * DATADEPTH_A != DATAWIDTH_B * DATADEPTH_B) begin
      $display("ERROR: DATAWIDTH_A * DATADEPTH_A != DATAWIDTH_B * DATADEPTH_B.\n");
      $finish;
  end
  if(USE_BYTE_WEA != 0) begin
    if(WEA_WIDTH * BYTE_SIZE != DATAWIDTH_A) begin
      $display("ERROR: Wrong size of DATAWIDTH_A or WEA_WIDTH.\n");
      $finish;
    end
  end
  if(USE_BYTE_WEB != 0) begin
    if(WEB_WIDTH * BYTE_SIZE != DATAWIDTH_B) begin
      $display("ERROR: Wrong size of DATAWIDTH_B or WEB_WIDTH.\n");
      $finish;
    end
  end
  if(DATADEPTH_A > (2 ** ADDRWIDTH_A)) begin
    $display("ERROR: DATADEPTH_A > (2 ** ADDRWIDTH_A)).\n");
    $finish;
  end
  if(DATADEPTH_A <= (2 ** (ADDRWIDTH_A-1))) begin
    $display("ERROR: DATADEPTH_A <= (2 ** (ADDRWIDTH_A-1)).\n");
    $finish;
  end
  if(DATADEPTH_B > (2 ** ADDRWIDTH_B)) begin
    $display("ERROR: DATADEPTH_B > (2 ** ADDRWIDTH_B)).\n");
    $finish;
  end
  if(DATADEPTH_B <= (2 ** (ADDRWIDTH_B-1))) begin
    $display("ERROR: DATADEPTH_B <= (2 ** (ADDRWIDTH_B-1)).\n");
    $finish;
  end
  if(MODE != "DP" && USE_BYTE_WEB != 0) begin
    $display("ERROR: USE_BYTE_WEB must be 0 because MODE is not \"DP\".\n");
    $finish;
  end
  if(MODE == "SDP" && (WRITEMODE_A != "NORMAL" || WRITEMODE_B != "NORMAL")) begin
    $display("ERROR: MODE == \"SDP\" && (WRITEMODE_A != \"NORMAL\" || WRITEMODE_B != \"NORMAL\").\n");
    $finish;
  end
  if(MODE == "SP" && DATAWIDTH_A != DATAWIDTH_B) begin
    $display("ERROR: MODE == \"SP\" && DATAWIDTH_A != DATAWIDTH_B\n");
    $finish;
  end
  if(MODE == "SDP" && cea == 1'b1 && wea != {WEA_WIDTH{1'b0}} && addra == addrb) begin
    $display("Warning: addra and addrb conflict at Simple Dual Port RAM MODE.\n");
    $finish;
  end
end


// synthesis translate_on

//integer fp;

  localparam MIN_WIDTH = (DATAWIDTH_A > DATAWIDTH_B) ? DATAWIDTH_B : DATAWIDTH_A;
  localparam MAX_DEPTH = (DATADEPTH_A > DATADEPTH_B) ? DATADEPTH_A : DATADEPTH_B;
  localparam WIDTHRATIO_A = DATAWIDTH_A / MIN_WIDTH;
  localparam WIDTHRATIO_B = DATAWIDTH_B / MIN_WIDTH;

  //synthesis force_ram
  // `ifdef BRAM_AREA
  (* ram_style = RESOURCE_TYPE *)reg [MIN_WIDTH-1:0] memory [MAX_DEPTH-1:0];  //synthesis ram_style = bram
  // `endif
  // `ifdef BRAM_FAST
  // reg [MIN_WIDTH-1:0] memory [MAX_DEPTH-1:0];  //synthesis ram_style = bram_fast
  // `endif
  // `ifdef BRAM_9K
  // reg [MIN_WIDTH-1:0] memory [MAX_DEPTH-1:0];  //synthesis ram_style = bram_9k
  // `endif
  // `ifdef BRAM_9K_FAST 
  // reg [MIN_WIDTH-1:0] memory [MAX_DEPTH-1:0];  //synthesis ram_style = bram_9k_fast
  // `endif
  // `ifdef BRAM_32K
  // reg [MIN_WIDTH-1:0] memory [MAX_DEPTH-1:0];  //synthesis ram_style = bram_32k
  // `endif

  reg [DATAWIDTH_A-1:0] doa_tmp = INITVAL_A;
  reg [DATAWIDTH_B-1:0] dob_tmp = INITVAL_B;
  reg [DATAWIDTH_A-1:0] doa_tmp2 = INITVAL_A;
  reg [DATAWIDTH_B-1:0] dob_tmp2 = INITVAL_B;


  integer i,j;
  //Initial value
  initial begin
    for (i = 0; i < MAX_DEPTH; i=i+1) begin
          memory[i] = 'd0;
    end
    // if(INIT_FILE[31:0] == ".dat")
    //   $readmemb(INIT_FILE,memory);
    // else if(INIT_FILE[31:0] == "dath")
    //   $readmemh(INIT_FILE,memory);
  end


  task write_a
    (input reg [ADDRWIDTH_A-1:0] addr, 
      input reg [DATAWIDTH_A-1:0] data,
      input reg [WEA_WIDTH-1:0] we);
    integer i,j;
    begin
      if(USE_BYTE_WEA != 0) begin
        for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
          for(j = 0; j < WEA_WIDTH/WIDTHRATIO_A; j=j+1) begin
            if(we[i*WEA_WIDTH/WIDTHRATIO_A+j]) begin
              memory[addr * WIDTHRATIO_A + i][j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                data[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else begin
        if(we) begin
          for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
            memory[addr * WIDTHRATIO_A + i] <= #DLY data[i*MIN_WIDTH+:MIN_WIDTH];
          end
        end
      end
    end
  endtask

  task write_b
    (input reg [ADDRWIDTH_B-1:0] addr, 
      input reg [DATAWIDTH_B-1:0] data,
      input reg [WEB_WIDTH-1:0] we);
    integer i,j;
    begin
      if(USE_BYTE_WEB != 0) begin
        for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
          for(j = 0; j < WEB_WIDTH/WIDTHRATIO_B; j=j+1) begin
            if(we[i*WEB_WIDTH/WIDTHRATIO_B+j]) begin
              memory[addr * WIDTHRATIO_B + i][j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                data[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else begin
        if(we) begin
          for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
            memory[addr * WIDTHRATIO_B + i] <= #DLY data[i*MIN_WIDTH+:MIN_WIDTH];
          end
        end
      end
    end
  endtask

  task read_a
    (input reg [ADDRWIDTH_A-1:0] addr,
      input reg [DATAWIDTH_A-1:0] data,
      input reg [WEA_WIDTH-1:0] we);
    integer i, j;
    if(USE_BYTE_WEA != 0) begin
      if(WRITEMODE_A == "NORMAL") begin
        for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
          for(j = 0; j < WEA_WIDTH/WIDTHRATIO_A; j=j+1) begin
            if(!we[i*WEA_WIDTH/WIDTHRATIO_A+j]) begin
              doa_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                memory[addr*WIDTHRATIO_A+i][j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else if(WRITEMODE_A == "WRITETHROUGH") begin
        for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
          for(j = 0; j < WEA_WIDTH/WIDTHRATIO_A; j=j+1) begin
            if(we[i*WEA_WIDTH/WIDTHRATIO_A+j]) begin
              doa_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                data[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE];
            end else begin
              doa_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                memory[addr*WIDTHRATIO_A+i][j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else begin
        for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
          doa_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_A+i];
        end
      end
    end else begin
      if(WRITEMODE_A == "NORMAL") begin
        if(!we[0]) begin
          for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
            doa_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_A+i];
          end
        end
      end else if(WRITEMODE_A == "WRITETHROUGH") begin
        if(we[0]) begin
          doa_tmp <= #DLY data;
        end else begin
          for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
            doa_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_A+i];
          end
        end
      end else begin
        for(i = 0; i < WIDTHRATIO_A; i=i+1) begin
          doa_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_A+i];
        end
      end
    end
  endtask

  task read_b
    (input reg [ADDRWIDTH_B-1:0] addr,
      input reg [DATAWIDTH_B-1:0] data,
      input reg [WEB_WIDTH-1:0] we);
    integer i, j;
    if(USE_BYTE_WEB != 0) begin
      if(WRITEMODE_B == "NORMAL") begin
        for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
          for(j = 0; j < WEB_WIDTH/WIDTHRATIO_B; j=j+1) begin
            if(!we[i*WEB_WIDTH/WIDTHRATIO_B+j]) begin
              dob_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                memory[addr*WIDTHRATIO_B+i][j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else if(WRITEMODE_B == "WRITETHROUGH") begin
        for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
          for(j = 0; j < WEB_WIDTH/WIDTHRATIO_B; j=j+1) begin
            if(we[i*WEB_WIDTH/WIDTHRATIO_B+j]) begin
              dob_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                data[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE];
            end else begin
              dob_tmp[i*MIN_WIDTH+j*BYTE_SIZE+:BYTE_SIZE] <= #DLY
                memory[addr*WIDTHRATIO_B+i][j*BYTE_SIZE+:BYTE_SIZE];
            end
          end
        end
      end else begin
        for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
          dob_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_B+i];
        end
      end
    end else begin
      if(WRITEMODE_B == "NORMAL") begin
        if(!we[0]) begin
          for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
            dob_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_B+i];
          end
        end
      end else if(WRITEMODE_B == "WRITETHROUGH") begin
        if(we[0]) begin
          dob_tmp <= #DLY data;
        end else begin
          for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
            dob_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_B+i];
          end
        end
      end else begin
        for(i = 0; i < WIDTHRATIO_B; i=i+1) begin
          dob_tmp[MIN_WIDTH*i+:MIN_WIDTH] <= #DLY memory[addr*WIDTHRATIO_B+i];
        end
      end
    end
  endtask

  //write data
  always @(posedge clka) begin
    if(cea) begin
      write_a(addra, dia, wea);
    end
  end
  always @(posedge clkb) begin
    if(ceb) begin
      if(MODE == "DP") begin
        write_b(addrb, dib, web);
      end
    end
  end

  reg rsta_p1=1, rsta_p2=1;
  wire rsta_p3 = rsta_p2 | rsta_p1 | rsta;

  always @(posedge clka or posedge rsta) begin
    if(rsta) begin
      rsta_p1 <= #DLY 1;
    end else begin
      rsta_p1 <= #DLY 0; 
    end
  end

  always @(negedge clka) begin
    rsta_p2 <= #DLY rsta_p1;
  end


  //read data
  wire sync_rsta = (RESETMODE_A == "SYNC") && rsta;
  wire async_rsta = (RESETMODE_A == "ASYNC") ? rsta : rsta_p3;//((RESETMODE_A == "ARSR") ? rsta_p3 : 0);
  wire ssroverce_a = (SSROVERCE_A == "ENABLE") && sync_rsta;
  wire ceoverssr_a = (SSROVERCE_A == "DISABLE") && sync_rsta;


  always @(posedge clka or posedge async_rsta) begin
    if(async_rsta) begin
      doa_tmp2 <= #DLY INITVAL_A;
    end else if(ssroverce_a) begin
      doa_tmp2 <= #DLY INITVAL_A;
    end else if(ocea) begin
      if(ceoverssr_a) begin
        doa_tmp2 <= #DLY INITVAL_A;
      end else begin
        doa_tmp2 <= #DLY doa_tmp;
      end
    end
  end

  always @(posedge clka or posedge async_rsta) begin
    if(async_rsta) begin
      doa_tmp <= #DLY INITVAL_A;
    end else if(sync_rsta) begin
      doa_tmp <= #DLY INITVAL_A;
    end else begin
      if(cea) begin
        if (MODE == "SP" || MODE == "DP") begin
          read_a(addra, dia, wea);
        end
      end
    end
  end

  reg rstb_p1=1, rstb_p2=1;
  wire rstb_p3 = rstb_p1 | rstb_p2 | rstb;

  always @(posedge clkb or posedge rstb) begin
    if(rstb) begin
      rstb_p1 <= #DLY 1;
    end else begin
      rstb_p1 <= #DLY 0; 
    end
  end

  always @(negedge clkb) begin
    rstb_p2 <= #DLY rstb_p1;
  end

  wire sync_rstb = (RESETMODE_B == "SYNC") && rstb;
  wire async_rstb = (RESETMODE_B == "ASYNC") ? rstb : rstb_p3;
  wire ssroverce_b = (SSROVERCE_B == "ENABLE") && sync_rstb;
  wire ceoverssr_b = (SSROVERCE_B == "DISABLE") && sync_rstb;

  always @(posedge clkb or posedge async_rstb) begin
    if(async_rstb) begin
      dob_tmp2 <= #DLY INITVAL_B;
    end else if(ssroverce_b) begin
      dob_tmp2 <= #DLY INITVAL_B;
    end else if(oceb) begin
      if(ceoverssr_b) begin
        dob_tmp2 <= #DLY INITVAL_B;
      end else begin
        dob_tmp2 <= #DLY dob_tmp;
      end
    end
  end

  always @(posedge clkb or posedge async_rstb) begin
    if(async_rstb) begin
      dob_tmp <= #DLY INITVAL_B;
    end else if(sync_rstb) begin
      dob_tmp <= #DLY INITVAL_B;
    end else begin
      if(ceb) begin
        if(MODE == "DP") begin
          read_b(addrb, dib, web);
        end else if(MODE == "SDP") begin
          read_b(addrb, dib, 1'b0);
        end
      end
    end
  end

  assign doa = REGMODE_A == "OUTREG" ? doa_tmp2 : doa_tmp;
  assign dob = REGMODE_B == "OUTREG" ? dob_tmp2 : dob_tmp;

endmodule
