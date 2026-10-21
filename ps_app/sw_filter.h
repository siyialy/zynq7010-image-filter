/* ============================================================================
 * sw_filter.h —— ARM 端 3x3 滤波的"软件基线"（用来和 FPGA 硬件比速度）
 *
 * 【为什么需要它】
 *   比赛评分要"FPGA/Zynq 的量化贡献"。光说"硬件快"没有说服力，
 *   必须：同一帧图像、同一算法，分别用 CPU 和 FPGA 各算一遍，比时间。
 *
 * 【为什么结果要和 RTL 完全一致】
 *   否则比的是两个不同算法，结论不成立。所以这里的整数运算、
 *   边界复制规则、饱和截断都和 src/rtl/img_filter_3x3.v 逐条对齐。
 * ==========================================================================*/
#ifndef SW_FILTER_H
#define SW_FILTER_H

#include <stdint.h>

/* 滤波模式，和 RTL 的 mode 编码一致 */
#define FILT_GRAY   0
#define FILT_MEAN   1
#define FILT_GAUSS  2
#define FILT_SOBEL  3

/*
 * 对一幅 8bit 灰度图做 3x3 滤波（原地不可，src/dst 分开）
 *   src, dst : 宽 w 高 h 的灰度图，行优先
 *   mode     : FILT_GRAY / MEAN / GAUSS / SOBEL
 *
 * 边界处理：边缘复制（clamp），和 RTL 一致。
 */
void sw_filter_3x3(const uint8_t *src, uint8_t *dst, int w, int h, int mode);

/* 单个像素的 3x3 计算（方便单元测试/逐点比对） */
uint8_t sw_filter_pixel(const uint8_t *src, int w, int h, int x, int y, int mode);

/* 生成一张 320x240 的测试图（棋盘 + 渐变 + 方块），无需外部图片 */
void sw_make_test_image(uint8_t *buf, int w, int h);

#endif /* SW_FILTER_H */
