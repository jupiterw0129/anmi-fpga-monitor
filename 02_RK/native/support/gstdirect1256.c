#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE
#include <gst/gst.h>
#include <gst/base/gstbasesink.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#define CHUNK (1024u*1024u)
typedef struct {GstBaseSink parent;gint fd;guint64 reserve,cursor,begin,extent,writes,max_ns;guint used;guint8 *pending,*aligned;gboolean failed;} Direct1256;
typedef struct {GstBaseSinkClass parent;} Direct1256Class;
G_DEFINE_TYPE(Direct1256,direct1256,GST_TYPE_BASE_SINK)
enum {P_NONE,P_FD,P_RESERVE,P_EXTENT,P_WRITES,P_MAX_NS,P_FAILED};
static gboolean flush1256(Direct1256 *s) {
    if(!s->used)return TRUE;
    guint64 low=s->begin&~511ull,end=s->begin+s->used,high=(end+511)&~511ull;
    gsize size=high-low;
    if(s->fd<0 || high>s->reserve){errno=EFBIG;goto fail;}
    if(low!=s->begin || high!=end) {
        struct stat st;
        if(fstat(s->fd,&st) || !S_ISREG(st.st_mode))goto fail;
        memset(s->aligned,0,size);
        ssize_t n;do{n=pread(s->fd,s->aligned,size,low);}while(n<0 && errno==EINTR);
        /* A new file may end inside the aligned batch. Only its actual EOF
         * permits a short read; preserve existing bytes and zero new padding. */
        guint64 available=(guint64)st.st_size>low?(guint64)st.st_size-low:0;
        gsize expected=MIN((guint64)size,available);
        if(n<0 || (gsize)n!=expected){if(n>=0)errno=EIO;goto fail;}
    }
    memcpy(s->aligned+s->begin-low,s->pending,s->used);
    GstClockTime started=gst_util_get_timestamp();
    ssize_t n;do{n=pwrite(s->fd,s->aligned,size,low);}while(n<0 && errno==EINTR);
    guint64 elapsed=gst_util_get_timestamp()-started;s->max_ns=MAX(s->max_ns,elapsed);s->writes++;
    if(n!=(ssize_t)size){if(n>=0)errno=EIO;goto fail;}
    s->used=0;s->begin=end;return TRUE;
fail:
    s->failed=TRUE;GST_ELEMENT_ERROR(s,RESOURCE,WRITE,("Aligned recording write failed"),("%s",g_strerror(errno)));return FALSE;
}
static GstFlowReturn render1256(GstBaseSink *base,GstBuffer *buffer) {
    Direct1256 *s=(Direct1256*)base;GstMapInfo map;
    if(s->failed || !gst_buffer_map(buffer,&map,GST_MAP_READ))return GST_FLOW_ERROR;
    if(s->cursor>s->reserve || map.size>s->reserve-s->cursor) {
        gst_buffer_unmap(buffer,&map);s->failed=TRUE;
        GST_ELEMENT_ERROR(s,RESOURCE,NO_SPACE_LEFT,("Mux output exceeds finite recording reserve"),(NULL));return GST_FLOW_ERROR;
    }
    gsize offset=0;
    while(offset<map.size) {
        if(!s->used)s->begin=s->cursor;
        gsize n=MIN(CHUNK-s->used,map.size-offset);
        memcpy(s->pending+s->used,map.data+offset,n);s->used+=n;offset+=n;s->cursor+=n;
        s->extent=MAX(s->extent,s->cursor);
        if(s->used==CHUNK && !flush1256(s)){gst_buffer_unmap(buffer,&map);return GST_FLOW_ERROR;}
    }
    gst_buffer_unmap(buffer,&map);return GST_FLOW_OK;
}
static gboolean event1256(GstBaseSink *base,GstEvent *event) {
    Direct1256 *s=(Direct1256*)base;
    if(GST_EVENT_TYPE(event)==GST_EVENT_SEGMENT) {
        const GstSegment *seg;gst_event_parse_segment(event,&seg);
        if(seg->format!=GST_FORMAT_BYTES || seg->start>s->reserve || !flush1256(s)) {
            s->failed=TRUE;gst_event_unref(event);return FALSE;
        }
        s->cursor=s->begin=seg->start;
    }else if(GST_EVENT_TYPE(event)==GST_EVENT_EOS && !flush1256(s)){gst_event_unref(event);return FALSE;}
    return GST_BASE_SINK_CLASS(direct1256_parent_class)->event(base,event);
}
static gboolean query1256(GstBaseSink *base,GstQuery *q) {
    Direct1256 *s=(Direct1256*)base;GstFormat format;
    if(GST_QUERY_TYPE(q)==GST_QUERY_SEEKING) {
        gst_query_parse_seeking(q,&format,NULL,NULL,NULL);
        if(format==GST_FORMAT_BYTES){gst_query_set_seeking(q,format,TRUE,0,s->reserve);return TRUE;}
    }else if(GST_QUERY_TYPE(q)==GST_QUERY_POSITION) {
        gst_query_parse_position(q,&format,NULL);
        if(format==GST_FORMAT_BYTES){gst_query_set_position(q,format,s->cursor);return TRUE;}
    }
    return GST_BASE_SINK_CLASS(direct1256_parent_class)->query(base,q);
}
static gboolean start1256(GstBaseSink *base) {
    Direct1256 *s=(Direct1256*)base;
    return s->fd>=0 && s->reserve>=CHUNK && s->pending && s->aligned && !s->failed;
}
static void set1256(GObject *object,guint id,const GValue *v,GParamSpec *spec) {
    Direct1256 *s=(Direct1256*)object;
    if(id==P_FD)s->fd=g_value_get_int(v);
    else if(id==P_RESERVE)s->reserve=g_value_get_uint64(v);
    else G_OBJECT_WARN_INVALID_PROPERTY_ID(object,id,spec);
}
static void get1256(GObject *object,guint id,GValue *v,GParamSpec *spec) {
    Direct1256 *s=(Direct1256*)object;
    switch(id) {
        case P_FD:g_value_set_int(v,s->fd);break;
        case P_RESERVE:g_value_set_uint64(v,s->reserve);break;
        case P_EXTENT:g_value_set_uint64(v,s->extent);break;
        case P_WRITES:g_value_set_uint64(v,s->writes);break;
        case P_MAX_NS:g_value_set_uint64(v,s->max_ns);break;
        case P_FAILED:g_value_set_boolean(v,s->failed);break;
        default:G_OBJECT_WARN_INVALID_PROPERTY_ID(object,id,spec);
    }
}
static void finalize1256(GObject *object) {
    Direct1256 *s=(Direct1256*)object;g_free(s->pending);free(s->aligned);
    G_OBJECT_CLASS(direct1256_parent_class)->finalize(object);
}
static void direct1256_class_init(Direct1256Class *klass) {
    GObjectClass *g=G_OBJECT_CLASS(klass);GstElementClass *e=GST_ELEMENT_CLASS(klass);GstBaseSinkClass *b=GST_BASE_SINK_CLASS(klass);
    g->set_property=set1256;g->get_property=get1256;g->finalize=finalize1256;
    g_object_class_install_property(g,P_FD,g_param_spec_int("fd","fd","Caller-owned direct file descriptor",-1,G_MAXINT,-1,G_PARAM_READWRITE));
    g_object_class_install_property(g,P_RESERVE,g_param_spec_uint64("reserve","reserve","Finite allocated bytes",0,G_MAXUINT64,0,G_PARAM_READWRITE));
    g_object_class_install_property(g,P_EXTENT,g_param_spec_uint64("extent","extent","Logical high water bytes",0,G_MAXUINT64,0,G_PARAM_READABLE));
    g_object_class_install_property(g,P_WRITES,g_param_spec_uint64("writes","writes","Aligned write count",0,G_MAXUINT64,0,G_PARAM_READABLE));
    g_object_class_install_property(g,P_MAX_NS,g_param_spec_uint64("max-write-ns","max-write-ns","Maximum direct write duration",0,G_MAXUINT64,0,G_PARAM_READABLE));
    g_object_class_install_property(g,P_FAILED,g_param_spec_boolean("failed","failed","Sticky write failure",FALSE,G_PARAM_READABLE));
    gst_element_class_set_static_metadata(e,"Finite aligned recorder","Sink/File","Bounded direct writer with byte seeks","FPGA");
    GstCaps *caps=gst_caps_new_any();
    gst_element_class_add_pad_template(e,gst_pad_template_new("sink",GST_PAD_SINK,GST_PAD_ALWAYS,caps));gst_caps_unref(caps);
    b->render=render1256;b->event=event1256;b->query=query1256;b->start=start1256;
}
static void direct1256_init(Direct1256 *s) {
    s->fd=-1;s->pending=g_malloc(CHUNK);
    if(posix_memalign((void**)&s->aligned,4096,CHUNK+4096))s->aligned=NULL;
    gst_base_sink_set_sync(GST_BASE_SINK(s),FALSE);gst_base_sink_set_async_enabled(GST_BASE_SINK(s),FALSE);
}
static gboolean plugin_init(GstPlugin *plugin){return gst_element_register(plugin,"direct1256sink",GST_RANK_NONE,direct1256_get_type());}
#ifndef PACKAGE
#define PACKAGE "fpga-direct1256"
#endif
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR,GST_VERSION_MINOR,direct1256,"Finite aligned recording",plugin_init,"1.0","LGPL","FPGA","local")
