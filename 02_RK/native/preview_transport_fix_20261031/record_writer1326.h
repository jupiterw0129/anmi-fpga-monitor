/* Reliable recorder delivery: finite byte queue, FIFO with write deadline.
 * The queue accounts for the worker's in-flight item until it is freed. */
#include <pthread.h>
#include <poll.h>
#include <signal.h>
#define RECORD_LIMIT1326 (64u*1024u*1024u)
#define RECORD_ITEMS1326 1024u
struct record_item1326 {struct record_item1326 *next;size_t size;uint8_t data[];};
struct record_writer1326 {
    pthread_mutex_t lock;pthread_cond_t ready;pthread_t thread;
    struct record_item1326 *head,*tail;size_t bytes,peak,count;
    uint64_t enqueued,written;int fd,started,stop,error;
};
static double record_time1326(void) {
    struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))return -1;
    return (double)t.tv_sec+t.tv_nsec/1e9;
}
static int record_write1326(int fd,const uint8_t *data,size_t size) {
    double deadline=record_time1326()+2;
    while(size) {
        int ms=(int)((deadline-record_time1326())*1000);
        if(ms<=0){errno=ETIMEDOUT;return -1;}
        struct pollfd p={.fd=fd,.events=POLLOUT};int r=poll(&p,1,ms);
        if(r<0 && errno==EINTR)continue;
        if(r<=0){if(!r)errno=ETIMEDOUT;return -1;}
        if(p.revents&(POLLERR|POLLHUP|POLLNVAL)){errno=EPIPE;return -1;}
        ssize_t n=write(fd,data,size);
        if(n<0 && (errno==EINTR || errno==EAGAIN))continue;
        if(n<=0){if(!n)errno=EIO;return -1;}
        data+=n;size-=(size_t)n;
    }
    return 0;
}
static void *record_run1326(void *context) {
    struct record_writer1326 *w=context;
    for(;;) {
        pthread_mutex_lock(&w->lock);
        while(!w->head && !w->stop)pthread_cond_wait(&w->ready,&w->lock);
        struct record_item1326 *item=w->head;
        if(!item){pthread_mutex_unlock(&w->lock);break;}
        w->head=item->next;if(!w->head)w->tail=NULL;
        pthread_mutex_unlock(&w->lock);
        int e=record_write1326(w->fd,item->data,item->size)?errno:0;
        pthread_mutex_lock(&w->lock);
        w->bytes-=sizeof(*item)+item->size;w->count--;
        if(e)w->error=e;else w->written++;
        pthread_mutex_unlock(&w->lock);free(item);
        if(e)break;
    }
    return NULL;
}
static int record_start1326(struct record_writer1326 *w,const char *path) {
    struct stat s;
    if(lstat(path,&s) || !S_ISFIFO(s.st_mode) || s.st_uid!=getuid() || (s.st_mode&0777)!=0600){errno=EINVAL;return -1;}
    w->fd=open(path,O_WRONLY|O_NONBLOCK|O_NOFOLLOW);
    if(w->fd<0)return -1;
    signal(SIGPIPE,SIG_IGN);
    int e=pthread_mutex_init(&w->lock,NULL);
    if(e){close(w->fd);errno=e;return -1;}
    e=pthread_cond_init(&w->ready,NULL);
    if(e){pthread_mutex_destroy(&w->lock);close(w->fd);errno=e;return -1;}
    e=pthread_create(&w->thread,NULL,record_run1326,w);
    if(e){pthread_cond_destroy(&w->ready);pthread_mutex_destroy(&w->lock);close(w->fd);errno=e;return -1;}
    w->started=1;return 0;
}
static int record_enqueue1326(void *context,const struct jpeg_slot755 *header,const uint8_t *data) {
    struct record_writer1326 *w=context;size_t size=64u+header->length;
    pthread_mutex_lock(&w->lock);int e=w->error;
    if(!e && (w->stop || !w->started))e=ECANCELED;
    if(!e && (size+sizeof(struct record_item1326)>RECORD_LIMIT1326-w->bytes || w->count>=RECORD_ITEMS1326))e=ENOBUFS;
    struct record_item1326 *item=NULL;
    if(!e){item=malloc(sizeof(*item)+size);if(!item)e=ENOMEM;}
    if(!e) {
        item->next=NULL;item->size=size;memcpy(item->data,header,64);memcpy(item->data+64,data,header->length);
        if(w->tail)w->tail->next=item;else w->head=item;w->tail=item;
        w->bytes+=sizeof(*item)+size;w->count++;w->enqueued++;
        if(w->bytes>w->peak)w->peak=w->bytes;
        pthread_cond_signal(&w->ready);
    }
    pthread_mutex_unlock(&w->lock);if(e){errno=e;return -1;}return 0;
}
static int record_finish1326(struct record_writer1326 *w) {
    if(!w->started)return 0;
    pthread_mutex_lock(&w->lock);w->stop=1;pthread_cond_signal(&w->ready);pthread_mutex_unlock(&w->lock);
    int e=pthread_join(w->thread,NULL);if(!e)e=w->error;
    if(!e && w->enqueued!=w->written)e=EIO;
    while(w->head){struct record_item1326 *item=w->head;w->head=item->next;free(item);}
    close(w->fd);pthread_cond_destroy(&w->ready);pthread_mutex_destroy(&w->lock);w->started=0;
    if(e){errno=e;return -1;}return 0;
}
