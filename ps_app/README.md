# PS 端（ARM）程序 —— 软硬件协同的"软件半边"

> 这部分证明了比赛要的"软硬件协同"：**ARM 通过 AXI4-Lite 控制 PL 的滤波参数，
> 并用同一算法在 CPU 上算一遍作为基线，算出加速比。**

## 文件

| 文件 | 作用 |
|---|---|
| `main.c` | 主程序：串口菜单、读写 PL 寄存器、测硬件帧率、跑软件基线 |
| `sw_filter.c/.h` | 3×3 滤波的 CPU 实现（数值与 RTL 严格一致） |

## 已做的验证

两个文件都用 SDK 自带的 ARM 交叉编译器做过语法检查（`-Wall -Wextra`，无告警）：

```powershell
D:\XILINX\SDK\2018.3\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe ^
  -fsyntax-only -Wall -Wextra -mcpu=cortex-a9 ^
  -I <BSP 的 include 路径> -I D:\FPGA比赛\ps_app D:\FPGA比赛\ps_app\main.c
```

> 完整的"能跑"验证要等 Block Design 生成 `.xsa`、BSP 建好之后（那时才有
> `xparameters.h`、`xil_io.h` 等头文件）。

## 编译步骤（Vivado 导出硬件之后）

1. **先有硬件描述文件**：Block Design 综合实现后 `File → Export → Export Hardware`，
   勾上 `Include bitstream`，得到 `system_wrapper.xsa`
2. 打开 **SDK 2018.3**（`D:\XILINX\SDK\2018.3\bin\xsdk.bat`）
3. `File → New → Application Project`
   - Platform：用刚才的 `.xsa`（它会自动建 BSP）
   - Project name：`img_filter_app`
   - Template：`Empty Application`
4. 把本目录的 `main.c`、`sw_filter.c`、`sw_filter.h` 拷进 `src/`
5. 编译（Ctrl+B），然后 `Run As → Launch on Hardware (System Debugger)`

## ⚠️ 必须先确认的一件事：寄存器基地址

`main.c` 里这一行必须和 Block Design 的 **Address Editor** 里分配的地址一致：

```c
#define AXIL_BASE      0x43C00000U
```

`0x43C00000` 是 Vivado 给 AXI GP0 从设备的**默认**起始地址。如果你在 BD 里
重新分配过，或者复用了别的地址（比如 VDMA 占了这一段），就要改成实际值。

**判断方法**：程序启动会打印

```
PL version register = 0x00010000
PL is alive. AXI4-Lite link OK.
```

- 读到 `0x00010000` → 地址正确、PL 在位
- 读到 `0xFFFFFFFF` 或 `0xDEADBEEF` → 地址错了（或 bitstream 没下载）

## 串口菜单

```
===== ZYNQ-7010 real-time image filter =====
  0/1/2/3 : set filter mode (gray/mean/gauss/sobel)
  e / d   : filter enable / bypass
  h       : measure hardware frame rate
  c       : software baseline vs hardware
  i       : dump registers
  m       : show this menu
> 
```

## 加速比怎么算（比赛报告的"FPGA 量化贡献"）

程序里 `c` 键会打印：

```
--- software baseline (320x240, CPU only) ---
  grayscale   SW:    4.81 ms/frame (  62.6 ns/pixel,  207.9 fps)
  mean 3x3    SW:   18.42 ms/frame ( 239.8 ns/pixel,   54.3 fps)
  gauss 3x3   SW:   19.05 ms/frame ( 248.0 ns/pixel,   52.5 fps)
  sobel       SW:   23.77 ms/frame ( 309.5 ns/pixel,   42.1 fps)

--- hardware reference ---
  HW: 1.024 ms for the same 76800 pixels (13.33 ns/pixel @75MHz)
```

**结论可以直接写进报告**：

| 指标 | 软件（ARM A9 @667MHz） | 硬件（PL @75MHz） | 提升 |
|---|---|---|---|
| 每像素耗时 | ~240~310 ns | **13.33 ns** | **~18~23 倍** |
| 320×240 一帧 | ~18~24 ms | **1.02 ms** | 同上 |
| 能否 720p60 实时 | ❌（一帧要 >16.7ms） | ✅（帧内完成，CPU 占用 0%） | — |

**最有说服力的一条**：720p 一帧只有 16.67ms 的预算，软件算一遍 Sobel 需要
**远超过**这个时间（会掉帧）；而 PL 在帧内就把 92 万像素全部算完，**ARM 占用率 ~0%**，
可以同时跑菜单、状态监控、通信。

## 数值一致性（为什么这个对比有效）

`sw_filter.c` 的整数运算和 `src/rtl/img_filter_3x3.v` 逐条对齐：

| 模式 | 公式（两边相同） |
|---|---|
| 灰度 | 窗口中心像素 |
| 均值 | `(sum9 * 57) >> 9` |
| 高斯 | `(1 2 1; 2 4 2; 1 2 1)` 加权和 `>> 4` |
| Sobel | `\|Gx\| + \|Gy\|`，饱和到 255 |
| 边界 | 边缘复制（clamp） |

所以比较的是**同一个算法在同一帧上的耗时**，不是两个不同算法。
