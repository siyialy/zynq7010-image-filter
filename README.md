# Real-Time Image Filtering Accelerator on ZYNQ-7010
# 基于 ZYNQ-7010 的软硬件协同实时图像滤波加速系统

[中文说明见下方](#中文说明) · [English below](#english)

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-ZYNQ--7010-blue)
![Tool](https://img.shields.io/badge/tool-Vivado%202018.3-orange)

A soft-hardware co-designed **real-time 3×3 image filtering accelerator** running on a
low-cost ZYNQ-7010 board. The PL fabric streams a 1280×720@60 video pipeline and applies
grayscale / mean / Gaussian / Sobel filtering at **one pixel per clock**, while the ARM core
controls the mode through AXI4-Lite registers and measures the hardware frame rate.

| Item | Value |
|---|---|
| Resolution / field rate | 1280×720, 60.6 Hz (720p60 class) |
| Pixel throughput | **1 pixel / clock @ 75 MHz = 13.33 ns/pixel** |
| Full-frame processing | **12.29 ms** (< 16.50 ms frame period) |
| CPU load while filtering | **≈ 0 %** |
| Speed-up vs. optimized C on Cortex-A9 | **≈ 13×** (166–178 ns/pixel → 13.33 ns/pixel) |
| PL utilization | LUT 8.7 %, FF 3.2 %, BRAM 54 % |
| Timing | **WNS +3.447 ns**, no violations |

---

## English

### What it does

```
image source (test pattern | 320×240 photo ROM)
        │
        ▼
video_timing_gen ─► source mux ─► 3×3 convolution pipeline ─► TMDS encoder ─► HDMI
  1280×720@60          (KEY1)      gray / mean / gauss / sobel      OSERDES 10:1
        ▲                                      ▲
        │                                      │ mode[2:0]
        └────────── frame counter ◄──── AXI4-Lite regs (axil_regs)
                                              ▲
                                     ARM Cortex-A9 (PS)
                                        UART console
```

- **PL side** – a fully pipelined video path: timing generator → image source → 3×3 convolution
  (two line buffers, 9 taps, four parallel adder trees, multiply/shift/abs stage) → 4-to-1 mode
  selector → TMDS serialiser. Throughput is one pixel per clock and independent of image content;
  the pipeline latency is fixed at 12 clocks (160 ns).
- **PS side** – a bare-metal C application that writes the filter mode through a self-designed
  AXI4-Lite slave, reads back a 32-bit frame counter to measure real frame rate, and runs an
  bit-exact software baseline for the speed-up comparison.
- **Cross-clock domain** – configuration bits use two-flop synchronisers (`ASYNC_REG`), the
  reverse-direction frame counter uses toggle + pulse synchronisation and local counting.

### Repository layout

```
├── README.md              this file
├── LICENSE                MIT
├── NOTICE                 third-party code attribution
├── docs/                  step-by-step tutorials (Chinese) + hardware notes
├── src/rtl/               Verilog RTL (13 modules) + image ROM init file
├── src/sim/               8 self-checking testbenches
├── constr/                XDC pin & timing constraints
├── build/                 reproducible Tcl scripts (simulation / build / program)
├── ps_app/                ARM application (C) + software baseline
├── tools/                 image→ROM converter, one-click helper scripts
├── board/                 prebuilt bitstream / HDF / ELF
└── report/                competition report (docx) + generated figures
```

### Build from source

Requirements: **Vivado / SDK 2018.3** (other versions may work), a ZYNQ-7010 board,
12 V supply, JTAG downloader, HDMI monitor.

> ⚠️ **All tool paths must be ASCII-only.** Vivado fails in subtle ways (synthesis crash,
> `$readmemh` not found, truncated file paths in the Program Device dialog) when the project
> path contains non-ASCII characters.

```powershell
# 1) full system build (BD + synthesis + implementation + bitstream + HDF)
vivado -mode batch -source build\build_system.tcl

# 2) build the ARM application (BSP + app)
xsct build\build_app.tcl

# 3) download bitstream + ELF and run
xsct build\run_app.tcl

# optional: run the self-checking simulations
vivado -mode batch -source build\sim_img_filter.tcl -tclargs D:/fpga_build/sim1
vivado -mode batch -source build\sim_axil_regs.tcl -tclargs D:/fpga_build/sim2
```

### Design highlights

1. **One data path, four operators.** Grayscale, mean, Gaussian and Sobel share the same line
   buffers and tap registers; they diverge only in the adder tree and the final
   multiply/shift/abs stage, then merge through a 4-to-1 selector. Mode switching is instant
   and never stalls the pixel stream.
2. **Handshake-correct AXI4-Lite slave.** Address and data are latched independently, so writes
   are never lost when `AWVALID` and `WVALID` arrive in different cycles — the behaviour real
   Zynq masters exhibit (see `docs/17_board_debug_log.md` for the bug this fixed).
3. **Explicit CDC and constraints.** `set_clock_groups -asynchronous` plus `set_max_delay
   -datapath_only` prevent spurious timing violations on synchroniser paths (−0.29 ns → clean).
4. **Reproducible.** Everything (block design, IP, bitstream, application) is generated by Tcl
   scripts from source; no `.xpr` files are needed.

### Results

| Mode | Software (-O2, 320×240) | Hardware | Speed-up |
|---|---|---|---|
| grayscale | 166 ns/pixel | 13.33 ns/pixel | 12.5× |
| mean 3×3 | 177 ns/pixel | 13.33 ns/pixel | 13.3× |
| gaussian 3×3 | 174 ns/pixel | 13.33 ns/pixel | 13.1× |
| sobel | 178 ns/pixel | 13.33 ns/pixel | 13.4× |

The more meaningful result: the PL finishes a **full 1280×720 frame in 12.29 ms** (60 fps with
margin), while the same Sobel in optimized C would need **153 ms per frame** — 9.3× short of
real time. Measured with a hardware frame counter across the clock domain boundary; see
`docs/19_metrics.md` for the raw serial output.

### License

Code and documentation: **MIT** (see `LICENSE`).
TMDS/DVI serialiser modules are adapted from the ALIENTEK reference design — see `NOTICE`.

---

## 中文说明

本项目在一块低成本的 **ZYNQ-7010** 开发板上，实现了**软硬件协同的实时 3×3 图像滤波加速系统**：
PL 内部自行产生 1280×720@60 视频时序，并将灰度 / 均值 / 高斯 / Sobel 四种 3×3 卷积算子
做到**每时钟处理一个像素**；PS（ARM）通过 AXI4-Lite 寄存器下发滤波模式、读取帧计数器实测帧率，
并在同一帧上运行与硬件数值完全一致的 C 语言软件基线，用于量化加速比。

### 核心指标（板上实测）

| 项目 | 数值 |
|---|---|
| 输出分辨率 / 场频 | 1280×720，60.6 Hz（720p60 级别） |
| 单像素耗时 | **13.33 ns**（75 MHz，每拍 1 像素） |
| 整帧处理时间 | **12.29 ms**（帧周期 16.50 ms，余量 4.21 ms） |
| 滤波期间 CPU 占用 | **≈ 0 %** |
| 加速比 | **约 13 倍**（软件 166~178 ns/像素 vs 硬件 13.33 ns/像素） |
| PL 资源占用 | LUT 8.7 % / FF 3.2 % / BRAM 54 % |
| 时序 | **WNS +3.447 ns**，无违例 |

### 四种滤波模式

| 模式 | 算法 | 效果 |
|---|---|---|
| 0 灰度 | `Y = (77R + 150G + 29B) >> 8`（BT.601） | 彩色变灰 |
| 1 均值 3×3 | `Σ9 × 57 >> 9`（≈ ÷9，纯移位加法实现） | 轻微模糊 |
| 2 高斯 3×3 | 核 `[1 2 1; 2 4 2; 1 2 1] >> 4` | 自然模糊 |
| 3 Sobel | `|Gx| + |Gy|`，限幅 255 | 黑底白轮廓 |

### 目录说明

| 目录 | 内容 |
|---|---|
| `docs/` | 从零开始的教程（环境、仿真、上板、PS 端、调试实录、指标） |
| `src/rtl/` | Verilog 源码（视频时序、滤波核、图像源、AXI 从机、跨时钟域、TMDS） |
| `src/sim/` | 8 个自检式 testbench（含综合后仿真） |
| `build/` | 可复现的 Tcl 脚本（仿真 / 构建 / 下载 / 一键换图） |
| `ps_app/` | ARM 端 C 程序 + 软件基线 |
| `tools/` | 图片转 ROM 工具、串口终端、一键构建脚本 |
| `board/` | 预编译的 bitstream / HDF / ELF |
| `report/` | 作品报告（docx）+ 全部图表的生成脚本 |

### 复现步骤

需要 **Vivado / SDK 2018.3**、ZYNQ-7010 开发板、12V 电源、JTAG 下载器、HDMI 显示器。

> ⚠️ **所有工具路径必须是纯英文。** 中文路径会让 Vivado 出现"综合崩溃""`$readmemh` 找不到
> 文件""Program Device 路径被截断"等难以定位的问题。

```powershell
vivado -mode batch -source build\build_system.tcl    # 构建系统（BD+综合+实现+bit+HDF）
xsct build\build_app.tcl                             # 编译 ARM 程序
xsct build\run_app.tcl                               # 下载并运行
```

### 调试踩坑记录

`docs/17_board_debug_log.md` 里有 6 个真实 bug 的完整定位过程，其中三个最具代表性：

1. **均值模式全黑** —— `sum*57>>9` 被综合器做位宽优化，行为仿真通过、网表仿真失败；
2. **AXI 从机握手错误** —— 要求 `AWVALID`/`WVALID` 同拍到达，真机上导致 ARM 永久阻塞；
3. **串口无数据** —— 底板跳线接在 PL 侧而非 PS 侧，硬件问题伪装成软件问题。

### 许可证

代码与文档：**MIT**（见 `LICENSE`）。
TMDS/DVI 串行化模块改编自正点原子参考设计，来源与授权见 `NOTICE`。
