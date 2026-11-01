#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>
#include <drm_mode.h>

struct overlay1190 {int fd;uint32_t handle,fb,pitch;uint64_t size;void *map;int shown;};

int overlay1190_close(struct overlay1190 *p) {
    if(!p)return 0;
    int error=0;
    if(p->shown && drmModeSetPlane(p->fd,148,72,0,0,0,0,0,0,0,0,0,0))error=errno;
    if(p->fb && drmModeRmFB(p->fd,p->fb) && !error)error=errno;
    if(p->map!=MAP_FAILED && p->map)munmap(p->map,p->size);
    if(p->handle){struct drm_mode_destroy_dumb d={.handle=p->handle};if(ioctl(p->fd,DRM_IOCTL_MODE_DESTROY_DUMB,&d)&&!error)error=errno;}
    if(p->fd>=0)close(p->fd);
    free(p);return error;
}

struct overlay1190 *overlay1190_open(void) {
    struct overlay1190 *p=calloc(1,sizeof(*p));if(!p)return NULL;
    p->fd=-1;p->map=MAP_FAILED;
    p->fd=open("/dev/dri/card0",O_RDWR|O_CLOEXEC);if(p->fd<0)goto failed;
    if(drmSetClientCap(p->fd,DRM_CLIENT_CAP_UNIVERSAL_PLANES,1))goto failed;
    drmModeRes *res=drmModeGetResources(p->fd);
    if(!res)goto failed;
    int index=-1;for(int i=0;i<res->count_crtcs;i++)if(res->crtcs[i]==72)index=i;
    drmModeFreeResources(res);
    drmModePlane *plane=drmModeGetPlane(p->fd,148);
    if(!plane)goto failed;
    int valid=index>=0 && index<32 && (plane->possible_crtcs&(1u<<index)) && !plane->crtc_id && !plane->fb_id;
    int argb=0;for(uint32_t i=0;i<plane->count_formats;i++)if(plane->formats[i]==DRM_FORMAT_ARGB8888)argb=1;
    drmModeFreePlane(plane);
    if(!valid || !argb){errno=EBUSY;goto failed;}
    drmModeCrtc *crtc=drmModeGetCrtc(p->fd,72);
    if(!crtc)goto failed;
    valid=crtc->mode_valid && crtc->width==1920 && crtc->height==1080;
    drmModeFreeCrtc(crtc);if(!valid){errno=EINVAL;goto failed;}
    struct drm_mode_create_dumb d={.width=960,.height=540,.bpp=32};
    if(ioctl(p->fd,DRM_IOCTL_MODE_CREATE_DUMB,&d))goto failed;
    p->handle=d.handle;p->pitch=d.pitch;p->size=d.size;
    uint32_t handles[4]={d.handle,0,0,0},pitches[4]={d.pitch,0,0,0},offsets[4]={0};
    if(drmModeAddFB2(p->fd,960,540,DRM_FORMAT_ARGB8888,handles,pitches,offsets,&p->fb,0))goto failed;
    struct drm_mode_map_dumb m={.handle=d.handle};
    if(ioctl(p->fd,DRM_IOCTL_MODE_MAP_DUMB,&m))goto failed;
    p->map=mmap(NULL,p->size,PROT_READ|PROT_WRITE,MAP_SHARED,p->fd,m.offset);
    if(p->map==MAP_FAILED)goto failed;
    memset(p->map,0,p->size);
    if(drmModeSetPlane(p->fd,148,72,p->fb,0,0,0,1920,1080,0,0,960u<<16,540u<<16))goto failed;
    p->shown=1;return p;
failed:;
    int saved=errno;overlay1190_close(p);errno=saved;return NULL;
}

int overlay1190_update(struct overlay1190 *p,const void *pixels,uint32_t bytes) {
    if(!p || !p->shown || !pixels || bytes!=960u*540*4)return EINVAL;
    for(unsigned y=0;y<540;y++)memcpy((uint8_t *)p->map+y*p->pitch,(const uint8_t *)pixels+y*960*4,960*4);
    return 0;
}

uint32_t overlay1190_fb(struct overlay1190 *p){return p?p->fb:0;}
