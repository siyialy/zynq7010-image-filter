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

static void print_menu(void)
{
    xil_printf("\r\n===== ZYNQ-7010 real-time image filter =====\r\n");
    xil_printf("  0/1/2/3 : set filter mode (gray/mean/gauss/sobel)\r\n");
    xil_printf("  e / d   : filter enable / bypass\r\n");
    xil_printf("  h       : measure hardware frame rate\r\n");
    xil_printf("  c       : software baseline vs hardware\r\n");
    xil_printf("  i       : dump registers\r\n");
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
        uint32_t i, retry, ok = 0;

        for (i = 0; i < 400000U; i++) { }           /* 约几十毫秒，等 PL 复位释放 */

        for (retry = 0; retry < 8U; retry++) {
            Xil_Out32(REG_CTRL, 1);                 /* 先开滤波使能 */
            Xil_Out32(REG_MODE, FILT_SOBEL);        /* 再设模式（开机演示 Sobel） */

            if ((Xil_In32(REG_MODE) & 0x7U) == (uint32_t)FILT_SOBEL) {
                ok = 1U;
                break;
            }
            for (i = 0; i < 200000U; i++) { }       /* 重试前再等一下 */
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
        default:
            xil_printf("  unknown key, press 'm' for menu\r\n");
            break;
        }
    }

    return 0;
}
