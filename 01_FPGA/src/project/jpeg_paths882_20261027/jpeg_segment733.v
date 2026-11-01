// JPG2: JPEG bytes are provisional until a CRC-protected terminal COMMIT.
// Distinct magic prevents P4R2 decoders from interpreting JPEG as predictive tokens.
module jpeg_segment733 #(
    parameter WIDTH=1280, HEIGHT=720, CHUNK_BYTES=4096,
    parameter MAX_FRAME_BYTES=WIDTH*HEIGHT*6+65536,
    parameter TIMEOUT_CYCLES=125000000
)(
    input wire clk, reset,
    input wire start_valid, input wire [31:0] start_id, output wire start_ready,
    input wire verdict_valid, input wire [31:0] verdict_id,
    input wire verdict_good, input wire [31:0] verdict_reason,
    input wire abort_valid, input wire [31:0] abort_reason,
    input wire [127:0] s_data, input wire [15:0] s_keep,
    input wire s_valid, s_sof, s_last, output wire s_ready,
    output reg [127:0] m_data, output wire [15:0] m_keep,
    output wire m_valid, input wire m_ready, output wire m_last,
    output wire active, flush, output wire transaction_done,
    output wire committed, aborted,
    output reg [31:0] ignored_verdicts
);
    localparam IDLE=0,FILL=1,HEAD0=2,HEAD1=3,PAYLOAD=4,TAIL=5,TRAILER=6,WAIT_END=7,CHECK_INPUT=8;
    localparam MAX_BYTES=MAX_FRAME_BYTES;
    localparam REMAINING_WIDTH=$clog2(MAX_BYTES+1);
    reg [REMAINING_WIDTH-1:0] remaining_bytes;
    localparam [15:0] WIDTH16=WIDTH, HEIGHT16=HEIGHT;
    localparam [31:0] DECODED_BYTES=WIDTH*HEIGHT*3;
    reg [3:0] state;
    reg [127:0] memory [0:CHUNK_BYTES/16-1];
    reg [127:0] payload_word,tail_data;
    reg [31:0] frame_id,segment_id,frame_offset,payload_bytes,send_word,checksum;
    reg [31:0] timer,reason,kind;
    reg last_data,got_good,bad_pending;
    reg [4:0] incoming_bytes,checksum_bytes,tail_bytes;
    reg [4:0] source_bytes882;
    reg input_keep_invalid882;
    reg [127:0] masked_input;
    // Isolate synchronous FIFO RAM output from length/shape/budget arithmetic.
    // CHECK_INPUT owns this word even if the upstream codec is reset on a fault.
    reg [127:0] input_data;
    reg [15:0] input_keep;
    reg input_sof,input_last;
    integer lane;
    wire matching_verdict=verdict_valid && active && verdict_id==frame_id;
    wire bad_now=(matching_verdict && !verdict_good) || (abort_valid && active);
    wire timeout_now=(state==FILL || state==WAIT_END) && timer==TIMEOUT_CYCLES-1;
    assign active=state!=IDLE;
    assign flush=bad_pending || bad_now || timeout_now;
    assign start_ready=state==IDLE;
    assign s_ready=state==FILL && !flush;
    assign m_keep=16'hffff;
    assign m_valid=state==HEAD0 || state==HEAD1 || state==PAYLOAD || state==TRAILER;
    assign m_last=state==TRAILER;
    assign transaction_done=m_valid && m_ready && m_last && kind!=0;
    assign committed=transaction_done && kind==1;
    assign aborted=transaction_done && kind==2;
        function [31:0] crc_update;
        input [31:0] prior;
        input [127:0] word;
        input [4:0] length;
        reg [31:0] value;
        integer byte_index, bit_index;
        begin
            value = prior;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
                if (byte_index < length) begin
                    value = value ^ word[byte_index*8 +: 8];
                    for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                        value = (value >> 1) ^ (value[0] ? 32'hedb88320 : 32'd0);
                end
            crc_update = value;
        end
    endfunction

    function [31:0] crc_word;
        input [31:0] prior;
        input [127:0] word;
        begin
            crc_word[0] = prior[0] ^ prior[1] ^ prior[2] ^ prior[3] ^ prior[5] ^ prior[9] ^ prior[10] ^ prior[11] ^ prior[12] ^ prior[14] ^ prior[15] ^ prior[17] ^ prior[18] ^ prior[22] ^ prior[24] ^ prior[25] ^ prior[27] ^ prior[29] ^ prior[30] ^ prior[31] ^ word[0] ^ word[1] ^ word[2] ^ word[3] ^ word[5] ^ word[9] ^ word[10] ^ word[11] ^ word[12] ^ word[14] ^ word[15] ^ word[17] ^ word[18] ^ word[22] ^ word[24] ^ word[25] ^ word[27] ^ word[29] ^ word[30] ^ word[31] ^ word[32] ^ word[33] ^ word[34] ^ word[41] ^ word[43] ^ word[44] ^ word[45] ^ word[46] ^ word[47] ^ word[49] ^ word[55] ^ word[56] ^ word[60] ^ word[61] ^ word[62] ^ word[63] ^ word[65] ^ word[67] ^ word[68] ^ word[70] ^ word[73] ^ word[74] ^ word[75] ^ word[78] ^ word[80] ^ word[81] ^ word[83] ^ word[84] ^ word[91] ^ word[94] ^ word[96] ^ word[97] ^ word[98] ^ word[99] ^ word[100] ^ word[102] ^ word[103] ^ word[104] ^ word[112] ^ word[116] ^ word[118] ^ word[119] ^ word[122];
            crc_word[1] = prior[1] ^ prior[2] ^ prior[3] ^ prior[4] ^ prior[6] ^ prior[10] ^ prior[11] ^ prior[12] ^ prior[13] ^ prior[15] ^ prior[16] ^ prior[18] ^ prior[19] ^ prior[23] ^ prior[25] ^ prior[26] ^ prior[28] ^ prior[30] ^ prior[31] ^ word[1] ^ word[2] ^ word[3] ^ word[4] ^ word[6] ^ word[10] ^ word[11] ^ word[12] ^ word[13] ^ word[15] ^ word[16] ^ word[18] ^ word[19] ^ word[23] ^ word[25] ^ word[26] ^ word[28] ^ word[30] ^ word[31] ^ word[32] ^ word[33] ^ word[34] ^ word[35] ^ word[42] ^ word[44] ^ word[45] ^ word[46] ^ word[47] ^ word[48] ^ word[50] ^ word[56] ^ word[57] ^ word[61] ^ word[62] ^ word[63] ^ word[64] ^ word[66] ^ word[68] ^ word[69] ^ word[71] ^ word[74] ^ word[75] ^ word[76] ^ word[79] ^ word[81] ^ word[82] ^ word[84] ^ word[85] ^ word[92] ^ word[95] ^ word[97] ^ word[98] ^ word[99] ^ word[100] ^ word[101] ^ word[103] ^ word[104] ^ word[105] ^ word[113] ^ word[117] ^ word[119] ^ word[120] ^ word[123];
            crc_word[2] = prior[2] ^ prior[3] ^ prior[4] ^ prior[5] ^ prior[7] ^ prior[11] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[16] ^ prior[17] ^ prior[19] ^ prior[20] ^ prior[24] ^ prior[26] ^ prior[27] ^ prior[29] ^ prior[31] ^ word[2] ^ word[3] ^ word[4] ^ word[5] ^ word[7] ^ word[11] ^ word[12] ^ word[13] ^ word[14] ^ word[16] ^ word[17] ^ word[19] ^ word[20] ^ word[24] ^ word[26] ^ word[27] ^ word[29] ^ word[31] ^ word[32] ^ word[33] ^ word[34] ^ word[35] ^ word[36] ^ word[43] ^ word[45] ^ word[46] ^ word[47] ^ word[48] ^ word[49] ^ word[51] ^ word[57] ^ word[58] ^ word[62] ^ word[63] ^ word[64] ^ word[65] ^ word[67] ^ word[69] ^ word[70] ^ word[72] ^ word[75] ^ word[76] ^ word[77] ^ word[80] ^ word[82] ^ word[83] ^ word[85] ^ word[86] ^ word[93] ^ word[96] ^ word[98] ^ word[99] ^ word[100] ^ word[101] ^ word[102] ^ word[104] ^ word[105] ^ word[106] ^ word[114] ^ word[118] ^ word[120] ^ word[121] ^ word[124];
            crc_word[3] = prior[3] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[8] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[17] ^ prior[18] ^ prior[20] ^ prior[21] ^ prior[25] ^ prior[27] ^ prior[28] ^ prior[30] ^ word[3] ^ word[4] ^ word[5] ^ word[6] ^ word[8] ^ word[12] ^ word[13] ^ word[14] ^ word[15] ^ word[17] ^ word[18] ^ word[20] ^ word[21] ^ word[25] ^ word[27] ^ word[28] ^ word[30] ^ word[32] ^ word[33] ^ word[34] ^ word[35] ^ word[36] ^ word[37] ^ word[44] ^ word[46] ^ word[47] ^ word[48] ^ word[49] ^ word[50] ^ word[52] ^ word[58] ^ word[59] ^ word[63] ^ word[64] ^ word[65] ^ word[66] ^ word[68] ^ word[70] ^ word[71] ^ word[73] ^ word[76] ^ word[77] ^ word[78] ^ word[81] ^ word[83] ^ word[84] ^ word[86] ^ word[87] ^ word[94] ^ word[97] ^ word[99] ^ word[100] ^ word[101] ^ word[102] ^ word[103] ^ word[105] ^ word[106] ^ word[107] ^ word[115] ^ word[119] ^ word[121] ^ word[122] ^ word[125];
            crc_word[4] = prior[0] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[9] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[18] ^ prior[19] ^ prior[21] ^ prior[22] ^ prior[26] ^ prior[28] ^ prior[29] ^ prior[31] ^ word[0] ^ word[4] ^ word[5] ^ word[6] ^ word[7] ^ word[9] ^ word[13] ^ word[14] ^ word[15] ^ word[16] ^ word[18] ^ word[19] ^ word[21] ^ word[22] ^ word[26] ^ word[28] ^ word[29] ^ word[31] ^ word[33] ^ word[34] ^ word[35] ^ word[36] ^ word[37] ^ word[38] ^ word[45] ^ word[47] ^ word[48] ^ word[49] ^ word[50] ^ word[51] ^ word[53] ^ word[59] ^ word[60] ^ word[64] ^ word[65] ^ word[66] ^ word[67] ^ word[69] ^ word[71] ^ word[72] ^ word[74] ^ word[77] ^ word[78] ^ word[79] ^ word[82] ^ word[84] ^ word[85] ^ word[87] ^ word[88] ^ word[95] ^ word[98] ^ word[100] ^ word[101] ^ word[102] ^ word[103] ^ word[104] ^ word[106] ^ word[107] ^ word[108] ^ word[116] ^ word[120] ^ word[122] ^ word[123] ^ word[126];
            crc_word[5] = prior[1] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[17] ^ prior[19] ^ prior[20] ^ prior[22] ^ prior[23] ^ prior[27] ^ prior[29] ^ prior[30] ^ word[1] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[14] ^ word[15] ^ word[16] ^ word[17] ^ word[19] ^ word[20] ^ word[22] ^ word[23] ^ word[27] ^ word[29] ^ word[30] ^ word[32] ^ word[34] ^ word[35] ^ word[36] ^ word[37] ^ word[38] ^ word[39] ^ word[46] ^ word[48] ^ word[49] ^ word[50] ^ word[51] ^ word[52] ^ word[54] ^ word[60] ^ word[61] ^ word[65] ^ word[66] ^ word[67] ^ word[68] ^ word[70] ^ word[72] ^ word[73] ^ word[75] ^ word[78] ^ word[79] ^ word[80] ^ word[83] ^ word[85] ^ word[86] ^ word[88] ^ word[89] ^ word[96] ^ word[99] ^ word[101] ^ word[102] ^ word[103] ^ word[104] ^ word[105] ^ word[107] ^ word[108] ^ word[109] ^ word[117] ^ word[121] ^ word[123] ^ word[124] ^ word[127];
            crc_word[6] = prior[1] ^ prior[3] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[12] ^ prior[14] ^ prior[16] ^ prior[20] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[25] ^ prior[27] ^ prior[28] ^ prior[29] ^ word[1] ^ word[3] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[12] ^ word[14] ^ word[16] ^ word[20] ^ word[21] ^ word[22] ^ word[23] ^ word[25] ^ word[27] ^ word[28] ^ word[29] ^ word[32] ^ word[34] ^ word[35] ^ word[36] ^ word[37] ^ word[38] ^ word[39] ^ word[40] ^ word[41] ^ word[43] ^ word[44] ^ word[45] ^ word[46] ^ word[50] ^ word[51] ^ word[52] ^ word[53] ^ word[56] ^ word[60] ^ word[63] ^ word[65] ^ word[66] ^ word[69] ^ word[70] ^ word[71] ^ word[75] ^ word[76] ^ word[78] ^ word[79] ^ word[83] ^ word[86] ^ word[87] ^ word[89] ^ word[90] ^ word[91] ^ word[94] ^ word[96] ^ word[98] ^ word[99] ^ word[105] ^ word[106] ^ word[108] ^ word[109] ^ word[110] ^ word[112] ^ word[116] ^ word[119] ^ word[124] ^ word[125];
            crc_word[7] = prior[0] ^ prior[2] ^ prior[4] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[9] ^ prior[11] ^ prior[13] ^ prior[15] ^ prior[17] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[26] ^ prior[28] ^ prior[29] ^ prior[30] ^ word[0] ^ word[2] ^ word[4] ^ word[6] ^ word[7] ^ word[8] ^ word[9] ^ word[11] ^ word[13] ^ word[15] ^ word[17] ^ word[21] ^ word[22] ^ word[23] ^ word[24] ^ word[26] ^ word[28] ^ word[29] ^ word[30] ^ word[33] ^ word[35] ^ word[36] ^ word[37] ^ word[38] ^ word[39] ^ word[40] ^ word[41] ^ word[42] ^ word[44] ^ word[45] ^ word[46] ^ word[47] ^ word[51] ^ word[52] ^ word[53] ^ word[54] ^ word[57] ^ word[61] ^ word[64] ^ word[66] ^ word[67] ^ word[70] ^ word[71] ^ word[72] ^ word[76] ^ word[77] ^ word[79] ^ word[80] ^ word[84] ^ word[87] ^ word[88] ^ word[90] ^ word[91] ^ word[92] ^ word[95] ^ word[97] ^ word[99] ^ word[100] ^ word[106] ^ word[107] ^ word[109] ^ word[110] ^ word[111] ^ word[113] ^ word[117] ^ word[120] ^ word[125] ^ word[126];
            crc_word[8] = prior[0] ^ prior[1] ^ prior[3] ^ prior[5] ^ prior[7] ^ prior[8] ^ prior[9] ^ prior[10] ^ prior[12] ^ prior[14] ^ prior[16] ^ prior[18] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[25] ^ prior[27] ^ prior[29] ^ prior[30] ^ prior[31] ^ word[0] ^ word[1] ^ word[3] ^ word[5] ^ word[7] ^ word[8] ^ word[9] ^ word[10] ^ word[12] ^ word[14] ^ word[16] ^ word[18] ^ word[22] ^ word[23] ^ word[24] ^ word[25] ^ word[27] ^ word[29] ^ word[30] ^ word[31] ^ word[34] ^ word[36] ^ word[37] ^ word[38] ^ word[39] ^ word[40] ^ word[41] ^ word[42] ^ word[43] ^ word[45] ^ word[46] ^ word[47] ^ word[48] ^ word[52] ^ word[53] ^ word[54] ^ word[55] ^ word[58] ^ word[62] ^ word[65] ^ word[67] ^ word[68] ^ word[71] ^ word[72] ^ word[73] ^ word[77] ^ word[78] ^ word[80] ^ word[81] ^ word[85] ^ word[88] ^ word[89] ^ word[91] ^ word[92] ^ word[93] ^ word[96] ^ word[98] ^ word[100] ^ word[101] ^ word[107] ^ word[108] ^ word[110] ^ word[111] ^ word[112] ^ word[114] ^ word[118] ^ word[121] ^ word[126] ^ word[127];
            crc_word[9] = prior[3] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[8] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[18] ^ prior[19] ^ prior[22] ^ prior[23] ^ prior[26] ^ prior[27] ^ prior[28] ^ prior[29] ^ word[3] ^ word[4] ^ word[5] ^ word[6] ^ word[8] ^ word[12] ^ word[13] ^ word[14] ^ word[18] ^ word[19] ^ word[22] ^ word[23] ^ word[26] ^ word[27] ^ word[28] ^ word[29] ^ word[33] ^ word[34] ^ word[35] ^ word[37] ^ word[38] ^ word[39] ^ word[40] ^ word[42] ^ word[45] ^ word[48] ^ word[53] ^ word[54] ^ word[59] ^ word[60] ^ word[61] ^ word[62] ^ word[65] ^ word[66] ^ word[67] ^ word[69] ^ word[70] ^ word[72] ^ word[75] ^ word[79] ^ word[80] ^ word[82] ^ word[83] ^ word[84] ^ word[86] ^ word[89] ^ word[90] ^ word[91] ^ word[92] ^ word[93] ^ word[96] ^ word[98] ^ word[100] ^ word[101] ^ word[103] ^ word[104] ^ word[108] ^ word[109] ^ word[111] ^ word[113] ^ word[115] ^ word[116] ^ word[118] ^ word[127];
            crc_word[10] = prior[1] ^ prior[2] ^ prior[3] ^ prior[4] ^ prior[6] ^ prior[7] ^ prior[10] ^ prior[11] ^ prior[12] ^ prior[13] ^ prior[17] ^ prior[18] ^ prior[19] ^ prior[20] ^ prior[22] ^ prior[23] ^ prior[25] ^ prior[28] ^ prior[31] ^ word[1] ^ word[2] ^ word[3] ^ word[4] ^ word[6] ^ word[7] ^ word[10] ^ word[11] ^ word[12] ^ word[13] ^ word[17] ^ word[18] ^ word[19] ^ word[20] ^ word[22] ^ word[23] ^ word[25] ^ word[28] ^ word[31] ^ word[32] ^ word[33] ^ word[35] ^ word[36] ^ word[38] ^ word[39] ^ word[40] ^ word[44] ^ word[45] ^ word[47] ^ word[54] ^ word[56] ^ word[65] ^ word[66] ^ word[71] ^ word[74] ^ word[75] ^ word[76] ^ word[78] ^ word[85] ^ word[87] ^ word[90] ^ word[92] ^ word[93] ^ word[96] ^ word[98] ^ word[100] ^ word[101] ^ word[103] ^ word[105] ^ word[109] ^ word[110] ^ word[114] ^ word[117] ^ word[118] ^ word[122];
            crc_word[11] = prior[2] ^ prior[3] ^ prior[4] ^ prior[5] ^ prior[7] ^ prior[8] ^ prior[11] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[18] ^ prior[19] ^ prior[20] ^ prior[21] ^ prior[23] ^ prior[24] ^ prior[26] ^ prior[29] ^ word[2] ^ word[3] ^ word[4] ^ word[5] ^ word[7] ^ word[8] ^ word[11] ^ word[12] ^ word[13] ^ word[14] ^ word[18] ^ word[19] ^ word[20] ^ word[21] ^ word[23] ^ word[24] ^ word[26] ^ word[29] ^ word[32] ^ word[33] ^ word[34] ^ word[36] ^ word[37] ^ word[39] ^ word[40] ^ word[41] ^ word[45] ^ word[46] ^ word[48] ^ word[55] ^ word[57] ^ word[66] ^ word[67] ^ word[72] ^ word[75] ^ word[76] ^ word[77] ^ word[79] ^ word[86] ^ word[88] ^ word[91] ^ word[93] ^ word[94] ^ word[97] ^ word[99] ^ word[101] ^ word[102] ^ word[104] ^ word[106] ^ word[110] ^ word[111] ^ word[115] ^ word[118] ^ word[119] ^ word[123];
            crc_word[12] = prior[0] ^ prior[3] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[8] ^ prior[9] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[19] ^ prior[20] ^ prior[21] ^ prior[22] ^ prior[24] ^ prior[25] ^ prior[27] ^ prior[30] ^ word[0] ^ word[3] ^ word[4] ^ word[5] ^ word[6] ^ word[8] ^ word[9] ^ word[12] ^ word[13] ^ word[14] ^ word[15] ^ word[19] ^ word[20] ^ word[21] ^ word[22] ^ word[24] ^ word[25] ^ word[27] ^ word[30] ^ word[33] ^ word[34] ^ word[35] ^ word[37] ^ word[38] ^ word[40] ^ word[41] ^ word[42] ^ word[46] ^ word[47] ^ word[49] ^ word[56] ^ word[58] ^ word[67] ^ word[68] ^ word[73] ^ word[76] ^ word[77] ^ word[78] ^ word[80] ^ word[87] ^ word[89] ^ word[92] ^ word[94] ^ word[95] ^ word[98] ^ word[100] ^ word[102] ^ word[103] ^ word[105] ^ word[107] ^ word[111] ^ word[112] ^ word[116] ^ word[119] ^ word[120] ^ word[124];
            crc_word[13] = prior[1] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[9] ^ prior[10] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[20] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[25] ^ prior[26] ^ prior[28] ^ prior[31] ^ word[1] ^ word[4] ^ word[5] ^ word[6] ^ word[7] ^ word[9] ^ word[10] ^ word[13] ^ word[14] ^ word[15] ^ word[16] ^ word[20] ^ word[21] ^ word[22] ^ word[23] ^ word[25] ^ word[26] ^ word[28] ^ word[31] ^ word[34] ^ word[35] ^ word[36] ^ word[38] ^ word[39] ^ word[41] ^ word[42] ^ word[43] ^ word[47] ^ word[48] ^ word[50] ^ word[57] ^ word[59] ^ word[68] ^ word[69] ^ word[74] ^ word[77] ^ word[78] ^ word[79] ^ word[81] ^ word[88] ^ word[90] ^ word[93] ^ word[95] ^ word[96] ^ word[99] ^ word[101] ^ word[103] ^ word[104] ^ word[106] ^ word[108] ^ word[112] ^ word[113] ^ word[117] ^ word[120] ^ word[121] ^ word[125];
            crc_word[14] = prior[2] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[11] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[17] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[26] ^ prior[27] ^ prior[29] ^ word[2] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[11] ^ word[14] ^ word[15] ^ word[16] ^ word[17] ^ word[21] ^ word[22] ^ word[23] ^ word[24] ^ word[26] ^ word[27] ^ word[29] ^ word[32] ^ word[35] ^ word[36] ^ word[37] ^ word[39] ^ word[40] ^ word[42] ^ word[43] ^ word[44] ^ word[48] ^ word[49] ^ word[51] ^ word[58] ^ word[60] ^ word[69] ^ word[70] ^ word[75] ^ word[78] ^ word[79] ^ word[80] ^ word[82] ^ word[89] ^ word[91] ^ word[94] ^ word[96] ^ word[97] ^ word[100] ^ word[102] ^ word[104] ^ word[105] ^ word[107] ^ word[109] ^ word[113] ^ word[114] ^ word[118] ^ word[121] ^ word[122] ^ word[126];
            crc_word[15] = prior[0] ^ prior[3] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[9] ^ prior[11] ^ prior[12] ^ prior[15] ^ prior[16] ^ prior[17] ^ prior[18] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[25] ^ prior[27] ^ prior[28] ^ prior[30] ^ word[0] ^ word[3] ^ word[6] ^ word[7] ^ word[8] ^ word[9] ^ word[11] ^ word[12] ^ word[15] ^ word[16] ^ word[17] ^ word[18] ^ word[22] ^ word[23] ^ word[24] ^ word[25] ^ word[27] ^ word[28] ^ word[30] ^ word[33] ^ word[36] ^ word[37] ^ word[38] ^ word[40] ^ word[41] ^ word[43] ^ word[44] ^ word[45] ^ word[49] ^ word[50] ^ word[52] ^ word[59] ^ word[61] ^ word[70] ^ word[71] ^ word[76] ^ word[79] ^ word[80] ^ word[81] ^ word[83] ^ word[90] ^ word[92] ^ word[95] ^ word[97] ^ word[98] ^ word[101] ^ word[103] ^ word[105] ^ word[106] ^ word[108] ^ word[110] ^ word[114] ^ word[115] ^ word[119] ^ word[122] ^ word[123] ^ word[127];
            crc_word[16] = prior[2] ^ prior[3] ^ prior[4] ^ prior[5] ^ prior[7] ^ prior[8] ^ prior[11] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[19] ^ prior[22] ^ prior[23] ^ prior[26] ^ prior[27] ^ prior[28] ^ prior[30] ^ word[2] ^ word[3] ^ word[4] ^ word[5] ^ word[7] ^ word[8] ^ word[11] ^ word[13] ^ word[14] ^ word[15] ^ word[16] ^ word[19] ^ word[22] ^ word[23] ^ word[26] ^ word[27] ^ word[28] ^ word[30] ^ word[32] ^ word[33] ^ word[37] ^ word[38] ^ word[39] ^ word[42] ^ word[43] ^ word[47] ^ word[49] ^ word[50] ^ word[51] ^ word[53] ^ word[55] ^ word[56] ^ word[61] ^ word[63] ^ word[65] ^ word[67] ^ word[68] ^ word[70] ^ word[71] ^ word[72] ^ word[73] ^ word[74] ^ word[75] ^ word[77] ^ word[78] ^ word[82] ^ word[83] ^ word[93] ^ word[94] ^ word[97] ^ word[100] ^ word[103] ^ word[106] ^ word[107] ^ word[109] ^ word[111] ^ word[112] ^ word[115] ^ word[118] ^ word[119] ^ word[120] ^ word[122] ^ word[123] ^ word[124];
            crc_word[17] = prior[3] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[8] ^ prior[9] ^ prior[12] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[17] ^ prior[20] ^ prior[23] ^ prior[24] ^ prior[27] ^ prior[28] ^ prior[29] ^ prior[31] ^ word[3] ^ word[4] ^ word[5] ^ word[6] ^ word[8] ^ word[9] ^ word[12] ^ word[14] ^ word[15] ^ word[16] ^ word[17] ^ word[20] ^ word[23] ^ word[24] ^ word[27] ^ word[28] ^ word[29] ^ word[31] ^ word[33] ^ word[34] ^ word[38] ^ word[39] ^ word[40] ^ word[43] ^ word[44] ^ word[48] ^ word[50] ^ word[51] ^ word[52] ^ word[54] ^ word[56] ^ word[57] ^ word[62] ^ word[64] ^ word[66] ^ word[68] ^ word[69] ^ word[71] ^ word[72] ^ word[73] ^ word[74] ^ word[75] ^ word[76] ^ word[78] ^ word[79] ^ word[83] ^ word[84] ^ word[94] ^ word[95] ^ word[98] ^ word[101] ^ word[104] ^ word[107] ^ word[108] ^ word[110] ^ word[112] ^ word[113] ^ word[116] ^ word[119] ^ word[120] ^ word[121] ^ word[123] ^ word[124] ^ word[125];
            crc_word[18] = prior[4] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[9] ^ prior[10] ^ prior[13] ^ prior[15] ^ prior[16] ^ prior[17] ^ prior[18] ^ prior[21] ^ prior[24] ^ prior[25] ^ prior[28] ^ prior[29] ^ prior[30] ^ word[4] ^ word[5] ^ word[6] ^ word[7] ^ word[9] ^ word[10] ^ word[13] ^ word[15] ^ word[16] ^ word[17] ^ word[18] ^ word[21] ^ word[24] ^ word[25] ^ word[28] ^ word[29] ^ word[30] ^ word[32] ^ word[34] ^ word[35] ^ word[39] ^ word[40] ^ word[41] ^ word[44] ^ word[45] ^ word[49] ^ word[51] ^ word[52] ^ word[53] ^ word[55] ^ word[57] ^ word[58] ^ word[63] ^ word[65] ^ word[67] ^ word[69] ^ word[70] ^ word[72] ^ word[73] ^ word[74] ^ word[75] ^ word[76] ^ word[77] ^ word[79] ^ word[80] ^ word[84] ^ word[85] ^ word[95] ^ word[96] ^ word[99] ^ word[102] ^ word[105] ^ word[108] ^ word[109] ^ word[111] ^ word[113] ^ word[114] ^ word[117] ^ word[120] ^ word[121] ^ word[122] ^ word[124] ^ word[125] ^ word[126];
            crc_word[19] = prior[0] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[11] ^ prior[14] ^ prior[16] ^ prior[17] ^ prior[18] ^ prior[19] ^ prior[22] ^ prior[25] ^ prior[26] ^ prior[29] ^ prior[30] ^ prior[31] ^ word[0] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[11] ^ word[14] ^ word[16] ^ word[17] ^ word[18] ^ word[19] ^ word[22] ^ word[25] ^ word[26] ^ word[29] ^ word[30] ^ word[31] ^ word[33] ^ word[35] ^ word[36] ^ word[40] ^ word[41] ^ word[42] ^ word[45] ^ word[46] ^ word[50] ^ word[52] ^ word[53] ^ word[54] ^ word[56] ^ word[58] ^ word[59] ^ word[64] ^ word[66] ^ word[68] ^ word[70] ^ word[71] ^ word[73] ^ word[74] ^ word[75] ^ word[76] ^ word[77] ^ word[78] ^ word[80] ^ word[81] ^ word[85] ^ word[86] ^ word[96] ^ word[97] ^ word[100] ^ word[103] ^ word[106] ^ word[109] ^ word[110] ^ word[112] ^ word[114] ^ word[115] ^ word[118] ^ word[121] ^ word[122] ^ word[123] ^ word[125] ^ word[126] ^ word[127];
            crc_word[20] = prior[2] ^ prior[3] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[14] ^ prior[19] ^ prior[20] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[25] ^ prior[26] ^ prior[29] ^ word[2] ^ word[3] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[14] ^ word[19] ^ word[20] ^ word[22] ^ word[23] ^ word[24] ^ word[25] ^ word[26] ^ word[29] ^ word[33] ^ word[36] ^ word[37] ^ word[42] ^ word[44] ^ word[45] ^ word[49] ^ word[51] ^ word[53] ^ word[54] ^ word[56] ^ word[57] ^ word[59] ^ word[61] ^ word[62] ^ word[63] ^ word[68] ^ word[69] ^ word[70] ^ word[71] ^ word[72] ^ word[73] ^ word[76] ^ word[77] ^ word[79] ^ word[80] ^ word[82] ^ word[83] ^ word[84] ^ word[86] ^ word[87] ^ word[91] ^ word[94] ^ word[96] ^ word[99] ^ word[100] ^ word[101] ^ word[102] ^ word[103] ^ word[107] ^ word[110] ^ word[111] ^ word[112] ^ word[113] ^ word[115] ^ word[118] ^ word[123] ^ word[124] ^ word[126] ^ word[127];
            crc_word[21] = prior[0] ^ prior[1] ^ prior[2] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[12] ^ prior[14] ^ prior[17] ^ prior[18] ^ prior[20] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[26] ^ prior[29] ^ prior[31] ^ word[0] ^ word[1] ^ word[2] ^ word[4] ^ word[5] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[12] ^ word[14] ^ word[17] ^ word[18] ^ word[20] ^ word[21] ^ word[22] ^ word[23] ^ word[26] ^ word[29] ^ word[31] ^ word[32] ^ word[33] ^ word[37] ^ word[38] ^ word[41] ^ word[44] ^ word[47] ^ word[49] ^ word[50] ^ word[52] ^ word[54] ^ word[56] ^ word[57] ^ word[58] ^ word[61] ^ word[64] ^ word[65] ^ word[67] ^ word[68] ^ word[69] ^ word[71] ^ word[72] ^ word[75] ^ word[77] ^ word[85] ^ word[87] ^ word[88] ^ word[91] ^ word[92] ^ word[94] ^ word[95] ^ word[96] ^ word[98] ^ word[99] ^ word[101] ^ word[108] ^ word[111] ^ word[113] ^ word[114] ^ word[118] ^ word[122] ^ word[124] ^ word[125] ^ word[127];
            crc_word[22] = prior[0] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[10] ^ prior[12] ^ prior[13] ^ prior[14] ^ prior[17] ^ prior[19] ^ prior[21] ^ prior[23] ^ prior[25] ^ prior[29] ^ prior[31] ^ word[0] ^ word[6] ^ word[7] ^ word[8] ^ word[10] ^ word[12] ^ word[13] ^ word[14] ^ word[17] ^ word[19] ^ word[21] ^ word[23] ^ word[25] ^ word[29] ^ word[31] ^ word[38] ^ word[39] ^ word[41] ^ word[42] ^ word[43] ^ word[44] ^ word[46] ^ word[47] ^ word[48] ^ word[49] ^ word[50] ^ word[51] ^ word[53] ^ word[56] ^ word[57] ^ word[58] ^ word[59] ^ word[60] ^ word[61] ^ word[63] ^ word[66] ^ word[67] ^ word[69] ^ word[72] ^ word[74] ^ word[75] ^ word[76] ^ word[80] ^ word[81] ^ word[83] ^ word[84] ^ word[86] ^ word[88] ^ word[89] ^ word[91] ^ word[92] ^ word[93] ^ word[94] ^ word[95] ^ word[98] ^ word[103] ^ word[104] ^ word[109] ^ word[114] ^ word[115] ^ word[116] ^ word[118] ^ word[122] ^ word[123] ^ word[125] ^ word[126];
            crc_word[23] = prior[1] ^ prior[7] ^ prior[8] ^ prior[9] ^ prior[11] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[18] ^ prior[20] ^ prior[22] ^ prior[24] ^ prior[26] ^ prior[30] ^ word[1] ^ word[7] ^ word[8] ^ word[9] ^ word[11] ^ word[13] ^ word[14] ^ word[15] ^ word[18] ^ word[20] ^ word[22] ^ word[24] ^ word[26] ^ word[30] ^ word[32] ^ word[39] ^ word[40] ^ word[42] ^ word[43] ^ word[44] ^ word[45] ^ word[47] ^ word[48] ^ word[49] ^ word[50] ^ word[51] ^ word[52] ^ word[54] ^ word[57] ^ word[58] ^ word[59] ^ word[60] ^ word[61] ^ word[62] ^ word[64] ^ word[67] ^ word[68] ^ word[70] ^ word[73] ^ word[75] ^ word[76] ^ word[77] ^ word[81] ^ word[82] ^ word[84] ^ word[85] ^ word[87] ^ word[89] ^ word[90] ^ word[92] ^ word[93] ^ word[94] ^ word[95] ^ word[96] ^ word[99] ^ word[104] ^ word[105] ^ word[110] ^ word[115] ^ word[116] ^ word[117] ^ word[119] ^ word[123] ^ word[124] ^ word[126] ^ word[127];
            crc_word[24] = prior[1] ^ prior[3] ^ prior[5] ^ prior[8] ^ prior[11] ^ prior[16] ^ prior[17] ^ prior[18] ^ prior[19] ^ prior[21] ^ prior[22] ^ prior[23] ^ prior[24] ^ prior[29] ^ prior[30] ^ word[1] ^ word[3] ^ word[5] ^ word[8] ^ word[11] ^ word[16] ^ word[17] ^ word[18] ^ word[19] ^ word[21] ^ word[22] ^ word[23] ^ word[24] ^ word[29] ^ word[30] ^ word[32] ^ word[34] ^ word[40] ^ word[47] ^ word[48] ^ word[50] ^ word[51] ^ word[52] ^ word[53] ^ word[56] ^ word[58] ^ word[59] ^ word[67] ^ word[69] ^ word[70] ^ word[71] ^ word[73] ^ word[75] ^ word[76] ^ word[77] ^ word[80] ^ word[81] ^ word[82] ^ word[84] ^ word[85] ^ word[86] ^ word[88] ^ word[90] ^ word[93] ^ word[95] ^ word[98] ^ word[99] ^ word[102] ^ word[103] ^ word[104] ^ word[105] ^ word[106] ^ word[111] ^ word[112] ^ word[117] ^ word[119] ^ word[120] ^ word[122] ^ word[124] ^ word[125] ^ word[127];
            crc_word[25] = prior[0] ^ prior[1] ^ prior[3] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[10] ^ prior[11] ^ prior[14] ^ prior[15] ^ prior[19] ^ prior[20] ^ prior[23] ^ prior[27] ^ prior[29] ^ word[0] ^ word[1] ^ word[3] ^ word[4] ^ word[5] ^ word[6] ^ word[10] ^ word[11] ^ word[14] ^ word[15] ^ word[19] ^ word[20] ^ word[23] ^ word[27] ^ word[29] ^ word[32] ^ word[34] ^ word[35] ^ word[43] ^ word[44] ^ word[45] ^ word[46] ^ word[47] ^ word[48] ^ word[51] ^ word[52] ^ word[53] ^ word[54] ^ word[55] ^ word[56] ^ word[57] ^ word[59] ^ word[61] ^ word[62] ^ word[63] ^ word[65] ^ word[67] ^ word[71] ^ word[72] ^ word[73] ^ word[75] ^ word[76] ^ word[77] ^ word[80] ^ word[82] ^ word[84] ^ word[85] ^ word[86] ^ word[87] ^ word[89] ^ word[97] ^ word[98] ^ word[102] ^ word[105] ^ word[106] ^ word[107] ^ word[113] ^ word[116] ^ word[119] ^ word[120] ^ word[121] ^ word[122] ^ word[123] ^ word[125] ^ word[126];
            crc_word[26] = prior[0] ^ prior[1] ^ prior[2] ^ prior[4] ^ prior[5] ^ prior[6] ^ prior[7] ^ prior[11] ^ prior[12] ^ prior[15] ^ prior[16] ^ prior[20] ^ prior[21] ^ prior[24] ^ prior[28] ^ prior[30] ^ word[0] ^ word[1] ^ word[2] ^ word[4] ^ word[5] ^ word[6] ^ word[7] ^ word[11] ^ word[12] ^ word[15] ^ word[16] ^ word[20] ^ word[21] ^ word[24] ^ word[28] ^ word[30] ^ word[33] ^ word[35] ^ word[36] ^ word[44] ^ word[45] ^ word[46] ^ word[47] ^ word[48] ^ word[49] ^ word[52] ^ word[53] ^ word[54] ^ word[55] ^ word[56] ^ word[57] ^ word[58] ^ word[60] ^ word[62] ^ word[63] ^ word[64] ^ word[66] ^ word[68] ^ word[72] ^ word[73] ^ word[74] ^ word[76] ^ word[77] ^ word[78] ^ word[81] ^ word[83] ^ word[85] ^ word[86] ^ word[87] ^ word[88] ^ word[90] ^ word[98] ^ word[99] ^ word[103] ^ word[106] ^ word[107] ^ word[108] ^ word[114] ^ word[117] ^ word[120] ^ word[121] ^ word[122] ^ word[123] ^ word[124] ^ word[126] ^ word[127];
            crc_word[27] = prior[0] ^ prior[6] ^ prior[7] ^ prior[8] ^ prior[9] ^ prior[10] ^ prior[11] ^ prior[13] ^ prior[14] ^ prior[15] ^ prior[16] ^ prior[18] ^ prior[21] ^ prior[24] ^ prior[27] ^ prior[30] ^ word[0] ^ word[6] ^ word[7] ^ word[8] ^ word[9] ^ word[10] ^ word[11] ^ word[13] ^ word[14] ^ word[15] ^ word[16] ^ word[18] ^ word[21] ^ word[24] ^ word[27] ^ word[30] ^ word[32] ^ word[33] ^ word[36] ^ word[37] ^ word[41] ^ word[43] ^ word[44] ^ word[48] ^ word[50] ^ word[53] ^ word[54] ^ word[57] ^ word[58] ^ word[59] ^ word[60] ^ word[62] ^ word[64] ^ word[68] ^ word[69] ^ word[70] ^ word[77] ^ word[79] ^ word[80] ^ word[81] ^ word[82] ^ word[83] ^ word[86] ^ word[87] ^ word[88] ^ word[89] ^ word[94] ^ word[96] ^ word[97] ^ word[98] ^ word[102] ^ word[103] ^ word[107] ^ word[108] ^ word[109] ^ word[112] ^ word[115] ^ word[116] ^ word[119] ^ word[121] ^ word[123] ^ word[124] ^ word[125] ^ word[127];
            crc_word[28] = prior[2] ^ prior[3] ^ prior[5] ^ prior[7] ^ prior[8] ^ prior[16] ^ prior[18] ^ prior[19] ^ prior[24] ^ prior[27] ^ prior[28] ^ prior[29] ^ prior[30] ^ word[2] ^ word[3] ^ word[5] ^ word[7] ^ word[8] ^ word[16] ^ word[18] ^ word[19] ^ word[24] ^ word[27] ^ word[28] ^ word[29] ^ word[30] ^ word[32] ^ word[37] ^ word[38] ^ word[41] ^ word[42] ^ word[43] ^ word[46] ^ word[47] ^ word[51] ^ word[54] ^ word[56] ^ word[58] ^ word[59] ^ word[62] ^ word[67] ^ word[68] ^ word[69] ^ word[71] ^ word[73] ^ word[74] ^ word[75] ^ word[82] ^ word[87] ^ word[88] ^ word[89] ^ word[90] ^ word[91] ^ word[94] ^ word[95] ^ word[96] ^ word[100] ^ word[102] ^ word[108] ^ word[109] ^ word[110] ^ word[112] ^ word[113] ^ word[117] ^ word[118] ^ word[119] ^ word[120] ^ word[124] ^ word[125] ^ word[126];
            crc_word[29] = prior[0] ^ prior[3] ^ prior[4] ^ prior[6] ^ prior[8] ^ prior[9] ^ prior[17] ^ prior[19] ^ prior[20] ^ prior[25] ^ prior[28] ^ prior[29] ^ prior[30] ^ prior[31] ^ word[0] ^ word[3] ^ word[4] ^ word[6] ^ word[8] ^ word[9] ^ word[17] ^ word[19] ^ word[20] ^ word[25] ^ word[28] ^ word[29] ^ word[30] ^ word[31] ^ word[33] ^ word[38] ^ word[39] ^ word[42] ^ word[43] ^ word[44] ^ word[47] ^ word[48] ^ word[52] ^ word[55] ^ word[57] ^ word[59] ^ word[60] ^ word[63] ^ word[68] ^ word[69] ^ word[70] ^ word[72] ^ word[74] ^ word[75] ^ word[76] ^ word[83] ^ word[88] ^ word[89] ^ word[90] ^ word[91] ^ word[92] ^ word[95] ^ word[96] ^ word[97] ^ word[101] ^ word[103] ^ word[109] ^ word[110] ^ word[111] ^ word[113] ^ word[114] ^ word[118] ^ word[119] ^ word[120] ^ word[121] ^ word[125] ^ word[126] ^ word[127];
            crc_word[30] = prior[2] ^ prior[3] ^ prior[4] ^ prior[7] ^ prior[11] ^ prior[12] ^ prior[14] ^ prior[15] ^ prior[17] ^ prior[20] ^ prior[21] ^ prior[22] ^ prior[24] ^ prior[25] ^ prior[26] ^ prior[27] ^ word[2] ^ word[3] ^ word[4] ^ word[7] ^ word[11] ^ word[12] ^ word[14] ^ word[15] ^ word[17] ^ word[20] ^ word[21] ^ word[22] ^ word[24] ^ word[25] ^ word[26] ^ word[27] ^ word[33] ^ word[39] ^ word[40] ^ word[41] ^ word[46] ^ word[47] ^ word[48] ^ word[53] ^ word[55] ^ word[58] ^ word[62] ^ word[63] ^ word[64] ^ word[65] ^ word[67] ^ word[68] ^ word[69] ^ word[71] ^ word[74] ^ word[76] ^ word[77] ^ word[78] ^ word[80] ^ word[81] ^ word[83] ^ word[89] ^ word[90] ^ word[92] ^ word[93] ^ word[94] ^ word[99] ^ word[100] ^ word[103] ^ word[110] ^ word[111] ^ word[114] ^ word[115] ^ word[116] ^ word[118] ^ word[120] ^ word[121] ^ word[126] ^ word[127];
            crc_word[31] = prior[0] ^ prior[1] ^ prior[2] ^ prior[4] ^ prior[8] ^ prior[9] ^ prior[10] ^ prior[11] ^ prior[13] ^ prior[14] ^ prior[16] ^ prior[17] ^ prior[21] ^ prior[23] ^ prior[24] ^ prior[26] ^ prior[28] ^ prior[29] ^ prior[30] ^ prior[31] ^ word[0] ^ word[1] ^ word[2] ^ word[4] ^ word[8] ^ word[9] ^ word[10] ^ word[11] ^ word[13] ^ word[14] ^ word[16] ^ word[17] ^ word[21] ^ word[23] ^ word[24] ^ word[26] ^ word[28] ^ word[29] ^ word[30] ^ word[31] ^ word[32] ^ word[33] ^ word[40] ^ word[42] ^ word[43] ^ word[44] ^ word[45] ^ word[46] ^ word[48] ^ word[54] ^ word[55] ^ word[59] ^ word[60] ^ word[61] ^ word[62] ^ word[64] ^ word[66] ^ word[67] ^ word[69] ^ word[72] ^ word[73] ^ word[74] ^ word[77] ^ word[79] ^ word[80] ^ word[82] ^ word[83] ^ word[90] ^ word[93] ^ word[95] ^ word[96] ^ word[97] ^ word[98] ^ word[99] ^ word[101] ^ word[102] ^ word[103] ^ word[111] ^ word[115] ^ word[117] ^ word[118] ^ word[121] ^ word[127];
        end
    endfunction


    always @* begin
        source_bytes882=0;
        for(lane=0;lane<16;lane=lane+1)if(s_keep[lane])source_bytes882=source_bytes882+1'b1;
        masked_input=0;
        for(lane=0;lane<16;lane=lane+1)if(input_keep[lane])masked_input[lane*8+:8]=input_data[lane*8+:8];
        checksum_bytes=16;
        m_data=0;
        case(state)
            HEAD0:m_data={HEIGHT16,WIDTH16,segment_id,frame_id,32'h3247504a};
            HEAD1:m_data={DECODED_BYTES,kind,payload_bytes,frame_offset};
            PAYLOAD:begin
                m_data=kind==0 ? payload_word : {32'd2,segment_id,frame_offset,kind==2 ? reason : 32'd0};
                if(payload_bytes-send_word*16<16)checksum_bytes=payload_bytes-send_word*16;
            end
            TRAILER:m_data={32'd0,payload_bytes,~checksum,32'h32435243};
        endcase
    end
    wire read_payload=kind==0 && (state==HEAD1 || (state==PAYLOAD && (send_word+1)*16<payload_bytes));
    wire [7:0] read_address=state==HEAD1 ? 8'd0 : send_word[7:0]+8'd1;
    always @(posedge clk)if(!reset && m_ready && read_payload)payload_word<=memory[read_address];
    // CRC advances only while sending a packet. While collecting the next
    // packet, preload the seed independently of source verdict/abort logic.
    // Every HEAD0 entry follows IDLE/FILL/WAIT_END/CHECK_INPUT, so the seed is
    // available before its first advertised word without a fault-to-CRC path.
    always @(posedge clk)begin
        if(reset)checksum<=32'hffffffff;
        else if(state==TAIL)checksum<=crc_update(checksum,tail_data,1);
        else if(m_valid && m_ready &&
            (state==HEAD0 || state==HEAD1 || (state==PAYLOAD && checksum_bytes==16)))
            checksum<=crc_word(checksum,m_data);
        else if(state==IDLE || state==FILL || state==WAIT_END || state==CHECK_INPUT)
            checksum<=32'hffffffff;
    end
    // Cursor is only observed while advertising packet data. Preload it
    // independently in every collection/start state, including the edge that
    // selects an immediate ABORT. No fault/flush decision is delayed.
    always @(posedge clk)begin
        if(reset || state==IDLE || state==FILL || state==WAIT_END || state==CHECK_INPUT)
            send_word<=0;
        else if(state==PAYLOAD && m_ready)send_word<=send_word+1'b1;
    end
    always @(posedge clk)begin
        if(reset)begin
            remaining_bytes<=MAX_BYTES;incoming_bytes<=0;input_keep_invalid882<=0;
            state<=IDLE;frame_id<=0;segment_id<=0;frame_offset<=0;payload_bytes<=0;
            timer<=0;reason<=0;kind<=0;last_data<=0;
            got_good<=0;bad_pending<=0;ignored_verdicts<=0;tail_data<=0;tail_bytes<=0;input_data<=0;input_keep<=0;input_sof<=0;input_last<=0;
        end else begin
            if(verdict_valid && !(active && verdict_id==frame_id) && !(start_valid && start_ready && verdict_id==start_id))ignored_verdicts<=ignored_verdicts+1'b1;
            if(matching_verdict && verdict_good)got_good<=1;
            if(bad_now || timeout_now)begin
                bad_pending<=1;
                if(!bad_pending)reason<=timeout_now ? 32'd4 : abort_valid ? (abort_reason==0 ? 32'd1 : abort_reason) : (verdict_reason==0 ? 32'd1 : verdict_reason);
            end
            if(state==FILL || state==WAIT_END)begin
                if(s_valid && s_ready)timer<=0;
                else if(!timeout_now)timer<=timer+1'b1;
            end else timer<=0;
            if(state==IDLE && start_valid)begin
                remaining_bytes<=MAX_BYTES;
                state<=FILL;frame_id<=start_id;segment_id<=0;frame_offset<=0;payload_bytes<=0;
                kind<=0;last_data<=0;got_good<=0;bad_pending<=0;reason<=0;timer<=0;
                // A verdict on the start edge belongs to this new transaction.
                if(verdict_valid && verdict_id==start_id)begin
                    if(verdict_good)got_good<=1;
                    else begin bad_pending<=1;reason<=verdict_reason==0 ? 32'd1 : verdict_reason;end
                end
            end else if((state==FILL || state==WAIT_END || state==CHECK_INPUT) && flush)begin
                kind<=2;payload_bytes<=16;state<=HEAD0;
                if(!bad_pending)reason<=timeout_now ? 32'd4 : abort_valid ? (abort_reason==0 ? 32'd1 : abort_reason) : (verdict_reason==0 ? 32'd1 : verdict_reason);
            end else if(state==WAIT_END && got_good)begin
                kind<=1;payload_bytes<=16;state<=HEAD0;
            end else if(s_valid && s_ready)begin
                input_data<=s_data;input_keep<=s_keep;input_sof<=s_sof;input_last<=s_last;
                incoming_bytes<=source_bytes882;
                input_keep_invalid882<=s_keep==0 || (s_keep & (s_keep+16'd1))!=0 || (!s_last && s_keep!=16'hffff);
                state<=CHECK_INPUT;
            end else if(state==CHECK_INPUT)begin
                state<=FILL;
                if(input_sof!=(frame_offset==0 && payload_bytes==0) || input_keep_invalid882 ||
                   incoming_bytes>remaining_bytes)begin
                    bad_pending<=1;reason<=2;
                end else begin
                    remaining_bytes<=remaining_bytes-incoming_bytes;
                    memory[payload_bytes/16]<=masked_input;
                    payload_bytes<=payload_bytes+incoming_bytes;last_data<=input_last;
                    if(input_last || payload_bytes+incoming_bytes==CHUNK_BYTES)begin
                        kind<=0;state<=HEAD0;
                    end
                end
            end else if(state==TAIL)begin
                tail_data<=tail_data>>8;tail_bytes<=tail_bytes-1'b1;
                if(tail_bytes==1)state<=TRAILER;
            end else if(m_valid && m_ready)begin
                case(state)
                    HEAD0:begin state<=HEAD1;end
                    HEAD1:begin state<=PAYLOAD;end
                    PAYLOAD:begin

                        if(checksum_bytes==16)begin
                            
                            if((send_word+1)*16>=payload_bytes)state<=TRAILER;
                        end else begin tail_data<=m_data;tail_bytes<=checksum_bytes;state<=TAIL;end
                    end
                    TRAILER:begin
                        if(kind!=0)state<=IDLE;
                        else begin
                            frame_offset<=frame_offset+payload_bytes;segment_id<=segment_id+1'b1;
                            payload_bytes<=0;state<=last_data ? WAIT_END : FILL;
                        end
                    end
                endcase
            end
        end
    end
endmodule
