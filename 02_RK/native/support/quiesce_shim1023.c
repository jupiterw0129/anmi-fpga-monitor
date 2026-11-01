#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
ssize_t __real_read(int fd,void *buf,size_t size);
static void putreg(unsigned offset,uint32_t value) {
    int fd=open(getenv("QUIESCE_BAR"),O_WRONLY);
    if(fd<0 || pwrite(fd,&value,4,offset)!=4)_exit(92);
    close(fd);
}
static uint32_t word(const unsigned char *p) {
    return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
ssize_t __wrap_read(int fd,void *buf,size_t size) {
    char path[64],target[64];snprintf(path,sizeof path,"/proc/self/fd/%d",fd);
    ssize_t length=readlink(path,target,sizeof(target)-1);
    if(length<0)return __real_read(fd,buf,size);
    target[length]=0;
    if(strcmp(target,"/dev/null"))return __real_read(fd,buf,size);
    static int input=-1,commits=0;
    if(input<0){input=open(getenv("QUIESCE_WIRE"),O_RDONLY);putreg(0x1d4,6);putreg(0x1cc,3);}
    uint32_t bytes=0;
    if(input<0 || __real_read(input,&bytes,4)!=4 || bytes>size){errno=EIO;return -1;}
    ssize_t got=__real_read(input,buf,bytes);
    if(got!=(ssize_t)bytes){errno=EIO;return -1;}
    if(word((unsigned char *)buf+24)==1){
        commits++;putreg(0x1d8,(uint32_t)commits);
        if(commits==3 && !strcmp(getenv("QUIESCE_CASE"),"denied_drain"))putreg(0x1e4,3);
        if(commits==6){putreg(0x1cc,1);putreg(0x1f4,!strcmp(getenv("QUIESCE_CASE"),"ready_timeout")?1:7);}
    }
    return got;
}
