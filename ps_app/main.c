/* ============================================================================
 * main.c —— PS 端主程序（ARM Cortex-A9，裸机）
 *
 * 功能：
 *   1. 通过 AXI4-Lite 读写 PL 里的寄存器：切滤波模式、读硬件版本、读帧计数
 *   2. 串口菜单交互（0/1/2/3 切模式，h 测帧率，c 跑软件基线对比，i 看寄存器）
 *   3. 软件基线：同一幅图用 CPU 算 3x3 滤波，测时间，和 FPGA 比加速比
 *
 * 编译环境：SDK/Vitis 2018.3，standalone BSP，配合本工程导出的 .xsa/.hdf
 *
 * 【必须先改这一行】AXIL_BASE 要和你 Block Design 里 Address Editor 的地址一致
 * ==========================================================================*/

#include <stdio.h>
#include <stdint.h>
#include "xparameters.h"
#include "xil_types.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xtime_l.h"
#include "sleep.h"

#include "sw_filter.h"
#include "pest.h"
#include "pv_samples.h"
#ifdef PEST_USE_PL
#include "pl_detector.h"
#endif

/* ---------------- 寄存器映射（和 src/rtl/axil_regs.v 一致） ---------------- */
#ifndef AXIL_BASE
#define AXIL_BASE      0x43C00000U      /* Block Design 里分配的基地址，按实际修改 */
#endif

#define REG_CTRL       (AXIL_BASE + 0x00U)
#define REG_MODE       (AXIL_BASE + 0x04U)
#define REG_THRESH     (AXIL_BASE + 0x08U)
#define REG_VERSION    (AXIL_BASE + 0x0CU)
#define REG_FRAME_CNT  (AXIL_BASE + 0x10U)
#define REG_STATUS     (AXIL_BASE + 0x14U)

#define EXPECT_VERSION 0x00010000U

/* ---- 图像上传 + 标框寄存器（V1.2 新增）---- */
#define REG_IMG_ADDR   (AXIL_BASE + 0x20U)   /* 缓冲区字节地址 */
#define REG_IMG_DATA   (AXIL_BASE + 0x24U)   /* 写一次 = 4 字节，地址自动 +4 */
#define REG_BOX_CNT    (AXIL_BASE + 0x6CU)   /* 有效框数量 */
#define REG_BOX_CTRL   (AXIL_BASE + 0x70U)   /* bit0=画框使能；写一次提交一次 */
#define REG_BOX(i)     (AXIL_BASE + 0x2CU + 8U * (i))   /* 第 i 个框：+0=(x0,y0) +4=(x1,y1) */

/* 显示坐标 -> 屏幕坐标：PL 把 320x240 放大 3 倍成 960x720 居中显示
                               screen_x = 3*dx + 160,  screen_y = 3*dy  */
#define DISP_TO_SCREEN_X(dx)  ((u32)(dx) * 3U + 160U)
#define DISP_TO_SCREEN_Y(dy)  ((int)(dy) * 3)

/* ---------------- 软件基线用的图像参数 ---------------- */
#define IMG_W   320
#define IMG_H   240
#define IMG_PIX (IMG_W * IMG_H)

/* 硬件处理一个像素需要的时间：75MHz 像素时钟，每拍 1 个像素
 * 用整数皮秒表示（13333 ps = 13.333 ns），避免浮点 */
#define HW_PS_PER_PIXEL   13333U

static uint8_t g_src[IMG_PIX];
static uint8_t g_dst[IMG_PIX];

static const char *mode_name(int m)
{
    switch (m) {
    case FILT_GRAY:  return "grayscale";
    case FILT_MEAN:  return "mean 3x3";
    case FILT_GAUSS: return "gauss 3x3";
    case FILT_SOBEL: return "sobel";
    default:         return "?";
    }
}

/* ---------------- 读串口一个字符（standalone） ---------------- */
static char uart_getc(void)
{
    return (char)inbyte();
}

/* ---------------- 设置滤波模式 ---------------- */
static void set_mode(int m)
{
    Xil_Out32(REG_MODE, (uint32_t)m);
    xil_printf("  -> mode = %d (%s)\r\n", m,
               mode_name(Xil_In32(REG_MODE) & 0x7));
}

/* ---------------- 测硬件帧率 ----------------
 * 注意：xil_printf 不支持 %f（浮点），所以全部用整数定点打印。
 * 这是嵌入式里很常见的一个坑：printf 看起来"没输出数字"，其实是格式符不支持。
 */
static void measure_hw_fps(void)
{
    uint32_t c0, c1;
    uint32_t frames, fps_x100, period_us;
    uint64_t ticks, us;
    XTime    t0, t1;

    c0 = Xil_In32(REG_FRAME_CNT);
    XTime_GetTime(&t0);
    sleep(1);
    XTime_GetTime(&t1);
    c1 = Xil_In32(REG_FRAME_CNT);

    ticks = (uint64_t)(t1 - t0);
    if (c1 < c0 || ticks == 0U) {
        xil_printf("  frame_cnt did not advance: %u -> %u. "
                   "Is the PL bitstream loaded?\r\n", (unsigned)c0, (unsigned)c1);
        return;
    }

    frames = c1 - c0;
    us     = (ticks * 1000000ULL) / (uint64_t)COUNTS_PER_SECOND;   /* 经过的微秒 */

    /* fps × 100，例如 6063 表示 60.63 fps */
    fps_x100  = (uint32_t)(((uint64_t)frames * (uint64_t)COUNTS_PER_SECOND * 100ULL) / ticks);
    period_us = (uint32_t)(us / frames);                            /* 每帧微秒 */

    xil_printf("  frame_cnt: %u -> %u  (%u frames in %u us)\r\n",
               (unsigned)c0, (unsigned)c1, (unsigned)frames, (unsigned)us);
    xil_printf("  hardware fps = %u.%02u  (frame period %u us = %u.%02u ms)\r\n",
               (unsigned)(fps_x100 / 100U), (unsigned)(fps_x100 % 100U),
               (unsigned)period_us,
               (unsigned)(period_us / 1000U), (unsigned)((period_us % 1000U) / 10U));
    xil_printf("  CPU load while filtering: ~0%% (all pixels done in PL)\r\n");
}

/* ---------------- 软件基线：同一算法用 CPU 算 ---------------- */
static void bench_sw(int mode)
{
    XTime    t0, t1;
    uint64_t ticks, us, ns_pix, fps_x100;

    /* 让 CPU cache 状态一致：先跑一遍预热，再 flush，再计时 */
    sw_filter_3x3(g_src, g_dst, IMG_W, IMG_H, mode);
    Xil_DCacheFlushRange((INTPTR)g_src, IMG_PIX);
    Xil_DCacheFlushRange((INTPTR)g_dst, IMG_PIX);

    XTime_GetTime(&t0);
    sw_filter_3x3(g_src, g_dst, IMG_W, IMG_H, mode);
    XTime_GetTime(&t1);

    ticks = (uint64_t)(t1 - t0);
    if (ticks == 0U) { xil_printf("  %-10s  SW: too fast to measure\r\n", mode_name(mode)); return; }

    us       = (ticks * 1000000ULL) / (uint64_t)COUNTS_PER_SECOND;      /* 总微秒 */
    ns_pix   = (ticks * 1000000000ULL) / (uint64_t)COUNTS_PER_SECOND / (uint64_t)IMG_PIX;
    fps_x100 = ((uint64_t)COUNTS_PER_SECOND * 100ULL) / ticks;          /* 1 次/秒 → fps */

    /* ms = us/1000，打印成 "整数.小数" */
    xil_printf("  %-10s  SW: %u.%03u ms/frame (%u ns/pixel, %u.%02u fps)\r\n",
               mode_name(mode),
               (unsigned)(us / 1000U), (unsigned)(us % 1000U),
               (unsigned)ns_pix,
               (unsigned)(fps_x100 / 100U), (unsigned)(fps_x100 % 100U));
}

static void bench_all(void)
{
    int m;

    xil_printf("\r\n--- software baseline (%dx%d, CPU only) ---\r\n", IMG_W, IMG_H);
    sw_make_test_image(g_src, IMG_W, IMG_H);

    for (m = 0; m <= 3; m++)
        bench_sw(m);

    /* 硬件参考：每像素 1 个时钟 @75MHz = 13333 ps */
    {
        uint64_t hw_ns_total = ((uint64_t)IMG_PIX * HW_PS_PER_PIXEL) / 1000ULL;  /* 纳秒 */
        xil_printf("\r\n--- hardware reference ---\r\n");
        xil_printf("  HW: %u.%03u ms for the same %u pixels (%u.%03u ns/pixel @75MHz)\r\n",
                   (unsigned)(hw_ns_total / 1000000ULL),
                   (unsigned)((hw_ns_total % 1000000ULL) / 1000ULL),
                   (unsigned)IMG_PIX,
                   (unsigned)(HW_PS_PER_PIXEL / 1000U),
                   (unsigned)(HW_PS_PER_PIXEL % 1000U));
    }
    xil_printf("  NOTE: in the real system PL filters the full 1280x720 frame\r\n");
    xil_printf("        inside the 16.67 ms frame period, with ~0%% CPU load.\r\n");
}

/* ---------------- 打印寄存器 ---------------- */
static void dump_regs(void)
{
    xil_printf("\r\n  CTRL      = 0x%08x\r\n", (unsigned)Xil_In32(REG_CTRL));
    xil_printf("  MODE      = 0x%08x\r\n", (unsigned)Xil_In32(REG_MODE));
    xil_printf("  THRESH    = 0x%08x\r\n", (unsigned)Xil_In32(REG_THRESH));
    xil_printf("  VERSION   = 0x%08x\r\n", (unsigned)Xil_In32(REG_VERSION));
    xil_printf("  FRAME_CNT = 0x%08x\r\n", (unsigned)Xil_In32(REG_FRAME_CNT));
    xil_printf("  STATUS    = 0x%08x\r\n", (unsigned)Xil_In32(REG_STATUS));
}

/* ==================================================================
 * 早疫病检测 / 图像上传 / 标框
 * ================================================================== */
static int  g_cur      = 0;        /* 当前样本序号 0..PV_N-1 */
static int  g_overlay  = 1;        /* 是否画框 */
static int g_display_idx=-1,g_result_idx=-1;
static u8   g_disp[DISP_W * DISP_H];
static u8   g_background[BG_PIX];

/* 把 320x240 灰度画面写进 PL 的图像缓冲区（每次 4 字节，共 19200 次写） */
static void upload_image(const u8 *img)
{
    u32 i, w;
    Xil_Out32(REG_IMG_ADDR, 0);
    for (i = 0; i < (u32)DISP_W * DISP_H; i += 4U) {
        w = (u32)img[i]
          | ((u32)img[i + 1] << 8)
          | ((u32)img[i + 2] << 16)
          | ((u32)img[i + 3] << 24);
        Xil_Out32(REG_IMG_DATA, w);
    }
}

static void upload_background(const u8 *image)
{
    u32 i, word;
    Xil_Out32(REG_IMG_ADDR, (u32)DISP_W*DISP_H);
    for (i = 0; i < BG_PIX; i += 4U) {
        word = (u32)image[i] | ((u32)image[i+1] << 8) |
               ((u32)image[i+2] << 16) | ((u32)image[i+3] << 24);
        Xil_Out32(REG_IMG_DATA,word);
    }
}

/* 把检测出的框写进 PL（坐标要换算成屏幕坐标） */
#ifndef PEST_USE_PL
static void set_boxes(const pest_result_t *r, int enable)
{
    u32 i, count = 0;
    for (i = 0; i < r->num_box && i < PV_MAX_BOX; i++) {
        const pest_box_t *b = &r->box[i];
        u32 x0, y0, x1, y1;
        /* Reject corrupt geometry; clamping an invalid box can create a long line. */
        if (b->x0 > b->x1 || b->y0 > b->y1 || b->x1 >= DISP_W || b->y1 >= DISP_H) continue;
        x0 = DISP_TO_SCREEN_X(b->x0);
        y0 = (u32)DISP_TO_SCREEN_Y(b->y0);
        /* Each inclusive display pixel occupies three screen pixels. */
        x1 = DISP_TO_SCREEN_X(b->x1) + 2U;
        y1 = (u32)DISP_TO_SCREEN_Y(b->y1) + 2U;
        Xil_Out32(REG_BOX(count) + 0U, (y0 << 16) | x0);
        Xil_Out32(REG_BOX(count) + 4U, (y1 << 16) | x1);
        count++;
    }
    for (i = count; i < PV_MAX_BOX; i++) {
        Xil_Out32(REG_BOX(i) + 0U, 0);
        Xil_Out32(REG_BOX(i) + 4U, 0);
    }
    Xil_Out32(REG_BOX_CNT, count);
    Xil_Out32(REG_BOX_CTRL, enable ? 1U : 0U);   /* 写这个寄存器同时提交配置 */
}

#endif

static int detect_sample(int idx,pest_result_t *r)
{
#ifdef PEST_USE_PL
    int ok;
    g_result_idx=-1;
    ok=pl_pest_detect(pv_rgb[idx],r);
    if(ok)g_result_idx=idx;
    return ok;
#else
    pest_detect(pv_rgb[idx],r);return 1;
#endif
}

/* 处理一个样本：检测 -> 渲染 -> 上传 -> 标框 -> 打印 */
static void pest_run(int idx)
{
    pest_result_t r = {0};
    u32 us;
#ifdef PEST_FAST_PL
    XTime whole_start,whole_end;
    u32 whole_us;
    XTime_GetTime(&whole_start);
#endif

    if (idx < 0) idx = 0;
    if (idx >= PV_N) idx = PV_N - 1;
    g_cur = idx;
    Xil_Out32(REG_CTRL,1);
    Xil_Out32(REG_MODE,FILT_GRAY);
#ifdef PEST_USE_PL
    /* Hide old boxes before changing the image. Publish new PL boxes only
       after this same image is uploaded and its hardware result is ready. */
    Xil_Out32(REG_BOX_CTRL,0);
    if(g_display_idx!=idx) {
        /* Prepare in PS while the intact previous image remains visible;
           cover HDMI only for the subsequent writes to the single buffer. */
        pest_render(pv_rgb[idx],&r,g_disp);
        pest_render_background(g_disp,g_background);
#ifdef PEST_OPTIMIZED
        pl_display_hold(1);
#endif
        usleep(20000);
        upload_image(g_disp);upload_background(g_background);
        g_display_idx=idx;
#ifdef PEST_OPTIMIZED
        pl_display_hold(0);
#endif
    } else usleep(20000); /* Let the hidden-overlay commit reach a frame boundary. */
#endif

    {
        XTime t_start, t_end;
        XTime_GetTime(&t_start);
        if(!detect_sample(idx,&r)) {
            xil_printf("  PL detector ERROR/timeout: no PS fallback, no healthy verdict\r\n");return;
        }
        XTime_GetTime(&t_end);
        us = (u32)((t_end - t_start) * 1000000ULL / COUNTS_PER_SECOND);
    }
#ifndef PEST_USE_PL
    pest_render(pv_rgb[idx], &r, g_disp);
    pest_render_background(g_disp,g_background);
    upload_image(g_disp);
    upload_background(g_background);
    set_boxes(&r, g_overlay);
#else
    Xil_Out32(REG_BOX_CTRL,g_overlay?1U:0U);
#endif

    /* 显示样本时切回灰度（否则是 Sobel 边缘图，看不清病灶） */
    Xil_Out32(REG_CTRL, 1);
    Xil_Out32(REG_MODE, FILT_GRAY);
#ifdef PEST_FAST_PL
    XTime_GetTime(&whole_end);
    whole_us=(u32)((whole_end-whole_start)*1000000ULL/COUNTS_PER_SECOND);
#endif
    xil_printf("\r\n  sample %d/%d  dataset label=%s\r\n", idx + 1, PV_N,
               pv_label[idx] ? "EARLY BLIGHT" : "HEALTHY");
    /* xil_printf 不支持 %f，全部用整数拼小数点 */
#ifdef PEST_USE_PL
    xil_printf("  detector=PL Verilog  boxes=%u  PS preprocess/upload + PL=%u.%03u ms\r\n",
               (unsigned)r.num_box,(unsigned)(us/1000U),(unsigned)(us%1000U));
    xil_printf("  PL processing cycles=%u at AXI clock; PS does not compute lesion boxes\r\n",
               (unsigned)pl_detector_cycles());
#ifdef PEST_OPTIMIZED
    xil_printf("  stages: RGB prepare=%u us, upload=%u us, PL wait=%u us; display sample=%d result sample=%d\r\n",
        (unsigned)pl_detector_prepare_us(),(unsigned)pl_detector_upload_us(),(unsigned)pl_detector_wait_us(),
        g_display_idx+1,g_result_idx+1);
#endif
#ifdef PEST_FAST_PL
    xil_printf("  whole sample work (display + detect): %u.%03u ms\r\n",
               (unsigned)(whole_us/1000U),(unsigned)(whole_us%1000U));
#endif
#else
    xil_printf("  leaf brown %u.%02u%%  (%u / %u px)   boxes=%u   %u.%03u ms\r\n",
               (unsigned)(r.frac_x100 / 100U), (unsigned)(r.frac_x100 % 100U),
               (unsigned)r.brown_px, (unsigned)r.leaf_px,
               (unsigned)r.num_box,
               (unsigned)(us / 1000U), (unsigned)(us % 1000U));
    /* 自检：打印源图前 3 个字节，确认数据真的在 DDR 里 */
    xil_printf("  dbg: px0=(%u,%u,%u) bg=(%u,%u,%u) leaf=%u brown=%u\r\n",
               (unsigned)pv_rgb[idx][0], (unsigned)pv_rgb[idx][1],
               (unsigned)pv_rgb[idx][2],
               (unsigned)r.bg[0], (unsigned)r.bg[1], (unsigned)r.bg[2],
               (unsigned)r.leaf_px, (unsigned)r.brown_px);
#endif
    xil_printf("  verdict (retained lesion evidence): %s\r\n", r.diseased ? "DISEASED" : "NO_RELIABLE_LESION");
    if (!r.diseased) {
        xil_printf("  no reliable lesion found; this does not prove the leaf is healthy\r\n");
    }
    if (r.diseased && r.num_box > 0) {
        xil_printf("  box0: screen (%u,%u)-(%u,%u) area %u\r\n",
                   (unsigned)DISP_TO_SCREEN_X(r.box[0].x0),
                   (unsigned)DISP_TO_SCREEN_Y(r.box[0].y0),
                   (unsigned)DISP_TO_SCREEN_X(r.box[0].x1),
                   (unsigned)DISP_TO_SCREEN_Y(r.box[0].y1),
                   (unsigned)r.box[0].area);
    }
}

/* 批量跑完全部样本，给出混淆矩阵 */
static void pest_bench(void)
{
    pest_result_t r;
    int i, tp = 0, tn = 0, fp = 0, fn = 0, errors = 0;
    u32 max_ms = 0;

#ifdef PEST_USE_PL
    Xil_Out32(REG_BOX_CTRL,0);
#endif
    xil_printf("\r\n  running all %d samples...\r\n", PV_N);
    for (i = 0; i < PV_N; i++) {
        XTime t0, t1;
        XTime_GetTime(&t0);
        if(!detect_sample(i,&r)) {
            errors++;xil_printf("    %2d PL_ERROR (excluded from TP/TN/FP/FN)\r\n",i+1);continue;
        }
        XTime_GetTime(&t1);
        {
            u32 us = (u32)((t1 - t0) * 1000000ULL / COUNTS_PER_SECOND);
            if (us > max_ms) max_ms = us;
        }

        if (r.diseased &&  pv_label[i]) tp++;
        if (!r.diseased && !pv_label[i]) tn++;
        if (r.diseased && !pv_label[i]) fp++;
        if (!r.diseased &&  pv_label[i]) fn++;
#ifdef PEST_USE_PL
        xil_printf("    %2d label=%s boxes=%u -> %s\r\n",i+1,pv_label[i]?"blight":"healthy",
                   (unsigned)r.num_box,r.diseased?"DISEASED":"NO_RELIABLE_LESION");
        {
            u32 box;
            for(box=0;box<r.num_box;box++)xil_printf("  PL_BOX %d %u %u %u %u %u %u\r\n",
                i+1,(unsigned)box,(unsigned)r.box[box].x0,(unsigned)r.box[box].y0,
                (unsigned)r.box[box].x1,(unsigned)r.box[box].y1,(unsigned)r.box[box].area);
        }
#else
        xil_printf("    %2d %-8s brown %2u.%02u%%  -> %s\r\n", i + 1,
                   pv_label[i] ? "blight" : "healthy",
                   (unsigned)(r.frac_x100 / 100U), (unsigned)(r.frac_x100 % 100U),
                   r.diseased ? "DISEASED" : "NO_RELIABLE_LESION");
#endif
    }
    /* The benchmark changed PL working results, while the displayed image
       stayed put. Recompute the displayed sample before enabling any boxes. */
#ifdef PEST_USE_PL
    xil_printf("  restoring displayed sample %d after benchmark\r\n",g_cur+1);
    pest_run(g_cur);
#endif
    xil_printf("  detector errors = %d\r\n",errors);
    xil_printf("\r\n  TP=%d TN=%d FP=%d FN=%d\r\n", tp, tn, fp, fn);
    if(tp+fn>0) xil_printf("  sensitivity = %d/%d = %d.%02d%%\r\n", tp, tp + fn,
               (tp * 100) / (tp + fn), ((tp * 10000) / (tp + fn)) % 100);
    if(tn+fp>0) xil_printf("  specificity = %d/%d = %d.%02d%%\r\n", tn, tn + fp,
               (tn * 100) / (tn + fp), ((tn * 10000) / (tn + fp)) % 100);
    if(PV_N>errors)xil_printf("  accuracy (valid samples) = %d/%d = %d.%02d%%\r\n",tp+tn,PV_N-errors,
        ((tp+tn)*100)/(PV_N-errors),(((tp+tn)*10000)/(PV_N-errors))%100);
    else xil_printf("  accuracy: unavailable (no valid detections)\r\n");
    xil_printf("  detector success = %d/%d\r\n",PV_N-errors,PV_N);
    xil_printf("  max detect time = %u us\r\n", (unsigned)max_ms);
}

static void print_menu(void)
{
    xil_printf("\r\n===== ZYNQ-7010 real-time image filter =====\r\n");
    xil_printf("  0/1/2/3 : set filter mode (gray/mean/gauss/sobel)\r\n");
    xil_printf("  e / d   : filter enable / bypass\r\n");
    xil_printf("  h       : measure hardware frame rate\r\n");
    xil_printf("  c       : software baseline vs hardware\r\n");
    xil_printf("  i       : dump registers\r\n");
#ifdef PEST_USE_PL
#ifdef PEST_V26
    xil_printf("  -------- pest detector v2.6 (PL shadow rejection / 32 boxes) --------\r\n");
#elif defined(PEST_V25)
    xil_printf("  -------- pest detector v2.5 (PL refinement / 32 boxes) --------\r\n");
#elif defined(PEST_OPTIMIZED)
    xil_printf("  -------- pest detector v2.4 (streamed morphology / matched display) --------\r\n");
#elif defined(PEST_RECALL)
    xil_printf("  -------- pest detector v2.3 (small dark lesions / 16 PL boxes) --------\r\n");
#elif defined(PEST_PRECISION)
    xil_printf("  -------- pest detector v2.2 (whole leaf / verified cores / 16 PL boxes) --------\r\n");
#elif defined(PEST_FAST_PL)
    xil_printf("  -------- pest detector v2.1 (fast PL windows / same lesion rules) --------\r\n");
#else
    xil_printf("  -------- pest detector v2.0 (PS preprocess / PL Verilog detection) --------\r\n");
#endif
#else
    xil_printf("  -------- pest detector v1.7 (faded lesion recall / bounded margin growth) --------\r\n");
#endif
    xil_printf("  n / b   : next / previous sample (%d samples)\r\n", PV_N);
    xil_printf("  p       : re-detect current sample\r\n");
    xil_printf("  o       : toggle box overlay\r\n");
    xil_printf("  s       : bench all samples (confusion matrix)\r\n");
    xil_printf("  [ / ]   : brown threshold -1 / +1 (now %u)\r\n", (unsigned)g_brown_thr);
    xil_printf("  m       : show this menu\r\n");
    xil_printf("===========================================\r\n");
}

int main(void)
{
    uint32_t ver;
    char     c;

    /* ================================================================
     * 开机初始化：写 PL 寄存器（带等待 + 回读校验 + 重试）
     *
     * 【为什么需要这段】
     *   真机实测发现：程序刚被下载运行时，PL 侧 AXI 的复位
     *   （proc_sys_reset 的 peripheral_aresetn）可能还没释放完，
     *   此时第一条 AXI 写会被静默丢弃，寄存器仍是 0。
     *
     *   表现：程序看起来在跑，但显示器画面不变（模式一直是 0）。
     *
     *   解法：先等一会儿，然后"写 → 读回 → 不对就重试"。
     *   这才是能上生产的写法 —— 不能假设第一条总线访问一定成功。
     * ================================================================ */
    {
        uint32_t retry, ok = 0;

        usleep(20000);

        for (retry = 0; retry < 8U; retry++) {
            Xil_Out32(REG_CTRL, 1);                 /* 先开滤波使能 */
            Xil_Out32(REG_MODE, FILT_SOBEL);        /* 再设模式（开机演示 Sobel） */

            if ((Xil_In32(REG_MODE) & 0x7U) == (uint32_t)FILT_SOBEL) {
                ok = 1U;
                break;
            }
            usleep(10000);
        }

        /* 回读校验失败也没关系，后面菜单还能改；这里只做一次记录 */
        if (!ok) {
            Xil_Out32(REG_CTRL, 1);
            Xil_Out32(REG_MODE, FILT_SOBEL);
        }
    }

    xil_printf("\r\n\r\n*** ZYNQ-7010 image filter (PS side) booting ***\r\n");

    /* ---- 确认 PL 在位：读 VERSION ---- */
    ver = Xil_In32(REG_VERSION);
    xil_printf("PL version register = 0x%08x\r\n", (unsigned)ver);
    if (ver != EXPECT_VERSION) {
        xil_printf("WARNING: unexpected version (expect 0x%08x).\r\n",
                   (unsigned)EXPECT_VERSION);
        xil_printf("         Check AXIL_BASE (0x%08x) in main.c against the\r\n",
                   (unsigned)AXIL_BASE);
        xil_printf("         Address Editor of your block design.\r\n");
    }
    else {
        xil_printf("PL is alive. AXI4-Lite link OK.\r\n");
    }

    /* ================================================================
     * 打开数据 cache —— 给软件基线一个公平的起点
     *
     * 裸机默认是关着 D-Cache 的，所有内存访问都直接走 DDR，
     * 3x3 滤波每像素 9 次访存 → 慢到 964 ns/像素，这个数字会让
     * "加速比"虚高几十倍，站不住脚。
     *
     * BSP 的页表已经把
     *     DDR 0x0000_0000-0x3FFF_FFFF 划为 Normal write-back Cacheable
     *     PL  0x4000_0000-0xBFFF_FFFF 划为 Strongly Ordered
     * 所以开 D-Cache 不会影响 AXI 寄存器访问（PL 区是强序的）。
     * ================================================================ */
    Xil_DCacheEnable();

    /* ---- 默认停在 Sobel（开机演示效果最好），阈值清零 ---- */
    Xil_Out32(REG_THRESH, 0);
    Xil_Out32(REG_CTRL, 1);
    Xil_Out32(REG_MODE, FILT_SOBEL);

    print_menu();

    while (1) {
        xil_printf("\r\n> ");
        c = uart_getc();
        xil_printf("%c\r\n", c);

        switch (c) {
        case '0': case '1': case '2': case '3':
            set_mode(c - '0');
            break;
        case 'e':
            Xil_Out32(REG_CTRL, 1);
            xil_printf("  filter enabled\r\n");
            break;
        case 'd':
            Xil_Out32(REG_CTRL, 0);
            xil_printf("  bypass (raw image)\r\n");
            break;
        case 'h':
            measure_hw_fps();
            break;
        case 'c':
            bench_all();
            break;
        case 'i':
            dump_regs();
            break;
        case 'm':
            print_menu();
            break;
        /* ---- 早疫病检测 ---- */
        case 'n':
            pest_run(g_cur + 1);
            break;
        case 'b':
            pest_run(g_cur - 1);
            break;
        case 'p':
            pest_run(g_cur);
            break;
        case 'o':
            g_overlay = !g_overlay;
#ifdef PEST_USE_PL
            if(g_overlay && (g_result_idx!=g_display_idx || g_result_idx!=g_cur))pest_run(g_cur);
            else
#endif
            Xil_Out32(REG_BOX_CTRL, g_overlay ? 1U : 0U);
            xil_printf("  box overlay %s\r\n", g_overlay ? "ON" : "OFF");
            break;
        case 's':
            pest_bench();
            break;
        case '[':
            if (g_brown_thr > 10U) g_brown_thr--;
            xil_printf("  brown control = %u (PL cut=%u); re-detecting\r\n",(unsigned)g_brown_thr,(unsigned)(g_brown_thr-9U));
            pest_run(g_cur);
            break;
        case ']':
            if(g_brown_thr<264U)g_brown_thr++;
            xil_printf("  brown control = %u (PL cut=%u); re-detecting\r\n",(unsigned)g_brown_thr,(unsigned)(g_brown_thr-9U));
            pest_run(g_cur);
            break;
        default:
            xil_printf("  unknown key, press 'm' for menu\r\n");
            break;
        }
    }

    return 0;
}
