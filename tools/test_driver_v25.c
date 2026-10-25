/* Execute the actual PS driver, including the new pass/final-publish protocol. */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "../ps_app/pl_detector.c"
u32 g_brown_thr=15,g_v_max=140,g_frac_thr_x100=50;
static u32 mock_addr,sel,mode,uploaded,starts,total_uploads;
static u32 latched_sel;
static unsigned long long ticks;
static int skip,bad_received,bad_box,timeout,bad_feature;
void XTime_GetTime(XTime *t){ticks+=timeout?11000000:1;*t=ticks;}
void Xil_Out32(uintptr_t addr,u32 value){
    if(addr==IMG_ADDR){mock_addr=value;return;}
    assert(addr==IMG_DATA);
    if(mock_addr==80000){uploaded++;total_uploads++;return;}
    assert(mock_addr==80004);sel=(value>>8)&255;
    switch(value>>24){
        case 7:mode=sel;break;
        case 1:uploaded=0;break;
        case 2:assert(uploaded==65536);starts++;break;
        default:break;
    }
}
u32 Xil_In32(uintptr_t addr){
    u32 read_sel=latched_sel;
    assert(addr==DET_STATUS);
    latched_sel=sel; /* First bus read can still contain the previous selected item. */
    if(read_sel==1)return 100+mode;
    if(read_sel==2)return bad_received && mode==2?123:uploaded;
    if(read_sel==3){
#ifdef PEST_V26
        return bad_feature?0x20005:0x20006;
#else
        return bad_feature?0x20004:0x20005;
#endif
    }
    if(read_sel==4)return (skip||mode==3)?3:1;
    if(read_sel>=16 && read_sel<80){
        u32 k=(read_sel-16)/2;
        return (read_sel&1)?((50+k)<<16)|(bad_box && k==31?400:100+k):((20+k)<<16)|(60+k);
    }
    if(read_sel>=144 && read_sel<176)return 20+read_sel-144;
    return 0xD2000008U | (timeout?1U:2U) | (((skip||mode==3)?32U:0U)<<8);
}
static void reset_mock(void){mock_addr=sel=latched_sel=mode=uploaded=starts=total_uploads=0;ticks=0;skip=bad_received=bad_box=timeout=bad_feature=0;}
int main(void){
    static u8 rgb[256*256*3];pest_result_t r;
    memset(rgb,90,sizeof(rgb));reset_mock();
    assert(pl_pest_detect(rgb,&r));assert(starts==4 && total_uploads==4*65536);
    assert(r.num_box==32 && r.diseased && r.box[31].area==51 && r.box[31].x0==91);
    assert(pl_detector_cycles()==406);
    reset_mock();skip=1;assert(pl_pest_detect(rgb,&r));assert(starts==1 && total_uploads==65536 && pl_detector_cycles()==100);
    reset_mock();bad_received=1;assert(!pl_pest_detect(rgb,&r));assert(starts==2 && r.num_box==0);
    reset_mock();bad_box=1;assert(!pl_pest_detect(rgb,&r));assert(r.num_box==0);
    reset_mock();timeout=1;assert(!pl_pest_detect(rgb,&r));assert(starts==1 && r.num_box==0);
    reset_mock();bad_feature=1;assert(!pl_pest_detect(rgb,&r));assert(starts==0);
    puts("PASS: actual v25 PS driver four profiles/early finish/32 boxes/areas/cycles and failure guards");return 0;
}
