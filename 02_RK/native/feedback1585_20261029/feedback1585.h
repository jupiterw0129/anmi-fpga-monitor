/* Metadata is copied from the receiver's immutable COMMIT payload, before reuse.
 * SHA256 comes from the installed OpenSSL 3 library, not a custom hash. */
#include <stdint.h>
extern unsigned char *SHA256(const unsigned char *,size_t,unsigned char *);

static int feedback1585(unsigned frame,int slot,unsigned size,double completed,const uint8_t *data) {
    unsigned char digest[32],tables[2][64];unsigned found=0;size_t at=2;
    if(size<4 || data[0]!=255 || data[1]!=216 || data[size-2]!=255 || data[size-1]!=217)goto invalid;
    while(at+4<=size) {
        if(data[at++]!=255)goto invalid;
        while(at<size && data[at]==255)++at;
        if(at>=size)goto invalid;
        unsigned marker=data[at++];
        if(marker==218)break;
        if(marker==216 || marker==217 || marker==1 || (marker>=208 && marker<=215))continue;
        if(at+2>size)goto invalid;
        size_t length=((size_t)data[at]<<8)|data[at+1];
        if(length<2 || length>size-at)goto invalid;
        if(marker==219) {
            size_t p=at+2,end=at+length;
            while(p<end) {
                unsigned key=data[p++];
                if(key>1 || found&(1u<<key) || end-p<64)goto invalid;
                memcpy(tables[key],data+p,64);p+=64;found|=1u<<key;
            }
        }
        at+=length;
    }
    if(found!=3 || !SHA256(data,size,digest))goto invalid;
    static const char hex[]="0123456789abcdef";
    char hash[65],signature[261];unsigned p=0;
    for(unsigned i=0;i<32;++i){hash[2*i]=hex[digest[i]>>4];hash[2*i+1]=hex[digest[i]&15];}
    hash[64]=0;
    for(unsigned key=0;key<2;++key) {
        signature[p++]=hex[key>>4];signature[p++]=hex[key&15];
        for(unsigned i=0;i<64;++i){signature[p++]=hex[tables[key][i]>>4];signature[p++]=hex[tables[key][i]&15];}
    }
    signature[p]=0;
    if(printf("FRAME %u %d %u %.9f %s %s\n",frame,slot,size,completed,hash,signature)<0 || fflush(stdout))return -1;
    return 0;
invalid:
    errno=EPROTO;return -1;
}
