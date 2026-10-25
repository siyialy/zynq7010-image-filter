/* Exercise the actual PS controller with mocked hardware, including failures. */
#include <assert.h>
#include <stdarg.h>
#include <setjmp.h>
#include <string.h>
#include <stdio.h>
#define main firmware_main
#include "../ps_app/main.c"
#undef main
u32 g_brown_thr=15,g_v_max=140,g_frac_thr_x100=50;
static u32 regs[64];
static unsigned uploads,renders,detected;
static int held,last_result=-1,fail_sample=-1;
static unsigned long long clock_ticks;
static char output[200000];static size_t output_size;
static const char *keys;static jmp_buf finished;
void Xil_Out32(uintptr_t addr,u32 value) {
    regs[(addr-AXIL_BASE)/4]=value;
    if(addr==REG_IMG_DATA){assert(held);uploads++;}
}
u32 Xil_In32(uintptr_t addr){return addr==REG_VERSION?EXPECT_VERSION:regs[(addr-AXIL_BASE)/4];}
void XTime_GetTime(XTime *t){*t=clock_ticks++;}
void usleep(unsigned t){clock_ticks+=t;}
unsigned sleep(unsigned t){clock_ticks+=(unsigned long long)t*1000000;return 0;}
void Xil_DCacheEnable(void){}
void Xil_DCacheFlushRange(INTPTR a,unsigned b){(void)a;(void)b;}
void xil_printf(const char *fmt,...){
    va_list a;va_start(a,fmt);
    output_size+=vsnprintf(output+output_size,sizeof(output)-output_size,fmt,a);
    va_end(a);assert(output_size<sizeof(output));
}
unsigned char inbyte(void){if(!*keys)longjmp(finished,1);return (unsigned char)*keys++;}
void pest_render(const u8 *a,const pest_result_t *b,u8 *c){(void)a;(void)b;memset(c,64,DISP_W*DISP_H);renders++;}
void pest_render_background(const u8 *a,u8 *b){(void)a;memset(b,64,BG_PIX);}
void pl_display_hold(int hold){held=hold;}
u32 pl_detector_cycles(void){return 1234;}
u32 pl_detector_prepare_us(void){return 1;}
u32 pl_detector_upload_us(void){return 1;}
u32 pl_detector_wait_us(void){return 1;}
int pl_pest_detect(const u8 *a,pest_result_t *r){
    int n;for(n=0;n<PV_N;n++)if(a==pv_rgb[n])break;
    assert(n<PV_N);detected++;last_result=n;memset(r,0,sizeof(*r));
    if(n==fail_sample)return 0;
    r->num_box=n==13?7:(n>=12?1:0);r->diseased=r->num_box>0;return 1;
}
void sw_filter_3x3(const uint8_t *a,uint8_t *b,int w,int h,int mode){(void)a;(void)mode;memset(b,0,w*h);}
void sw_make_test_image(uint8_t *a,int w,int h){memset(a,0,w*h);}
static void menu(const char *s){keys=s;if(!setjmp(finished))firmware_main();}
int main(void){
    unsigned before;
    pest_run(13);assert(renders==1 && uploads==19680 && !held && last_result==13);
    before=detected;pest_run(13);assert(renders==1 && uploads==19680 && detected==before+1);
    pest_bench();assert(last_result==13 && g_cur==13 && g_result_idx==13 && g_display_idx==13 && regs[0x70/4]==1);
    g_overlay=0;pest_bench();assert(last_result==13 && regs[0x70/4]==0);
    fail_sample=13;pest_bench();assert(g_result_idx==-1 && regs[0x70/4]==0);
    assert(strstr(output,"detector success = 23/24"));
    fail_sample=-1;menu("o");assert(g_result_idx==13 && regs[0x70/4]==1);
    g_brown_thr=264;menu("]");assert(g_brown_thr==264);
    g_brown_thr=10;menu("[");assert(g_brown_thr==10);
    assert(renders==1 && uploads==19680);
    puts("PASS: real PS controller restores current boxes after benchmark, retains OFF state, hides failed results, repairs overlay, reuses display and clamps threshold endpoints");
    return 0;
}
