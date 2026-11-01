    reg [31:0] raw_expected[0:2047];
    reg raw_sof[0:2047],raw_last[0:2047];
    reg [95:0] awb_expected[0:2047],first_demosaic[0:518399];
    reg awb_sof[0:2047],awb_last[0:2047];
    integer raw_written=0,raw_read=0,d_written=0,a_read=0;
    integer input_frame=-1,input_index=0,d_frame=-1,d_index=0,a_frame=-1,a_index=0;
    integer raw_pixels=0,awb_pixels=0,stable_pixels=0;
    longint unsigned red_sum=1,green_sum=1,blue_sum=1;
    longint unsigned gain_r[0:5],gain_b[0:5],sr,sg,sb;
    integer r,g,b,pr,pb,expected_sample;
    reg [95:0] expected_word;
    function integer sample(input integer fr,input integer row,input integer col);
        if(pattern==0) sample=128;
        else if(pattern==1) sample=row%2==0 ? (col%2==0?64:128) : (col%2==0?128:32);
        else if(pattern==2) sample=16+((fr*47+row*11+col)%192);
        else sample=row%2==0 ? (col%2==0?32+fr*8:96) : (col%2==0?96:64+fr*8);
    endfunction
    initial begin
        for(integer k=0;k<6;k=k+1) begin gain_r[k]=65536;gain_b[k]=65536;end
    end
    always @(posedge clk) begin
        #1;
        cycle=cycle+1;
        if(rst_n) begin
            if(demo.X_ui_raw_matrix_3x3_buffer.raw_data_valid) begin
                if(demo.X_ui_raw_matrix_3x3_buffer.O_raw_tuser_d0) begin
                    input_frame=input_frame+1;input_index=0;
                end
                for(integer k=0;k<4;k=k+1) begin
                    expected_sample=sample(input_frame,input_index/(width/4),(input_index%(width/4))*4+k);
                    if(demo.X_ui_raw_matrix_3x3_buffer.raw_data[31-k*8-:8]!==expected_sample[7:0])
                        $fatal(1,"INPUT_BLC_CONVERTER_ORACLE_FAIL");
                end
                raw_expected[raw_written%2048]=demo.X_ui_raw_matrix_3x3_buffer.raw_data;
                raw_sof[raw_written%2048]=demo.X_ui_raw_matrix_3x3_buffer.O_raw_tuser_d0;
                raw_last[raw_written%2048]=demo.X_ui_raw_matrix_3x3_buffer.O_raw_tlast_d0;
                raw_written=raw_written+1;input_index=input_index+1;
                if(raw_written-raw_read>=2048) $fatal(1,"RAW_SCOREBOARD_CAPACITY");
            end
            if(demo.X_ui_raw_matrix_3x3_buffer.zhenghe_tvalid) begin
                if(raw_read>=raw_written || demo.X_ui_raw_matrix_3x3_buffer.zhenghe_tdata!==raw_expected[raw_read%2048]
                    || demo.X_ui_raw_matrix_3x3_buffer.zhenghe_tuser!==raw_sof[raw_read%2048]
                    || demo.X_ui_raw_matrix_3x3_buffer.zhenghe_tlast!==raw_last[raw_read%2048])
                    $fatal(1,"FULL_RAW_LINE_ORACLE_FAIL at=%0d",raw_read);
                raw_read=raw_read+1;raw_pixels=raw_pixels+4;
            end
            if(dv) begin
                if(du) begin
                    d_frame=d_frame+1;d_index=0;red_sum=1;green_sum=1;blue_sum=1;
                end
                if(dl!==(d_index%(width/4)==width/4-1)) $fatal(1,"DEMOSAIC_EOL");
                if(pattern==0 && rgb!=={12{8'd128}}) $fatal(1,"NEUTRAL_DEMOSAIC_ORACLE");
                if(pattern<2) begin
                    if(d_frame==0) first_demosaic[d_index]=rgb;
                    else if(rgb!==first_demosaic[d_index]) $fatal(1,"STARTUP_DEMOSAIC_NOT_STABLE");
                    stable_pixels=stable_pixels+4;
                end
                awb_expected[d_written%2048]=rgb;
                awb_sof[d_written%2048]=du;awb_last[d_written%2048]=dl;
                d_written=d_written+1;
                if(d_written-a_read>=2048) $fatal(1,"AWB_SCOREBOARD_CAPACITY");
                for(integer k=0;k<4;k=k+1) begin
                    r=rgb[k*24+16+:8];g=rgb[k*24+8+:8];b=rgb[k*24+:8];
                    if(r+g+b<700) begin red_sum=red_sum+r;green_sum=green_sum+g;blue_sum=blue_sum+b;end
                end
                d_index=d_index+1;
                if(d_index==width*height/4) begin
                    sr=red_sum/4;sg=green_sum/4;sb=blue_sum/4;
                    if(sr==0) sr=1;if(sg==0) sg=1;if(sb==0) sb=1;
                    gain_r[d_frame+1]=(sg*65536)/sr;
                    gain_b[d_frame+1]=(sg*65536)/sb;
                    if(gain_r[d_frame+1]>1048575) gain_r[d_frame+1]=1048575;
                    if(gain_b[d_frame+1]>1048575) gain_b[d_frame+1]=1048575;
                end
            end
            if(av) begin
                if(au) begin a_frame=a_frame+1;a_index=0;end
                if(a_read>=d_written || au!==awb_sof[a_read%2048] || al!==awb_last[a_read%2048])
                    $fatal(1,"AWB_FRAME_BOUNDARY_ORACLE");
                expected_word=awb_expected[a_read%2048];
                for(integer k=0;k<4;k=k+1) begin
                    r=expected_word[k*24+16+:8];b=expected_word[k*24+:8];
                    pr=(r*gain_r[a_frame])/65536;pb=(b*gain_b[a_frame])/65536;
                    expected_word[k*24+16+:8]=(pr>255)?255:pr;
                    expected_word[k*24+:8]=(pb>255)?255:pb;
                end
                if(adata!==expected_word) $fatal(1,"FULL_AWB_PIXEL_ORACLE frame=%0d beat=%0d got=%h expected=%h",a_frame,a_index,adata,expected_word);
                a_read=a_read+1;a_index=a_index+1;awb_pixels=awb_pixels+4;
            end
        end
    end
