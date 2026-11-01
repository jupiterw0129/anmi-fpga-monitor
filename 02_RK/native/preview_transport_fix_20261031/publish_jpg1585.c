/* EOP packet adapter: strict JPG2 COMMIT -> independently locked JPEG slots.
 * No BAR, driver, camera, or DMA access. A future live EOP reader calls push755.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include "receiver_jpg735.c"
#include "feedback1585.h"
#define SLOT_COUNT755 4u
#define SLOT_BYTES755 ((size_t)CAPACITY+64u)
#define SHARED_BYTES755 (SLOT_COUNT755*SLOT_BYTES755)
struct jpeg_slot755 {
    char magic[8];uint64_t frame,length;double completed;
    uint64_t packets,encoded;uint32_t width,height,generation,flags;
};
_Static_assert(sizeof(struct jpeg_slot755)==64u,"JPEG slot ABI");
struct publisher755 {
    struct receiver735 receiver;
    int shared;uint8_t *mapping;uint32_t generation;
    unsigned committed,aborted,published,dropped,frame_packets,used;
    uint64_t packets,wire_bytes;
    int (*record)(void *,const struct jpeg_slot755 *,const uint8_t *);
    void *record_context;
};
static int slot_lock755(int fd,unsigned slot,short type) {
    struct flock l={.l_type=type,.l_whence=SEEK_SET,.l_start=(off_t)slot*SLOT_BYTES755,.l_len=SLOT_BYTES755};
    return fcntl(fd,F_SETLK,&l);
}
/* 0 DATA, 1 published COMMIT, 2 ABORT, 3 COMMIT dropped due to reader locks,
 * -1 fatal input/publication failure. ABORT and invalid input never publish.
 */
int push755(struct publisher755 *p,const uint8_t *packet,size_t size) {
    uint32_t reason=0;
    int event=receiver735_push(&p->receiver,packet,size,&reason);
    ++p->packets;++p->frame_packets;p->wire_bytes+=size;
    if(event<0){errno=EBADMSG;return -1;}
    if(event==1) {
        ++p->committed;
        int slot=-1;
        for(unsigned n=0;n<SLOT_COUNT755;n++) {
            unsigned candidate=(p->published+n)%SLOT_COUNT755;
            if(!slot_lock755(p->shared,candidate,F_WRLCK)){slot=(int)candidate;break;}
            if(errno!=EACCES && errno!=EAGAIN)return -1;
        }
        if(slot>=0) {
            struct timespec t;
            if(clock_gettime(CLOCK_MONOTONIC,&t)){int saved=errno;slot_lock755(p->shared,(unsigned)slot,F_UNLCK);errno=saved;return -1;}
            struct receiver735 *s=&p->receiver;
            struct jpeg_slot755 h={.magic="JPGS755",.frame=s->frame,.length=s->length,
                .completed=(double)t.tv_sec+(double)t.tv_nsec/1e9,.packets=p->frame_packets,
                .encoded=s->length,.width=s->width,.height=s->height,.generation=p->generation,.flags=1};
            uint8_t *dest=p->mapping+(size_t)slot*SLOT_BYTES755;
            memset(dest,0,64u);memcpy(dest+64u,s->payload,s->length);memcpy(dest,&h,64u);
            if(slot_lock755(p->shared,(unsigned)slot,F_UNLCK))return -1;
            if(p->record && p->record(p->record_context,&h,s->payload))return -1;
            ++p->published;p->used|=1u<<(unsigned)slot;
            if(feedback1585(s->frame,slot,s->length,h.completed,s->payload))return -1;
        }else {++p->dropped;event=3;}
    }else if(event==2) {++p->aborted;printf("ABORT %u %u\n",p->receiver.frame,reason);fflush(stdout);}
    if(event){receiver735_release(&p->receiver);p->frame_packets=0;}
    return event;
}
#ifdef PUBLISH755_REPLAY
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    char *end=NULL;errno=0;unsigned long generation=strtoul(argv[3],&end,10);
    if(errno || !*argv[3] || *end || generation>UINT32_MAX)return 2;
    struct publisher755 p={.shared=-1,.mapping=MAP_FAILED,.generation=(uint32_t)generation};
    FILE *input=NULL;int failed=0;struct stat st;
    int fd=open(argv[1],O_RDONLY|O_NOFOLLOW);
    if(fd<0)return 3;
    if(fstat(fd,&st)||!S_ISREG(st.st_mode)){close(fd);return 3;}
    input=fdopen(fd,"rb");if(!input){close(fd);return 3;}
    p.shared=open(argv[2],O_RDWR|O_NOFOLLOW);
    if(p.shared<0 || fstat(p.shared,&st) || !S_ISREG(st.st_mode) || st.st_uid!=getuid() ||
       (st.st_mode&0777)!=0600 || st.st_size!=(off_t)SHARED_BYTES755){failed=1;goto cleanup;}
    p.mapping=mmap(NULL,SHARED_BYTES755,PROT_READ|PROT_WRITE,MAP_SHARED,p.shared,0);
    p.receiver.payload=malloc(CAPACITY);
    if(p.mapping==MAP_FAILED || !p.receiver.payload){failed=1;goto cleanup;}
    for(;;) {
        uint8_t prefix[4],packet[4144];size_t got=fread(prefix,1,4,input);
        if(!got&&!ferror(input))break;
        if(got!=4){failed=1;break;}
        uint32_t size=u32(prefix);
        if(size<64u||size>sizeof(packet)||fread(packet,1,size,input)!=size){failed=1;break;}
        if(push755(&p,packet,size)<0){failed=1;break;}
    }
    if(receiver735_finish(&p.receiver))failed=1;
cleanup:
    printf("{\"committed\":%u,\"aborted\":%u,\"published\":%u,\"slot_busy_drops\":%u,\"packets\":%llu,\"wire_bytes\":%llu,\"used_slot_mask\":%u,\"failed\":%s}\n",
        p.committed,p.aborted,p.published,p.dropped,(unsigned long long)p.packets,(unsigned long long)p.wire_bytes,p.used,failed?"true":"false");
    free(p.receiver.payload);
    if(p.mapping!=MAP_FAILED)munmap(p.mapping,SHARED_BYTES755);
    if(p.shared>=0)close(p.shared);
    if(input)fclose(input);
    return failed?1:0;
}
#endif
