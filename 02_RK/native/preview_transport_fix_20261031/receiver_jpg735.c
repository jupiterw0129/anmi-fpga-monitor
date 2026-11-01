/* JPG2 bounded provisional-JPEG receiver. Header validation is not full decode. No DMA/driver/board side effects. */
#include <stdint.h>
#if defined(__ARM_FEATURE_CRC32)
#include <arm_acle.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CAPACITY (1920u*1080u*6u+65536u)
struct receiver735 {
    uint8_t *payload;
    uint32_t frame,width,height,next_frame,index,length;
    unsigned active,have_next,failed;
};
static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;
}
static unsigned u16(const uint8_t *p) { return (unsigned)p[0]|(unsigned)p[1]<<8; }
static uint32_t crc_update735(uint32_t crc,const uint8_t *p,size_t n) {
#if defined(__ARM_FEATURE_CRC32)
    while(n>=8) { uint64_t word;memcpy(&word,p,8);crc=__crc32d(crc,word);p+=8;n-=8; }
    while(n--)crc=__crc32b(crc,*p++);
#else
    while(n--) { crc^=*p++;for(unsigned i=0;i<8;i++)crc=(crc>>1)^((crc&1u)?0xedb88320u:0); }
#endif
    return crc;
}
#include <setjmp.h>
#include <jpeglib.h>
struct jpeg_error735 { struct jpeg_error_mgr base; jmp_buf jump; };
static void jpeg_fail735(j_common_ptr info) {
    struct jpeg_error735 *error=(struct jpeg_error735 *)info->err;
    longjmp(error->jump,1);
}
static void jpeg_message735(j_common_ptr info,int level) {
    if(level<0)jpeg_fail735(info); /* Reject warnings instead of accepting repaired headers. */
}
static int jpeg_header735(const uint8_t *p,uint32_t size,unsigned width,unsigned height) {
    if(size<4u || p[0]!=0xffu || p[1]!=0xd8u || p[size-2u]!=0xffu || p[size-1u]!=0xd9u)return 0;
    struct jpeg_decompress_struct info;
    struct jpeg_error735 error;
    volatile int created=0;
    memset(&info,0,sizeof(info));
    info.err=jpeg_std_error(&error.base);
    error.base.error_exit=jpeg_fail735;error.base.emit_message=jpeg_message735;
    if(setjmp(error.jump)) { if(created)jpeg_destroy_decompress(&info);return 0; }
    jpeg_create_decompress(&info);created=1;
    jpeg_mem_src(&info,p,size);
    int good=jpeg_read_header(&info,TRUE)==JPEG_HEADER_OK &&
        info.image_width==width && info.image_height==height &&
        info.data_precision==8 && info.num_components==3 && !info.progressive_mode;
    jpeg_destroy_decompress(&info);
    return good;
}
/* Returns 0 provisional DATA, 1 publishable COMMIT, 2 discarded ABORT, -1 fatal.
 * Payload remains readable until the next push, and must only be read on 1. */
int receiver735_push(struct receiver735 *s,const uint8_t *p,size_t size,uint32_t *reason) {
    if(s->failed)return -1;
    if(size<64u || size>4144u || size%16u)goto bad;
    uint32_t frame=u32(p+4),index=u32(p+8),offset=u32(p+16),length=u32(p+20),kind=u32(p+24);
    unsigned width=u16(p+12),height=u16(p+14);
    uint32_t decoded=width*height*3u;
    if(memcmp(p,"JPG2",4) || !width || width>1920u || width%16u || !height || height>1080u || height%8u || u32(p+28)!=decoded)goto bad;
    if(kind>2u || !length || length>4096u || (kind && length!=16u))goto bad;
    uint32_t padded=(length+15u)/16u*16u;
    if(size!=48u+padded)goto bad;
    for(unsigned i=length;i<padded;i++)if(p[32u+i])goto bad;
    const uint8_t *trailer=p+32u+padded;
    uint32_t crc=~crc_update735(crc_update735(UINT32_MAX,p,32),p+32,length);
    if(memcmp(trailer,"CRC2",4) || u32(trailer+4)!=crc || u32(trailer+8)!=length || u32(trailer+12))goto bad;
    uint32_t maximum=width*height*6u+65536u;
    if(offset>maximum || (!kind && length>maximum-offset))goto bad;
    *reason=0;
    if(kind) {
        *reason=u32(p+32);
        if(u32(p+36)!=offset || u32(p+40)!=index || u32(p+44)!=2u || (kind==1u && *reason) || (kind==2u && !*reason))goto bad;
    }
    if(!s->active) {
        if(index || offset || (s->have_next && (uint32_t)(frame-s->next_frame)>=0x80000000u))goto bad;
        s->frame=frame;s->width=width;s->height=height;s->active=1;
    }
    if(s->frame!=frame || s->width!=width || s->height!=height || s->index!=index || s->length!=offset)goto bad;
    if(!kind) {
        if(length>CAPACITY-s->length)goto bad;
        memcpy(s->payload+s->length,p+32,length);s->length+=length;s->index++;return 0;
    }
    if(kind==1u && !jpeg_header735(s->payload,s->length,width,height))goto bad;
    s->next_frame=frame+1u;s->have_next=1;s->active=0;s->index=0;
    return (int)kind;
bad:
    s->failed=1;s->active=0;s->length=0;return -1;
}
/* Caller acknowledges a terminal event before feeding the next transaction. */
void receiver735_release(struct receiver735 *s) { s->length=0; }
int receiver735_finish(struct receiver735 *s) { return s->failed || s->active ? -1:0; }
#ifdef RECEIVER735_REPLAY
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    FILE *f=fopen(argv[1],"rb");if(!f)return 3;
    struct receiver735 s={0};s.payload=malloc(CAPACITY);if(!s.payload){fclose(f);return 4;}
    uint8_t packet[4144],prefix[4];unsigned commits=0,aborts=0,packets=0;int failure=0;
    while(1) {
        size_t got=fread(prefix,1,4,f);
        if(!got && !ferror(f))break;
        if(got!=4){failure=1;break;}
        uint32_t n=u32(prefix),reason=0;
        if(n<64 || n>sizeof(packet) || fread(packet,1,n,f)!=n){failure=1;break;}
        int event=receiver735_push(&s,packet,n,&reason);++packets;
        if(event<0){failure=1;break;}
        if(event) {
            printf("{\"kind\":%d,\"frame_id\":%u,\"reason\":%u,\"encoded_bytes\":%u,\"encoded_crc32\":%u}\n",
                event,s.frame,reason,s.length,event==1 ? ~crc_update735(UINT32_MAX,s.payload,s.length):0);
            commits+=event==1;aborts+=event==2;receiver735_release(&s);
        }
    }
    failure=failure || receiver735_finish(&s)!=0;
    printf("{\"committed\":%u,\"aborted\":%u,\"packets\":%u,\"failed\":%s}\n",commits,aborts,packets,failure?"true":"false");
    free(s.payload);fclose(f);return failure?1:0;
}
#endif
