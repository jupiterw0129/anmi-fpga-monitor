#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "jpg2_884_guard.h"
int main(void) {
    unsigned int good[20]={0x4a505399,0x3247504a,0x10000,31,50,1,1,0,1,0,1,486,1097,0,0,0,0,2,48,0};
    unsigned int v[20];
    assert(jpg2_884_ready(good,2));
    assert(!jpg2_884_ready(good,0));
    for(unsigned int i=0;i<20;i++) {
        memcpy(v,good,sizeof v);v[i]=0xffffffffU;
        assert(!jpg2_884_ready(v,2));
    }
    memcpy(v,good,sizeof v);v[0]=0x4a504727;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[10]=3;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[10]=5;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[11]=480;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[12]=1079;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[17]=3;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a504884;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a504913;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a504939;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a504951;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a504976;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[3]=7;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[19]=1;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[19]=7;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a505018;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[0]=0x4a505134;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[4]=1;assert(jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[4]=100;assert(jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[4]=0;assert(!jpg2_884_ready(v,2));
    memcpy(v,good,sizeof v);v[4]=101;assert(!jpg2_884_ready(v,2));
    puts("GUARD1403_37_IDENTITY_BUSY_GEOMETRY_FAULT_DENIED_REJECTIONS_PASS");
    return 0;
}
