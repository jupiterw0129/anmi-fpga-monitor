// ===========================================================================
// Copyright (c) 2011-2021 Anlogic Inc., All Right Reserved.
//
// TEL: 86-21-61633787
// WEB: http://www.anlogic.com/
// ===========================================================================
//
// Designer    :
// Date        : 2021/09/15
// Discription :
//          native clinet0 interface convert to axi rq interface
//
// Email       :
//
// ===========================================================================

`timescale 1ns/1ns

module axi4_st_mux #(
  parameter C_AXI_DATA_WIDTH = 64,                     // RX/TX interface data width
  parameter C_KEEP_WIDTH     = C_AXI_DATA_WIDTH/32,     // TKEEP width
  parameter TCQ              = 1                       // Clock to Q time
  ) (

  input  wire                       user_clk,
  input  wire                       user_reset,

  //-------------------------------------------------
  // AXI-S TX Interface to PCIe Hard Block
  //-------------------------------------------------
  output reg [C_AXI_DATA_WIDTH-1:0] m_axis_tx_tdata,   // TX data
  output reg                        m_axis_tx_tvalid,  // TX data is valid
  input  wire                           m_axis_tx_tready,  // TX ready for data
  output reg    [C_KEEP_WIDTH-1:0]  m_axis_tx_tkeep,   // TX strobe byte enables
  output reg                        m_axis_tx_tlast,   // TX data is last
  output reg                 [61:0] m_axis_tx_tuser,   // TX user signals

  //-------------------------------------------------
  // AXI-S TX Interface from DMA REQ
  //-------------------------------------------------
  input  wire[C_AXI_DATA_WIDTH-1:0] s_axis_tx_req_tdata,   // TX data
  input  wire                       s_axis_tx_req_tvalid,  // TX data is valid
  output wire                   s_axis_tx_req_tready,  // TX ready for data
  input  wire    [C_KEEP_WIDTH-1:0] s_axis_tx_req_tkeep,   // TX strobe byte enables
  input  wire                       s_axis_tx_req_tlast,   // TX data is last
  input  wire                 [61:0] s_axis_tx_req_tuser,   // TX user signals

  //-------------------------------------------------
  // AXI-S TX Interface from Target Bridge
  //-------------------------------------------------
  // input  [C_AXI_DATA_WIDTH-1:0] s_axis_tx_tgt_tdata,   // TX data
  // input                         s_axis_tx_tgt_tvalid,  // TX data is valid
  // output wire                   s_axis_tx_tgt_tready,  // TX ready for data
  // input      [C_KEEP_WIDTH-1:0] s_axis_tx_tgt_tkeep,   // TX strobe byte enables
  // input                         s_axis_tx_tgt_tlast,   // TX data is last
  // input                   [3:0] s_axis_tx_tgt_tuser,   // TX user signals

  //-------------------------------------------------
  // AXI-S TX Interface from CFG Sideband            
  //-------------------------------------------------
  input  wire[C_AXI_DATA_WIDTH-1:0] s_axis_tx_msix_tdata,  // TX data
  input  wire                       s_axis_tx_msix_tvalid, // TX data is valid
  output wire                   s_axis_tx_msix_tready, // TX ready for data
  input  wire[C_KEEP_WIDTH-1:0]     s_axis_tx_msix_tkeep,  // TX strobe byte enables
  input  wire                       s_axis_tx_msix_tlast,  // TX data is last
  input  wire[61:0]                 s_axis_tx_msix_tuser   // TX user signals

);

// Local parameters
localparam        SM_IDLE = 2'b00;
localparam        SM_REQ  = 2'b01;
localparam        SM_TGT  = 2'b10;
localparam        SM_MSIX = 2'b11;

// Wire and Register Declarations
// wire              pkt_relax_set;  // Indicates the current packet has Relaxed Ordering bit set.  -- need to decode bits
reg [1:0]         transfer_SM;    // Transfer State Machine


// assign  pkt_relax_set = s_axis_tx_tgt_tdata[13];

// Ordering Rules RX Demux will adopt (simplified from the PCIe Specification)
// Further detailed packet ordering will be done at the respective target modules
// MSI-X will follow DMA REQ rule per the table below however will always be prioritized over DMA REQ
// |----------------------------------------------------------------------------------------------------|
// |  Row Pass Column                  | DMA REQ (Posted/Non-Posted)       | Target Bridge (Completion) |
// |----------------------------------------------------------------------------------------------------|
// | DMA REQ       (Posted/Non-Posted) | NO  (will preserve ordering)      |             YES            |
// | Target Bridge (Completion)        | YES (If Relaxed Ordering bit set) |             NO             |
// |----------------------------------------------------------------------------------------------------|

assign s_axis_tx_msix_tready = (transfer_SM == SM_MSIX) ? m_axis_tx_tready : 1'b0;
assign s_axis_tx_req_tready  = (transfer_SM == SM_REQ)  ? m_axis_tx_tready : 1'b0;
// assign s_axis_tx_tgt_tready  = (transfer_SM == SM_TGT)  ? m_axis_tx_tready : 1'b0;

always @(posedge user_clk) begin

  if (user_reset) begin
    m_axis_tx_tvalid      <= #TCQ 1'b0;
    transfer_SM           <= #TCQ SM_IDLE;
  end else begin

    case (transfer_SM)
      SM_IDLE: begin

        if (m_axis_tx_tready) begin
          m_axis_tx_tdata       <= #TCQ 'b0;
          m_axis_tx_tvalid      <= #TCQ 1'b0;
          m_axis_tx_tkeep       <= #TCQ 'b0;
          m_axis_tx_tlast       <= #TCQ 1'b0;
          m_axis_tx_tuser       <= #TCQ 'b0;
        end

        // if ( (s_axis_tx_req_tvalid || s_axis_tx_msix_tvalid) && s_axis_tx_tgt_tvalid ) begin
        //   if (pkt_relax_set)
        //     transfer_SM           <= #TCQ SM_TGT;
        //   else
        //     transfer_SM           <= #TCQ s_axis_tx_msix_tvalid ? SM_MSIX : SM_REQ;
        // end
        // else 
        if (s_axis_tx_req_tvalid || s_axis_tx_msix_tvalid) begin
            transfer_SM           <= #TCQ s_axis_tx_msix_tvalid ? SM_MSIX : SM_REQ;
        end
        // else if (s_axis_tx_tgt_tvalid) begin
        //     transfer_SM           <= #TCQ SM_TGT;
        // end

      end

      SM_MSIX: begin

        if (m_axis_tx_tready) begin
          m_axis_tx_tdata       <= #TCQ s_axis_tx_msix_tdata;
          m_axis_tx_tvalid      <= #TCQ s_axis_tx_msix_tvalid;
          m_axis_tx_tkeep       <= #TCQ s_axis_tx_msix_tkeep;
          m_axis_tx_tlast       <= #TCQ s_axis_tx_msix_tlast;
          m_axis_tx_tuser       <= #TCQ s_axis_tx_msix_tuser;
        end

        if (s_axis_tx_msix_tlast && s_axis_tx_msix_tvalid && m_axis_tx_tready) begin
          transfer_SM           <= #TCQ SM_IDLE;
        end

      end

      SM_REQ: begin

        if (m_axis_tx_tready) begin
          m_axis_tx_tdata       <= #TCQ s_axis_tx_req_tdata;
          m_axis_tx_tvalid      <= #TCQ s_axis_tx_req_tvalid;
          m_axis_tx_tkeep       <= #TCQ s_axis_tx_req_tkeep;
          m_axis_tx_tlast       <= #TCQ s_axis_tx_req_tlast;
          m_axis_tx_tuser       <= #TCQ s_axis_tx_req_tuser;
        end

        if (s_axis_tx_req_tlast && s_axis_tx_req_tvalid && m_axis_tx_tready) begin
          transfer_SM           <= #TCQ SM_IDLE;
        end

      end
        
      // SM_TGT: begin

      //   if (m_axis_tx_tready) begin
      //     m_axis_tx_tdata       <= #TCQ s_axis_tx_tgt_tdata;
      //     m_axis_tx_tvalid      <= #TCQ s_axis_tx_tgt_tvalid;
      //     m_axis_tx_tkeep       <= #TCQ s_axis_tx_tgt_tkeep;
      //     m_axis_tx_tlast       <= #TCQ s_axis_tx_tgt_tlast;
      //     m_axis_tx_tuser       <= #TCQ s_axis_tx_tgt_tuser;
      //   end

      //   if (s_axis_tx_tgt_tlast && s_axis_tx_tgt_tvalid && m_axis_tx_tready) begin
      //     transfer_SM           <= #TCQ SM_IDLE;
      //   end

      // end

      default: begin
        transfer_SM           <= #TCQ SM_IDLE;
      end
    endcase

  end // reset

end // always

endmodule
