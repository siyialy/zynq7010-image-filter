// ============================================================================
// pest.h —— 番茄早疫病检测（PS 端算法）
// ============================================================================
#ifndef PEST_H
#define PEST_H

#include "xil_types.h"

#ifdef PEST_V25
#define PV_MAX_BOX 32
#elif defined(PEST_FULL_FRAME)
#define PV_MAX_BOX 16
#else
#define PV_MAX_BOX   8          // 最多输出几个标注框
#endif
#define PV_IMG_W     256
#define PV_IMG_H     256
#define DISP_W       320        // 送给 PL 的画面尺寸
#define DISP_H       240
#define BG_W         32         // 16 pooled columns per side, uploaded after main image
#define BG_H         60
#define BG_PIX       (BG_W * BG_H)
#define DISP_OX      0          // 铺满全屏，不留黑边
#ifdef PEST_FULL_FRAME
#define SRC_CROP_Y0 0
#define SRC_CROP_H 256
#define SRC_TO_DISP_X(sx) (40+(int)(sx)*15/16)
#define SRC_TO_DISP_Y(sy) ((int)(sy)*15/16)
#else
#define SRC_CROP_Y0 32
#define SRC_CROP_H 192
#define SRC_TO_DISP_X(sx) ((int)(sx)*5/4)
#define SRC_TO_DISP_Y(sy) (((int)(sy)-32)*5/4)
#endif

typedef struct {
    u16 x0, y0, x1, y1;         // 显示坐标（0..319 / 0..239）
    u32 area;                   // 该连通域面积（像素）
} pest_box_t;

typedef struct {
    u32   brown_px;             // 褐色像素数
    u32   leaf_px;              // 叶片像素数
    u32   frac_x100;            // 褐色占比 × 100（即 0.01% 为单位）
    u32   num_box;              // 输出框数
    int   diseased;             // 1 = 判为病害
    u8    bg[3];                // 估计出来的背景色（调试用）
    pest_box_t box[PV_MAX_BOX];
} pest_result_t;

// 检测一张 256x256 的 RGB 图
void pest_detect(const u8 *rgb, pest_result_t *res);

// Inclusive source bounds; these helpers are also checked by host regressions.
int pest_map_box(int x0, int y0, int x1, int y1, u32 area, pest_box_t *out);
void pest_insert_box(pest_result_t *res, const pest_box_t *box);

// 输出 320x240 灰度画面（bit7 保留为 0）；FULL_FRAME 保留完整原图，红框由 PL 绘制。
void pest_render(const u8 *rgb, const pest_result_t *res, u8 *out320x240);
// Build a blurred, mirrored side background from the clean 7-bit display image.
void pest_render_background(const u8 *display, u8 *background);

// 可在线调整的参数
void pest_set_params(u32 brown_thr, u32 v_max, u32 frac_thr_x100);
extern u32 g_brown_thr;      // R-G 门限，默认 15
extern u32 g_v_max;          // 亮度上限，默认 140
extern u32 g_frac_thr_x100;  // 判定阈值（×100），默认 50 即 0.5%

#endif // PEST_H
