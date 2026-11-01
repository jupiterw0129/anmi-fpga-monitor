/* Same pure predicate is compiled by the kernel and the userspace test. */
static inline int jpg2_884_ready(const unsigned int v[20], unsigned int denied)
{
    return v[0]==0x4a505399U && v[1]==0x3247504aU && v[2]==0x10000U &&
        v[3]==31U && v[4]>=1U && v[4]<=100U && v[5]==1U && v[6]==1U &&
        v[7]==0 && v[8]==1 && v[9]==0 && (v[10]&7U)==1 &&
        v[11]>=481 && v[11]<=1024 && v[12]>=1080 && v[12]<=2301 &&
        v[13]==0 && v[14]==0 && v[15]==0 && v[16]==0 &&
        v[17]==denied && v[18]<=63 && v[19]==0;
}
