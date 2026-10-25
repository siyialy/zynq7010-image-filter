#include "pl_detector.h"
#include <string.h>
#ifndef PL_PREPROCESS_ONLY
#include "xil_io.h"
#include "xtime_l.h"
#define DET_BASE 0x43C00000U
#define DET_STATUS (DET_BASE+0x14U)
#define IMG_ADDR (DET_BASE+0x20U)
#define IMG_DATA (DET_BASE+0x24U)
static u32 last_cycles;
static u32 prepared[PV_IMG_W*PV_IMG_H];
static u32 prepare_us,upload_us,wait_us;
static void command(u32 opcode,u32 selector)
{
    u32 cut=g_brown_thr>9U?g_brown_thr-9U:1U;
    Xil_Out32(IMG_ADDR,80004U);
    Xil_Out32(IMG_DATA,(opcode<<24)|(selector<<8)|(cut&255U));
}
static u32 read_value(u32 selector)
{
    command(4,selector);
#ifdef PEST_V25
    /* Registered PL readback: complete one AXI read before consuming the next. */
    (void)Xil_In32(DET_STATUS);
#endif
    return Xil_In32(DET_STATUS);
}
u32 pl_detector_cycles(void) { return last_cycles; }
u32 pl_detector_prepare_us(void) { return prepare_us; }
u32 pl_detector_upload_us(void) { return upload_us; }
u32 pl_detector_wait_us(void) { return wait_us; }
void pl_display_hold(int hold) { command(hold?5U:6U,0); }
int pl_pest_detect(const u8 *rgb,pest_result_t *result)
{
    int x,y,i;
    u32 status;
#ifdef PEST_V25
    u32 pass,flags=0;
#endif
    XTime begin,now,stage;
    memset(result,0,sizeof(*result));
    last_cycles=0;
    prepare_us=upload_us=wait_us=0;
    if((read_value(0)&0xFF000000U)!=0xD2000000U)return 0;
#ifdef PEST_V26
    if(read_value(3)!=0x00020006U)return 0;
#elif defined(PEST_V25)
    if(read_value(3)!=0x00020005U)return 0;
#elif defined(PEST_OPTIMIZED)
    if(read_value(3)!=0x00020004U)return 0;
#elif defined(PEST_RECALL)
    if(read_value(3)!=0x00020003U)return 0;
#elif defined(PEST_PRECISION)
    if(read_value(3)!=0x00020002U)return 0;
#elif defined(PEST_FAST_PL)
    if(read_value(3)!=0x00020001U)return 0;
#endif
    XTime_GetTime(&stage);
#ifdef PEST_OPTIMIZED
    pl_preprocess_frame(rgb,prepared);
#endif
    XTime_GetTime(&begin);
    prepare_us=(u32)((begin-stage)*1000000ULL/COUNTS_PER_SECOND);
#ifdef PEST_V25
    for(pass=0;pass<4;pass++) {
    command(7,pass);
#endif
    command(3,0); /* Abort stale engine work; PL fusion survives between profiles. */
    command(1,0);
    XTime_GetTime(&begin);
    for(y=0;y<PV_IMG_H;y++)for(x=0;x<PV_IMG_W;x++) {
        Xil_Out32(IMG_ADDR,80000U);
#ifdef PEST_OPTIMIZED
        Xil_Out32(IMG_DATA,prepared[y*PV_IMG_W+x]);
#else
        Xil_Out32(IMG_DATA,pl_preprocess_pixel(rgb,x,y));
#endif
    }
    XTime_GetTime(&now);
    upload_us+=(u32)((now-begin)*1000000ULL/COUNTS_PER_SECOND);
    if(read_value(2)!=PV_IMG_W*PV_IMG_H){command(3,0);return 0;}
    command(2,0);
    XTime_GetTime(&begin);
    do {
        status=Xil_In32(DET_STATUS);
        if(status&4U){command(3,0);return 0;}
        if(status&2U)break;
        XTime_GetTime(&now);
        if(now-begin>10ULL*COUNTS_PER_SECOND){command(3,0);return 0;}
    }while(1);
    XTime_GetTime(&now);
    wait_us+=(u32)((now-begin)*1000000ULL/COUNTS_PER_SECOND);
#ifdef PEST_V25
    last_cycles+=read_value(1);
    flags=read_value(4);
    if(flags&2U)break;
    }
    if(!(flags&2U)){command(3,0);return 0;}
    status=read_value(0);
    result->num_box=(status>>8)&63U;
#else
    result->num_box=(status>>8)&31U;
#endif
    if(result->num_box>PV_MAX_BOX){command(3,0);return 0;}
    result->diseased=result->num_box>0;
    for(i=0;i<(int)result->num_box;i++) {
        u32 low=read_value(16U+2U*(u32)i),high=read_value(17U+2U*(u32)i);
        result->box[i].x0=(u16)(low&511U);result->box[i].y0=(u16)((low>>16)&511U);
        result->box[i].x1=(u16)(high&511U);result->box[i].y1=(u16)((high>>16)&511U);
        #ifdef PEST_V25
        result->box[i].area=read_value(144U+(u32)i);
#elif defined(PEST_PRECISION)
        result->box[i].area=read_value(64U+(u32)i);
#else
        result->box[i].area=read_value(40U+(u32)i);
#endif

        if(result->box[i].x0>result->box[i].x1 || result->box[i].y0>result->box[i].y1 ||
           result->box[i].x1>=DISP_W || result->box[i].y1>=DISP_H || !result->box[i].area) {
            command(3,0);memset(result,0,sizeof(*result));return 0;
        }
    }
#ifndef PEST_V25
    last_cycles=read_value(1);
#endif
    command(4,0);
    return 1;
}
#endif

static void horizontal_sum(const u8 *rgb,int y,u16 row[PV_IMG_W][3])
{
    int x,c;
    for(x=0;x<PV_IMG_W;x++)for(c=0;c<3;c++) {
        int left=x?x-1:0,right=x+1<PV_IMG_W?x+1:PV_IMG_W-1;
        row[x][c]=(u16)(rgb[(y*PV_IMG_W+left)*3+c]+rgb[(y*PV_IMG_W+x)*3+c]+rgb[(y*PV_IMG_W+right)*3+c]);
    }
}
void pl_preprocess_frame(const u8 *rgb,u32 *packed)
{
    static u16 rows[3][PV_IMG_W][3];
    u16 (*top)[3]=rows[0],(*mid)[3]=rows[1],(*bottom)[3]=rows[2],(*reuse)[3];
    int x,y;
    horizontal_sum(rgb,0,top);horizontal_sum(rgb,0,mid);horizontal_sum(rgb,1,bottom);
    for(y=0;y<PV_IMG_H;y++) {
        for(x=0;x<PV_IMG_W;x++) {
            u32 r=(top[x][0]+mid[x][0]+bottom[x][0])/9U;
            u32 g=(top[x][1]+mid[x][1]+bottom[x][1])/9U;
            u32 b=(top[x][2]+mid[x][2]+bottom[x][2])/9U;
            packed[y*PV_IMG_W+x]=r|(g<<8)|(b<<16);
        }
        if(y+1<PV_IMG_H) {
            reuse=top;top=mid;mid=bottom;bottom=reuse;
            horizontal_sum(rgb,y+2<PV_IMG_H?y+2:PV_IMG_H-1,bottom);
        }
    }
}

u32 pl_preprocess_pixel(const u8 *rgb,int x,int y)
{
    u32 sum[3]={0,0,0};
    int dx,dy,c;
    for(dy=-1;dy<=1;dy++)for(dx=-1;dx<=1;dx++) {
        int sx=x+dx,sy=y+dy;
        const u8 *p;
        if(sx<0)sx=0;
        if(sx>=PV_IMG_W)sx=PV_IMG_W-1;
        if(sy<0)sy=0;
        if(sy>=PV_IMG_H)sy=PV_IMG_H-1;
        p=rgb+(sy*PV_IMG_W+sx)*3;
        for(c=0;c<3;c++)sum[c]+=p[c];
    }
    return sum[0]/9U | ((sum[1]/9U)<<8) | ((sum[2]/9U)<<16);
}
