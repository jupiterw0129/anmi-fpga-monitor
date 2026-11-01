/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基�?�上删去了一些赘余的代码，并且优化了时序，加�?BRAM IP核，
                 让从除法器出来的每一�?数据都可以�?�上相应的像素数�?进�?��?�益，使
                 得它的适用行更加广泛了�?
*****************************************************************/
module ui_awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk  ,
    input                   I_rst_n,

    input  wire [12:0]      I_img_width,   // Runtime image width
    input  wire [12:0]      I_img_height,  // Runtime image height

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);


/*****************************************************************
                          �?间信�?                                        
*****************************************************************/

reg         I_tvalid_r0,I_tvalid_r1;          // 输入有效信号的寄�?
reg  [95:0] I_tdata_d0,I_tdata_d1,I_tdata_d2; // 输入数据的寄�?

// �?加RGB通道的数值，用于计算平均�?
reg  [33:0]         sum_r;
reg  [33:0]         sum_g;
reg  [33:0]         sum_b;

wire  [95:0]        data_d0 ;     // 延时后的数据
wire                valid_d0;     // 延时后的有效信号
wire                I_tuser_r0;   // 延时后的帧开始信�?

reg                 I_tuser_r1;   // 帧开始信号的寄存

reg   [95:0]        data_d1 ;     // 再�?�延时后的数�?
reg                 valid_d1;     // 再�?�延时后的有效信�?
localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);  // 图像宽度除以4，得到每�?数据块的数量

/*****************************************************************
                           平均值�?�算                                        
*****************************************************************/

// 对输入数�?和有效信号进行寄存，形成流水�?
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        I_tdata_d2  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tdata_d2  <= I_tdata_d1;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end


function [9:0] accepted_channel_sum;
    input [95:0] pixels;
    input integer channel_offset;
    integer pixel_index;
    reg [9:0] intensity;
    begin
        accepted_channel_sum = 0;
        for (pixel_index = 0; pixel_index < 4; pixel_index = pixel_index + 1) begin
            intensity = {2'b0, pixels[pixel_index*24 +: 8]}
                      + {2'b0, pixels[pixel_index*24+8 +: 8]}
                      + {2'b0, pixels[pixel_index*24+16 +: 8]};
            if (intensity < 700)
                accepted_channel_sum = accepted_channel_sum
                    + {2'b0, pixels[pixel_index*24+channel_offset +: 8]};
        end
    end
endfunction

reg [9:0] beat_red;
reg [9:0] beat_green;
reg [9:0] beat_blue;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        beat_red <= 0;
        beat_green <= 0;
        beat_blue <= 0;
    end else if (I_tvalid) begin
        beat_red <= accepted_channel_sum(I_tdata, 16);
        beat_green <= accepted_channel_sum(I_tdata, 8);
        beat_blue <= accepted_channel_sum(I_tdata, 0);
    end
end

    // Statistics belong to one complete input frame. Partial frames never
    // publish gains. I_tuser is aligned with the registered four-lane sum.
    reg stats_sof;
    reg stats_tracking;
    reg [23:0] stats_count, stats_goal;
    reg [33:0] frame_sum_r, frame_sum_g, frame_sum_b;
    reg divide_start;
    wire [23:0] configured_beats = {13'd0, I_img_width[12:2]}
                                      * {11'd0, I_img_height};
    wire geometry_valid = I_img_width >= 4 && I_img_width[1:0] == 0
                                             && I_img_height != 0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            stats_sof <= 0;
            stats_tracking <= 0;
            stats_count <= 0;
            stats_goal <= 0;
            frame_sum_r <= 1; frame_sum_g <= 1; frame_sum_b <= 1;
            sum_r <= 1; sum_g <= 1; sum_b <= 1;
            divide_start <= 0;
        end else begin
            stats_sof <= I_tuser;
            divide_start <= 0;
            if (I_tvalid_r0) begin
                if (stats_sof) begin
                    stats_count <= 1;
                    stats_goal <= configured_beats;
                    stats_tracking <= geometry_valid && configured_beats > 1;
                    frame_sum_r <= 34'd1 + beat_red;
                    frame_sum_g <= 34'd1 + beat_green;
                    frame_sum_b <= 34'd1 + beat_blue;
                    if (geometry_valid && configured_beats == 1) begin
                        sum_r <= 34'd1 + beat_red;
                        sum_g <= 34'd1 + beat_green;
                        sum_b <= 34'd1 + beat_blue;
                        divide_start <= 1;
                    end
                end else if (stats_tracking) begin
                    stats_count <= stats_count + 1'b1;
                    frame_sum_r <= frame_sum_r + beat_red;
                    frame_sum_g <= frame_sum_g + beat_green;
                    frame_sum_b <= frame_sum_b + beat_blue;
                    if (stats_count == stats_goal - 1'b1) begin
                        sum_r <= frame_sum_r + beat_red;
                        sum_g <= frame_sum_g + beat_green;
                        sum_b <= frame_sum_b + beat_blue;
                        divide_start <= 1;
                        stats_tracking <= 0;
                    end
                end
            end
        end
    end

  wire [31:0] scaled_sum_r = (|sum_r[33:2]) ? sum_r[33:2] : 32'd1;
  wire [31:0] scaled_sum_g = (|sum_g[33:2]) ? sum_g[33:2] : 32'd1;
  wire [31:0] scaled_sum_b = (|sum_b[33:2]) ? sum_b[33:2] : 32'd1;

  wire [47:0] dout_R;
  wire [47:0] dout_B;

  wire done;
  wire done_b;

  wire [47:0] in_r_x1;
  wire [47:0] in_b_x1;
  assign in_r_x1 = dout_R[47:0];
  assign in_b_x1 = dout_B[47:0];

    

/*****************************************************************
                   IP 调用                                    
*****************************************************************/
    //为了保证合理的延迟，这里使用了除法器


      divider div_gen_G_R_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(divide_start),
          .denominator(scaled_sum_r),  // input wire [31 : 0] s_axis_divisor_tdata
          .numerator({scaled_sum_g,16'd0}),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_R),  // output wire [79 : 0] m_axis_dout_tdata
          .done(done)
      );

      divider divide_G_B_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(divide_start),
          .denominator(scaled_sum_b),  // input wire [31 : 0] s_axis_divisor_tdata
          .numerator({scaled_sum_g,16'd0}),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_B),  // output wire [79 : 0] m_axis_dout_tdata
          .done(done_b)
      );

     
    ui_signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    )X_ui_signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input  wire [12:0]          */ .I_img_width (I_img_width ),
        /*input  wire [12:0]          */ .I_img_height(I_img_height),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );

    

/*****************************************************************
                            ????????                                      
*****************************************************************/

reg  [19:0]   in_r_r1;
reg  [19:0]   in_b_r1;


// Divider results are pending until a delayed output frame starts.
// Commit one cycle before multiplication, so the first pixel also uses the
// new gain. Reset keeps unity until a complete frame has been measured.
reg [19:0] pending_r, pending_b;
reg pending_valid;
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        pending_r <= 20'h10000; pending_b <= 20'h10000;
        pending_valid <= 0;
        in_r_r1 <= 20'h10000; in_b_r1 <= 20'h10000;
    end else begin
        if (done && done_b) begin
            pending_r <= (|in_r_x1[47:20]) ? 20'hfffff : in_r_x1[19:0];
            pending_b <= (|in_b_x1[47:20]) ? 20'hfffff : in_b_x1[19:0];
            pending_valid <= 1;
        end
        if (valid_d0 && I_tuser_r0 && pending_valid) begin
            in_r_r1 <= pending_r;
            in_b_r1 <= pending_b;
        end
    end
end
    ////信号同�??
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ????????                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
// 计算新的RGB值，应用增益
always @(posedge I_clk or negedge I_rst_n)begin 
    if(!I_rst_n)begin
        R_new_r1 <= 0;
        G_new_r1 <= 0;
        B_new_r1 <= 0;

        R_new_r2 <= 0;
        G_new_r2 <= 0;
        B_new_r2 <= 0;

        R_new_r3 <= 0;
        G_new_r3 <= 0;
        B_new_r3 <= 0;

        R_new_r4 <= 0;
        G_new_r4 <= 0;
        B_new_r4 <= 0;
    end
    else if(valid_d1) begin
        R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
        G_new_r1 <=           rgb888_g_d1[0];
        B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

        R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
        G_new_r2 <=           rgb888_g_d1[1];
        B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

        R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
        G_new_r3 <=           rgb888_g_d1[2];
        B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

        R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
        G_new_r4 <=           rgb888_g_d1[3];
        B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
    end
end

/*****************************************************************
                            ??????????                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (R_new_r1[27:24])?255:R_new_r1[23:16];
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24])?255:B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24])?255:R_new_r2[23:16];
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24])?255:B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24])?255:R_new_r3[23:16];
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24])?255:B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24])?255:R_new_r4[23:16];
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24])?255:B_new_r4[23:16];
/*****************************************************************
                           ??????                                       
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   
    assign  O_tuser  = I_tuser_r2 ;   
    assign  O_tvalid = valid_d2;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule





