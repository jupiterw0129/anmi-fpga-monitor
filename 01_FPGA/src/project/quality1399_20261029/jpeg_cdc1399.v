// RGB4 and atomic per-frame identity queues cross to the codec clock.
// The caller must abort provisional transport on fault and reset this codec
// separately from any already-advertised transport packet.
module jpeg_cdc748 #(
    parameter WIDTH=1920, HEIGHT=1080, QUALITY=50,
    parameter INPUT_BITS=9, OUTPUT_BITS=8
)(
    input wire user_clk,codec_clk,reset_n,
    input wire [6:0] requested_quality,
    input wire [95:0] rgb4_data,input wire [31:0] source_frame_id,
    input wire rgb4_valid,rgb4_sof,rgb4_eol,output wire rgb4_ready,
    output wire [127:0] jpeg_data,output wire [15:0] jpeg_keep,
    output wire [31:0] jpeg_frame_id,output wire jpeg_sof,jpeg_last,jpeg_valid,
    input wire jpeg_ready,output wire fault,
    output wire [(INPUT_BITS>12 ? INPUT_BITS : 12):0] input_used,
    output wire [OUTPUT_BITS-1:0] output_used
);
    wire user_reset_n,codec_reset_n;
    board_reset_release user_release(user_clk,reset_n,user_reset_n);
    board_reset_release codec_release(codec_clk,reset_n,codec_reset_n);
    // RGB and raster flags occupy 98 bits per group. Source identities are
    // validated on every accepted user-domain group and queued once per SOF.
    wire input_full,input_empty,identity_full,identity_empty;
    wire [97:0] input_head;
    wire [38:0] identity_head;
    wire input_pop,take_pending;
    reg [97:0] pending_group;
    // Store payload, raster flags and source ID atomically in the user domain.
    // This queue absorbs a line burst while the existing crossing is full.
    // It does not throttle the unbackpressured ISP or alter the encoded pixels.
    wire front_full,front_empty;
    wire [136:0] front_head;
    wire [11:0] front_used;
    wire [INPUT_BITS-1:0] main_used;
    reg [136:0] front_pending;
    reg front_pending_valid;
    wire front_sof=front_pending[97];
    wire [31:0] front_id=front_pending[129:98];
    wire [6:0] request_clamped=requested_quality==0 ? 7'd1 : requested_quality>100 ? 7'd100 : requested_quality;
    wire front_pop=user_reset_n && !front_empty && !front_pending_valid;
    wire input_push=user_reset_n && front_pending_valid && !input_full && (!front_sof || !identity_full);
    assign rgb4_ready=user_reset_n && !front_full;
    // Counts are conservative write-domain observations, as in the original
    // crossing; include the elastic entry when reporting total queued groups.
    assign input_used={1'b0,main_used}+front_used+front_pending_valid;
    jpeg_input_fifo820 #(.DATA_WIDTH_W(137),.DATA_WIDTH_R(137),
        .ADDR_WIDTH_W(12),.ADDR_WIDTH_R(12),
        .AL_FULL_NUM(2048),.AL_EMPTY_NUM(2),.SHOW_AHEAD_EN(1'b1)) front_queue935(
        .rst(!reset_n),.clkw(user_clk),.clkr(user_clk),
        .di({request_clamped,source_frame_id,rgb4_sof,rgb4_eol,rgb4_data}),
        .we(rgb4_valid && rgb4_ready),.full_flag(front_full),.afull(),
        .re(front_pop),.dout(front_head),.empty_flag(front_empty),.aempty(),.valid(),
        .wrusedw(front_used),.rdusedw());
    always @(posedge user_clk or negedge user_reset_n)begin
        if(!user_reset_n)front_pending_valid<=0;
        else begin
            if(input_push)front_pending_valid<=0;
            if(front_pop)front_pending_valid<=1;
        end
    end
    always @(posedge user_clk)if(!front_pending_valid)front_pending<=front_head;
    jpeg_input_fifo820 #(.DATA_WIDTH_W(98),.DATA_WIDTH_R(98),
        .ADDR_WIDTH_W(INPUT_BITS),.ADDR_WIDTH_R(INPUT_BITS),
        .AL_FULL_NUM(1<<(INPUT_BITS-1)),.AL_EMPTY_NUM(2),.SHOW_AHEAD_EN(1'b1)) input_crossing(
        .rst(!reset_n),.clkw(user_clk),.clkr(codec_clk),
        .di(front_pending[97:0]),
        .we(input_push),.full_flag(input_full),.afull(),
        .re(input_pop),.dout(input_head),.empty_flag(input_empty),.aempty(),.valid(),
        .wrusedw(main_used),.rdusedw());
    jpeg_input_fifo820 #(.DATA_WIDTH_W(39),.DATA_WIDTH_R(39),
        .ADDR_WIDTH_W(4),.ADDR_WIDTH_R(4),
        .AL_FULL_NUM(8),.AL_EMPTY_NUM(2),.SHOW_AHEAD_EN(1'b1)) identity_crossing(
        .rst(!reset_n),.clkw(user_clk),.clkr(codec_clk),
        .di({front_pending[136:130],front_id}),.we(input_push && front_sof),
        .full_flag(identity_full),.afull(),
        .re(take_pending && pending_group[97]),.dout(identity_head),
        .empty_flag(identity_empty),.aempty(),.valid(),.wrusedw(),.rdusedw());
    reg [31:0] group_identity;

    reg [136:0] held_group;
    reg held_valid;
    // One elastic group isolates FIFO prefetch/address logic from the encoder's
    // combinational ready tree. Refilling may take two clocks per RGB4 group;
    // the pixel consumer needs at least four clocks, so steady throughput stays.
    
    reg pending_valid;
    reg [1:0] lane;
    wire config_ready,config_error,pixel_ready;
    wire pixel_valid=held_valid && config_ready;
    wire pixel_sof=pixel_valid && held_group[97] && lane==0;
    wire pixel_eol=pixel_valid && held_group[96] && lane==3;
    wire pixel_fire=pixel_valid && pixel_ready;
    // A SOF may enter pending before its separately synchronized identity.
    // Wait for that identity only when promoting to held; the large FIFO pop
    // never depends on its own RAM data/SOF output. Metadata pops atomically
    // with this promotion, and every following group inherits that identity.
    assign input_pop=!input_empty && !pending_valid;
    assign take_pending=pending_valid && (!pending_group[97] || !identity_empty) &&
        (!held_valid || (pixel_fire && lane==3));
    always @(posedge codec_clk or negedge codec_reset_n) begin
        if(!codec_reset_n)begin
            held_group<=0;held_valid<=0;lane<=0;group_identity<=0;
            pending_valid<=0;
        end
        else begin
            if(pixel_fire)begin
                lane<=lane+1'b1;
                if(lane==3)held_valid<=0;
            end
            if(take_pending)begin
                held_group<={identity_head[38:32],pending_group[97] ? identity_head[31:0] : group_identity,pending_group};
                if(pending_group[97])group_identity<=identity_head[31:0];
                held_valid<=1;lane<=0;pending_valid<=0;
            end
            if(input_pop)begin
                pending_valid<=1;
            end
        end
    end
    // Payload has no meaning until pending_valid. Capture while the slot is
    // empty, independently of FIFO empty/reset, and hold until promotion.
    always @(posedge codec_clk)if(!pending_valid)pending_group<=input_head;
    wire [4:0] awaddr;
    wire [31:0] wdata;
    wire awvalid,awready,wvalid,wready,bvalid;
    wire [1:0] bresp;
    wire [6:0] quality;
    // AXI startup enables the encoder. Actual quality follows each SOF metadata.
    // This implements adjustable quality, not a constant bitrate guarantee.
    jpeg_quality_config config_unit(.clk(codec_clk),.rst_n(codec_reset_n),
        .frame_accept(1'b1),.requested_quality(QUALITY[6:0]),.active_quality(quality),
        .ready(config_ready),.error(config_error),.awaddr(awaddr),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp));
    wire [7:0] byte_data;
    wire byte_valid,byte_last;
    reg [6:0] frame_qualities[0:7];
    reg [2:0] id_write,id_read;
    mjpegzero_enc_top723 #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT),.RGB_INPUT(1),.LITE_MODE(0)) encoder(
        .frame_quality_config(frame_qualities[id_read]),.quality_debug(),.clk(codec_clk),.rst_n(codec_reset_n),
        .s_axis_vid_tdata(held_group[lane*24+:24]),.s_axis_vid_tvalid(pixel_valid),
        .s_axis_vid_tready(pixel_ready),.s_axis_vid_tlast(pixel_eol),.s_axis_vid_tuser(pixel_sof),
        .m_axis_jpg_tdata(byte_data),.m_axis_jpg_tvalid(byte_valid),.m_axis_jpg_tlast(byte_last),
        .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(4'hf),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(1'b1),
        .s_axi_araddr(5'd0),.s_axi_arvalid(1'b0),.s_axi_arready(),
        .s_axi_rdata(),.s_axi_rresp(),.s_axi_rvalid(),.s_axi_rready(1'b0));

    // Input admission may overlap output of the preceding frame. Preserve IDs
    // in a queue rather than overwriting a single "current frame" register.
    reg [31:0] identities[0:7];
    // The input buffer can prefetch a later frame while the encoder drains.
    // Keep Q at the OUTPUT head through EOI, exactly like frame identity;
    // the encoder snapshots it only after returning to F_IDLE.
    reg [3:0] id_count;
    reg [31:0] input_identity;
    wire id_push=pixel_fire && pixel_sof;
    wire id_pop=byte_valid && byte_last && id_count!=0;
    reg codec_fault;
    wire output_full,output_empty;
    reg [127:0] partial;
    reg [3:0] byte_index;
    reg first_word,first_byte;
    reg [31:0] output_identity;
    reg [127:0] assembled;
    always @* begin assembled=partial;assembled[byte_index*8+:8]=byte_data;end
    wire complete_word=byte_valid && (byte_index==15 || byte_last);
    wire [31:0] packed_identity=first_byte ? identities[id_read] : output_identity;
    wire [15:0] packed_keep=16'hffff>>(15-byte_index);
    always @(posedge codec_clk or negedge codec_reset_n)begin
        if(!codec_reset_n)begin
            id_write<=0;id_read<=0;id_count<=0;input_identity<=0;codec_fault<=0;
            partial<=0;byte_index<=0;first_word<=1;first_byte<=1;output_identity<=0;
        end else begin
            if(config_error || (complete_word && output_full) ||
                (id_push && id_count==8 && !id_pop) || (byte_valid && id_count==0) ||
                (pixel_fire && !pixel_sof && held_group[129:98]!=input_identity))codec_fault<=1;
            if(id_push)begin frame_qualities[id_write]<=held_group[136:130];identities[id_write]<=held_group[129:98];id_write<=id_write+1'b1;input_identity<=held_group[129:98];end
            if(id_pop)id_read<=id_read+1'b1;
            case({id_push,id_pop})2'b10:id_count<=id_count+1'b1;2'b01:id_count<=id_count-1'b1;endcase
            if(byte_valid)begin
                if(first_byte)output_identity<=identities[id_read];
                first_byte<=0;
                if(complete_word)begin partial<=0;byte_index<=0;first_word<=0;end
                else begin partial<=assembled;byte_index<=byte_index+1'b1;end
                if(byte_last)begin first_word<=1;first_byte<=1;end
            end
        end
    end
    wire [177:0] packed_output;
    reg [177:0] output_word;
    reg output_word_valid;
    reg [177:0] output_pending;
    reg output_pending_valid;
    // Independently refill the elastic slot. Fault/transport ready decisions
    // cannot feed back through jpeg_ready into the crossing RAM read address.
    // Two clocks per 128-bit word still exceed the encoder's byte output rate.
    wire take_output=user_reset_n && !output_empty && !output_pending_valid;
    // Refill only an already empty slot. This removes transport's entire
    // ready/fault tree from the 178-bit data register enable. The intentional
    // bubble still permits one word per four user clocks, versus at least
    // eight user clocks per encoder word at 250MHz/125MHz.
    wire deliver_output=output_pending_valid && !output_word_valid;
    assign {jpeg_frame_id,jpeg_last,jpeg_sof,jpeg_keep,jpeg_data}=output_word;
    assign jpeg_valid=user_reset_n && output_word_valid;
    always @(posedge user_clk or negedge user_reset_n)begin
        if(!user_reset_n)begin
            output_word<=0;output_word_valid<=0;output_pending<=0;output_pending_valid<=0;
        end else begin
            if(output_word_valid && jpeg_ready)output_word_valid<=0;
            if(deliver_output)begin
                output_word<=output_pending;output_word_valid<=1;output_pending_valid<=0;
            end
            if(take_output)begin output_pending<=packed_output;output_pending_valid<=1;end
        end
    end
    jpeg_output_fifo843 #(.DATA_WIDTH_W(178),.DATA_WIDTH_R(178),
        .ADDR_WIDTH_W(OUTPUT_BITS),.ADDR_WIDTH_R(OUTPUT_BITS),
        .AL_FULL_NUM(1<<(OUTPUT_BITS-1)),.AL_EMPTY_NUM(2),.SHOW_AHEAD_EN(1'b1)) output_crossing(
        .rst(!reset_n),.clkw(codec_clk),.clkr(user_clk),
        .di({packed_identity,byte_last,first_word,packed_keep,assembled}),
        .we(complete_word && !output_full),.full_flag(output_full),.afull(),
        .re(take_output),.dout(packed_output),.empty_flag(output_empty),.aempty(),.valid(),
        // Public diagnostics are sampled by user_clk logic. The read-side
        // count already uses the synchronized write Gray pointer; never expose
        // the raw codec_clk binary occupancy to the host/probe parity register.
        .wrusedw(),.rdusedw(output_used));
    reg input_fault;
    reg [31:0] accepted_identity;
    (* async_reg="true",dont_touch="true" *) reg [1:0] codec_fault_sync;
    always @(posedge user_clk or negedge user_reset_n)begin
        if(!user_reset_n)begin input_fault<=0;codec_fault_sync<=0;accepted_identity<=0;end
        else begin
            if(rgb4_valid && !rgb4_ready)input_fault<=1;
            if(input_push)begin
                if(front_sof)accepted_identity<=front_id;
                else if(front_id!=accepted_identity)input_fault<=1;
            end
            codec_fault_sync<={codec_fault_sync[0],codec_fault};
        end
    end
    assign fault=input_fault || codec_fault_sync[1];
endmodule
