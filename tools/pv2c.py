#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
pv2c.py —— 把 PlantVillage 样本转成 C 头文件（给 ARM 程序直接烧进 DDR）

输出：ps_app/pv_samples.h
  #define PV_N   24            // 样本数（12 健康 + 12 病叶）
  #define PV_W   256
  #define PV_H   256
  pv_label[n]          0=健康  1=早疫病
  pv_rgb[n][y*PV_W*3 + x*3 + {0,1,2}]   R,G,B 三通道

为什么存彩色：
  早疫病的判据是「褐色」，即 R > G。灰度化会把这个信息扔掉，
  实测灰度判据在健康叶和病叶上完全重叠（详见 docs 里的实验记录）。
"""
import os
import sys
import glob
import numpy as np
from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = True

SRC = r"D:\FPGA比赛\report\photos\samples\pv"
OUT = r"D:\FPGA比赛\ps_app\pv_samples.h"

PV_N_PER_CLASS = 12
PV_W = 256
PV_H = 256


def leafmask(a, thr=45):
    edge = np.concatenate([a[0, :].reshape(-1, 3), a[-1, :].reshape(-1, 3),
                           a[:, 0].reshape(-1, 3), a[:, -1].reshape(-1, 3)])
    bg = np.median(edge, axis=0)
    return np.sqrt(((a - bg) ** 2).sum(axis=2)) > thr


def brown_frac(a):
    """褐色面积占比（与 C 端算法一致，用于挑选样本）"""
    R = a[..., 0].astype(np.int16)
    G = a[..., 1].astype(np.int16)
    B = a[..., 2].astype(np.int16)
    V = ((R * 77 + G * 150 + B * 29) >> 8)
    leaf = leafmask(a.astype(np.float64))
    if leaf.sum() < 400:
        leaf = np.ones(V.shape, bool)
    return float((leaf & ((R - G) > 15) & (V < 140)).sum()) / max(1, leaf.sum()) * 100


def pick(cls):
    files = sorted(glob.glob(os.path.join(SRC, cls, "*.JPG")))
    scored = []
    for f in files:
        try:
            a = np.asarray(Image.open(f).convert("RGB"), dtype=np.int16)
            scored.append((brown_frac(a), f))
        except Exception:
            pass
    scored.sort(key=lambda x: x[0])
    n = len(scored)
    idx = [round(i * (n - 1) / (PV_N_PER_CLASS - 1)) for i in range(PV_N_PER_CLASS)]
    return [scored[i] for i in idx]


def main():
    picks = [("Tomato_healthy", 0), ("Tomato_Early_blight", 1)]
    names, labels, blobs = [], [], []

    for cls, lab in picks:
        for frac, f in pick(cls):
            im = Image.open(f).convert("RGB").resize((PV_W, PV_H), Image.LANCZOS)
            names.append(os.path.basename(f))
            labels.append(lab)
            blobs.append(np.asarray(im, dtype=np.uint8))
            print("  %-40s %s  褐色 %5.2f%%" % (os.path.basename(f)[:38],
                                                "病叶" if lab else "健康", frac))

    data = np.stack(blobs)          # (N, 256, 256, 3)
    n = data.shape[0]

    with open(OUT, "w", encoding="utf-8", newline="\n") as fp:
        fp.write("// 本文件由 tools/pv2c.py 自动生成，不要手工修改\n")
        fp.write("// 数据来源：PlantVillage 数据集（spMohanty/PlantVillage-Dataset）\n")
        fp.write("// 12 张番茄健康叶片 + 12 张番茄早疫病叶片，均为 256x256 彩色\n\n")
        fp.write("#ifndef PV_SAMPLES_H\n#define PV_SAMPLES_H\n\n")
        fp.write("#define PV_N %d\n#define PV_W %d\n#define PV_H %d\n\n" % (n, PV_W, PV_H))

        fp.write("// 0 = 健康，1 = 早疫病\n")
        fp.write("static const unsigned char pv_label[PV_N] = {\n")
        for i in range(0, n, 12):
            fp.write("    " + ", ".join(str(v) for v in labels[i:i + 12]) + ",\n")
        fp.write("};\n\n")

        fp.write("// 样本文件名（串口打印用）\n")
        fp.write("static const char *const pv_name[PV_N] = {\n")
        for nm in names:
            fp.write('    "%s",\n' % nm[:20])
        fp.write("};\n\n")

        fp.write("// RGB 像素数据：pv_rgb[n][(y*PV_W + x)*3 + c]\n")
        fp.write("static const unsigned char pv_rgb[PV_N][PV_W * PV_H * 3] = {\n")
        flat = data.reshape(n, -1)
        for i in range(n):
            fp.write("  {  // %d: %s (%s)\n" % (i, names[i][:24], "blight" if labels[i] else "healthy"))
            row = flat[i]
            for j in range(0, len(row), 32):
                fp.write("    " + ",".join("%d" % b for b in row[j:j + 32]) + ",\n")
            fp.write("  },\n")
        fp.write("};\n\n#endif // PV_SAMPLES_H\n")

    size_mb = os.path.getsize(OUT) / 1024 / 1024
    print("\n生成: %s" % OUT)
    print("  样本数: %d（健康 %d / 病叶 %d）" % (n, labels.count(0), labels.count(1)))
    print("  像素数据: %.2f MB" % (n * PV_W * PV_H * 3 / 1024 / 1024))
    print("  头文件: %.1f MB（文本形式）" % size_mb)


if __name__ == "__main__":
    main()
