#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/stat.h>
#include <pthread.h>
#include <time.h>
static double monotonic840(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
#include "wire_writer1299.h"
static int read_all(int fd,uint8_t *p,size_t n){while(n){ssize_t k=read(fd,p,n);if(k<=0)return -1;p+=k;n-=k;}return 0;}
struct consumer {int fd,error;unsigned packets;};
static void *consume(void *v){struct consumer *c=v;uint8_t b[4148];
 for(unsigned i=0;i<c->packets;i++){
  if(read_all(c->fd,b,sizeof b)){c->error=1;break;}
  if(b[0]!=0x30||b[1]!=0x10||b[2]||b[3]){c->error=2;break;}
  for(size_t j=4;j<sizeof b;j++)if(b[j]!=(uint8_t)(i+j-4)){c->error=3;break;}
  if(c->error)break;
 }
 close(c->fd);return NULL;
}
int main(void){
 int fds[2];if(pipe(fds))return 1;fcntl(fds[1],F_SETFL,O_NONBLOCK);
 FILE *f=fdopen(fds[1],"wb");struct wire_writer1299 w={0};
 if(wire_start1299(&w,f))return 2;
 struct consumer c={.fd=fds[0],.packets=12000};pthread_t t;pthread_create(&t,NULL,consume,&c);
 uint8_t prefix[4]={0x30,0x10,0,0},packet[4144];
 for(unsigned i=0;i<c.packets;i++){
  for(size_t j=0;j<sizeof packet;j++)packet[j]=(uint8_t)(i+j);
  while(1){pthread_mutex_lock(&w.lock);size_t count=w.count;pthread_mutex_unlock(&w.lock);
   if(count<WIRE_SLOTS1299/2)break;
   struct timespec pause={.tv_sec=0,.tv_nsec=1000000};nanosleep(&pause,NULL);
  }
  if(wire_enqueue1299(&w,prefix,packet,sizeof packet))return 3;
 }
 if(wire_finish1299(&w))return 4;fclose(f);pthread_join(t,NULL);if(c.error)return 5;
 if(w.enqueued!=c.packets||w.written!=c.packets)return 6;
 printf("ORDER_BYTES_PASS packets=%u bytes=%u capacity=%u\n",c.packets,c.packets*4148u,(unsigned)WIRE_SLOTS1299);
 if(pipe(fds))return 7;fcntl(fds[1],F_SETFL,O_NONBLOCK);f=fdopen(fds[1],"wb");memset(&w,0,sizeof w);
 if(wire_start1299(&w,f))return 8;close(fds[0]);
 if(wire_enqueue1299(&w,prefix,packet,sizeof packet))return 9;
 if(!wire_finish1299(&w))return 10;fclose(f);puts("BROKEN_PIPE_BOUNDED_PASS");return 0;
}
