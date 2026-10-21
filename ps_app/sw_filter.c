/* ============================================================================
 * sw_filter.c —— 3x3 滤波的 ARM 软件实现（软件基线）
 *
 * 所有整数运算与 src/rtl/img_filter_3x3.v 保持一致：
 *   均值   : (sum9 * 57) >> 9        （57/512 ≈ 1/9，误差 <=1）
 *   高斯   : (1 2 1; 2 4 2; 1 2 1) 加权和 >> 4
 *   Sobel  : |Gx| + |Gy|，饱和到 255
 *   边界   : 边缘复制（clamp）
 * ==========================================================================*/

#include "sw_filter.h"

/* 把越界坐标钳到图像内（和 RTL 的边界复制一致） */
static inline int clamp_i(int v, int lo, int hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

uint8_t sw_filter_pixel(const uint8_t *src, int w, int h, int x, int y, int mode)
{
    int i, j;
    int p[3][3];
    int sum9, gsum, gx, gy, mag;

    /* 取 3x3 邻域，越界用边缘复制 */
    for (i = 0; i < 3; i++) {
        int yi = clamp_i(y + i - 1, 0, h - 1);
        for (j = 0; j < 3; j++) {
            int xj = clamp_i(x + j - 1, 0, w - 1);
            p[i][j] = src[yi * w + xj];
        }
    }

    switch (mode) {
    case FILT_GRAY:
        return (uint8_t)p[1][1];

    case FILT_MEAN:
        sum9 = p[0][0]+p[0][1]+p[0][2]
             + p[1][0]+p[1][1]+p[1][2]
             + p[2][0]+p[2][1]+p[2][2];
        return (uint8_t)((sum9 * 57) >> 9);

    case FILT_GAUSS:
        gsum = p[0][0] + 2*p[0][1] + p[0][2]
             + 2*p[1][0] + 4*p[1][1] + 2*p[1][2]
             + p[2][0] + 2*p[2][1] + p[2][2];
        return (uint8_t)(gsum >> 4);

    case FILT_SOBEL:
        gx = (p[0][2] + 2*p[1][2] + p[2][2]) - (p[0][0] + 2*p[1][0] + p[2][0]);
        gy = (p[2][0] + 2*p[2][1] + p[2][2]) - (p[0][0] + 2*p[0][1] + p[0][2]);
        if (gx < 0) gx = -gx;
        if (gy < 0) gy = -gy;
        mag = gx + gy;
        if (mag > 255) mag = 255;
        return (uint8_t)mag;

    default:
        return (uint8_t)p[1][1];
    }
}

void sw_filter_3x3(const uint8_t *src, uint8_t *dst, int w, int h, int mode)
{
    int x, y;
    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            dst[y * w + x] = sw_filter_pixel(src, w, h, x, y, mode);
        }
    }
}

void sw_make_test_image(uint8_t *buf, int w, int h)
{
    int x, y;
    for (y = 0; y < h; y++) {
        for (x = 0; x < w; x++) {
            uint8_t v;
            /* 8x8 棋盘（考验边缘检测）+ 横向渐变（考验模糊） */
            v = (uint8_t)((x * 255) / (w > 1 ? (w - 1) : 1));
            if (((x >> 3) + (y >> 3)) & 1)
                v = (uint8_t)(255 - v);

            /* 中间放一个实心方块（清晰的边界） */
            if (x > w/4 && x < w*3/4 && y > h/4 && y < h*3/4)
                v = 200;

            buf[y * w + x] = v;
        }
    }
}
