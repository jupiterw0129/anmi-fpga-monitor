// One stream for payload, short packets and errors. The guard's eager read
// output is held until its descriptor reaches the front of this queue.
module csi_ordered_packets724 #(
    parameter MAX_BYTES=8192,
    parameter QUEUE_BITS=4
)(
    input wire clock, reset_n, enable,
    input wire [31:0] input_data,
    input wire input_valid,
    output wire packet_done, sync_wait, header_attempt, header_valid,
    output wire header_bad, filter_bad, crc_bad, truncated, overflow,
    output reg queue_overflow,
    output reg [63:0] token_data,
    output reg token_valid,
    input wire token_ready
);
    localparam PAYLOAD=2'd0, SHORT=2'd1, ERROR=2'd2;
    localparam DEPTH=1<<QUEUE_BITS;
    reg [25:0] descriptors [0:DEPTH-1];
    reg [QUEUE_BITS-1:0] write_index, read_index;
    reg [QUEUE_BITS:0] count;
    reg first;
    reg halted, fatal_pending;
    wire [23:0] packet_header, short_header, out_header;
    wire good, short_valid;
    wire [31:0] payload_data;
    wire [3:0] payload_keep;
    wire payload_valid, payload_ready, payload_last;
    wire [25:0] head=descriptors[read_index];
    wire [1:0] head_kind=head[25:24];
    wire push_error=header_bad || filter_bad || crc_bad || truncated || overflow;
    wire push_long=good && packet_header[23:8]!=0;
    wire push=push_error || push_long || short_valid;
    wire [25:0] pushed={push_error ? ERROR : short_valid ? SHORT : PAYLOAD,
                          short_valid ? short_header : packet_header};
    wire available=count!=0 && !halted;
    wire payload_head=available && head_kind==PAYLOAD;
    wire transfer_ready=!token_valid || token_ready;
    assign payload_ready=payload_head && transfer_ready;
    wire pending_valid=enable && (fatal_pending ||
        (available && (head_kind!=PAYLOAD || payload_valid)));
    // [63:40] header, [39:38] kind, [37] first, [36] last,
    // [35:32] keep, [31:0] data. Control tokens contain no payload bytes.
    wire [63:0] pending_data=fatal_pending ? {24'd0,ERROR,2'b11,4'd0,32'd0} :
        {head[23:0],head_kind,first,head_kind==PAYLOAD ? payload_last : 1'b1,
         head_kind==PAYLOAD ? payload_keep : 4'd0,
         head_kind==PAYLOAD ? payload_data : 32'd0};
    wire pop=pending_valid && transfer_ready && !fatal_pending &&
        (head_kind!=PAYLOAD || payload_last);
    wire full=count==DEPTH;
    wire guard_enable=enable && !halted;
    csi_packet_guard_frame724 #(.MAX_BYTES(MAX_BYTES)) guard (
        .clock(clock),.reset_n(reset_n),.enable(guard_enable),
        .input_data(input_data),.input_valid(input_valid),
        .packet_header(packet_header),.packet_done(packet_done),
        .header_attempt(header_attempt),.header_valid(header_valid),.sync_wait(sync_wait),
        .packet_good(good),.header_bad(header_bad),.filter_bad(filter_bad),
        .crc_bad(crc_bad),.truncated(truncated),.overflow(overflow),
        .short_valid(short_valid),.short_header(short_header),
        .output_data(payload_data),.output_keep(payload_keep),
        .output_valid(payload_valid),.output_ready(payload_ready),
        .output_last(payload_last),.output_header(out_header)
    );
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            write_index<=0; read_index<=0; count<=0; first<=1;
            halted<=0; fatal_pending<=0; queue_overflow<=0;
            token_data<=0; token_valid<=0;
        end else begin
            queue_overflow<=0;
            if (transfer_ready) begin
                token_valid<=pending_valid;
                if (pending_valid) token_data<=pending_data;
            end
            if (!enable) begin
                write_index<=0; read_index<=0; count<=0; first<=1;
                halted<=0; fatal_pending<=0; token_valid<=0;
            end else if (halted) begin
                if (fatal_pending && transfer_ready) fatal_pending<=0;
                // Flush the guard and wait for an input burst boundary. A
                // following valid FS is still required by the frame decoder.
                if ((!fatal_pending || transfer_ready) && !input_valid) halted<=0;
            end else if (push && full && !pop) begin
                write_index<=0; read_index<=0; count<=0; first<=1;
                halted<=1; fatal_pending<=1; queue_overflow<=1;
            end else begin
                if (push) begin
                    descriptors[write_index]<=pushed;
                    write_index<=write_index+1'b1;
                end
                if (pop) read_index<=read_index+1'b1;
                case ({push,pop})
                    2'b10: count<=count+1'b1;
                    2'b01: count<=count-1'b1;
                endcase
                if (pending_valid && transfer_ready) first<=pop;
            end
        end
    end
endmodule
