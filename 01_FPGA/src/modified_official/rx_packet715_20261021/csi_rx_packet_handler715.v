

module csi_rx_packet_handler715 #(
    parameter MIPI_LAN = 4, 
    parameter VC_ID = 0     
)(
    
    input  wire         I_clock,        
    input  wire         I_reset_n,      
    input wire I_default_raw12,
    output reg O_raw12,
    output wire [2:0] O_payload_bytes,
    input  wire         I_enable,       

    input wire [31:0]   I_data,         
    input wire          I_data_valid,   

    output wire         O_packet_done,  
    output wire         O_sync_wait,    
    
    output reg [31:0]   O_payload_out,   
    output reg          O_payload_valid, 

    output wire         O_vsync_out,    
    output wire         O_in_frame,     
    output wire O_header_attempt,
    output wire O_header_valid,
    output wire O_header_ecc_bad,
    output wire O_header_filter_bad,
    output wire O_payload_timeout,
    output wire         O_in_line       

);

localparam [1:0] 
    STATE_IDLE       = 2'b00,  
    STATE_WAIT_HDR   = 2'b01,  
    STATE_RX_PAYLOAD = 2'b10,  
    STATE_PKT_END    = 2'b11;  

reg [1:0] R_MS;  
reg [1:0] R_MS_NEXT;      

wire  [7:0]   w_packet_type;     
wire          w_long_packet;     
wire [15:0]   w_packet_len;      
wire          w_valid_packet;    
wire [23:0]   w_packet_for_ecc;  
wire  [7:0]   w_expected_ecc;    

reg [16:0]    r_bytes_read;      
reg [15:0]    r_packet_len_q;    
reg           r_in_frame_d;      
reg           r_in_line_d;       
reg           r_packet_done;     

reg[4:0]      r_error_cunt;      
reg           r_data_valid;
reg drain_tail;

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) drain_tail <= 1'b0;
    else if (!I_enable) drain_tail <= 1'b0;
    else if (r_packet_done) drain_tail <= I_data_valid;
    else if (!I_data_valid) drain_tail <= 1'b0;
end

assign w_packet_type    = {2'b00,I_data[5:0]}; 
assign w_packet_for_ecc = I_data[23:0];        
assign w_packet_len     = I_data[23:8];        

assign w_long_packet = (w_packet_type > 8'h0F) && w_valid_packet ;

assign w_valid_packet = (I_data[31:24] == w_expected_ecc) && (is_allowed_type (w_packet_type)) && (I_data[7:6] == VC_ID[1:0]) && I_data_valid && !drain_tail && !r_packet_done;

function is_allowed_type;
    input [7:0] packet_type;
    begin
        case (packet_type)
            8'h00, 8'h01, 8'h02, 8'h03, 8'h12, 8'h2B, 8'h2C, 8'h37:
                is_allowed_type = 1'b1;
            default: is_allowed_type = 1'b0;
        endcase
    end
endfunction

reg [2:0] payload_bytes;
assign O_payload_bytes = payload_bytes;
wire [16:0] payload_remaining = {1'b0, r_packet_len_q} - r_bytes_read;

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) begin
        O_raw12 <= 1'b0;
        payload_bytes <= 3'd0;
    end else begin
        payload_bytes <= 3'd0;
        if (!I_enable) begin
            O_raw12 <= 1'b0;
        end else begin
            if (R_MS == STATE_WAIT_HDR && w_long_packet)
                O_raw12 <= w_packet_type == 8'h2C ||
                    ((w_packet_type == 8'h12 || w_packet_type == 8'h37) && I_default_raw12);
            if (R_MS == STATE_RX_PAYLOAD && I_data_valid && r_bytes_read < r_packet_len_q)
                payload_bytes <= payload_remaining >= 4 ? 3'd4 : payload_remaining[2:0];
        end
    end
end

csi_rx_hdr_ecc ecc_inst (
    .data(w_packet_for_ecc),  
    .ecc(w_expected_ecc)      
);

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        R_MS <= STATE_IDLE;  
    else if (I_enable) 
        R_MS <= R_MS_NEXT;  
    else 
        R_MS <= R_MS;
end

always @(*) begin
    
    R_MS_NEXT = R_MS;
    
    case (R_MS)
        STATE_IDLE       : R_MS_NEXT = STATE_WAIT_HDR;   
        STATE_WAIT_HDR   : R_MS_NEXT = (w_valid_packet) ? (w_long_packet ? STATE_RX_PAYLOAD : STATE_PKT_END ): STATE_WAIT_HDR;
        STATE_RX_PAYLOAD : R_MS_NEXT = ((r_bytes_read >= (r_packet_len_q)) | (r_error_cunt==5'h1f)) ? STATE_PKT_END : STATE_RX_PAYLOAD ; 
        STATE_PKT_END    : R_MS_NEXT = STATE_IDLE; 
        default: R_MS_NEXT = STATE_IDLE;  
    endcase
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_packet_len_q <= 16'h0; 
    else begin 
        if (I_enable) begin
            if ((R_MS == STATE_WAIT_HDR) & w_long_packet)         
                r_packet_len_q <= w_packet_len;
            else 
                r_packet_len_q <= r_packet_len_q;
        end
        else 
            r_packet_len_q <= 16'h0;
    end

end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_bytes_read <= 17'h0;
    else begin
        if (I_enable) begin
            if (R_MS == STATE_WAIT_HDR) 
                r_bytes_read <= 16'h0;
            else if (R_MS == STATE_RX_PAYLOAD) begin 
                if (r_bytes_read < r_packet_len_q && I_data_valid) 
                    r_bytes_read <= r_bytes_read + 4;
                else 
                    r_bytes_read <= r_bytes_read;
            end
            else 
                r_bytes_read <= r_bytes_read;
        end
        else
            r_bytes_read   <= 17'h0;
    end
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        O_payload_valid <= 1'b0;
    else begin 
        if (I_enable) begin
            if (R_MS == STATE_RX_PAYLOAD && I_data_valid && r_bytes_read < r_packet_len_q) 
                O_payload_valid <= 1'b1;
            else 
                O_payload_valid <= 1'b0;
        end
        else 
            O_payload_valid <= 1'b0;
    end
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        O_payload_out   <= 32'h0;
    else begin 
        if (I_enable) begin
            
            if (R_MS == STATE_RX_PAYLOAD && I_data_valid && r_bytes_read < r_packet_len_q) 
                O_payload_out   <= I_data;
            else 
                O_payload_out <= 32'h0;
        end
        else 
        O_payload_out   <= 32'h0; 
    end
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_in_frame_d <= 1'b0;
    else begin
        if (I_enable) begin
            if (R_MS == STATE_WAIT_HDR && w_valid_packet) begin            
                case (w_packet_type)              
                    8'h00: r_in_frame_d <= 1'b1;  
                    8'h01: r_in_frame_d <= 1'b0;  
                endcase
            end 
            else r_in_frame_d <= r_in_frame_d;
        end
        else r_in_frame_d <= r_in_frame_d;
    end 
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_in_line_d  <= 1'b0; 
    else begin
        if (I_enable) begin
            if (R_MS == STATE_WAIT_HDR  && w_valid_packet) begin        
                
                if ((w_packet_type[7:4] == 4'h1) ||  
                    (w_packet_type[7:4] == 4'h2) ||  
                    (w_packet_type[7:4] == 4'h3))    
                    r_in_line_d <= 1'b1;
                else
                    r_in_line_d <= 1'b0;                 
            end 
            else 
                r_in_line_d <= 1'b0;
        end
        else 
        r_in_line_d  <= 1'b0; 
    end 
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_packet_done <= 1'b0; 
    else begin 
        if (I_enable) begin
            if (R_MS_NEXT == STATE_PKT_END) 
                r_packet_done <= 1'b1;
            else 
                r_packet_done <= 1'b0;
        end
        else 
        r_packet_done <= 1'b0; 
    end
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_error_cunt <= 5'b0; 
    else begin 
        if (I_enable) begin
            if (R_MS == STATE_RX_PAYLOAD) begin
                if (!r_data_valid &!I_data_valid) 
                    r_error_cunt <= r_error_cunt + 1'b1; 
                else
                    r_error_cunt <= 5'b0; 
            end
            else 
            r_error_cunt <= 5'b0; 
        end
        else 
        r_error_cunt <= 5'b0; 
    end
end

always @(posedge I_clock or negedge I_reset_n) begin
    if (!I_reset_n) 
        r_data_valid <= 1'b0; 
    else begin 
        if (I_enable) 
            r_data_valid <= I_data_valid;
        else 
            r_data_valid <= 1'b0; 
    end
end

assign O_header_attempt = I_enable && R_MS == STATE_WAIT_HDR && I_data_valid && !drain_tail && !r_packet_done;
assign O_header_valid = w_valid_packet;
assign O_header_ecc_bad = I_data[31:24] != w_expected_ecc;
assign O_header_filter_bad = !is_allowed_type(w_packet_type) || I_data[7:6] != VC_ID[1:0];
assign O_payload_timeout = I_enable && R_MS == STATE_RX_PAYLOAD && r_error_cunt == 5'h1f;
assign O_vsync_out    = (R_MS == STATE_WAIT_HDR) && 
                        (w_packet_type == 8'h00) && 
                        w_valid_packet;
                
assign O_in_frame     = r_in_frame_d;
assign O_in_line      = r_in_line_d;
assign O_packet_done  = r_packet_done;
assign O_sync_wait   = R_MS == STATE_WAIT_HDR;

endmodule


