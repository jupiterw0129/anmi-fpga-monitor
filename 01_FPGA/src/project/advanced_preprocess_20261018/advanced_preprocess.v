module advanced_preprocess (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [1:0]  requested_mode,
    input  wire [7:0]  requested_threshold,
    output reg  [1:0]  active_mode,
    output reg  [7:0]  active_threshold,
    input  wire [95:0] input_data,
    input  wire        input_valid,
    output wire        input_ready,
    input  wire        input_last,
    input  wire        input_user,
    output reg  [95:0] output_data,
    output reg         output_valid,
    input  wire        output_ready,
    output reg         output_last,
    output reg         output_user
);
    reg [1:0] mode_pipe;
    reg [7:0] threshold_pipe;
    reg        pending;
    integer pixel_index;

    assign input_ready = output_ready || !pending;

    function [7:0] luma;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        reg [15:0] red_wide, green_wide, blue_wide;
        reg [15:0] value;
        begin
            red_wide = {8'd0, red};
            green_wide = {8'd0, green};
            blue_wide = {8'd0, blue};
            value = (red_wide << 6) + (red_wide << 3) + (red_wide << 2) + red_wide
                  + (green_wide << 7) + (green_wide << 4) + (green_wide << 2) + (green_wide << 1)
                  + (blue_wide << 4) + (blue_wide << 3) + (blue_wide << 2) + blue_wide;
            luma = value >> 8;
        end
    endfunction

    function [7:0] gamma_value;
        input [7:0] value;
        begin
            case (value)
                8'd0: gamma_value = 8'd0;
                8'd1: gamma_value = 8'd0;
                8'd2: gamma_value = 8'd0;
                8'd3: gamma_value = 8'd0;
                8'd4: gamma_value = 8'd0;
                8'd5: gamma_value = 8'd0;
                8'd6: gamma_value = 8'd0;
                8'd7: gamma_value = 8'd0;
                8'd8: gamma_value = 8'd0;
                8'd9: gamma_value = 8'd0;
                8'd10: gamma_value = 8'd0;
                8'd11: gamma_value = 8'd0;
                8'd12: gamma_value = 8'd1;
                8'd13: gamma_value = 8'd1;
                8'd14: gamma_value = 8'd1;
                8'd15: gamma_value = 8'd1;
                8'd16: gamma_value = 8'd1;
                8'd17: gamma_value = 8'd1;
                8'd18: gamma_value = 8'd1;
                8'd19: gamma_value = 8'd1;
                8'd20: gamma_value = 8'd2;
                8'd21: gamma_value = 8'd2;
                8'd22: gamma_value = 8'd2;
                8'd23: gamma_value = 8'd2;
                8'd24: gamma_value = 8'd2;
                8'd25: gamma_value = 8'd2;
                8'd26: gamma_value = 8'd3;
                8'd27: gamma_value = 8'd3;
                8'd28: gamma_value = 8'd3;
                8'd29: gamma_value = 8'd3;
                8'd30: gamma_value = 8'd4;
                8'd31: gamma_value = 8'd4;
                8'd32: gamma_value = 8'd4;
                8'd33: gamma_value = 8'd4;
                8'd34: gamma_value = 8'd5;
                8'd35: gamma_value = 8'd5;
                8'd36: gamma_value = 8'd5;
                8'd37: gamma_value = 8'd5;
                8'd38: gamma_value = 8'd6;
                8'd39: gamma_value = 8'd6;
                8'd40: gamma_value = 8'd6;
                8'd41: gamma_value = 8'd7;
                8'd42: gamma_value = 8'd7;
                8'd43: gamma_value = 8'd7;
                8'd44: gamma_value = 8'd8;
                8'd45: gamma_value = 8'd8;
                8'd46: gamma_value = 8'd8;
                8'd47: gamma_value = 8'd9;
                8'd48: gamma_value = 8'd9;
                8'd49: gamma_value = 8'd9;
                8'd50: gamma_value = 8'd10;
                8'd51: gamma_value = 8'd10;
                8'd52: gamma_value = 8'd11;
                8'd53: gamma_value = 8'd11;
                8'd54: gamma_value = 8'd11;
                8'd55: gamma_value = 8'd12;
                8'd56: gamma_value = 8'd12;
                8'd57: gamma_value = 8'd13;
                8'd58: gamma_value = 8'd13;
                8'd59: gamma_value = 8'd14;
                8'd60: gamma_value = 8'd14;
                8'd61: gamma_value = 8'd15;
                8'd62: gamma_value = 8'd15;
                8'd63: gamma_value = 8'd16;
                8'd64: gamma_value = 8'd16;
                8'd65: gamma_value = 8'd17;
                8'd66: gamma_value = 8'd17;
                8'd67: gamma_value = 8'd18;
                8'd68: gamma_value = 8'd18;
                8'd69: gamma_value = 8'd19;
                8'd70: gamma_value = 8'd19;
                8'd71: gamma_value = 8'd20;
                8'd72: gamma_value = 8'd20;
                8'd73: gamma_value = 8'd21;
                8'd74: gamma_value = 8'd21;
                8'd75: gamma_value = 8'd22;
                8'd76: gamma_value = 8'd23;
                8'd77: gamma_value = 8'd23;
                8'd78: gamma_value = 8'd24;
                8'd79: gamma_value = 8'd24;
                8'd80: gamma_value = 8'd25;
                8'd81: gamma_value = 8'd26;
                8'd82: gamma_value = 8'd26;
                8'd83: gamma_value = 8'd27;
                8'd84: gamma_value = 8'd28;
                8'd85: gamma_value = 8'd28;
                8'd86: gamma_value = 8'd29;
                8'd87: gamma_value = 8'd30;
                8'd88: gamma_value = 8'd30;
                8'd89: gamma_value = 8'd31;
                8'd90: gamma_value = 8'd32;
                8'd91: gamma_value = 8'd32;
                8'd92: gamma_value = 8'd33;
                8'd93: gamma_value = 8'd34;
                8'd94: gamma_value = 8'd35;
                8'd95: gamma_value = 8'd35;
                8'd96: gamma_value = 8'd36;
                8'd97: gamma_value = 8'd37;
                8'd98: gamma_value = 8'd38;
                8'd99: gamma_value = 8'd38;
                8'd100: gamma_value = 8'd39;
                8'd101: gamma_value = 8'd40;
                8'd102: gamma_value = 8'd41;
                8'd103: gamma_value = 8'd42;
                8'd104: gamma_value = 8'd42;
                8'd105: gamma_value = 8'd43;
                8'd106: gamma_value = 8'd44;
                8'd107: gamma_value = 8'd45;
                8'd108: gamma_value = 8'd46;
                8'd109: gamma_value = 8'd47;
                8'd110: gamma_value = 8'd47;
                8'd111: gamma_value = 8'd48;
                8'd112: gamma_value = 8'd49;
                8'd113: gamma_value = 8'd50;
                8'd114: gamma_value = 8'd51;
                8'd115: gamma_value = 8'd52;
                8'd116: gamma_value = 8'd53;
                8'd117: gamma_value = 8'd54;
                8'd118: gamma_value = 8'd55;
                8'd119: gamma_value = 8'd56;
                8'd120: gamma_value = 8'd56;
                8'd121: gamma_value = 8'd57;
                8'd122: gamma_value = 8'd58;
                8'd123: gamma_value = 8'd59;
                8'd124: gamma_value = 8'd60;
                8'd125: gamma_value = 8'd61;
                8'd126: gamma_value = 8'd62;
                8'd127: gamma_value = 8'd63;
                8'd128: gamma_value = 8'd64;
                8'd129: gamma_value = 8'd65;
                8'd130: gamma_value = 8'd66;
                8'd131: gamma_value = 8'd67;
                8'd132: gamma_value = 8'd68;
                8'd133: gamma_value = 8'd69;
                8'd134: gamma_value = 8'd70;
                8'd135: gamma_value = 8'd71;
                8'd136: gamma_value = 8'd73;
                8'd137: gamma_value = 8'd74;
                8'd138: gamma_value = 8'd75;
                8'd139: gamma_value = 8'd76;
                8'd140: gamma_value = 8'd77;
                8'd141: gamma_value = 8'd78;
                8'd142: gamma_value = 8'd79;
                8'd143: gamma_value = 8'd80;
                8'd144: gamma_value = 8'd81;
                8'd145: gamma_value = 8'd82;
                8'd146: gamma_value = 8'd84;
                8'd147: gamma_value = 8'd85;
                8'd148: gamma_value = 8'd86;
                8'd149: gamma_value = 8'd87;
                8'd150: gamma_value = 8'd88;
                8'd151: gamma_value = 8'd89;
                8'd152: gamma_value = 8'd91;
                8'd153: gamma_value = 8'd92;
                8'd154: gamma_value = 8'd93;
                8'd155: gamma_value = 8'd94;
                8'd156: gamma_value = 8'd95;
                8'd157: gamma_value = 8'd97;
                8'd158: gamma_value = 8'd98;
                8'd159: gamma_value = 8'd99;
                8'd160: gamma_value = 8'd100;
                8'd161: gamma_value = 8'd102;
                8'd162: gamma_value = 8'd103;
                8'd163: gamma_value = 8'd104;
                8'd164: gamma_value = 8'd105;
                8'd165: gamma_value = 8'd107;
                8'd166: gamma_value = 8'd108;
                8'd167: gamma_value = 8'd109;
                8'd168: gamma_value = 8'd111;
                8'd169: gamma_value = 8'd112;
                8'd170: gamma_value = 8'd113;
                8'd171: gamma_value = 8'd115;
                8'd172: gamma_value = 8'd116;
                8'd173: gamma_value = 8'd117;
                8'd174: gamma_value = 8'd119;
                8'd175: gamma_value = 8'd120;
                8'd176: gamma_value = 8'd121;
                8'd177: gamma_value = 8'd123;
                8'd178: gamma_value = 8'd124;
                8'd179: gamma_value = 8'd126;
                8'd180: gamma_value = 8'd127;
                8'd181: gamma_value = 8'd128;
                8'd182: gamma_value = 8'd130;
                8'd183: gamma_value = 8'd131;
                8'd184: gamma_value = 8'd133;
                8'd185: gamma_value = 8'd134;
                8'd186: gamma_value = 8'd136;
                8'd187: gamma_value = 8'd137;
                8'd188: gamma_value = 8'd139;
                8'd189: gamma_value = 8'd140;
                8'd190: gamma_value = 8'd142;
                8'd191: gamma_value = 8'd143;
                8'd192: gamma_value = 8'd145;
                8'd193: gamma_value = 8'd146;
                8'd194: gamma_value = 8'd148;
                8'd195: gamma_value = 8'd149;
                8'd196: gamma_value = 8'd151;
                8'd197: gamma_value = 8'd152;
                8'd198: gamma_value = 8'd154;
                8'd199: gamma_value = 8'd155;
                8'd200: gamma_value = 8'd157;
                8'd201: gamma_value = 8'd158;
                8'd202: gamma_value = 8'd160;
                8'd203: gamma_value = 8'd162;
                8'd204: gamma_value = 8'd163;
                8'd205: gamma_value = 8'd165;
                8'd206: gamma_value = 8'd166;
                8'd207: gamma_value = 8'd168;
                8'd208: gamma_value = 8'd170;
                8'd209: gamma_value = 8'd171;
                8'd210: gamma_value = 8'd173;
                8'd211: gamma_value = 8'd175;
                8'd212: gamma_value = 8'd176;
                8'd213: gamma_value = 8'd178;
                8'd214: gamma_value = 8'd180;
                8'd215: gamma_value = 8'd181;
                8'd216: gamma_value = 8'd183;
                8'd217: gamma_value = 8'd185;
                8'd218: gamma_value = 8'd186;
                8'd219: gamma_value = 8'd188;
                8'd220: gamma_value = 8'd190;
                8'd221: gamma_value = 8'd192;
                8'd222: gamma_value = 8'd193;
                8'd223: gamma_value = 8'd195;
                8'd224: gamma_value = 8'd197;
                8'd225: gamma_value = 8'd199;
                8'd226: gamma_value = 8'd200;
                8'd227: gamma_value = 8'd202;
                8'd228: gamma_value = 8'd204;
                8'd229: gamma_value = 8'd206;
                8'd230: gamma_value = 8'd207;
                8'd231: gamma_value = 8'd209;
                8'd232: gamma_value = 8'd211;
                8'd233: gamma_value = 8'd213;
                8'd234: gamma_value = 8'd215;
                8'd235: gamma_value = 8'd217;
                8'd236: gamma_value = 8'd218;
                8'd237: gamma_value = 8'd220;
                8'd238: gamma_value = 8'd222;
                8'd239: gamma_value = 8'd224;
                8'd240: gamma_value = 8'd226;
                8'd241: gamma_value = 8'd228;
                8'd242: gamma_value = 8'd230;
                8'd243: gamma_value = 8'd232;
                8'd244: gamma_value = 8'd233;
                8'd245: gamma_value = 8'd235;
                8'd246: gamma_value = 8'd237;
                8'd247: gamma_value = 8'd239;
                8'd248: gamma_value = 8'd241;
                8'd249: gamma_value = 8'd243;
                8'd250: gamma_value = 8'd245;
                8'd251: gamma_value = 8'd247;
                8'd252: gamma_value = 8'd249;
                8'd253: gamma_value = 8'd251;
                8'd254: gamma_value = 8'd253;
                8'd255: gamma_value = 8'd255;
                default: gamma_value = 0;
            endcase
        end
    endfunction

    function [7:0] threshold_value;
        input [7:0] value;
        input [7:0] threshold;
        begin
            threshold_value = value >= threshold ? 8'hff : 8'h00;
        end
    endfunction

    function [7:0] transform_channel;
        input [7:0] value;
        input [7:0] pixel_luma;
        input [1:0] mode;
        input [7:0] threshold;
        begin
            case (mode)
                2'd1: transform_channel = gamma_value(value);
                2'd2: transform_channel = threshold_value(pixel_luma, threshold);
                default: transform_channel = value;
            endcase
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_mode      <= 0;
            active_threshold <= 0;
            mode_pipe        <= 0;
            threshold_pipe   <= 0;
            output_data      <= 0;
            output_valid     <= 0;
            output_last      <= 0;
            output_user      <= 0;
            pending          <= 0;
        end else if (input_ready) begin
            output_valid <= input_valid;
            output_last  <= input_last;
            output_user  <= input_user;
            pending      <= input_valid;
            if (input_valid) begin
                if (input_user) begin
                    active_mode      <= requested_mode;
                    active_threshold <= requested_threshold;
                    mode_pipe        <= requested_mode;
                    threshold_pipe   <= requested_threshold;
                end
                for (pixel_index = 0; pixel_index < 4; pixel_index = pixel_index + 1) begin
                    output_data[pixel_index*24 +: 8] <= transform_channel(
                        input_data[pixel_index*24 +: 8],
                        luma(input_data[pixel_index*24+16 +: 8],
                             input_data[pixel_index*24+8 +: 8],
                             input_data[pixel_index*24 +: 8]),
                        input_user ? requested_mode : mode_pipe,
                        input_user ? requested_threshold : threshold_pipe);
                    output_data[pixel_index*24+8 +: 8] <= transform_channel(
                        input_data[pixel_index*24+8 +: 8],
                        luma(input_data[pixel_index*24+16 +: 8],
                             input_data[pixel_index*24+8 +: 8],
                             input_data[pixel_index*24 +: 8]),
                        input_user ? requested_mode : mode_pipe,
                        input_user ? requested_threshold : threshold_pipe);
                    output_data[pixel_index*24+16 +: 8] <= transform_channel(
                        input_data[pixel_index*24+16 +: 8],
                        luma(input_data[pixel_index*24+16 +: 8],
                             input_data[pixel_index*24+8 +: 8],
                             input_data[pixel_index*24 +: 8]),
                        input_user ? requested_mode : mode_pipe,
                        input_user ? requested_threshold : threshold_pipe);
                end
            end
        end
    end
endmodule
