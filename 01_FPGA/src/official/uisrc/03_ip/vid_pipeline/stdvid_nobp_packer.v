`timescale 1ns / 1ps

module stdvid_nobp_packer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,
    input  wire         frame_request,
    input  wire [15:0]  act_width,
    input  wire [15:0]  act_height,
    input  wire         src_de,
    input  wire         src_user,
    input  wire         src_last,
    input  wire [23:0]  src_data,
    output reg  [511:0] m_tdata,
    output reg          m_tvalid,
    input  wire         m_tready,
    output reg          m_tlast,
    output reg          m_frame_last,
    output reg          sof,
    output reg          eof,
    output wire [31:0]  frame_count_out
);

    reg [31:0] frame_count;
    reg        frame_req_pending;
    reg        accept_frame;
    reg        drop_frame;
    reg        sof_pending;

    reg [15:0] src_x;
    reg [15:0] src_y;

    reg [511:0] pack_buf;
    reg [5:0]   pack_ptr;

    reg        flush_pending;
    reg        flush_line_last;
    reg        flush_frame_last;
    reg        flush_sof;
    reg        flush_eof;

    wire [15:0] safe_width  = (act_width  < 16'd64) ? 16'd64 : act_width;
    wire [15:0] safe_height = (act_height == 16'd0) ? 16'd1  : act_height;

    wire [15:0] cur_x = src_user ? 16'd0 : src_x;
    wire [15:0] cur_y = src_user ? 16'd0 : src_y;
    wire        request_available = frame_req_pending || frame_request;
    wire        frame_selected    = src_user ? (enable && request_available) : accept_frame;
    wire        frame_dropped     = src_user ? 1'b0 : drop_frame;
    wire        accept_pixel      = src_de && frame_selected && !frame_dropped &&
                                    (cur_x < safe_width) && (cur_y < safe_height);
    wire        pixel_line_end    = accept_pixel && (cur_x + 16'd1 >= safe_width);
    wire        pixel_frame_end   = pixel_line_end && (cur_y + 16'd1 >= safe_height);
    wire        output_slot_free  = !m_tvalid || m_tready;
    wire        stall_now         = m_tvalid && !m_tready;

    assign frame_count_out = frame_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count       <= 32'd0;
            frame_req_pending <= 1'b0;
            accept_frame      <= 1'b0;
            drop_frame        <= 1'b0;
            sof_pending       <= 1'b0;
            src_x             <= 16'd0;
            src_y             <= 16'd0;
            pack_buf          <= 512'd0;
            pack_ptr          <= 6'd0;
            flush_pending     <= 1'b0;
            flush_line_last   <= 1'b0;
            flush_frame_last  <= 1'b0;
            flush_sof         <= 1'b0;
            flush_eof         <= 1'b0;
            m_tdata           <= 512'd0;
            m_tvalid          <= 1'b0;
            m_tlast           <= 1'b0;
            m_frame_last      <= 1'b0;
            sof               <= 1'b0;
            eof               <= 1'b0;
        end else begin
            if (m_tvalid && m_tready) begin
                if (m_frame_last)
                    frame_count <= frame_count + 1'b1;
                m_tvalid     <= 1'b0;
                m_tlast      <= 1'b0;
                m_frame_last <= 1'b0;
                sof          <= 1'b0;
                eof          <= 1'b0;
            end

            if (!enable) begin
                frame_req_pending <= 1'b0;
                accept_frame      <= 1'b0;
                drop_frame        <= 1'b0;
                sof_pending       <= 1'b0;
                src_x             <= 16'd0;
                src_y             <= 16'd0;
                pack_buf          <= 512'd0;
                pack_ptr          <= 6'd0;
                flush_pending     <= 1'b0;
                flush_line_last   <= 1'b0;
                flush_frame_last  <= 1'b0;
                flush_sof         <= 1'b0;
                flush_eof         <= 1'b0;
                m_tvalid          <= 1'b0;
                m_tlast           <= 1'b0;
                m_frame_last      <= 1'b0;
                sof               <= 1'b0;
                eof               <= 1'b0;
            end else begin
                if (src_user && src_de && frame_selected)
                    frame_req_pending <= frame_request;
                else if (frame_request)
                    frame_req_pending <= 1'b1;

                if (src_de) begin
                    if (src_user) begin
                        if (src_last) begin
                            src_x <= 16'd0;
                            src_y <= 16'd1;
                        end else begin
                            src_x <= 16'd1;
                            src_y <= 16'd0;
                        end
                    end else if (src_last) begin
                        src_x <= 16'd0;
                        src_y <= src_y + 1'b1;
                    end else begin
                        src_x <= src_x + 1'b1;
                    end
                end

                if (src_user && src_de) begin
                    accept_frame     <= frame_selected;
                    drop_frame       <= 1'b0;
                    sof_pending      <= frame_selected;
                    pack_buf         <= 512'd0;
                    pack_ptr         <= 6'd0;
                    flush_pending    <= 1'b0;
                    flush_line_last  <= 1'b0;
                    flush_frame_last <= 1'b0;
                    flush_sof        <= 1'b0;
                    flush_eof        <= 1'b0;
                end

                if (stall_now) begin
                    accept_frame      <= 1'b0;
                    drop_frame        <= 1'b1;
                    sof_pending       <= 1'b0;
                    pack_buf          <= 512'd0;
                    pack_ptr          <= 6'd0;
                    flush_pending     <= 1'b0;
                    flush_line_last   <= 1'b0;
                    flush_frame_last  <= 1'b0;
                    flush_sof         <= 1'b0;
                    flush_eof         <= 1'b0;
                    m_tvalid          <= 1'b0;
                    m_tlast           <= 1'b0;
                    m_frame_last      <= 1'b0;
                    sof               <= 1'b0;
                    eof               <= 1'b0;
                end else begin
                    if (flush_pending && !accept_pixel && output_slot_free) begin
                        m_tdata       <= pack_buf;
                        m_tvalid      <= 1'b1;
                        m_tlast       <= flush_line_last;
                        m_frame_last  <= flush_frame_last;
                        sof           <= flush_sof;
                        eof           <= flush_eof;
                        if (flush_sof)
                            sof_pending <= 1'b0;
                        pack_buf         <= 512'd0;
                        pack_ptr         <= 6'd0;
                        flush_pending    <= 1'b0;
                        flush_line_last  <= 1'b0;
                        flush_frame_last <= 1'b0;
                        flush_sof        <= 1'b0;
                        flush_eof        <= 1'b0;
                    end

                    if (accept_pixel) begin
                        case (pack_ptr)
                            6'd61: begin
                                pack_buf[61*8 +: 8] <= src_data[23:16];
                                pack_buf[62*8 +: 8] <= src_data[15:8];
                                pack_buf[63*8 +: 8] <= src_data[7:0];
                                if (output_slot_free) begin
                                    m_tdata      <= (pack_buf |
                                                    ({504'd0, src_data[23:16]} << (61*8)) |
                                                    ({496'd0, src_data[15:8]}  << (62*8)) |
                                                    ({488'd0, src_data[7:0]}   << (63*8)));
                                    m_tvalid     <= 1'b1;
                                    m_tlast      <= pixel_line_end;
                                    m_frame_last <= pixel_frame_end;
                                    sof          <= sof_pending;
                                    eof          <= pixel_frame_end;
                                    pack_buf     <= 512'd0;
                                    pack_ptr     <= 6'd0;
                                    if (sof_pending)
                                        sof_pending <= 1'b0;
                                    if (pixel_frame_end)
                                        accept_frame <= 1'b0;
                                end
                            end

                            6'd62: begin
                                if (output_slot_free) begin
                                    m_tdata      <= (pack_buf |
                                                    ({504'd0, src_data[23:16]} << (62*8)) |
                                                    ({496'd0, src_data[15:8]}  << (63*8)));
                                    m_tvalid     <= 1'b1;
                                    m_tlast      <= 1'b0;
                                    m_frame_last <= 1'b0;
                                    sof          <= sof_pending;
                                    eof          <= 1'b0;
                                    pack_buf     <= 512'd0;
                                    pack_buf[7:0] <= src_data[7:0];
                                    pack_ptr     <= 6'd1;
                                    if (sof_pending)
                                        sof_pending <= 1'b0;
                                    if (pixel_line_end) begin
                                        flush_pending    <= 1'b1;
                                        flush_line_last  <= 1'b1;
                                        flush_frame_last <= pixel_frame_end;
                                        flush_sof        <= 1'b0;
                                        flush_eof        <= pixel_frame_end;
                                    end
                                    if (pixel_frame_end)
                                        accept_frame <= 1'b0;
                                end
                            end

                            6'd63: begin
                                if (output_slot_free) begin
                                    m_tdata      <= (pack_buf |
                                                    ({504'd0, src_data[23:16]} << (63*8)));
                                    m_tvalid     <= 1'b1;
                                    m_tlast      <= 1'b0;
                                    m_frame_last <= 1'b0;
                                    sof          <= sof_pending;
                                    eof          <= 1'b0;
                                    pack_buf     <= 512'd0;
                                    pack_buf[7:0]  <= src_data[15:8];
                                    pack_buf[15:8] <= src_data[7:0];
                                    pack_ptr     <= 6'd2;
                                    if (sof_pending)
                                        sof_pending <= 1'b0;
                                    if (pixel_line_end) begin
                                        flush_pending    <= 1'b1;
                                        flush_line_last  <= 1'b1;
                                        flush_frame_last <= pixel_frame_end;
                                        flush_sof        <= 1'b0;
                                        flush_eof        <= pixel_frame_end;
                                    end
                                    if (pixel_frame_end)
                                        accept_frame <= 1'b0;
                                end
                            end

                            default: begin
                                pack_buf[pack_ptr*8 +: 8] <= src_data[23:16];
                                pack_buf[(pack_ptr+1'b1)*8 +: 8] <= src_data[15:8];
                                pack_buf[(pack_ptr+2'd2)*8 +: 8] <= src_data[7:0];
                                if (pixel_line_end) begin
                                    if (output_slot_free) begin
                                        m_tdata      <= (pack_buf |
                                                        ({504'd0, src_data[23:16]} << (pack_ptr*8)) |
                                                        ({496'd0, src_data[15:8]}  << ((pack_ptr+1'b1)*8)) |
                                                        ({488'd0, src_data[7:0]}   << ((pack_ptr+2'd2)*8)));
                                        m_tvalid     <= 1'b1;
                                        m_tlast      <= 1'b1;
                                        m_frame_last <= pixel_frame_end;
                                        sof          <= sof_pending;
                                        eof          <= pixel_frame_end;
                                        pack_buf     <= 512'd0;
                                        pack_ptr     <= 6'd0;
                                        if (sof_pending)
                                            sof_pending <= 1'b0;
                                        if (pixel_frame_end)
                                            accept_frame <= 1'b0;
                                    end
                                end else begin
                                    pack_ptr <= pack_ptr + 2'd3;
                                end
                            end
                        endcase
                    end
                end
            end
        end
    end

endmodule
