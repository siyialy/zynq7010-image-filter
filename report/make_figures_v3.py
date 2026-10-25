#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
make_figures_v3.py —— 为"应用成果：番茄早疫病检测"补两张图
  图13  PL 病斑检测器流水线（v2.6）
  图14  检测效果对照（第 14 张，v2.2 4 框 → v2.3 7 框）

风格与 make_figures.py 保持一致（同一套配色、同一字体）。
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(HERE, "figures")
PHO = os.path.join(HERE, "photos")
BUILD = os.path.join(os.path.dirname(HERE), "build")

FONT = r"C:\Windows\Fonts\msyh.ttc"
FONTB = r"C:\Windows\Fonts\msyhbd.ttc"

# ---- 统一配色（与 make_figures.py 相同）----
PS_F, PS_E = (222, 235, 247), (31, 78, 121)      # 蓝：PS 侧
PL_F, PL_E = (226, 240, 217), (55, 86, 35)       # 绿：PL 侧
IO_F, IO_E = (252, 228, 214), (140, 60, 20)      # 橙：外设/存储
GY_F, GY_E = (242, 242, 242), (80, 80, 80)       # 灰：辅助
BLK = (30, 30, 30)
LINE = (100, 100, 100)


def f(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def box(d, x0, y0, x1, y1, fill, edge, r=8, w=2):
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill, outline=edge, width=w)


def center_text(d, cx, y, text, font, fill=BLK):
    tw = d.textlength(text, font=font)
    d.text((cx - tw / 2, y), text, font=font, fill=fill)


def arrow(d, x0, y0, x1, y1, color=LINE, w=3):
    d.line([x0, y0, x1, y1], fill=color, width=w)
    # 箭头
    if abs(x1 - x0) > abs(y1 - y0):
        s = 1 if x1 > x0 else -1
        d.polygon([(x1, y1), (x1 - 12 * s, y1 - 7), (x1 - 12 * s, y1 + 7)], fill=color)
    else:
        s = 1 if y1 > y0 else -1
        d.polygon([(x1, y1), (x1 - 7, y1 - 12 * s), (x1 + 7, y1 - 12 * s)], fill=color)


# ===========================================================================
# 图13：PL 病斑检测器流水线
# ===========================================================================
def fig_detector():
    W, H = 1680, 1180
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)

    # ---- 顶部：数据来源（DDR 里的样本）----
    box(d, 60, 40, 760, 130, IO_F, IO_E)
    d.text((90, 58), "DDR：24 张 256×256 彩色样本（编译进 ELF）", font=f(28, True), fill=IO_E)
    d.text((90, 96), "12 张健康 + 12 张早疫病", font=f(24), fill=BLK)

    # ---- PS 预处理 ----
    box(d, 60, 170, 760, 300, PS_F, PS_E)
    d.text((90, 188), "PS（Cortex-A9）", font=f(28, True), fill=PS_E)
    d.text((90, 226), "① 3×3 均值平滑（逐像素，供 PL 使用）", font=f(24), fill=BLK)
    d.text((90, 262), "② AXI4-Lite 分块上传 256×256 RGB + 显示用灰度图", font=f(24), fill=BLK)

    arrow(d, 410, 130, 410, 168)
    arrow(d, 410, 300, 410, 345)
    d.text((425, 310), "AXI4-Lite（100 MHz）", font=f(22), fill=LINE)

    # ---- PL 检测器大框 ----
    box(d, 60, 350, 1620, 1040, (250, 252, 250), PL_E, r=12, w=3)
    d.text((90, 366), "PL：pl_pest_detector.v（独立状态机，100 MHz AXI 时钟域）", font=f(30, True), fill=PL_E)

    steps = [
        ("① 灰度化 + 5 bit 量化", "两帧 9 bit 帧 RAM 复用，不新增整帧缓存"),
        ("② 31×31 灰度闭运算", "可分离：横 max → 纵 max → 横 min → 纵 min（v2.1，快 22.8 倍）"),
        ("③ 局部对比度 = 闭运算 − 原灰度", "提取“比周围暗”的候选，阈值可在线调"),
        ("④ 叶片掩膜 + 形态学开闭", "排除背景与叶缘，只保留主叶片区域"),
        ("⑤ 连通域标记（有界洪泛）", "FIFO 深度 2048，避免整帧标记内存"),
        ("⑥ 候选验证", "颜色核心 / 四侧绿色组织支持 / 面积 / 宽高比 / 填充率"),
        ("⑦ 排序去重 → 最多 32 框", "帧边界锁存，经 cdc_boxes 送出"),
    ]
    y = 425
    for i, (t1, t2) in enumerate(steps):
        box(d, 100, y, 1580, y + 74, PL_F, (150, 180, 140), r=6, w=2)
        d.text((125, y + 10), t1, font=f(26, True), fill=PL_E)
        d.text((125, y + 44), t2, font=f(22), fill=(60, 60, 60))
        if i < len(steps) - 1:
            arrow(d, 840, y + 74, 840, y + 88, color=(120, 160, 110), w=3)
        y += 88

    # ---- 输出：画框 + HDMI ----
    arrow(d, 840, 1040, 840, 1080)
    box(d, 380, 1085, 1300, 1155, IO_F, IO_E)
    d.text((405, 1100), "box_overlay（像素流比较器）→ TMDS → HDMI 红框", font=f(26, True), fill=IO_E)

    # ---- 右侧：性能标注 ----
    box(d, 1180, 170, 1620, 300, GY_F, GY_E)
    d.text((1200, 184), "资源占用（v2.6）", font=f(24, True), fill=GY_E)
    d.text((1200, 222), "LUT 13821 / FF 8303", font=f(22), fill=BLK)
    d.text((1200, 254), "BRAM 60/60 · DSP 11", font=f(22), fill=BLK)

    out = os.path.join(FIG, "fig7_detector.png")
    im.save(out, "PNG", optimize=True)
    print("OK  " + out, im.size)


# ===========================================================================
# 图14：检测效果对照（v2.2 vs v2.3）
# ===========================================================================
def fig_detect_result():
    src = os.path.join(BUILD, "pl_detector_v23", "localization_before_after.jpg")
    if not os.path.exists(src):
        print("SKIP fig8: 找不到 " + src)
        return
    im = Image.open(src).convert("RGB")
    # 缩到适合报告页宽（14 cm 约 1600 px @ 300dpi，这里给 1500 宽）
    w, h = im.size
    if w > 1500:
        im = im.resize((1500, int(h * 1500 / w)), Image.LANCZOS)
    out = os.path.join(FIG, "fig8_detect_result.jpg")
    im.save(out, "JPEG", quality=92, optimize=True)
    print("OK  " + out, im.size)


if __name__ == "__main__":
    fig_detector()
    fig_detect_result()
