/*===========================================*\
Filename         : dma_regwr.v
Author           :
Project name     : sgdma_app
Description      :
Called by        : sgdma_subsystem_tst.v
Revision History : v1.0
Email            :
Modified         :
Copyright(c)Shanghai Anlu Information Technology Co.,Ltd
\*===========================================*/
`timescale 1ns/1ps

module usr_dmarw#(
  parameter     DLY = 1
  )(
  input wire   usr_rst_n,
  input wire   usr_clk,

  output  wire   [31: 0]  s_axil_awaddr_o ,
  output  wire   [2 : 0]  s_axil_awprot_o ,
  output  wire   s_axil_awvalid_o ,
  input   wire   s_axil_awready_i ,
  output  wire   [31: 0]  s_axil_wdata_o  ,
  output  wire   [3 : 0]  s_axil_wstrb_o  ,
  output  wire   s_axil_wvalid_o  ,
  input   wire   s_axil_wready_i  ,
  input   wire   s_axil_bvalid_i  ,
  input   wire   [1 : 0]  s_axil_bresp_i  ,
  output  wire   s_axil_bready_o  ,
  output  wire   [31: 0]  s_axil_araddr_o ,
  output  wire   [2 : 0]  s_axil_arprot_o ,
  output  wire   s_axil_arvalid_o ,
  input   wire   s_axil_arready_i ,
  input   wire   [31: 0]  s_axil_rdata_i  ,
  input   wire   [1 : 0]  s_axil_rresp_i  ,
  input   wire   s_axil_rvalid_i  ,
  output  wire   s_axil_rready_o  ,

  input   wire   [1:0]    usr_dmarw_run_i,
  output  wire   [31:0]   h2c0_chn_stts_o,
  output  wire   [31:0]   c2h0_chn_stts_o
);

  reg [83:0]rw_cmd;
  reg [5:0] index ;
  reg       chk_err ;
  reg [1:0] usr_dmarw_run_d1;
  reg   s_axil_rready ;
  reg   s_axil_bready ;
  reg [3:0] state ;
  wire[1:0] usr_dmarw_run_rising;
  reg       c2h0_stts_rdp;
  reg       h2c0_stts_rdp;
  wire      write_ok;
  wire      read_ok ;
  reg [31: 0] s_axil_awaddr;
  reg         s_axil_awvalid;
  reg [31: 0] s_axil_wdata ;
  reg [3 : 0] s_axil_wstrb ;
  reg         s_axil_wvalid;
  reg         awrite_flag ;
  reg [31:0]  s_axil_araddr;
  reg         s_axil_arvalid;
  reg         aread_flag;
  reg         rd4chk;
  localparam  IDLE  = 4'd0,
              FETCH = 4'd1,
              WRITE = 4'd2,
              READ  = 4'd3,
              CHECK = 4'd4,
              DELAY = 4'd5;
  localparam  REG_NUM = 'd42 ;

  // assign  c2h0_stts_rdp = usr_dmarw_run_rising[0];
  // assign  h2c0_stts_rdp = usr_dmarw_run_rising[1];
  assign  s_axil_bready_o = s_axil_bready ;
  assign  s_axil_rready_o = s_axil_rready ;
  assign  write_ok = s_axil_bvalid_i & s_axil_bready & ~(|s_axil_bresp_i);
  assign  read_ok  = s_axil_rvalid_i & s_axil_rready & ~(|s_axil_rresp_i);

  always@(posedge usr_clk,negedge usr_rst_n)
  begin
    if(!usr_rst_n)
        usr_dmarw_run_d1 <= #DLY 2'b00;
      else
        usr_dmarw_run_d1 <= #DLY usr_dmarw_run_i;
  end
  assign usr_dmarw_run_rising = (~usr_dmarw_run_d1) & usr_dmarw_run_i;
  always@(posedge usr_clk,negedge usr_rst_n)
  begin
    if(!usr_rst_n)
        c2h0_stts_rdp <= #DLY 1'b0;
      else
        c2h0_stts_rdp <= #DLY usr_dmarw_run_rising[0];
  end
  always@(posedge usr_clk,negedge usr_rst_n)
  begin
    if(!usr_rst_n)
        h2c0_stts_rdp <= #DLY 1'b0;
      else
        h2c0_stts_rdp <= #DLY usr_dmarw_run_rising[1];
  end

  always @( posedge usr_clk ) begin
    case( index )
      //Format
      //  84  83:64   63:32  |  31:0
      //  RO Addr    Wdata  |Check data
      //H2C
      'd0 : rw_cmd <= #DLY {20'h00000,32'hffffffee , 32'h1fc08001 };
      'd1 : rw_cmd <= #DLY {20'h00004,32'hfffffff6 , 32'h00070018 };
      'd2 : rw_cmd <= #DLY {20'h00008,32'h0000001e , 32'h00070018 };
      'd3 : rw_cmd <= #DLY {20'h0000c,32'hffffffe7 , 32'h00070018 };
      'd4 : rw_cmd <= #DLY {20'h00040,32'hfffffffd , 32'h00000000 };
      'd5 : rw_cmd <= #DLY {20'h00088,32'hffffffed , 32'hffffffed };
      'd6 : rw_cmd <= #DLY {20'h0008c,32'h0000001d , 32'h0000001d };
      'd7 : rw_cmd <= #DLY {20'h00090,32'hffffffe4 , 32'h003ffff4 };
      'd8 : rw_cmd <= #DLY {20'h00094,32'h00000016 , 32'h003ffff4 };
      'd9 : rw_cmd <= #DLY {20'h00098,32'h0000000a , 32'h003ffff4 };
      'd10: rw_cmd <= #DLY {20'h000c0,32'h00000011 , 32'h00000001 };
      'd11: rw_cmd <= #DLY {20'h01000,32'h00000003 , 32'h1fc18001 };
      'd12: rw_cmd <= #DLY {20'h01004,32'hfffffff3 , 32'h0cf83e70 };
      'd13: rw_cmd <= #DLY {20'h01008,32'h0000000b , 32'h0cf83e70 };
      'd14: rw_cmd <= #DLY {20'h0100c,32'h0000000f , 32'h0cf83e70 };
      'd15: rw_cmd <= #DLY {20'h01040,32'hfffffffd , 32'h00000001 };
      'd16: rw_cmd <= #DLY {20'h01088,32'hfffffffb , 32'hfffffffb };
      'd17: rw_cmd <= #DLY {20'h0108c,32'hffffffdf , 32'hffffffdf };
      'd18: rw_cmd <= #DLY {20'h01090,32'hfffffff1 , 32'h00000016 };
      'd19: rw_cmd <= #DLY {20'h01094,32'h00000016 , 32'h00000016 };
      'd20: rw_cmd <= #DLY {20'h01098,32'hffffffe0 , 32'h00000016 };
      'd21: rw_cmd <= #DLY {20'h010c0,32'hffffffed , 32'h00000005 };
      'd22: rw_cmd <= #DLY {20'h02004,32'h0000000e , 32'h00000000 };
      'd23: rw_cmd <= #DLY {20'h02008,32'h00000001 , 32'h00000000 };
      'd24: rw_cmd <= #DLY {20'h0200c,32'h0000000b , 32'h00000000 };
      'd25: rw_cmd <= #DLY {20'h02010,32'hfffffff8 , 32'h00000000 };
      'd26: rw_cmd <= #DLY {20'h02014,32'hfffffffd , 32'h00000000 };
      'd27: rw_cmd <= #DLY {20'h02018,32'h00000005 , 32'h00000000 };
      'd28: rw_cmd <= #DLY {20'h02080,32'hffffffec , 32'h00001f0c };
      'd29: rw_cmd <= #DLY {20'h020a0,32'h00000006 , 32'h00000006 };
      'd30: rw_cmd <= #DLY {20'h020a8,32'h00000007 , 32'h00000001 };
      'd31: rw_cmd <= #DLY {20'h04080,32'hfffffff6 , 32'hfffffff6 };
      'd32: rw_cmd <= #DLY {20'h04084,32'h0000001d , 32'h0000001d };
      'd33: rw_cmd <= #DLY {20'h04090,32'h0000000e , 32'hffffffff };
      'd34: rw_cmd <= #DLY {20'h0408c,32'hffffffe1 , 32'h000003e1 };
      'd35: rw_cmd <= #DLY {20'h05080,32'h00000010 , 32'h00000010 };
      'd36: rw_cmd <= #DLY {20'h05084,32'h00000021 , 32'h00000021 };
      'd37: rw_cmd <= #DLY {20'h05090,32'h00000000 , 32'hffffffff };
      'd38: rw_cmd <= #DLY {20'h0508c,32'hffffffec , 32'h000003ec };
      'd39: rw_cmd <= #DLY {20'h06020,32'h0000001d , 32'h00010000 };
      'd40: rw_cmd <= #DLY {20'h06024,32'hffffffe9 , 32'h00010000 };
      'd41: rw_cmd <= #DLY {20'h06028,32'h00000007 , 32'h00010000 };
      default : rw_cmd <= #DLY rw_cmd;
    endcase
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      index   <= #DLY 6'd0 ;
    else if( state == FETCH )
      index   <= #DLY index + 1'b1 ;
    else if( index == REG_NUM && write_ok == 1'b1 )
      index   <= #DLY 6'd0 ;
  end
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      rd4chk  <= #DLY 1'b0 ;
    else if( index == REG_NUM && write_ok == 1'b1 && state == WRITE )
      rd4chk  <= #DLY 1'b1 ;
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      state <= #DLY 4'd0 ;
    else begin
      case( state )
        IDLE : begin
          if( c2h0_stts_rdp )
            state <= #DLY FETCH;
          else
            state <= #DLY IDLE ;
        end
        FETCH: begin
          if(rd4chk == 1'b0)
            state <= #DLY WRITE;
          else
            state <= #DLY READ;
        end
        WRITE:begin
          if( write_ok )
            state <= #DLY (index == REG_NUM) ? DELAY : FETCH;//READ ;
          else
            state <= #DLY WRITE;
        end
        READ : begin
          if( read_ok )
            state <= #DLY CHECK;
          else
            state <= #DLY READ ;
        end
        CHECK: begin
          state   <= #DLY (index == REG_NUM) ? IDLE : FETCH ;
        end
        DELAY: begin
          state   <= #DLY FETCH;
        end
        default: begin
          state   <= #DLY IDLE ;
        end
      endcase
    end
  end

  //Write
  assign s_axil_awaddr_o = s_axil_awaddr;
  assign s_axil_awprot_o = 3'd0;
  assign s_axil_awvalid_o= s_axil_awvalid;
  assign s_axil_wvalid_o = s_axil_wvalid;
  assign s_axil_wdata_o  = s_axil_wdata;
  assign s_axil_wstrb_o  = s_axil_wstrb;

  always @( posedge usr_clk , negedge usr_rst_n ) begin
  	if(!usr_rst_n) begin
      s_axil_awaddr <= #DLY 32'd0;
      s_axil_wdata  <= #DLY 32'd0;
      s_axil_wstrb  <= #DLY 4'd0;
    end
    else if( state == FETCH ) begin
      s_axil_awaddr <= #DLY {12'h000,rw_cmd[83:64]} ;
      s_axil_wdata  <= #DLY rw_cmd[63:32] ;
      s_axil_wstrb  <= #DLY 4'b1111;
    end
    else begin
      s_axil_awaddr <= #DLY s_axil_awaddr;
      s_axil_wdata  <= #DLY s_axil_wdata;
      s_axil_wstrb  <= #DLY s_axil_wstrb;
    end
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      awrite_flag  <= #DLY 1'd0 ;
    else if( state == WRITE )
      awrite_flag  <= #DLY 1'd1 ;
    else
      awrite_flag  <= #DLY 1'd0 ;
  end
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      s_axil_awvalid  <= #DLY 1'd0 ;
    else if( state == WRITE && s_axil_awready_i && s_axil_awvalid )
      s_axil_awvalid  <= #DLY 1'd0 ;
    else if( state == WRITE && awrite_flag == 1'b0 )
      s_axil_awvalid  <= #DLY 1'd1 ;
  end
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      s_axil_wvalid   <= #DLY 1'd0 ;
    else if( state == WRITE && s_axil_wready_i && s_axil_wvalid )
      s_axil_wvalid   <= #DLY 1'd0 ;
    else if( state == WRITE && awrite_flag == 1'b0 )
      s_axil_wvalid   <= #DLY 1'd1 ;
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      s_axil_bready   <= #DLY 1'd0 ;
    else if( state == WRITE && ( ~s_axil_bready ) && s_axil_bvalid_i )
      s_axil_bready   <= #DLY 1'd1 ;
    else
      s_axil_bready   <= #DLY 1'd0 ;
  end

  //Read
  assign s_axil_arprot_o = 3'b000;
  assign s_axil_araddr_o = s_axil_araddr;
  assign s_axil_arvalid_o= s_axil_arvalid;

  always @( posedge usr_clk , negedge usr_rst_n ) begin
  	if(!usr_rst_n)
      s_axil_araddr <= #DLY 32'd0;
    else if( state == FETCH )
      s_axil_araddr <= #DLY {12'h000,rw_cmd[83:64]} ;
    else
      s_axil_araddr <= #DLY s_axil_araddr;
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      aread_flag   <= #DLY 1'd0 ;
    else if( state == READ )
      aread_flag   <= #DLY 1'd1 ;
    else
      aread_flag   <= #DLY 1'd0 ;
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      s_axil_arvalid   <= #DLY 1'd0 ;
    else if( state == READ && s_axil_arready_i && s_axil_arvalid )
      s_axil_arvalid   <= #DLY 1'd0 ;
    else if( state == READ && aread_flag == 1'b0 )
      s_axil_arvalid   <= #DLY 1'd1 ;
  end

  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      s_axil_rready   <= #DLY 1'd0 ;
    else if( state == READ && ( ~s_axil_rready ) && s_axil_rvalid_i )
      s_axil_rready   <= #DLY 1'd1 ;
    else
      s_axil_rready   <= #DLY 1'd0 ;
  end

  assign h2c0_chn_stts_o = 'b0;
  assign c2h0_chn_stts_o = 'b0;

`ifdef DEBUG_MODE
  reg [31:0]  usr_rwdma_sim [REG_NUM:0];
  reg [5:0]   reg_cnt;
  integer     i;
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n ) begin
      for(i = 0 ; i < REG_NUM + 1; i = i + 1 ) begin
        usr_rwdma_sim[i] <= #DLY 32'h0000_0000 ;
      end
      reg_cnt       <= #DLY 6'd0 ;
    end
    else if( state == READ && ( s_axil_rready ) && s_axil_rvalid_i )  begin
      usr_rwdma_sim[reg_cnt] <= #DLY s_axil_rdata_i ;
      reg_cnt       <= #DLY reg_cnt + 1'b1 ;
    end
  end
`else
  reg [31:0]  rdback_data ;
  reg [31:0]  chk_data ;
  reg         read_only;
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      rdback_data <= #DLY 32'h0000_0000 ;
    else if( state == READ && ( s_axil_rready ) && s_axil_rvalid_i )
      rdback_data <= #DLY s_axil_rdata_i ;
  end
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      chk_data    <= #DLY 32'h0000_0000 ;
    else if( state == READ )
      chk_data    <= #DLY rw_cmd[31:0] ;
  end
  always @( posedge usr_clk , negedge usr_rst_n ) begin
    if( !usr_rst_n )
      chk_err     <= #DLY 1'b0 ;
    else if( state == CHECK && rdback_data != chk_data ) begin
      chk_err     <= #DLY 1'b1 ;
    end
    else
      chk_err     <= #DLY 1'b0 ;
  end
`endif

endmodule

