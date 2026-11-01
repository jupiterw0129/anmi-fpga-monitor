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
/*********ui_line_buffer_demosaic ******************************
--版本�?1.0  
*****************************************************************/

module ui_line_buffer_demosaic (
    input           I_clk	,    // 输入时钟信号
    input           I_rst_n	,    // 输入复位信号，低电平有效
    input   [12:0]  I_img_width,  // Runtime image width
    input           I_tuser	,    // 输入tuser信号，帧起�?�标�? 
    input           I_valid	,    // 输入数据有效信号          
    input   [32:0]  I_data	,    // 输入数据总线，�?�度�?33�?  
    output          O_valid	,    // 输出数据有效信号          
    output  [32:0]  O_data       // 输出数据总线，�?�度�?33�?  
);

    // 定义局部参数，计算图像宽度的四分之一，用于地址计数
    wire [12:0] img_width_4x = (I_img_width >> 2);

    // 定义读使能信�?
    wire        rd_en;  // synthesis keep 

    // 定义地址计数器寄存器和数�?寄存�?
    reg  [10:0] addra;     // 写地址计数�?               
    reg  [10:0] addrb;     // 读地址计数�?               
    reg  [32:0] data_d0;   // 延时一�?时钟的数�?         
    reg         valid_d0;  // 延时一�?时钟的数�?有效信号  
	
	reg 		tlast_lock_d0;
	
	
	// 读使能信号rd_en的生�?
    assign rd_en = (I_valid && tlast_lock_d0) ? 1'b1 : 1'b0;
    // �?有当I_valid有效且tlast_lock_d0�?位后，才产生读使能信�?
	
	// 输出有效信号O_valid的生�?
    assign O_valid = (valid_d0 && tlast_lock_d0) ? 1'b1 : 1'b0;
    // �?有当valid_d0有效且tlast_lock_d0�?位后，才输出有效数据

    // 数据和有效信号的寄存，延时一�?时钟
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            data_d0  <= 0;            // 复位时将data_d0清零
            valid_d0 <= 0;            // 复位时将valid_d0清零
        end else begin
            data_d0  <= I_data;       // 正常工作时，data_d0跟随I_data
            valid_d0 <= I_valid;      // 正常工作时，valid_d0跟随I_valid
        end
    end

    // 写地址计数器addra的更�?
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            addra <= 0;    // 复位或者I_tuser有效时，将addra清零
        end else if (valid_d0) begin
            // 当valid_d0有效时，更新addra
            addra <= (addra == img_width_4x - 1) ? 0 : addra + 1'b1;
            // 如果addra达到最大值（IMG_WIDTH_4x - 1），则清零，否则�?1
        end
    end

    // 行结束标志tlast_lock_d0的更�?

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            tlast_lock_d0 <= 1'b0;  // 复位或者I_tuser有效时，将tlast_lock_d0清零
        end else if ((tlast_lock_d0 == 1'b0) & (addra == img_width_4x - 1)) begin
            tlast_lock_d0 <= 1'b1;  // 当�??一�?addra达到最大值时，置位tlast_lock_d0
        end
    end

    // 读地址计数器addrb的更�?
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            addrb <= 0;    // 复位或者I_tuser有效时，将addrb清零
        end else begin
            // 当rd_en有效时，更新addrb
            addrb <= rd_en ? ((addrb == img_width_4x - 1) ? 0 : addrb + 1'b1) : addrb;
            // 如果addrb达到最大值（IMG_WIDTH_4x - 1），则清零，否则�?1
            // 如果rd_en无效，addrb保持不变
        end
    end

    // 实例化块存储�?，用于数�?的存储和读取
    ui_ram_demosaic X_ui_ram_demosaic_demosaic (
        .clka 	(I_clk  )	,	// 写�??口时钟信�?
        .wea  	(valid_d0)	,  	// 写使能信�?
        .addra	(addra  )	,  	// 写地址
        .dia 	(data_d0)	,   // 写数�?
        .clkb 	(I_clk  )	,   // 读�??口时钟信�?
        .addrb	(addrb  )	,   // 读地址
        .dob	(O_data )    	// 读数�?输出
    );

endmodule

