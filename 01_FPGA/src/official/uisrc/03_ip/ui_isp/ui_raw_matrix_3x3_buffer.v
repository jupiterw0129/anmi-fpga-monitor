
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ui_raw_matrix_3x3_buffer ******************************
该模块主要是用于3x3矩阵的形成，以及对图像边界像素的处理
在原基�?�上优化了时序，把原来的一些未完全对齐的信号进行�?�齐�?
--版本�?1.0  
*****************************************************************/

module ui_raw_matrix_3x3_buffer #(
    parameter 			data_complete_delay = 50
)
(
    input           	I_clk   			,  // 时钟信号
    input           	I_rst_n 			,  // 复位信号，低电平有效

    input   [12:0]      I_img_width     ,  // Runtime image width
    input   [12:0]      I_img_height    ,  // Runtime image height

    input [39:0]  		I_axi4s_video_tdata ,  // AXI4-Stream视�?�数�?
    input [9:0]   		I_axi4s_video_tdest ,
    input         		I_axi4s_video_tlast ,  // 行结束信�?
    input         		I_axi4s_video_tvalid,  // 数据有效信号
    input         		I_axi4s_video_tuser ,  // 帧开始信�?
    output        		I_axi4s_video_tready,  // 从模块准备好接受数据
		
    output        		O_tlast         	,   // 行结束信号输�?
    output        		O_tuser         	,   // 帧开始信号输�?
    output        		O_tvalid        	,   // 数据有效信号输出
    input         		O_tready        	,   // 上一级模块准备好接受数据
			
    output        		bayer_ypos      	,   // Bayer滤波器�?�位�?
    output  [95:0]		matrix_last_line	,   // 上一�?3x3矩阵数据
    output  [95:0]		matrix_cur_line 	,   // 当前�?3x3矩阵数据
    output  [95:0]		matrix_next_line        // 下一�?3x3矩阵数据
);


/*********************************************************
******************1.功能声明*******************************
*********************************************************/
// 计算数据的位�?
function integer clog2b(
    input integer depth
);
    begin
        for(clog2b=0; depth>0; clog2b=clog2b+1)begin
            depth = depth >> 1;
        end
    end    
endfunction

/*********************************************************
******************2.常数声明*******************************
*********************************************************/
localparam N = 3;  // 矩阵大小�?3x3

localparam DATA_WIDTH   = 32;  // 数据位�??

wire [12:0] IMG_WIDTH_4x = (I_img_width >> 2);  // 图像宽度除以4，得到每�?数据块的数量

/*********************************************************
******************3.信号声明*******************************
*********************************************************/
// 定义线网信号
wire                        zhenghe_tlast 	;    // 合并后的行结束信�?
wire                        zhenghe_tuser 	;    // 合并后的帧开始信�?
wire  [31:0]                zhenghe_tdata 	;    // 合并后的数据
wire                        zhenghe_tvalid	;    // 合并后的数据有效信号

wire  [DATA_WIDTH-1:0]      raw_data        ;    // 原�?�数�?
wire                        raw_data_valid  ;    // 原�?�数�?有效信号

wire                		valid   [0:N-1] ;    // 有效信号数组
wire [DATA_WIDTH:0] 		data    [0:N-1] ;    // 数据数组（包含tuser位）

wire                		O_raw_tlast_d0	;    // 行结束信号，延迟0周期
wire                		O_raw_tuser_d0	;    // 帧开始信号，延迟0周期
wire                		I_raw_tready	;    // 模块准�?�好接受原�?�数�?
wire [32:0]         		next_line_data	;    // 下一行数�?
wire [32:0]         		data_d2			;    // 数据延迟2�?周期
wire                		next_line_start	;    // 下一行的开始信�?
wire                		bayer_ypos_d0	;    // Bayer位置，延�?0周期

/*********************************************************
******************4.寄存器信号声�?*************************
*********************************************************/
// 定义寄存器信�?
reg [95:0]      matrix_cur_line_buffer       ; // 当前行的3x3矩阵缓冲
reg [95:0]      matrix_last_line_buffer      ; // 上一行的3x3矩阵缓冲
reg [95:0]      matrix_next_line_buffer      ; // 下一行的3x3矩阵缓冲
reg             tlast_d0,tlast_d1,tlast_d2;     // 行结束信号延迟寄存器
reg             tuser_d0,tuser_d1,tuser_d2;     // 帧开始信号延迟寄存器
reg             ch_valid;                       // 数据通道有效信号
reg [13:0]      h_cnt;                          // 水平像素计数�?
reg [13:0]      v_cnt,v_cnt_d;                  // 垂直像素计数器及其延�?
reg             next_line_data_valid;           // 下一行数�?有效信号
reg             valid_d0,valid_d1;              // 有效信号延迟寄存�?
reg             bayer_ypos_d;                   // Bayer位置延迟寄存�?
reg  [32:0]     data_d0_d,data_d0;              // 数据延迟寄存�?
reg  [32:0]     data_d1;

/*********************************************************
******************5.组合逻辑******************************
*********************************************************/
// 将数�?和有效信号进行连�?
assign data[0]  = {zhenghe_tuser, zhenghe_tdata};  // 将tuser和数�?拼接
assign valid[0] = zhenghe_tvalid;                  // �?一�?有效信号

// 将准备信号连接到上级模块
assign I_axi4s_video_tready = O_tready;

/*********************************************************/
// 将矩阵缓冲输�?
assign matrix_last_line = matrix_last_line_buffer;
assign matrix_cur_line  = matrix_cur_line_buffer ;
assign matrix_next_line = matrix_next_line_buffer;

// 计算Bayer滤波器的行位�?
assign bayer_ypos_d0 = !v_cnt_d[0] & ch_valid;

/*********************************************************
******************6.模块实例�?*****************************
*********************************************************/
// 实例化mipi_to_raw_converter模块，将MIPI协�??的数�?�?�?为RAW数据
ui_mipi_to_raw_converter X_ui_mipi_to_raw_converter(
    .I_clk       (I_clk  ),              // 时钟信号
    .I_rst_n     (I_rst_n),              // 复位信号，低有效
    .I_raw_tdata (I_axi4s_video_tdata ),   // 输入原�?�数�?
    .I_raw_tdest (I_axi4s_video_tdest ),   // 输入�?的地地址
    .I_raw_tlast (I_axi4s_video_tlast ),   // 输入行结束信�?
    .I_raw_tvalid(I_axi4s_video_tvalid),   // 输入数据有效信号
    .I_raw_tuser (I_axi4s_video_tuser),    // 输入帧开始信�?
    .I_raw_tready(I_raw_tready  ),       // 输出准�?�好信号
    .O_raw_tdata (raw_data      ),       // 输出原�?�数�?
    .O_raw_tlast (O_raw_tlast_d0),       // 输出行结束信�?
    .O_raw_tvalid(raw_data_valid),       // 输出数据有效信号
    .O_raw_tuser (O_raw_tuser_d0),       // 输出帧开始信�?
    .O_raw_tready(1)                     // 模块始终准�?�好接受数据
);

// 实例化“zhenghe”模块，将数�?进�?�合并�?�理
ui_zhenghe#(
    .DATA_WIDTH( 32),
    .data_complete_delay (data_complete_delay)
) 
X_ui_zhenghe(
    .I_clk    (I_clk   ),               // 时钟信号
    .I_rst_n  (I_rst_n ),               // 复位信号，低电平有效

    .I_img_width (I_img_width),          // Runtime image width

    .I_tlast  (O_raw_tlast_d0 ),        // 输入行结束信�?
    .I_tuser  (O_raw_tuser_d0 ),        // 输入帧开始信�?
    .I_tdata  (raw_data ),              // 输入原�?�数�?
    .I_tvalid (raw_data_valid),         // 输入数据有效信号

    .O_tlast  (zhenghe_tlast ),         // 输出合并后的行结束信�?
    .O_tuser  (zhenghe_tuser ),         // 输出合并后的帧开始信�?
    .O_tdata  (zhenghe_tdata ),         // 输出合并后的数据
    .O_tvalid (zhenghe_tvalid)          // 输出合并后的数据有效信号
);

// 生成两�?�缓冲区，使用线性缓冲区实现3x3矩阵的�?�数�?缓存
genvar i;
generate
    for(i=1; i<3; i=i+1)
    begin: two_line_buffer  // 模块命名为two_line_buffer
        ui_line_buffer_demosaic X_ui_line_buffer_demosaic (
            .I_clk     ( I_clk      ),    // 时钟信号
            .I_rst_n   ( I_rst_n    ),    // 复位信号，低电平有效
            .I_img_width( I_img_width),    // Runtime image width
            .I_tuser   ( data[i-1][32] & valid[i-1]), // 输入帧开始信�?
            .I_valid   ( valid[i-1] ),    // 输入有效信号
            .I_data    ( data[i-1]  ),    // 输入数据
            .O_valid   ( valid[i]   ),    // 输出有效信号
            .O_data    ( data[i]    )     // 输出数据
        );           
    end        
endgenerate

// 由于在BRAM�?每�?�输出数�?都会延迟一�?周期，所以�?�使这些数据对齐，需要�?�这些数�?进�?�延迟�?�理，其中data[0]延迟2�?周期，data[1]延迟一�?周期
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        data_d0_d <= 0;
        data_d0   <= 0;
        data_d1   <= 0;
        valid_d0  <= 0;
        valid_d1  <= 0;
    end
    else begin
        valid_d0  <= valid[0];
        valid_d1  <= valid_d0;
        data_d0_d <= data[0];
        data_d0   <= data_d0_d;
        data_d1   <= data[1];
    end
end

assign data_d2 = data[2];
/*********************************************************
***********3x3矩阵的形成，以及对边界元素的补充处理***********
*********************************************************/

always @(posedge I_clk or negedge I_rst_n) begin 
    if(!I_rst_n) begin
        matrix_last_line_buffer <= 'b0 ;
        matrix_cur_line_buffer  <= 'b0 ;
        matrix_next_line_buffer <= 'b0 ;
    end else if(valid_d1) begin
        if(v_cnt == 0) begin  // �?一�?
            if(h_cnt == 0) begin  // �?一行的�?一�?像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // �?一行的最后一�?像素
                matrix_last_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // �?一行的�?间像�?
                matrix_last_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end
        end
        else if(v_cnt == 1) begin  // �?二�??
            if(h_cnt == 0) begin  // �?二�?�的�?一�?像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // �?二�?�的最后一�?像素
                matrix_last_line_buffer <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer[7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // �?二�?�的�?间像�?
                matrix_last_line_buffer <= {matrix_cur_line_buffer[63:0],  data_d1[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer[63:0],  data_d1[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end
        end
        else begin  // �?三�?�及以后
            if(h_cnt == 0) begin  // �?一�?像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d2[31:24], data_d2[31:0], data_d2[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // 最后一�?像素
                matrix_last_line_buffer <= {matrix_last_line_buffer[63:0], matrix_last_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer [7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // �?间像�?
                matrix_last_line_buffer <= {matrix_last_line_buffer[63:0], data_d2[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end  
        end
    end
    else begin
        matrix_last_line_buffer <= 'b0 ;
        matrix_cur_line_buffer  <= 'b0 ;
        matrix_next_line_buffer <= 'b0 ;
    end 
end

// 计算水平和垂直�?�数�?
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n || zhenghe_tuser) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end else begin
        h_cnt    <= valid_d1 ? ((h_cnt == IMG_WIDTH_4x - 1) ? 0 : h_cnt + 1) : h_cnt;
        v_cnt    <= valid_d1 && (h_cnt == IMG_WIDTH_4x - 1) ? ((v_cnt == I_img_height - 1) ? 0 : v_cnt + 1) : v_cnt;
    end
end

// 数据有效信号的延迟�?�理
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        ch_valid <= 0;
        v_cnt_d <= 0;
    end else begin
        ch_valid <= valid_d1 ;
        v_cnt_d  <= v_cnt;
    end
end

assign bayer_ypos = bayer_ypos_d0 ;

// 对tuser和tlast信号进�?�同步�?�理，�?�时数据和流控制信号已经同�??
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        tlast_d0 <= 0;
        tlast_d1 <= 0;
        tlast_d2 <= 0;
        tuser_d0 <= 0;
        tuser_d1 <= 0;
        tuser_d2 <= 0;
    end
    else begin
        tlast_d0 <= zhenghe_tlast;
        tlast_d1 <= tlast_d0;
        tlast_d2 <= tlast_d1;
        tuser_d0 <= zhenghe_tuser;
        tuser_d1 <= tuser_d0;
        tuser_d2 <= tuser_d1;
    end
end

// 将同步后的信号输�?
assign O_tuser  = tuser_d2;
assign O_tlast  = tlast_d2;
assign O_tvalid = ch_valid;


endmodule


