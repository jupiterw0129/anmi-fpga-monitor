/* Strict JPG2 per-EOP DMA adapter for board884. BAR is read-only here;
 * the controller owns capture enable, draining handshake and driver recovery.
 * Replay uses the identical receiver/publication path without device access. */
#define _POSIX_C_SOURCE 200809L
#include <poll.h>
#include "publish_jpg1585.c"
#include "record_writer1326.h"


static uint32_t reg840(volatile uint8_t *bar,unsigned offset) {
    return *(volatile uint32_t *)(bar+offset);
}
static int identity840(volatile uint8_t *b) {
    return reg840(b,0x5c)==0x4a505399u && reg840(b,0x1c0)==0x3247504au &&
        reg840(b,0x1c4)==0x00010000u && reg840(b,0x1c8)==31u &&
        (reg840(b,0x1d0)>=1u && reg840(b,0x1d0)<=100u) && reg840(b,0x1ec)==1u && reg840(b,0x1f0)==1u;
}
static int number840(const char *s,uint32_t *n) {
    char *end=NULL;errno=0;unsigned long v=strtoul(s,&end,10);
    if(errno || !*s || !end || *end || v>UINT32_MAX)return 0;
    *n=(uint32_t)v;return 1;
}
static double monotonic840(void) {
    struct timespec t;
    if(clock_gettime(CLOCK_MONOTONIC,&t))return -1;
    return (double)t.tv_sec+(double)t.tv_nsec/1e9;
}
#include "wire_writer1299.h"

static int command840(char wanted) {
    struct pollfd p={.fd=STDIN_FILENO,.events=POLLIN};
    int r;do{r=poll(&p,1,10000);}while(r<0 && errno==EINTR);
    char c=0;return r>0 && read(STDIN_FILENO,&c,1)==1 && c==wanted;
}
struct fanout1332 {struct record_writer1326 *record,*video;};
static int fanout_enqueue1332(void *context,const struct jpeg_slot755 *header,const uint8_t *data) {
    struct fanout1332 *f=context;
    if(record_enqueue1326(f->record,header,data))return -1;
    return record_enqueue1326(f->video,header,data);
}
int main(int argc,char **argv) {
    int pressure_reported=0;
    int av_live=argc==11 && !strcmp(argv[1],"--stream-av-dma");
    int av_replay=argc==7 && !strcmp(argv[1],"--replay-av");
    int record_live=av_live || (argc==10 && !strcmp(argv[1],"--stream-rec-dma"));
    int record_replay=av_replay || (argc==6 && !strcmp(argv[1],"--replay-rec"));
    int stream=record_live || ((argc==8 || argc==9) && !strcmp(argv[1],"--stream-dma"));
    int live=stream || ((argc==8 || argc==9) && !strcmp(argv[1],"--dma"));
    if(!live && !record_replay && !(argc==5 && !strcmp(argv[1],"--replay")))return 2;
    uint32_t generation=0,target=0,expected_denied=0;
    if(live && argc>=9 && !number840(argv[8],&expected_denied))return 2;
    if(!number840(argv[4],&generation) || (live && (!number840(argv[5],&target) || target<2 || target>(stream?432000u:16000u))))return 2;
    struct publisher755 p={.shared=-1,.mapping=MAP_FAILED,.generation=generation};
    int raw=-1,barfd=-1,failure=0,stopped=0,quiescing=0,target_reported=0,early_stop=0;
    struct wire_writer1299 writer={0};
    struct record_writer1326 recorder={0},video={0};
    struct fanout1332 fanout={.record=&recorder,.video=&video};
    double quiesce_started=0;FILE *input=NULL,*wire=NULL;
    uint8_t *bar=MAP_FAILED;void *aligned=NULL;struct stat st;
    double started=monotonic840(),first=0,last=0;
    if(started<0){failure=errno;goto cleanup;}
    if(live) {
        barfd=open(argv[6],O_RDONLY|O_SYNC|O_NOFOLLOW);
        if(barfd<0 || fstat(barfd,&st) || !S_ISREG(st.st_mode) || st.st_size<4096){failure=EINVAL;goto cleanup;}
        bar=mmap(NULL,4096,PROT_READ,MAP_SHARED,barfd,0);
        if(bar==MAP_FAILED){failure=errno;goto cleanup;}
        if(!identity840(bar) || reg840(bar,0x60) || reg840(bar,0xa4)!=1 ||
           reg840(bar,0x90) || reg840(bar,0x1f4) || (reg840(bar,0x1cc)&7u)!=1 ||
           !reg840(bar,0x104) || !reg840(bar,0x108) ||
           reg840(bar,0x1d4) || reg840(bar,0x1d8) || reg840(bar,0x1dc) ||
           reg840(bar,0x1e0) || reg840(bar,0x1e4)!=expected_denied){failure=EPROTO;goto cleanup;}
        if(lstat(argv[2],&st) || !S_ISCHR(st.st_mode)){failure=ENODEV;goto cleanup;}
        raw=open(argv[2],O_RDONLY|O_TRUNC|O_NOFOLLOW);
        if(raw<0){failure=errno;goto cleanup;}
        if(fstat(raw,&st) || !S_ISCHR(st.st_mode)){failure=ENODEV;goto cleanup;}
        int fd;
        if(stream) {
            if(lstat(argv[7],&st) || !S_ISFIFO(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&0777)!=0600){failure=EINVAL;goto cleanup;}
            double connect_deadline=monotonic840()+30;
            do {
                fd=open(argv[7],O_WRONLY|O_NONBLOCK|O_NOFOLLOW);
                if(fd>=0 || errno!=ENXIO)break;
                struct timespec pause={.tv_sec=0,.tv_nsec=10000000};nanosleep(&pause,NULL);
            }while(monotonic840()<connect_deadline);
        }else fd=open(argv[7],O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        if(fd<0){failure=errno;goto cleanup;}
        wire=fdopen(fd,"wb");if(!wire){close(fd);failure=errno;goto cleanup;}
        if(wire_start1299(&writer,wire)){failure=errno;goto cleanup;}
    }else {
        int fd=open(argv[2],O_RDONLY|O_NOFOLLOW);
        if(fd<0){failure=errno;goto cleanup;}
        if(fstat(fd,&st) || !S_ISREG(st.st_mode)){close(fd);failure=EINVAL;goto cleanup;}
        input=fdopen(fd,"rb");if(!input){close(fd);failure=errno;goto cleanup;}
    }
    p.shared=open(argv[3],O_RDWR|O_NOFOLLOW);
    if(p.shared<0 || fstat(p.shared,&st) || !S_ISREG(st.st_mode) || st.st_uid!=getuid() ||
       (st.st_mode&0777)!=0600 || st.st_size!=(off_t)SHARED_BYTES755){failure=EINVAL;goto cleanup;}
    p.mapping=mmap(NULL,SHARED_BYTES755,PROT_READ|PROT_WRITE,MAP_SHARED,p.shared,0);
    p.receiver.payload=malloc(CAPACITY);
    if(p.mapping==MAP_FAILED || !p.receiver.payload || posix_memalign(&aligned,4096,8192)){failure=ENOMEM;goto cleanup;}
    if(record_live || record_replay){
        if(record_start1326(&recorder,argv[record_live?9:5])){failure=errno;goto cleanup;}
        if(av_live || av_replay) {
            if(record_start1326(&video,argv[av_live?10:6])){failure=errno;goto cleanup;}
            p.record=fanout_enqueue1332;p.record_context=&fanout;
        }else {p.record=record_enqueue1326;p.record_context=&recorder;}
    }
    if(live){puts("READY");fflush(stdout);if(!command840('S')){failure=ECANCELED;goto cleanup;}}
    for(;;) {
        uint8_t prefix[4],packet[4144];uint32_t size;
        if(live) {
            if(!identity840(bar) || !(reg840(bar,0x1cc)&1u) ||
               reg840(bar,0x1e4)!=expected_denied){failure=EPROTO;break;}
            /* Keep the DMA descriptor alive after the first hardware fault.
             * The controller stops capture before authorizing a bounded drain.
             * EPROTO remains sticky: cleanup cannot turn this into a pass. */
            if(!stopped && reg840(bar,0x1e0)) {
                failure=EPROTO;puts("FAULT");fflush(stdout);
                if(!command840('D') || reg840(bar,0x60)){failure=ECANCELED;break;}
                stopped=1;
            }
            /* Ask the controller for a frame-boundary stop while headroom
             * remains. Never discard bytes or silently change JPEG quality. */
            if(!quiescing && !stopped && !pressure_reported) {
                pthread_mutex_lock(&writer.lock);
                size_t queued=writer.count;
                pthread_mutex_unlock(&writer.lock);
                if(queued>=WIRE_SLOTS1299*3u/4u) {
                    pressure_reported=1;puts("PRESSURE wire");fflush(stdout);
                }
            }
            /* Consumer failure may request the same frame-boundary drain
             * before TARGET. Only an armed BAR request plus Q authorizes it. */
            if(!quiescing && !stopped) {
                struct pollfd control={.fd=STDIN_FILENO,.events=POLLIN};
                int ready;do{ready=poll(&control,1,0);}while(ready<0 && errno==EINTR);
                if(ready<0){failure=errno;break;}
                if(ready>0) {
                    char command=0;
                    if(read(STDIN_FILENO,&command,1)!=1 || command!='Q' ||
                       !reg840(bar,0x60) || !(reg840(bar,0x1f4)&1u)) {
                        failure=ECANCELED;break;
                    }
                    early_stop=1;quiescing=1;quiesce_started=monotonic840();
                    puts("EARLY_STOP");fflush(stdout);
                }
            }
            if(quiescing && !stopped && monotonic840()-quiesce_started>10){failure=ETIMEDOUT;break;}
            if(quiescing && !stopped && !(reg840(bar,0x1cc)&2u) && !p.receiver.active &&
               p.committed==reg840(bar,0x1d8) && p.aborted==reg840(bar,0x1dc) &&
               p.committed+p.aborted==reg840(bar,0x1d4)) {
                uint32_t stop_state=reg840(bar,0x1f4);
                if(!(stop_state&1u)){failure=EPROTO;break;}
                if((stop_state&7u)!=7u){
                    struct timespec pause={.tv_sec=0,.tv_nsec=1000000};nanosleep(&pause,NULL);continue;
                }
                puts("QUIESCED");fflush(stdout);
                if(!command840('D') || reg840(bar,0x60)){failure=ECANCELED;break;}
                stopped=1;
            }
            if(!stopped && (reg840(bar,0x1cc)&4u)){failure=EPROTO;break;}
            if(stopped && !(reg840(bar,0x1cc)&2u) && !p.receiver.active &&
               p.committed==reg840(bar,0x1d8) && p.aborted==reg840(bar,0x1dc) &&
               p.committed+p.aborted==reg840(bar,0x1d4))break;
            if(monotonic840()-started>(stream?7500:900) || (stream ? p.wire_bytes+4*p.packets>70ull*1024*1024*1024 : p.wire_bytes>2ull*1024*1024*1024)){failure=EOVERFLOW;break;}
            ssize_t got=read(raw,aligned,8192);
            if(got<0){failure=errno;break;}
            if(got<64 || got>(ssize_t)sizeof(packet) || got%16){failure=EPROTO;break;}
            size=(uint32_t)got;memcpy(packet,aligned,size);
            for(unsigned i=0;i<4;i++)prefix[i]=(uint8_t)(size>>(8*i));
            if(wire_enqueue1299(&writer,prefix,packet,size)){failure=errno;break;}
            if(u16(packet+12)!=1920 || u16(packet+14)!=1080){failure=EPROTO;break;}
        }else {
            size_t got=fread(prefix,1,4,input);
            if(!got && !ferror(input))break;
            if(got!=4){failure=EPROTO;break;}
            size=u32(prefix);
            if(size<64 || size>sizeof(packet) || fread(packet,1,size,input)!=size){failure=EPROTO;break;}
        }
        int event=push755(&p,packet,size);
        if(event<0){failure=errno;break;}
        if(event==1 || event==3){double t=monotonic840();if(!first)first=t;last=t;}
        if(live && !stopped && !quiescing && !target_reported && p.committed>=target) {
            puts("TARGET");fflush(stdout);
            if(!command840('Q') || !reg840(bar,0x60) || !(reg840(bar,0x1f4)&1u)){failure=ECANCELED;break;}
            target_reported=1;quiescing=1;quiesce_started=monotonic840();
        }
    }
    if(receiver735_finish(&p.receiver))failure=failure?failure:EPROTO;
    if(live && stopped && !(reg840(bar,0x1cc)&2u) && !p.receiver.active &&
       p.committed==reg840(bar,0x1d8) && p.aborted==reg840(bar,0x1dc) &&
       p.committed+p.aborted==reg840(bar,0x1d4)){puts("DRAINED");fflush(stdout);if(!command840('T'))failure=ECANCELED;}
cleanup:
    if(record_finish1326(&recorder))failure=failure?failure:errno;
    if(record_finish1326(&video))failure=failure?failure:errno;
    if(wire_finish1299(&writer))failure=failure?failure:errno;
    if(wire && fclose(wire))failure=failure?failure:EIO;
    fprintf(stderr,"RECORD1326 enqueued=%llu written=%llu peak_bytes=%zu limit_bytes=%u\n",(unsigned long long)recorder.enqueued,(unsigned long long)recorder.written,recorder.peak,RECORD_LIMIT1326);
    fprintf(stderr,"VIDEO1332 enqueued=%llu written=%llu peak_bytes=%zu limit_bytes=%u\n",(unsigned long long)video.enqueued,(unsigned long long)video.written,video.peak,RECORD_LIMIT1326);
    printf("{\"committed\":%u,\"aborted\":%u,\"published\":%u,\"slot_busy_drops\":%u,\"packets\":%llu,"
           "\"wire_bytes\":%llu,\"used_slot_mask\":%u,\"first_completed\":%.9f,\"last_completed\":%.9f,\"early_stop\":%d,\"wire_enqueued\":%llu,\"wire_written\":%llu,\"wire_queue_peak_packets\":%zu,\"wire_queue_capacity_packets\":%zu,\"errno\":%d}\n",
           p.committed,p.aborted,p.published,p.dropped,(unsigned long long)p.packets,
           (unsigned long long)p.wire_bytes,p.used,first,last,early_stop,(unsigned long long)writer.enqueued,(unsigned long long)writer.written,writer.peak,(size_t)WIRE_SLOTS1299,failure);
    free(p.receiver.payload);free(aligned);
    if(p.mapping!=MAP_FAILED)munmap(p.mapping,SHARED_BYTES755);
    if(bar!=MAP_FAILED)munmap(bar,4096);
    if(raw>=0)close(raw);
    if(barfd>=0)close(barfd);
    if(p.shared>=0)close(p.shared);
    if(input)fclose(input);
    return failure || (live && p.committed<target && !early_stop)?1:0;
}
