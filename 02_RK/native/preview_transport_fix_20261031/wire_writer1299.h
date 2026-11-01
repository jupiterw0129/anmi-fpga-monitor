/* Finite nonblocking DMA-side enqueue; one worker preserves exact wire order. */
#include <pthread.h>
#include <signal.h>
struct wire_item1299 {size_t size;uint8_t data[4148];};
#define WIRE_SLOTS1299 ((16u*1024u*1024u)/sizeof(struct wire_item1299))
struct wire_writer1299 {
    pthread_mutex_t lock;pthread_cond_t ready;pthread_t thread;
    struct wire_item1299 *items;FILE *file;size_t head,count,peak;
    uint64_t enqueued,written;int stop,error,started,stream;
};
static int wire_pipe1299(int fd,const uint8_t *data,size_t size) {
    double deadline=monotonic840()+2.0;
    while(size) {
        int remaining=(int)((deadline-monotonic840())*1000);
        if(remaining<=0){errno=ETIMEDOUT;return -1;}
        struct pollfd p={.fd=fd,.events=POLLOUT};
        int ready=poll(&p,1,remaining);
        if(ready<0 && errno==EINTR)continue;
        if(ready<=0){if(!ready)errno=ETIMEDOUT;return -1;}
        if(p.revents&(POLLERR|POLLHUP|POLLNVAL)){errno=EPIPE;return -1;}
        ssize_t written=write(fd,data,size);
        if(written<0 && (errno==EAGAIN || errno==EINTR))continue;
        if(written<=0){if(!written)errno=EIO;return -1;}
        data+=written;size-=(size_t)written;
    }
    return 0;
}
static void *wire_run1299(void *opaque) {
    struct wire_writer1299 *w=opaque;
    uint8_t batch[64u*4148u];
    for(;;) {
        size_t size=0,items=0;
        pthread_mutex_lock(&w->lock);
        while(!w->count && !w->stop)pthread_cond_wait(&w->ready,&w->lock);
        if(!w->count && w->stop){pthread_mutex_unlock(&w->lock);break;}
        while(w->count && items<64u) {
            struct wire_item1299 *item=&w->items[w->head];
            memcpy(batch+size,item->data,item->size);size+=item->size;items++;
            w->head=(w->head+1)%WIRE_SLOTS1299;w->count--;
        }
        pthread_mutex_unlock(&w->lock);
        if(w->stream ? wire_pipe1299(fileno(w->file),batch,size) :
           (fwrite(batch,1,size,w->file)!=size || ferror(w->file))) {
            int saved=errno?errno:EIO;pthread_mutex_lock(&w->lock);w->error=saved;
            pthread_mutex_unlock(&w->lock);break;
        }
        w->written+=items;
    }
    return NULL;
}
static int wire_start1299(struct wire_writer1299 *w,FILE *file) {
    struct stat sink_stat;
    if(fstat(fileno(file),&sink_stat))return -1;
    w->stream=S_ISFIFO(sink_stat.st_mode);
    if(w->stream)signal(SIGPIPE,SIG_IGN);
    w->file=file;w->items=calloc(WIRE_SLOTS1299,sizeof(*w->items));
    if(!w->items){errno=ENOMEM;return -1;}
    int e=pthread_mutex_init(&w->lock,NULL);
    if(e){free(w->items);w->items=NULL;errno=e;return -1;}
    e=pthread_cond_init(&w->ready,NULL);
    if(e){pthread_mutex_destroy(&w->lock);free(w->items);w->items=NULL;errno=e;return -1;}
    e=pthread_create(&w->thread,NULL,wire_run1299,w);
    if(e){pthread_cond_destroy(&w->ready);pthread_mutex_destroy(&w->lock);free(w->items);w->items=NULL;errno=e;return -1;}
    w->started=1;return 0;
}
static int wire_enqueue1299(struct wire_writer1299 *w,const uint8_t *prefix,const uint8_t *packet,size_t size) {
    if(size>4144){errno=EOVERFLOW;return -1;}
    pthread_mutex_lock(&w->lock);
    int e=w->error;
    if(!e && w->count==WIRE_SLOTS1299)e=ENOBUFS;
    if(!e && w->stop)e=ECANCELED;
    if(!e) {
        struct wire_item1299 *item=&w->items[(w->head+w->count)%WIRE_SLOTS1299];
        item->size=size+4;memcpy(item->data,prefix,4);memcpy(item->data+4,packet,size);
        w->count++;w->enqueued++;if(w->count>w->peak)w->peak=w->count;
        pthread_cond_signal(&w->ready);
    }
    pthread_mutex_unlock(&w->lock);
    if(e){errno=e;return -1;}return 0;
}
static int wire_finish1299(struct wire_writer1299 *w) {
    if(!w->started)return 0;
    pthread_mutex_lock(&w->lock);w->stop=1;pthread_cond_signal(&w->ready);pthread_mutex_unlock(&w->lock);
    int e=pthread_join(w->thread,NULL);
    if(!e)e=w->error;
    if(!e && w->written!=w->enqueued)e=EIO;
    if(!e && (fflush(w->file) || (!w->stream && fsync(fileno(w->file)))))e=errno?errno:EIO;
    pthread_cond_destroy(&w->ready);pthread_mutex_destroy(&w->lock);
    free(w->items);w->items=NULL;w->started=0;
    if(e){errno=e;return -1;}return 0;
}
