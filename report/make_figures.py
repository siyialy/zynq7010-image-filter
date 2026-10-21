# -*- coding: utf-8 -*-
"""
make_figures.py —— 生成作品报告所需示意图（统一视觉规范）

视觉规范
--------
配色语义：
    蓝 (222,235,247) / 边 (47,85,151)   → 控制与软件（PS、寄存器、程序）
    绿 (226,240,217) / 边 (56,118,29)   → PL 计算单元（滤波、时序、编码）
    橙 (252,228,214) / 边 (197,90,17)   → 外部资源与 I/O（ROM、显示器、PC）
    黄 (255,242,204) / 边 (191,144,0)   → 特殊单元（判断、时钟/同步、多路选择）
    灰 (241,241,241) / 边 (130,130,130) → 异常/次要分支
绘图：
    圆角 + 浅阴影、橙色信号标注、正交连线、连接点圆点、箭头只走空隙
    图中不写"图 N"标题，图号与图注统一由 Word 图注给出
"""
import os
import math
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")
os.makedirs(OUT, exist_ok=True)

FONT   = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"
if not os.path.exists(FONT_B):
    FONT_B = FONT

def F(sz, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, sz)

C_BG      = (255, 255, 255)
C_TEXT    = (25, 25, 25)
C_GREY    = (105, 105, 105)
C_LIGHT   = (232, 232, 232)

PS_F, PS_E   = (222, 235, 247), (47, 85, 151)
PL_F, PL_E   = (226, 240, 217), (56, 118, 29)
IO_F, IO_E   = (252, 228, 214), (197, 90, 17)
CLK_F, CLK_E = (255, 242, 204), (191, 144, 0)
GY_F,  GY_E  = (241, 241, 241), (130, 130, 130)
ORANGE       = (190, 90, 40)
ARROW        = (70, 70, 70)
REGION_F     = (248, 251, 246)
REGION_BLUE  = (245, 249, 254)


def canvas(w, h):
    im = Image.new("RGB", (w, h), C_BG)
    return im, ImageDraw.Draw(im)


def fit_lines(d, text, font, max_w):
    lines, cur = [], ""
    for ch in text:
        if d.textlength(cur + ch, font=font) <= max_w:
            cur += ch
        else:
            lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    return lines


def node(d, x0, y0, x1, y1, title, subs=(), fill=PL_F, edge=PL_E,
         tsize=22, lsize=17, r=14, shadow=True, width=3):
    if shadow:
        d.rounded_rectangle([x0 + 5, y0 + 6, x1 + 5, y1 + 6], radius=r, fill=C_LIGHT)
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill, outline=edge, width=width)
    tf, sf = F(tsize, True), F(lsize)
    tl = fit_lines(d, title, tf, (x1 - x0) - 26)
    sl = []
    for s in subs:
        sl += fit_lines(d, s, sf, (x1 - x0) - 26)
    total = len(tl) * (tsize + 6) + len(sl) * (lsize + 5)
    y = (y0 + y1) / 2 - total / 2 + 2
    for ln in tl:
        d.text(((x0 + x1) / 2, y), ln, font=tf, fill=C_TEXT, anchor="ma")
        y += tsize + 6
    for ln in sl:
        d.text(((x0 + x1) / 2, y), ln, font=sf, fill=C_GREY, anchor="ma")
        y += lsize + 5


def arrow(d, pts, w=3, color=ARROW, head=13):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=color, width=w)
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    ang = math.atan2(y1 - y0, x1 - x0)
    for s in (+1, -1):
        a = ang + s * 0.42
        d.line([(x1, y1), (x1 - head * math.cos(a), y1 - head * math.sin(a))],
               fill=color, width=w)


def dot(d, x, y, r=5, color=ARROW):
    d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def tag(d, x, y, text, sz=19, color=ORANGE, bold=True, bg=False, anchor="lm"):
    f = F(sz, bold)
    if bg:
        tw = d.textlength(text, font=f)
        if anchor in ("lm", "la"):
            d.rectangle([x - 4, y - sz * 0.72, x + tw + 6, y + sz * 0.72], fill=C_BG)
        else:
            d.rectangle([x - tw - 6, y - sz * 0.72, x + 4, y + sz * 0.72], fill=C_BG)
    d.text((x, y), text, font=f, fill=color, anchor=anchor)


def region(d, x0, y0, x1, y1, title, fill, edge, tsize=23):
    d.rounded_rectangle([x0, y0, x1, y1], radius=16, fill=fill, outline=edge, width=3)
    d.text((x0 + 20, y0 + 12), title, font=F(tsize, True), fill=edge, anchor="la")


def save(im, name, top_crop=0):
    if top_crop:
        im = im.crop((0, top_crop, im.width, im.height))
    im.save(os.path.join(OUT, name))
    return name


# ============================================================ 图1 系统总体框图
def fig_system():
    W, H = 1780, 1010
    im, d = canvas(W, H)

    node(d, 40, 120, 520, 470, "Zynq PS（ARM Cortex-A9 @667MHz）",
         ["DDR3 512MB：图像工作区 / 软件基线",
          "UART0 @MIO14/15（115200 8N1）",
          "私有定时器：XTime 计时",
          "裸机 C 程序：控制 + 测量"], PS_F, PS_E, tsize=23)

    node(d, 60, 560, 500, 680, "PC 串口终端", ["0/1/2/3 切模式 · h 帧率 · c 基线"],
         IO_F, IO_E, tsize=21)
    arrow(d, [(280, 558), (280, 474)])
    tag(d, 292, 520, "115200 8N1", 18)

    region(d, 600, 100, 1740, 920, "Zynq PL（FPGA 可编程逻辑）", REGION_F, PL_E)

    node(d, 630, 170, 880, 300, "AXI Interconnect", ["M_AXI_GP0", "100MHz"], CLK_F, CLK_E, tsize=21)
    arrow(d, [(522, 220), (626, 220)])
    tag(d, 540, 196, "AXI4-Lite", 18)

    node(d, 920, 170, 1180, 300, "axil_regs", ["CTRL / MODE / THRESH", "VERSION / FRAME_CNT"],
         PS_F, PS_E, tsize=21)
    arrow(d, [(882, 235), (916, 235)])

    node(d, 1220, 170, 1480, 300, "跨时钟域同步", ["配置：两级触发器", "帧计数：脉冲同步"],
         CLK_F, CLK_E, tsize=21)
    arrow(d, [(1182, 235), (1216, 235)])

    node(d, 630, 380, 900, 520, "video_timing_gen", ["1280×720 @ 60 Hz", "H1650 / V750"],
         PL_F, PL_E, tsize=21)

    node(d, 630, 590, 900, 740, "图像源（二选一）", ["test_pattern 彩条", "image_rom 320×240"],
         IO_F, IO_E, tsize=21)
    arrow(d, [(765, 522), (765, 586)])

    node(d, 950, 610, 1100, 720, "源选择", ["src_sel（KEY1）"], PL_F, PL_E, tsize=20, lsize=16)
    arrow(d, [(902, 665), (946, 665)])

    node(d, 1150, 580, 1470, 760, "img_filter_3x3",
         ["行缓冲 + 9 抽头", "加/乘/移位流水线", "灰度·均值·高斯·Sobel"],
         PL_F, PL_E, tsize=22, width=4)
    arrow(d, [(1102, 665), (1146, 665)])
    arrow(d, [(1350, 302), (1350, 576)])
    tag(d, 1362, 400, "mode[2:0]", 18, bg=True)

    node(d, 1520, 610, 1700, 720, "TMDS 编码", ["OSERDES 10:1"], PL_F, PL_E, tsize=20, lsize=16)
    arrow(d, [(1472, 670), (1516, 670)])

    arrow(d, [(1440, 578), (1440, 470), (1560, 470), (1560, 305)], color=(130, 130, 130))
    dot(d, 1440, 470, 5, (130, 130, 130))
    tag(d, 1572, 420, "frame_start", 17, (120, 120, 120))

    node(d, 60, 780, 500, 900, "HDMI 显示器", ["1280×720 @ 60 Hz"], IO_F, IO_E, tsize=21)
    arrow(d, [(1610, 722), (1610, 950), (530, 950), (530, 860), (504, 860)])
    tag(d, 1200, 962, "TMDS 差分对 · 4 对", 18)

    return save(im, "fig1_system.png")


# ============================================================ 图2 PL 数据通路
def fig_pipeline():
    W, H = 1760, 640
    im, d = canvas(W, H)

    y0, y1 = 210, 360
    items = [
        ("视频时序生成", ["1280×720 @ 60 Hz", "1650×750"], PL_F, PL_E, 210),
        ("图像源", ["彩条 / 照片 ROM"], IO_F, IO_E, 190),
        ("源选择", ["src_sel（KEY1）"], PL_F, PL_E, 170),
        ("3×3 卷积滤波", ["灰度 · 均值", "高斯 · Sobel"], PL_F, PL_E, 210),
        ("输出对齐", ["hs/vs/de", "同延迟输出"], PL_F, PL_E, 170),
        ("TMDS 编码并串", ["OSERDES", "10:1 DDR"], PL_F, PL_E, 190),
        ("HDMI", ["差分对输出"], IO_F, IO_E, 150),
    ]
    gap = 46
    total = sum(i[4] for i in items) + gap * (len(items) - 1)
    x = (W - total) / 2
    centers = []
    for i, (t, subs, fill, edge, w) in enumerate(items):
        node(d, x, y0, x + w, y1, t, subs, fill, edge, tsize=20, lsize=16, width=4 if i == 3 else 3)
        centers.append((x + w / 2, (y0 + y1) / 2))
        if i:
            arrow(d, [(x - gap + 6, (y0 + y1) / 2), (x - 6, (y0 + y1) / 2)])
        x += w + gap

    mx = centers[3][0]
    arrow(d, [(mx, 92), (mx, y0 - 6)])
    tag(d, mx + 14, 96, "mode[2:0]", 19)
    tag(d, mx + 14, 126, "（来自 axil_regs，经跨时钟域同步）", 16, C_GREY, bold=False)

    marks = [
        (centers[1][0], "延迟 4 拍"),
        (centers[2][0], "对齐后送入"),
        (centers[3][0], "延迟 8 拍（6 级流水）"),
        (centers[4][0], "hs/vs/de 同步延迟 12 拍"),
    ]
    for cx, txt in marks:
        tag(d, cx, y1 + 34, txt, 17, C_GREY, bold=False, anchor="ma")

    d.text((70, 470), "同步信号 hs / vs / de 与像素数据同步延迟相同的拍数，保证像素与消隐区严格对齐",
           font=F(19), fill=C_GREY, anchor="la")
    d.text((70, 505), "总延迟 LAT = 12 拍 = 160ns（滤波器 8 拍 + 图像源 4 拍）",
           font=F(19), fill=C_GREY, anchor="la")
    d.text((70, 540), "整条链路每拍推进一个像素，吞吐率与画面内容无关，延迟恒定",
           font=F(19), fill=C_GREY, anchor="la")

    return save(im, "fig2_pipeline.png")


# ============================================================ 图3 卷积流水线
def fig_filter():
    W, H = 1760, 860
    im, d = canvas(W, H)

    stages = [
        ("S0", "坐标计算", ["x/SCALE", "y/SCALE"], 190),
        ("S1", "RGB→灰度", ["77R+150G+29B", ">> 8"], 200),
        ("S2~S3", "行缓存 + 抽头", ["2 行 LUTRAM", "9 个抽头寄存器"], 220),
        ("S4", "抽头寄存", ["w00 ~ w22", "同时有效"], 180),
        ("S5", "加法树（4 组并行）", ["sum9 / gsum", "Gx / Gy"], 230),
        ("S6", "乘 · 移 · 绝对值", ["均值 ×57>>9", "高斯 >>4", "Sobel |Gx|+|Gy|"], 240),
    ]
    y0, y1 = 160, 320
    gap = 52
    total = sum(w for _, _, _, w in stages) + gap * (len(stages) - 1)
    x = (W - total) / 2
    for i, (st, t, subs, w) in enumerate(stages):
        node(d, x, y0, x + w, y1, t, subs, PL_F, PL_E, tsize=20, lsize=16)
        bf = F(18, True)
        bw = d.textlength(st, font=bf) + 22
        d.rounded_rectangle([x + w / 2 - bw / 2, y0 - 36, x + w / 2 + bw / 2, y0 - 6],
                            radius=12, fill=CLK_F, outline=CLK_E, width=2)
        d.text((x + w / 2, y0 - 21), st, font=bf, fill=(140, 100, 0), anchor="mm")
        if i:
            arrow(d, [(x - gap + 6, (y0 + y1) / 2), (x - 6, (y0 + y1) / 2)])
        x += w + gap

    # ---- 下部：左侧邻域与卷积核，右侧 mode 选择与输出 ----
    band_y = 450
    d.text((80, band_y - 34), "3×3 邻域", font=F(20, True), fill=C_TEXT, anchor="la")
    gx, gy, cell = 80, band_y, 46
    names = ["w00", "w01", "w02", "w10", "w11", "w12", "w20", "w21", "w22"]
    for r in range(3):
        for c in range(3):
            d.rectangle([gx + c * cell, gy + r * cell, gx + (c + 1) * cell, gy + (r + 1) * cell],
                        fill=CLK_F if (r, c) == (1, 1) else (250, 250, 245),
                        outline=(150, 150, 150), width=2)
            d.text((gx + c * cell + cell / 2, gy + r * cell + cell / 2), names[r * 3 + c],
                   font=F(15), fill=C_TEXT, anchor="mm")

    kernels = [
        ("均值 1/9", ["1  1  1", "1  1  1", "1  1  1"]),
        ("高斯 1/16", ["1  2  1", "2  4  2", "1  2  1"]),
        ("Sobel Gx", ["−1  0  +1", "−2  0  +2", "−1  0  +1"]),
        ("Sobel Gy", ["−1  −2  −1", "0   0   0", "+1  +2  +1"]),
    ]
    kx = 310
    for i, (name, rows) in enumerate(kernels):
        bx = kx + i * 210
        d.text((bx, band_y - 34), name, font=F(18, True), fill=ORANGE, anchor="la")
        for r, rowtxt in enumerate(rows):
            d.text((bx, band_y + 6 + r * 34), rowtxt, font=F(17), fill=C_TEXT, anchor="la")

    # 右侧：4 选 1 与输出
    ox = 1330
    node(d, ox - 190, band_y - 30, ox + 190, band_y + 86, "mode 选择（4 选 1）",
         ["0 灰度 · 1 均值 · 2 高斯 · 3 Sobel"], CLK_F, CLK_E, tsize=20, lsize=16)
    node(d, ox - 190, band_y + 150, ox + 190, band_y + 260, "输出寄存",
         ["与 de / hs / vs 对齐后送 TMDS"], PL_F, PL_E, tsize=20, lsize=16)
    arrow(d, [(ox, band_y + 90), (ox, band_y + 146)])

    # S6 出口向下接到 mode 选择
    last_right = x - gap
    arrow(d, [(last_right - 120, y1 + 6), (last_right - 120, y1 + 46),
              (ox, y1 + 46), (ox, band_y - 34)])

    d.text((80, 790), "关键路径最长一级约 6.5ns，在 75MHz（13.33ns 周期）下时序余量充足（实测 WNS +3.447ns）",
           font=F(18), fill=C_GREY, anchor="la")

    return save(im, "fig3_filter.png")


# ============================================================ 图4 跨时钟域
def fig_cdc():
    W, H = 1680, 760
    im, d = canvas(W, H)

    region(d, 60, 90, 760, 620, "AXI 时钟域（100MHz · FCLK_CLK0）", REGION_BLUE, PS_E, 22)
    region(d, 900, 90, 1620, 620, "像素时钟域（75MHz · clk_wiz 输出）", REGION_F, PL_E, 22)

    node(d, 100, 170, 470, 300, "axil_regs", ["mode / threshold / filter_en"], PS_F, PS_E, tsize=20, lsize=16)
    node(d, 100, 360, 470, 480, "帧计数器", ["32bit，在本域内递增"], CLK_F, CLK_E, tsize=20, lsize=16)

    node(d, 950, 170, 1290, 300, "两级触发器同步", ["meta → sync", "ASYNC_REG = TRUE"], PL_F, PL_E, tsize=20, lsize=16)
    node(d, 950, 360, 1290, 480, "脉冲同步 + 边沿检测", ["toggle 翻转 → 同步 → tick"], PL_F, PL_E, tsize=20, lsize=16)
    node(d, 1340, 170, 1580, 480, "视频流水线", ["mode 生效", "每帧计数"], PL_F, PL_E, tsize=20, lsize=16)

    arrow(d, [(470, 235), (760, 235), (760, 150), (900, 150), (900, 235), (946, 235)])
    tag(d, 556, 205, "配置位（慢变）", 18, bg=True)
    tag(d, 556, 236, "每 bit 打两拍", 16, C_GREY, bold=False, bg=True)

    arrow(d, [(900, 420), (470, 420)])
    tag(d, 556, 392, "frame_start 脉冲", 18, bg=True)
    tag(d, 556, 448, "（像素域 → AXI 域）", 16, C_GREY, bold=False, bg=True)

    arrow(d, [(1292, 235), (1336, 235)])
    arrow(d, [(1292, 420), (1336, 420)])

    d.text((70, 650), "① 配置类信号只在人机操作时变化，用两级触发器同步即可，最坏情况是某一帧用错模式",
           font=F(18), fill=C_TEXT, anchor="la")
    d.text((70, 682), "② 帧计数方向相反且为 32 位，直接跨域读会读到进位中间值，故改为“翻转标志 + 脉冲同步 + 本地计数”",
           font=F(18), fill=C_TEXT, anchor="la")
    d.text((70, 714), "③ 不加 set_clock_groups 时工具会把异步路径当同步路径分析，报出 −0.29ns 假违例",
           font=F(18), fill=C_TEXT, anchor="la")

    return save(im, "fig4_cdc.png")


# ============================================================ 图5 软件流程图
def fig_flow():
    W, H = 1600, 1420
    im, d = canvas(W, H)

    MAIN_X, MAIN_W = 420, 470
    mx0, mx1 = MAIN_X - MAIN_W / 2, MAIN_X + MAIN_W / 2
    d.rounded_rectangle([mx0 + 40, 56, mx1 - 40, 132], radius=38, fill=(209, 231, 209),
                        outline=(56, 118, 29), width=3)
    d.text((MAIN_X, 94), "上电 / main()  启动", font=F(24, True), fill=C_TEXT, anchor="mm")

    y = 132
    steps = [
        ("初始化 BSP", ["UART0 · 私有定时器 · D-Cache"]),
        ("写 PL 寄存器（读回校验，最多重试 8 次）", ["CTRL=1、MODE=Sobel"]),
        ("读 VERSION 寄存器", ["期望 0x00010000，确认 PL 在位"]),
        ("打印菜单，等待串口字符", ["阻塞于 inbyte()"]),
    ]
    boxes = []
    for t, sub in steps:
        y0 = y + 52
        h = 96 if (sub and len(t) < 16) else 108
        node(d, mx0, y0, mx1, y0 + h, t, sub, PS_F, PS_E, tsize=23, lsize=18)
        boxes.append((y0, y0 + h))
        arrow(d, [(MAIN_X, y + 3), (MAIN_X, y0 - 5)])
        y = y0 + h

    dy, dh, dw = y + 62, 62, 96
    d.polygon([(MAIN_X, dy), (MAIN_X - dw, dy + dh), (MAIN_X, dy + 2 * dh), (MAIN_X + dw, dy + dh)],
              fill=CLK_F, outline=CLK_E, width=3)
    d.text((MAIN_X, dy + dh - 4), "命令?", font=F(23, True), fill=C_TEXT, anchor="mm")
    arrow(d, [(MAIN_X, y + 3), (MAIN_X, dy - 5)])

    cmds = [("0 ~ 3", "设置滤波模式", "写 MODE，读回确认"),
            ("h", "测量硬件帧率", "帧计数 + 定时器"),
            ("c", "软件基线对比", "四种算法 CPU 耗时"),
            ("i", "打印寄存器", "6 个寄存器全部回读"),
            ("其他", "提示未知命令", "提示按 m 查看菜单")]
    n = len(cmds)
    bw, gap = 258, 42
    total = n * bw + (n - 1) * gap
    bx0 = (W - total) / 2
    centers = [bx0 + i * (bw + gap) + bw / 2 for i in range(n)]

    bar_y = dy + 2 * dh + 66
    d.line([(centers[0], bar_y), (centers[-1], bar_y)], fill=ARROW, width=3)
    d.line([(MAIN_X, dy + 2 * dh + 4), (MAIN_X, bar_y)], fill=ARROW, width=3)
    dot(d, MAIN_X, bar_y)

    for i, (key, act, note) in enumerate(cmds):
        cx = centers[i]
        arrow(d, [(cx, bar_y + 3), (cx, bar_y + 44)])
        tag(d, cx, bar_y - 18, key, 20, ORANGE, anchor="mm", bg=True)

    act_y0, act_h = bar_y + 48, 118
    for i, (key, act, note) in enumerate(cmds):
        cx = centers[i]
        fill, edge = (PL_F, PL_E) if i < 4 else (GY_F, GY_E)
        node(d, cx - bw / 2, act_y0, cx + bw / 2, act_y0 + act_h, act, [note],
             fill, edge, tsize=21, lsize=17)

    merge_y = act_y0 + act_h + 46
    for cx in centers:
        d.line([(cx, act_y0 + act_h + 3), (cx, merge_y)], fill=ARROW, width=3)
    d.line([(centers[0], merge_y), (centers[-1], merge_y)], fill=ARROW, width=3)
    for i in range(1, n - 1):
        dot(d, centers[i], merge_y)

    ret_x = W - 70
    d.line([(centers[-1], merge_y), (ret_x, merge_y)], fill=ARROW, width=3)
    d.line([(ret_x, merge_y), (ret_x, boxes[3][0] + 52)], fill=ARROW, width=3)
    arrow(d, [(ret_x, boxes[3][0] + 52), (mx1 + 5, boxes[3][0] + 52)])
    d.text((centers[0] - 30, merge_y + 26), "各分支处理完成后返回，等待下一个命令",
           font=F(19), fill=C_GREY, anchor="la")

    return save(im, "fig5_flow.png", top_crop=30)


# ============================================================ 图6 加速比
def fig_speed():
    W, H = 1520, 880
    im, d = canvas(W, H)

    data = [("灰度", 166), ("均值 3×3", 177), ("高斯 3×3", 174), ("Sobel", 178)]
    hw = 13.33
    x0, y0 = 170, 700
    plot_w, plot_h = 1210, 540
    maxv = 200.0

    for gv in range(0, 201, 40):
        yy = y0 - gv / maxv * plot_h
        d.line([(x0, yy), (x0 + plot_w, yy)], fill=(228, 228, 228), width=2)
        d.text((x0 - 18, yy), str(gv), font=F(19), fill=C_GREY, anchor="rm")
    d.line([(x0, y0), (x0 + plot_w, y0)], fill=(90, 90, 90), width=3)
    d.line([(x0, y0), (x0, y0 - plot_h)], fill=(90, 90, 90), width=3)
    d.text((x0 - 100, y0 - plot_h - 14), "ns / 像素", font=F(21, True), fill=C_TEXT, anchor="la")

    slot = plot_w / len(data)
    bw = 88
    for i, (name, sw) in enumerate(data):
        cx = x0 + slot * i + slot / 2
        h1 = sw / maxv * plot_h
        d.rounded_rectangle([cx - bw - 10, y0 - h1, cx - 10, y0], radius=8,
                            fill=(150, 190, 230), outline=PS_E, width=2)
        d.text((cx - bw / 2 - 10, y0 - h1 - 26), str(sw), font=F(23, True), fill=PS_E, anchor="mm")
        h2 = hw / maxv * plot_h
        d.rounded_rectangle([cx + 10, y0 - h2, cx + bw + 10, y0], radius=8,
                            fill=(150, 200, 140), outline=PL_E, width=2)
        d.text((cx + bw / 2 + 10, y0 - h2 - 26), "13.3", font=F(23, True), fill=PL_E, anchor="mm")
        d.text((cx, y0 + 34), name, font=F(22, True), fill=C_TEXT, anchor="mm")
        d.text((cx, y0 + 72), "加速 %.1f×" % (sw / hw), font=F(22, True), fill=ORANGE, anchor="mm")

    d.rounded_rectangle([x0 + 30, 110, x0 + 74, 146], radius=6, fill=(150, 190, 230), outline=PS_E, width=2)
    d.text((x0 + 88, 128), "软件实现（Cortex-A9，-O2 优化）", font=F(20), fill=C_TEXT, anchor="lm")
    d.rounded_rectangle([x0 + 470, 110, x0 + 514, 146], radius=6, fill=(150, 200, 140), outline=PL_E, width=2)
    d.text((x0 + 528, 128), "硬件实现（PL，每拍 1 像素 @75MHz）", font=F(20), fill=C_TEXT, anchor="lm")

    d.text((x0, 830), "注：软件为 320×240（76800 像素）逐帧计时；硬件为同一算法、同一帧；数据来自板上实测",
           font=F(18), fill=C_GREY, anchor="la")

    return save(im, "fig6_speed.png")


if __name__ == "__main__":
    for fn in (fig_system, fig_pipeline, fig_filter, fig_cdc, fig_flow, fig_speed):
        try:
            print("OK  ", fn())
        except Exception as e:
            import traceback
            print("FAIL", fn.__name__, "->", type(e).__name__, e)
            traceback.print_exc()
