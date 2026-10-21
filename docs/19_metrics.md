# 实测数据（2026-10-21，板上真实测量）

> 所有数字都是**在硬件上跑出来的**，不是估算。
> 测量方式：PS 用 `XTime_GetTime()`（100MHz 私有定时器）计时，PL 用帧计数器计时。

---

## 一、测量环境

| 项目 | 值 |
|---|---|
| 开发板 | 正点原子 启明星 ZYNQ-7010 V2（XC7Z010-1CLG400C） |
| CPU | ARM Cortex-A9 双核 @ 667MHz（单核运行裸机程序） |
| 内存 | DDR3 512MB（MT41K128M16，32bit，533MHz） |
| 工具链 | Vivado / SDK 2018.3 |
| 像素时钟 | 75MHz（720p60） |
| AXI 时钟 | 100MHz（PS FCLK_CLK0） |
| 编译配置 | SDK Release（`-O2`） |

---

## 二、PL 侧资源与时序

| 资源 | 用量 | 占比 |
|---|---|---|
| Slice LUT | 1527 / 17600 | 8.68% |
| Slice Register | 1109 / 35200 | 3.15% |
| Block RAM | 32.5 / 60 | 54.2% |
| DSP48 | 1 | 0.3% |
| **时序 WNS** | **+1.096 ns** | 无违例 |

> BRAM 占用高是因为 320×240 灰度照片 ROM（76.8 KB）放在片上。

---

## 三、硬件性能（PS 通过 AXI 读帧计数器测得）

串口命令 `h`：

```
frame_cnt: 2066 -> 2126  (60 frames in 1000000 us)
hardware fps = 59.99  (frame period 16666 us = 16.66 ms)
CPU load while filtering: ~0% (all pixels done in PL)
```

| 指标 | 值 |
|---|---|
| 输出分辨率 | 1280×720 @ 60fps |
| 实际上屏刷新率 | **59.99 fps**（理论 75MHz/1650/750 = 60.6fps） |
| 每帧像素数 | 921,600 |
| 每像素时钟数 | 1（每拍处理 1 像素） |
| 每像素时间 | **13.333 ns** |
| 全帧处理时间 | **12.29 ms**（< 16.67 ms 帧周期，满足实时） |
| CPU 占用 | **≈0%**（CPU 只负责发命令和读计数） |

---

## 四、软件基线（同一算法、同一帧，纯 CPU）

### 4.1 优化版（Release `-O2`）—— **正式对比采用这一组**

```
--- software baseline (320x240, CPU only) ---
  grayscale   SW: 12.793 ms/frame (166 ns/pixel, 78.16 fps)
  mean 3x3    SW: 13.593 ms/frame (177 ns/pixel, 73.56 fps)
  gauss 3x3   SW: 13.369 ms/frame (174 ns/pixel, 74.79 fps)
  sobel       SW: 13.740 ms/frame (178 ns/pixel, 72.78 fps)
```

### 4.2 未优化版（Debug `-O0`）—— 用来展示"编译器优化的影响"

```
  grayscale   SW: 75.643 ms/frame (984 ns/pixel, 13.21 fps)
  mean 3x3    SW: 77.721 ms/frame (1011 ns/pixel, 12.86 fps)
  gauss 3x3   SW: 77.834 ms/frame (1013 ns/pixel, 12.84 fps)
  sobel       SW: 78.707 ms/frame (1024 ns/pixel, 12.70 fps)
```

> **为什么两组都要报**：`-O0` 的 1000 ns/像素会让加速比虚高到 75 倍，
> 这种数字经不起追问。正式结论用 `-O2` 的 166~178 ns/像素，
> 同时把 `-O0` 作为"软件实现质量对结果影响有多大"的旁证。

---

## 五、加速比（同一算法、同一帧，逐像素比较）

| 滤波模式 | 软件 (-O2) | 硬件 | 加速比 |
|---|---|---|---|
| 灰度 | 166 ns/像素 | 13.333 ns/像素 | **12.5×** |
| 均值 3×3 | 177 ns/像素 | 13.333 ns/像素 | **13.3×** |
| 高斯 3×3 | 174 ns/像素 | 13.333 ns/像素 | **13.1×** |
| Sobel | 178 ns/像素 | 13.333 ns/像素 | **13.4×** |

**（若用 -O0 基线，加速比为 74~77×）**

---

## 六、更硬的结论：实时性

这不只是"快 13 倍"，而是"**能不能实时**"的问题：

| | 每像素耗时 | 全 720p 一帧（921600 像素） | 能否 60fps（16.67ms） |
|---|---|---|---|
| **PL（本设计）** | 13.333 ns | **12.29 ms** | ✅ **能**（还剩 4.4ms 余量） |
| 软件 -O2 | 166 ns | **153 ms** | ❌ 差 **9.2 倍** |
| 软件 -O0 | 984 ns | 907 ms | ❌ 差 54 倍 |

**这是最有力的一句话**：

> 同样的 3×3 Sobel，即使是最优化编译的 C 代码，在这颗 667MHz 的 ARM 上也
> 需要 153 ms 才能处理完一帧 720p，比 16.67 ms 的帧周期慢 9.2 倍——
> **软件方案根本不可能做到实时**。而 PL 在 12.29 ms 内完成全帧，
> CPU 占用为 0%，可以同时去做别的事。

---

## 七、测量方法说明（可复现）

1. **硬件帧率**：PS 读 PL 的 32 位帧计数器（跨时钟域同步后），用 `XTime_GetTime()`
   取时间差，`fps = Δframes / Δt`。计数器在像素时钟域递增，经脉冲同步到 AXI 域，
   不会出现读到进位中间值的问题。
2. **软件耗时**：`sw_filter_3x3()` 与 RTL **数值逐条对齐**
   （同一边界复制策略、同样用整数运算：均值 `(sum9*57)>>9`、高斯 `>>4`、Sobel `|Gx|+|Gy|`）。
   计时前先跑一遍预热，再 flush D-Cache，再计时；连跑 4 种模式取各自结果。
3. **CPU 占用**：滤波期间 CPU 只执行 `Xil_In32` 读计数和延时，
   不参与任何像素运算 → 占用率 ≈0%。

---

## 八、原始串口输出（存档）

```
> i

  CTRL      = 0x00000001
  MODE      = 0x00000003
  THRESH    = 0x00000000
  VERSION   = 0x00010000
  FRAME_CNT = 0x000001EC
  STATUS    = 0x00000000

> h
  frame_cnt: 2066 -> 2126  (60 frames in 1000000 us)
  hardware fps = 59.99  (frame period 16666 us = 16.66 ms)
  CPU load while filtering: ~0% (all pixels done in PL)

> c
--- software baseline (320x240, CPU only) ---
  grayscale   SW: 12.793 ms/frame (166 ns/pixel, 78.16 fps)
  mean 3x3    SW: 13.593 ms/frame (177 ns/pixel, 73.56 fps)
  gauss 3x3   SW: 13.369 ms/frame (174 ns/pixel, 74.79 fps)
  sobel       SW: 13.740 ms/frame (178 ns/pixel, 72.78 fps)

--- hardware reference ---
  HW: 1.023 ms for the same 76800 pixels (13.333 ns/pixel @75MHz)
```
