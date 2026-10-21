#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bmp2coe.py —— 把任意图片转成 Vivado BRAM 初始化文件 (.coe)

用途：你没有摄像头，我们就用"图片 ROM"当图像源 —— 把一张实拍图烧进 PL 的
BRAM，上电就能显示，滤波前后对比最直观。

用法：
    # 灰度（省 BRAM，推荐）
    python bmp2coe.py photo.jpg -o image_gray.coe --width 320 --height 240 --gray

    # 彩色 RGB888
    python bmp2coe.py photo.jpg -o image_rgb.coe --width 320 --height 240

输出：
    image_gray.coe        给 Vivado 的存储器初始化文件
    image_gray_preview.png 实际会被存进 BRAM 的图（缩放后），先看一眼对不对

【容量提醒：XC7Z010 只有 2.1 Mb BRAM（约 58 个 36Kb 块）】
    640x480 灰度   = 2.46 Mb  ✗ 装不下
    320x240 灰度   = 0.61 Mb  ✓ 约 17 块，推荐
    320x240 彩色   = 1.84 Mb  ✓ 约 51 块，勉强（会把 BRAM 用光）
    256x192 灰度   = 0.39 Mb  ✓ 约 11 块，最省
所以推荐 320x240 灰度，RTL 里用"像素复制"放大到 640x480 显示。
"""

import argparse
import os
import sys

# Windows 控制台默认 GBK，避免打印特殊符号时报 UnicodeEncodeError
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    from PIL import Image
except ImportError:
    print("缺少 Pillow，请先安装：pip install Pillow")
    sys.exit(1)

BRAM36_BITS = 36 * 1024          # 一块 BRAM36 = 36864 bit
BRAM_TOTAL_BLOCKS = 60           # XC7Z010 约 60 块 BRAM36（2.1 Mb）


def load_and_fit(path, width, height, gray):
    im = Image.open(path)
    im = im.convert("L" if gray else "RGB")
    src_w, src_h = im.size

    # 等比缩放 + 居中裁剪（不拉伸变形）
    scale = max(width / src_w, height / src_h)
    new_w, new_h = int(round(src_w * scale)), int(round(src_h * scale))
    im = im.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - width) // 2
    top = (new_h - height) // 2
    im = im.crop((left, top, left + width, top + height))
    return im, (src_w, src_h)


def to_coe(im, out_path, gray):
    width, height = im.size
    px = im.load()
    words = []
    if gray:
        for y in range(height):
            for x in range(width):
                words.append("%02X" % px[x, y])
        bits_per_px = 8
    else:
        for y in range(height):
            for x in range(width):
                r, g, b = px[x, y]
                words.append("%02X%02X%02X" % (r, g, b))
        bits_per_px = 24

    with open(out_path, "w", encoding="ascii", newline="\n") as f:
        f.write("; bmp2coe.py generated\n")
        f.write("; size = %dx%d, %d bit/pixel\n" % (width, height, bits_per_px))
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        # 一行一个像素便于 diff；文件大一点但可读
        for i, w in enumerate(words):
            if i == len(words) - 1:
                f.write(w + ";\n")
            else:
                f.write(w + ",\n")

    # 同时输出 .mem（Verilog $readmemh 直接能读，一行一个像素，无文件头）
    mem_path = os.path.splitext(out_path)[0] + ".mem"
    with open(mem_path, "w", encoding="ascii", newline="\n") as f:
        for w in words:
            f.write(w + "\n")

    total_bits = width * height * bits_per_px
    return total_bits, bits_per_px


def main():
    ap = argparse.ArgumentParser(description="图片转 Vivado .coe")
    ap.add_argument("input", help="输入图片 (jpg/png/bmp)")
    ap.add_argument("-o", "--output", help="输出 .coe 路径")
    ap.add_argument("--width",  type=int, default=320)
    ap.add_argument("--height", type=int, default=240)
    ap.add_argument("--gray", action="store_true", help="转灰度 8bit（推荐）")
    args = ap.parse_args()

    if not os.path.exists(args.input):
        print("找不到文件:", args.input)
        sys.exit(1)

    out = args.output or (os.path.splitext(args.input)[0] + "_image.coe")

    im, src_size = load_and_fit(args.input, args.width, args.height, args.gray)
    total_bits, bits = to_coe(im, out, args.gray)

    preview = os.path.splitext(out)[0] + "_preview.png"

    # 预览图保存：如果这个文件正被「照片」等看图软件打开着，Windows 会拒绝写入
    # （报 OSError: [Errno 22] Invalid argument）。这时自动换个带时间戳的名字。
    try:
        im.save(preview)
    except OSError as e:
        import time
        alt = "%s_%s.png" % (os.path.splitext(preview)[0], time.strftime("%H%M%S"))
        try:
            im.save(alt)
            print("[提示] 原预览图被占用（%s），已改存为: %s" % (e.__class__.__name__, alt))
            print("       建议关掉正在看图的「照片」窗口，否则每次都会生成新文件。")
            preview = alt
        except OSError:
            print("[警告] 预览图保存失败，但 .coe/.mem 已经生成，不影响使用")
            preview = None

    blocks = (total_bits + BRAM36_BITS - 1) // BRAM36_BITS
    print("原图尺寸      : %dx%d" % src_size)
    print("存储尺寸      : %dx%d, %d bit/像素" % (args.width, args.height, bits))
    print("总容量        : %.2f Mb" % (total_bits / 1024.0 / 1024.0))
    print("BRAM36 占用   : 约 %d / %d 块 (%.0f%%)"
          % (blocks, BRAM_TOTAL_BLOCKS, 100.0 * blocks / BRAM_TOTAL_BLOCKS))
    print("输出 .coe     : %s" % out)
    print("预览图        : %s" % (preview if preview else "(保存失败)"))

    if blocks > BRAM_TOTAL_BLOCKS * 0.85:
        print("[WARN] 容量超过 85%, 建议减小尺寸(如 256x192)或改用 --gray")
    elif blocks <= BRAM_TOTAL_BLOCKS:
        print("[OK] 容量合适，可以烧进 BRAM")

    print()
    print("RTL 里这样读（同步读，1 拍延迟）：")
    print("    reg [%d:0] rom [0:%d];" % (bits - 1, args.width * args.height - 1))
    print("    initial $readmemh(\"%s\", rom);   // 或用 .coe 生成 IP"
          % os.path.basename(out))


if __name__ == "__main__":
    main()
